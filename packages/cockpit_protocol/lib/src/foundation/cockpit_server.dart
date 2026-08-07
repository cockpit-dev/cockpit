import 'cockpit_api_error.dart';
import 'cockpit_api_version.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

final class CockpitServerInfo {
  /// Creates a CockpitServerInfo.
  CockpitServerInfo({
    this.schemaVersion = 'cockpit.foundation/v2',
    required this.instanceId,
    required this.apiVersion,
    required this.engineVersion,
    required this.startedAt,
    Iterable<CockpitFeatureDescriptor> features =
        const <CockpitFeatureDescriptor>[],
  }) : features = List<CockpitFeatureDescriptor>.unmodifiable(features) {
    if (schemaVersion != 'cockpit.foundation/v2') {
      throw const FormatException('Invalid foundation schemaVersion.');
    }
    CockpitFoundationValueReader.id(instanceId, r'$.instanceId');
    CockpitFoundationValueReader.string(
      engineVersion,
      r'$.engineVersion',
      maximum: 128,
    );
    CockpitFoundationValueReader.utcDateTime(startedAt, r'$.startedAt');
    final featureIds = <String>{};
    for (final feature in this.features) {
      if (feature.minimumApiMinor > apiVersion.minor) {
        throw FormatException(
          'Feature ${feature.id} requires a newer API minor.',
        );
      }
      if (!featureIds.add(feature.id)) {
        throw FormatException('Duplicate feature ${feature.id}.');
      }
    }
  }

  final String schemaVersion;
  final String instanceId;
  final CockpitApiVersion apiVersion;
  final String engineVersion;
  final DateTime startedAt;
  final List<CockpitFeatureDescriptor> features;

  Set<String> get featureIds =>
      Set<String>.unmodifiable(features.map((feature) => feature.id));

  /// Encodes this CockpitServerInfo as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'instanceId': instanceId,
    'apiVersion': apiVersion.toJson(),
    'engineVersion': engineVersion,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'features': features.map((feature) => feature.toJson()).toList(),
  };

  /// Decodes a CockpitServerInfo from a JSON object.
  factory CockpitServerInfo.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'schemaVersion',
      'instanceId',
      'apiVersion',
      'engineVersion',
      'startedAt',
      'features',
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
    return CockpitServerInfo(
      schemaVersion: CockpitFoundationValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      instanceId: CockpitFoundationValueReader.id(
        json['instanceId'],
        '$path.instanceId',
      ),
      apiVersion: CockpitApiVersion.fromJson(
        json['apiVersion'],
        path: '$path.apiVersion',
        decodePolicy: decodePolicy,
      ),
      engineVersion: CockpitFoundationValueReader.string(
        json['engineVersion'],
        '$path.engineVersion',
        maximum: 128,
      ),
      startedAt: CockpitFoundationValueReader.dateTime(
        json['startedAt'],
        '$path.startedAt',
      ),
      features: <CockpitFeatureDescriptor>[
        for (var index = 0; index < rawFeatures.length; index += 1)
          CockpitFeatureDescriptor.fromJson(
            rawFeatures[index],
            path: '$path.features[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
    );
  }
}

final class CockpitNegotiationRequest {
  /// Creates a CockpitNegotiationRequest.
  CockpitNegotiationRequest({
    required this.apiVersion,
    Iterable<String> requiredFeatures = const <String>[],
  }) : requiredFeatures = List<String>.unmodifiable(requiredFeatures) {
    final seen = <String>{};
    for (final feature in this.requiredFeatures) {
      CockpitFoundationValueReader.id(feature, r'$.requiredFeatures[]');
      if (!seen.add(feature)) {
        throw FormatException('Duplicate required feature $feature.');
      }
    }
  }

  final CockpitApiVersion apiVersion;
  final List<String> requiredFeatures;

