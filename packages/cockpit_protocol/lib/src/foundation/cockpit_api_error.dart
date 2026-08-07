import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_artifact.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitErrorCategory {
  invalidInput,
  unsupported,
  environment,
  resource,
  driver,
  locator,
  assertion,
  application,
  evidence,
  cancelled,
  interrupted,
  internal,
}

enum CockpitResponsibleLayer {
  client,
  supervisor,
  worker,
  provider,
  driver,
  application,
}

enum CockpitWarningStage { cleanup, evidence }

abstract final class CockpitErrorCode {
  static const invalidRequest = 'invalidRequest';
  static const authenticationRequired = 'authenticationRequired';
  static const authorizationDenied = 'authorizationDenied';
  static const notFound = 'notFound';
  static const conflict = 'conflict';
  static const upgradeRequired = 'upgradeRequired';
  static const unsupportedOperation = 'unsupportedOperation';
  static const resourceBusy = 'resourceBusy';
  static const staleReference = 'staleReference';
  static const transportFailed = 'transportFailed';
  static const driverUnavailable = 'driverUnavailable';
  static const locatorNotFound = 'locatorNotFound';
  static const assertionFailed = 'assertionFailed';
  static const applicationFailed = 'applicationFailed';
  static const evidenceFailed = 'evidenceFailed';
  static const cancelled = 'cancelled';
  static const interrupted = 'interrupted';
  static const internalError = 'internalError';
}

final class CockpitApiError {
  /// Creates a CockpitApiError.
  CockpitApiError({
    required this.code,
    required this.category,
    required this.message,
    required this.retryable,
    required this.responsibleLayer,
    Map<String, Object?> redactedDetails = const <String, Object?>{},
    Iterable<CockpitArtifactReference> artifacts =
        const <CockpitArtifactReference>[],
  }) : redactedDetails = CockpitFoundationValueReader.jsonObject(
         redactedDetails,
         r'$.redactedDetails',
       ),
       artifacts = List<CockpitArtifactReference>.unmodifiable(artifacts) {
    CockpitFoundationValueReader.id(code, r'$.code');
    CockpitFoundationValueReader.string(message, r'$.message', maximum: 4096);
    final ids = <String>{};
    for (final artifact in this.artifacts) {
      if (!ids.add(artifact.artifactId)) {
        throw FormatException(
          'Duplicate error artifact ${artifact.artifactId}.',
        );
      }
    }
  }

  final String code;
  final CockpitErrorCategory category;
  final String message;
  final bool retryable;
  final CockpitResponsibleLayer responsibleLayer;
  final Map<String, Object?> redactedDetails;
  final List<CockpitArtifactReference> artifacts;

  /// Encodes this CockpitApiError as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'category': category.name,
    'message': message,
    'retryable': retryable,
    'responsibleLayer': responsibleLayer.name,
    if (redactedDetails.isNotEmpty) 'redactedDetails': redactedDetails,
    if (artifacts.isNotEmpty)
      'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };

  /// Decodes a CockpitApiError from a JSON object.
  factory CockpitApiError.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'code',
        'category',
        'message',
        'retryable',
        'responsibleLayer',
        'redactedDetails',
        'artifacts',
      },
      path,
      required: const <String>{
        'code',
        'category',
        'message',
        'retryable',
        'responsibleLayer',
      },
      policy: decodePolicy,
    );
    final rawArtifacts = json['artifacts'] == null
        ? const <Object?>[]
        : CockpitFoundationValueReader.list(
            json['artifacts'],
            '$path.artifacts',
          );
    return CockpitApiError(
      code: CockpitFoundationValueReader.id(json['code'], '$path.code'),
      category: _closedEnum(
        json['category'],
        CockpitErrorCategory.values,
        '$path.category',
      ),
      message: CockpitFoundationValueReader.string(
        json['message'],
        '$path.message',
        maximum: 4096,
      ),
      retryable: CockpitFoundationValueReader.boolean(
        json['retryable'],
        '$path.retryable',
      ),
      responsibleLayer: _closedEnum(
        json['responsibleLayer'],
        CockpitResponsibleLayer.values,
        '$path.responsibleLayer',
      ),
      redactedDetails: json['redactedDetails'] == null
          ? const <String, Object?>{}
          : CockpitFoundationValueReader.jsonObject(
              json['redactedDetails'],
              '$path.redactedDetails',
            ),
      artifacts: <CockpitArtifactReference>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          CockpitArtifactReference.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
    );
  }
}

