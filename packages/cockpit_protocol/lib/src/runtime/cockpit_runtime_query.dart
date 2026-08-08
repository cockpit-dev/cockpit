import 'package:collection/collection.dart';

import '../foundation/cockpit_foundation_value_reader.dart';

final class CockpitRuntimeQuery {
  /// Creates a CockpitRuntimeQuery.
  const CockpitRuntimeQuery({this.onlyErrors = false, this.messageContains});

  final bool onlyErrors;
  final String? messageContains;

  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();

  bool get isEmpty =>
      !onlyErrors &&
      (messageContains == null || messageContains!.trim().isEmpty);

  /// Encodes this CockpitRuntimeQuery as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'onlyErrors': onlyErrors,
    if (messageContains != null) 'messageContains': messageContains,
  };

  /// Decodes a CockpitRuntimeQuery from a JSON object.
  factory CockpitRuntimeQuery.fromJson(Map<String, Object?> json) {
    CockpitFoundationValueReader.keys(json, const <String>{
      'onlyErrors',
      'messageContains',
    }, r'$');
    return CockpitRuntimeQuery(
      onlyErrors: json['onlyErrors'] == null
          ? false
          : CockpitFoundationValueReader.boolean(
              json['onlyErrors'],
              r'$.onlyErrors',
            ),
      messageContains: json['messageContains'] == null
          ? null
          : CockpitFoundationValueReader.string(
              json['messageContains'],
              r'$.messageContains',
              maximum: 1024,
            ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRuntimeQuery &&
            _mapEquality.equals(other.toJson(), toJson());
  }

  @override
  int get hashCode => _mapEquality.hash(toJson());
}
