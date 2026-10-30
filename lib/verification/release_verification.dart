import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:background_downloader/background_downloader.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../app_version.dart';
import '../core/bili_api.dart';
import '../core/models.dart';
import '../data/local_store.dart';
import '../data/app_paths.dart';
import '../data/transfer_store.dart';
import '../services/auth_controller.dart';
import '../services/browser_cookies.dart';
import '../services/download_manager.dart';
import '../services/file_session_vault.dart';
import '../services/media_probe.dart';
import '../ui/app.dart';

/// Opt-in verification of the packaged desktop executable, with synthetic media
/// and separate databases, outputs, and credentials. Never restores a user login.
void runReleaseVerification() {
  runApp(const MaterialApp(home: Scaffold(body: Text('biload 验证中'))));
  unawaited(_verify());
}

Future<void> _until(bool Function() condition, String operation) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out: $operation');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class _FixtureApi extends BiliApi {
  _FixtureApi(this.base, this.sizes);
  final Uri base;
  final Map<String, dynamic> sizes;
  bool slow = false;
  static const page = MediaPage(
    ref: ContentRef(ContentKind.video, 'BV19pnt6XE6d'),
    cid: 1,
    aid: 1,
    bvid: 'BV19pnt6XE6d',
    title: 'biload 中文 # 100% 验证',
    part: '原创测试素材',
    index: 1,
    duration: 2,
  );
  StreamSource source(String file) =>
      StreamSource([base.resolve(file).toString()], size: sizes[file] as int);
  @override
  Future<MediaContent> content(ContentRef ref) async => const MediaContent(
    title: 'biload 中文 # 100% 验证',
    author: '烨染霜华',
    cover: '',
    pages: [page],
  );
  @override
  Future<StreamCatalog> catalog(MediaPage page) async => StreamCatalog(
    videos: [
      for (final (codec, name, file) in [
        (7, 'avc1', slow ? 'slow.mp4' : 'avc.mp4'),
        (12, 'hev1', 'hevc.mp4'),
        (13, 'av01', 'av1.mp4'),
      ])
        VideoVariant(
          quality: 80,
          codec: codec,
          codecs: name,
          bandwidth: 100000,
          width: 128,
          height: 72,
          frameRate: '8',
          sources: [source(file)],
        ),
    ],
    audios: [
      for (final (id, codec, file) in [
        (30280, 'mp4a.40.2', 'aac.m4a'),
        (30251, 'fLaC', 'hires.flac'),
        (30250, 'ec-3', 'dolby.eac3'),
      ])
        AudioVariant(
          id: id,
          codecs: codec,
          bandwidth: 128000,
          sources: [source(file)],
        ),
    ],
  );
}

