import 'package:desktop_webview_window/desktop_webview_window.dart';

import '../core/link_parser.dart';

/// desktop_webview_window 0.4.0 on Windows includes the UTF-16 terminator in
/// converted cookie strings. Remove only trailing terminators; reject embedded
/// controls rather than silently changing a credential's contents.
String? browserCookieText(String value) {
  final text = value.replaceFirst(RegExp(r'\x00+$'), '');
  return RegExp(r'[\x00-\x1f\x7f]').hasMatch(text) ? null : text;
}

Map<String, String> biliBrowserCookies(
  Iterable<WebviewCookie> cookies, {
  DateTime? now,
}) {
  final values = <String, String>{};
  final time = now ?? DateTime.now();
  for (final cookie in cookies) {
    final domain = browserCookieText(cookie.domain)?.toLowerCase();
    final name = browserCookieText(cookie.name);
    final value = browserCookieText(cookie.value);
    if (domain == null ||
        name == null ||
        value == null ||
        name.isEmpty ||
        !LinkParser.isBiliHost(domain.replaceFirst(RegExp(r'^\.'), '')) ||
        (!cookie.sessionOnly &&
            cookie.expires != null &&
            !cookie.expires!.isAfter(time))) {
      continue;
    }
    values[name] = value;
  }
  return values;
}
