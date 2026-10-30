import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import 'core/bili_api.dart';
import 'core/models.dart';
import 'data/local_store.dart';
import 'data/app_paths.dart';
import 'data/transfer_store.dart';
import 'services/auth_controller.dart';
import 'services/download_manager.dart';
import 'services/file_session_vault.dart';
import 'services/output_storage.dart';

class BiloadController extends ChangeNotifier {
  BiloadController({
    required this.api,
    required this.auth,
    required this.downloads,
    required this.store,
    required this.outputDirectory,
    this.dataDirectory,
  }) {
    auth.addListener(notifyListeners);
    downloads.addListener(notifyListeners);
  }
  final BiliApi api;
  final AuthController auth;
  final DownloadManager downloads;
  final LocalStore store;
  final String? dataDirectory;
  String outputDirectory;
  String get outputDirectoryLabel =>
      outputDirectory == OutputStorage.androidDownloads
      ? OutputStorage.androidDownloadsLabel
      : store.setting('directoryLabel') ?? outputDirectory;
  MediaContent? content;
  StreamCatalog? catalog;
  int pageIndex = 0;
  bool parsing = false;
  bool adding = false;
  bool allPages = false;
  String? error;
  String status = '';
  String container = 'mp4';
  final Set<String> selectedVideos = {};
  final Set<String> selectedAudios = {};
  String get outputSelectionDescription {
    if (selectedVideos.isNotEmpty) {
      return '将生成 ${selectedVideos.length} 个视频文件，${selectedAudios.isEmpty ? '保留源文件自带音频（如有）' : '每个文件合并 ${selectedAudios.length} 条所选音轨'}，不会额外生成音频文件。';
    }
    return selectedAudios.isEmpty
        ? '请至少选择一个视频版本或音轨。'
        : '仅下载音频：将生成 ${selectedAudios.length} 个音频文件。';
  }

