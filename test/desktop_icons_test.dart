import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<void> checkBrandIcon(Uint8List bytes, int size) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  expect(image.width, size);
  expect(image.height, size);
  final rgba = (await image.toByteData())!;
  final background = (size * (size ~/ 3) + size ~/ 5) * 4;
  for (final (channel, value) in [24, 58, 50].indexed) {
    expect(rgba.getUint8(background + channel), closeTo(value, 12));
  }
  expect(rgba.getUint8(3), 0, reason: 'Rounded corners stay transparent');
  final center = (size * (size ~/ 2) + size ~/ 2) * 4;
  expect(rgba.getUint8(center), greaterThan(100));
  expect(rgba.getUint8(center + 1), greaterThan(150));
  image.dispose();
  codec.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every Windows ICO frame contains the biload brand', () async {
    final bytes = File('windows/runner/resources/app_icon.ico')
        .readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint16(2, Endian.little), 1);
    final count = data.getUint16(4, Endian.little);
    final sizes = <int>[];
    for (var i = 0; i < count; i++) {
      final entry = 6 + i * 16;
      final size = bytes[entry] == 0 ? 256 : bytes[entry];
      sizes.add(size);
      final length = data.getUint32(entry + 8, Endian.little);
      final offset = data.getUint32(entry + 12, Endian.little);
      await checkBrandIcon(
        Uint8List.sublistView(bytes, offset, offset + length),
        size,
      );
    }
    expect(sizes, containsAll([16, 24, 32, 48, 64, 128, 256]));
  });

  test(
    'all macOS AppIcon slots resolve to correctly sized brand images',
    () async {
      final directory = Directory(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset',
      );
      final manifest = jsonDecode(
        File('${directory.path}/Contents.json').readAsStringSync(),
      );
      for (final slot in manifest['images']) {
        final size =
            int.parse((slot['size'] as String).split('x').first) *
            int.parse((slot['scale'] as String).substring(0, 1));
        await checkBrandIcon(
          File('${directory.path}/${slot['filename']}').readAsBytesSync(),
          size,
        );
      }
    },
  );
}
