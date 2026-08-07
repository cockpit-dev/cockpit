import '../control/cockpit_command.dart';
import '../control/cockpit_command_result.dart';
import '../capture/cockpit_capture_kind.dart';
import '../model/cockpit_artifact_ref.dart';
import '../model/cockpit_observation.dart';
import '../runtime/cockpit_plane_kind.dart';
import '../runtime/cockpit_snapshot.dart';
import '../runtime/cockpit_snapshot_options.dart';
import '../runtime/cockpit_surface_kind.dart';
import '../runtime/cockpit_target_kind.dart';

final class CockpitObservationAssembler {
  /// Creates a CockpitObservationAssembler.
  const CockpitObservationAssembler();

  CockpitSnapshot? normalizeCommandSnapshot(
    CockpitCommand command,
    CockpitCommandResult result, {
    required int stepIndex,
  }) {
    final rawSnapshot = result.snapshot == null
        ? null
        : CockpitSnapshot.fromJson(result.snapshot!);
    if (rawSnapshot == null) {
      return null;
    }
    return _normalizeSnapshotForBundle(
      rawSnapshot,
      command: command,
      stepIndex: stepIndex,
    );
  }

  CockpitObservation? observationFromCommandResult(
    CockpitCommandResult result,
    CockpitSnapshot? snapshot,
  ) {
    if (snapshot == null) {
      return null;
    }

    return CockpitObservation(
      routeName: snapshot.routeName,
      interactiveElements: snapshot.visibleTargets
          .map((target) => target.displayLabel)
          .whereType<String>()
          .toList(growable: false),
      phase: result.success
          ? CockpitObservationPhase.afterAction
          : CockpitObservationPhase.failure,
      diagnosticLevel: snapshot.diagnosticLevel,
      truncated: snapshot.truncated,
      diagnosticsArtifactRef: snapshot.diagnosticsArtifactRef,
      summary: snapshot.summary,
      targetKind: CockpitTargetKind.flutterApp,
      executionPlane: executionPlaneFor(result),
      surfaceKind: surfaceKindFor(result),
      fallbackUsed: result.usedCaptureFallback,
    );
  }

  CockpitSnapshot _normalizeSnapshotForBundle(
    CockpitSnapshot snapshot, {
    required CockpitCommand command,
    required int stepIndex,
  }) {
    final diagnosticsArtifactRef =
        snapshot.diagnosticsArtifactRef ??
        _diagnosticsArtifactRefFor(
          snapshot,
          command: command,
          stepIndex: stepIndex,
        );
    if (diagnosticsArtifactRef == null) {
      return snapshot;
    }

    return CockpitSnapshot(
      routeName: snapshot.routeName,
      visibleTargets: snapshot.visibleTargets,
      diagnosticLevel: snapshot.diagnosticLevel,
      truncated: snapshot.truncated,
      diagnosticsArtifactRef: diagnosticsArtifactRef,
      summary: snapshot.summary,
      network: snapshot.network,
      runtime: snapshot.runtime,
    );
  }

  CockpitArtifactRef? _diagnosticsArtifactRefFor(
    CockpitSnapshot snapshot, {
    required CockpitCommand command,
    required int stepIndex,
  }) {
    final shouldExternalize =
        snapshot.diagnosticLevel == CockpitSnapshotProfile.forensic ||
        snapshot.truncated;
    if (!shouldExternalize) {
      return null;
    }

    final safeCommandId = _sanitizeForPath(
      command.commandId.isEmpty ? command.commandType.name : command.commandId,
    );
    final paddedStepIndex = stepIndex.toString().padLeft(3, '0');
    return CockpitArtifactRef(
      role: 'diagnostics',
      relativePath:
          'diagnostics/step_${paddedStepIndex}_${safeCommandId}_snapshot.json',
    );
  }

  String _sanitizeForPath(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return sanitized.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  CockpitPlaneKind executionPlaneFor(CockpitCommandResult result) {
    return switch (surfaceKindFor(result)) {
      CockpitSurfaceKind.nativeUi => CockpitPlaneKind.nativeUiPlane,
      CockpitSurfaceKind.systemUi => CockpitPlaneKind.deviceSystemPlane,
      CockpitSurfaceKind.hostShell => CockpitPlaneKind.hostPlane,
      _ => CockpitPlaneKind.flutterSemanticPlane,
    };
  }

  CockpitSurfaceKind surfaceKindFor(CockpitCommandResult result) {
    return switch (result.resolvedCaptureKind) {
      CockpitCaptureKind.hostSystem => CockpitSurfaceKind.systemUi,
      CockpitCaptureKind.appNative ||
      CockpitCaptureKind.nativeAcceptance => CockpitSurfaceKind.nativeUi,
      _ => CockpitSurfaceKind.flutterSemantic,
    };
  }
}

List<CockpitPlaneKind> cockpitCaptureFallbackTrailFor(
  CockpitCommandResult result,
) {
  if (!result.usedCaptureFallback) {
    return const <CockpitPlaneKind>[];
  }
  if (result.resolvedCaptureKind == null) {
    return const <CockpitPlaneKind>[];
  }
  final hostCaptureFailed =
      result.degradationReason?.startsWith('hostCapture') == true;
  return switch (result.resolvedCaptureKind) {
    CockpitCaptureKind.flutterView => <CockpitPlaneKind>[
      if (hostCaptureFailed) CockpitPlaneKind.deviceSystemPlane,
      CockpitPlaneKind.nativeUiPlane,
    ],
    CockpitCaptureKind.appNative || CockpitCaptureKind.nativeAcceptance
        when hostCaptureFailed =>
      const <CockpitPlaneKind>[CockpitPlaneKind.deviceSystemPlane],
    _ => const <CockpitPlaneKind>[CockpitPlaneKind.flutterSemanticPlane],
  };
}
