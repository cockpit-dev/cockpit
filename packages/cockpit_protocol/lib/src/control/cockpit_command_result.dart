import 'package:collection/collection.dart';

import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../errors/cockpit_command_error.dart';
import '../model/cockpit_artifact_ref.dart';
import 'cockpit_command_type.dart';
import 'cockpit_locator_resolution.dart';

final class CockpitCommandResult {
  /// Creates a CockpitCommandResult.
  CockpitCommandResult({
    required this.success,
    required this.commandId,
    required this.commandType,
    this.locatorResolution,
    required this.durationMs,
    List<CockpitArtifactRef> artifacts = const <CockpitArtifactRef>[],
    Map<String, Object?>? snapshot,
    this.requestedCaptureProfile,
    this.resolvedCaptureKind,
    this.usedCaptureFallback = false,
    this.degradationReason,
    Map<String, Object?>? surface,
    this.changed,
    this.error,
  }) : artifacts = List.unmodifiable(artifacts),
       snapshot = snapshot == null ? null : Map.unmodifiable(snapshot),
       surface = surface == null ? null : Map.unmodifiable(surface);

  final bool success;
  final String commandId;
  final CockpitCommandType commandType;
  final CockpitLocatorResolution? locatorResolution;
  final int durationMs;
  final List<CockpitArtifactRef> artifacts;
  final Map<String, Object?>? snapshot;
  final CockpitCaptureProfile? requestedCaptureProfile;
  final CockpitCaptureKind? resolvedCaptureKind;
  final bool usedCaptureFallback;
  final String? degradationReason;
  final Map<String, Object?>? surface;
  final bool? changed;
  final CockpitCommandError? error;

  static const ListEquality<CockpitArtifactRef> _artifactListEquality =
      ListEquality<CockpitArtifactRef>();
  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();

  /// Encodes this CockpitCommandResult as a JSON object.
  Map<String, Object?> toJson() => {
    'success': success,
    'commandId': commandId,
    'commandType': commandType.name,
    if (locatorResolution != null)
      'locatorResolution': locatorResolution!.toJson(),
    'durationMs': durationMs,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    if (snapshot != null) 'snapshot': snapshot,
    if (requestedCaptureProfile != null)
      'requestedCaptureProfile': requestedCaptureProfile!.name,
    if (resolvedCaptureKind != null)
      'resolvedCaptureKind': resolvedCaptureKind!.name,
    'usedCaptureFallback': usedCaptureFallback,
    if (degradationReason != null) 'degradationReason': degradationReason,
    if (surface != null) 'surface': surface,
    if (changed != null) 'changed': changed,
    if (error != null) 'error': error!.toJson(),
  };

  /// Decodes a CockpitCommandResult from a JSON object.
  factory CockpitCommandResult.fromJson(Map<String, Object?> json) {
    final locatorResolutionJson =
        json['locatorResolution'] as Map<Object?, Object?>?;
    final errorJson = json['error'] as Map<Object?, Object?>?;
    final snapshotJson = json['snapshot'] as Map<Object?, Object?>?;
    final surfaceJson = json['surface'] as Map<Object?, Object?>?;
    final requestedCaptureProfile = json['requestedCaptureProfile'];
    final resolvedCaptureKind = json['resolvedCaptureKind'];

    return CockpitCommandResult(
      success: json['success']! as bool,
      commandId: json['commandId']! as String,
      commandType: CockpitCommandType.fromJson(json['commandType']),
      locatorResolution: locatorResolutionJson == null
          ? null
          : CockpitLocatorResolution.fromJson(
              Map<String, Object?>.from(locatorResolutionJson),
            ),
      durationMs: json['durationMs']! as int,
      artifacts: (json['artifacts'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) =>
                CockpitArtifactRef.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(growable: false),
      snapshot: snapshotJson == null
          ? null
          : Map<String, Object?>.from(snapshotJson),
      requestedCaptureProfile: requestedCaptureProfile == null
          ? null
          : CockpitCaptureProfile.fromJson(requestedCaptureProfile),
      resolvedCaptureKind: resolvedCaptureKind == null
          ? null
          : CockpitCaptureKind.fromJson(resolvedCaptureKind),
      usedCaptureFallback: json['usedCaptureFallback'] as bool? ?? false,
      degradationReason: json['degradationReason'] as String?,
      surface: surfaceJson == null
          ? null
          : Map<String, Object?>.from(surfaceJson),
      changed: json['changed'] as bool?,
      error: errorJson == null
          ? null
          : CockpitCommandError.fromJson(Map<String, Object?>.from(errorJson)),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitCommandResult &&
            other.success == success &&
            other.commandId == commandId &&
            other.commandType == commandType &&
            other.locatorResolution == locatorResolution &&
            other.durationMs == durationMs &&
            _artifactListEquality.equals(other.artifacts, artifacts) &&
            _mapEquality.equals(other.snapshot, snapshot) &&
            other.requestedCaptureProfile == requestedCaptureProfile &&
            other.resolvedCaptureKind == resolvedCaptureKind &&
            other.usedCaptureFallback == usedCaptureFallback &&
            other.degradationReason == degradationReason &&
            _mapEquality.equals(other.surface, surface) &&
            other.changed == changed &&
            other.error == error;
  }

  @override
  int get hashCode => Object.hash(
    success,
    commandId,
    commandType,
    locatorResolution,
    durationMs,
    _artifactListEquality.hash(artifacts),
    snapshot == null ? null : _mapEquality.hash(snapshot!),
    requestedCaptureProfile,
    resolvedCaptureKind,
    usedCaptureFallback,
    degradationReason,
    surface == null ? null : _mapEquality.hash(surface!),
    changed,
    error,
  );
}
