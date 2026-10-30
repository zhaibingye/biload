import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../core/models.dart';

MediaInformation parseProbeOutput(String output) {
  final value = object(jsonDecode(output));
  final streams = value['streams'];
  if (streams is! List ||
      streams.isEmpty ||
      streams.any((stream) => stream is! Map) ||
      value['format'] is! Map) {
    throw const BiliException('无法读取完整的媒体轨道信息，原始流已保留。');
  }
  return MediaInformation(value);
}

Future<MediaInformation?> probeMedia(String path) async {
  if (!Platform.isLinux) {
    return (await FFprobeKit.getMediaInformation(path)).getMediaInformation();
  }
  // The Linux native MediaInformation bridge in 4.6.7 returns null entries in
  // streams. Read FFprobe's original JSON text instead of accepting broken
  // metadata or omitting the track checks.
  final session = await FFprobeKit.executeWithArguments([
    '-v',
    'error',
    '-hide_banner',
    '-print_format',
    'json',
    '-show_format',
    '-show_streams',
    '-show_chapters',
    '-i',
    path,
  ]);
  if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
  return parseProbeOutput(await session.getOutput() ?? '');
}
