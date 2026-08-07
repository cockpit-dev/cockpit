import 'package:collection/collection.dart';

final class CockpitEvidencePolicy {
  /// Creates a CockpitEvidencePolicy.
  const CockpitEvidencePolicy({
    this.captureBeforeAction = false,
    this.captureAfterAction = false,
    this.captureOnFailure = true,
    this.attachArtifactMetadataOnly = false,
    this.escalateToDiagnosticsOnAmbiguity = false,
  });

  final bool captureBeforeAction;
  final bool captureAfterAction;
  final bool captureOnFailure;
  final bool attachArtifactMetadataOnly;
  final bool escalateToDiagnosticsOnAmbiguity;

  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();

  /// Encodes this CockpitEvidencePolicy as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'captureBeforeAction': captureBeforeAction,
    'captureAfterAction': captureAfterAction,
    'captureOnFailure': captureOnFailure,
    'attachArtifactMetadataOnly': attachArtifactMetadataOnly,
    'escalateToDiagnosticsOnAmbiguity': escalateToDiagnosticsOnAmbiguity,
  };

  /// Decodes a CockpitEvidencePolicy from a JSON object.
  factory CockpitEvidencePolicy.fromJson(Map<String, Object?> json) {
    return CockpitEvidencePolicy(
      captureBeforeAction: json['captureBeforeAction'] as bool? ?? false,
      captureAfterAction: json['captureAfterAction'] as bool? ?? false,
      captureOnFailure: json['captureOnFailure'] as bool? ?? true,
      attachArtifactMetadataOnly:
          json['attachArtifactMetadataOnly'] as bool? ?? false,
      escalateToDiagnosticsOnAmbiguity:
          json['escalateToDiagnosticsOnAmbiguity'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitEvidencePolicy &&
            _mapEquality.equals(other.toJson(), toJson());
  }

  @override
  int get hashCode => _mapEquality.hash(toJson());
}
