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
    int maxRetainedSteps = _defaultMaxRetainedSteps,
  }) : _now = now,
       _observationAssembler = observationAssembler,
       _maxRetainedSteps = maxRetainedSteps {
    if (maxRetainedSteps < 1) {
      throw ArgumentError.value(
        maxRetainedSteps,
        'maxRetainedSteps',
        'must be at least 1',
      );
    }
  }

  static const int _defaultMaxRetainedSteps = 120;

  final CockpitTimestampProvider _now;
  final CockpitObservationAssembler _observationAssembler;
  final int _maxRetainedSteps;
  final List<CockpitStepRecord> _steps = <CockpitStepRecord>[];

  /// Number of steps evicted by the retention cap. Each evicted step shifts
  /// the reported `index` forward so the surviving records keep their
  /// original session-scoped ordering.
  int _droppedSteps = 0;

  /// Steps dropped by the retention cap since the recorder was created.
  int get droppedSteps => _droppedSteps;

  List<CockpitStepRecord> get steps =>
      List<CockpitStepRecord>.unmodifiable(_steps);

  int get _nextIndex => _droppedSteps + _steps.length;

  void _appendStep(CockpitStepRecord step) {
    _steps.add(step);
    while (_steps.length > _maxRetainedSteps) {
      _steps.removeAt(0);
      _droppedSteps += 1;
    }
  }

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
    _appendStep(
      CockpitStepRecord(
        index: _nextIndex,
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
      stepIndex: _nextIndex,
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
      _appendStep(
        CockpitStepRecord(
          index: _nextIndex,
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
