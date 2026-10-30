import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import 'auth_controller.dart';

/// Account files stay in user-data. Windows protects them for the current OS
/// user with DPAPI; Unix uses AES-GCM and an owner-only local key file.
class FileSessionVault implements SessionVault {
  FileSessionVault(String directory, {bool? isWindows, MethodChannel? channel})
    : file = File(p.join(directory, 'session.bin')),
      keyFile = File(p.join(directory, 'session.key')),
      isWindows = isWindows ?? Platform.isWindows,
      channel = channel ?? const MethodChannel('app.biload/platform');

  final File file;
  final File keyFile;
  final bool isWindows;
  final MethodChannel channel;

  Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<void> _ownerOnly(String path) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', ['600', path]);
    if (result.exitCode != 0) throw const FileSystemException('无法保护账号文件权限。');
  }

  Future<Uint8List> _crypt(Uint8List bytes, {required bool encrypt}) async {
    if (isWindows) {
      return (await channel.invokeMethod<Uint8List>(
        encrypt ? 'protectSession' : 'unprotectSession',
        bytes,
      ))!;
    }
    if (encrypt && !await keyFile.exists()) {
      await keyFile.writeAsBytes(_random(32), flush: true);
      await _ownerOnly(keyFile.path);
    }
    final key = await keyFile.readAsBytes();
    final nonce = encrypt ? _random(12) : Uint8List.sublistView(bytes, 0, 12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
      );
    final result = cipher.process(
      encrypt ? bytes : Uint8List.sublistView(bytes, 12),
    );
    return encrypt ? Uint8List.fromList([...nonce, ...result]) : result;
  }

  @override
  Future<String?> read() async => await file.exists()
      ? utf8.decode(await _crypt(await file.readAsBytes(), encrypt: false))
      : null;

  @override
  Future<void> write(String encoded) async {
    await file.parent.create(recursive: true);
    final bytes = await _crypt(
      Uint8List.fromList(utf8.encode(encoded)),
      encrypt: true,
    );
    final staging = File('${file.path}.tmp');
    try {
      await staging.writeAsBytes(bytes, flush: true);
      await _ownerOnly(staging.path);
      await staging.rename(file.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  @override
  Future<void> clear() async {
    for (final entry in [file, keyFile]) {
      if (await entry.exists()) await entry.delete();
    }
  }
}