  /// Encodes this CockpitNegotiationRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'apiVersion': apiVersion.toJson(),
    'requiredFeatures': requiredFeatures,
  };

  /// Decodes a CockpitNegotiationRequest from a JSON object.
  factory CockpitNegotiationRequest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'apiVersion', 'requiredFeatures'},
      path,
      required: const <String>{'apiVersion', 'requiredFeatures'},
    );
    return CockpitNegotiationRequest(
      apiVersion: CockpitApiVersion.fromJson(
        json['apiVersion'],
        path: '$path.apiVersion',
      ),
      requiredFeatures: CockpitFoundationValueReader.ids(
        json['requiredFeatures'],
        '$path.requiredFeatures',
      ),
    );
  }
}

final class CockpitNegotiationResult {
  /// Creates a CockpitNegotiationResult.
  CockpitNegotiationResult({
    required this.apiVersion,
    Iterable<String> featureIds = const <String>[],
  }) : featureIds = List<String>.unmodifiable(featureIds) {
    final seen = <String>{};
    for (final featureId in this.featureIds) {
      CockpitFoundationValueReader.id(featureId, r'$.featureIds[]');
      if (!seen.add(featureId)) {
        throw FormatException('Duplicate negotiated feature $featureId.');
      }
    }
  }

  final CockpitApiVersion apiVersion;
  final List<String> featureIds;

  CockpitDecodePolicy get responseDecodePolicy =>
      CockpitDecodePolicy.negotiatedResponse(featureIds);

  /// Encodes this CockpitNegotiationResult as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'apiVersion': apiVersion.toJson(),
    'featureIds': featureIds,
  };

  /// Decodes a CockpitNegotiationResult from a JSON object.
  factory CockpitNegotiationResult.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'apiVersion', 'featureIds'},
      path,
      required: const <String>{'apiVersion', 'featureIds'},
      policy: decodePolicy,
    );
    return CockpitNegotiationResult(
      apiVersion: CockpitApiVersion.fromJson(
        json['apiVersion'],
        path: '$path.apiVersion',
        decodePolicy: decodePolicy,
      ),
      featureIds: CockpitFoundationValueReader.ids(
        json['featureIds'],
        '$path.featureIds',
      ),
    );
  }
}

abstract final class CockpitProtocolNegotiator {
  static CockpitNegotiationResult negotiate({
    required CockpitNegotiationRequest request,
    required CockpitServerInfo server,
  }) {
    final compatibleMajor = request.apiVersion.major == server.apiVersion.major;
    final negotiatedMinor = request.apiVersion.minor < server.apiVersion.minor
        ? request.apiVersion.minor
        : server.apiVersion.minor;
    final availableFeatures = server.features
        .where((feature) => feature.minimumApiMinor <= negotiatedMinor)
        .toList(growable: false);
    final availableFeatureIds = availableFeatures
        .map((feature) => feature.id)
        .toSet();
    final missingFeatures = request.requiredFeatures
        .where((feature) => !availableFeatureIds.contains(feature))
        .toList(growable: false);
    if (!compatibleMajor || missingFeatures.isNotEmpty) {
      throw CockpitApiException(
        CockpitApiError(
          code: CockpitErrorCode.upgradeRequired,
          category: CockpitErrorCategory.unsupported,
          message: !compatibleMajor
              ? 'Client and server API majors are incompatible.'
              : 'The server is missing required client features.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
          redactedDetails: <String, Object?>{
            'clientApiVersion': request.apiVersion.toJson(),
            'serverApiVersion': server.apiVersion.toJson(),
            if (missingFeatures.isNotEmpty) 'missingFeatures': missingFeatures,
          },
        ),
      );
    }
    final features = availableFeatures
        .map((feature) => feature.id)
        .toList(growable: false);
    return CockpitNegotiationResult(
      apiVersion: CockpitApiVersion(
        major: server.apiVersion.major,
        minor: negotiatedMinor,
      ),
      featureIds: features,
    );
  }
}
