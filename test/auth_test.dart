import 'dart:convert';
import 'dart:typed_data';

import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';
import 'package:biload/services/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class BrokenVault extends MemoryVault {
  @override
  Future<void> write(String value) async =>
      throw StateError('vault unavailable');
}

class RefreshAdapter implements HttpClientAdapter {
  RefreshAdapter(this.vault);
  final MemoryVault vault;
  bool confirmed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    var data = <String, dynamic>{};
    final headers = <String, List<String>>{
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    if (options.path.contains('/correspond/')) {
      return ResponseBody.fromString(
        '<div id="1-name">refresh-csrf-fixture</div>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );
    } else if (options.path.endsWith('/cookie/info')) {
      data = {
        'code': 0,
        'data': {
          'refresh': true,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      };
    } else if (options.path.endsWith('/cookie/refresh')) {
      data = {
        'code': 0,
        'data': {'refresh_token': 'new-refresh-token'},
      };
      headers['set-cookie'] = [
        'SESSDATA=new-session; Domain=.bilibili.com; Path=/',
        'bili_jct=new-csrf; Domain=.bilibili.com; Path=/',
      ];
    } else if (options.path.endsWith('/confirm/refresh')) {
      final saved = BiliSession.decode(vault.encoded!);
      expect(saved.cookies['SESSDATA'], 'new-session');
      expect(saved.refreshToken, 'new-refresh-token');
      expect(options.headers['Cookie'], contains('bili_jct=new-csrf'));
      expect((options.data as Map)['refresh_token'], 'old-refresh-token');
      confirmed = true;
      data = {'code': 0};
    }
    return ResponseBody.fromString(jsonEncode(data), 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('invalid login is never written to secure storage', () async {
    final vault = MemoryVault();
    final dio = Dio()..httpClientAdapter = FakeAdapter((_) => navFixture());
    final api = BiliApi(dio: dio);
    final auth = AuthController(api, vault);
    await expectLater(
      auth.adopt(BiliSession(cookies: {'SESSDATA': 'invalid'})),
      throwsA(isA<BiliException>()),
    );
    expect(vault.encoded, isNull);
    expect(api.session.hasLogin, isFalse);
  });
  test('failed secure write preserves the existing active account', () async {
    final dio = Dio()
      ..httpClientAdapter = FakeAdapter(
        (_) => {
          'code': 0,
          'data': {
            'isLogin': true,
            'mid': 123,
            'uname': 'test',
            'vipStatus': 1,
            'face': '',
          },
        },
      );
    final api = BiliApi(
      dio: dio,
      session: BiliSession(cookies: {'SESSDATA': 'old'}),
    );
    final auth = AuthController(api, BrokenVault());
    await expectLater(
      auth.adopt(BiliSession(cookies: {'SESSDATA': 'candidate'})),
      throwsA(isA<BiliException>()),
    );
    expect(api.session.cookies['SESSDATA'], 'old');
  });
  test('session refresh persists new cookie/token pair before confirming old pair invalidation', () async {
    final vault = MemoryVault();
    final adapter = RefreshAdapter(vault);
    final api = BiliApi(
      dio: Dio()..httpClientAdapter = adapter,
      session: BiliSession(
        cookies: {'SESSDATA': 'old-session', 'bili_jct': 'old-csrf'},
        refreshToken: 'old-refresh-token',
      ),
    );
    expect(
      await api.refreshSession(() => vault.write(api.session.encode())),
      isTrue,
    );
    expect(adapter.confirmed, isTrue);
  });
  test(
    'cookie import preserves encoded values and filters header injection',
    () {
      final session = BiliSession.fromCookieHeader(
        'SESSDATA=a%2Cb%3Dc; bili_jct=abc',
      );
      expect(session.cookies['SESSDATA'], 'a%2Cb%3Dc');
      session.cookies['bad\r\nheader'] = 'value';
      expect(session.cookieHeader, isNot(contains('\r')));
    },
  );
}