final class CockpitApiWarning {
  /// Creates a CockpitApiWarning.
  CockpitApiWarning({required this.stage, required this.error});

  final CockpitWarningStage stage;
  final CockpitApiError error;

  /// Encodes this CockpitApiWarning as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'stage': stage.name,
    'error': error.toJson(),
  };

  /// Decodes a CockpitApiWarning from a JSON object.
  factory CockpitApiWarning.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'stage', 'error'},
      path,
      required: const <String>{'stage', 'error'},
      policy: decodePolicy,
    );
    return CockpitApiWarning(
      stage: _closedEnum(
        json['stage'],
        CockpitWarningStage.values,
        '$path.stage',
      ),
      error: CockpitApiError.fromJson(
        json['error'],
        path: '$path.error',
        decodePolicy: decodePolicy,
      ),
    );
  }
}

final class CockpitFailure {
  /// Creates a CockpitFailure.
  CockpitFailure({
    required this.primary,
    Iterable<CockpitApiWarning> warnings = const <CockpitApiWarning>[],
  }) : warnings = List<CockpitApiWarning>.unmodifiable(warnings) {
    artifacts =
        List<CockpitArtifactReference>.unmodifiable(<CockpitArtifactReference>[
          ...primary.artifacts,
          for (final warning in this.warnings) ...warning.error.artifacts,
        ]);
  }

  final CockpitApiError primary;
  final List<CockpitApiWarning> warnings;
  late final List<CockpitArtifactReference> artifacts;

  /// Encodes this CockpitFailure as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'primary': primary.toJson(),
    if (warnings.isNotEmpty)
      'warnings': warnings.map((warning) => warning.toJson()).toList(),
  };

  /// Decodes a CockpitFailure from a JSON object.
  factory CockpitFailure.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'primary', 'warnings'},
      path,
      required: const <String>{'primary'},
      policy: decodePolicy,
    );
    final rawWarnings = json['warnings'] == null
        ? const <Object?>[]
        : CockpitFoundationValueReader.list(json['warnings'], '$path.warnings');
    return CockpitFailure(
      primary: CockpitApiError.fromJson(
        json['primary'],
        path: '$path.primary',
        decodePolicy: decodePolicy,
      ),
      warnings: <CockpitApiWarning>[
        for (var index = 0; index < rawWarnings.length; index += 1)
          CockpitApiWarning.fromJson(
            rawWarnings[index],
            path: '$path.warnings[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
    );
  }
}

final class CockpitApiErrorResponse {
  /// Creates a CockpitApiErrorResponse.
  CockpitApiErrorResponse({
    this.schemaVersion = 'cockpit.foundation/v2',
    required this.requestId,
    required this.timestamp,
    required this.failure,
  }) {
    if (schemaVersion != 'cockpit.foundation/v2') {
      throw const FormatException('Invalid foundation schemaVersion.');
    }
    CockpitFoundationValueReader.id(requestId, r'$.requestId');
    CockpitFoundationValueReader.utcDateTime(timestamp, r'$.timestamp');
  }

  final String schemaVersion;
  final String requestId;
  final DateTime timestamp;
  final CockpitFailure failure;

  /// Encodes this CockpitApiErrorResponse as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'requestId': requestId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'failure': failure.toJson(),
  };

  /// Decodes a CockpitApiErrorResponse from a JSON object.
  factory CockpitApiErrorResponse.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'schemaVersion',
      'requestId',
      'timestamp',
      'failure',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields,
      policy: decodePolicy,
    );
    return CockpitApiErrorResponse(
      schemaVersion: CockpitFoundationValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      requestId: CockpitFoundationValueReader.id(
        json['requestId'],
        '$path.requestId',
      ),
      timestamp: CockpitFoundationValueReader.dateTime(
        json['timestamp'],
        '$path.timestamp',
      ),
      failure: CockpitFailure.fromJson(
        json['failure'],
        path: '$path.failure',
        decodePolicy: decodePolicy,
      ),
    );
  }
}

final class CockpitApiException implements Exception {
  /// Creates a CockpitApiException.
  const CockpitApiException(this.error);

  final CockpitApiError error;

  @override
  String toString() => '${error.code}: ${error.message}';
}

T _closedEnum<T extends Enum>(Object? value, List<T> values, String path) {
  return CockpitEnumValue<T>.parse(
    value,
    values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}