  static Future<BiloadController> create() async {
    final paths = await AppPaths.create();
    final store = LocalStore(paths.databasePath);
    final api = BiliApi();
    final auth = AuthController(
      api,
      Platform.isAndroid
          ? const AndroidSessionVault()
          : FileSessionVault(paths.dataDirectory),
    );
    final outputDirectory =
        store.setting('directory') ?? await OutputStorage.defaultDirectory();
    final downloads = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(paths.cacheDirectory, 'downloads'),
      downloader: FileDownloader(
        persistentStorage: TransferStore(
          p.join(paths.dataDirectory, 'transfers.sqlite'),
        ),
      ),
    );
    final app = BiloadController(
      api: api,
      auth: auth,
      downloads: downloads,
      store: store,
      dataDirectory: paths.dataDirectory,
      outputDirectory: outputDirectory,
    );
    await auth.restore();
    await downloads.initialize();
    return app;
  }

  MediaPage? get page => content == null ? null : content!.pages[pageIndex];

  Future<void> parse(String input) async {
    if (parsing || adding) return;
    if (input.trim().isEmpty) {
      error = '请先粘贴视频链接或编号。';
      notifyListeners();
      return;
    }
    parsing = true;
    error = null;
    status = '正在解析视频信息';
    catalog = null;
    content = null;
    selectedVideos.clear();
    selectedAudios.clear();
    notifyListeners();
    try {
      final ref = await api.resolveLink(input);
      final media = await api.content(ref);
      content = media;
      pageIndex = media.preferredPage;
      status = '正在枚举清晰度、编码和音轨';
      notifyListeners();
      await _catalog();
    } catch (e) {
      error = e is BiliException ? e.message : '解析失败，请检查链接并重试。';
    } finally {
      parsing = false;
      status = '';
      notifyListeners();
    }
  }

  Future<void> selectPage(int index) async {
    if (parsing ||
        adding ||
        content == null ||
        index < 0 ||
        index >= content!.pages.length) {
      return;
    }
    pageIndex = index;
    parsing = true;
    error = null;
    catalog = null;
    selectedVideos.clear();
    selectedAudios.clear();
    status = '正在枚举此分集的版本';
    notifyListeners();
    try {
      await _catalog();
    } catch (e) {
      error = e is BiliException ? e.message : '获取版本列表失败，请重试。';
    } finally {
      parsing = false;
      status = '';
      notifyListeners();
    }
  }

  Future<void> _catalog() async {
    final versions = await api.catalog(page!);
    catalog = versions;
    if (versions.videos.isNotEmpty) {
      final bestQuality = versions.videos.first.quality;
      final avc = versions.videos.where(
        (v) => v.quality == bestQuality && v.codec == 7,
      );
      final selected = avc.firstOrNull ?? versions.videos.first;
      selectedVideos.add(selected.key);
      if (selected.progressive) return;
    }
    final aac = versions.audios.where((a) => a.codecs.startsWith('mp4a'));
    if (aac.isNotEmpty) {
      selectedAudios.add(aac.first.key);
    } else if (versions.audios.isNotEmpty) {
      selectedAudios.add(versions.audios.first.key);
      container = 'mkv';
    }
  }

  void toggleVideo(String key) {
    selectedVideos.contains(key)
        ? selectedVideos.remove(key)
        : selectedVideos.add(key);
    notifyListeners();
  }

  void toggleAudio(String key) {
    selectedAudios.contains(key)
        ? selectedAudios.remove(key)
        : selectedAudios.add(key);
    notifyListeners();
  }

  void setContainer(String value) {
    container = value;
    notifyListeners();
  }

  void setAllPages(bool value) {
    allPages = value;
    notifyListeners();
  }

  void setDirectory(String value, {String? label}) {
    outputDirectory = value;
    store.setSetting('directory', value);
    store.setSetting('directoryLabel', label ?? value);
    notifyListeners();
  }

  Future<int> enqueue() async {
    if (catalog == null || page == null || adding || parsing) return 0;
    final chosenVideo = catalog!.videos
        .where((v) => selectedVideos.contains(v.key))
        .toList();
    final chosenAudio = catalog!.audios
        .where((a) => selectedAudios.contains(a.key))
        .toList();
    if (chosenVideo.isEmpty && chosenAudio.isEmpty) {
      throw const BiliException('请至少选择一个视频或音频版本。');
    }
    adding = true;
    notifyListeners();
    try {
      final pages = allPages ? content!.pages : [page!];
      final plans = <(MediaPage, List<VideoVariant>, List<AudioVariant>)>[];
      for (var i = 0; i < pages.length; i++) {
        final current = pages[i];
        status = '检查分集 ${i + 1} / ${pages.length}';
        notifyListeners();
        final versions = current.key == page!.key
            ? catalog!
            : await api.catalog(current);
        final video = <VideoVariant>[];
        final audio = <AudioVariant>[];
        for (final selected in chosenVideo) {
          final matches = versions.videos.where(
            (v) => v.semanticKey == selected.semanticKey,
          );
          if (matches.isEmpty) {
            throw BiliException(
              '第 ${current.index} 集缺少 ${selected.qualityLabel} ${selected.codecLabel}，未加入本批任务。',
            );
          }
          video.add(
            matches.reduce((a, b) => a.bandwidth > b.bandwidth ? a : b),
          );
        }
        for (final selected in chosenAudio) {
          final matches = versions.audios.where(
            (a) => a.semanticKey == selected.semanticKey,
          );
          if (matches.isEmpty) {
            throw BiliException(
              '第 ${current.index} 集缺少 ${selected.label}，未加入本批任务。',
            );
          }
          audio.add(matches.first);
        }
        plans.add((current, video, audio));
      }
      var added = 0;
      for (final (current, video, audio) in plans) {
        added += (await downloads.add(
          page: current,
          videos: video,
          audios: audio,
          container: container,
          directory: outputDirectory,
        )).length;
      }
      return added;
    } finally {
      adding = false;
      status = '';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    auth.removeListener(notifyListeners);
    downloads.removeListener(notifyListeners);
    super.dispose();
  }
}
