import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/bili_api.dart';
import '../core/models.dart';
import '../data/local_store.dart';
import 'download_permissions.dart';
import 'byte_progress.dart';
import 'muxer.dart';
import 'output_storage.dart';

class _Canceled implements Exception {}

class _Paused implements Exception {}

class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.api,
    required this.store,
    required this.workDirectory,
    MediaMuxer? muxer,
    FileDownloader? downloader,
    OutputStorage? outputStorage,
    bool? isAndroid,
    this.onError,
  }) : muxer = muxer ?? MediaMuxer(),
       downloader = downloader ?? FileDownloader(),
       outputStorage = outputStorage ?? OutputStorage(),
       isAndroid = isAndroid ?? Platform.isAndroid;
  final BiliApi api;
  final LocalStore store;
  final String workDirectory;
  final MediaMuxer muxer;
  final FileDownloader downloader;
  final OutputStorage outputStorage;
  final bool isAndroid;

  /// Optional observer for isolated verification; production never logs media
  /// URLs or account data from native exceptions.
  final void Function(Object error, StackTrace stack)? onError;
  final List<DownloadJob> jobs = [];
  final Set<String> _running = {};
  final Map<String, Transfer> _transfers = {};
  final Map<String, Completer<void>> _pauseSignals = {};
  final Map<String, Future<void>> _pausing = {};
  final Map<String, DateTime> _lastSaved = {};
  int concurrency = 2;
  bool _ready = false;
  Future<void>? _nativeRestoration;
  bool get hasActiveWorkers => _running.isNotEmpty;

  Future<void> initialize() async {
    jobs.addAll(store.loadJobs());
    concurrency =
        int.tryParse(store.setting('concurrency') ?? '')?.clamp(1, 4) ?? 2;
    downloader.configureNotification(
      running: const TaskNotification(
        'biload 正在下载',
        '{displayName} · {progress}',
      ),
      paused: const TaskNotification('下载已暂停', '{displayName}'),
      error: const TaskNotification('下载需要处理', '请打开 biload 查看任务'),
      progressBar: true,
      tapOpensFile: false,
    );
    if (isAndroid) {
      await downloader.configure(
        androidConfig: [(Config.runInForeground, Config.always)],
      );
    } else {
      final temporary = await Directory(
        p.join(p.dirname(workDirectory), 'transfers'),
      ).create(recursive: true);
      await downloader.configure(
        desktopConfig: [(Config.tempFilePath, temporary.path)],
      );
    }
    await downloader.start(
      autoCleanDatabase: true,
      doRescheduleKilledTasks: false,
    );
    final notificationsReady = await _prepareNativeTransfers();
    for (final job in jobs) {
      if ({
        JobStatus.queued,
        JobStatus.resolving,
        JobStatus.downloading,
        JobStatus.merging,
      }.contains(job.status)) {
        job.status = notificationsReady ? JobStatus.queued : JobStatus.paused;
        job.message = notificationsReady
            ? '等待恢复'
            : downloadNotificationPermissionMessage;
        store.saveJob(job);
      }
    }
    await cleanupFinishedCache();
    _ready = true;
    notifyListeners();
    _pump();
  }

  Future<void> _restoreNativeTransfers() async {
    try {
      await downloader.rescheduleKilledTasks();
    } catch (_) {
      _nativeRestoration = null;
      rethrow;
    }
  }

  Future<bool> _prepareNativeTransfers({bool requestIfNeeded = false}) async {
    if (isAndroid &&
        !await prepareDownloadNotifications(
          () => downloader.permissions.status(PermissionType.notifications),
          () => downloader.permissions.request(PermissionType.notifications),
          requestIfNeeded: requestIfNeeded,
        )) {
      return false;
    }
    // Do not let the plugin restore UIDT jobs before notifications are allowed.
    await (_nativeRestoration ??= _restoreNativeTransfers());
    return true;
  }

  Future<List<DownloadJob>> add({
    required MediaPage page,
    required List<VideoVariant> videos,
    required List<AudioVariant> audios,
    required String container,
    required String directory,
  }) async {
    if (videos.isEmpty && audios.isEmpty) {
      throw const BiliException('请至少选择一个视频或音频版本。');
    }
    if (videos.isNotEmpty &&
        container == 'mp4' &&
        audios.any((a) => a.id == 30251 || a.codecs.startsWith('fLaC'))) {
      throw const BiliException('无损音轨请使用 MKV，以保留音质并提高播放器兼容性。');
    }
    await outputStorage.prepare(directory);
    if (!await _prepareNativeTransfers(requestIfNeeded: true)) {
      throw const BiliException(downloadNotificationPermissionMessage);
    }
    final added = <DownloadJob>[];
    final selections = videos.isEmpty
        ? audios.map((a) => (null as VideoVariant?, [a]))
        : videos.map((v) => (v as VideoVariant?, audios));
    for (final (video, audio) in selections) {
      final duplicate = jobs.any(
        (j) =>
            !j.isFinished &&
            j.page.key == page.key &&
            j.videoKey == video?.key &&
            listEquals(j.audioKeys, audio.map((a) => a.key).toList()) &&
            j.container == container &&
            j.directory == directory,
      );
      if (duplicate) continue;
      final id =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(0xFFFFFF).toRadixString(36)}';
      final job = DownloadJob(
        id: id,
        page: page,
        videoKey: video?.key,
        audioKeys: audio.map((a) => a.key).toList(),
        container: container,
        directory: directory,
        createdAt: DateTime.now(),
      );
      jobs.insert(0, job);
      store.saveJob(job);
      added.add(job);
    }
    notifyListeners();
    _pump();
    return added;
  }

  void _save(DownloadJob job, {bool throttle = false}) {
    final now = DateTime.now();
    if (!throttle ||
        now.difference(_lastSaved[job.id] ?? DateTime(1970)).inMilliseconds >
            1000) {
      store.saveJob(job);
      _lastSaved[job.id] = now;
    }
    notifyListeners();
  }

  void _pump() {
    if (!_ready) return;
    for (final job in jobs.reversed.toList()) {
      if (_running.length >= concurrency) break;
      if (job.status != JobStatus.queued || _running.contains(job.id)) continue;
      _running.add(job.id);
      unawaited(
        _run(job).whenComplete(() async {
          _transfers.remove(job.id);
          _pauseSignals.remove(job.id);
          _lastSaved.remove(job.id);
          if (job.status == JobStatus.canceled) await _cleanupWorkFiles(job);
          _running.remove(job.id);
          _pump();
        }),
      );
    }
  }

  void _guard(DownloadJob job) {
    if (job.status == JobStatus.canceled) throw _Canceled();
    if (job.status == JobStatus.paused) {
      throw _Paused();
    }
  }

  Future<void> _run(DownloadJob job) async {
    _pauseSignals[job.id] = Completer<void>();
    try {
      _guard(job);
      job.status = JobStatus.resolving;
      job.message = '正在更新下载地址';
      _save(job);
      var catalog = await api.catalog(job.page);
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await _perform(job, catalog, attempt);
          return;
        } on BiliException catch (e) {
          _guard(job);
          if (attempt == 1 || !{403, 404, 410}.contains(e.code)) rethrow;
          job.message = '地址已失效，正在重新解析';
          _save(job);
          catalog = await api.catalog(job.page);
        }
      }
    } on _Paused {
      job.bytesPerSecond = 0;
      _save(job);
    } on _Canceled {
      job.status = JobStatus.canceled;
      job.message = '已取消';
      _save(job);
    } catch (e, stack) {
      onError?.call(e, stack);
      if (job.status != JobStatus.canceled) {
        job.status = JobStatus.failed;
        job.message = e is BiliException
            ? e.message
            : e is FileSystemException
            ? '文件读写失败，请检查目录权限和剩余空间。'
            : '任务处理失败，临时文件已保留，可重试。';
        job.bytesPerSecond = 0;
        _save(job);
      }
    }
  }

  Future<void> _perform(
    DownloadJob job,
    StreamCatalog catalog,
    int attempt,
  ) async {
    VideoVariant? video;
    if (job.videoKey != null) {
      video = catalog.videos.where((v) => v.key == job.videoKey).firstOrNull;
      if (video == null) throw const BiliException('原选视频规格已不可用，请重新解析；没有自动降级。');
    }
    final audios = <AudioVariant>[];
    for (final key in job.audioKeys) {
      final matches = catalog.audios.where((a) => a.key == key);
      if (matches.isEmpty) throw const BiliException('原选音轨已不可用，请重新解析。');
      audios.add(matches.first);
    }
    final jobDir = p.join(workDirectory, job.id);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(job.id) ||
        !p.isWithin(p.absolute(workDirectory), p.absolute(jobDir))) {
      throw const BiliException('任务工作目录无效。');
    }
    await Directory(jobDir).create(recursive: true);
    final resources = <(String, StreamSource)>[
      if (video != null)
        for (var i = 0; i < video.sources.length; i++)
          ('${video.key}_$i', video.sources[i]),
      for (final audio in audios) (audio.key, audio.sources.single),
    ];
    job.message = '正在获取文件大小';
    job.totalBytes = 0;
    job.bytesPerSecond = 0;
    _save(job);
    final sizes = <int?>[];
    final cachedResources = <bool>[];
    for (var offset = 0; offset < resources.length; offset += 3) {
      _guard(job);
      final batch = await Future.wait(
        resources.skip(offset).take(3).map((r) async {
          final hash = _resourceHash(r.$1);
          final file = File(p.join(jobDir, '$hash.media'));
          final cachedSize = await _cachedSize('${job.id}_$hash', file);
          if (cachedSize != null) {
            return (size: cachedSize, cached: true);
          }
          return (size: await api.resourceSize(r.$2, job.page), cached: false);
        }),
      );
      sizes.addAll(batch.map((r) => r.size));
      cachedResources.addAll(batch.map((r) => r.cached));
    }
    final byteProgress = ByteProgress(sizes);
    for (var i = 0; i < cachedResources.length; i++) {
      if (cachedResources[i]) byteProgress.complete(i, sizes[i]!);
    }
    void saveBytes() {
      job.downloadedBytes = byteProgress.downloadedBytes;
      job.totalBytes = byteProgress.totalBytes ?? 0;
      job.progress = byteProgress.fraction ?? 0;
    }

    saveBytes();
    final files = <String>[];
    for (var i = 0; i < resources.length; i++) {
      _guard(job);
      job.status = JobStatus.downloading;
      job.message = '下载流 ${i + 1} / ${resources.length}';
      _save(job);
      files.add(
        await _resource(
          job,
          resources[i].$1,
          resources[i].$2,
          jobDir,
          i,
          byteProgress,
          attempt,
        ),
      );
      saveBytes();
      _save(job);
    }
    _guard(job);
    job.status = JobStatus.merging;
    job.progress = 1;
    job.bytesPerSecond = 0;
    job.message = '下载完成（100%），正在合并并检查文件';
    _save(job);
    final videoCount = video?.sources.length ?? 0;
    final inputs = <MuxInput>[];
    if (videoCount == 1) inputs.add(MuxInput(files.first));
    if (videoCount > 1) {
      final list = File(p.join(jobDir, 'segments.txt'));
      String quote(String path) =>
          path.replaceAll('\\', '/').replaceAll("'", "'\\''");
      await list.writeAsString(
        files.take(videoCount).map((f) => "file '${quote(f)}'").join('\n'),
      );
      inputs.add(MuxInput(list.path, concat: true));
    }
    final extension = video == null
        ? audios.single.id == 30251
              ? 'flac'
              : audios.single.codecs.startsWith('mp4a')
              ? 'm4a'
              : 'mka'
        : job.container;
    final temporary = p.join(jobDir, 'output.$extension');
    await muxer.mux(
      job: job,
      video: inputs,
      audio: files.skip(videoCount).toList(),
      audioInfo: audios,
      output: temporary,
      progressive: video?.progressive ?? false,
    );
    _guard(job);
    final suffix = video == null
        ? audios.single.qualityLabel
        : '${video.qualityLabel}_${video.codecLabel}';
    final stem = safeFilename(
      '${job.page.title}_P${job.page.index}_${job.page.part}',
    );
    final filename = '${stem}_${safeFilename(suffix)}_${job.id}.$extension';
    job.message = '下载完成（100%），正在保存文件';
    _save(job);
    final output = await outputStorage.publish(
      temporary,
      job.directory,
      filename,
    );
    try {
      _guard(job);
      job.output = output;
      job.status = JobStatus.complete;
      job.progress = 1;
      job.message = '下载完成';
      _save(job);
    } catch (_) {
      job.output = '';
      if (job.status == JobStatus.complete) job.status = JobStatus.merging;
      await outputStorage.delete(output);
      rethrow;
    }
    if (!await _cleanupWorkFiles(job)) {
      job.message = '下载完成，临时文件清理失败，可在设置中重新清理';
      _save(job);
    }
  }

  static String _resourceHash(String key) =>
      sha256.convert(utf8.encode(key)).toString().substring(0, 20);

  Future<int?> _cachedSize(String resourceId, File file) async {
    final saved = store.resource(resourceId);
    if (saved?['complete'] != true) return null;
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file &&
            stat.size > 0 &&
            stat.size == integer(saved?['length'])
        ? stat.size
        : null;
  }

  Future<String> _resource(
    DownloadJob job,
    String variantKey,
    StreamSource source,
    String directory,
    int index,
    ByteProgress byteProgress,
    int attempt,
  ) async {
    final hash = _resourceHash(variantKey);
    final resourceId = '${job.id}_$hash';
    final path = p.join(directory, '$hash.media');
    final cachedSize = await _cachedSize(resourceId, File(path));
    if (cachedSize != null) {
      byteProgress.complete(index, cachedSize);
      return path;
    }
    TaskStatusUpdate? last;
    for (var backup = 0; backup < source.urls.length; backup++) {
      _guard(job);
      if (!await _prepareNativeTransfers()) {
        throw const BiliException(downloadNotificationPermissionMessage);
      }
      final task = DownloadTask(
        taskId: '${resourceId}_${attempt}_$backup',
        url: source.urls[backup],
        filename: p.basename(path),
        directory: directory,
        baseDirectory: BaseDirectory.root,
        group: 'biload',
        allowPause: true,
        updates: Updates.statusAndProgress,
        retries: 2,
        requiresWiFi: false,
        headers: {
          'User-Agent': BiliApi.userAgent,
          'Referer': job.page.webUrl,
          'Accept-Encoding': 'identity',
        },
        metaData: job.id,
        displayName: job.page.part,
        transferHints: {TransferHint.userInitiated, TransferHint.largeFile},
      );
      final transfer = await downloader.transfers.getOrStart(task);
      _transfers[job.id] = transfer;
      void update() {
        if (job.status == JobStatus.canceled) return;
        if (transfer.statusNotifier.value == TaskStatus.paused &&
            job.status != JobStatus.paused) {
          job.status = JobStatus.paused;
          job.message = '下载已暂停';
          final signal = _pauseSignals[job.id];
          if (signal != null && !signal.isCompleted) signal.complete();
        }
        byteProgress.update(index, transfer.progressNotifier.value);
        job.progress = byteProgress.fraction ?? 0;
        job.downloadedBytes = byteProgress.downloadedBytes;
        job.totalBytes = byteProgress.totalBytes ?? 0;
        job.bytesPerSecond =
            max(0, transfer.networkSpeedNotifier.value) * 1000000;
        _save(job, throttle: true);
      }

      transfer.progressNotifier.addListener(update);
      transfer.statusNotifier.addListener(update);
      final progressEvents = transfer.progressUpdates.listen((event) {
        byteProgress.update(
          index,
          event.progress,
          expectedSize: event.expectedFileSize,
        );
        update();
      });
      try {
        _guard(job);
        if (transfer.statusNotifier.value == TaskStatus.paused) {
          await transfer.resume();
        }
        update();
        last = await Future.any<TaskStatusUpdate>([
          transfer.result,
          _pauseSignals[job.id]!.future.then<TaskStatusUpdate>((_) {
            if (job.status == JobStatus.canceled) throw _Canceled();
            throw _Paused();
          }),
        ]);
      } finally {
        transfer.progressNotifier.removeListener(update);
        transfer.statusNotifier.removeListener(update);
        await progressEvents.cancel();
        if (identical(_transfers[job.id], transfer)) _transfers.remove(job.id);
      }
      _guard(job);
      if (last.status == TaskStatus.complete) {
        final length = await File(path).length();
        if (length == 0 ||
            (source.size > 0 && length != source.size) ||
            (byteProgress.sizes[index] != null &&
                length != byteProgress.sizes[index])) {
          throw const BiliException('下载文件长度与源信息不一致，请重试。');
        }
        store.saveResource(resourceId, job.id, {
          'complete': true,
          'length': length,
          'path': path,
        });
        byteProgress.complete(index, length);
        return path;
      }
      if (last.status == TaskStatus.canceled) throw _Canceled();
    }
    final exception = last?.exception;
    final code =
        last?.responseStatusCode ??
        (exception is TaskHttpException ? exception.httpResponseCode : null);
    throw BiliException('视频流下载失败，可重试任务以更新地址。', code: code);
  }

  Future<void> pause(DownloadJob job) {
    final pending = _pausing[job.id];
    if (pending != null) return pending;
    final operation = _pause(job);
    _pausing[job.id] = operation;
    return operation.whenComplete(() => _pausing.remove(job.id));
  }

  Future<void> _pause(DownloadJob job) async {
    if (!{
      JobStatus.queued,
      JobStatus.resolving,
      JobStatus.downloading,
    }.contains(job.status)) {
      return;
    }
    final old = job.status;
    job.status = JobStatus.paused;
    final transfer = _transfers[job.id];
    if (transfer != null) {
      final acknowledged = Completer<void>();
      void inspectStatus() {
        final status = transfer.statusNotifier.value;
        if ((status == TaskStatus.paused || status.isFinalState) &&
            !acknowledged.isCompleted) {
          acknowledged.complete();
        }
      }

      transfer.statusNotifier.addListener(inspectStatus);
      try {
        if (!await transfer.pause()) {
          throw const BiliException('当前流暂时无法暂停，请稍后重试。');
        }
        inspectStatus();
        // Desktop pause() acknowledges the command before the worker has
        // written resume data. Resuming before its paused event loses the
        // resume request, especially on macOS.
        await acknowledged.future.timeout(const Duration(seconds: 20));
      } catch (_) {
        if (job.status == JobStatus.paused) job.status = old;
        rethrow;
      } finally {
        transfer.statusNotifier.removeListener(inspectStatus);
      }
    }
    if (job.isFinished) return;
    job.message = '已暂停';
    job.bytesPerSecond = 0;
    final signal = _pauseSignals[job.id];
    if (signal != null && !signal.isCompleted) signal.complete();
    _save(job);
  }

  Future<void> resume(DownloadJob job) async {
    await _pausing[job.id];
    if (job.status != JobStatus.paused && job.status != JobStatus.failed) {
      return;
    }
    if (!await _prepareNativeTransfers(requestIfNeeded: true)) {
      throw const BiliException(downloadNotificationPermissionMessage);
    }
    job.status = JobStatus.queued;
    job.message = '等待继续';
    _save(job);
    _pump();
  }

  Future<void> cancel(DownloadJob job) async {
    if (job.isFinished) return;
    job.status = JobStatus.canceled;
    job.message = '已取消';
    _save(job);
    final signal = _pauseSignals[job.id];
    if (signal != null && !signal.isCompleted) signal.complete();
    await _transfers[job.id]?.cancel();
    await muxer.cancel(job.id);
  }

  Future<void> remove(DownloadJob job) async {
    if (!job.isFinished || _running.contains(job.id)) return;
    if (!await _cleanupWorkFiles(job)) {
      throw const BiliException('临时文件清理失败，记录已保留，请检查文件权限后重试。');
    }
    jobs.remove(job);
    store.removeJob(job.id);
    notifyListeners();
  }

  Future<bool> _cleanupWorkFiles(DownloadJob job) =>
      _cleanupWorkDirectory(job.id);

  Future<bool> _cleanupWorkDirectory(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) return false;
    final directory = Directory(p.join(workDirectory, id));
    try {
      if (!await directory.exists()) return true;
      final root = await Directory(workDirectory).resolveSymbolicLinks();
      final target = await directory.resolveSymbolicLinks();
      if (!p.isWithin(root, target)) return false;
      await directory.delete(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<int> cleanupFinishedCache({
    bool includeFailed = false,
    bool strict = false,
  }) async {
    var cleaned = 0;
    var failed = false;
    for (final job in jobs.toList()) {
      if (_running.contains(job.id)) continue;
      if ({
        JobStatus.complete,
        JobStatus.canceled,
        if (includeFailed) JobStatus.failed,
      }.contains(job.status)) {
        if (await _cleanupWorkFiles(job)) {
          cleaned++;
        } else {
          failed = true;
        }
      }
    }
    try {
      final root = Directory(workDirectory);
      if (await root.exists()) {
        await for (final entry in root.list(followLinks: false)) {
          final id = p.basename(entry.path);
          if (entry is! Directory ||
              jobs.any((j) => j.id == id) ||
              _running.contains(id)) {
            continue;
          }
          if (await _cleanupWorkDirectory(id)) {
            cleaned++;
          } else {
            failed = true;
          }
        }
      }
    } on FileSystemException {
      failed = true;
    }
    if (strict && failed) {
      throw const BiliException('部分临时文件尚未清理，请检查目录权限。');
    }
    return cleaned;
  }

  void configure({required int concurrent}) {
    concurrency = concurrent.clamp(1, 4);
    store.setSetting('concurrency', '$concurrency');
    notifyListeners();
    _pump();
  }
}