Future<void> _verify() async {
  final report = <String, dynamic>{
      'version': '$appVersion+$releaseBuildNumber',
    'platform': Platform.operatingSystem,
    'started': DateTime.now().toUtc().toIso8601String(),
    'checks': <String>[],
  };
  final checks = report['checks'] as List<String>;
  Directory? root;
  try {
    final id = Platform.environment['BILOAD_VERIFY_ID'] ?? '';
    _check(RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id), 'Invalid run id');
    final base = Uri.parse(
      Platform.environment['BILOAD_VERIFY_BASE_URL'] ?? '',
    );
    _check(
      base.scheme == 'http' && base.host == '127.0.0.1',
      'Verification only accepts loopback fixtures',
    );
    final paths = await AppPaths.create();
    root = Directory(p.join(paths.dataDirectory, 'verification', id));
    await root.create(recursive: true);
    _check(
      p.isWithin(paths.installDirectory, root.path),
      'Data escaped the installation directory',
    );
    report['dataDirectory'] = paths.dataDirectory;
    checks.add('installation-local-data');
    stdout.writeln('BILOAD_RELEASE_REPORT=${p.join(root.path, 'report.json')}');
    await stdout.flush();
    final client = HttpClient();
    Future<Json> manifest() async {
      final response = await (await client.getUrl(
        base.resolve('manifest.json'),
      )).close();
      return object(jsonDecode(await utf8.decoder.bind(response).join()));
    }

    final api = _FixtureApi(base, object((await manifest())['files']));
    final store = LocalStore(p.join(root.path, 'jobs.sqlite'));
    store.setSetting('probe', id);
    _check(store.setting('probe') == id, 'SQLite round trip');
    checks.add('sqlite');
    final vault = FileSessionVault(root.path);
    await vault.write('synthetic-$id').timeout(const Duration(seconds: 20));
    _check(
      await vault.read().timeout(const Duration(seconds: 20)) ==
          'synthetic-$id',
      'Local encrypted account round trip',
    );
    _check(
      !utf8
          .decode(await vault.file.readAsBytes(), allowMalformed: true)
          .contains('synthetic-$id'),
      'Account was stored as plaintext',
    );
    await vault.write('updated-$id');
    _check(
      await FileSessionVault(root.path).read() == 'updated-$id',
      'Account overwrite and reopen',
    );
    await vault.clear().timeout(const Duration(seconds: 20));
    _check(
      await vault.read().timeout(const Duration(seconds: 20)) == null,
      'Local account cleanup',
    );
    checks.add('local-session-vault');
    final version = await FFmpegKit.executeWithArguments(['-version']);
    _check(
      ReturnCode.isSuccess(await version.getReturnCode()),
      'Native FFmpeg version command',
    );
    report['ffmpegVersionAndConfiguration'] = await version.getOutput();
    final transferStore = TransferStore(p.join(root.path, 'transfers.sqlite'));
    final downloader = FileDownloader(persistentStorage: transferStore);
    final manager = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(root.path, 'working'),
      downloader: downloader,
      onError: (error, stack) {
        // This process only handles local synthetic fixtures, never credentials.
        report['nativeFailure'] = '$error';
        report['nativeStack'] = '$stack';
      },
    );
    await manager.initialize().timeout(const Duration(seconds: 45));
    final output = p.join(root.path, '下载 中文 # 100%');
    final controller = BiloadController(
      api: api,
      auth: AuthController(api, vault),
      downloads: manager,
      store: store,
      outputDirectory: output,
      dataDirectory: root.path,
    );
    final flutterErrors = <String>[];
    final asyncErrors = <String>[];
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      asyncErrors.add('$error\n$stack');
      return true;
    };
    FlutterError.onError = (details) => flutterErrors.add(details.toString());
    final boundaryKey = GlobalKey();
    runApp(
      RepaintBoundary(
        key: boundaryKey,
        child: BiloadApp(controller: controller),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    await controller.parse('https://www.bilibili.com/video/BV19pnt6XE6d/');
    _check(controller.error == null, 'Controller parse: ${controller.error}');
    _check(
      controller.selectedVideos.length == 1 &&
          controller.selectedAudios.length == 1,
      'Default track selection',
    );
    checks.add('ui-and-default-selection');
    await Future<void>.delayed(const Duration(seconds: 1));
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    _check(image.width > 0 && image.height > 0, 'Empty UI image');
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    var minimum = 255;
    var maximum = 0;
    var opaque = 0;
    for (var offset = 0; offset < rgba.length; offset += 4 * 97) {
      if (rgba[offset + 3] < 200) continue;
      opaque++;
      for (var channel = 0; channel < 3; channel++) {
        final value = rgba[offset + channel];
        if (value < minimum) minimum = value;
        if (value > maximum) maximum = value;
      }
    }
    report['uiPixels'] = {
      'width': image.width,
      'height': image.height,
      'opaqueSamples': opaque,
      'minimum': minimum,
      'maximum': maximum,
    };
    _check(
      opaque > 100 && minimum < 200 && maximum > 220,
      'UI raster is blank, black, or transparent',
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(p.join(root.path, 'parsed-ui.png'))
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    checks.add('rendered-ui');

    Future<void> download(
      VideoVariant? video,
      List<AudioVariant> audios,
      String container,
      String label, {
      bool pause = false,
    }) async {
      final jobs = await manager.add(
        page: _FixtureApi.page,
        videos: video == null ? [] : [video],
        audios: audios,
        container: container,
        directory: output,
      );
      _check(jobs.length == 1, '$label should create one output');
      final job = jobs.single;
      if (pause) {
        await _until(
          () => job.downloadedBytes > 100000 || job.isFinished,
          'download before pause',
        );
        _check(!job.isFinished, 'Pause fixture completed too soon');
        await manager.pause(job);
        await _until(() => !manager.hasActiveWorkers, 'paused worker');
        _check(job.status == JobStatus.paused, 'Paused state');
        final resumeData = await transferStore.retrieveAllResumeData();
        _check(
          resumeData.isNotEmpty &&
              resumeData.every(
                (data) => p.isWithin(root!.path, data.tempFilepath),
              ),
          'Native resume cache escaped user-data',
        );
        checks.add('local-native-transfer-cache');
        await manager.resume(job);
      }
      await _until(() => job.isFinished, label);
      _check(job.status == JobStatus.complete, '$label: ${job.message}');
      _check(
        job.progress == 1 && job.remainingBytes == 0,
        '$label byte progress',
      );
      _check(await File(job.output).length() > 0, '$label published file');
      final info = await probeMedia(job.output);
      final streams = info?.getStreams();
      _check(streams != null, '$label ffprobe');
      _check(
        streams!.where((s) => s.getType() == 'video').length ==
            (video == null ? 0 : 1),
        '$label video tracks',
      );
      _check(
        streams.where((s) => s.getType() == 'audio').length == audios.length,
        '$label audio tracks',
      );
      await _until(() => !manager.hasActiveWorkers, '$label cleanup');
      final leftovers = await Directory(manager.workDirectory)
          .list(recursive: true)
          .where((entry) => entry is File)
          .toList();
      _check(leftovers.isEmpty, '$label retained duplicate cache');
      _check(
        store.loadJobs().any(
          (saved) =>
              saved.output == job.output && saved.status == JobStatus.complete,
        ),
        '$label persisted completion',
      );
      checks.add(label);
    }

    final catalog = controller.catalog!;
    for (final video in catalog.videos) {
      await download(
        video,
        [catalog.audios.first],
        'mp4',
        '${video.codecLabel}-AAC',
      );
    }
    await download(
      catalog.videos.first,
      catalog.audios,
      'mkv',
      'multi-audio-AAC-FLAC-EAC3',
    );
    for (final audio in catalog.audios) {
      await download(null, [audio], 'mkv', 'audio-only-${audio.id}');
    }
    api.slow = true;
    await download(
      (await api.catalog(_FixtureApi.page)).videos.first,
      [catalog.audios.first],
      'mp4',
      'pause-resume',
      pause: true,
    );
    final requests = objects((await manifest())['rangeRequests']);
    _check(
      requests.any((r) => r['file'] == 'slow.mp4' && integer(r['start']) > 0),
      'Resume must issue a byte Range',
    );
    checks.add('http-range-resume');
    _check(flutterErrors.isEmpty, 'Flutter errors: $flutterErrors');
    _check(asyncErrors.isEmpty, 'Unhandled asynchronous errors: $asyncErrors');
    checks.add('no-flutter-errors');
    _check(
      await WebviewWindow.isWebviewAvailable(),
      'Native webview unavailable',
    );
    if (Platform.isMacOS) {
      final result = await const MethodChannel('app.biload/platform')
          .invokeMethod<Map<Object?, Object?>>('verifyLoginBrowser', {
            'url': base.resolve('login').toString(),
            'title': 'biload · isolated web verification',
          })
          .timeout(const Duration(seconds: 30));
      _check(
        result?['value'] == 'fixture' && result?['httpOnly'] == true,
        'Ephemeral native HttpOnly cookie retrieval failed',
      );
    } else {
      final browser = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'biload · isolated web verification',
          windows: WindowsWebviewOptions(
            userDataFolder: p.join(root.path, 'verification-webview'),
          ),
        ),
      );
      try {
        await browser.setOnUrlRequestCallback(
          (url) => Uri.tryParse(url)?.origin == base.origin,
        );
        await browser.launch(base.resolve('login').toString());
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        var found = false;
        while (DateTime.now().isBefore(deadline)) {
          final cookies = await browser.getAllCookies().timeout(
            const Duration(seconds: 5),
          );
          found = cookies.any(
            (cookie) =>
                browserCookieText(cookie.name) == 'biload_fixture' &&
                browserCookieText(cookie.value) == 'fixture' &&
                cookie.httpOnly,
          );
          if (found) break;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        _check(found, 'Native HttpOnly cookie retrieval failed');
      } finally {
        await browser.close();
      }
    }
    _check(
      integer((await manifest())['successfulPosts']) == 1,
      'Webview navigation did not preserve the POST body',
    );
    checks.add('webview-post-and-httpOnly-cookie');
    client.close();
    store.close();
    transferStore.db.close();
    report['passed'] = true;
  } catch (error, stack) {
    report['passed'] = false;
    report['error'] = '$error';
    report['stack'] = '$stack';
    stderr.writeln('BILOAD_RELEASE_FAILURE=$error');
  }
  report['finished'] = DateTime.now().toUtc().toIso8601String();
  if (root != null) {
    await File(p.join(root.path, 'report.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }
  exit(report['passed'] == true ? 0 : 1);
}
