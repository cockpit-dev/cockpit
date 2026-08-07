import 'cockpit_test_diagnostic.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestErrorCode {
  parseFailed,
  schemaUnsupported,
  validationFailed,
  bindingFailed,
  safetyDenied,
  secretResolutionFailed,
  targetMismatch,
  unsupportedAction,
  unsupportedLocator,
  conditionError,
  assertionFailed,
  timeout,
  cancelled,
  hardShutdown,
  driverFailed,
  recordingFailed,
  evidenceFailed,
  bundlePublicationFailed,
  bundleIntegrityFailed,
  internalFailure,
}

final class CockpitTestError {
  /// Creates a CockpitTestError.
  CockpitTestError({
    required this.code,
    required this.message,
    this.path,
    this.stepId,
    this.location,
    Map<String, Object?> details = const <String, Object?>{},
  }) : details = Map<String, Object?>.unmodifiable(
         CockpitTestValueReader.object(
           CockpitTestValueReader.jsonValue(details, r'$.details'),
           r'$.details',
         ),
       );

  final CockpitTestErrorCode code;
  final String message;
  final String? path;
  final String? stepId;
  final CockpitTestSourceLocation? location;
  final Map<String, Object?> details;

  /// Encodes this CockpitTestError as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.name,
    'message': message,
    if (path != null) 'path': path,
    if (stepId != null) 'stepId': stepId,
    if (location != null) 'location': location!.toJson(),
    if (details.isNotEmpty) 'details': details,
  };

  /// Decodes a CockpitTestError from a JSON object.
  factory CockpitTestError.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'code',
        'message',
        'path',
        'stepId',
        'location',
        'details',
      },
      path,
      required: const <String>{'code', 'message'},
    );
    return CockpitTestError(
      code: CockpitTestValueReader.enumeration(
        json['code'],
        CockpitTestErrorCode.values,
        '$path.code',
      ),
      message: CockpitTestValueReader.string(json['message'], '$path.message'),
      path: CockpitTestValueReader.optionalString(json['path'], '$path.path'),
      stepId: CockpitTestValueReader.optionalString(
        json['stepId'],
        '$path.stepId',
        id: true,
      ),
      location: json['location'] == null
          ? null
          : CockpitTestSourceLocation.fromJson(
              json['location'],
              path: '$path.location',
            ),
      details: json['details'] == null
          ? const <String, Object?>{}
          : CockpitTestValueReader.object(json['details'], '$path.details'),
    );
  }
}
