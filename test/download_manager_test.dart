import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
// The package's public permissions getter returns this unexported interface.
// ignore: implementation_imports
import 'package:background_downloader/src/permissions.dart' show Permissions;
import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';
import 'package:biload/data/local_store.dart';
import 'package:biload/services/download_manager.dart';
import 'package:biload/services/download_permissions.dart';
import 'package:biload/services/muxer.dart';
import 'package:biload/services/output_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

class CatalogApi extends BiliApi {
  int calls = 0;
  bool missing = false;
  int? videoSize = 32;
  int? audioSize = 32;
  @override
  Future<int?> resourceSize(StreamSource source, MediaPage page) async =>
      source.urls.first.contains('audio') ? audioSize : videoSize;
  @override
  Future<StreamCatalog> catalog(MediaPage page) async {
    calls++;
    return missing
        ? const StreamCatalog(videos: [], audios: [])
        : BiliApi.parseStreams(sampleStreams());
  }
}

class FakeMuxer extends MediaMuxer {
  int calls = 0;
  int audioTracks = 0;
  @override
  Future<void> mux({
    required DownloadJob job,
    required List<MuxInput> video,
    required List<String> audio,
    required List<AudioVariant> audioInfo,
    required String output,
    required bool progressive,
  }) async {
    calls++;
    audioTracks = audio.length;
    for (final input in [...video.map((v) => v.path), ...audio]) {
      expect(await File(input).length(), 32);
    }
    await File(output).writeAsBytes(List.filled(64, 1));
  }
}

class TestPublicStorage extends OutputStorage {
  TestPublicStorage(this.root) : super(isAndroid: true);
  final Directory root;
  final files = <String, File>{};
  List<LegacyOutput> discovered = [];
  @override
  Future<List<LegacyOutput>> legacyOutputs() async => discovered;
  bool failPublish = false;
  bool failSourceCleanup = false;
  void Function()? beforeSourceCleanup;
  Future<void> Function()? afterPublication;
  @override
  Future<void> prepare(String directory) async {
    expect(directory, OutputStorage.androidDownloads);
    await root.create(recursive: true);
  }

  @override
  Future<String> publish(String source, String directory, String name) async {
    if (failPublish) throw const BiliException('Public destination is full');
    final uri =
        'content://media/external_primary/downloads/${files.length + 1}';
    files[uri] = await File(source).copy(p.join(root.path, name));
    await afterPublication?.call();
    return uri;
  }

  @override
  Future<bool> exists(String output) =>
      (files[output] ?? File(output)).exists();
  @override
  Future<void> delete(String output) async {
    final file = files[output];
    if (file != null && await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteLegacySource(String source) async {
    beforeSourceCleanup?.call();
    if (failSourceCleanup) throw const BiliException('Cleanup failed');
    if (await File(source).exists()) await File(source).delete();
  }
}

class TestTransfer extends Fake implements Transfer {
  TestTransfer(this.task);
  @override
  final Task task;
  final completed = Completer<TaskStatusUpdate>();
  final events = StreamController<TaskProgressUpdate>.broadcast();
  @override
  Stream<TaskProgressUpdate> get progressUpdates => events.stream;
  void emitProgress(double progress, {int expectedSize = -1}) {
    progressNotifier.value = progress;
    events.add(TaskProgressUpdate(task, progress, expectedSize));
  }

  @override
  final progressNotifier = ValueNotifier<double?>(0.0);
  @override
  final statusNotifier = ValueNotifier<TaskStatus>(TaskStatus.running);
  @override
  final networkSpeedNotifier = ValueNotifier<double>(1);
  @override
  Future<TaskStatusUpdate> get result => completed.future;
  @override
  Future<bool> pause() async {
    statusNotifier.value = TaskStatus.paused;
    return true;
  }

  @override
  Future<bool> resume() async {
    statusNotifier.value = TaskStatus.running;
    return true;
  }

  @override
  Future<bool> cancel() async {
    if (!completed.isCompleted) {
      completed.complete(TaskStatusUpdate(task, TaskStatus.canceled));
    }
    statusNotifier.value = TaskStatus.canceled;
    return true;
  }

  Future<void> finish({int? error, int length = 32}) async {
    if (completed.isCompleted) return;
    if (error == null) {
      final file = File(p.join(task.directory, task.filename));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List.filled(length, 7));
    }
    final state = error == null ? TaskStatus.complete : TaskStatus.failed;
    statusNotifier.value = state;
    completed.complete(TaskStatusUpdate(task, state, null, null, null, error));
  }
}

class TestTransfers extends Fake implements Transfers {
  final Map<String, TestTransfer> handles = {};
  bool automatic = false;
  bool failOldAddress = false;
  @override
  Future<Transfer> getOrStart(
    Task task, {
    bool Function(Task existingTask)? matchBy,
    bool reEnqueueIfFailed = true,
  }) async {
    final transfer = handles.putIfAbsent(task.taskId, () => TestTransfer(task));
    if (automatic && !transfer.completed.isCompleted) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 5),
          () => transfer.finish(
            error: failOldAddress && task.taskId.contains('_0_') ? 403 : null,
          ),
        ),
      );
    }
    return transfer;
  }
}

