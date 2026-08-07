import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../control/cockpit_command.dart';
import '../control/cockpit_command_result.dart';
import '../control/cockpit_command_status.dart';
import '../control/cockpit_command_type.dart';
import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../errors/cockpit_command_error.dart';
import '../model/cockpit_artifact_ref.dart';
import '../model/cockpit_observation.dart';
import '../model/cockpit_step_record.dart';
import '../runtime/cockpit_plane_kind.dart';
import '../runtime/cockpit_snapshot.dart';
import '../runtime/cockpit_surface_kind.dart';
import '../runtime/cockpit_target_kind.dart';
import 'cockpit_observation_assembler.dart';
import 'cockpit_timestamp_provider.dart';

final class CockpitStepRecorder {
  /// Creates a CockpitStepRecorder.
  CockpitStepRecorder({
    required CockpitTimestampProvider now,
    required CockpitObservationAssembler observationAssembler,
  }) : _now = now,
       _observationAssembler = observationAssembler;

  final CockpitTimestampProvider _now;
  final CockpitObservationAssembler _observationAssembler;
  final List<CockpitStepRecord> _steps = <CockpitStepRecord>[];

  List<CockpitStepRecord> get steps =>
      List<CockpitStepRecord>.unmodifiable(_steps);

  void recordStep({
    required String actionType,
    required Map<String, Object?> actionArgs,
    CockpitObservation? observation,
    CockpitSnapshot? snapshot,
    List<CockpitArtifactRef> artifactRefs = const [],
    CockpitCommandType? commandType,
    CockpitLocator? locator,
    CockpitLocatorResolution? locatorResolution,
    CockpitCommandError? commandError,
    int? durationMs,
    CockpitCommandStatus? status,
    CockpitTargetKind? targetKind,
    CockpitPlaneKind? executionPlane,
    CockpitSurfaceKind? surfaceKind,
    List<CockpitPlaneKind> fallbackTrail = const <CockpitPlaneKind>[],
    bool usedPlaneFallback = false,
    CockpitCaptureProfile? requestedCaptureProfile,
    CockpitCaptureKind? resolvedCaptureKind,
    bool usedCaptureFallback = false,
    String? degradationReason,
    List<CockpitArtifactRef> captureRefs = const [],
  }) {
    _steps.add(
      CockpitStepRecord(
        index: _steps.length,
        actionType: actionType,
        actionArgs: actionArgs,
        observedAt: _now().toUtc(),
        observation: observation,
        snapshot: snapshot,
        artifactRefs: artifactRefs,
        commandType: commandType,
        locator: locator,
        locatorResolution: locatorResolution,
        commandError: commandError,
        durationMs: durationMs,
        status: status,
        targetKind: targetKind,
        executionPlane: executionPlane,
        surfaceKind: surfaceKind,
        fallbackTrail: fallbackTrail,
        usedPlaneFallback: usedPlaneFallback,
        requestedCaptureProfile: requestedCaptureProfile,
        resolvedCaptureKind: resolvedCaptureKind,
        usedCaptureFallback: usedCaptureFallback,
        degradationReason: degradationReason,
        captureRefs: captureRefs,
      ),
    );
  }

  void recordCommandResult(
    CockpitCommand command,
    CockpitCommandResult result,
  ) {
    final snapshot = _observationAssembler.normalizeCommandSnapshot(
      command,
      result,
      stepIndex: _steps.length,
    );
    final observation = _observationAssembler.observationFromCommandResult(
      result,
      snapshot,
    );
    final hasCaptureSource = result.resolvedCaptureKind != null;
    final executionPlane =
        observation?.executionPlane ??
        (hasCaptureSource
            ? _observationAssembler.executionPlaneFor(result)
            : null);
    final surfaceKind =
        observation?.surfaceKind ??
        (hasCaptureSource
            ? _observationAssembler.surfaceKindFor(result)
            : null);
    final usedPlaneFallback =
        observation?.fallbackUsed == true || result.usedCaptureFallback;

    recordStep(
      actionType: command.commandType.name,
      actionArgs: <String, Object?>{
        'commandId': command.commandId,
        ...command.parameters,
      },
      observation: observation,
      snapshot: snapshot,
      artifactRefs: <CockpitArtifactRef>[
        ...result.artifacts,
        if (snapshot?.diagnosticsArtifactRef != null)
          snapshot!.diagnosticsArtifactRef!,
      ],
      commandType: command.commandType,
      locator: command.locator,
      locatorResolution: result.locatorResolution,
      commandError: result.error,
      durationMs: result.durationMs,
      status: result.success
          ? CockpitCommandStatus.succeeded
          : CockpitCommandStatus.failed,
      targetKind: observation?.targetKind,
      executionPlane: executionPlane,
      surfaceKind: surfaceKind,
      fallbackTrail: cockpitCaptureFallbackTrailFor(result),
      usedPlaneFallback: usedPlaneFallback,
      requestedCaptureProfile: result.requestedCaptureProfile,
      resolvedCaptureKind: result.resolvedCaptureKind,
      usedCaptureFallback: result.usedCaptureFallback,
      degradationReason: result.degradationReason,
      captureRefs: result.artifacts
          .where(
            (artifact) =>
                artifact.role == 'screenshot' ||
                artifact.role == 'step_screenshot',
          )
          .toList(growable: false),
    );
  }

  void importStepRecords(Iterable<CockpitStepRecord> steps) {
    for (final step in steps) {
      _steps.add(
        CockpitStepRecord(
          index: _steps.length,
          actionType: step.actionType,
          actionArgs: step.actionArgs,
          observedAt: step.observedAt,
          observation: step.observation,
          snapshot: step.snapshot,
          artifactRefs: step.artifactRefs,
          commandType: step.commandType,
          locator: step.locator,
          locatorResolution: step.locatorResolution,
          commandError: step.commandError,
          durationMs: step.durationMs,
          status: step.status,
          targetKind: step.targetKind,
          executionPlane: step.executionPlane,
          surfaceKind: step.surfaceKind,
          fallbackTrail: step.fallbackTrail,
          usedPlaneFallback: step.usedPlaneFallback,
          requestedCaptureProfile: step.requestedCaptureProfile,
          resolvedCaptureKind: step.resolvedCaptureKind,
          usedCaptureFallback: step.usedCaptureFallback,
          degradationReason: step.degradationReason,
          captureRefs: step.captureRefs,
        ),
      );
    }
  }
}
