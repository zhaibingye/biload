import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';

Future<void> main(List<String> args) async {
  final api = BiliApi();
  final report = <String, dynamic>{
    'testedAt': DateTime.now().toUtc().toIso8601String(),
    'authenticated': false,
    'scope': 'public samples only',
    'results': <Json>[],
  };
  final results = report['results'] as List<Json>;
  Future<void> probe(String name, Future<Json> Function() run) async {
    try {
      final result = {'probe': name, 'ok': true, ...await run()};
      results.add(result);
      stdout.writeln(jsonEncode(result));
    } catch (e) {
      final result = {
        'probe': name,
        'ok': false,
        'error': e is BiliException ? e.message : e.runtimeType.toString(),
      };
      results.add(result);
      stdout.writeln(jsonEncode(result));
    }
  }

  await probe('qrcode.generate-and-poll', () async {
    final qr = await api.createQr();
    return {'keyLength': qr.key.length, 'pollState': await api.pollQr(qr)};
  });
  await probe('password.key', () async {
    final j = object(
      (await api.request(
        'https://passport.bilibili.com/x/passport-login/web/key',
      ))['data'],
    );
    return {
      'hasRsaKey': string(j['key']).contains('PUBLIC KEY'),
      'saltLength': string(j['hash']).length,
    };
  });
  await probe('captcha.parameters', () async {
    final j = object(
      (await api.request(
        'https://passport.bilibili.com/x/passport-login/captcha',
        query: {'source': 'main_web'},
      ))['data'],
    );
    return {'type': j['type'], 'hasToken': string(j['token']).isNotEmpty};
  });
  await probe('sms.country-list', () async {
    final j = object(
      (await api.request(
        'https://passport.bilibili.com/web/generic/country/list',
      ))['data'],
    );
    return {'commonCountries': objects(j['common']).length};
  });
  for (final input
      in args.isEmpty ? ['BV17x411w7KC', 'ep508404', 'md28237119'] : args) {
    await probe('content:$input', () async {
      final ref = await api.resolveLink(input);
      final content = await api.content(ref);
      final page = content.pages[content.preferredPage];
      final catalog = await api.catalog(page);
      final result = <String, dynamic>{
        'title': content.title,
        'pages': content.pages.length,
        'videos': [
          for (final v in catalog.videos)
            {'quality': v.quality, 'codec': v.codec, 'bandwidth': v.bandwidth},
        ],
        'audios': [
          for (final a in catalog.audios)
            {'id': a.id, 'codecs': a.codecs, 'language': a.language},
        ],
        'unavailable': [for (final f in catalog.unavailable) f.quality],
        'warnings': catalog.warnings,
      };
      if (catalog.videos.isNotEmpty) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        try {
          final request = await client.getUrl(
            Uri.parse(catalog.videos.first.sources.first.urls.first),
          );
          request.headers.set('User-Agent', BiliApi.userAgent);
          request.headers.set('Referer', page.webUrl);
          request.headers.set('Range', 'bytes=0-1023');
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          var received = 0;
          await for (final chunk in response.timeout(
            const Duration(seconds: 20),
          )) {
            received += min(1024 - received, chunk.length);
            if (received >= 1024) break;
          }
          result['range'] = {
            'status': response.statusCode,
            'contentRange': response.headers.value('content-range'),
            'bytesRead': received,
          };
        } finally {
          client.close(force: true);
        }
      }
      return result;
    });
  }
  await Directory('docs').create(recursive: true);
  await File('docs/api-verification.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  if (results.any((r) => r['ok'] != true)) exitCode = 1;
}
