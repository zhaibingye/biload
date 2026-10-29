import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/bili_api.dart';
import '../core/models.dart';
import '../services/auth_controller.dart';
import '../services/web_login.dart';
import 'theme.dart';

Future<void> showLogin(BuildContext context, AuthController auth) =>
    showDialog<void>(
      context: context,
      builder: (_) => LoginDialog(auth: auth),
    );

class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key, required this.auth});
  final AuthController auth;
  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final pending = BiliApi();
  Timer? timer;
  LoginQr? qr;
  int tab = 0;
  bool busy = false;
  bool polling = false;
  int generation = 0;
  String message = '正在生成二维码';
  String? error;
  DateTime? expires;
  static const modes = ['扫码', '网页', '短信', '密码'];
  @override
  void initState() {
    super.initState();
    unawaited(generate());
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    super.dispose();
  }

  Future<void> generate() async {
    timer?.cancel();
    final current = ++generation;
    setState(() {
      qr = null;
      error = null;
      message = '正在生成二维码';
    });
    try {
      final code = await pending.createQr();
      if (!mounted || current != generation) return;
      setState(() {
        qr = code;
        expires = DateTime.now().add(const Duration(seconds: 175));
        message = '使用哔哩哔哩手机客户端扫码';
      });
      timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(poll(current)),
      );
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = e is BiliException ? e.message : '二维码生成失败，请重试。');
      }
    }
  }

  Future<void> poll(int current) async {
    if (polling || busy || qr == null || !mounted || current != generation) {
      return;
    }
    if (DateTime.now().isAfter(expires!)) {
      timer?.cancel();
      setState(() {
        error = '二维码已过期，请刷新后重新扫码。';
      });
      return;
    }
    polling = true;
    try {
      final status = await pending.pollQr(qr!);
      if (!mounted || current != generation) return;
      if (status == 0) {
        timer?.cancel();
        busy = true;
        setState(() => message = '正在安全保存登录状态');
        await widget.auth.adopt(pending.session);
        if (mounted) Navigator.of(context).pop();
      } else if (status == 86038) {
        timer?.cancel();
        setState(() => error = '二维码已失效，请刷新。');
      } else if (status == 86090) {
        setState(() => message = '扫码成功，请在手机上确认登录');
      } else if (status != 86101) {
        timer?.cancel();
        setState(() => error = '登录状态异常（$status），请刷新二维码。');
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() {
          busy = false;
          error = e is BiliException ? e.message : '登录查询失败，请刷新后重试。';
        });
      }
    } finally {
      polling = false;
    }
  }

  Future<void> web() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = await openOfficialLogin(context, switch (tab) {
        2 => '短信登录',
        3 => '账号密码登录',
        _ => '网页登录',
      });
      if (session != null) {
        await widget.auth.adopt(session);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is BiliException
              ? e.message
              : '无法打开登录窗口，请检查系统 WebView。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '登录哔哩哔哩',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Text(
                '连接自己的账号，获取可用的画质与音轨。',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < modes.length; i++)
                    ButtonSegment(value: i, label: Text(modes[i])),
                ],
                selected: {tab},
                showSelectedIcon: false,
                onSelectionChanged: busy
                    ? null
                    : (values) {
                        timer?.cancel();
                        generation++;
                        setState(() {
                          tab = values.first;
                          error = null;
                        });
                        if (tab == 0) unawaited(generate());
                      },
              ),
              const SizedBox(height: 24),
              if (tab == 0) ...[
                Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: qr == null
                        ? const Center(child: CircularProgressIndicator())
                        : Opacity(
                            opacity: error == null ? 1 : 0.25,
                            child: QrImageView(
                              data: qr!.url,
                              version: QrVersions.auto,
                              size: 206,
                              backgroundColor: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
                TextButton.icon(
                  onPressed: busy ? null : generate,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('刷新二维码'),
                ),
              ] else ...[
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: canvas,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    switch (tab) {
                      2 => Icons.sms_outlined,
                      3 => Icons.password_rounded,
                      _ => Icons.language_rounded,
                    },
                    size: 46,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(switch (tab) {
                  2 => '在官方登录窗口选择短信登录，输入手机号、完成验证并填写验证码。',
                  3 => '在官方登录窗口选择密码登录。密码仅在 B 站页面输入，biload 不保存密码。',
                  _ => '打开 B 站官方登录页面，完成登录和安全验证后，会话将保存到本机。',
                }, style: const TextStyle(color: muted, fontSize: 13)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: busy ? null : web,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(busy ? '等待完成登录' : '打开官方${modes[tab]}登录'),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 14),
                Notice(error!, error: true),
              ],
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: muted),
                  SizedBox(width: 6),
                  Text(
                    '登录凭据仅保存在此设备',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
