import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_automation_adapter.dart';
import '../adapters/cockpit_active_operation_aborter.dart';
import '../adapters/cockpit_capture_adapter.dart';
import '../adapters/cockpit_recording_adapter.dart';
import '../artifacts/cockpit_test_attempt_recorder.dart';
import '../test/cockpit_test_action_lowerer.dart';
import '../test/cockpit_test_execution_plan.dart';
import '../test/cockpit_test_safety_policy.dart';
import '../test/cockpit_test_secret_resolver.dart';
import 'cockpit_case_execution_kernel.dart';
import 'cockpit_case_operation_lease.dart';

final class CockpitCaseDriverDelegate implements CockpitCaseExecutionDelegate {
  CockpitCaseDriverDelegate({
    required CockpitAutomationAdapter automationAdapter,
    CockpitCaptureAdapter? captureAdapter,
    CockpitRecordingAdapter? recordingAdapter,
    required CockpitTestSecretResolver secretResolver,
    required CockpitTestSafetyPolicy safetyPolicy,
    required CockpitTestActionLowerer lowerer,
    required CockpitTestAttemptRecorder recorder,
    required CockpitTestRunContext runContext,
    required CockpitTestExecutionPlan plan,
    required CockpitCapabilities capabilities,
    CockpitAutomationAdapter? systemAutomationAdapter,
    CockpitCaptureAdapter? systemCaptureAdapter,
    CockpitRecordingAdapter? systemRecordingAdapter,
    CockpitCapabilities? systemCapabilities,
    required CockpitTestTargetEnvironment targetEnvironment,
  }) : _automationAdapter = automationAdapter,
       _captureAdapter = captureAdapter,
       _recordingAdapter = recordingAdapter,
       _secretResolver = secretResolver,
       _safetyPolicy = safetyPolicy,
       _lowerer = lowerer,
       _recorder = recorder,
       _runContext = runContext,
       _plan = plan,
       _capabilities = capabilities,
       _systemAutomationAdapter = systemAutomationAdapter,
       _systemCaptureAdapter = systemCaptureAdapter,
       _systemRecordingAdapter = systemRecordingAdapter,
       _systemCapabilities = systemCapabilities,
       _targetEnvironment = targetEnvironment;

  final CockpitAutomationAdapter _automationAdapter;
  final CockpitCaptureAdapter? _captureAdapter;
  final CockpitRecordingAdapter? _recordingAdapter;
  final CockpitTestSecretResolver _secretResolver;
  final CockpitTestSafetyPolicy _safetyPolicy;
  final CockpitTestActionLowerer _lowerer;
  final CockpitTestAttemptRecorder _recorder;
  final CockpitTestRunContext _runContext;
  final CockpitTestExecutionPlan _plan;
  final CockpitCapabilities _capabilities;
  final CockpitAutomationAdapter? _systemAutomationAdapter;
  final CockpitCaptureAdapter? _systemCaptureAdapter;
  final CockpitRecordingAdapter? _systemRecordingAdapter;
  final CockpitCapabilities? _systemCapabilities;
  final CockpitTestTargetEnvironment _targetEnvironment;
  CockpitRecordingSession? _recordingSession;
  CockpitRecordingAdapter? _activeRecordingAdapter;
  CockpitTestPlane? _activeRecordingPlane;
  String? _activeRecordingDriverId;
  String? _activeRecordingDegradationReason;

