import 'dart:convert';
import 'dart:io';

import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';
import 'package:biload/data/local_store.dart';
import 'package:biload/services/download_manager.dart';
import 'package:biload/services/muxer.dart';
import 'package:biload/services/output_storage.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FixtureCatalogApi extends BiliApi {
  FixtureCatalogApi(this.fixture);
  final StreamCatalog fixture;
  @override
  Future<StreamCatalog> catalog(MediaPage page) async => fixture;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <String, Object?>{};
  late Directory verificationRoot;
  late String fixtureVideo;
  late String fixtureAudio;
  late String fixtureOutput;
  setUpAll(() async {
    final base = Platform.isAndroid
        ? await getExternalStorageDirectory() ?? await getTemporaryDirectory()
        : await getTemporaryDirectory();
    verificationRoot = await Directory(
      p.join(
        base.path,
        'biload-verification-${DateTime.now().millisecondsSinceEpoch}',
      ),
    ).create(recursive: true);
  });
  tearDownAll(() async {
    final report = {
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
      'networkRequested': const bool.fromEnvironment('BILOAD_NETWORK_SMOKE'),
      'results': results,
    };
    binding.reportData = report;
    final file = File(p.join(verificationRoot.path, 'report.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    debugPrint('BILOAD_NATIVE_REPORT=${file.path}');
  });

  testWidgets(
    'native FFmpeg copies video and audio and validates the resulting file',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('biload native verification')),
        ),
      );
      final root = await Directory(
        p.join(verificationRoot.path, 'native-空格 test'),
      ).create(recursive: true);
      final video = p.join(root.path, 'video.mp4');
      final audio = p.join(root.path, 'audio.m4a');
      fixtureVideo = video;
      fixtureAudio = audio;
      for (final args in [
        [
          '-y',
          '-f',
          'lavfi',
          '-i',
          'color=c=green:s=128x72:r=10',
          '-t',
          '2',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          video,
        ],
        [
          '-y',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:sample_rate=44100',
          '-t',
          '2',
          '-c:a',
          'aac',
          audio,
        ],
      ]) {
        final session = await FFmpegKit.executeWithArguments(args);
        expect(
          ReturnCode.isSuccess(await session.getReturnCode()),
          isTrue,
          reason: await session.getFailStackTrace(),
        );
      }
      const page = MediaPage(
        ref: ContentRef(ContentKind.video, 'BV17x411w7KC'),
        cid: 1,
        aid: 1,
        bvid: 'BV17x411w7KC',
        title: 'native test',
        part: 'test',
        index: 1,
        duration: 2,
      );
      final job = DownloadJob(
        id: 'native-smoke',
        page: page,
        videoKey: 'test',
        audioKeys: ['aac'],
        container: 'mkv',
        directory: root.path,
        createdAt: DateTime.now(),
      );
      final output = p.join(root.path, '输出 test.mkv');
      fixtureOutput = output;
      await MediaMuxer().mux(
        job: job,
        video: [MuxInput(video)],
        audio: [audio],
        audioInfo: const [
          AudioVariant(
            id: 30280,
            codecs: 'mp4a.40.2',
            bandwidth: 192000,
            sources: [],
          ),
        ],
        output: output,
        progressive: false,
      );
      final info = (await FFprobeKit.getMediaInformation(output))
          .getMediaInformation()!;
      expect(
        info
            .getStreams()
            .where((s) => s.getType() == 'video')
            .single
            .getCodec(),
        'h264',
      );
      expect(
        info
            .getStreams()
            .where((s) => s.getType() == 'audio')
            .single
            .getCodec(),
        'aac',
      );
      results['syntheticMux'] = {
        'container': 'mkv',
        'videoCodec': 'h264',
        'audioCodec': 'aac',
        'unicodePath': true,
        'bytes': await File(output).length(),
        'output': p.relative(output, from: verificationRoot.path),
      };
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'Android public Downloads storage commits one readable file and can delete it',
    (tester) async {
      final storage = OutputStorage();
      final name =
          'biload-storage-${DateTime.now().millisecondsSinceEpoch}.mkv';
      await storage.prepare(OutputStorage.androidDownloads);
      final output = await storage.publish(
        fixtureOutput,
        OutputStorage.androidDownloads,
        name,
      );
      try {
        expect(output, startsWith('content://media/'));
        expect(await storage.exists(output), isTrue);
        expect(await File(fixtureOutput).exists(), isTrue);
        final repeated = await storage.publish(
          fixtureOutput,
          OutputStorage.androidDownloads,
          name,
        );
        expect(
          repeated,
          output,
          reason: 'Retry must reuse the committed publication',
        );
        final safPath = await FFmpegKitConfig.getSafParameterForRead(output);
        final info = (await FFprobeKit.getMediaInformation(safPath!))
            .getMediaInformation()!;
        expect(
          info
              .getStreams()
              .where((s) => s.getType() == 'video')
              .single
              .getCodec(),
          'h264',
        );
        expect(
          info
              .getStreams()
              .where((s) => s.getType() == 'audio')
              .single
              .getCodec(),
          'aac',
        );
        results['publicStorage'] = {
          'destination': 'Download/biload',
          'readable': true,
          'idempotent': true,
          'videoCodec': 'h264',
          'audioCodec': 'aac',
        };
      } finally {
        await storage.delete(output);
      }
      expect(await storage.exists(output), isFalse);
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native UIDT stays alive during a slow transfer beyond the notification deadline',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('biload slow transfer verification')),
        ),
      );
      final videoBytes = await File(fixtureVideo).readAsBytes();
      final audioBytes = await File(fixtureAudio).readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.forEach((request) async {
        final bytes = request.uri.path == '/video' ? videoBytes : audioBytes;
        final match = RegExp(r'^bytes=(\d+)-')
            .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
        final start = match == null ? 0 : int.parse(match.group(1)!);
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.contentLength = bytes.length - start;
        if (match != null) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${bytes.length - 1}/${bytes.length}',
          );
        }
        if (request.method != 'HEAD') {
          request.response.add(bytes.sublist(start, start + 1));
          await request.response.flush();
          if (request.uri.path == '/video') {
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          request.response.add(bytes.sublist(start + 1));
        }
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final catalog = StreamCatalog(
        videos: [
          VideoVariant(
            quality: 16,
            codec: 7,
            codecs: 'avc1',
            bandwidth: 10000,
            width: 128,
            height: 72,
            frameRate: '10',
            sources: [
              StreamSource(['$base/video'], size: videoBytes.length),
            ],
          ),
        ],
        audios: [
          AudioVariant(
            id: 30280,
            codecs: 'mp4a.40.2',
            bandwidth: 70000,
            sources: [
              StreamSource(['$base/audio'], size: audioBytes.length),
            ],
          ),
        ],
      );
      const page = MediaPage(
        ref: ContentRef(ContentKind.video, 'BV17x411w7KC'),
        cid: 1,
        aid: 1,
        bvid: 'BV17x411w7KC',
        title: 'slow native fixture',
        part: 'test',
        index: 1,
        duration: 2,
      );
      final root = await Directory(p.join(verificationRoot.path, 'slow'))
          .create();
      final store = LocalStore(p.join(root.path, 'tasks.sqlite'));
      final manager = DownloadManager(
        outputStorage: OutputStorage(isAndroid: false),
        api: FixtureCatalogApi(catalog),
        store: store,
        workDirectory: p.join(root.path, 'work'),
      );
      try {
        await manager.initialize();
        manager.configure(concurrent: 1);
        final elapsed = Stopwatch()..start();
        final job = (await manager.add(
          page: page,
          videos: catalog.videos,
          audios: catalog.audios,
          container: 'mp4',
          directory: p.join(root.path, 'output'),
        )).single;
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while (!job.isFinished && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        expect(job.status, JobStatus.complete, reason: job.message);
        expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(15000));
        results['slowNativeTransfer'] = {
          'elapsedMs': elapsed.elapsedMilliseconds,
          'bytes': await File(job.output).length(),
          'notificationDeadlineExceeded': true,
        };
      } finally {
        for (final job in manager.jobs.where((j) => !j.isFinished)) {
          await manager.cancel(job);
        }
        for (var i = 0; manager.hasActiveWorkers && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        manager.dispose();
        store.close();
        await server.close(force: true);
        await serving;
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'public Bilibili stream downloads and muxes through native components',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('biload network verification')),
        ),
      );
      final api = BiliApi();
      final media = await api.content(
        await api.resolveLink(
          const String.fromEnvironment(
            'BILOAD_TEST_BVID',
            defaultValue: 'BV17x411w7KC',
          ),
        ),
      );
      final page = media.pages.first;
      final catalog = await api.catalog(page);
      final root = await Directory(p.join(verificationRoot.path, 'network'))
          .create(recursive: true);
      final store = LocalStore(p.join(root.path, 'tasks.sqlite'));
      final manager = DownloadManager(
        api: api,
        store: store,
        workDirectory: p.join(root.path, 'work'),
      );
      await manager.initialize();
      manager.configure(concurrent: 1);
      final progressSamples = <Map<String, Object>>[];
      manager.addListener(() {
        if (manager.jobs.isEmpty || progressSamples.length >= 20) return;
        final job = manager.jobs.first;
        if (job.status != JobStatus.downloading || job.totalBytes <= 0) return;
        final sample = <String, Object>{
          'downloaded': job.downloadedBytes,
          'total': job.totalBytes,
          'remaining': job.remainingBytes,
          'fraction': job.progress,
        };
        if (progressSamples.isEmpty ||
            progressSamples.last['downloaded'] != job.downloadedBytes) {
          progressSamples.add(sample);
        }
      });
      final job = (await manager.add(
        page: page,
        videos: [catalog.videos.firstWhere((v) => v.codec == 7)],
        audios: [catalog.audios.firstWhere((a) => a.codecs.startsWith('mp4a'))],
        container: 'mp4',
        directory: Platform.isAndroid
            ? OutputStorage.androidDownloads
            : p.join(root.path, 'output'),
      )).single;
      try {
        final deadline = DateTime.now().add(const Duration(minutes: 8));
        while (manager.hasActiveWorkers && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(job.status, JobStatus.complete, reason: job.message);
        expect(await manager.outputStorage.exists(job.output), isTrue);
        final readPath = Platform.isAndroid
            ? (await FFmpegKitConfig.getSafParameterForRead(job.output))!
            : job.output;
        final info = (await FFprobeKit.getMediaInformation(readPath))
            .getMediaInformation()!;
        final bytes = int.parse(info.getSize()!);
        expect(bytes, greaterThan(1024));
        expect(
          info.getStreams().where((s) => s.getType() == 'video').length,
          1,
        );
        expect(
          info.getStreams().where((s) => s.getType() == 'audio').length,
          1,
        );
        expect(
          await Directory(p.join(root.path, 'work', job.id)).exists(),
          isFalse,
        );
        expect(progressSamples, isNotEmpty);
        for (final sample in progressSamples) {
          expect(
            sample['fraction'],
            closeTo(
              (sample['downloaded'] as int) / (sample['total'] as int),
              0.00001,
            ),
          );
        }
        results['publicDownload'] = {
          'bvid': page.bvid,
          'container': 'mp4',
          'bytes': bytes,
          if (!Platform.isAndroid)
            'output': p.relative(job.output, from: verificationRoot.path),
          'destination': Platform.isAndroid ? 'Download/biload' : root.path,
          'videoTracks': 1,
          'audioTracks': 1,
          'byteProgressSamples': progressSamples,
          'privateTaskCacheRemoved': true,
          'persistedStatus': store.loadJobs().single.status.name,
          'testFileRemovedAfterVerification': Platform.isAndroid,
        };
      } finally {
        if (Platform.isAndroid && job.status == JobStatus.complete) {
          await manager.outputStorage.delete(job.output);
        }
        if (!job.isFinished) await manager.cancel(job);
        while (manager.hasActiveWorkers) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        manager.dispose();
        store.close();
      }
    },
    skip: !const bool.fromEnvironment('BILOAD_NETWORK_SMOKE'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
