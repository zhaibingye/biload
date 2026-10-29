import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:biload/core/models.dart';
import 'package:biload/services/auth_controller.dart';

const samplePage = MediaPage(
  ref: ContentRef(ContentKind.video, 'BV17x411w7KC'),
  cid: 279786,
  aid: 170001,
  bvid: 'BV17x411w7KC',
  title: '山与海之间，一段值得收藏的旅程',
  part: '穿过森林，去看海',
  index: 1,
  duration: 120,
);

Json sampleStreams() => {
  'quality': 80,
  'support_formats': [
    {'quality': 120, 'new_description': '4K 超清'},
    {'quality': 80, 'new_description': '1080P 高清'},
  ],
  'dash': {
    'video': [
      for (final codec in [7, 12, 13])
        {
          'id': 80,
          'codecid': codec,
          'codecs': codec == 7
              ? 'avc1.640028'
              : codec == 12
              ? 'hev1.1.6.L120.90'
              : 'av01.0.08M.08',
          'bandwidth': 1000000 + codec,
          'width': 1920,
          'height': 1080,
          'frame_rate': '30000/1001',
          'base_url': 'https://example.bilivideo.com/$codec.m4s?deadline=123',
          'backup_url': ['https://backup.bilivideo.cn/$codec.m4s'],
        },
    ],
    'audio': [
      {
        'id': 30280,
        'codecs': 'mp4a.40.2',
        'bandwidth': 192000,
        'baseUrl': 'https://example.bilivideo.com/audio.m4s',
      },
    ],
    'dolby': {
      'audio': [
        {
          'id': 30250,
          'codecs': 'ec-3',
          'bandwidth': 448000,
          'baseUrl': 'https://example.bilivideo.com/dolby.m4s',
        },
      ],
    },
    'flac': {
      'audio': {
        'id': 30251,
        'codecs': 'fLaC',
        'bandwidth': 1000000,
        'baseUrl': 'https://example.bilivideo.com/flac.m4s',
      },
    },
  },
};

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Json Function(RequestOptions) handler;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(handler(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Json navFixture() => {
  'code': -101,
  'data': {
    'isLogin': false,
    'wbi_img': {
      'img_url':
          'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
      'sub_url':
          'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
    },
  },
};

class MemoryVault implements SessionVault {
  String? encoded;
  @override
  Future<void> clear() async {
    encoded = null;
  }

  @override
  Future<String?> read() async => encoded;
  @override
  Future<void> write(String value) async {
    encoded = value;
  }
}

class FakeListenable extends ChangeNotifier {}
