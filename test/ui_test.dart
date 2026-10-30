import 'dart:io';
import 'dart:ui' as ui;

import 'package:background_downloader/background_downloader.dart';
import 'package:biload/app_controller.dart';
import 'package:biload/core/bili_api.dart';
import 'package:biload/core/models.dart';
import 'package:biload/data/local_store.dart';
import 'package:biload/services/auth_controller.dart';
import 'package:biload/services/download_manager.dart';
import 'package:biload/ui/app.dart';
import 'package:biload/ui/login_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'ui_showcase.dart';

class _UnusedDownloader extends Fake implements FileDownloader {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    for (final path in [
      'C:/Windows/Fonts/msyh.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ]) {
      if (await File(path).exists()) {
        final loader = FontLoader('Microsoft YaHei')
          ..addFont(
            Future.value(ByteData.sublistView(await File(path).readAsBytes())),
          );
        await loader.load();
        break;
      }
    }
  });

  BiloadController controller({bool parsed = false}) {
    final store = LocalStore(':memory:');
    final api = BiliApi();
    final result = BiloadController(
      api: api,
      auth: AuthController(api, MemoryVault()),
      downloads: DownloadManager(
        api: api,
        store: store,
        workDirectory: Directory.systemTemp.path,
        downloader: _UnusedDownloader(),
      ),
      store: store,
      outputDirectory: 'C:/Downloads/biload',
    );
    if (parsed) {
      result.content = const MediaContent(
        title: '山与海之间，一段值得收藏的旅程',
        author: '演示创作者',
        cover: '',
        pages: [samplePage],
      );
      result.catalog = BiliApi.parseStreams(sampleStreams());
      result.selectedVideos.add(result.catalog!.videos.first.key);
      result.selectedAudios.add(result.catalog!.audios.first.key);
    }
    return result;
  }

  Future<void> capture(WidgetTester tester, String name, GlobalKey key) async {
    if (Platform.environment['BILOAD_CAPTURE'] != '1') return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('artifacts/ui').create(recursive: true);
      await File('artifacts/ui/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [
    const Size(1440, 960),
    const Size(390, 844),
    const Size(360, 800),
  ]) {
    testWidgets('workspace layout and navigation at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BiloadApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('把喜欢的，\n好好收藏。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 1440 && Platform.environment['BILOAD_CAPTURE'] == '1') {
        tester.view.physicalSize = const Size(1440, 820);
        await tester.pumpAndSettle();
      }
      await capture(tester, 'home-${size.width.toInt()}', key);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载任务').last);
      await tester.pumpAndSettle();
      expect(find.text('这里还没有下载任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['BILOAD_CAPTURE'] == '1') {
        c.downloads.jobs.addAll(showcaseJobs());
        // Rebuild the visible queue through its existing filter control.
        await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
        await tester.pumpAndSettle();
        await capture(tester, 'queue-${size.width.toInt()}', key);
      }
      await tester.tap(find.text('账号与设置').last);
      await tester.pumpAndSettle();
      expect(find.text('尚未登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'settings-${size.width.toInt()}', key);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      c.store.close();
    });
  }

  testWidgets('long version list stays usable on a phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = controller(parsed: true);
    await tester.pumpWidget(BiloadApp(controller: c));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('选择下载版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    c.store.close();
  });

  testWidgets(
    'signed-in account entry opens visible account information after scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller(parsed: true);
      c.api.session = BiliSession(cookies: {'SESSDATA': 'fixture-session'});
      c.auth.account = const AccountInfo(
        uid: 42,
        name: '演示账号',
        avatar: '',
        vip: true,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BiloadApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginDialog), findsNothing);
      expect(find.text('哔哩哔哩账号').hitTestable(), findsOneWidget);
      expect(find.text('UID 42 · 大会员'), findsOneWidget);
      expect(find.text('切换 / 重新登录'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'account-mobile', key);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      c.store.close();
    },
  );

  testWidgets(
    'parsed desktop catalog shows all codecs and preserves independent choices',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller(parsed: true);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BiloadApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();
      expect(find.text('AVC'), findsOneWidget);
      expect(find.text('HEVC'), findsOneWidget);
      expect(find.text('AV1'), findsOneWidget);
      await tester.tap(find.text('HEVC'));
      await tester.pumpAndSettle();
      expect(c.selectedVideos.length, 2);
      expect(c.selectedAudios.length, 1);
      expect(tester.takeException(), isNull);
      await capture(tester, 'versions-desktop', key);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      c.store.close();
    },
  );
}
