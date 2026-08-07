import 'package:collection/collection.dart';

import 'cockpit_action_capability.dart';
import 'cockpit_evidence_capability.dart';
import 'cockpit_quality_flag.dart';
import 'cockpit_surface_kind.dart';
import 'cockpit_target_kind.dart';

final class CockpitCapabilityProfile {
  /// Creates a CockpitCapabilityProfile.
  CockpitCapabilityProfile({
    required this.targetKind,
    Set<CockpitSurfaceKind> surfaceKinds = const <CockpitSurfaceKind>{},
    Set<CockpitActionCapability> actionCapabilities =
        const <CockpitActionCapability>{},
    Set<CockpitEvidenceCapability> evidenceCapabilities =
        const <CockpitEvidenceCapability>{},
    Set<CockpitQualityFlag> qualityFlags = const <CockpitQualityFlag>{},
  }) : surfaceKinds = Set.unmodifiable(surfaceKinds),
       actionCapabilities = Set.unmodifiable(actionCapabilities),
       evidenceCapabilities = Set.unmodifiable(evidenceCapabilities),
       qualityFlags = Set.unmodifiable(qualityFlags);

  final CockpitTargetKind targetKind;
  final Set<CockpitSurfaceKind> surfaceKinds;
  final Set<CockpitActionCapability> actionCapabilities;
  final Set<CockpitEvidenceCapability> evidenceCapabilities;
  final Set<CockpitQualityFlag> qualityFlags;

  static const SetEquality<CockpitSurfaceKind> _surfaceEquality =
      SetEquality<CockpitSurfaceKind>();
  static const SetEquality<CockpitActionCapability> _actionEquality =
      SetEquality<CockpitActionCapability>();
  static const SetEquality<CockpitEvidenceCapability> _evidenceEquality =
      SetEquality<CockpitEvidenceCapability>();
  static const SetEquality<CockpitQualityFlag> _qualityEquality =
      SetEquality<CockpitQualityFlag>();

  bool supportsSurface(CockpitSurfaceKind surfaceKind) {
    return surfaceKinds.contains(surfaceKind);
  }

  bool supportsAction(CockpitActionCapability actionCapability) {
    return actionCapabilities.contains(actionCapability);
  }

  bool supportsEvidence(CockpitEvidenceCapability evidenceCapability) {
    return evidenceCapabilities.contains(evidenceCapability);
  }

  /// Encodes this CockpitCapabilityProfile as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'targetKind': targetKind.name,
    'surfaceKinds': surfaceKinds
        .map((surfaceKind) => surfaceKind.name)
        .toList(),
    'actionCapabilities': actionCapabilities
        .map((actionCapability) => actionCapability.name)
        .toList(),
    'evidenceCapabilities': evidenceCapabilities
        .map((evidenceCapability) => evidenceCapability.name)
        .toList(),
    'qualityFlags': qualityFlags
        .map((qualityFlag) => qualityFlag.name)
        .toList(),
  };

  /// Decodes a CockpitCapabilityProfile from a JSON object.
  factory CockpitCapabilityProfile.fromJson(Map<String, Object?> json) {
    return CockpitCapabilityProfile(
      targetKind: CockpitTargetKind.fromJson(json['targetKind']),
      surfaceKinds:
          (json['surfaceKinds'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitSurfaceKind.fromJson)
              .toSet(),
      actionCapabilities:
          (json['actionCapabilities'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitActionCapability.fromJson)
              .toSet(),
      evidenceCapabilities:
          (json['evidenceCapabilities'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitEvidenceCapability.fromJson)
              .toSet(),
      qualityFlags:
          (json['qualityFlags'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitQualityFlag.fromJson)
              .toSet(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitCapabilityProfile &&
            other.targetKind == targetKind &&
            _surfaceEquality.equals(other.surfaceKinds, surfaceKinds) &&
            _actionEquality.equals(
              other.actionCapabilities,
              actionCapabilities,
            ) &&
            _evidenceEquality.equals(
              other.evidenceCapabilities,
              evidenceCapabilities,
            ) &&
            _qualityEquality.equals(other.qualityFlags, qualityFlags);
  }

  @override
  int get hashCode => Object.hash(
    targetKind,
    _surfaceEquality.hash(surfaceKinds),
    _actionEquality.hash(actionCapabilities),
    _evidenceEquality.hash(evidenceCapabilities),
    _qualityEquality.hash(qualityFlags),
  );
}
