Map<String, Object?> freezeCockpitJson(
  Map<String, Object?> value, {
  String path = r'$',
}) {
  return Map<String, Object?>.unmodifiable(
    _freezeJsonMap(value, path, Set<Object>.identity()),
  );
}

Map<String, Object?> _freezeJsonMap(
  Map<Object?, Object?> value,
  String path,
  Set<Object> ancestors,
) {
  if (!ancestors.add(value)) {
    throw ArgumentError.value(value, path, 'JSON values must not be cyclic.');
  }
  try {
    return <String, Object?>{
      for (final entry in value.entries)
        _jsonKey(entry.key, path): _freezeJsonValue(
          entry.value,
          '$path.${entry.key}',
          ancestors,
        ),
    };
  } finally {
    ancestors.remove(value);
  }
}

Object? _freezeJsonValue(Object? value, String path, Set<Object> ancestors) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is num) {
    final number = value.toDouble();
    if (!number.isFinite) {
      throw ArgumentError.value(value, path, 'JSON numbers must be finite.');
    }
    return number;
  }
  if (value is Map<Object?, Object?>) {
    return Map<String, Object?>.unmodifiable(
      _freezeJsonMap(value, path, ancestors),
    );
  }
  if (value is Iterable<Object?>) {
    if (!ancestors.add(value)) {
      throw ArgumentError.value(value, path, 'JSON values must not be cyclic.');
    }
    try {
      var index = 0;
      return List<Object?>.unmodifiable(<Object?>[
        for (final item in value)
          _freezeJsonValue(item, '$path[${index++}]', ancestors),
      ]);
    } finally {
      ancestors.remove(value);
    }
  }
  throw ArgumentError.value(value, path, 'Expected a JSON-compatible value.');
}

String _jsonKey(Object? value, String path) {
  if (value is String) return value;
  throw ArgumentError.value(value, path, 'JSON object keys must be strings.');
}
