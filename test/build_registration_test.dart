import 'dart:io';

import 'package:biload/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_android_plugins.dart';

void main() {
  test('displayed release version matches the package version', () {
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(version, '$appVersion+$releaseBuildNumber');
  });
  final metadata = <String, dynamic>{
    'plugins': {
      'android': [
        {'name': 'jni', 'native_build': true, 'dev_dependency': false},
        {'name': 'jni_flutter', 'native_build': true, 'dev_dependency': false},
        {
          'name': 'path_provider_android',
          'native_build': false,
          'dev_dependency': false,
        },
        {
          'name': 'integration_test',
          'native_build': true,
          'dev_dependency': true,
        },
      ],
    },
  };
  const runtimeRegistrations = '''
    flutterEngine.getPlugins().add(new com.github.dart_lang.jni.JniPlugin());
    Log.e(TAG, "Error registering plugin jni, com.github.dart_lang.jni.JniPlugin", e);
    flutterEngine.getPlugins().add(new com.github.dart_lang.jni_flutter.JniFlutterPlugin());
    Log.e(TAG, "Error registering plugin jni_flutter, com.github.dart_lang.jni_flutter.JniFlutterPlugin", e);
  ''';

  test(
    'rejects the empty generated registrant that caused the startup crash',
    () {
      expect(
        missingAndroidPluginRegistrations(
          metadata,
          'public static void registerWith(FlutterEngine flutterEngine) {}',
          release: true,
        ),
        ['jni', 'jni_flutter'],
      );
    },
  );
  test('accepts complete runtime registration without Dart-only or dev-only entries', () {
    expect(
      missingAndroidPluginRegistrations(
        metadata,
        runtimeRegistrations,
        release: true,
      ),
      isEmpty,
    );
  });
  test('debug builds also require native development plugins', () {
    expect(
      missingAndroidPluginRegistrations(
        metadata,
        runtimeRegistrations,
        release: false,
      ),
      ['integration_test'],
    );
  });
}
