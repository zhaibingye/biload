import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';

class AppPaths {
  AppPaths(this.installDirectory, this.dataDirectory);

  factory AppPaths.desktop(
    String executable, {
    bool isMacOS = false,
    p.Context? context,
  }) {
    final paths = context ?? p.context;
    var root = paths.dirname(executable);
    if (isMacOS &&
        paths.basename(root) == 'MacOS' &&
        paths.basename(paths.dirname(root)) == 'Contents') {
      root = paths.dirname(paths.dirname(paths.dirname(root)));
    }
    return AppPaths(root, paths.join(root, 'user-data'));
  }

  final String installDirectory;
  final String dataDirectory;
  String get cacheDirectory => p.join(dataDirectory, 'cache');
  String get webviewDirectory => p.join(dataDirectory, 'webview');
  String get databasePath => p.join(dataDirectory, 'biload.sqlite');

  static Future<AppPaths> create() async {
    final paths = Platform.isAndroid
        ? AppPaths(
            '',
            p.join((await getApplicationSupportDirectory()).path, 'user-data'),
          )
        : AppPaths.desktop(
            Platform.resolvedExecutable,
            isMacOS: Platform.isMacOS,
          );
    await paths.prepare();
    return paths;
  }

  Future<void> prepare() async {
    try {
      await Directory(cacheDirectory).create(recursive: true);
      if (!Platform.isWindows && !Platform.isAndroid) {
        final permissions = await Process.run('chmod', ['700', dataDirectory]);
        if (permissions.exitCode != 0) {
          throw const FileSystemException('无法保护用户数据文件夹。');
        }
      }
      final probe = File(p.join(dataDirectory, '.write-check-$pid'));
      await probe.writeAsString('', flush: true);
      await probe.delete();
    } on FileSystemException {
      throw BiliException(
        '无法写入用户数据文件夹：$dataDirectory。请将 biload 解压到桌面或其他可写目录后重试。',
      );
    }
  }
}
