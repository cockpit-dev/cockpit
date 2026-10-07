import 'package:cockpit_protocol/cockpit_protocol.dart';

enum CockpitReplayStatus { passed, deviated, skipped }

/// Outcome of replaying one recorded step through the verify-replay pass.
///
/// App-side concept: the report surfaces in the recorder panel, but it is
/// serialized like every other model so tests and future remote exposure
/// share one shape.
final class CockpitReplayReport {
  /// Creates a CockpitReplayReport.
  const CockpitReplayReport({
    required this.stepId,
    required this.kind,
    required this.status,
    this.reason,
  });

  final String stepId;
  final CockpitInteractionStepKind kind;
  final CockpitReplayStatus status;

  /// Why the step deviated (locator resolution failure, action failure) or
  /// was skipped (kind not replayable in-process); `null` when passed.
  final String? reason;

  /// Encodes this CockpitReplayReport as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'stepId': stepId,
    'kind': kind.name,
    'status': status.name,
    if (reason != null) 'reason': reason,
  };

  /// Decodes a CockpitReplayReport from a JSON object.
  factory CockpitReplayReport.fromJson(Object? value, {String path = r'$'}) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected an object at $path.');
    }
    final json = Map<String, Object?>.from(value);
    for (final field in const <String>['stepId', 'kind', 'status']) {
      if (!json.containsKey(field)) {
        throw FormatException('Missing required field $path.$field.');
      }
    }
    final reason = json['reason'];
    if (reason != null && reason is! String) {
      throw FormatException('Expected a string at $path.reason.');
    }
    final typedReason = reason is String ? reason : null;
    return CockpitReplayReport(
      stepId: _nonEmptyString(json['stepId'], '$path.stepId'),
      kind: CockpitInteractionStepKind.fromJson(
        json['kind'],
        path: '$path.kind',
      ),
      status: _statusFromName(
        _nonEmptyString(json['status'], '$path.status'),
        '$path.status',
      ),
      reason: typedReason,
    );
  }

  static String _nonEmptyString(Object? value, String path) {
    if (value is! String || value.isEmpty) {
      throw FormatException('Expected a non-empty string at $path.');
    }
    return value;
  }

  static CockpitReplayStatus _statusFromName(String name, String path) {
    for (final status in CockpitReplayStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    throw FormatException('Unsupported replay status "$name" at $path.');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitReplayReport &&
            other.stepId == stepId &&
            other.kind == kind &&
            other.status == status &&
            other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(stepId, kind, status, reason);
}