  @override
  Future<CockpitTestKernelOperationResult> executeAction({
    required CockpitTestExecutionNode node,
    required CockpitTestAction action,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) async {
    final operationLease = lease;
    final safetyError = await cockpitAuthorizeTestAction(
      policy: _safetyPolicy,
      request: CockpitTestSafetyRequest(
        phase: CockpitTestSafetyPhase.dispatch,
        runContext: _runContext,
        target: _plan.target,
        targetEnvironment: _targetEnvironment,
        stepId: node.stepId,
        executionId: node.executionId,
        action: action,
        declaration: node.safety,
        isMutation: cockpitTestActionIsMutation(action.kind),
      ),
    );
    if (!operationLease.isActive) {
      return _abortedOperation(node);
    }
    if (safetyError != null) {
      return CockpitTestKernelOperationResult.failure(safetyError);
    }
    CockpitTestAction resolved;
    try {
      resolved = await cockpitResolveTestActionSecrets(
        action: action,
        secretBindings: _plan.secretBindings,
        resolver: _secretResolver,
      );
    } on CockpitTestSecretResolutionException catch (error) {
      return CockpitTestKernelOperationResult.failure(
        _withStep(error.error, node.stepId),
      );
    }
    if (!operationLease.isActive) {
      return _abortedOperation(node);
    }
    final requestedPlane = cockpitRequestedPlane(node, _plan.target.plane);
    final driver = _driverFor(requestedPlane);
    if (driver == null) {
      return CockpitTestKernelOperationResult.failure(
        CockpitTestError(
          code: CockpitTestErrorCode.unsupportedAction,
          message: 'No driver is available for ${requestedPlane.name} plane.',
          stepId: node.stepId,
        ),
      );
    }
    CockpitTestLoweringResult lowering;
    try {
      lowering = driver.lowerer.lower(
        action: resolved,
        commandId: node.executionId,
        timeoutMs: timeout.inMilliseconds,
        requestedPlane: requestedPlane,
        capabilities: driver.capabilities,
      );
    } on FormatException {
      return CockpitTestKernelOperationResult.failure(
        CockpitTestError(
          code: CockpitTestErrorCode.unsupportedAction,
          message: 'Action cannot be represented by the Flutter backend.',
          stepId: node.stepId,
        ),
      );
    }
    if (!lowering.isSuccess) {
      return CockpitTestKernelOperationResult.failure(
        _withStep(lowering.error!, node.stepId),
      );
    }
    final lowered = lowering.value!;
    CockpitCommandExecution execution;
    try {
      if (!operationLease.isActive) {
        return _abortedOperation(node);
      }
      _registerAbort(operationLease, _adapterFor(lowered.command, driver));
      execution = await _execute(lowered.command, driver);
    } catch (_) {
      operationLease.clearAbort();
      if (!operationLease.isActive) {
        return _abortedOperation(node);
      }
      return CockpitTestKernelOperationResult.failure(
        CockpitTestError(
          code: CockpitTestErrorCode.driverFailed,
          message: 'Driver failed while executing ${action.kind.name}.',
          stepId: node.stepId,
        ),
        actualPlane: lowered.actualPlane,
      );
    }
    operationLease.clearAbort();
    var evidence = const <String>[];
    if (!operationLease.tryCommit(() {
      evidence = _recorder.addExecutionArtifacts(
        execution: execution,
        stepExecutionId: node.executionId,
      );
    })) {
      return _abortedOperation(node);
    }
    final commandError = execution.result.success
        ? null
        : _commandError(execution.result, node.stepId);
    final supplemental = await _collectEvidence(
      node: node,
      commandSucceeded: commandError == null,
      timeout: timeout,
      lease: operationLease,
      captureAdapter: driver.captureAdapter,
    );
    if (!operationLease.isActive) {
      return _abortedOperation(node);
    }
    final allEvidence = <String>[...evidence, ...supplemental.artifactIds];
    final effectiveError = commandError ?? supplemental.error;
    return effectiveError == null
        ? CockpitTestKernelOperationResult.success(
            actualPlane: lowered.actualPlane,
            locatorResolution: execution.result.locatorResolution,
            degradationReason: execution.result.degradationReason,
            evidence: allEvidence,
          )
        : CockpitTestKernelOperationResult.failure(
            effectiveError,
            actualPlane: lowered.actualPlane,
            locatorResolution: execution.result.locatorResolution,
            degradationReason: execution.result.degradationReason,
            evidence: allEvidence,
          );
  }

  @override
  Future<CockpitTestKernelConditionResult> evaluateCondition({
    required CockpitTestExecutionNode node,
    required CockpitTestCondition condition,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) async {
    final requestedPlane = cockpitRequestedPlane(node, _plan.target.plane);
    final driver = _driverFor(requestedPlane);
    if (driver == null) {
      return CockpitTestKernelConditionResult(
        evaluation: CockpitTestConditionEvaluation.error(
          CockpitTestError(
            code: CockpitTestErrorCode.unsupportedAction,
            message: 'No driver is available for ${requestedPlane.name} plane.',
            stepId: node.stepId,
          ),
        ),
      );
    }
    final lowering = driver.lowerer.lowerCondition(
      condition: condition,
      commandId: '${node.executionId}/condition',
      timeoutMs: timeout.inMilliseconds,
      requestedPlane: requestedPlane,
      capabilities: driver.capabilities,
    );
    if (!lowering.isSuccess) {
      return CockpitTestKernelConditionResult(
        evaluation: CockpitTestConditionEvaluation.error(
          _withStep(lowering.error!, node.stepId),
        ),
      );
    }
    final lowered = lowering.value!;
    try {
      if (!lease.isActive) {
        return _abortedCondition(node);
      }
      _registerAbort(lease, driver.automationAdapter);
      final execution = await driver.automationAdapter.execute(lowered.command);
      lease.clearAbort();
      var evidence = const <String>[];
      if (!lease.tryCommit(() {
        evidence = _recorder.addExecutionArtifacts(
          execution: execution,
          stepExecutionId: node.executionId,
        );
      })) {
        return _abortedCondition(node);
      }
      if (execution.result.success) {
        return CockpitTestKernelConditionResult(
          evaluation: const CockpitTestConditionEvaluation.matched(),
          actualPlane: lowered.actualPlane,
          locatorResolution: execution.result.locatorResolution,
          degradationReason: execution.result.degradationReason,
          evidence: evidence,
        );
      }
      final commandError = execution.result.error;
      if (commandError != null &&
          (commandError.code == CockpitCommandError.targetNotFoundCode ||
              commandError.code == CockpitCommandError.assertionFailedCode ||
              commandError.code == CockpitCommandError.timeoutCode)) {
        return CockpitTestKernelConditionResult(
          evaluation: const CockpitTestConditionEvaluation.notMatched(),
          actualPlane: lowered.actualPlane,
          locatorResolution: execution.result.locatorResolution,
          degradationReason: execution.result.degradationReason,
          evidence: evidence,
        );
      }
      return CockpitTestKernelConditionResult(
        evaluation: CockpitTestConditionEvaluation.error(
          _commandError(execution.result, node.stepId),
        ),
        actualPlane: lowered.actualPlane,
        locatorResolution: execution.result.locatorResolution,
        degradationReason: execution.result.degradationReason,
        evidence: evidence,
      );
    } catch (_) {
      lease.clearAbort();
      if (!lease.isActive) {
        return _abortedCondition(node);
      }
      return CockpitTestKernelConditionResult(
        evaluation: CockpitTestConditionEvaluation.error(
          CockpitTestError(
            code: CockpitTestErrorCode.conditionError,
            message: 'Driver failed while evaluating a condition.',
            stepId: node.stepId,
          ),
        ),
        actualPlane: lowered.actualPlane,
      );
    }
  }

  @override
  Future<CockpitTestKernelOperationResult> startRecording({
    required CockpitTestExecutionNode node,
    required CockpitTestStartRecordingPlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) async {
    final requestedPlane = cockpitRequestedPlane(node, _plan.target.plane);
    final candidates = _recordingCandidates(
      node: node,
      operation: operation,
      requestedPlane: requestedPlane,
    );
    if (candidates.isEmpty) {
      return CockpitTestKernelOperationResult.failure(
        _recordingError(node, 'Recording adapter is unavailable.'),
      );
    }
    if (_recordingSession != null) {
      return CockpitTestKernelOperationResult.failure(
        _recordingError(node, 'A recording session is already active.'),
      );
    }
    if (!lease.isActive) {
      return _abortedOperation(node);
    }
    final request = CockpitRecordingRequest(
      purpose: CockpitRecordingPurpose.fromJson(operation.purpose),
      name: operation.name,
      mode: CockpitRecordingMode.fromJson(operation.mode),
      layer: operation.layer == null
          ? null
          : CockpitRecordingLayer.fromJson(operation.layer),
      allowFallback: operation.allowFallback,
      attachToStep: operation.attachToStep,
    );
    final failures = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      if (!lease.isActive) {
        return _abortedOperation(node);
      }
      try {
        _registerAbort(lease, candidate.adapter);
        final session = await candidate.adapter.startRecording(request);
        lease.clearAbort();
        final degradationReason = failures.isEmpty
            ? null
            : 'Preferred recording adapter failed; using '
                  '${candidate.driverId} fallback.';
        if (!lease.tryCommit(() {
          _recordingSession = session;
          _activeRecordingAdapter = candidate.adapter;
          _activeRecordingPlane = candidate.plane;
          _activeRecordingDriverId = candidate.driverId;
          _activeRecordingDegradationReason = degradationReason;
        })) {
          await _stopUnownedRecording(candidate.adapter);
          return _abortedOperation(node);
        }
        return CockpitTestKernelOperationResult.success(
          actualPlane: candidate.plane,
          driverId: candidate.driverId,
          degradationReason: degradationReason,
        );
      } on Object catch (error) {
        lease.clearAbort();
        failures.add(<String, Object?>{
          'driverId': candidate.driverId,
          ..._recordingExceptionDetails(error),
        });
      }
    }
    if (!lease.isActive) {
      return _abortedOperation(node);
    }
    return CockpitTestKernelOperationResult.failure(
      _recordingError(
        node,
        'Recording failed to start.',
        details: <String, Object?>{'attempts': failures},
      ),
    );
  }

  @override
  Future<CockpitTestKernelOperationResult> stopRecording({
    required CockpitTestExecutionNode node,
    required CockpitTestStopRecordingPlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) async {
    if (_recordingSession == null) {
      return CockpitTestKernelOperationResult.failure(
        _recordingError(node, 'No recording session is active.'),
      );
    }
    return _stopRecording(node, lease);
  }

  @override
  CockpitTestExecutionNode? get residualCleanupNode => _recordingSession == null
      ? null
      : CockpitTestExecutionNode(
          stepId: 'residualRecording',
          executionId: 'finally/residualRecording',
          section: 'finally',
          timeoutMs: _plan.defaults.cleanupTimeoutMs,
          evidence: _plan.defaults.evidence,
          safety: CockpitTestSafetyDeclaration(),
          sourcePath: r'$.finally',
          operation: const CockpitTestStopRecordingPlanOperation(settleMs: 0),
        );

  @override
  Future<CockpitTestKernelOperationResult> cleanupResidual({
    required Duration timeout,
    required CockpitCaseOperationLease lease,
  }) async {
    final node = residualCleanupNode;
    if (node == null) {
      return const CockpitTestKernelOperationResult.success();
    }
    return _stopRecording(node, lease);
  }

  Future<CockpitTestKernelOperationResult> _stopRecording(
    CockpitTestExecutionNode node,
    CockpitCaseOperationLease lease,
  ) async {
    final adapter = _activeRecordingAdapter;
    if (adapter == null) {
      return CockpitTestKernelOperationResult.failure(
        _recordingError(node, 'Recording adapter is unavailable.'),
      );
    }
    final session = _recordingSession;
    final actualPlane = _activeRecordingPlane;
    final driverId = _activeRecordingDriverId;
    final degradationReason = _activeRecordingDegradationReason;
    if (session == null || !lease.isActive) {
      return _abortedOperation(node);
    }
    try {
      _registerAbort(lease, adapter);
      final result = await adapter.stopRecording();
      lease.clearAbort();
      if (!lease.isActive) {
        return _abortedOperation(node);
      }
      final artifact = result.artifact;
      final evidence = <String>[];
      if (artifact != null) {
        String? id;
        if (!lease.tryCommit(() {
          id = _recorder.addArtifact(
            kind: artifact.role,
            relativePath: artifact.relativePath,
            stepExecutionId: node.executionId,
            bytes: result.bytes,
            sourcePath: result.sourceFilePath,
          );
        })) {
          return _abortedOperation(node);
        }
        final artifactId = id;
        if (artifactId != null) evidence.add(artifactId);
      }
      if (result.state != CockpitRecordingState.completed) {
        return CockpitTestKernelOperationResult.failure(
          _recordingError(
            node,
            'Recording did not complete successfully.',
            details: <String, Object?>{
              'state': result.state.name,
              if (result.failureReason != null)
                'failureReason': result.failureReason,
            },
          ),
          actualPlane: actualPlane,
          driverId: driverId,
          degradationReason: degradationReason,
          evidence: evidence,
        );
      }
      var released = false;
      if (!lease.tryCommit(() {
        if (identical(_recordingSession, session)) {
          _recordingSession = null;
          _activeRecordingAdapter = null;
          _activeRecordingPlane = null;
          _activeRecordingDriverId = null;
          _activeRecordingDegradationReason = null;
          released = true;
        }
      })) {
        return _abortedOperation(node);
      }
      if (!released) {
        return CockpitTestKernelOperationResult.failure(
          _recordingError(node, 'Recording session ownership changed.'),
          evidence: evidence,
        );
      }
      return CockpitTestKernelOperationResult.success(
        actualPlane: actualPlane,
        driverId: driverId,
        degradationReason: degradationReason,
        evidence: evidence,
      );
    } on Object catch (error) {
      lease.clearAbort();
      if (!lease.isActive) {
        return _abortedOperation(node);
      }
      return CockpitTestKernelOperationResult.failure(
        _recordingError(
          node,
          'Recording failed to stop.',
          details: _recordingExceptionDetails(error),
        ),
        actualPlane: actualPlane,
        driverId: driverId,
        degradationReason: degradationReason,
      );
    }
  }

  Future<CockpitCommandExecution> _execute(
    CockpitCommand command,
    _CockpitCaseDriver driver,
  ) {
    if (command.commandType == CockpitCommandType.captureScreenshot) {
      final adapter = driver.captureAdapter;
      if (adapter == null) {
        throw StateError('Screenshot capture adapter is unavailable.');
      }
      return adapter.capture(command);
    }
    return driver.automationAdapter.execute(command);
  }

  Object _adapterFor(CockpitCommand command, _CockpitCaseDriver driver) =>
      command.commandType == CockpitCommandType.captureScreenshot
      ? driver.captureAdapter ?? driver.automationAdapter
      : driver.automationAdapter;

  _CockpitCaseDriver? _driverFor(CockpitTestPlane plane) {
    if (_lowerer.backend == CockpitTestActionBackend.system) {
      return _CockpitCaseDriver(
        automationAdapter: _automationAdapter,
        captureAdapter: _captureAdapter,
        recordingAdapter: _recordingAdapter,
        lowerer: _lowerer,
        capabilities: _capabilities,
      );
    }
    if (plane == CockpitTestPlane.semantic) {
      return _CockpitCaseDriver(
        automationAdapter: _automationAdapter,
        captureAdapter: _captureAdapter,
        recordingAdapter: _recordingAdapter,
        lowerer: _lowerer,
        capabilities: _capabilities,
      );
    }
    final automation = _systemAutomationAdapter;
    final capabilities = _systemCapabilities;
    if (automation == null || capabilities == null) return null;
    return _CockpitCaseDriver(
      automationAdapter: automation,
      captureAdapter: _systemCaptureAdapter,
      recordingAdapter: _systemRecordingAdapter,
      lowerer: const CockpitTestActionLowerer.system(),
      capabilities: capabilities,
    );
  }

  List<_CockpitRecordingCandidate> _recordingCandidates({
    required CockpitTestExecutionNode node,
    required CockpitTestStartRecordingPlanOperation operation,
    required CockpitTestPlane requestedPlane,
  }) {
    if (_lowerer.backend == CockpitTestActionBackend.system) {
      final adapter = _recordingAdapter;
      return adapter == null
          ? const <_CockpitRecordingCandidate>[]
          : <_CockpitRecordingCandidate>[
              _CockpitRecordingCandidate(
                adapter: adapter,
                plane: requestedPlane,
                driverId: 'systemRecording',
              ),
            ];
    }

    final semantic = _recordingAdapter == null
        ? null
        : _CockpitRecordingCandidate(
            adapter: _recordingAdapter,
            plane: CockpitTestPlane.semantic,
            driverId: 'flutterRecording',
          );
    final system = _systemRecordingAdapter == null
        ? null
        : _CockpitRecordingCandidate(
            adapter: _systemRecordingAdapter,
            plane: CockpitTestPlane.native,
            driverId: 'systemRecording',
          );
    final explicitPlane = node.plane;
    final requestedLayer = operation.layer == null
        ? null
        : CockpitRecordingLayer.fromJson(operation.layer);
    final mode = CockpitRecordingMode.fromJson(operation.mode);
    final preferSystem = switch (explicitPlane) {
      CockpitTestPlane.semantic => false,
      CockpitTestPlane.native ||
      CockpitTestPlane.visual ||
      CockpitTestPlane.coordinate => true,
      null => switch (requestedLayer) {
        CockpitRecordingLayer.flutter ||
        CockpitRecordingLayer.appWindow => false,
        CockpitRecordingLayer.system ||
        CockpitRecordingLayer.hostScreen => true,
        null =>
          mode == CockpitRecordingMode.auto ||
              mode == CockpitRecordingMode.full,
      },
    };
    final preferred = preferSystem ? system : semantic;
    final fallback = preferSystem ? semantic : system;
    return <_CockpitRecordingCandidate>[
      ?preferred,
      if (fallback != null &&
          (operation.allowFallback == true ||
              (preferred == null &&
                  explicitPlane == null &&
                  requestedLayer == null)))
        fallback,
    ];
  }

  void _registerAbort(CockpitCaseOperationLease lease, Object adapter) {
    if (adapter case CockpitActiveOperationAborter aborter) {
      lease.registerAbort(aborter.abortActiveOperation);
    } else {
      lease.clearAbort();
    }
  }

  Future<void> _stopUnownedRecording(CockpitRecordingAdapter adapter) async {
    try {
      await adapter.stopRecording();
    } catch (_) {
      // The owning operation has already ended; the runner cannot report this.
    }
  }

  Future<_EvidenceCollection> _collectEvidence({
    required CockpitTestExecutionNode node,
    required bool commandSucceeded,
    required Duration timeout,
    required CockpitCaseOperationLease lease,
    required CockpitCaptureAdapter? captureAdapter,
  }) async {
    final policy = node.evidence;
    final artifactIds = <String>[];
    CockpitTestError? firstError;
    final screenshot = _shouldCollect(policy.screenshot, commandSucceeded);
    final snapshot = _shouldCollect(policy.snapshot, commandSucceeded);
    if (screenshot) {
      if (!lease.isActive) {
        return const _EvidenceCollection(artifactIds: <String>[]);
      }
      final adapter = captureAdapter;
      if (adapter == null) {
        firstError = _evidenceError(node, 'Screenshot adapter is unavailable.');
      } else {
        try {
          if (!lease.isActive) {
            return const _EvidenceCollection(artifactIds: <String>[]);
          }
          _registerAbort(lease, adapter);
          final execution = await adapter.capture(
            CockpitCommand(
              commandId: '${node.executionId}/evidence/screenshot',
              commandType: CockpitCommandType.captureScreenshot,
              capturePolicy: CockpitCapturePolicy.none,
              timeoutMs: timeout.inMilliseconds,
              screenshotRequest: CockpitScreenshotRequest(
                reason: commandSucceeded
                    ? CockpitScreenshotReason.afterAction
                    : CockpitScreenshotReason.assertionFailure,
                name: '${node.stepId}-evidence',
                attachToStep: true,
              ),
            ),
          );
          lease.clearAbort();
          if (!lease.isActive) {
            return const _EvidenceCollection(artifactIds: <String>[]);
          }
          if (!lease.tryCommit(() {
            artifactIds.addAll(
              _recorder.addExecutionArtifacts(
                execution: execution,
                stepExecutionId: node.executionId,
              ),
            );
          })) {
            return const _EvidenceCollection(artifactIds: <String>[]);
          }
          if (!execution.result.success) {
            firstError ??= _evidenceError(node, 'Screenshot capture failed.');
          }
        } catch (_) {
          lease.clearAbort();
          if (!lease.isActive) {
            return const _EvidenceCollection(artifactIds: <String>[]);
          }
          firstError ??= _evidenceError(node, 'Screenshot capture failed.');
        }
      }
    }
    if (snapshot) {
      if (!lease.isActive) {
        return const _EvidenceCollection(artifactIds: <String>[]);
      }
      try {
        _registerAbort(lease, _automationAdapter);
        final execution = await _automationAdapter.execute(
          CockpitCommand(
            commandId: '${node.executionId}/evidence/snapshot',
            commandType: CockpitCommandType.collectSnapshot,
            capturePolicy: CockpitCapturePolicy.none,
            timeoutMs: timeout.inMilliseconds,
          ),
        );
        lease.clearAbort();
        if (!lease.isActive) {
          return const _EvidenceCollection(artifactIds: <String>[]);
        }
        if (!lease.tryCommit(() {
          artifactIds.addAll(
            _recorder.addExecutionArtifacts(
              execution: execution,
              stepExecutionId: node.executionId,
            ),
          );
        })) {
          return const _EvidenceCollection(artifactIds: <String>[]);
        }
        if (!execution.result.success) {
          firstError ??= _evidenceError(node, 'Snapshot collection failed.');
        }
      } catch (_) {
        lease.clearAbort();
        if (!lease.isActive) {
          return const _EvidenceCollection(artifactIds: <String>[]);
        }
        firstError ??= _evidenceError(node, 'Snapshot collection failed.');
      }
    }
    if (policy.failurePolicy ==
        CockpitTestEvidenceFailurePolicy.recordWarning) {
      firstError = null;
    }
    return _EvidenceCollection(artifactIds: artifactIds, error: firstError);
  }
}

CockpitTestKernelOperationResult _abortedOperation(
  CockpitTestExecutionNode node,
) => CockpitTestKernelOperationResult.failure(
  CockpitTestError(
    code: CockpitTestErrorCode.cancelled,
    message: 'Driver operation completed after its execution lease ended.',
    stepId: node.stepId,
  ),
);

CockpitTestKernelConditionResult _abortedCondition(
  CockpitTestExecutionNode node,
) => CockpitTestKernelConditionResult(
  evaluation: CockpitTestConditionEvaluation.error(
    CockpitTestError(
      code: CockpitTestErrorCode.cancelled,
      message: 'Condition completed after its execution lease ended.',
      stepId: node.stepId,
    ),
  ),
);

bool _shouldCollect(CockpitTestEvidenceMode mode, bool succeeded) =>
    switch (mode) {
      CockpitTestEvidenceMode.none => false,
      CockpitTestEvidenceMode.always => true,
      CockpitTestEvidenceMode.onFailure => !succeeded,
    };

CockpitTestError _commandError(CockpitCommandResult result, String stepId) {
  final commandError = result.error;
  final code = switch (commandError?.code) {
    CockpitCommandError.timeoutCode => CockpitTestErrorCode.timeout,
    CockpitCommandError.assertionFailedCode ||
    CockpitCommandError.targetNotFoundCode ||
    CockpitCommandError.ambiguousTargetCode =>
      CockpitTestErrorCode.assertionFailed,
    CockpitCommandError.unsupportedCapabilityCode =>
      CockpitTestErrorCode.unsupportedAction,
    CockpitCommandError.captureFailedCode =>
      CockpitTestErrorCode.evidenceFailed,
    _ => CockpitTestErrorCode.driverFailed,
  };
  return CockpitTestError(
    code: code,
    message:
        commandError?.message ??
        'Driver command ${result.commandType.name} failed.',
    stepId: stepId,
    details: <String, Object?>{
      'commandType': result.commandType.name,
      if (commandError != null) 'driverError': commandError.toJson(),
    },
  );
}

CockpitTestError _recordingError(
  CockpitTestExecutionNode node,
  String message, {
  Map<String, Object?> details = const <String, Object?>{},
}) => CockpitTestError(
  code: CockpitTestErrorCode.recordingFailed,
  message: message,
  stepId: node.stepId,
  details: details,
);

Map<String, Object?> _recordingExceptionDetails(Object error) =>
    <String, Object?>{
      'errorType': error.runtimeType.toString(),
      'reason': '$error',
    };

CockpitTestError _evidenceError(
  CockpitTestExecutionNode node,
  String message,
) => CockpitTestError(
  code: CockpitTestErrorCode.evidenceFailed,
  message: message,
  stepId: node.stepId,
);

CockpitTestError _withStep(CockpitTestError error, String stepId) =>
    CockpitTestError(
      code: error.code,
      message: error.message,
      path: error.path,
      stepId: stepId,
      location: error.location,
      details: error.details,
    );

final class _EvidenceCollection {
  const _EvidenceCollection({required this.artifactIds, this.error});

  final List<String> artifactIds;
  final CockpitTestError? error;
}

final class _CockpitRecordingCandidate {
  const _CockpitRecordingCandidate({
    required this.adapter,
    required this.plane,
    required this.driverId,
  });

  final CockpitRecordingAdapter adapter;
  final CockpitTestPlane plane;
  final String driverId;
}

final class _CockpitCaseDriver {
  const _CockpitCaseDriver({
    required this.automationAdapter,
    required this.captureAdapter,
    required this.recordingAdapter,
    required this.lowerer,
    required this.capabilities,
  });

  final CockpitAutomationAdapter automationAdapter;
  final CockpitCaptureAdapter? captureAdapter;
  final CockpitRecordingAdapter? recordingAdapter;
  final CockpitTestActionLowerer lowerer;
  final CockpitCapabilities capabilities;
}
