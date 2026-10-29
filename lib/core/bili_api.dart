import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';

import 'link_parser.dart';
import 'models.dart';
import 'wbi.dart';

class BiliApi {
  BiliApi({Dio? dio, BiliSession? session})
    : http =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              followRedirects: false,
            ),
          ),
      session = session ?? BiliSession();

  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  final Dio http;
  BiliSession session;
  String? _imgKey;
  String? _subKey;
  DateTime? _keyTime;

  Map<String, String> _headers(Uri uri) => {
    'User-Agent': userAgent,
    'Referer': 'https://www.bilibili.com/',
    if (uri.scheme == 'https' && LinkParser.isBiliHost(uri.host))
      'Cookie': session.cookieHeader,
  };

  void _acceptCookies(Response<dynamic> response) {
    if (!LinkParser.isBiliHost(response.realUri.host)) return;
    for (final header in response.headers['set-cookie'] ?? <String>[]) {
      final pair = header.split(';').first;
      final i = pair.indexOf('=');
      if (i > 0) {
        session.cookies[pair.substring(0, i).trim()] = pair
            .substring(i + 1)
            .trim();
      }
    }
  }

  Future<Json> request(
    String endpoint, {
    Map<String, Object>? query,
    Map<String, Object>? form,
    bool allowNotLoggedIn = false,
  }) async {
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'https' || !LinkParser.isBiliHost(uri.host)) {
      throw const BiliException('已阻止向非 B 站接口发送账号信息。');
    }
    try {
      final response = await http.request<dynamic>(
        endpoint,
        queryParameters: query,
        data: form,
        options: Options(
          method: form == null ? 'GET' : 'POST',
          headers: _headers(uri),
          contentType: form == null ? null : Headers.formUrlEncodedContentType,
        ),
      );
      _acceptCookies(response);
      final json = object(
        response.data is String ? jsonDecode(response.data) : response.data,
      );
      if (!json.containsKey('code')) throw const BiliException('接口返回了无法识别的数据。');
      final code = integer(json['code']);
      if (code != 0 && !(allowNotLoggedIn && code == -101)) {
        throw BiliException(switch (code) {
          -101 => '登录已失效，请重新登录。',
          -352 || -412 => 'B 站要求安全验证，请稍后重试或通过网页登录完成验证。',
          -404 => '内容不存在或已被删除。',
          -10403 || 10015002 => '当前账号没有此内容的访问权限，或内容受地区限制。',
          _ => 'B 站返回错误 $code：${string(json['message'], '请求未成功')}',
        }, code: code);
      }
      return json;
    } on DioException catch (e) {
      throw BiliException(switch (e.response?.statusCode) {
        403 || 412 || 429 => '请求受到限制，请降低请求频率或完成网页登录验证。',
        _ => '网络请求失败，请检查连接后重试。',
      }, code: e.response?.statusCode);
    } on FormatException {
      throw const BiliException('接口返回内容异常，可能需要先完成安全验证。');
    }
  }

  Future<Json> _nav() => request(
    'https://api.bilibili.com/x/web-interface/nav',
    allowNotLoggedIn: true,
  );

  Future<AccountInfo?> account() async {
    final nav = await _nav();
    final data = object(nav['data']);
    if (integer(nav['code']) == -101 || data['isLogin'] != true) return null;
    return AccountInfo(
      uid: integer(data['mid']),
      name: string(data['uname']),
      avatar: string(data['face']),
      vip: integer(data['vipStatus']) == 1,
    );
  }

  Future<Map<String, String>> _signed(
    Map<String, Object> parameters, {
    bool refresh = false,
  }) async {
    if (refresh ||
        _imgKey == null ||
        _subKey == null ||
        DateTime.now().difference(_keyTime ?? DateTime(1970)).inHours >= 6) {
      final data = object((await _nav())['data']);
      final images = object(data['wbi_img']);
      String key(Object? url) =>
          Uri.parse(string(url)).pathSegments.last.split('.').first;
      try {
        _imgKey = key(images['img_url']);
        _subKey = key(images['sub_url']);
        if (_imgKey!.length != 32 || _subKey!.length != 32) {
          throw const FormatException();
        }
        _keyTime = DateTime.now();
      } catch (_) {
        throw const BiliException('无法取得 WBI 签名参数，请稍后重试。');
      }
    }
    return Wbi.sign(parameters, _imgKey!, _subKey!);
  }

  Future<LoginQr> createQr() async {
    final j = object(
      (await request(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      ))['data'],
    );
    if (string(j['qrcode_key']).isEmpty || string(j['url']).isEmpty) {
      throw const BiliException('无法生成登录二维码。');
    }
    return LoginQr(string(j['qrcode_key']), string(j['url']));
  }

  Future<int> pollQr(LoginQr qr) async {
    final j = object(
      (await request(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
        query: {'qrcode_key': qr.key},
      ))['data'],
    );
    final status = integer(j['code'], -1);
    if (status == 0) {
      session.refreshToken = string(j['refresh_token']);
      if (!session.hasLogin) throw const BiliException('登录响应中缺少会话凭据，请重新扫码。');
    }
    return status;
  }

  Future<bool> refreshSession(Future<void> Function() persist) async {
    if (!session.hasLogin) return false;
    final info = object(
      (await request(
        'https://passport.bilibili.com/x/passport-login/web/cookie/info',
        query: {'csrf': session.cookies['bili_jct'] ?? ''},
      ))['data'],
    );
    if (info['refresh'] != true) return false;
    if (session.refreshToken.isEmpty) {
      throw const BiliException('当前登录缺少刷新凭据，请通过扫码或网页登录更新会话。');
    }
    final path = correspondPath(
      integer(info['timestamp'], DateTime.now().millisecondsSinceEpoch),
    );
    final uri = Uri.parse('https://www.bilibili.com/correspond/1/$path');
    final Response<String> response;
    try {
      response = await http.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: _headers(uri),
        ),
      );
    } on DioException {
      throw const BiliException('登录刷新验证未成功，请重新登录。');
    }
    final match = RegExp(r'''<div\s+id=["']1-name["'][^>]*>([^<]+)</div>''')
        .firstMatch(response.data ?? '');
    if (match == null) throw const BiliException('登录刷新口令缺失，请重新登录。');
    final oldToken = session.refreshToken;
    final data = object(
      (await request(
        'https://passport.bilibili.com/x/passport-login/web/cookie/refresh',
        form: {
          'csrf': session.cookies['bili_jct'] ?? '',
          'refresh_csrf': match.group(1)!,
          'source': 'main_web',
          'refresh_token': oldToken,
        },
      ))['data'],
    );
    final newToken = string(data['refresh_token']);
    if (newToken.isEmpty) throw const BiliException('刷新响应缺少凭据，请重新登录。');
    session.refreshToken = newToken;
    // Persist the new pair before invalidating the old one.
    await persist();
    await request(
      'https://passport.bilibili.com/x/passport-login/web/confirm/refresh',
      form: {
        'csrf': session.cookies['bili_jct'] ?? '',
        'refresh_token': oldToken,
      },
    );
    return true;
  }

  static String correspondPath(int timestamp) {
    const pem =
        '-----BEGIN PUBLIC KEY-----\n'
        'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLgd2OAkcGVtoE3ThUREbio0Eg\n'
        'Uc/prcajMKXvkCKFCWhJYJcLkcM2DKKcSeFpD/j6Boy538YXnR6VhcuUJOhH2x71\n'
        'nzPjfdTcqMz7djHum0qSZA0AyCBDABUqCrfNgCiJ00Ra7GmRj+YCK1NJEuewlb40\n'
        'JNrRuoEUXpabUzGB8QIDAQAB\n-----END PUBLIC KEY-----';
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(
            List.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    final engine = OAEPEncoding.withSHA256(RSAEngine())
      ..init(
        true,
        ParametersWithRandom(
          PublicKeyParameter<RSAPublicKey>(
            CryptoUtils.rsaPublicKeyFromPem(pem),
          ),
          random,
        ),
      );
    return engine
        .process(Uint8List.fromList(utf8.encode('refresh_$timestamp')))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<ContentRef> resolveLink(String input) async {
    var uri = LinkParser.extractUrl(input);
    if (uri == null || !LinkParser.isShortHost(uri.host)) {
      return LinkParser.parse(input);
    }
    final shortClient = Dio(
      BaseOptions(
        followRedirects: false,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      for (var i = 0; i < 5; i++) {
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            !(LinkParser.isShortHost(uri.host) ||
                LinkParser.isBiliHost(uri.host))) {
          throw const BiliException('分享链接跳转到了不支持的网站。');
        }
        if (LinkParser.isBiliHost(uri.host)) {
          return LinkParser.parse(uri.toString());
        }
        final response = await shortClient.get<dynamic>(
          uri.toString(),
          options: Options(
            responseType: ResponseType.plain,
            headers: {'User-Agent': userAgent},
            validateStatus: (code) => code != null && code >= 200 && code < 400,
          ),
        );
        final location = response.headers.value('location');
        if (location == null) throw const BiliException('分享链接未返回视频地址。');
        uri = uri.resolve(location);
      }
      throw const BiliException('分享链接跳转次数过多。');
    } on DioException {
      throw const BiliException('无法展开分享链接，请尝试粘贴完整视频地址。');
    } finally {
      shortClient.close();
    }
  }

  Future<MediaContent> content(ContentRef ref) async {
    if (ref.kind == ContentKind.video) {
      final j = object(
        (await request(
          'https://api.bilibili.com/x/web-interface/view',
          query: ref.id.startsWith('BV')
              ? {'bvid': ref.id}
              : {'aid': ref.id.substring(2)},
        ))['data'],
      );
      final pages = objects(j['pages']);
      final bvid = string(j['bvid']);
      final title = string(j['title']);
      if (pages.isEmpty) throw const BiliException('视频没有可解析的分 P。');
      if (ref.page > pages.length) {
        throw BiliException('此视频只有 ${pages.length} 个分 P。');
      }
      return MediaContent(
        title: title,
        author: string(object(j['owner'])['name']),
        cover: string(j['pic']),
        preferredPage: ref.page - 1,
        pages: pages
            .asMap()
            .entries
            .map(
              (entry) => MediaPage(
                ref: ContentRef(ContentKind.video, bvid, page: entry.key + 1),
                cid: integer(entry.value['cid']),
                aid: integer(j['aid']),
                bvid: bvid,
                title: title,
                part: string(entry.value['part']),
                index: entry.key + 1,
                duration: integer(entry.value['duration']),
                cover: string(j['pic']),
              ),
            )
            .toList(),
      );
    }
    var id = ref.id;
    if (ref.kind == ContentKind.media) {
      final review = object(
        (await request(
          'https://api.bilibili.com/pgc/review/user',
          query: {'media_id': id},
        ))['result'],
      );
      id = string(object(review['media'])['season_id']);
      if (id.isEmpty || id == '0') throw const BiliException('无法取得此影视的剧集编号。');
    }
    final data = object(
      (await request(
        'https://api.bilibili.com/pgc/view/web/season',
        query: ref.kind == ContentKind.episode
            ? {'ep_id': id}
            : {'season_id': id},
      ))['result'],
    );
    final episodes = [
      ...objects(data['episodes']),
      for (final section in objects(data['section']))
        ...objects(section['episodes']),
    ];
    final seen = <int>{};
    final pages = <MediaPage>[];
    for (final e in episodes) {
      final epid = integer(e['id']);
      if (epid < 1 || !seen.add(epid) || integer(e['cid']) == 0) continue;
      pages.add(
        MediaPage(
          ref: ContentRef(ContentKind.episode, '$epid'),
          cid: integer(e['cid']),
          aid: integer(e['aid']),
          bvid: string(e['bvid']),
          title: string(data['title']),
          part: [
            string(e['title']),
            string(e['long_title']),
          ].where((s) => s.isNotEmpty).join(' · '),
          index: pages.length + 1,
          duration: integer(e['duration']) ~/ 1000,
          epid: epid,
          cover: string(e['cover'], string(data['cover'])),
        ),
      );
    }
    if (pages.isEmpty) throw const BiliException('剧集暂未提供可解析的分集。');
    final preferred = ref.kind == ContentKind.episode
        ? pages.indexWhere((e) => '${e.epid}' == ref.id)
        : 0;
    return MediaContent(
      title: string(data['title']),
      author: '番剧 / 影视',
      cover: string(data['cover']),
      pages: pages,
      preferredPage: max(0, preferred),
    );
  }

  Future<Json> _play(
    MediaPage page, {
    int quality = 127,
    String language = '',
    bool refreshKey = false,
  }) async {
    final parameters = <String, Object>{
      'cid': page.cid,
      'qn': quality,
      'fnval': 4048,
      'fnver': 0,
      'fourk': 1,
      'from_client': 'BROWSER',
      if (language.isNotEmpty) 'cur_language': language,
      if (page.isPgc) 'ep_id': page.epid! else 'bvid': page.bvid,
    };
    final result = await request(
      page.isPgc
          ? 'https://api.bilibili.com/pgc/player/web/playurl'
          : 'https://api.bilibili.com/x/player/wbi/playurl',
      query: page.isPgc
          ? parameters
          : await _signed(parameters, refresh: refreshKey),
    );
    final data = object(result[page.isPgc ? 'result' : 'data']);
    if (data['v_voucher'] != null) {
      if (!refreshKey && !page.isPgc) {
        return _play(
          page,
          quality: quality,
          language: language,
          refreshKey: true,
        );
      }
      throw const BiliException('B 站要求安全验证，请通过网页登录完成验证后重试。');
    }
    if (data['is_drm'] == true || integer(data['is_drm']) == 1) {
      throw const BiliException('此内容使用 DRM 加密，当前无法保存为普通视频文件。');
    }
    if (integer(data['is_preview']) == 1 || data['is_preview'] == true) {
      throw const BiliException('当前返回的是试看内容，请确认账号拥有完整观看权限。');
    }
    return data;
  }

  Future<StreamCatalog> catalog(MediaPage page) async {
    final initial = await _play(page);
    final videoMap = <String, VideoVariant>{};
    final audioMap = <String, AudioVariant>{};
    final formats = <int, String>{};
    final warnings = <String>[];
    void collect(Json data, {String language = '', String languageTitle = ''}) {
      final parsed = parseStreams(
        data,
        language: language,
        languageTitle: languageTitle,
      );
      for (final video in parsed.videos) {
        videoMap[video.key] = video;
      }
      for (final audio in parsed.audios) {
        audioMap[audio.key] = audio;
      }
      for (final format in objects(data['support_formats'])) {
        final qn = integer(format['quality']);
        formats[qn] = string(format['new_description'], qualityName(qn));
      }
    }

    collect(initial);
    final missing = formats.keys
        .where((q) => !videoMap.values.any((v) => v.quality == q))
        .toList();
    for (final quality in missing) {
      try {
        collect(await _play(page, quality: quality));
      } on BiliException catch (e) {
        if ({-101, -352, -412, 403, 412, 429}.contains(e.code)) rethrow;
        warnings.add('${qualityName(quality)}：${e.message}');
      }
    }
    for (final language in objects(object(initial['language'])['items'])) {
      final code = string(language['lang']);
      if (code.isEmpty) continue;
      try {
        final data = await _play(page, language: code);
        if (string(data['cur_language']) != code) {
          warnings.add('$code 音轨没有返回对应语言，已跳过。');
          continue;
        }
        collect(
          data,
          language: code,
          languageTitle: string(language['title'], code),
        );
      } on BiliException catch (e) {
        if ({-101, -352, -412, 403, 412, 429}.contains(e.code)) rethrow;
        warnings.add('$code 音轨：${e.message}');
      }
    }
    if (videoMap.isEmpty && audioMap.isEmpty) {
      throw const BiliException('未取得可下载的完整音视频流。');
    }
    final videos = videoMap.values.toList()
      ..sort((a, b) {
        final q = b.quality.compareTo(a.quality);
        return q != 0 ? q : a.codec.compareTo(b.codec);
      });
    final audios = audioMap.values.toList()
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return StreamCatalog(
      videos: videos,
      audios: audios,
      warnings: warnings,
      unavailable: [
        for (final entry in formats.entries)
          if (!videos.any((video) => video.quality == entry.key))
            UnavailableFormat(
              entry.key,
              entry.value,
              session.hasLogin
                  ? '接口未提供可下载流，可能需要额外权限或客户端接口支持'
                  : '尚未取得可下载流，可登录后重新解析',
            ),
      ],
    );
  }

  static bool isMediaUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    return [
      'acgvideo.com',
      'bilivideo.com',
      'bilivideo.cn',
      'hdslb.com',
      'bilibili.com',
    ].any((domain) => uri.host == domain || uri.host.endsWith('.$domain'));
  }

  Future<int?> resourceSize(StreamSource source, MediaPage page) async {
    if (source.size > 0) return source.size;
    for (final url in source.urls) {
      if (!isMediaUrl(url)) continue;
      final headers = <String, String>{
        'User-Agent': userAgent,
        'Referer': page.webUrl,
        'Accept-Encoding': 'identity',
      };
      try {
        final response = await http.head<void>(
          url,
          options: Options(
            headers: headers,
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        final length = int.tryParse(
          response.headers.value('content-length') ?? '',
        );
        if (length != null && length > 0) return length;
      } on DioException {
        /* Some CDNs don't accept HEAD. */
      }
      final cancel = CancelToken();
      try {
        final response = await http.get<ResponseBody>(
          url,
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            headers: {...headers, 'Range': 'bytes=0-0'},
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (s) => s == 200 || s == 206,
          ),
        );
        final range = RegExp(r'/([0-9]+)$')
            .firstMatch(response.headers.value('content-range') ?? '');
        final length = int.tryParse(
          response.statusCode == 206
              ? range?.group(1) ?? ''
              : response.headers.value('content-length') ?? '',
        );
        await response.data?.stream.listen((_) {}).cancel();
        if (length != null && length > 0) return length;
      } on DioException {
        /* Native transfer headers can still provide a size. */
      } finally {
        cancel.cancel();
      }
    }
    return null;
  }

  static StreamCatalog parseStreams(
    Json data, {
    String language = '',
    String languageTitle = '',
  }) {
    StreamSource source(Json item) {
      final urls =
          <String>{
                string(item['baseUrl'] ?? item['base_url'] ?? item['url']),
                ...((item['backupUrl'] ?? item['backup_url'] ?? []) as List)
                    .map(string),
              }
              .where((s) => s.isNotEmpty && isMediaUrl(s))
              .map((s) => Uri.parse(s).replace(scheme: 'https').toString())
              .toList();
      if (urls.isEmpty) throw const BiliException('视频流域名未被识别，已停止下载。');
      return StreamSource(urls, size: integer(item['size']));
    }

    final dash = object(data['dash']);
    final videos = [
      for (final item in objects(dash['video']))
        VideoVariant(
          quality: integer(item['id']),
          codec: integer(item['codecid']),
          codecs: string(item['codecs']),
          bandwidth: integer(item['bandwidth']),
          width: integer(item['width']),
          height: integer(item['height']),
          frameRate: string(item['frameRate'] ?? item['frame_rate']),
          sources: [source(item)],
        ),
    ];
    final durl = objects(data['durl']);
    if (durl.isNotEmpty) {
      videos.add(
        VideoVariant(
          quality: integer(data['quality']),
          codec: integer(data['video_codecid'], 7),
          codecs: 'progressive',
          bandwidth: 0,
          width: 0,
          height: 0,
          frameRate: '',
          sources: durl.map(source).toList(),
          progressive: true,
        ),
      );
    }
    final audioItems = [
      ...objects(dash['audio']),
      ...objects(object(dash['dolby'])['audio']),
      if (object(object(dash['flac'])['audio']).isNotEmpty)
        object(object(dash['flac'])['audio']),
    ];
    final audios = [
      for (final item in audioItems)
        AudioVariant(
          id: integer(item['id']),
          codecs: string(item['codecs']),
          bandwidth: integer(item['bandwidth']),
          sources: [source(item)],
          language: language,
          languageTitle: languageTitle,
        ),
    ];
    return StreamCatalog(videos: videos, audios: audios);
  }
}
