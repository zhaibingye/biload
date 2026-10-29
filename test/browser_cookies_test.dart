import 'package:biload/services/browser_cookies.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter_test/flutter_test.dart';

WebviewCookie cookie({
  String name = 'SESSDATA',
  String value = 'fixture',
  String domain = '.bilibili.com',
  DateTime? expires,
  bool sessionOnly = false,
}) => WebviewCookie(
  name: name,
  value: value,
  domain: domain,
  path: '/',
  expires: expires,
  secure: true,
  httpOnly: true,
  sessionOnly: sessionOnly,
);

void main() {
  test('Windows native terminating NUL does not hide domain or SESSDATA', () {
    expect(
      biliBrowserCookies([
        cookie(
          name: 'SESSDATA\x00',
          value: 'fixture%2Ctoken\x00',
          domain: '.bilibili.com\x00',
        ),
      ]),
      {'SESSDATA': 'fixture%2Ctoken'},
    );
  });
  test('normal cookies on other desktop platforms remain unchanged', () {
    expect(
      biliBrowserCookies([cookie(), cookie(name: 'bili_jct', value: 'csrf')]),
      {'SESSDATA': 'fixture', 'bili_jct': 'csrf'},
    );
  });
  test('embedded controls are rejected instead of changing the credential', () {
    expect(
      biliBrowserCookies([
        cookie(value: 'first\x00second'),
        cookie(value: 'first\r\nsecond'),
      ]),
      isEmpty,
    );
  });
  test(
    'expired persistent cookies are ignored and session-only expiry is ignored',
    () {
      final now = DateTime.utc(2026, 1, 1);
      expect(biliBrowserCookies([cookie(expires: now)], now: now), isEmpty);
      expect(
        biliBrowserCookies([cookie(expires: now, sessionOnly: true)], now: now),
        {'SESSDATA': 'fixture'},
      );
    },
  );
  test(
    'unrelated and spoofed cookie domains cannot become the Bilibili session',
    () {
      expect(
        biliBrowserCookies([
          cookie(domain: '.bilibili.com.evil.test'),
          cookie(domain: 'evilbilibili.com'),
          cookie(domain: 'biligame.com'),
        ]),
        isEmpty,
      );
    },
  );
}
