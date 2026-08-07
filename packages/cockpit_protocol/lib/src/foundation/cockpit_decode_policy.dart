enum CockpitFoundationFeature {
  additiveResponseFields('foundation.response.additiveFields'),
  extensibleResponseEnums('foundation.response.extensibleEnums'),
  cleanRetry('foundation.recovery.cleanRetry'),
  locatorRetry('foundation.recovery.locatorRetry');

  /// Creates a CockpitFoundationFeature.
  const CockpitFoundationFeature(this.id);

  final String id;
}

final class CockpitDecodePolicy {
  const CockpitDecodePolicy._({
    required this.allowUnknownFields,
    required this.allowUnknownEnumValues,
  });

  static const requests = CockpitDecodePolicy._(
    allowUnknownFields: false,
    allowUnknownEnumValues: false,
  );

  static const strictResponses = CockpitDecodePolicy._(
    allowUnknownFields: false,
    allowUnknownEnumValues: false,
  );

  /// Creates a CockpitDecodePolicy using the named constructor `negotiatedResponse`.
  factory CockpitDecodePolicy.negotiatedResponse(Iterable<String> featureIds) {
    final features = featureIds.toSet();
    return CockpitDecodePolicy._(
      allowUnknownFields: features.contains(
        CockpitFoundationFeature.additiveResponseFields.id,
      ),
      allowUnknownEnumValues: features.contains(
        CockpitFoundationFeature.extensibleResponseEnums.id,
      ),
    );
  }

  final bool allowUnknownFields;
  final bool allowUnknownEnumValues;
}

final class CockpitEnumValue<T extends Enum> {
  const CockpitEnumValue._({required this.wireValue, this.knownValue});

  /// Creates a CockpitEnumValue using the named constructor `known`.
  factory CockpitEnumValue.known(T value) {
    return CockpitEnumValue<T>._(wireValue: value.name, knownValue: value);
  }

  /// Creates a CockpitEnumValue using the named constructor `parse`.
  factory CockpitEnumValue.parse(
    Object? value,
    List<T> values,
    String path, {
    required CockpitDecodePolicy policy,
    bool extensibleResponse = false,
  }) {
    if (value is! String || value.isEmpty) {
      throw FormatException('Expected a non-empty enum value at $path.');
    }
    for (final candidate in values) {
      if (candidate.name == value) {
        return CockpitEnumValue<T>.known(candidate);
      }
    }
    if (!extensibleResponse || !policy.allowUnknownEnumValues) {
      throw FormatException('Unsupported enum value "$value" at $path.');
    }
    return CockpitEnumValue<T>._(wireValue: value);
  }

  final String wireValue;
  final T? knownValue;

  bool get isKnown => knownValue != null;

  T requireKnown() {
    final value = knownValue;
    if (value == null) {
      throw StateError('Unsupported negotiated enum value "$wireValue".');
    }
    return value;
  }
}
