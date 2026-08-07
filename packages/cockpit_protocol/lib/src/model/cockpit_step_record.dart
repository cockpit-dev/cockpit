import 'package:collection/collection.dart';

import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../control/cockpit_command_status.dart';
import '../control/cockpit_command_type.dart';
import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../errors/cockpit_command_error.dart';
import '../runtime/cockpit_plane_kind.dart';
import '../runtime/cockpit_snapshot.dart';
import '../runtime/cockpit_surface_kind.dart';
import '../runtime/cockpit_target_kind.dart';
import 'cockpit_artifact_ref.dart';
import 'cockpit_observation.dart';

final class CockpitStepRecord {
  /// Creates a CockpitStepRecord.
  CockpitStepRecord({
    required this.index,
    required this.actionType,
    required Map<String, Object?> actionArgs,
    required this.observedAt,
    this.observation,
    this.snapshot,
    List<CockpitArtifactRef> artifactRefs = const [],
    this.commandType,
    this.locator,
    this.locatorResolution,
    this.commandError,
    this.durationMs,
    this.status,
    this.targetKind,
    this.executionPlane,
    this.surfaceKind,
    List<CockpitPlaneKind> fallbackTrail = const <CockpitPlaneKind>[],
    this.usedPlaneFallback = false,
    this.requestedCaptureProfile,
    this.resolvedCaptureKind,
    this.usedCaptureFallback = false,
    this.degradationReason,
    List<CockpitArtifactRef> captureRefs = const [],
  }) : actionArgs = Map.unmodifiable(actionArgs),
       artifactRefs = List.unmodifiable(artifactRefs),
       fallbackTrail = List.unmodifiable(fallbackTrail),
       captureRefs = List.unmodifiable(captureRefs);

  final int index;
  final String actionType;
  final Map<String, Object?> actionArgs;
  final DateTime observedAt;
  final CockpitObservation? observation;
  final CockpitSnapshot? snapshot;
  final List<CockpitArtifactRef> artifactRefs;
  final CockpitCommandType? commandType;
  final CockpitLocator? locator;
  final CockpitLocatorResolution? locatorResolution;
  final CockpitCommandError? commandError;
  final int? durationMs;
  final CockpitCommandStatus? status;
  final CockpitTargetKind? targetKind;
  final CockpitPlaneKind? executionPlane;
  final CockpitSurfaceKind? surfaceKind;
  final List<CockpitPlaneKind> fallbackTrail;
  final bool usedPlaneFallback;
  final CockpitCaptureProfile? requestedCaptureProfile;
  final CockpitCaptureKind? resolvedCaptureKind;
  final bool usedCaptureFallback;
  final String? degradationReason;
  final List<CockpitArtifactRef> captureRefs;

  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();
  static const ListEquality<CockpitArtifactRef> _artifactListEquality =
      ListEquality<CockpitArtifactRef>();
  static const ListEquality<CockpitPlaneKind> _planeListEquality =
      ListEquality<CockpitPlaneKind>();

  /// Encodes this CockpitStepRecord as a JSON object.
  Map<String, Object?> toJson() => {
    'index': index,
    'actionType': actionType,
    'actionArgs': actionArgs,
    'observedAt': observedAt.toUtc().toIso8601String(),
    if (observation != null) 'observation': observation!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    'artifactRefs': artifactRefs.map((artifact) => artifact.toJson()).toList(),
    if (commandType != null) 'commandType': commandType!.name,
    if (locator != null) 'locator': locator!.toJson(),
    if (locatorResolution != null)
      'locatorResolution': locatorResolution!.toJson(),
    if (commandError != null) 'commandError': commandError!.toJson(),
    if (durationMs != null) 'durationMs': durationMs,
    if (status != null) 'status': status!.name,
    if (targetKind != null) 'targetKind': targetKind!.name,
    if (executionPlane != null) 'executionPlane': executionPlane!.name,
    if (surfaceKind != null) 'surfaceKind': surfaceKind!.name,
    if (fallbackTrail.isNotEmpty)
      'fallbackTrail': fallbackTrail.map((plane) => plane.name).toList(),
    if (usedPlaneFallback) 'usedPlaneFallback': usedPlaneFallback,
    if (requestedCaptureProfile != null)
      'requestedCaptureProfile': requestedCaptureProfile!.name,
    if (resolvedCaptureKind != null)
      'resolvedCaptureKind': resolvedCaptureKind!.name,
    'usedCaptureFallback': usedCaptureFallback,
    if (degradationReason != null) 'degradationReason': degradationReason,
    'captureRefs': captureRefs.map((artifact) => artifact.toJson()).toList(),
  };

