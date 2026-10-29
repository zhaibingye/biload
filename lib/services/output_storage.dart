import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';

typedef LegacyOutput = ({String path, String name, int bytes, int modified});

class OutputStorage {
  OutputStorage({bool? isAndroid, MethodChannel? channel})
    : isAndroid = isAndroid ?? Platform.isAndroid,
      channel = channel ?? const MethodChannel('app.biload/platform');

  static const androidDownloads = 'android-downloads://biload';
  static const androidDownloadsLabel = '下载/biload';
  final bool isAndroid;
  final MethodChannel channel;

  bool isSharedDirectory(String value) =>
      value == androidDownloads ||
      (Uri.tryParse(value)?.scheme == 'content' && value.contains('/tree/'));

  bool isLegacyOutput(String value) =>
      isAndroid && value.isNotEmpty && p.isAbsolute(value);

  Future<List<LegacyOutput>> legacyOutputs() async {
    if (!isAndroid) return [];
    final values = await _call<List<Object?>>('storageLegacyFiles') ?? [];
    return values.map((value) {
      final file = value as Map;
      return (
        path: file['path'] as String,
        name: file['name'] as String,
        bytes: (file['bytes'] as num).toInt(),
        modified: (file['modified'] as num).toInt(),
      );
    }).toList();
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw BiliException(e.message ?? '无法访问下载目录，请重新授权。');
    }
  }

  Future<void> prepare(String directory) async {
    if (isAndroid) {
      if (!isSharedDirectory(directory)) {
        throw const BiliException('请选择公共下载目录或通过系统授权一个文件夹。');
      }
      await _call<void>('storagePrepare', {'directory': directory});
      return;
    }
    if (!p.isAbsolute(directory)) throw const BiliException('请选择有效的本地下载目录。');
    try {
      await Directory(directory).create(recursive: true);
    } on FileSystemException {
      throw const BiliException('下载目录不可写，请重新选择。');
    }
  }

  Future<({String directory, String label})?> chooseDirectory() async {
    final result = await _call<Map<Object?, Object?>>('storageChooseDirectory');
    if (result == null) return null;
    return (
      directory: result['directory'] as String,
      label: result['label'] as String,
    );
  }

  Future<String> publish(String source, String directory, String name) async {
    if (name.isEmpty || p.basename(name) != name) {
      throw const BiliException('输出文件名无效。');
    }
    if (isAndroid) {
      final output = await _call<String>('storagePublish', {
        'source': source,
        'directory': directory,
        'name': name,
      });
      if (output == null || output.isEmpty) {
        throw const BiliException('文件未能保存到公共目录，临时文件已保留。');
      }
      return output;
    }
    final output = p.join(directory, name);
    if (await File(output).exists()) {
      throw const BiliException('输出文件已存在，请检查下载目录。');
    }
    final staging = File('$output.biload-part');
    try {
      await File(source).copy(staging.path);
      await staging.rename(output);
      return output;
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  Future<bool> exists(String output) async => output.isEmpty
      ? false
      : isAndroid
      ? await _call<bool>('storageExists', {'output': output}) ?? false
      : File(output).exists();

  Future<void> open(String output) =>
      _call<void>('storageOpen', {'output': output});

  Future<void> delete(String output) async {
    if (isAndroid) {
      await _call<void>('storageDelete', {'output': output});
    } else if (await File(output).exists()) {
      await File(output).delete();
    }
  }

  Future<void> deleteLegacySource(String source) async {
    if (isAndroid) {
      await _call<void>('storageDeletePrivate', {'source': source});
    } else if (await File(source).exists()) {
      await File(source).delete();
    }
  }
}
