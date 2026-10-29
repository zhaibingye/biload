import 'package:biload/services/byte_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown remaining resource size never produces a false percentage', () {
    final progress = ByteProgress([900, null]);
    progress.update(0, 0.5);
    expect(progress.downloadedBytes, 450);
    expect(progress.totalBytes, isNull);
    expect(progress.fraction, isNull);
    progress.complete(0, 900);
    progress.update(1, 0.5, expectedSize: 100);
    expect(progress.totalBytes, 1000);
    expect(progress.downloadedBytes, 950);
    expect(progress.fraction, 0.95);
  });
  test(
    'cached completed bytes are counted once when an active transfer resumes',
    () {
      final progress = ByteProgress([900, 100]);
      progress.complete(0, 900);
      progress.complete(0, 900);
      progress.update(1, 0.4);
      progress.update(1, 0.4);
      expect(progress.downloadedBytes, 940);
      expect(progress.fraction, 0.94);
      progress.complete(1, 100);
      expect(progress.fraction, 1);
    },
  );
  test('invalid native status sentinels cannot turn into downloaded bytes', () {
    final progress = ByteProgress([100]);
    progress.update(0, 0.3);
    progress.update(0, -1);
    progress.update(0, 2);
    expect(progress.downloadedBytes, 30);
    expect(progress.fraction, 0.3);
  });
}
