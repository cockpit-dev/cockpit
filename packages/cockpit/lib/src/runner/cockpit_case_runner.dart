import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_automation_adapter.dart';
import '../adapters/cockpit_capture_adapter.dart';
import '../adapters/cockpit_recording_adapter.dart';
import '../artifacts/cockpit_test_attempt_bundle_writer.dart';
import '../artifacts/cockpit_test_attempt_recorder.dart';
import '../infrastructure/cockpit_monotonic_clock.dart';
import '../test/cockpit_test_action_lowerer.dart';
import '../test/cockpit_test_document_compiler.dart';
import '../test/cockpit_test_execution_plan.dart';
import '../test/cockpit_test_safety_policy.dart';
import '../test/cockpit_test_secret_resolver.dart';
import '../test/cockpit_test_variable_binder.dart';
import 'cockpit_case_driver_delegate.dart';
import 'cockpit_case_execution_control.dart';
import 'cockpit_case_execution_kernel.dart';

final class CockpitCaseRunner {
  CockpitCaseRunner({
    required CockpitAutomationAdapter automationAdapter,
    CockpitCaptureAdapter? captureAdapter,
    CockpitRecordingAdapter? recordingAdapter,
    CockpitAutomationAdapter? systemAutomationAdapter,
    CockpitCaptureAdapter? systemCaptureAdapter,
    CockpitRecordingAdapter? systemRecordingAdapter,
    required CockpitTestSecretResolver secretResolver,
    required CockpitTestSafetyPolicy safetyPolicy,
    CockpitTestBundlePrePublicationValidator? bundlePrePublicationValidator,
    CockpitMonotonicClock? clock,
    CockpitTestActionLowerer lowerer = const CockpitTestActionLowerer(),
  }) : _automationAdapter = automationAdapter,
       _captureAdapter = captureAdapter,
       _recordingAdapter = recordingAdapter,
       _systemAutomationAdapter = systemAutomationAdapter,
       _systemCaptureAdapter = systemCaptureAdapter,
       _systemRecordingAdapter = systemRecordingAdapter,
       _secretResolver = secretResolver,
       _safetyPolicy = safetyPolicy,
       _bundlePrePublicationValidator = bundlePrePublicationValidator,
       _clock = clock ?? CockpitSystemMonotonicClock(),
       _lowerer = lowerer;

  final CockpitAutomationAdapter _automationAdapter;
  final CockpitCaptureAdapter? _captureAdapter;
  final CockpitRecordingAdapter? _recordingAdapter;
  final CockpitAutomationAdapter? _systemAutomationAdapter;
  final CockpitCaptureAdapter? _systemCaptureAdapter;
  final CockpitRecordingAdapter? _systemRecordingAdapter;
  final CockpitTestSecretResolver _secretResolver;
  final CockpitTestSafetyPolicy _safetyPolicy;
  final CockpitTestBundlePrePublicationValidator?
  _bundlePrePublicationValidator;
  final CockpitTestActionLowerer _lowerer;
  final CockpitMonotonicClock _clock;
  final CockpitTestAttemptBundleWriter _bundleWriter =
      const CockpitTestAttemptBundleWriter();