class TestPermissions extends Fake implements Permissions {
  PermissionStatus current = PermissionStatus.granted;
  PermissionStatus requested = PermissionStatus.granted;
  int requests = 0;
  @override
  Future<PermissionStatus> status(PermissionType permissionType) async =>
      current;
  @override
  Future<PermissionStatus> request(PermissionType permissionType) async {
    requests++;
    return current = requested;
  }
}

class TestDownloader extends Fake implements FileDownloader {
  @override
  final TestTransfers transfers = TestTransfers();
  @override
  final TestPermissions permissions = TestPermissions();
  bool? autoRestoration;
  int restorations = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #configureNotification) return this;
    if (invocation.memberName == #start) {
      autoRestoration =
          invocation.namedArguments[#doRescheduleKilledTasks] as bool?;
      return Future<void>.value();
    }
    if (invocation.memberName == #configure) {
      return Future<List<(String, String)>>.value([]);
    }
    if (invocation.memberName == #rescheduleKilledTasks) {
      restorations++;
      return Future<(List<Task>, List<Task>)>.value((<Task>[], <Task>[]));
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 500; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for download state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStore store;
  late TestDownloader downloader;
  late CatalogApi api;
  late FakeMuxer muxer;
  late DownloadManager manager;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('biload-download-test-');
    store = LocalStore(':memory:');
    downloader = TestDownloader();
    api = CatalogApi();
    muxer = FakeMuxer();
    manager = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(root.path, 'work'),
      downloader: downloader,
      muxer: muxer,
    );
    await manager.initialize();
  });
  tearDown(() async {
    for (final job in manager.jobs.toList()) {
      if (!job.isFinished) await manager.cancel(job);
    }
    await until(() => !manager.hasActiveWorkers);
    manager.dispose();
    store.close();
    await root.delete(recursive: true);
  });
  Future<List<DownloadJob>> add({int videos = 1}) => manager.add(
    page: samplePage,
    videos: BiliApi.parseStreams(sampleStreams()).videos.take(videos).toList(),
    audios: BiliApi.parseStreams(sampleStreams()).audios.take(1).toList(),
    container: 'mkv',
    directory: p.join(root.path, 'output'),
  );

  Future<void> useAndroid() async {
    manager.dispose();
    manager = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(root.path, 'work'),
      downloader: downloader,
      muxer: muxer,
      isAndroid: true,
    );
    await manager.initialize();
  }

  Future<TestPublicStorage> usePublicStorage() async {
    manager.dispose();
    final storage = TestPublicStorage(Directory(p.join(root.path, 'public')));
    manager = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(root.path, 'work'),
      downloader: downloader,
      muxer: muxer,
      isAndroid: true,
      outputStorage: storage,
    );
    await manager.initialize();
    return storage;
  }

  Future<DownloadJob> addPublic() async => (await manager.add(
    page: samplePage,
    videos: BiliApi.parseStreams(sampleStreams()).videos.take(1).toList(),
    audios: BiliApi.parseStreams(sampleStreams()).audios.take(1).toList(),
    container: 'mkv',
    directory: OutputStorage.androidDownloads,
  )).single;

  test(
    'old Wi-Fi-only preference never restricts newly scheduled transfers',
    () async {
      store.setSetting('wifiOnly', 'true');
      await useAndroid();
      await add();
      await until(() => downloader.transfers.handles.isNotEmpty);
      expect(
        downloader.transfers.handles.values.every((h) => !h.task.requiresWiFi),
        isTrue,
      );
    },
  );

  test(
    'orphaned task cache is cleared while paused task data is preserved',
    () async {
      final paused = DownloadJob(
        id: 'paused-task',
        page: samplePage,
        videoKey: 'v',
        audioKeys: ['a'],
        container: 'mkv',
        directory: root.path,
        createdAt: DateTime.now(),
        status: JobStatus.paused,
      );
      manager.jobs.add(paused);
      final orphan = Directory(p.join(root.path, 'work', 'removed-task'));
      final retained = Directory(p.join(root.path, 'work', paused.id));
      await orphan.create(recursive: true);
      await retained.create(recursive: true);
      await File(p.join(orphan.path, 'video.media')).writeAsBytes([1, 2, 3]);
      await File(p.join(retained.path, 'video.media')).writeAsBytes([1, 2, 3]);
      await manager.cleanupFinishedCache(strict: true);
      expect(await orphan.exists(), isFalse);
      expect(await retained.exists(), isTrue);
    },
  );

  test('failed task cache is retained automatically and removed only on explicit cleanup', () async {
    final job = DownloadJob(
      id: 'failed-task',
      page: samplePage,
      videoKey: 'v',
      audioKeys: ['a'],
      container: 'mkv',
      directory: root.path,
      createdAt: DateTime.now(),
      status: JobStatus.failed,
    );
    manager.jobs.add(job);
    store.saveJob(job);
    final cache = Directory(p.join(root.path, 'work', job.id));
    await cache.create(recursive: true);
    await File(p.join(cache.path, 'video.media')).writeAsBytes([1, 2, 3]);
    await manager.cleanupFinishedCache();
    expect(await cache.exists(), isTrue);
    await manager.cleanupFinishedCache(includeFailed: true, strict: true);
    expect(await cache.exists(), isFalse);
    expect(store.loadJobs().single.status, JobStatus.failed);
  });

  test('untracked legacy files are adopted before migration', () async {
    final storage = await usePublicStorage();
    final source = File(p.join(root.path, 'untracked.mp4'));
    await source.writeAsBytes(List.filled(64, 1));
    storage.discovered = [
      (path: source.path, name: 'untracked.mp4', bytes: 64, modified: 1),
    ];
    manager.dispose();
    manager = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(root.path, 'work'),
      downloader: downloader,
      muxer: muxer,
      isAndroid: true,
      outputStorage: storage,
    );
    await manager.initialize();
    expect(manager.legacyOutputCount, 1);
    expect(manager.jobs.single.output, source.path);
    expect(
      await manager.migrateLegacyOutputs(OutputStorage.androidDownloads),
      1,
    );
    expect(await source.exists(), isFalse);
    expect(await storage.exists(manager.jobs.single.output), isTrue);
  });

  test('large video and small audio use combined bytes for progress and remaining size', () async {
    api.videoSize = 900;
    api.audioSize = 100;
    final job = (await add()).single;
    await until(() => downloader.transfers.handles.length == 1);
    final video = downloader.transfers.handles.values.first;
    video.emitProgress(0.5, expectedSize: 900);
    await until(() => job.downloadedBytes == 450);
    expect(job.totalBytes, 1000);
    expect(job.progress, 0.45);
    expect(job.remainingBytes, 550);
    await video.finish(length: 900);
    await until(() => downloader.transfers.handles.length == 2);
    expect(job.progress, 0.9);
    downloader.transfers.handles.values.last.emitProgress(
      0.5,
      expectedSize: 100,
    );
    await until(() => job.downloadedBytes == 950);
    expect(job.progress, 0.95);
    expect(job.remainingBytes, 50);
  });

  test('public publication failure preserves retryable sources, then leaves one final file', () async {
    final storage = await usePublicStorage();
    downloader.transfers.automatic = true;
    storage.failPublish = true;
    final job = await addPublic();
    await until(() => !manager.hasActiveWorkers);
    expect(job.status, JobStatus.failed);
    expect(job.output, isEmpty);
    expect(await Directory(p.join(root.path, 'work', job.id)).exists(), isTrue);
    expect(storage.files, isEmpty);
    storage.failPublish = false;
    await manager.resume(job);
    await until(() => !manager.hasActiveWorkers);
    expect(job.status, JobStatus.complete);
    expect(job.output, startsWith('content://media/'));
    expect(await storage.exists(job.output), isTrue);
    expect(
      downloader.transfers.handles.length,
      2,
      reason: 'Completed streams are reused',
    );
    expect(
      await Directory(p.join(root.path, 'work', job.id)).exists(),
      isFalse,
    );
    expect(await storage.root.list().length, 1);
    expect(store.loadJobs().single.output, job.output);
  });

  test('cancellation after publication rolls back the public file and clears task cache', () async {
    final storage = await usePublicStorage();
    downloader.transfers.automatic = true;
    storage.afterPublication = () => manager.cancel(manager.jobs.single);
    final job = await addPublic();
    await until(() => !manager.hasActiveWorkers);
    expect(job.status, JobStatus.canceled);
    expect(job.output, isEmpty);
    expect(await storage.root.list().length, 0);
    expect(
      await Directory(p.join(root.path, 'work', job.id)).exists(),
      isFalse,
    );
  });

  test('legacy migration commits the destination before deletion and retries retained cleanup', () async {
    final storage = await usePublicStorage();
    final source = File(p.join(root.path, 'legacy-video.mp4'));
    await source.writeAsBytes(List.filled(100, 42));
    final job = DownloadJob(
      id: 'legacy-task',
      page: samplePage,
      videoKey: 'video',
      audioKeys: ['audio'],
      container: 'mp4',
      directory: root.path,
      createdAt: DateTime.now(),
      status: JobStatus.complete,
      output: source.path,
    );
    manager.jobs.add(job);
    store.saveJob(job);
    storage.failPublish = true;
    await expectLater(
      manager.migrateLegacyOutputs(OutputStorage.androidDownloads),
      throwsA(isA<BiliException>()),
    );
    expect(await source.exists(), isTrue);
    expect(store.loadJobs().single.output, source.path);
    storage.failPublish = false;
    storage.failSourceCleanup = true;
    storage.beforeSourceCleanup = () {
      final saved = store.loadJobs().single;
      expect(saved.output, startsWith('content://media/'));
      expect(saved.retainedSource, source.path);
    };
    expect(
      await manager.migrateLegacyOutputs(OutputStorage.androidDownloads),
      1,
    );
    expect(await source.exists(), isTrue);
    expect(job.retainedSource, source.path);
    expect(manager.legacyOutputCount, 1);
    storage.failSourceCleanup = false;
    await manager.cleanupFinishedCache();
    expect(await source.exists(), isFalse);
    expect(await storage.exists(job.output), isTrue);
    expect(store.loadJobs().single.retainedSource, isEmpty);
    expect(manager.legacyOutputCount, 0);
  });

  test('multiple selected audio tracks merge into one video output without sidecar audio', () async {
    downloader.transfers.automatic = true;
    final catalog = BiliApi.parseStreams(sampleStreams());
    final jobs = await manager.add(
      page: samplePage,
      videos: catalog.videos.take(1).toList(),
      audios: catalog.audios.take(2).toList(),
      container: 'mkv',
      directory: p.join(root.path, 'output'),
    );
    await until(() => !manager.hasActiveWorkers);
    expect(jobs.length, 1);
    expect(jobs.single.status, JobStatus.complete);
    expect(muxer.audioTracks, 2);
    expect(await Directory(p.join(root.path, 'output')).list().length, 1);
    expect(
      await Directory(p.join(root.path, 'work', jobs.single.id)).exists(),
      isFalse,
    );
  });

  test('fresh denied Android notification permission is requested before scheduling', () async {
    downloader.permissions.current = PermissionStatus.denied;
    await useAndroid();
    final restoresBeforeAdd = downloader.restorations;
    final job = (await add()).single;
    await until(() => downloader.transfers.handles.isNotEmpty);
    expect(downloader.permissions.requests, 1);
    expect(downloader.restorations, restoresBeforeAdd + 1);
    expect(job.status, JobStatus.downloading);
  });

  test('denying notifications creates no task or native transfer', () async {
    downloader.permissions.current = PermissionStatus.denied;
    downloader.permissions.requested = PermissionStatus.denied;
    await useAndroid();
    final restoresBeforeAdd = downloader.restorations;
    await expectLater(add(), throwsA(isA<BiliException>()));
    expect(manager.jobs, isEmpty);
    expect(downloader.transfers.handles, isEmpty);
    expect(downloader.restorations, restoresBeforeAdd);
  });

  test('revoking notifications prevents scheduling the next stream', () async {
    await useAndroid();
    final job = (await add()).single;
    await until(() => downloader.transfers.handles.length == 1);
    downloader.permissions.current = PermissionStatus.denied;
    await downloader.transfers.handles.values.single.finish();
    await until(() => job.isFinished);
    expect(job.status, JobStatus.failed);
    expect(job.message, downloadNotificationPermissionMessage);
    expect(downloader.transfers.handles.length, 1);
  });

  test(
    'restart pauses persisted jobs until notification permission is available',
    () async {
      store.saveJob(
        DownloadJob(
          id: 'saved-job',
          page: samplePage,
          videoKey: BiliApi.parseStreams(sampleStreams()).videos.first.key,
          audioKeys: [],
          container: 'mp4',
          directory: p.join(root.path, 'output'),
          createdAt: DateTime.now(),
        ),
      );
      downloader.permissions.current = PermissionStatus.denied;
      await useAndroid();
      expect(manager.jobs.single.status, JobStatus.paused);
      expect(
        manager.jobs.single.message,
        downloadNotificationPermissionMessage,
      );
      expect(downloader.transfers.handles, isEmpty);
      expect(downloader.autoRestoration, isFalse);
      expect(downloader.permissions.requests, 0);
      await manager.resume(manager.jobs.single);
      await until(() => downloader.transfers.handles.isNotEmpty);
      expect(downloader.permissions.requests, 1);
    },
  );

  test(
    'completed streams produce a checked final output and persisted state',
    () async {
      downloader.transfers.automatic = true;
      final job = (await add()).single;
      await until(() => job.isFinished);
      expect(job.status, JobStatus.complete, reason: job.message);
      expect(await File(job.output).length(), 64);
      expect(store.loadJobs().single.status, JobStatus.complete);
      expect(muxer.calls, 1);
      await until(() => !manager.hasActiveWorkers);
      expect(downloader.transfers.handles.length, 2);
      expect(await Directory(p.join(root.path, 'output')).list().length, 1);
      expect(
        await Directory(p.join(root.path, 'work', job.id)).exists(),
        isFalse,
      );
      expect(
        downloader.transfers.handles.values.every(
          (h) => !h.task.headers.containsKey('Cookie'),
        ),
        isTrue,
      );
    },
  );

  test('pausing releases a queue slot and resume attaches to the same native transfer', () async {
    manager.configure(concurrent: 1);
    final jobs = await add(videos: 2);
    await until(() => downloader.transfers.handles.length == 1);
    final firstHandle = downloader.transfers.handles.values.first;
    await manager.pause(jobs.first);
    await until(() => downloader.transfers.handles.length == 2);
    expect(jobs.first.status, JobStatus.paused);
    expect(jobs.last.status, JobStatus.downloading);
    await manager.cancel(jobs.last);
    await until(() => !manager.hasActiveWorkers);
    await manager.resume(jobs.first);
    await until(() => firstHandle.statusNotifier.value == TaskStatus.running);
    expect(downloader.transfers.handles.values.first, same(firstHandle));
    await firstHandle.finish();
    await until(() => downloader.transfers.handles.length == 3);
    await downloader.transfers.handles.values.last.finish();
    await until(() => jobs.first.isFinished);
    expect(jobs.first.status, JobStatus.complete, reason: jobs.first.message);
  });

  test('expired CDN addresses refresh the catalog once without choosing a lower version', () async {
    downloader.transfers.automatic = true;
    downloader.transfers.failOldAddress = true;
    final job = (await add()).single;
    await until(() => job.isFinished);
    expect(job.status, JobStatus.complete, reason: job.message);
    expect(api.calls, 2);
  });

  test(
    'missing original representation fails instead of silently downgrading',
    () async {
      api.missing = true;
      final job = (await add()).single;
      await until(() => job.isFinished);
      expect(job.status, JobStatus.failed);
      expect(job.message, contains('没有自动降级'));
      expect(downloader.transfers.handles, isEmpty);
    },
  );
}
