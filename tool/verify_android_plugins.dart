import 'dart:convert';
import 'dart:io';

List<String> requiredAndroidPlugins(
  Map<String, dynamic> metadata, {
  required bool release,
}) {
  final platforms = metadata['plugins'] as Map<String, dynamic>? ?? {};
  final android = platforms['android'] as List<dynamic>? ?? [];
  return [
    for (final plugin in android.cast<Map<String, dynamic>>())
      if (plugin['native_build'] == true &&
          (!release || plugin['dev_dependency'] != true))
        plugin['name'] as String,
  ];
}

List<String> missingAndroidPluginRegistrations(
  Map<String, dynamic> metadata,
  String registrant, {
  required bool release,
}) => [
  for (final name in requiredAndroidPlugins(metadata, release: release))
    if (!registrant.contains('Error registering plugin $name,')) name,
];

void main(List<String> arguments) {
  final release = !arguments.contains('--debug');
  final metadataFile = File('.flutter-plugins-dependencies');
  final registrantFile = File(
    'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
  );
  try {
    if (!metadataFile.existsSync() || !registrantFile.existsSync()) {
      throw StateError('Android native plugin registration files are missing.');
    }
    final metadata =
        jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
    final required = requiredAndroidPlugins(metadata, release: release);
    if (required.isEmpty) {
      throw StateError('No Android native plugins were discovered for biload.');
    }
    final missing = missingAndroidPluginRegistrations(
      metadata,
      registrantFile.readAsStringSync(),
      release: release,
    );
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing Android native plugin registrations: ${missing.join(', ')}.',
      );
    }
    stdout.writeln(
      'Android native plugin registration verified (${required.length} runtime plugins).',
    );
  } catch (error) {
    stderr.writeln(
      '$error\nComplete flutter pub get successfully before building.',
    );
    exitCode = 1;
  }
}
