import 'package:biload/core/models.dart';
import 'package:biload/services/media_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raw FFprobe JSON preserves separate video and audio tracks', () {
    final info = parseProbeOutput('''{"streams":[
      {"codec_type":"video","codec_name":"av1"},
      {"codec_type":"audio","codec_name":"aac"},
      {"codec_type":"audio","codec_name":"flac"}
    ],"format":{"duration":"2.0"}}''');
    expect(info.getStreams().map((s) => s.getType()), [
      'video',
      'audio',
      'audio',
    ]);
    expect(info.getDuration(), '2.0');
  });
  test('broken native null stream metadata cannot pass integrity checks', () {
    expect(
      () => parseProbeOutput(
        '{"streams":[null,null],"format":{"duration":"2.0"}}',
      ),
      throwsA(isA<BiliException>()),
    );
    expect(
      () => parseProbeOutput('{"streams":[],"format":{}}'),
      throwsA(isA<BiliException>()),
    );
  });
}
