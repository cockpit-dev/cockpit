import 'cockpit_api_version.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';
import 'cockpit_operation_descriptor.dart';

final class CockpitResourceDescriptor {
  /// Creates a CockpitResourceDescriptor.
  CockpitResourceDescriptor({
    required this.kind,
    required this.scope,
    required this.uriTemplate,
    required this.mediaType,
    Iterable<String> requiredFeatures = const <String>[],
  }) : requiredFeatures = List<String>.unmodifiable(requiredFeatures) {
    CockpitFoundationValueReader.kind(kind, r'$.kind');
    CockpitFoundationValueReader.apiTemplate(uriTemplate, r'$.uriTemplate');
    CockpitFoundationValueReader.mediaType(mediaType, r'$.mediaType');
    final features = <String>{};
    for (final feature in this.requiredFeatures) {
      CockpitFoundationValueReader.id(feature, r'$.requiredFeatures[]');
      if (!features.add(feature)) {
        throw FormatException('Duplicate required feature $feature.');
      }
    }
  }

  final String kind;
  final CockpitOperationScope scope;
  final String uriTemplate;
  final String mediaType;
  final List<String> requiredFeatures;

  /// Encodes this CockpitResourceDescriptor as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'scope': scope.name,
    'uriTemplate': uriTemplate,
    'mediaType': mediaType,
    'requiredFeatures': requiredFeatures,
  };

  /// Decodes a CockpitResourceDescriptor from a JSON object.
  factory CockpitResourceDescriptor.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'kind',
      'scope',
      'uriTemplate',
      'mediaType',
      'requiredFeatures',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields,
      policy: decodePolicy,
    );
    return CockpitResourceDescriptor(
      kind: CockpitFoundationValueReader.kind(json['kind'], '$path.kind'),
      scope: CockpitEnumValue<CockpitOperationScope>.parse(
        json['scope'],
        CockpitOperationScope.values,
        '$path.scope',
        policy: CockpitDecodePolicy.requests,
      ).requireKnown(),
      uriTemplate: CockpitFoundationValueReader.apiTemplate(
        json['uriTemplate'],
        '$path.uriTemplate',
      ),
      mediaType: CockpitFoundationValueReader.mediaType(
        json['mediaType'],
        '$path.mediaType',
      ),
      requiredFeatures: CockpitFoundationValueReader.ids(
        json['requiredFeatures'],
        '$path.requiredFeatures',
      ),
    );
  }
}

final class CockpitCapabilityDocument {
  /// Creates a CockpitCapabilityDocument.
  CockpitCapabilityDocument({
    this.schemaVersion = 'cockpit.foundation/v2',
    required this.apiVersion,
    Iterable<CockpitFeatureDescriptor> features =
        const <CockpitFeatureDescriptor>[],
    Iterable<CockpitOperationDescriptor> operations =
        const <CockpitOperationDescriptor>[],
    Iterable<CockpitResourceDescriptor> resources =
        const <CockpitResourceDescriptor>[],
  }) : features = List<CockpitFeatureDescriptor>.unmodifiable(features),
       operations = List<CockpitOperationDescriptor>.unmodifiable(operations),
       resources = List<CockpitResourceDescriptor>.unmodifiable(resources) {
    if (schemaVersion != 'cockpit.foundation/v2') {
      throw const FormatException('Invalid foundation schemaVersion.');
    }
    _unique(this.features.map((feature) => feature.id), 'feature');
    _unique(this.operations.map((operation) => operation.kind), 'operation');
    _unique(this.resources.map((resource) => resource.kind), 'resource');
  }

  final String schemaVersion;
  final CockpitApiVersion apiVersion;
  final List<CockpitFeatureDescriptor> features;
  final List<CockpitOperationDescriptor> operations;
  final List<CockpitResourceDescriptor> resources;

  /// Encodes this CockpitCapabilityDocument as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'apiVersion': apiVersion.toJson(),
    'features': features.map((feature) => feature.toJson()).toList(),
    'operations': operations.map((operation) => operation.toJson()).toList(),
    'resources': resources.map((resource) => resource.toJson()).toList(),
  };

  /// Decodes a CockpitCapabilityDocument from a JSON object.
  factory CockpitCapabilityDocument.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'schemaVersion',
      'apiVersion',
      'features',
      'operations',
      'resources',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields,
      policy: decodePolicy,
    );
    final rawFeatures = CockpitFoundationValueReader.list(
      json['features'],
      '$path.features',
    );
    final rawOperations = CockpitFoundationValueReader.list(
      json['operations'],
      '$path.operations',
    );
    final rawResources = CockpitFoundationValueReader.list(
      json['resources'],
      '$path.resources',
    );
    return CockpitCapabilityDocument(
      schemaVersion: CockpitFoundationValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      apiVersion: CockpitApiVersion.fromJson(
        json['apiVersion'],
        path: '$path.apiVersion',
        decodePolicy: decodePolicy,
      ),
      features: <CockpitFeatureDescriptor>[
        for (var index = 0; index < rawFeatures.length; index += 1)
          CockpitFeatureDescriptor.fromJson(
            rawFeatures[index],
            path: '$path.features[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
      operations: <CockpitOperationDescriptor>[
        for (var index = 0; index < rawOperations.length; index += 1)
          CockpitOperationDescriptor.fromJson(
            rawOperations[index],
            path: '$path.operations[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
      resources: <CockpitResourceDescriptor>[
        for (var index = 0; index < rawResources.length; index += 1)
          CockpitResourceDescriptor.fromJson(
            rawResources[index],
            path: '$path.resources[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
    );
  }
}

void _unique(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw FormatException('Duplicate $label $value.');
    }
  }
}
