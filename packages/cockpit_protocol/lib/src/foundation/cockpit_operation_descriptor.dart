import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitOperationScope { supervisor, root, workspace }

enum CockpitMutationClass { readOnly, mutating }

enum CockpitIdempotencyBehavior { prohibited, optional, required }

enum CockpitOperationExecutionMode { synchronous, job }

enum CockpitSafetyEffect {
  shell,
  system,
  reset,
  permission,
  externalSideEffect,
  capture,
  recording,
}

final class CockpitOperationDescriptor {
  /// Creates a CockpitOperationDescriptor.
  CockpitOperationDescriptor({
    required this.kind,
    required this.title,
    required this.description,
    required this.scope,
    required this.mutationClass,
    required this.idempotency,
    required this.executionMode,
    required this.defaultTimeoutMs,
    required this.maximumTimeoutMs,
    required this.requestSchemaRef,
    required this.responseSchemaRef,
    Iterable<CockpitEnumValue<CockpitSafetyEffect>> safetyEffects =
        const <CockpitEnumValue<CockpitSafetyEffect>>[],
    Iterable<String> requiredFeatures = const <String>[],
  }) : safetyEffects = List<CockpitEnumValue<CockpitSafetyEffect>>.unmodifiable(
         safetyEffects,
       ),
       requiredFeatures = List<String>.unmodifiable(requiredFeatures) {
    CockpitFoundationValueReader.kind(kind, r'$.kind');
    CockpitFoundationValueReader.string(title, r'$.title', maximum: 128);
    CockpitFoundationValueReader.string(
      description,
      r'$.description',
      maximum: 1024,
    );
    CockpitFoundationValueReader.schemaReference(
      requestSchemaRef,
      r'$.requestSchemaRef',
    );
    CockpitFoundationValueReader.schemaReference(
      responseSchemaRef,
      r'$.responseSchemaRef',
    );
    CockpitFoundationValueReader.integer(
      defaultTimeoutMs,
      r'$.defaultTimeoutMs',
      min: 1,
      max: 86400000,
    );
    CockpitFoundationValueReader.integer(
      maximumTimeoutMs,
      r'$.maximumTimeoutMs',
      min: 1,
      max: 86400000,
    );
    if (defaultTimeoutMs > maximumTimeoutMs) {
      throw const FormatException(
        'Operation default timeout cannot exceed its maximum timeout.',
      );
    }
    if (mutationClass == CockpitMutationClass.readOnly &&
        this.safetyEffects.isNotEmpty) {
      throw const FormatException('Read-only operations cannot have effects.');
    }
    final effects = <String>{};
    for (final effect in this.safetyEffects) {
      if (!effects.add(effect.wireValue)) {
        throw FormatException('Duplicate safety effect ${effect.wireValue}.');
      }
    }
    final features = <String>{};
    for (final feature in this.requiredFeatures) {
      CockpitFoundationValueReader.id(feature, r'$.requiredFeatures[]');
      if (!features.add(feature)) {
        throw FormatException('Duplicate required feature $feature.');
      }
    }
  }

  final String kind;
  final String title;
  final String description;
  final CockpitOperationScope scope;
  final CockpitMutationClass mutationClass;
  final CockpitIdempotencyBehavior idempotency;
  final CockpitOperationExecutionMode executionMode;
  final int defaultTimeoutMs;
  final int maximumTimeoutMs;
  final List<CockpitEnumValue<CockpitSafetyEffect>> safetyEffects;
  final String requestSchemaRef;
  final String responseSchemaRef;
  final List<String> requiredFeatures;

  /// Encodes this CockpitOperationDescriptor as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'title': title,
    'description': description,
    'scope': scope.name,
    'mutationClass': mutationClass.name,
    'idempotency': idempotency.name,
    'executionMode': executionMode.name,
    'defaultTimeoutMs': defaultTimeoutMs,
    'maximumTimeoutMs': maximumTimeoutMs,
    'safetyEffects': safetyEffects.map((effect) => effect.wireValue).toList(),
    'requestSchemaRef': requestSchemaRef,
    'responseSchemaRef': responseSchemaRef,
    'requiredFeatures': requiredFeatures,
  };

  /// Decodes a CockpitOperationDescriptor from a JSON object.
  factory CockpitOperationDescriptor.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'kind',
      'title',
      'description',
      'scope',
      'mutationClass',
      'idempotency',
      'executionMode',
      'defaultTimeoutMs',
      'maximumTimeoutMs',
      'safetyEffects',
      'requestSchemaRef',
      'responseSchemaRef',
      'requiredFeatures',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields,
      policy: decodePolicy,
    );
    final rawEffects = CockpitFoundationValueReader.list(
      json['safetyEffects'],
      '$path.safetyEffects',
    );
    return CockpitOperationDescriptor(
      kind: CockpitFoundationValueReader.kind(json['kind'], '$path.kind'),
      title: CockpitFoundationValueReader.string(
        json['title'],
        '$path.title',
        maximum: 128,
      ),
      description: CockpitFoundationValueReader.string(
        json['description'],
        '$path.description',
        maximum: 1024,
      ),
      scope: _enum(json['scope'], CockpitOperationScope.values, '$path.scope'),
      mutationClass: _enum(
        json['mutationClass'],
        CockpitMutationClass.values,
        '$path.mutationClass',
      ),
      idempotency: _enum(
        json['idempotency'],
        CockpitIdempotencyBehavior.values,
        '$path.idempotency',
      ),
      executionMode: _enum(
        json['executionMode'],
        CockpitOperationExecutionMode.values,
        '$path.executionMode',
      ),
      defaultTimeoutMs: CockpitFoundationValueReader.integer(
        json['defaultTimeoutMs'],
        '$path.defaultTimeoutMs',
        min: 1,
        max: 86400000,
      ),
      maximumTimeoutMs: CockpitFoundationValueReader.integer(
        json['maximumTimeoutMs'],
        '$path.maximumTimeoutMs',
        min: 1,
        max: 86400000,
      ),
      safetyEffects: <CockpitEnumValue<CockpitSafetyEffect>>[
        for (var index = 0; index < rawEffects.length; index += 1)
          CockpitEnumValue<CockpitSafetyEffect>.parse(
            rawEffects[index],
            CockpitSafetyEffect.values,
            '$path.safetyEffects[$index]',
            policy: decodePolicy,
            extensibleResponse: true,
          ),
      ],
      requestSchemaRef: CockpitFoundationValueReader.schemaReference(
        json['requestSchemaRef'],
        '$path.requestSchemaRef',
      ),
      responseSchemaRef: CockpitFoundationValueReader.schemaReference(
        json['responseSchemaRef'],
        '$path.responseSchemaRef',
      ),
      requiredFeatures: CockpitFoundationValueReader.ids(
        json['requiredFeatures'],
        '$path.requiredFeatures',
      ),
    );
  }
}

T _enum<T extends Enum>(Object? value, List<T> values, String path) {
  return CockpitEnumValue<T>.parse(
    value,
    values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}
