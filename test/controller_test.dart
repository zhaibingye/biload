import 'dart:io';

import 'package:biload/app_controller.dart';
import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';
import 'package:biload/data/local_store.dart';
import 'package:biload/services/auth_controller.dart';
import 'package:biload/services/download_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class SelectionApi extends BiliApi {
  StreamCatalog versions = BiliApi.parseStreams(sampleStreams());
  @override
  Future<MediaContent> content(ContentRef ref) async => const MediaContent(
    title: 'fixture',
    author: '',
    cover: '',
    pages: [samplePage],
  );
  @override
  Future<StreamCatalog> catalog(MediaPage page) async => versions;
}

class RecordingDownloads extends DownloadManager {
  RecordingDownloads(SelectionApi api, LocalStore store)
    : super(api: api, store: store, workDirectory: Directory.systemTemp.path);
  final plans = <({List<VideoVariant> video, List<AudioVariant> audio})>[];
  @override
  Future<List<DownloadJob>> add({
    required MediaPage page,
    required List<VideoVariant> videos,
    required List<AudioVariant> audios,
    required String container,
    required String directory,
  }) async {
    plans.add((video: videos, audio: audios));
    return [
      DownloadJob(
        id: 'selection',
        page: page,
        videoKey: videos.firstOrNull?.key,
        audioKeys: audios.map((a) => a.key).toList(),
        container: container,
        directory: directory,
        createdAt: DateTime.now(),
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SelectionApi api;
  late LocalStore store;
  late RecordingDownloads downloads;
  late BiloadController controller;
  setUp(() {
    api = SelectionApi();
    store = LocalStore(':memory:');
    downloads = RecordingDownloads(api, store);
    controller = BiloadController(
      api: api,
      auth: AuthController(api, MemoryVault()),
      downloads: downloads,
      store: store,
      outputDirectory: Directory.systemTemp.path,
    );
  });
  tearDown(() {
    controller.dispose();
    downloads.dispose();
    store.close();
  });

  test(
    'default DASH video and AAC are submitted as one combined video job',
    () async {
      await controller.parse('BV17x411w7KC');
      expect(controller.error, isNull);
      expect(controller.selectedVideos.length, 1);
      expect(controller.selectedAudios.length, 1);
      expect(controller.outputSelectionDescription, contains('不会额外生成音频文件'));
      expect(await controller.enqueue(), 1);
      expect(downloads.plans.length, 1);
      expect(downloads.plans.single.video.length, 1);
      expect(downloads.plans.single.audio.single.codecs, startsWith('mp4a'));
    },
  );

  test('progressive source keeps embedded audio without default redundant audio transfer', () async {
    api.versions = StreamCatalog(
      videos: const [
        VideoVariant(
          quality: 80,
          codec: 7,
          codecs: 'progressive',
          bandwidth: 0,
          width: 0,
          height: 0,
          frameRate: '',
          sources: [],
          progressive: true,
        ),
      ],
      audios: api.versions.audios,
    );
    await controller.parse('BV17x411w7KC');
    expect(controller.selectedVideos.length, 1);
    expect(controller.selectedAudios, isEmpty);
    expect(await controller.enqueue(), 1);
    expect(downloads.plans.single.video.single.progressive, isTrue);
    expect(downloads.plans.single.audio, isEmpty);
  });

  test(
    'an independent audio job is created only when no video is selected',
    () async {
      await controller.parse('BV17x411w7KC');
      controller.toggleVideo(controller.selectedVideos.single);
      expect(controller.outputSelectionDescription, startsWith('仅下载音频'));
      expect(await controller.enqueue(), 1);
      expect(downloads.plans.single.video, isEmpty);
      expect(downloads.plans.single.audio.length, 1);
    },
  );
}