  Future<CockpitTestAttemptResult> run({
    required CockpitCompiledTestCase compiled,
    required CockpitTestRunContext context,
    required String targetId,
    required CockpitTestTargetEnvironment targetEnvironment,
    required String reportRoot,
    Map<String, Object?> inputs = const <String, Object?>{},
    CockpitTestExecutionPlan? preparedPlan,
    CockpitCaseExecutionControl? control,
  }) async {
    final startedAt = _clock.utcNow;
    final startedElapsed = _clock.elapsed;
    final executionControl = control ?? CockpitCaseExecutionControl();
    if (context.caseId != compiled.testCase.id) {
      return _publishPreparationFailure(
        compiled: compiled,
        context: context,
        targetId: targetId,
        reportRoot: reportRoot,
        startedAt: startedAt,
        startedElapsed: startedElapsed,
        error: CockpitTestError(
          code: CockpitTestErrorCode.validationFailed,
          message: 'Run context caseId does not match the compiled case.',
        ),
      );
    }

    late final CockpitTestExecutionPlan plan;
    if (preparedPlan != null) {
      if (inputs.isNotEmpty) {
        throw ArgumentError(
          'Runtime inputs cannot accompany an already prepared case plan.',
        );
      }
      plan = preparedPlan;
    } else {
      try {
        plan = CockpitTestVariableBinder().bind(compiled, inputs: inputs);
      } on CockpitTestBindingException catch (error) {
        return _publishPreparationFailure(
          compiled: compiled,
          context: context,
          targetId: targetId,
          reportRoot: reportRoot,
          startedAt: startedAt,
          startedElapsed: startedElapsed,
          error: error.error,
        );
      }
    }
    if (plan.caseId != compiled.testCase.id ||
        plan.sourceSha256 != compiled.sourceSha256) {
      return _publishPreparationFailure(
        compiled: compiled,
        context: context,
        targetId: targetId,
        reportRoot: reportRoot,
        startedAt: startedAt,
        startedElapsed: startedElapsed,
        error: CockpitTestError(
          code: CockpitTestErrorCode.validationFailed,
          message: 'Prepared plan does not match the compiled case.',
        ),
      );
    }

    CockpitCapabilities capabilities;
    CockpitCapabilities? systemCapabilities;
    try {
      capabilities = await _automationAdapter.describeCapabilities();
      if (_systemAutomationAdapter != null) {
        try {
          systemCapabilities = await _systemAutomationAdapter
              .describeCapabilities();
        } on Object {
          systemCapabilities = null;
        }
      }
    } catch (_) {
      return _publishPreparationFailure(
        compiled: compiled,
        context: context,
        targetId: targetId,
        reportRoot: reportRoot,
        startedAt: startedAt,
        startedElapsed: startedElapsed,
        error: CockpitTestError(
          code: CockpitTestErrorCode.driverFailed,
          message: 'Driver capability discovery failed.',
        ),
      );
    }
    final preflightError = await _preflight(
      plan: plan,
      context: context,
      capabilities: capabilities,
      systemCapabilities: systemCapabilities,
      targetEnvironment: targetEnvironment,
    );
    if (preflightError != null) {
      return _publishPreparationFailure(
        compiled: compiled,
        context: context,
        targetId: targetId,
        reportRoot: reportRoot,
        startedAt: startedAt,
        startedElapsed: startedElapsed,
        error: preflightError,
      );
    }

    final recorder = CockpitTestAttemptRecorder(clock: _clock);
    final delegate = CockpitCaseDriverDelegate(
      automationAdapter: _automationAdapter,
      captureAdapter: _captureAdapter,
      recordingAdapter: _recordingAdapter,
      secretResolver: _secretResolver,
      safetyPolicy: _safetyPolicy,
      lowerer: _lowerer,
      recorder: recorder,
      runContext: context,
      plan: plan,
      capabilities: capabilities,
      systemAutomationAdapter: _systemAutomationAdapter,
      systemCaptureAdapter: _systemCaptureAdapter,
      systemRecordingAdapter: _systemRecordingAdapter,
      systemCapabilities: systemCapabilities,
      targetEnvironment: targetEnvironment,
    );
    final kernel = CockpitCaseExecutionKernel(
      clock: _clock,
      delegate: delegate,
      recorder: recorder,
    );
    final kernelResult = await kernel.run(
      plan: plan,
      control: executionControl,
    );
    return _publish(
      compiled: compiled,
      context: context,
      targetId: targetId,
      reportRoot: reportRoot,
      startedAt: startedAt,
      startedElapsed: startedElapsed,
      steps: recorder.steps,
      artifacts: recorder.artifacts,
      primaryError: kernelResult.primaryError,
      cleanupErrors: kernelResult.cleanupErrors,
      outcome: kernelResult.outcome,
      actualPlane: plan.target.plane,
      platform: capabilities.platform,
    );
  }

