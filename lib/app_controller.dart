import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/bili_api.dart';
import 'core/models.dart';
import 'data/local_store.dart';
import 'services/auth_controller.dart';
import 'services/download_manager.dart';
import 'services/output_storage.dart';

class BiloadController extends ChangeNotifier {
  BiloadController({
    required this.api,
    required this.auth,
    required this.downloads,
    required this.store,
    required this.outputDirectory,
  }) {
    auth.addListener(notifyListeners);
    downloads.addListener(notifyListeners);
  }
  final BiliApi api;
  final AuthController auth;
  final DownloadManager downloads;
  final LocalStore store;
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

  int _generation = 0;

  static Future<BiloadController> create() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final store = LocalStore(p.join(support.path, 'biload.sqlite'));
    final api = BiliApi();
    final auth = AuthController(api, const SecureSessionVault());
    final base = Platform.isAndroid ? null : await getDownloadsDirectory();
    final fallback = base ?? await getApplicationDocumentsDirectory();
    final defaultOutput = Platform.isAndroid
        ? OutputStorage.androidDownloads
        : p.join(fallback.path, 'biload');
    final savedDirectory = store.setting('directory');
    final downloads = DownloadManager(
      api: api,
      store: store,
      workDirectory: p.join(support.path, 'downloads'),
    );
    final app = BiloadController(
      api: api,
      auth: auth,
      downloads: downloads,
      store: store,
      outputDirectory:
          savedDirectory != null &&
              (!Platform.isAndroid ||
                  downloads.outputStorage.isSharedDirectory(savedDirectory))
          ? savedDirectory
          : defaultOutput,
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
    final generation = ++_generation;
    notifyListeners();
    try {
      final ref = await api.resolveLink(input);
      final media = await api.content(ref);
      if (generation != _generation) return;
      content = media;
      pageIndex = media.preferredPage;
      status = '正在枚举清晰度、编码和音轨';
      notifyListeners();
      await _catalog(generation);
    } catch (e) {
      error = e is BiliException ? e.message : '解析失败，请检查链接并重试。';
    } finally {
      if (generation == _generation) {
        parsing = false;
        status = '';
        notifyListeners();
      }
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
    final generation = ++_generation;
    status = '正在枚举此分集的版本';
    notifyListeners();
    try {
      await _catalog(generation);
    } catch (e) {
      error = e is BiliException ? e.message : '获取版本列表失败，请重试。';
    } finally {
      parsing = false;
      status = '';
      notifyListeners();
    }
  }

  Future<void> _catalog(int generation) async {
    final versions = await api.catalog(page!);
    if (generation != _generation) return;
    catalog = versions;
    selectedVideos.clear();
    selectedAudios.clear();
    if (versions.videos.isNotEmpty) {
      final bestQuality = versions.videos.first.quality;
      final avc = versions.videos.where(
        (v) => v.quality == bestQuality && v.codec == 7,
      );
      selectedVideos.add((avc.isEmpty ? versions.videos.first : avc.first).key);
      final selected = versions.videos.firstWhere(
        (v) => selectedVideos.contains(v.key),
      );
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
