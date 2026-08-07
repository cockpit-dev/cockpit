// ignore_for_file: deprecated_member_use

import '../context/cockpit_context_bundle.dart';
import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../control/cockpit_command_status.dart';
import '../control/cockpit_command.dart';
import '../control/cockpit_command_result.dart';
import '../control/cockpit_command_type.dart';
import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../errors/cockpit_command_error.dart';
import '../model/cockpit_artifact_ref.dart';
import '../model/cockpit_environment.dart';
import '../model/cockpit_observation.dart';
import '../model/cockpit_step_record.dart';
import '../model/cockpit_task_status.dart';
import '../runtime/cockpit_snapshot.dart';
import 'cockpit_bundle_summary_assembler.dart';
import 'cockpit_observation_assembler.dart';
import 'cockpit_session.dart';
import 'cockpit_step_recorder.dart';
import 'cockpit_timestamp_provider.dart';

final class CockpitSessionController {
  /// Creates a CockpitSessionController.
  CockpitSessionController({
    required String sessionId,
    required String taskId,
    required String platform,
    CockpitTimestampProvider? now,
  }) : _session = CockpitSession(
         sessionId: sessionId,
         taskId: taskId,
         platform: platform,
         startedAt: (now ?? _systemNow)().toUtc(),
       ),
       _stepRecorder = CockpitStepRecorder(
         now: now ?? _systemNow,
         observationAssembler: const CockpitObservationAssembler(),
       ),
       _bundleSummaryAssembler = CockpitBundleSummaryAssembler(now: now);

  final CockpitSession _session;
  final CockpitStepRecorder _stepRecorder;
  final CockpitBundleSummaryAssembler _bundleSummaryAssembler;
  bool _isClosed = false;

  CockpitSession get session => _session;

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
    CockpitCaptureProfile? requestedCaptureProfile,
    CockpitCaptureKind? resolvedCaptureKind,
    bool usedCaptureFallback = false,
    String? degradationReason,
    List<CockpitArtifactRef> captureRefs = const [],
  }) {
    _ensureOpen();
    _stepRecorder.recordStep(
      actionType: actionType,
      actionArgs: actionArgs,
      observation: observation,
      snapshot: snapshot,
      artifactRefs: artifactRefs,
      commandType: commandType,
      locator: locator,
      locatorResolution: locatorResolution,
      commandError: commandError,
      durationMs: durationMs,
      status: status,
      requestedCaptureProfile: requestedCaptureProfile,
      resolvedCaptureKind: resolvedCaptureKind,
      usedCaptureFallback: usedCaptureFallback,
      degradationReason: degradationReason,
      captureRefs: captureRefs,
    );
  }

  void recordCommandResult(
    CockpitCommand command,
    CockpitCommandResult result,
  ) {
    _ensureOpen();
    _stepRecorder.recordCommandResult(command, result);
  }

  void importStepRecords(Iterable<CockpitStepRecord> steps) {
    _ensureOpen();
    _stepRecorder.importStepRecords(steps);
  }

  CockpitContextBundle finish({
    required CockpitEnvironment environment,
    List<String> capabilitiesUsed = const [],
  }) {
    return _close(
      environment: environment,
      status: CockpitTaskStatus.completed,
      capabilitiesUsed: capabilitiesUsed,
    );
  }

  CockpitContextBundle finishWithFailure({
    required CockpitEnvironment environment,
    required String failureSummary,
    List<String> capabilitiesUsed = const [],
  }) {
    return _close(
      environment: environment,
      status: CockpitTaskStatus.failed,
      failureSummary: failureSummary,
      capabilitiesUsed: capabilitiesUsed,
    );
  }

  CockpitContextBundle _close({
    required CockpitEnvironment environment,
    required CockpitTaskStatus status,
    required List<String> capabilitiesUsed,
    String? failureSummary,
  }) {
    _ensureOpen();
    _isClosed = true;
    return _bundleSummaryAssembler.assemble(
      session: _session,
      environment: environment,
      steps: _stepRecorder.steps,
      status: status,
      capabilitiesUsed: capabilitiesUsed,
      failureSummary: failureSummary,
    );
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('Cockpit session is already closed.');
    }
  }

  static DateTime _systemNow() => DateTime.now().toUtc();
}
