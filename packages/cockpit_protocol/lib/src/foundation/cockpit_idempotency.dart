import 'cockpit_foundation_value_reader.dart';

final class CockpitIdempotencyKey {
  /// Creates a CockpitIdempotencyKey.
  CockpitIdempotencyKey(this.value) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
      throw const FormatException('Invalid idempotency key.');
    }
  }

  final String value;

  /// Decodes a CockpitIdempotencyKey from a JSON object.
  factory CockpitIdempotencyKey.fromJson(Object? value, {String path = r'$'}) {
    return CockpitIdempotencyKey(
      CockpitFoundationValueReader.string(value, path, maximum: 128),
    );
  }

  /// Encodes this CockpitIdempotencyKey as a JSON object.
  String toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is CockpitIdempotencyKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