  Future<CockpitTestError?> _preflight({
    required CockpitTestExecutionPlan plan,
    required CockpitTestRunContext context,
    required CockpitCapabilities capabilities,
    required CockpitCapabilities? systemCapabilities,
    required CockpitTestTargetEnvironment targetEnvironment,
  }) async {
    final target = plan.target;
    final acceptsTargetKind = switch (_lowerer.backend) {
      CockpitTestActionBackend.flutter =>
        target.targetKind == CockpitTargetKind.flutterApp.name &&
            target.plane == CockpitTestPlane.semantic,
      CockpitTestActionBackend.system =>
        target.targetKind != CockpitTargetKind.flutterApp.name ||
            target.plane != CockpitTestPlane.semantic,
    };
    if (!acceptsTargetKind) {
      return CockpitTestError(
        code: CockpitTestErrorCode.targetMismatch,
        message: _lowerer.backend == CockpitTestActionBackend.flutter
            ? 'Flutter case runner requires targetKind flutterApp on the '
                  'semantic plane.'
            : 'System case runner cannot execute a Flutter semantic-plane '
                  'case.',
      );
    }
    if (target.platform != 'flutter' &&
        target.platform != capabilities.platform) {
      return CockpitTestError(
        code: CockpitTestErrorCode.targetMismatch,
        message:
            'Required platform ${target.platform} does not match the '
            'driver platform ${capabilities.platform}.',
      );
    }
    final available = <String>{
      ...capabilities.supportedCommands.map((command) => command.name),
      ...?systemCapabilities?.supportedCommands.map((command) => command.name),
    };
    final missing = target.requiredCapabilities.difference(available);
    if (missing.isNotEmpty) {
      return CockpitTestError(
        code: CockpitTestErrorCode.targetMismatch,
        message:
            'Target is missing required capabilities: ${missing.join(', ')}.',
      );
    }
    for (final node in plan.allNodes) {
      final operation = node.operation;
      if (operation is CockpitTestActionPlanOperation) {
        final plane = cockpitRequestedPlane(node, target.plane);
        final driver = _preflightDriver(
          plane,
          capabilities,
          systemCapabilities,
        );
        if (driver == null) {
          return CockpitTestError(
            code: CockpitTestErrorCode.unsupportedAction,
            message: 'No driver is available for ${plane.name} plane.',
            stepId: node.stepId,
          );
        }
        final lowered = driver.lowerer.lower(
          action: operation.action,
          commandId: node.executionId,
          timeoutMs: node.timeoutMs,
          requestedPlane: plane,
          capabilities: driver.capabilities,
        );
        if (!lowered.isSuccess) {
          return _withStep(lowered.error!, node.stepId);
        }
        final safetyError = await cockpitAuthorizeTestAction(
          policy: _safetyPolicy,
          request: CockpitTestSafetyRequest(
            phase: CockpitTestSafetyPhase.preflight,
            runContext: context,
            target: target,
            targetEnvironment: targetEnvironment,
            stepId: node.stepId,
            executionId: node.executionId,
            action: operation.action,
            declaration: node.safety,
            isMutation: cockpitTestActionIsMutation(operation.action.kind),
          ),
        );
        if (safetyError != null) {
          return safetyError;
        }
      } else if (operation is CockpitTestIfPlanOperation) {
        final plane = cockpitRequestedPlane(node, target.plane);
        final error = _preflightCondition(
          operation.condition,
          node,
          plane,
          capabilities,
          systemCapabilities,
        );
        if (error != null) return error;
      } else if (operation is CockpitTestLoopPlanOperation) {
        final plane = cockpitRequestedPlane(node, target.plane);
        final error = _preflightCondition(
          operation.condition,
          node,
          plane,
          capabilities,
          systemCapabilities,
        );
        if (error != null) return error;
      } else if ((operation is CockpitTestStartRecordingPlanOperation ||
              operation is CockpitTestStopRecordingPlanOperation) &&
          !_hasRecordingAdapter(cockpitRequestedPlane(node, target.plane))) {
        return CockpitTestError(
          code: CockpitTestErrorCode.unsupportedAction,
          message:
              'Recording is requested but no recording adapter is configured.',
          stepId: node.stepId,
        );
      }
    }
    return null;
  }

  CockpitTestError? _preflightCondition(
    CockpitTestCondition condition,
    CockpitTestExecutionNode node,
    CockpitTestPlane plane,
    CockpitCapabilities capabilities,
    CockpitCapabilities? systemCapabilities,
  ) {
    final driver = _preflightDriver(plane, capabilities, systemCapabilities);
    if (driver == null) {
      return CockpitTestError(
        code: CockpitTestErrorCode.unsupportedAction,
        message: 'No driver is available for ${plane.name} plane.',
        stepId: node.stepId,
      );
    }
    final lowered = driver.lowerer.lowerCondition(
      condition: condition,
      commandId: '${node.executionId}/condition',
      timeoutMs: node.timeoutMs,
      requestedPlane: plane,
      capabilities: driver.capabilities,
    );
    return lowered.error == null
        ? null
        : _withStep(lowered.error!, node.stepId);
  }

  _CockpitPreflightDriver? _preflightDriver(
    CockpitTestPlane plane,
    CockpitCapabilities capabilities,
    CockpitCapabilities? systemCapabilities,
  ) {
    if (_lowerer.backend == CockpitTestActionBackend.system) {
      return plane == CockpitTestPlane.semantic
          ? null
          : _CockpitPreflightDriver(_lowerer, capabilities);
    }
    if (plane == CockpitTestPlane.semantic) {
      return _CockpitPreflightDriver(_lowerer, capabilities);
    }
    return systemCapabilities == null
        ? null
        : _CockpitPreflightDriver(
            const CockpitTestActionLowerer.system(),
            systemCapabilities,
          );
  }

  bool _hasRecordingAdapter(CockpitTestPlane plane) {
    if (_lowerer.backend == CockpitTestActionBackend.system ||
        plane == CockpitTestPlane.semantic) {
      return _recordingAdapter != null;
    }
    return _systemRecordingAdapter != null;
  }

