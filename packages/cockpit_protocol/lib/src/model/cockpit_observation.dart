import 'package:collection/collection.dart';

import '../runtime/cockpit_snapshot.dart';
import '../runtime/cockpit_snapshot_options.dart';
import '../runtime/cockpit_plane_kind.dart';
import '../runtime/cockpit_surface_kind.dart';
import '../runtime/cockpit_target_kind.dart';
import 'cockpit_artifact_ref.dart';

enum CockpitObservationPhase {
  baseline,
  beforeAction,
  afterAction,
  failure;

  static CockpitObservationPhase fromJson(Object? json) {
    return values.byName(json! as String);
  }
}

final class CockpitObservation {
  /// Creates a CockpitObservation.
  CockpitObservation({
    this.routeName,
    List<String> interactiveElements = const [],
    this.phase,
    this.diagnosticLevel,
    this.truncated = false,
    this.diagnosticsArtifactRef,
    this.summary,
    this.targetKind,
    this.executionPlane,
    this.surfaceKind,
    this.fallbackUsed = false,
  }) : interactiveElements = List.unmodifiable(interactiveElements);

  final String? routeName;
  final List<String> interactiveElements;
  final CockpitObservationPhase? phase;
  final CockpitSnapshotProfile? diagnosticLevel;
  final bool truncated;
  final CockpitArtifactRef? diagnosticsArtifactRef;
  final CockpitSnapshotSummary? summary;
  final CockpitTargetKind? targetKind;
  final CockpitPlaneKind? executionPlane;
  final CockpitSurfaceKind? surfaceKind;
  final bool fallbackUsed;

  static const ListEquality<String> _listEquality = ListEquality<String>();

  /// Encodes this CockpitObservation as a JSON object.
  Map<String, Object?> toJson() => {
    if (routeName != null) 'routeName': routeName,
    'interactiveElements': interactiveElements,
    if (phase != null) 'phase': phase!.name,
    if (diagnosticLevel != null) 'diagnosticLevel': diagnosticLevel!.jsonValue,
    'truncated': truncated,
    if (diagnosticsArtifactRef != null)
      'diagnosticsArtifactRef': diagnosticsArtifactRef!.toJson(),
    if (summary != null) 'summary': summary!.toJson(),
    if (targetKind != null) 'targetKind': targetKind!.name,
    if (executionPlane != null) 'executionPlane': executionPlane!.name,
    if (surfaceKind != null) 'surfaceKind': surfaceKind!.name,
    if (fallbackUsed) 'fallbackUsed': fallbackUsed,
  };

  /// Decodes a CockpitObservation from a JSON object.
  factory CockpitObservation.fromJson(Map<String, Object?> json) {
    final interactiveElements =
        (json['interactiveElements'] as List<Object?>? ?? const <Object?>[])
            .cast<String>();
    final diagnosticsArtifactJson =
        json['diagnosticsArtifactRef'] as Map<Object?, Object?>?;
    final summaryJson = json['summary'] as Map<Object?, Object?>?;

    return CockpitObservation(
      routeName: json['routeName'] as String?,
      interactiveElements: interactiveElements,
      phase: json['phase'] == null
          ? null
          : CockpitObservationPhase.fromJson(json['phase']),
      diagnosticLevel: json['diagnosticLevel'] == null
          ? null
          : CockpitSnapshotProfile.fromJson(json['diagnosticLevel']),
      truncated: json['truncated'] as bool? ?? false,
      diagnosticsArtifactRef: diagnosticsArtifactJson == null
          ? null
          : CockpitArtifactRef.fromJson(
              Map<String, Object?>.from(diagnosticsArtifactJson),
            ),
      summary: summaryJson == null
          ? null
          : CockpitSnapshotSummary.fromJson(
              Map<String, Object?>.from(summaryJson),
            ),
      targetKind: json['targetKind'] == null
          ? null
          : CockpitTargetKind.fromJson(json['targetKind']),
      executionPlane: json['executionPlane'] == null
          ? null
          : CockpitPlaneKind.fromJson(json['executionPlane']),
      surfaceKind: json['surfaceKind'] == null
          ? null
          : CockpitSurfaceKind.fromJson(json['surfaceKind']),
      fallbackUsed: json['fallbackUsed'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitObservation &&
            other.routeName == routeName &&
            other.phase == phase &&
            other.diagnosticLevel == diagnosticLevel &&
            other.truncated == truncated &&
            other.diagnosticsArtifactRef == diagnosticsArtifactRef &&
            other.summary == summary &&
            other.targetKind == targetKind &&
            other.executionPlane == executionPlane &&
            other.surfaceKind == surfaceKind &&
            other.fallbackUsed == fallbackUsed &&
            _listEquality.equals(
              other.interactiveElements,
              interactiveElements,
            );
  }

  @override
  int get hashCode => Object.hash(
    routeName,
    phase,
    diagnosticLevel,
    truncated,
    diagnosticsArtifactRef,
    summary,
    targetKind,
    executionPlane,
    surfaceKind,
    fallbackUsed,
    _listEquality.hash(interactiveElements),
  );
}
