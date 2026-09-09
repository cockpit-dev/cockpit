/// Parses a protocol enum without leaking [ArgumentError] from `byName`.
/// Unknown and malformed values are protocol format errors with a path.
T cockpitEnumFromJson<T extends Enum>(
  Object? value,
  List<T> values,
  String path,
) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected a non-empty enum value at $path.');
  }
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException(
    'Unsupported enum value "$value" at $path. Expected one of '
    '${values.map((candidate) => candidate.name).join(', ')}.',
  );
}
