import 'dart:convert';

final class CockpitNetworkRedactor {
  /// Creates a CockpitNetworkRedactor.
  const CockpitNetworkRedactor();

  static const String masked = '********';

  static final RegExp _inlineCredential = RegExp(
    r'''((?:bearer|basic)\s+|(?:authorization|password|passwd|secret|token|api[-_ ]?key|private[-_ ]?key|credential|signature|csrf|xsrf)\s*["']?\s*[=:]\s*["']?)([^"'\s,;&]+)''',
    caseSensitive: false,
  );
  static final RegExp _cookieCredential = RegExp(
    r'''(cookie\s*["']?\s*[=:]\s*["']?)([^\r\n]+)''',
    caseSensitive: false,
  );
  static final RegExp _privateKey = RegExp(
    r'-----BEGIN [^-\r\n]*PRIVATE KEY-----[\s\S]*?(?:-----END [^-\r\n]*PRIVATE KEY-----|$)',
    caseSensitive: false,
  );
  static final RegExp _urlUserInfo = RegExp(
    r'((?:https?|wss?)://)[^/@\s:]+:[^/@\s]+@',
    caseSensitive: false,
  );

  String headerValue(String name, String value) {
    final normalized = _normalizedName(name);
    if (!isSensitiveName(name)) return text(value);
    if (normalized.endsWith('authorization')) {
      final match = RegExp(
        r'^\s*([A-Za-z][A-Za-z0-9._~-]{0,31})\s+\S',
      ).firstMatch(value);
      return match == null ? masked : '${match.group(1)} $masked';
    }
    if (normalized.endsWith('setcookie')) {
      final name = _cookieName(value);
      return name == null ? masked : '$name=$masked';
    }
    if (normalized.endsWith('cookie')) {
      final cookies = <String>[];
      for (final part in value.split(';')) {
        final name = _cookieName(part);
        if (name == null) return masked;
        cookies.add('$name=$masked');
      }
      return cookies.isEmpty ? masked : cookies.join('; ');
    }
    return masked;
  }

  Map<String, String> headers(Map<Object?, Object?> values) {
    return Map<String, String>.unmodifiable(<String, String>{
      for (final entry in values.entries)
        if (entry.key is String)
          entry.key! as String: headerValue(
            entry.key! as String,
            _headerText(entry.value),
          ),
    });
  }

  String? contentType(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') return entry.value;
    }
    return null;
  }

  Uri uri(Uri value) {
    var result = value;
    if (result.userInfo.isNotEmpty) {
      result = result.replace(userInfo: Uri.encodeComponent(masked));
    }
    if (result.query.isNotEmpty) {
      result = result.replace(
        queryParameters: <String, Object?>{
          for (final entry in result.queryParametersAll.entries)
            entry.key: isSensitiveName(entry.key)
                ? <String>[for (final _ in entry.value) masked]
                : <String>[for (final item in entry.value) text(item)],
        },
      );
    }
    if (result.fragment.isNotEmpty) {
      result = result.replace(fragment: text(result.fragment));
    }
    return result;
  }

  String body(String value, {String? contentType}) {
    final mediaType = contentType?.split(';').first.trim().toLowerCase();
    if (mediaType?.startsWith('multipart/') == true) return masked;

    final trimmed = value.trimLeft();
    if (mediaType?.contains('json') == true ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      try {
        return jsonEncode(_value(jsonDecode(value), depth: 0));
      } on FormatException {
        // A partial payload still receives the bounded textual pass below.
      }
    }
    if (mediaType == 'application/x-www-form-urlencoded') {
      try {
        final parameters = Uri(query: value).queryParametersAll;
        return Uri(
          queryParameters: <String, Object?>{
            for (final entry in parameters.entries)
              entry.key: isSensitiveName(entry.key)
                  ? <String>[for (final _ in entry.value) masked]
                  : <String>[for (final item in entry.value) text(item)],
          },
        ).query;
      } on FormatException {
        // A partial form still receives the textual pass below.
      }
    }
    return text(value);
  }

  String text(String value) => value
      .replaceAll(_privateKey, masked)
      .replaceAllMapped(_urlUserInfo, (match) => '${match.group(1)}$masked@')
      .replaceAllMapped(
        _cookieCredential,
        (match) => '${match.group(1)}$masked',
      )
      .replaceAllMapped(
        _inlineCredential,
        (match) => '${match.group(1)}$masked',
      );

  bool isSensitiveName(String name) {
    final normalized = _normalizedName(name);
    return normalized.endsWith('authorization') ||
        normalized.endsWith('cookie') ||
        normalized.endsWith('apikey') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('accesskey') ||
        normalized.endsWith('signature') ||
        normalized == 'bearer' ||
        normalized == 'sig' ||
        normalized == 'hmac' ||
        normalized == 'csrf' ||
        normalized == 'xsrf' ||
        normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized.contains('credential');
  }

  String _normalizedName(String name) =>
      name.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase();

  String? _cookieName(String value) {
    final separator = value.indexOf('=');
    if (separator <= 0) return null;
    final name = value.substring(0, separator).trim();
    return name.isNotEmpty &&
            !name.contains(RegExp(r'[\x00-\x20\x7f()<>@,;:\\"/\[\]?={}]'))
        ? name
        : null;
  }

  String _headerText(Object? value) => switch (value) {
    Iterable<Object?>() => value.map(_headerText).join(', '),
    _ => '${value ?? ''}',
  };

  Object? _value(Object? value, {required int depth, String? key}) {
    if (key != null && isSensitiveName(key)) return masked;
    if (depth >= 32) return masked;
    return switch (value) {
      String() => text(value),
      Map<Object?, Object?>() => <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _value(
            entry.value,
            depth: depth + 1,
            key: '${entry.key}',
          ),
      },
      Iterable<Object?>() => <Object?>[
        for (final item in value) _value(item, depth: depth + 1),
      ],
      _ => value,
    };
  }
}
