import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../core/models.dart';
import 'media_probe.dart';

class MuxInput {
  const MuxInput(this.path, {this.concat = false});
  final String path;
  final bool concat;
}

class MediaMuxer {
  final Map<String, int> _sessions = {};

  static List<String> arguments({
    required List<MuxInput> video,
    required List<String> audio,
    required List<AudioVariant> audioInfo,
    required String output,
    required bool progressive,
  }) {
    final args = <String>['-hide_banner', '-nostdin', '-y', '-v', 'error'];
    for (final input in video) {
      if (input.concat) args.addAll(['-f', 'concat', '-safe', '0']);
      args.addAll(['-i', input.path]);
    }
    for (final input in audio) {
      args.addAll(['-i', input]);
    }
    if (video.isNotEmpty) {
      args.addAll(['-map', '0:v:0']);
      if (progressive && audio.isEmpty) args.addAll(['-map', '0:a?']);
    }
    for (var i = 0; i < audio.length; i++) {
      args.addAll(['-map', '${video.length + i}:a:0']);
    }
    args.addAll(['-c', 'copy']);
    for (var i = 0; i < audioInfo.length; i++) {
      args.addAll(['-metadata:s:a:$i', 'title=${audioInfo[i].label}']);
      final language = switch (audioInfo[i].language.split('-').first) {
        'en' => 'eng',
        'zh' => 'zho',
        'ja' => 'jpn',
        'ko' => 'kor',
        _ => 'und',
      };
      args.addAll(['-metadata:s:a:$i', 'language=$language']);
    }
    if (output.endsWith('.mp4') || output.endsWith('.m4a')) {
      args.addAll(['-movflags', '+faststart']);
    }
    return [...args, output];
  }

  Future<void> _execute(String job, List<String> args) async {
    final complete = Completer<ReturnCode?>();
    final session = await FFmpegKit.executeWithArgumentsAsync(args, (
      finished,
    ) async {
      complete.complete(await finished.getReturnCode());
    });
    final id = session.getSessionId();
    if (id != null) _sessions[job] = id;
    final code = await complete.future;
    _sessions.remove(job);
    if (ReturnCode.isCancel(code)) throw const BiliException('处理已取消。');
    if (!ReturnCode.isSuccess(code)) {
      throw const BiliException('音视频处理失败，原始流已保留。可尝试 MKV 容器后重试。');
    }
  }

  Future<void> mux({
    required DownloadJob job,
    required List<MuxInput> video,
    required List<String> audio,
    required List<AudioVariant> audioInfo,
    required String output,
    required bool progressive,
  }) async {
    await _execute(
      job.id,
      arguments(
        video: video,
        audio: audio,
        audioInfo: audioInfo,
        output: output,
        progressive: progressive,
      ),
    );
    final info = await probeMedia(output);
    if (info == null ||
        !await File(output).exists() ||
        await File(output).length() == 0) {
      throw const BiliException('输出文件未通过完整性检查，原始流已保留。');
    }
    final streams = info.getStreams();
    if (video.isNotEmpty && !streams.any((s) => s.getType() == 'video')) {
      throw const BiliException('输出文件缺少视频轨道。');
    }
    if (audio.length > streams.where((s) => s.getType() == 'audio').length) {
      throw const BiliException('输出文件缺少已选音轨。');
    }
    final duration = double.tryParse(info.getDuration() ?? '') ?? 0;
    final tolerance = job.page.duration * 0.02 > 8
        ? job.page.duration * 0.02
        : 8;
    if (duration <= 0 ||
        (job.page.duration > 0 && duration < job.page.duration - tolerance)) {
      throw const BiliException('输出时长异常，可能未取得完整内容，原始流已保留。');
    }
    await _execute(job.id, [
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      '-i',
      output,
      '-t',
      '1',
      '-f',
      'null',
      '-',
    ]);
  }

  Future<void> cancel(String id) async {
    final session = _sessions[id];
    if (session != null) await FFmpegKit.cancel(session);
  }
}
