import 'dart:typed_data';

import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

class SizeAdapter implements HttpClientAdapter {
  SizeAdapter(this.response);
  final ResponseBody Function(RequestOptions) response;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return response(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const source = StreamSource(['https://example.bilivideo.com/video.m4s']);
  test('CDN HEAD gives full size without sending account cookies', () async {
    final adapter = SizeAdapter(
      (_) => ResponseBody.fromString(
        '',
        200,
        headers: {
          'content-length': ['900'],
        },
      ),
    );
    final api = BiliApi(
      dio: Dio()..httpClientAdapter = adapter,
      session: BiliSession(cookies: {'SESSDATA': 'fixture-cookie'}),
    );
    expect(await api.resourceSize(source, samplePage), 900);
    expect(adapter.requests.single.method, 'HEAD');
    expect(
      adapter.requests.single.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('cookie')),
    );
  });
  test('one-byte range fallback uses total Content-Range instead of response length', () async {
    final adapter = SizeAdapter(
      (options) => options.method == 'HEAD'
          ? ResponseBody.fromString('', 405)
          : ResponseBody.fromBytes(
              [1],
              206,
              headers: {
                'content-range': ['bytes 0-0/1000'],
                'content-length': ['1'],
              },
            ),
    );
    final api = BiliApi(dio: Dio()..httpClientAdapter = adapter);
    expect(await api.resourceSize(source, samplePage), 1000);
    expect(adapter.requests.last.headers['Range'], 'bytes=0-0');
  });
  test('known source sizes avoid additional requests', () async {
    final adapter = SizeAdapter((_) => throw StateError('unexpected request'));
    final api = BiliApi(dio: Dio()..httpClientAdapter = adapter);
    expect(
      await api.resourceSize(const StreamSource([], size: 123), samplePage),
      123,
    );
    expect(adapter.requests, isEmpty);
  });
  test('size probes reject unrelated media hosts', () async {
    final adapter = SizeAdapter((_) => throw StateError('unexpected request'));
    final api = BiliApi(dio: Dio()..httpClientAdapter = adapter);
    expect(
      await api.resourceSize(
        const StreamSource(['https://example.com/video']),
        samplePage,
      ),
      isNull,
    );
    expect(adapter.requests, isEmpty);
  });
}
