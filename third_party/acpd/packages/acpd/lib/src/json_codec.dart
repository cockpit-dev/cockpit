/// JSON serialization helpers for the ACP protocol.
///
/// All ACP schema types are serialized as JSON-RPC 2.0 messages with
/// camelCase property keys and snake_case enum/discriminator values. This
/// module centralizes the conversion logic so individual type files stay
/// focused on structure rather than JSON plumbing.
library;

import 'dart:convert';

/// The JSON-RPC protocol version string used by every ACP message.
const String kJsonRpcVersion = '2.0';

/// Converts a JSON-decodeable string into a typed value via [fromJson].
///
/// Convenience wrapper around [jsonDecode] + cast.
T jsonDecodeAs<T>(String data) => jsonDecode(data) as T;

/// Encodes a value map to a compact JSON string.
String jsonEncodeTo(Object? value) => jsonEncode(value);

/// Reads an optional object field, returning `null` when absent or `null`.
///
/// Use for nullable fields. Unlike direct `[]` access this never throws on
/// non-Map inputs.
T? readField<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return value as T;
}

/// Reads a required field, throwing [FormatException] when absent.
T requireField<T>(Map<String, Object?> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException(
        'Missing required field "$key" in ${jsonEncode(json)}');
  }
  return json[key] as T;
}

/// Reads a required field with a default value when the field is absent.
///
/// Schema fields annotated with `x-deserialize-default-on-error` should use
/// this to gracefully tolerate missing/invalid values.
T readFieldOr<T>(Map<String, Object?> json, String key, T defaultValue) {
  final value = json[key];
  if (value == null) return defaultValue;
  try {
    return value as T;
  } on TypeError {
    return defaultValue;
  }
}

/// Converts a list field of nested objects into typed values via [convert].
///
/// Items that are not maps or that cause [convert] to throw are silently
/// skipped, matching the schema's `x-deserialize-skip-invalid-items` semantics.
List<T> readListField<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) convert,
) {
  final raw = json[key];
  if (raw == null) return const [];
  if (raw is! List) return const [];
  final result = <T>[];
  for (final item in raw) {
    if (item is! Map<String, Object?>) {
      if (item is Map) {
        try {
          result.add(convert(Map<String, Object?>.from(item)));
        } catch (_) {
          // skip invalid item
        }
      }
      continue;
    }
    try {
      result.add(convert(item));
    } catch (_) {
      // skip invalid item
    }
  }
  return result;
}

/// Writes [_meta] into [json] only when non-null and non-empty.
///
/// Avoids serializing `_meta: null` or `_meta: {}`, matching the schema's
/// nullable-with-default-null semantics.
void writeMeta(Map<String, Object?> json, Map<String, Object?>? meta) {
  if (meta != null && meta.isNotEmpty) {
    json['_meta'] = meta;
  }
}

/// Reads the [_meta] field, returning an empty map when absent.
Map<String, Object?> readMeta(Map<String, Object?> json) {
  final raw = json['_meta'];
  if (raw is Map<String, Object?>) return raw;
  return const {};
}

/// Casts a decoded JSON value to `Map<String, Object?>`.
///
/// Decoded JSON maps are `Map<String, dynamic>`, which cannot be assigned to
/// `Map<String, Object?>` via a plain `as` cast. This helper performs a
/// shallow re-keyed copy that satisfies the type system. Throws
/// [TypeError] (rethrown) when [value] is not a [Map].
Map<String, Object?> asJsonObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  return Map<String, Object?>.from(value! as Map);
}
