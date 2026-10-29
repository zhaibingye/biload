import 'dart:convert';

import 'package:crypto/crypto.dart';

class Wbi {
  static const _map = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
  ];
  static Map<String, String> sign(
    Map<String, Object> parameters,
    String imgKey,
    String subKey, {
    int? timestamp,
  }) {
    final raw = imgKey + subKey;
    if (raw.length < 64) throw const FormatException('Invalid WBI keys');
    final mixin = _map.map((i) => raw[i]).join();
    final values = parameters.map(
      (key, value) =>
          MapEntry(key, '$value'.replaceAll(RegExp(r"[!'()*]"), '')),
    );
    values['wts'] =
        '${timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final keys = values.keys.toList()..sort();
    final query = keys
        .map(
          (key) =>
              '${Uri.encodeComponent(key)}=${Uri.encodeComponent(values[key]!)}',
        )
        .join('&');
    return {
      ...values,
      'w_rid': md5.convert(utf8.encode(query + mixin)).toString(),
    };
  }
}
