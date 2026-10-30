import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:biload/core/models.dart';
import 'package:biload/data/app_paths.dart';
import 'package:biload/data/transfer_store.dart';
import 'package:biload/services/file_session_vault.dart';
import 'package:biload/services/output_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('biload-portable-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'desktop paths follow the executable including Unicode and spaces',
    () async {
      final executable = p.join(root.path, '中文 安装位置', 'biload.exe');
      final paths = AppPaths.desktop(executable);
      await paths.prepare();
      expect(paths.dataDirectory, p.join(p.dirname(executable), 'user-data'));
      expect(await Directory(paths.cacheDirectory).exists(), isTrue);
    },
  );

  test('macOS data sits beside the app bundle', () {
    final paths = AppPaths.desktop(
      '/Applications/biload.app/Contents/MacOS/biload',
      isMacOS: true,
      context: p.Context(style: p.Style.posix),
    );
    expect(paths.installDirectory, '/Applications');
    expect(paths.dataDirectory, '/Applications/user-data');
  });

  test('completed media defaults to the system Downloads location', () async {
    final systemDownloads = Directory(p.join(root.path, '系统下载'));
    expect(
      await OutputStorage.defaultDirectory(
        downloadsDirectory: () async => systemDownloads,
      ),
      p.join(systemDownloads.path, 'biload'),
    );
    await expectLater(
      OutputStorage.defaultDirectory(downloadsDirectory: () async => null),
      throwsA(isA<BiliException>()),
    );
  });

  test(
    'an unwritable installation reports its location without a hidden fallback',
    () async {
      await File(p.join(root.path, 'user-data'))
          .writeAsString('file blocks directory');
      await expectLater(
        AppPaths.desktop(p.join(root.path, 'biload.exe')).prepare(),
        throwsA(
          isA<BiliException>().having(
            (e) => e.message,
            'message',
            contains(root.path),
          ),
        ),
      );
    },
  );

  test(
    'local encrypted account survives overwrite and reopen, then clears',
    () async {
      final vault = FileSessionVault(root.path, isWindows: false);
      expect(await vault.read(), isNull);
      await vault.write('SESSDATA=synthetic-only');
      expect(
        await vault.file.readAsBytes(),
        isNot(containsAll('SESSDATA'.codeUnits)),
      );
      expect(
        await FileSessionVault(root.path, isWindows: false).read(),
        'SESSDATA=synthetic-only',
      );
      await vault.write('replacement');
      expect(await vault.read(), 'replacement');
      await vault.clear();
      expect(await vault.read(), isNull);
      expect(await root.list().isEmpty, isTrue);
    },
  );

  test('modified account ciphertext is rejected', () async {
    final vault = FileSessionVault(root.path, isWindows: false);
    await vault.write('synthetic-session');
    final bytes = await vault.file.readAsBytes();
    bytes.last ^= 1;
    await vault.file.writeAsBytes(bytes);
    await expectLater(vault.read(), throwsA(anything));
  });

  test('transfer queue and paused state reopen only from the chosen local database', () async {
    final path = p.join(root.path, 'transfers.sqlite');
    var store = TransferStore(path);
    final task = DownloadTask(
      taskId: 'portable-test',
      url: 'https://example.com/fixture',
      directory: root.path,
      baseDirectory: BaseDirectory.root,
    );
    await store.storePausedTask(task);
    store.db.close();
    store = TransferStore(path);
    expect((await store.retrievePausedTask(task.taskId))?.taskId, task.taskId);
    expect(await store.retrieveAllTaskRecords(), isEmpty);
    store.db.close();
    final other = TransferStore(p.join(root.path, 'other.sqlite'));
    expect(await other.retrieveAllPausedTasks(), isEmpty);
    other.db.close();
  });
}
