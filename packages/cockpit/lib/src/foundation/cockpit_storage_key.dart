import 'dart:convert';

import 'package:crypto/crypto.dart';

String cockpitStorageKey(String identity) {
  final digest = sha256.convert(utf8.encode(identity)).bytes;
  return base64UrlEncode(digest.sublist(0, 16)).replaceAll('=', '');
}