  Future<CockpitTestAttemptResult> _publishPreparationFailure({
    required CockpitCompiledTestCase compiled,
    required CockpitTestRunContext context,
    required String targetId,
    required String reportRoot,
    required DateTime startedAt,
    required Duration startedElapsed,
    required CockpitTestError error,
  }) => _publish(
    compiled: compiled,
    context: context,
    targetId: targetId,
    reportRoot: reportRoot,
    startedAt: startedAt,
    startedElapsed: startedElapsed,
    steps: const <CockpitTestStepResult>[],
    artifacts: const <CockpitTestRecordedArtifact>[],
    primaryError: error,
    cleanupErrors: const <CockpitTestError>[],
    outcome:
        error.code == CockpitTestErrorCode.safetyDenied ||
            error.code == CockpitTestErrorCode.targetMismatch ||
            error.code == CockpitTestErrorCode.unsupportedAction ||
            error.code == CockpitTestErrorCode.unsupportedLocator
        ? CockpitTestOutcome.blocked
        : CockpitTestOutcome.failed,
    actualPlane: null,
    platform: compiled.testCase.target.platform,
  );

  Future<CockpitTestAttemptResult> _publish({
    required CockpitCompiledTestCase compiled,
    required CockpitTestRunContext context,
    required String targetId,
    required String reportRoot,
    required DateTime startedAt,
    required Duration startedElapsed,
    required List<CockpitTestStepResult> steps,
    required List<CockpitTestRecordedArtifact> artifacts,
    required CockpitTestError? primaryError,
    required List<CockpitTestError> cleanupErrors,
    required CockpitTestOutcome outcome,
    required CockpitTestPlane? actualPlane,
    required String platform,
  }) async {
    final finishedAt = _clock.utcNow;
    final durationMs = (_clock.elapsed - startedElapsed).inMilliseconds;
    var result = CockpitTestAttemptResult(
      context: context,
      lifecycle: CockpitTestLifecycle.completed,
      outcome: outcome,
      stability:
          outcome == CockpitTestOutcome.passed &&
              steps.any((step) => (step.occurrence.retryAttempt ?? 1) > 1)
          ? CockpitTestStability.flaky
          : CockpitTestStability.stable,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: durationMs < 0 ? 0 : durationMs,
      targetId: targetId,
      platform: platform,
      requestedPlane: compiled.testCase.target.plane,
      actualPlane: actualPlane,
      steps: steps,
      primaryError: primaryError,
      cleanupErrors: cleanupErrors,
    );
    try {
      final summary = await _bundleWriter.write(
        rootPath: reportRoot,
        context: context,
        sourceSha256: compiled.sourceSha256,
        result: result,
        artifacts: artifacts,
        createdAt: finishedAt,
        prePublicationValidator: _bundlePrePublicationValidator,
      );
      result = CockpitTestAttemptResult(
        context: context,
        lifecycle: result.lifecycle,
        outcome: result.outcome,
        stability: result.stability,
        startedAt: result.startedAt,
        finishedAt: result.finishedAt,
        durationMs: result.durationMs,
        targetId: result.targetId,
        platform: result.platform,
        requestedPlane: result.requestedPlane,
        actualPlane: result.actualPlane,
        steps: result.steps,
        primaryError: result.primaryError,
        cleanupErrors: result.cleanupErrors,
        bundlePath: summary.path,
      );
      return result;
    } on CockpitTestBundlePublicationException catch (error) {
      final bundleError = error.error;
      final effectivePrimary = result.primaryError ?? bundleError;
      return CockpitTestAttemptResult(
        context: context,
        lifecycle: CockpitTestLifecycle.completed,
        outcome: result.primaryError == null
            ? CockpitTestOutcome.failed
            : result.outcome,
        stability: result.stability,
        startedAt: result.startedAt,
        finishedAt: _clock.utcNow,
        durationMs: (_clock.elapsed - startedElapsed).inMilliseconds.clamp(
          0,
          1 << 31,
        ),
        targetId: targetId,
        platform: platform,
        requestedPlane: result.requestedPlane,
        actualPlane: result.actualPlane,
        steps: result.steps,
        primaryError: effectivePrimary,
        cleanupErrors: <CockpitTestError>[
          ...result.cleanupErrors,
          if (result.primaryError != null) bundleError,
        ],
      );
    }
  }
}

final class _CockpitPreflightDriver {
  const _CockpitPreflightDriver(this.lowerer, this.capabilities);

  final CockpitTestActionLowerer lowerer;
  final CockpitCapabilities capabilities;
}

CockpitTestError _withStep(CockpitTestError error, String stepId) =>
    CockpitTestError(
      code: error.code,
      message: error.message,
      path: error.path,
      stepId: stepId,
      location: error.location,
      details: error.details,
    );
