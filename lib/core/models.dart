import 'dart:convert';

typedef Json = Map<String, dynamic>;

Json object(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};
List<Json> objects(Object? value) =>
    value is List ? value.whereType<Map>().map(object).toList() : <Json>[];
int integer(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
String string(Object? value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

class BiliException implements Exception {
  const BiliException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => message;
}

enum ContentKind { video, episode, season, media }

class ContentRef {
  const ContentRef(this.kind, this.id, {this.page = 1});
  final ContentKind kind;
  final String id;
  final int page;
  Json toJson() => {'kind': kind.name, 'id': id, 'page': page};
  factory ContentRef.fromJson(Json json) => ContentRef(
    ContentKind.values.byName(string(json['kind'])),
    string(json['id']),
    page: integer(json['page'], 1),
  );
}

class MediaPage {
  const MediaPage({
    required this.ref,
    required this.cid,
    required this.aid,
    required this.bvid,
    required this.title,
    required this.part,
    required this.index,
    required this.duration,
    this.epid,
    this.cover = '',
  });
  final ContentRef ref;
  final int cid;
  final int aid;
  final String bvid;
  final int? epid;
  final String title;
  final String part;
  final int index;
  final int duration;
  final String cover;
  bool get isPgc => epid != null;
  String get key => epid == null ? '$bvid:$cid' : 'ep$epid:$cid';
  String get webUrl => epid == null
      ? 'https://www.bilibili.com/video/$bvid?p=$index'
      : 'https://www.bilibili.com/bangumi/play/ep$epid';
  Json toJson() => {
    'ref': ref.toJson(),
    'cid': cid,
    'aid': aid,
    'bvid': bvid,
    'epid': epid,
    'title': title,
    'part': part,
    'index': index,
    'duration': duration,
    'cover': cover,
  };
  factory MediaPage.fromJson(Json j) => MediaPage(
    ref: ContentRef.fromJson(object(j['ref'])),
    cid: integer(j['cid']),
    aid: integer(j['aid']),
    bvid: string(j['bvid']),
    title: string(j['title']),
    part: string(j['part']),
    index: integer(j['index']),
    duration: integer(j['duration']),
    epid: j['epid'] == null ? null : integer(j['epid']),
    cover: string(j['cover']),
  );
}

class MediaContent {
  const MediaContent({
    required this.title,
    required this.author,
    required this.cover,
    required this.pages,
    this.preferredPage = 0,
  });
  final String title;
  final String author;
  final String cover;
  final List<MediaPage> pages;
  final int preferredPage;
}

class StreamSource {
  const StreamSource(this.urls, {this.size = 0});
  final List<String> urls;
  final int size;
}

class VideoVariant {
  const VideoVariant({
    required this.quality,
    required this.codec,
    required this.codecs,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.sources,
    this.progressive = false,
  });
  final int quality;
  final int codec;
  final String codecs;
  final int bandwidth;
  final int width;
  final int height;
  final String frameRate;
  final List<StreamSource> sources;
  final bool progressive;
  String get codecLabel => switch (codec) {
    7 => 'AVC',
    12 => 'HEVC',
    13 => 'AV1',
    _ => '编码 $codec',
  };
  String get qualityLabel => qualityName(quality);
  String get semanticKey => '${progressive ? 'p' : 'v'}_${quality}_$codec';
  String get key => '${semanticKey}_${bandwidth}_${width}_${height}_$frameRate';
  int estimateBytes(int seconds) =>
      sources.fold(0, (sum, e) => sum + e.size) > 0
      ? sources.fold(0, (sum, e) => sum + e.size)
      : bandwidth * seconds ~/ 8;
}

class AudioVariant {
  const AudioVariant({
    required this.id,
    required this.codecs,
    required this.bandwidth,
    required this.sources,
    this.language = '',
    this.languageTitle = '',
  });
  final int id;
  final String codecs;
  final int bandwidth;
  final List<StreamSource> sources;
  final String language;
  final String languageTitle;
  String get qualityLabel => switch (id) {
    30216 => '标准音质',
    30232 => '高音质',
    30280 => '高码率',
    30250 => '杜比音频',
    30251 => 'Hi-Res 无损',
    _ => '音频 $id',
  };
  String get label =>
      '$qualityLabel · ${languageTitle.isEmpty ? '原音' : languageTitle}';
  String get semanticKey => 'a_${id}_${language}_$codecs';
  String get key => '${semanticKey}_$bandwidth';
}

class UnavailableFormat {
  const UnavailableFormat(this.quality, this.label, this.reason);
  final int quality;
  final String label;
  final String reason;
}

class StreamCatalog {
  const StreamCatalog({
    required this.videos,
    required this.audios,
    this.unavailable = const [],
    this.warnings = const [],
  });
  final List<VideoVariant> videos;
  final List<AudioVariant> audios;
  final List<UnavailableFormat> unavailable;
  final List<String> warnings;
}

String qualityName(int quality) => switch (quality) {
  6 => '240P',
  16 => '360P',
  32 => '480P',
  64 => '720P',
  74 => '720P 60帧',
  80 => '1080P',
  100 => '智能修复',
  112 => '1080P 高码率',
  116 => '1080P 60帧',
  120 => '4K',
  125 => 'HDR',
  126 => '杜比视界',
  127 => '8K',
  129 => 'HDR Vivid',
  _ => '清晰度 $quality',
};

class BiliSession {
  BiliSession({Map<String, String>? cookies, this.refreshToken = ''})
    : cookies = cookies ?? {};
  final Map<String, String> cookies;
  String refreshToken;
  bool get hasLogin => (cookies['SESSDATA'] ?? '').isNotEmpty;
  String get cookieHeader => cookies.entries
      .where(
        (e) =>
            RegExp(r'^[A-Za-z0-9_]+$').hasMatch(e.key) &&
            !e.value.contains(RegExp(r'[\r\n;]')),
      )
      .map((e) => '${e.key}=${e.value}')
      .join('; ');
  String encode() =>
      jsonEncode({'cookies': cookies, 'refreshToken': refreshToken});
  factory BiliSession.decode(String encoded) {
    final j = object(jsonDecode(encoded));
    return BiliSession(
      cookies: object(j['cookies']).map((k, v) => MapEntry(k, string(v))),
      refreshToken: string(j['refreshToken']),
    );
  }
  factory BiliSession.fromCookieHeader(String header) {
    final cookies = <String, String>{};
    for (final part in header.trim().split(';')) {
      final split = part.indexOf('=');
      if (split > 0) {
        final key = part.substring(0, split).trim();
        final value = part.substring(split + 1).trim();
        if (RegExp(r'^[A-Za-z0-9_]+$').hasMatch(key) &&
            !value.contains(RegExp(r'[\r\n]'))) {
          cookies[key] = value;
        }
      }
    }
    if (!(cookies['SESSDATA']?.isNotEmpty ?? false)) {
      throw const BiliException('未找到有效的 SESSDATA，请检查 Cookie。');
    }
    return BiliSession(cookies: cookies);
  }
}

class AccountInfo {
  const AccountInfo({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.vip,
  });
  final int uid;
  final String name;
  final String avatar;
  final bool vip;
}

class LoginQr {
  const LoginQr(this.key, this.url);
  final String key;
  final String url;
}

enum JobStatus {
  queued,
  resolving,
  downloading,
  paused,
  merging,
  complete,
  failed,
  canceled,
}

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.page,
    required this.videoKey,
    required this.audioKeys,
    required this.container,
    required this.directory,
    required this.createdAt,
    this.status = JobStatus.queued,
    this.progress = 0,
    this.message = '',
    this.output = '',
    this.bytesPerSecond = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
  });
  final String id;
  final MediaPage page;
  final String? videoKey;
  final List<String> audioKeys;
  final String container;
  String directory;
  final DateTime createdAt;
  JobStatus status;
  double progress;
  String message;
  String output;
  double bytesPerSecond;
  int downloadedBytes;
  int totalBytes;
  int get remainingBytes => (totalBytes - downloadedBytes).clamp(0, totalBytes);
  bool get isFinished => {
    JobStatus.complete,
    JobStatus.failed,
    JobStatus.canceled,
  }.contains(status);
  Json toJson() => {
    'id': id,
    'page': page.toJson(),
    'videoKey': videoKey,
    'audioKeys': audioKeys,
    'container': container,
    'directory': directory,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'progress': progress,
    'message': message,
    'output': output,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
  };
  factory DownloadJob.fromJson(Json j) => DownloadJob(
    id: string(j['id']),
    page: MediaPage.fromJson(object(j['page'])),
    videoKey: j['videoKey'] as String?,
    audioKeys: (j['audioKeys'] as List).cast<String>(),
    container: string(j['container']),
    directory: string(j['directory']),
    createdAt: DateTime.parse(string(j['createdAt'])),
    status: JobStatus.values.byName(string(j['status'])),
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    message: string(j['message']),
    output: string(j['output']),
    downloadedBytes: integer(j['downloadedBytes']),
    totalBytes: integer(j['totalBytes']),
  );
}

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String safeFilename(String value) {
  var name = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (name.isEmpty) name = 'biload';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(name)) {
    name = '_$name';
  }
  return String.fromCharCodes(name.runes.take(50));
}
