import 'models.dart';

class LinkParser {
  static bool isBiliHost(String host) =>
      host == 'bilibili.com' || host.endsWith('.bilibili.com');
  static bool isShortHost(String host) =>
      host == 'b23.tv' || host == 'www.b23.tv';

  static Uri? extractUrl(String input) {
    final match = RegExp(
      r'https?://[^\s<>"“”]+',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final text = match.group(0)!.replaceFirst(RegExp(r'[，。！）)\]]+$'), '');
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443 && uri.port != 80)) {
      throw const BiliException('链接格式不正确。');
    }
    return uri.replace(scheme: 'https');
  }

  static ContentRef parse(String input) {
    final trimmed = input.trim();
    final uri = extractUrl(trimmed);
    var text = trimmed;
    var page = 1;
    if (uri != null) {
      if (!isBiliHost(uri.host.toLowerCase())) {
        throw const BiliException('请粘贴 bilibili.com 视频链接或 b23.tv 分享链接。');
      }
      text = uri.path;
      page = int.tryParse(uri.queryParameters['p'] ?? '') ?? 1;
      if (page < 1) throw const BiliException('分 P 编号必须大于 0。');
      if (uri.queryParameters['bvid'] case final String bvid) text = bvid;
    }
    final bvid = RegExp(
      r'(?:^|/)BV[0-9A-Za-z]{10}(?=$|/)',
      caseSensitive: true,
    ).firstMatch(text);
    if (bvid != null) {
      return ContentRef(
        ContentKind.video,
        bvid.group(0)!.replaceAll('/', ''),
        page: page,
      );
    }
    final id = RegExp(
      r'(?:^|/)(av|ep|ss|md)(\d+)(?=$|/)',
      caseSensitive: false,
    ).firstMatch(text);
    if (id == null || int.parse(id.group(2)!) < 1) {
      throw const BiliException('未识别到视频编号，支持 BV、AV、ep、ss、md 和对应链接。');
    }
    final prefix = id.group(1)!.toLowerCase();
    return ContentRef(
      switch (prefix) {
        'av' => ContentKind.video,
        'ep' => ContentKind.episode,
        'ss' => ContentKind.season,
        _ => ContentKind.media,
      },
      prefix == 'av' ? 'av${id.group(2)}' : id.group(2)!,
      page: page,
    );
  }
}
