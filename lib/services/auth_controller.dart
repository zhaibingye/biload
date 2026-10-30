import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/bili_api.dart';
import '../core/models.dart';

abstract class SessionVault {
  Future<String?> read();
  Future<void> write(String encoded);
  Future<void> clear();
}

class SecureSessionVault implements SessionVault {
  const SecureSessionVault({this.key = 'biload.bilibili.session.v1'});
  final String key;
  // A standalone macOS build has no provisioning profile for shared Keychain
  // groups. Use the login Keychain; credentials still stay in the OS vault.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String encoded) =>
      _storage.write(key: key, value: encoded);
  @override
  Future<void> clear() => _storage.delete(key: key);
}

class AuthController extends ChangeNotifier {
  AuthController(this.api, this.vault);
  final BiliApi api;
  final SessionVault vault;
  AccountInfo? account;
  String? warning;
  bool busy = false;
  bool get loggedIn => account != null && api.session.hasLogin;

  Future<void> restore() async {
    try {
      final encoded = await vault.read();
      if (encoded != null) {
        api.session = BiliSession.decode(encoded);
        await refresh();
      }
    } catch (_) {
      warning = '无法恢复账号，请检查系统凭据存储或重新登录。';
      notifyListeners();
    }
  }

  Future<void> adopt(BiliSession session) async {
    final candidate = BiliApi(dio: api.http, session: session);
    final info = await candidate.account();
    if (info == null) throw const BiliException('未检测到有效登录，请完成 B 站确认后重试。');
    try {
      await vault.write(session.encode());
    } catch (_) {
      throw const BiliException('无法安全保存登录状态，请检查系统钥匙串或凭据服务。');
    }
    api.session = session;
    account = info;
    warning = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      account = await api.account();
      if (account == null) {
        warning = api.session.hasLogin ? '登录已失效，请重新登录。' : null;
      } else {
        warning = null;
        try {
          await api.refreshSession(() => vault.write(api.session.encode()));
        } on BiliException catch (e) {
          warning = e.message;
        }
      }
    } on BiliException catch (e) {
      warning = e.message;
    } catch (_) {
      warning = '无法安全更新登录状态，请检查系统凭据存储或重新登录。';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await vault.clear();
    api.session = BiliSession();
    account = null;
    warning = null;
    notifyListeners();
  }
}
