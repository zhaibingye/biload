import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biload/services/output_storage.dart';
import 'package:biload/services/browser_cookies.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('biload Windows native verification')),
      ),
    ),
  );
  unawaited(verify());
}

Future<void> verify() async {
  final root = await Directory(
    p.join(Directory.systemTemp.path, 'biload-windows-native-smoke'),
  ).create(recursive: true);
  final report = <String, Object?>{};
  Webview? view;
  HttpServer? server;
  try {
    final output = p.join(root.path, '中文 空格 #100% fixture.mp4');
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=green:s=128x72:r=10',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440',
      '-t',
      '2',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      output,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw StateError('FFmpeg fixture failed');
    }
    const channel = MethodChannel('app.biload/platform');
    try {
      await channel.invokeMethod<void>('storageOpen', {
        'output': p.join(root.path, 'missing.mp4'),
      });
      throw StateError('Missing file accepted');
    } on PlatformException catch (e) {
      if (e.code != 'missing_file') rethrow;
      report['missingFileRejected'] = true;
    }
    await OutputStorage().open(output);
    report['unicodeSpaceHashPercentFileOpened'] = true;
    final received = Completer<String>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/start') {
        request.response.write(
          '<form action="/finish" method="post"><input name="value" value="fixture"></form><script>document.forms[0].submit()</script>',
        );
      } else {
        final body = await utf8.decodeStream(request);
        request.response.cookies.add(
          Cookie('biload_session_fixture', 'fixture')..httpOnly = true,
        );
        request.response.cookies.add(
          Cookie('biload_persistent_fixture', 'fixture')
            ..expires = DateTime.now().toUtc().add(const Duration(days: 1))
            ..path = '/',
        );
        request.response.write('done');
        if (!received.isCompleted) received.complete(body);
      }
      await request.response.close();
    });
    view = await WebviewWindow.create(
      configuration: CreateConfiguration(
        windows: WindowsWebviewOptions(
          userDataFolder: p.join(root.path, 'webview'),
        ),
      ),
    );
    final base = 'http://127.0.0.1:${server.port}';
    await view.setOnUrlRequestCallback((url) => url.startsWith('$base/'));
    await view.launch('$base/start');
    if (await received.future.timeout(const Duration(seconds: 20)) !=
        'value=fixture') {
      throw StateError('POST body lost');
    }
    report['navigationPreservesPostBody'] = true;
    await Future<void>.delayed(const Duration(seconds: 1));
    final cookies = await view.getAllCookies().timeout(
      const Duration(seconds: 5),
    );
    report['fixtureCookies'] = [
      for (final c in cookies)
        if (c.name.startsWith('biload_'))
          {
            'name': c.name,
            'httpOnly': c.httpOnly,
            'sessionOnly': c.sessionOnly,
          },
    ];
    if (!cookies.any(
      (c) =>
          browserCookieText(c.name) == 'biload_session_fixture' &&
          c.httpOnly &&
          c.sessionOnly,
    )) {
      throw StateError('HttpOnly session cookie missing');
    }
    report['httpOnlySessionCookieRead'] = true;
    report['passed'] = true;
  } catch (e) {
    report['passed'] = false;
    report['failureType'] = e.runtimeType.toString();
    report['failure'] = e.toString();
  } finally {
    await view?.close();
    await server?.close(force: true);
    await File(p.join(root.path, 'report.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    exit(report['passed'] == true ? 0 : 1);
  }
}
