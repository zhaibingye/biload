import 'dart:convert';
import 'dart:io';

import 'package:biload/core/bili_api.dart';
import 'package:biload/core/link_parser.dart';
import 'package:biload/core/models.dart';
import 'package:biload/core/wbi.dart';
import 'package:biload/data/local_store.dart';
import 'package:biload/services/muxer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('链接与签名', () {
    test('WBI matches independent documented vector', () {
      final signed = Wbi.sign(
        {'foo': 114, 'bar': 514, 'zab': 1919810},
        '7cd084941338484aae1ad9425b84077c',
        '4932caff0ff746eab6f01bf08b70ac45',
        timestamp: 1702204169,
      );
      expect(signed['w_rid'], '8f6f2b5b3d485fe1886cec6a0be8c5d4');
      expect(signed['wts'], '1702204169');
    });
    test('supports shared text, page selection and episode ids', () {
      final ref = LinkParser.parse(
        '分享一个视频 https://www.bilibili.com/video/BV17x411w7KC/?p=3&share_source=copy，',
      );
      expect(ref.id, 'BV17x411w7KC');
      expect(ref.page, 3);
      expect(LinkParser.parse('av170001').kind, ContentKind.video);
      expect(LinkParser.parse('ep508404').kind, ContentKind.episode);
      expect(
        LinkParser.parse('https://www.bilibili.com/bangumi/media/md123').kind,
        ContentKind.media,
      );
    });
    test('rejects deceptive domains and malformed ids', () {
      for (final input in [
        'https://bilibili.com.evil.test/video/BV17x411w7KC',
        'https://bilibili.com@evil.test/video/BV17x411w7KC',
        'BV17x411w7KCjunk',
        'ep0',
        'https://www.bilibili.com/video/BV17x411w7KC?p=0',
      ]) {
        expect(
          () => LinkParser.parse(input),
          throwsA(isA<BiliException>()),
          reason: input,
        );
      }
    });
    test('filenames cannot escape a directory or use Windows device names', () {
      expect(safeFilename('../../CON:video|name?'), '.._.._CON_video_name_');
      expect(safeFilename('CON'), '_CON');
      expect(safeFilename('...'), 'biload');
      expect(
        utf8.encode(safeFilename('海' * 200)).length,
        lessThanOrEqualTo(150),
      );
    });
  });

  group('流归一化', () {
    test('preserves codecs, Dolby, lossless and language identity', () {
      final result = BiliApi.parseStreams(
        sampleStreams(),
        language: 'ja',
        languageTitle: '日语',
      );
      expect(result.videos.map((v) => v.codec), [7, 12, 13]);
      expect(result.videos.first.sources.single.urls.length, 2);
      expect(result.audios.map((a) => a.id), [30280, 30250, 30251]);
      expect(result.audios.every((a) => a.language == 'ja'), isTrue);
      expect(result.audios.map((a) => a.key).toSet().length, 3);
    });
    test('preserves progressive segments in order and absent audio', () {
      final result = BiliApi.parseStreams({
        'quality': 32,
        'video_codecid': 7,
        'durl': [
          {'url': 'https://one.bilivideo.com/first', 'size': 12},
          {'url': 'https://two.bilivideo.com/second', 'size': 24},
        ],
      });
      expect(result.videos.single.progressive, isTrue);
      expect(result.videos.single.sources.length, 2);
      expect(result.videos.single.estimateBytes(0), 36);
      expect(result.audios, isEmpty);
    });
    test('rejects unknown/local media hosts', () {
      for (final url in [
        'http://127.0.0.1/secret',
        'file:///etc/passwd',
        'https://bilivideo.com.evil.test/a',
      ]) {
        expect(BiliApi.isMediaUrl(url), isFalse);
      }
    });
  });

  group('API semantics', () {
    test('declared quality without an actual stream is unavailable', () async {
      final adapter = FakeAdapter(
        (options) => options.path.endsWith('/nav')
            ? navFixture()
            : {'code': 0, 'data': sampleStreams()},
      );
      final api = BiliApi(dio: Dio()..httpClientAdapter = adapter);
      final result = await api.catalog(samplePage);
      expect(result.videos.length, 3);
      expect(result.unavailable.single.quality, 120);
      expect(
        adapter.requests.where((r) => r.path.endsWith('playurl')).length,
        2,
      );
      expect(adapter.requests.last.queryParameters['w_rid'], isNotEmpty);
    });
    test('code zero with voucher is never accepted as a video', () async {
      final adapter = FakeAdapter(
        (options) => options.path.endsWith('/nav')
            ? navFixture()
            : {
                'code': 0,
                'data': {'v_voucher': 'voucher_redacted'},
              },
      );
      final api = BiliApi(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(api.catalog(samplePage), throwsA(isA<BiliException>()));
      expect(
        adapter.requests.where((r) => r.path.endsWith('playurl')).length,
        2,
      );
    });
    test('DRM and preview responses are rejected', () async {
      for (final flag in ['is_drm', 'is_preview']) {
        final adapter = FakeAdapter(
          (options) => options.path.endsWith('/nav')
              ? navFixture()
              : {
                  'code': 0,
                  'data': {flag: true, ...sampleStreams()},
                },
        );
        await expectLater(
          BiliApi(dio: Dio()..httpClientAdapter = adapter).catalog(samplePage),
          throwsA(isA<BiliException>()),
        );
      }
    });
    test(
      'refuses credentials to external endpoints before opening a connection',
      () async {
        final adapter = FakeAdapter((_) => {'code': 0});
        final api = BiliApi(
          dio: Dio()..httpClientAdapter = adapter,
          session: BiliSession(cookies: {'SESSDATA': 'private-test'}),
        );
        await expectLater(
          api.request('https://example.com/'),
          throwsA(isA<BiliException>()),
        );
        expect(adapter.requests, isEmpty);
      },
    );
    test('correspond token uses full-length randomized RSA-OAEP', () {
      final a = BiliApi.correspondPath(1700000000000);
      final b = BiliApi.correspondPath(1700000000000);
      expect(a, matches(RegExp(r'^[a-f0-9]{256}$')));
      expect(a, isNot(b));
    });
  });

  test(
    'SQLite survives reopen without persisting account credentials in jobs',
    () async {
      final directory = await Directory.systemTemp.createTemp('biload-store-');
      final path = '${directory.path}/state.sqlite';
      final first = LocalStore(path);
      final job = DownloadJob(
        id: 'job1',
        page: samplePage,
        videoKey: 'v80',
        audioKeys: ['a30280'],
        container: 'mkv',
        directory: directory.path,
        createdAt: DateTime.utc(2026, 10, 29),
        status: JobStatus.paused,
        progress: 0.45,
      );
      first.saveJob(job);
      first.setSetting('directory', directory.path);
      first.close();
      final second = LocalStore(path);
      expect(second.loadJobs().single.status, JobStatus.paused);
      expect(second.loadJobs().single.progress, 0.45);
      expect(second.setting('directory'), directory.path);
      expect(
        jsonEncode(second.loadJobs().single.toJson()),
        isNot(contains('SESSDATA')),
      );
      second.removeJob('job1');
      expect(second.loadJobs(), isEmpty);
      second.close();
      await directory.delete(recursive: true);
    },
  );

  test('mux arguments preserve streams, map all selected audio and handle spaces as single args', () {
    final audios = BiliApi.parseStreams(sampleStreams()).audios
        .take(2)
        .toList();
    final args = MediaMuxer.arguments(
      video: [const MuxInput('C:/路径 空格/video.m4s')],
      audio: ['C:/路径 空格/a.m4s', 'C:/路径 空格/b.m4s'],
      audioInfo: audios,
      output: 'C:/输出 目录/out.mkv',
      progressive: false,
    );
    expect(
      args,
      containsAllInOrder([
        '-map',
        '0:v:0',
        '-map',
        '1:a:0',
        '-map',
        '2:a:0',
        '-c',
        'copy',
      ]),
    );
    expect(args, contains('C:/路径 空格/video.m4s'));
    expect(args.last, 'C:/输出 目录/out.mkv');
    expect(args, isNot(contains('-c:v')));
  });

  test('progressive input retains embedded audio unless selected audio replaces it', () {
    final embedded = MediaMuxer.arguments(
      video: [const MuxInput('combined.mp4')],
      audio: [],
      audioInfo: [],
      output: 'out.mp4',
      progressive: true,
    );
    expect(embedded, contains('0:a?'));
    final replaced = MediaMuxer.arguments(
      video: [const MuxInput('combined.mp4')],
      audio: ['chosen.m4a'],
      audioInfo: [],
      output: 'out.mp4',
      progressive: true,
    );
    expect(replaced, contains('1:a:0'));
    expect(replaced, isNot(contains('0:a?')));
  });
}
