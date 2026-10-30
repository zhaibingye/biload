import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../core/link_parser.dart';
import '../core/models.dart';
import '../data/app_paths.dart';
import 'browser_cookies.dart';

const platformChannel = MethodChannel('app.biload/platform');
const officialLoginUrl =
    'https://passport.bilibili.com/login?gourl=https%3A%2F%2Fwww.bilibili.com%2F';

bool _allowedNavigation(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (LinkParser.isBiliHost(uri.host) ||
          [
            'biligame.com',
            'geetest.com',
            'gtimg.com',
            'qq.com',
          ].any((h) => uri.host == h || uri.host.endsWith('.$h')));
}

Future<BiliSession?> openOfficialLogin(
  BuildContext context,
  String mode,
) async {
  if (Platform.isAndroid) {
    return Navigator.of(context).push<BiliSession>(
      MaterialPageRoute(builder: (_) => _AndroidLoginPage(mode: mode)),
    );
  }
  if (Platform.isMacOS) {
    final result = await platformChannel.invokeMethod<Map<Object?, Object?>>(
      'officialLogin',
      {'url': officialLoginUrl, 'title': 'biload · $mode（B站官方页面）'},
    );
    return result == null
        ? null
        : BiliSession(
            cookies: Map<String, String>.from(result['cookies'] as Map),
            refreshToken: result['refreshToken'] as String? ?? '',
          );
  }
  if (!await WebviewWindow.isWebviewAvailable()) {
    throw const BiliException(
      '系统网页组件不可用。Windows 请安装 WebView2，Linux 请安装 WebKitGTK 4.1。',
    );
  }
  final paths = await AppPaths.create();
  final profile = paths.webviewDirectory;
  final windows = WindowsWebviewOptions(
    userDataFolder: profile,
    denyCameraAndMicrophone: true,
  );
  final browser = await WebviewWindow.create(
    configuration: CreateConfiguration(
      windowWidth: 1000,
      windowHeight: 760,
      title: 'biload · $mode（B站官方页面）',
      windows: windows,
    ),
  );
  await browser.setOnUrlRequestCallback(_allowedNavigation);
  final result = Completer<BiliSession?>();
  var inspecting = false;
  DateTime? firstCookieAt;
  var recoveredRefreshToken = '';
  Future<void> inspect() async {
    if (inspecting || result.isCompleted) return;
    inspecting = true;
    try {
      final cookies = await browser.getAllCookies().timeout(
        const Duration(seconds: 5),
      );
      final values = biliBrowserCookies(cookies);
      final uri = Uri.tryParse(browser.navigationState.value.url ?? '');
      if (uri != null && LinkParser.isBiliHost(uri.host)) {
        // Optional token retrieval must never prevent accepting valid cookies.
        try {
          final value = await browser
              .evaluateJavaScript(
                "window.localStorage.getItem('ac_time_value') || ''",
              )
              .timeout(const Duration(seconds: 2));
          if (value is String && value.isNotEmpty) {
            recoveredRefreshToken = value;
          }
        } catch (_) {}
      }
      if (values['SESSDATA']?.isNotEmpty ?? false) {
        firstCookieAt ??= DateTime.now();
        if (recoveredRefreshToken.isEmpty &&
            DateTime.now().difference(firstCookieAt!).inSeconds < 10) {
          return;
        }
        if (!result.isCompleted) {
          result.complete(
            BiliSession(cookies: values, refreshToken: recoveredRefreshToken),
          );
        }
      }
    } catch (_) {
      // Native windows may close between the timer tick and the cookie read.
    } finally {
      inspecting = false;
    }
  }

  final timer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => unawaited(inspect()),
  );
  unawaited(
    browser.onClose.then((_) {
      if (!result.isCompleted) result.complete(null);
    }),
  );
  try {
    await browser.launch(officialLoginUrl);
    return await result.future;
  } finally {
    timer.cancel();
    try {
      await browser.close();
    } catch (_) {}
    // This is the dedicated login profile, never the user's normal browser profile.
    if (p.isWithin(paths.dataDirectory, profile)) {
      try {
        await WebviewWindow.clearAll(windows: windows);
      } catch (_) {}
    }
  }
}

class _AndroidLoginPage extends StatefulWidget {
  const _AndroidLoginPage({required this.mode});
  final String mode;
  @override
  State<_AndroidLoginPage> createState() => _AndroidLoginPageState();
}

class _AndroidLoginPageState extends State<_AndroidLoginPage> {
  late final WebViewController controller;
  Timer? timer;
  String? currentUrl;
  bool inspecting = false;
  bool done = false;
  DateTime? firstCookieAt;
  String? error;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              !request.isMainFrame || _allowedNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onUrlChange: (change) => currentUrl = change.url,
          onPageFinished: (_) => unawaited(inspect()),
          onWebResourceError: (failure) {
            if (failure.isForMainFrame == true && mounted) {
              setState(() => error = '页面加载失败，请检查网络后重试。');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(officialLoginUrl));
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(inspect()),
    );
  }

  Future<void> inspect() async {
    if (inspecting || done) return;
    inspecting = true;
    try {
      final header =
          await platformChannel.invokeMethod<String>('biliCookies') ?? '';
      if (!header.contains('SESSDATA=')) return;
      firstCookieAt ??= DateTime.now();
      final session = BiliSession.fromCookieHeader(header);
      final uri = Uri.tryParse(currentUrl ?? '');
      if (uri != null && LinkParser.isBiliHost(uri.host)) {
        var value = await controller.runJavaScriptReturningResult(
          "window.localStorage.getItem('ac_time_value') || ''",
        );
        if (value is String) {
          try {
            value = jsonDecode(value);
          } catch (_) {}
          session.refreshToken = value is String ? value : '';
        }
      }
      if (session.refreshToken.isEmpty &&
          DateTime.now().difference(firstCookieAt!).inSeconds < 10) {
        return;
      }
      if (!mounted) return;
      done = true;
      timer?.cancel();
      Navigator.of(context).pop(session);
    } catch (_) {
      if (mounted) setState(() => error = '暂未取得登录凭据，请完成登录后点击“检查登录”。');
    } finally {
      inspecting = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(
      platformChannel.invokeMethod<void>('clearBiliCookies').catchError((_) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.mode),
      actions: [TextButton(onPressed: inspect, child: const Text('检查登录'))],
    ),
    body: Column(
      children: [
        Material(
          color: const Color(0xFFEAF4F0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error ?? '请在 B 站官方页面选择${widget.mode}，并完成安全验证。'),
          ),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    ),
  );
}