  /// Decodes a CockpitStepRecord from a JSON object.
  factory CockpitStepRecord.fromJson(Map<String, Object?> json) {
    final actionArgs = Map<String, Object?>.from(
      (json['actionArgs'] as Map<Object?, Object?>?) ??
          const <Object?, Object?>{},
    );
    final artifactRefs =
        (json['artifactRefs'] as List<Object?>? ?? const <Object?>[])
            .cast<Map<Object?, Object?>>()
            .map(
              (item) =>
                  CockpitArtifactRef.fromJson(Map<String, Object?>.from(item)),
            )
            .toList();
    final observationJson = json['observation'] as Map<Object?, Object?>?;
    final snapshotJson = json['snapshot'] as Map<Object?, Object?>?;
    final locatorJson = json['locator'] as Map<Object?, Object?>?;
    final locatorResolutionJson =
        json['locatorResolution'] as Map<Object?, Object?>?;
    final commandErrorJson = json['commandError'] as Map<Object?, Object?>?;
    final captureRefs =
        (json['captureRefs'] as List<Object?>? ?? const <Object?>[])
            .cast<Map<Object?, Object?>>()
            .map(
              (item) =>
                  CockpitArtifactRef.fromJson(Map<String, Object?>.from(item)),
            )
            .toList();

    return CockpitStepRecord(
      index: json['index']! as int,
      actionType: json['actionType']! as String,
      actionArgs: actionArgs,
      observedAt: DateTime.parse(json['observedAt']! as String).toUtc(),
      observation: observationJson == null
          ? null
          : CockpitObservation.fromJson(
              Map<String, Object?>.from(observationJson),
            ),
      snapshot: snapshotJson == null
          ? null
          : CockpitSnapshot.fromJson(Map<String, Object?>.from(snapshotJson)),
      artifactRefs: artifactRefs,
      commandType: json['commandType'] == null
          ? null
          : CockpitCommandType.fromJson(json['commandType']),
      locator: locatorJson == null
          ? null
          : CockpitLocator.fromJson(Map<String, Object?>.from(locatorJson)),
      locatorResolution: locatorResolutionJson == null
          ? null
          : CockpitLocatorResolution.fromJson(
              Map<String, Object?>.from(locatorResolutionJson),
            ),
      commandError: commandErrorJson == null
          ? null
          : CockpitCommandError.fromJson(
              Map<String, Object?>.from(commandErrorJson),
            ),
      durationMs: json['durationMs'] as int?,
      status: json['status'] == null
          ? null
          : CockpitCommandStatus.fromJson(json['status']),
      targetKind: json['targetKind'] == null
          ? null
          : CockpitTargetKind.fromJson(json['targetKind']),
      executionPlane: json['executionPlane'] == null
          ? null
          : CockpitPlaneKind.fromJson(json['executionPlane']),
      surfaceKind: json['surfaceKind'] == null
          ? null
          : CockpitSurfaceKind.fromJson(json['surfaceKind']),
      fallbackTrail:
          (json['fallbackTrail'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitPlaneKind.fromJson)
              .toList(growable: false),
      usedPlaneFallback: json['usedPlaneFallback'] as bool? ?? false,
      requestedCaptureProfile: json['requestedCaptureProfile'] == null
          ? null
          : CockpitCaptureProfile.fromJson(json['requestedCaptureProfile']),
      resolvedCaptureKind: json['resolvedCaptureKind'] == null
          ? null
          : CockpitCaptureKind.fromJson(json['resolvedCaptureKind']),
      usedCaptureFallback: json['usedCaptureFallback'] as bool? ?? false,
      degradationReason: json['degradationReason'] as String?,
      captureRefs: captureRefs,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitStepRecord &&
            other.index == index &&
            other.actionType == actionType &&
            _mapEquality.equals(other.actionArgs, actionArgs) &&
            other.observedAt == observedAt &&
            other.observation == observation &&
            other.snapshot == snapshot &&
            other.commandType == commandType &&
            other.locator == locator &&
            other.locatorResolution == locatorResolution &&
            other.commandError == commandError &&
            other.durationMs == durationMs &&
            other.status == status &&
            other.targetKind == targetKind &&
            other.executionPlane == executionPlane &&
            other.surfaceKind == surfaceKind &&
            other.usedPlaneFallback == usedPlaneFallback &&
            other.requestedCaptureProfile == requestedCaptureProfile &&
            other.resolvedCaptureKind == resolvedCaptureKind &&
            other.usedCaptureFallback == usedCaptureFallback &&
            other.degradationReason == degradationReason &&
            _planeListEquality.equals(other.fallbackTrail, fallbackTrail) &&
            _artifactListEquality.equals(other.artifactRefs, artifactRefs) &&
            _artifactListEquality.equals(other.captureRefs, captureRefs);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    index,
    actionType,
    _mapEquality.hash(actionArgs),
    observedAt,
    observation,
    snapshot,
    commandType,
    locator,
    locatorResolution,
    commandError,
    durationMs,
    status,
    targetKind,
    executionPlane,
    surfaceKind,
    _planeListEquality.hash(fallbackTrail),
    usedPlaneFallback,
    requestedCaptureProfile,
    resolvedCaptureKind,
    usedCaptureFallback,
    degradationReason,
    _artifactListEquality.hash(artifactRefs),
    _artifactListEquality.hash(captureRefs),
  ]);
}
