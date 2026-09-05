import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../artifacts/cockpit_test_attempt_recorder.dart';
import '../infrastructure/cockpit_monotonic_clock.dart';
import '../remote/cockpit_remote_command_timeout_budget.dart';
import '../test/cockpit_test_execution_plan.dart';
import 'cockpit_case_execution_control.dart';
import 'cockpit_case_operation_lease.dart';

const Duration _commandReturnSettlementGrace = Duration(milliseconds: 250);
const Duration _semanticConditionTimeout = Duration(milliseconds: 500);
const Duration _externalConditionTimeout =
    cockpitRemoteCommandMinimumTransportTimeout;

final class CockpitTestKernelOperationResult {
  const CockpitTestKernelOperationResult.success({
    this.actualPlane,
    this.driverId,
    this.locatorResolution,
    this.degradationReason,
    this.evidence = const <String>[],
  }) : error = null;

  const CockpitTestKernelOperationResult.failure(
    this.error, {
    this.actualPlane,
    this.driverId,
    this.locatorResolution,
    this.degradationReason,
    this.evidence = const <String>[],
  });

  final CockpitTestError? error;
  final CockpitTestPlane? actualPlane;
  final String? driverId;
  final CockpitLocatorResolution? locatorResolution;
  final String? degradationReason;
  final List<String> evidence;

  bool get isSuccess => error == null;
}

final class CockpitTestKernelConditionResult {
  const CockpitTestKernelConditionResult({
    required this.evaluation,
    this.actualPlane,
    this.driverId,
    this.locatorResolution,
    this.degradationReason,
    this.evidence = const <String>[],
  });

  final CockpitTestConditionEvaluation evaluation;
  final CockpitTestPlane? actualPlane;
  final String? driverId;
  final CockpitLocatorResolution? locatorResolution;
  final String? degradationReason;
  final List<String> evidence;
}

abstract interface class CockpitCaseExecutionDelegate {
  Future<CockpitTestKernelOperationResult> executeAction({
    required CockpitTestExecutionNode node,
    required CockpitTestAction action,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  });

  Future<CockpitTestKernelConditionResult> evaluateCondition({
    required CockpitTestExecutionNode node,
    required CockpitTestCondition condition,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  });

  Future<CockpitTestKernelOperationResult> startRecording({
    required CockpitTestExecutionNode node,
    required CockpitTestStartRecordingPlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  });

  Future<CockpitTestKernelOperationResult> stopRecording({
    required CockpitTestExecutionNode node,
    required CockpitTestStopRecordingPlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  });

  Future<CockpitTestKernelOperationResult> startPerformance({
    required CockpitTestExecutionNode node,
    required CockpitTestStartPerformancePlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  });

  Future<CockpitTestKernelOperationResult> stopPerformance({
    required CockpitTestExecutionNode node,
    required CockpitTestStopPerformancePlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  });

  CockpitTestExecutionNode? get residualCleanupNode;

  Future<CockpitTestKernelOperationResult> cleanupResidual({
    required Duration timeout,
    required CockpitCaseOperationLease lease,
  });
}

final class CockpitCaseKernelResult {
  CockpitCaseKernelResult({
    this.primaryError,
    Iterable<CockpitTestError> cleanupErrors = const <CockpitTestError>[],
  }) : cleanupErrors = List<CockpitTestError>.unmodifiable(cleanupErrors);

  final CockpitTestError? primaryError;
  final List<CockpitTestError> cleanupErrors;

  CockpitTestOutcome get outcome {
    final error = primaryError;
    if (error == null) return CockpitTestOutcome.passed;
    if (error.code == CockpitTestErrorCode.cancelled ||
        error.code == CockpitTestErrorCode.hardShutdown) {
      return CockpitTestOutcome.cancelled;
    }
    if (error.code == CockpitTestErrorCode.safetyDenied ||
        error.code == CockpitTestErrorCode.targetMismatch ||
        error.code == CockpitTestErrorCode.unsupportedAction ||
        error.code == CockpitTestErrorCode.unsupportedLocator) {
      return CockpitTestOutcome.blocked;
    }
    return CockpitTestOutcome.failed;
  }
}

final class CockpitCaseExecutionKernel {
  const CockpitCaseExecutionKernel({
    required CockpitMonotonicClock clock,
    required CockpitCaseExecutionDelegate delegate,
    required CockpitTestAttemptRecorder recorder,
  }) : _clock = clock,
       _delegate = delegate,
       _recorder = recorder;

  final CockpitMonotonicClock _clock;
  final CockpitCaseExecutionDelegate _delegate;
  final CockpitTestAttemptRecorder _recorder;

  Future<CockpitCaseKernelResult> run({
    required CockpitTestExecutionPlan plan,
    required CockpitCaseExecutionControl control,
  }) async {
    CockpitTestError? primaryError;
    try {
      primaryError = await _runSequence(
        plan.setup,
        plan: plan,
        control: control,
        cleanupControl: null,
        parentDeadline: null,
        parentGuardDeadline: null,
        occurrence: const _KernelOccurrence(),
        failFast: plan.defaults.failFast,
      );
      if (primaryError == null || !plan.defaults.failFast) {
        final mainError = await _runSequence(
          plan.steps,
          plan: plan,
          control: control,
          cleanupControl: null,
          parentDeadline: null,
          parentGuardDeadline: null,
          occurrence: const _KernelOccurrence(),
          failFast: plan.defaults.failFast,
        );
        primaryError ??= mainError;
      }
    } on CockpitCaseCancelled {
      primaryError = _KernelErrors.cancelled();
    } on CockpitCaseHardShutdown {
      primaryError = _KernelErrors.hardShutdown();
    }

    final cleanupErrors = <CockpitTestError>[];
    final cleanupDeadline = CockpitMonotonicDeadline.after(
      _clock,
      Duration(milliseconds: plan.defaults.cleanupTimeoutMs),
    );
    final cleanupControl = CockpitCaseCleanupControl(control);
    try {
      final cleanupError = await _runSequence(
        plan.finallySteps,
        plan: plan,
        control: control,
        cleanupControl: cleanupControl,
        parentDeadline: cleanupDeadline,
        parentGuardDeadline: cleanupDeadline,
        occurrence: const _KernelOccurrence(),
        failFast: false,
        collectedErrors: cleanupErrors,
      );
      if (!cleanupErrors.contains(cleanupError)) {
        cleanupErrors.addAll(<CockpitTestError>[?cleanupError]);
      }
      final residualError = await _runResidualCleanup(
        plan: plan,
        control: control,
        cleanupControl: cleanupControl,
        deadline: cleanupDeadline,
      );
      if (residualError != null) {
        cleanupErrors.add(residualError);
      }
    } on CockpitDeadlineExceeded {
      cleanupErrors.add(_KernelErrors.timeout());
    } on CockpitCaseHardShutdown {
      cleanupErrors.add(_KernelErrors.hardShutdown());
    }
    if (primaryError == null && cleanupErrors.isNotEmpty) {
      primaryError = cleanupErrors.first;
    }
    return CockpitCaseKernelResult(
      primaryError: primaryError,
      cleanupErrors: cleanupErrors,
    );
  }

  Future<CockpitTestError?> _runSequence(
    List<CockpitTestExecutionNode> nodes, {
    required CockpitTestExecutionPlan plan,
    required CockpitCaseExecutionControl control,
    required CockpitCaseCleanupControl? cleanupControl,
    required CockpitMonotonicDeadline? parentDeadline,
    required CockpitMonotonicDeadline? parentGuardDeadline,
    required _KernelOccurrence occurrence,
    required bool failFast,
    List<CockpitTestError>? collectedErrors,
  }) async {
    CockpitTestError? firstError;
    for (final node in nodes) {
      if (cleanupControl == null && control.isCancellationRequested) {
        if (control.isHardShutdownRequested) {
          throw const CockpitCaseHardShutdown();
        }
        throw const CockpitCaseCancelled();
      }
      if (cleanupControl?.isHardShutdownRequested == true) {
        throw const CockpitCaseHardShutdown();
      }
      final outcome = await _runNode(
        node,
        plan: plan,
        control: control,
        cleanupControl: cleanupControl,
        parentDeadline: parentDeadline,
        parentGuardDeadline: parentGuardDeadline,
        occurrence: occurrence,
      );
      final error = outcome.error;
      if (error != null) {
        firstError ??= error;
        collectedErrors?.add(error);
        if (failFast) {
          break;
        }
      }
    }
    return firstError;
  }

  Future<CockpitTestError?> _runResidualCleanup({
    required CockpitTestExecutionPlan plan,
    required CockpitCaseExecutionControl control,
    required CockpitCaseCleanupControl cleanupControl,
    required CockpitMonotonicDeadline deadline,
  }) async {
    final node = _delegate.residualCleanupNode;
    if (node == null) {
      return null;
    }
    final handle = _recorder.startStep(node);
    try {
      final result = await _controlled(
        (lease) => _delegate.cleanupResidual(
          timeout: deadline.remaining,
          lease: lease,
        ),
        control: control,
        cleanupControl: cleanupControl,
        deadline: deadline,
      );
      final error = result.error;
      if (error == null) {
        _recorder.finishStep(
          handle,
          status: CockpitTestStepStatus.passed,
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      } else {
        _finishFailure(
          handle,
          error,
          _requestedPlane(node, plan),
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      }
      return error;
    } on CockpitDeadlineExceeded {
      final error = _KernelErrors.timeout(node.stepId);
      _finishFailure(handle, error, _requestedPlane(node, plan));
      return error;
    } on CockpitCaseHardShutdown {
      final error = _KernelErrors.hardShutdown(node.stepId);
      _recorder.finishStep(
        handle,
        status: CockpitTestStepStatus.cancelled,
        error: error,
      );
      rethrow;
    } catch (_) {
      final error = CockpitTestError(
        code: CockpitTestErrorCode.internalFailure,
        message: 'Internal residual cleanup failure.',
        stepId: node.stepId,
      );
      _finishFailure(handle, error, _requestedPlane(node, plan));
      return error;
    }
  }

  Future<_KernelNodeOutcome> _runNode(
    CockpitTestExecutionNode node, {
    required CockpitTestExecutionPlan plan,
    required CockpitCaseExecutionControl control,
    required CockpitCaseCleanupControl? cleanupControl,
    required CockpitMonotonicDeadline? parentDeadline,
    required CockpitMonotonicDeadline? parentGuardDeadline,
    required _KernelOccurrence occurrence,
  }) async {
    final handle = _recorder.startStep(
      node,
      retryAttempt: occurrence.retryAttempt,
      loopIteration: occurrence.loopIteration,
    );
    final availableMs = parentDeadline?.remaining.inMilliseconds;
    final budgetMs = availableMs == null
        ? node.timeoutMs
        : node.timeoutMs < availableMs
        ? node.timeoutMs
        : availableMs;
    if (budgetMs <= 0) {
      final error = _KernelErrors.timeout(node.stepId);
      _finishFailure(handle, error, _requestedPlane(node, plan));
      return _KernelNodeOutcome(error: error);
    }
    final deadline = CockpitMonotonicDeadline.after(
      _clock,
      Duration(milliseconds: budgetMs),
    );
    final requestedGuard =
        Duration(milliseconds: budgetMs) + _nodeCommandReturnGrace(node);
    final guardBudget = parentGuardDeadline == null
        ? requestedGuard
        : parentGuardDeadline.clamp(requestedGuard);
    final guardDeadline = CockpitMonotonicDeadline.after(_clock, guardBudget);
    try {
      final outcome = await _executeNode(
        node,
        plan: plan,
        control: control,
        cleanupControl: cleanupControl,
        deadline: deadline,
        guardDeadline: guardDeadline,
        occurrence: occurrence,
      );
      final error = outcome.error;
      if (error == null) {
        _recorder.finishStep(
          handle,
          status: CockpitTestStepStatus.passed,
          requestedPlane: _requestedPlane(node, plan),
          actualPlane: outcome.actualPlane,
          driverId: outcome.driverId,
          locatorResolution: outcome.locatorResolution,
          degradationReason: outcome.degradationReason,
          evidence: outcome.evidence,
        );
      } else {
        _finishFailure(
          handle,
          error,
          _requestedPlane(node, plan),
          actualPlane: outcome.actualPlane,
          driverId: outcome.driverId,
          locatorResolution: outcome.locatorResolution,
          degradationReason: outcome.degradationReason,
          evidence: outcome.evidence,
        );
      }
      return outcome;
    } on CockpitDeadlineExceeded {
      final error = _KernelErrors.timeout(node.stepId);
      _finishFailure(handle, error, _requestedPlane(node, plan));
      return _KernelNodeOutcome(error: error);
    } on CockpitCaseCancelled {
      final error = _KernelErrors.cancelled(node.stepId);
      _recorder.finishStep(
        handle,
        status: CockpitTestStepStatus.cancelled,
        requestedPlane: _requestedPlane(node, plan),
        error: error,
      );
      rethrow;
    } on CockpitCaseHardShutdown {
      final error = _KernelErrors.hardShutdown(node.stepId);
      _recorder.finishStep(
        handle,
        status: CockpitTestStepStatus.cancelled,
        requestedPlane: _requestedPlane(node, plan),
        error: error,
      );
      rethrow;
    } catch (_) {
      final error = CockpitTestError(
        code: CockpitTestErrorCode.internalFailure,
        message: 'Internal case execution failure.',
        stepId: node.stepId,
      );
      _finishFailure(handle, error, _requestedPlane(node, plan));
      return _KernelNodeOutcome(error: error);
    }
  }

  Future<_KernelNodeOutcome> _executeNode(
    CockpitTestExecutionNode node, {
    required CockpitTestExecutionPlan plan,
    required CockpitCaseExecutionControl control,
    required CockpitCaseCleanupControl? cleanupControl,
    required CockpitMonotonicDeadline deadline,
    required CockpitMonotonicDeadline guardDeadline,
    required _KernelOccurrence occurrence,
  }) async {
    final operation = node.operation;
    switch (operation) {
      case CockpitTestActionPlanOperation(:final action):
        final result = await _controlled(
          (lease) => _delegate.executeAction(
            node: node,
            action: action,
            timeout: deadline.remaining,
            cleanup: cleanupControl != null,
            lease: lease,
          ),
          control: control,
          cleanupControl: cleanupControl,
          deadline: guardDeadline,
        );
        return _KernelNodeOutcome(
          error: result.error,
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      case CockpitTestStartRecordingPlanOperation():
        final result = await _controlled(
          (lease) => _delegate.startRecording(
            node: node,
            operation: operation,
            timeout: deadline.remaining,
            cleanup: cleanupControl != null,
            lease: lease,
          ),
          control: control,
          cleanupControl: cleanupControl,
          deadline: deadline,
        );
        return _KernelNodeOutcome(
          error: result.error,
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      case CockpitTestStopRecordingPlanOperation():
        if (operation.settleMs > 0) {
          await _controlled(
            (_) => _clock.delay(Duration(milliseconds: operation.settleMs)),
            control: control,
            cleanupControl: cleanupControl,
            deadline: deadline,
          );
        }
        final result = await _controlled(
          (lease) => _delegate.stopRecording(
            node: node,
            operation: operation,
            timeout: deadline.remaining,
            cleanup: cleanupControl != null,
            lease: lease,
          ),
          control: control,
          cleanupControl: cleanupControl,
          deadline: deadline,
        );
        return _KernelNodeOutcome(
          error: result.error,
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      case CockpitTestStartPerformancePlanOperation():
        final result = await _controlled(
          (lease) => _delegate.startPerformance(
            node: node,
            operation: operation,
            timeout: deadline.remaining,
            cleanup: cleanupControl != null,
            lease: lease,
          ),
          control: control,
          cleanupControl: cleanupControl,
          deadline: deadline,
        );
        return _KernelNodeOutcome(
          error: result.error,
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      case CockpitTestStopPerformancePlanOperation():
        if (operation.settleMs > 0) {
          await _controlled(
            (_) => _clock.delay(Duration(milliseconds: operation.settleMs)),
            control: control,
            cleanupControl: cleanupControl,
            deadline: deadline,
          );
        }
        final result = await _controlled(
          (lease) => _delegate.stopPerformance(
            node: node,
            operation: operation,
            timeout: deadline.remaining,
            cleanup: cleanupControl != null,
            lease: lease,
          ),
          control: control,
          cleanupControl: cleanupControl,
          deadline: deadline,
        );
        return _KernelNodeOutcome(
          error: result.error,
          actualPlane: result.actualPlane,
          driverId: result.driverId,
          locatorResolution: result.locatorResolution,
          degradationReason: result.degradationReason,
          evidence: result.evidence,
        );
      case CockpitTestIfPlanOperation():
        final conditionResult = await _evaluateCondition(
          node,
          operation.condition,
          plane: cockpitRequestedPlane(node, plan.target.plane),
          control: control,
          cleanupControl: cleanupControl,
          deadline: deadline,
        );
        final conditionError = _conditionError(conditionResult, node.stepId);
        if (conditionError != null) {
          return _KernelNodeOutcome(error: conditionError);
        }
        final branch =
            conditionResult.evaluation.state ==
                CockpitTestConditionState.matched
            ? operation.thenSteps
            : operation.elseSteps;
        final error = await _runSequence(
          branch,
          plan: plan,
          control: control,
          cleanupControl: cleanupControl,
          parentDeadline: deadline,
          parentGuardDeadline: guardDeadline,
          occurrence: occurrence,
          failFast: plan.defaults.failFast,
        );
        return _KernelNodeOutcome(
          error: error,
          actualPlane: conditionResult.actualPlane,
          driverId: conditionResult.driverId,
          locatorResolution: conditionResult.locatorResolution,
          degradationReason: conditionResult.degradationReason,
          evidence: conditionResult.evidence,
        );
      case CockpitTestRetryPlanOperation():
        CockpitTestError? lastError;
        for (var attempt = 1; attempt <= operation.maxAttempts; attempt += 1) {
          lastError = await _runSequence(
            operation.steps,
            plan: plan,
            control: control,
            cleanupControl: cleanupControl,
            parentDeadline: deadline,
            parentGuardDeadline: guardDeadline,
            occurrence: occurrence.copyWith(retryAttempt: attempt),
            failFast: plan.defaults.failFast,
          );
          if (lastError == null) {
            return const _KernelNodeOutcome();
          }
          if (attempt < operation.maxAttempts && operation.delayMs > 0) {
            await _controlled(
              (_) => _clock.delay(Duration(milliseconds: operation.delayMs)),
              control: control,
              cleanupControl: cleanupControl,
              deadline: deadline,
            );
          }
        }
        return _KernelNodeOutcome(error: lastError);
      case CockpitTestLoopPlanOperation():
        for (
          var iteration = 1;
          iteration <= operation.maxIterations;
          iteration += 1
        ) {
          final conditionResult = await _evaluateCondition(
            node,
            operation.condition,
            plane: cockpitRequestedPlane(node, plan.target.plane),
            control: control,
            cleanupControl: cleanupControl,
            deadline: deadline,
          );
          final conditionError = _conditionError(conditionResult, node.stepId);
          if (conditionError != null) {
            return _KernelNodeOutcome(error: conditionError);
          }
          if (conditionResult.evaluation.state ==
              CockpitTestConditionState.notMatched) {
            return _KernelNodeOutcome(
              actualPlane: conditionResult.actualPlane,
              driverId: conditionResult.driverId,
              locatorResolution: conditionResult.locatorResolution,
              degradationReason: conditionResult.degradationReason,
              evidence: conditionResult.evidence,
            );
          }
          final error = await _runSequence(
            operation.steps,
            plan: plan,
            control: control,
            cleanupControl: cleanupControl,
            parentDeadline: deadline,
            parentGuardDeadline: guardDeadline,
            occurrence: occurrence.copyWith(loopIteration: iteration),
            failFast: plan.defaults.failFast,
          );
          if (error != null) {
            return _KernelNodeOutcome(error: error);
          }
          // A successful action can commit its visible state just after the
          // command returns (desktop and remote Flutter bindings are the
          // common case). Re-check after the final iteration so a bounded
          // loop does not report a false failure merely because the last
          // frame landed between the next condition probe and loop exit.
          if (iteration == operation.maxIterations) {
            final finalConditionResult = await _evaluateCondition(
              node,
              operation.condition,
              plane: cockpitRequestedPlane(node, plan.target.plane),
              control: control,
              cleanupControl: cleanupControl,
              deadline: deadline,
            );
            final finalConditionError = _conditionError(
              finalConditionResult,
              node.stepId,
            );
            if (finalConditionError != null) {
              return _KernelNodeOutcome(error: finalConditionError);
            }
            if (finalConditionResult.evaluation.state ==
                CockpitTestConditionState.notMatched) {
              return _KernelNodeOutcome(
                actualPlane: finalConditionResult.actualPlane,
                driverId: finalConditionResult.driverId,
                locatorResolution: finalConditionResult.locatorResolution,
                degradationReason: finalConditionResult.degradationReason,
                evidence: finalConditionResult.evidence,
              );
            }
          }
        }
        return _KernelNodeOutcome(
          error: CockpitTestError(
            code: CockpitTestErrorCode.conditionError,
            message: 'Loop remained matched after its maximum iterations.',
            stepId: node.stepId,
          ),
        );
    }
  }

  Future<CockpitTestKernelConditionResult> _evaluateCondition(
    CockpitTestExecutionNode node,
    CockpitTestCondition condition, {
    required CockpitTestPlane plane,
    required CockpitCaseExecutionControl control,
    required CockpitCaseCleanupControl? cleanupControl,
    required CockpitMonotonicDeadline deadline,
  }) async {
    if (deadline.isExpired) {
      throw const CockpitDeadlineExceeded();
    }
    final commandTimeout = _controlConditionTimeout(
      plane: plane,
      remaining: deadline.remaining,
    );
    final probeTimeout = _controlConditionProbeTimeout(
      remaining: deadline.remaining,
      commandTimeout: commandTimeout,
    );
    final probeDeadline = CockpitMonotonicDeadline.after(_clock, probeTimeout);
    try {
      return await _controlled(
        (lease) => _delegate.evaluateCondition(
          node: node,
          condition: condition,
          timeout: commandTimeout,
          cleanup: cleanupControl != null,
          lease: lease,
        ),
        control: control,
        cleanupControl: cleanupControl,
        deadline: probeDeadline,
      );
    } on CockpitDeadlineExceeded {
      if (deadline.isExpired) {
        rethrow;
      }
      return CockpitTestKernelConditionResult(
        evaluation: CockpitTestConditionEvaluation.error(
          CockpitTestError(
            code: CockpitTestErrorCode.conditionError,
            message: 'Condition probe did not return within its guard budget.',
            stepId: node.stepId,
            details: <String, Object?>{
              'plane': plane.name,
              'commandTimeoutMs': commandTimeout.inMilliseconds,
              'probeTimeoutMs': probeTimeout.inMilliseconds,
            },
          ),
        ),
      );
    }
  }

  Duration _controlConditionTimeout({
    required CockpitTestPlane plane,
    required Duration remaining,
  }) {
    final maximum = switch (plane) {
      CockpitTestPlane.semantic => _semanticConditionTimeout,
      CockpitTestPlane.native ||
      CockpitTestPlane.visual ||
      CockpitTestPlane.coordinate => _externalConditionTimeout,
    };
    return remaining < maximum ? remaining : maximum;
  }

  Duration _controlConditionProbeTimeout({
    required Duration remaining,
    required Duration commandTimeout,
  }) {
    final requested =
        commandTimeout + cockpitRemoteCommandPlainTransportHeadroom;
    return requested < remaining ? requested : remaining;
  }

  Duration _nodeCommandReturnGrace(CockpitTestExecutionNode node) {
    final operation = node.operation;
    return switch (operation) {
      CockpitTestActionPlanOperation(:final action) =>
        _actionCarriesEvidence(node, action)
            ? cockpitRemoteCommandEvidenceTransportHeadroom +
                  _commandReturnSettlementGrace
            : cockpitRemoteCommandPlainTransportHeadroom +
                  _commandReturnSettlementGrace,
      CockpitTestIfPlanOperation(:final thenSteps, :final elseSteps) =>
        _maximumNodeCommandReturnGrace(<CockpitTestExecutionNode>[
          ...thenSteps,
          ...elseSteps,
        ]),
      CockpitTestRetryPlanOperation(:final steps) ||
      CockpitTestLoopPlanOperation(
        :final steps,
      ) => _maximumNodeCommandReturnGrace(steps),
      CockpitTestStartRecordingPlanOperation() ||
      CockpitTestStopRecordingPlanOperation() ||
      CockpitTestStartPerformancePlanOperation() ||
      CockpitTestStopPerformancePlanOperation() => Duration.zero,
    };
  }

  Duration _maximumNodeCommandReturnGrace(
    Iterable<CockpitTestExecutionNode> nodes,
  ) {
    var maximum = Duration.zero;
    for (final node in nodes) {
      final candidate = _nodeCommandReturnGrace(node);
      if (candidate > maximum) {
        maximum = candidate;
      }
    }
    return maximum;
  }

  bool _actionCarriesEvidence(
    CockpitTestExecutionNode node,
    CockpitTestAction action,
  ) {
    if (node.evidence.screenshot != CockpitTestEvidenceMode.none ||
        node.evidence.snapshot != CockpitTestEvidenceMode.none) {
      return true;
    }
    return action.kind == CockpitTestActionKind.captureScreenshot ||
        action.kind == CockpitTestActionKind.assertScreenshot;
  }

  Future<T> _controlled<T>(
    Future<T> Function(CockpitCaseOperationLease lease) start, {
    required CockpitCaseExecutionControl control,
    required CockpitCaseCleanupControl? cleanupControl,
    required CockpitMonotonicDeadline deadline,
  }) async {
    if (cleanupControl == null && control.isCancellationRequested) {
      if (control.isHardShutdownRequested) {
        throw const CockpitCaseHardShutdown();
      }
      throw const CockpitCaseCancelled();
    }
    if (cleanupControl?.isHardShutdownRequested == true) {
      throw const CockpitCaseHardShutdown();
    }
    if (deadline.isExpired) {
      throw const CockpitDeadlineExceeded();
    }
    final lease = CockpitCaseOperationLease();
    try {
      final timed = cockpitRaceDeadline(
        operation: start(lease),
        clock: _clock,
        deadline: deadline,
      );
      return await (cleanupControl == null
          ? cockpitRacePrimaryControl(
              operation: timed,
              control: control,
              clock: _clock,
            )
          : cockpitRaceCleanupControl(
              operation: timed,
              control: cleanupControl,
            ));
    } catch (error, stackTrace) {
      lease.revoke(
        requestAbort:
            error is CockpitDeadlineExceeded ||
            error is CockpitCaseCancelled ||
            error is CockpitCaseHardShutdown,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      lease.revoke(requestAbort: false);
    }
  }

  void _finishFailure(
    CockpitTestStepRecordingHandle handle,
    CockpitTestError error,
    CockpitTestPlane? requestedPlane, {
    CockpitTestPlane? actualPlane,
    String? driverId,
    CockpitLocatorResolution? locatorResolution,
    String? degradationReason,
    Iterable<String> evidence = const <String>[],
  }) {
    final blocked =
        error.code == CockpitTestErrorCode.safetyDenied ||
        error.code == CockpitTestErrorCode.targetMismatch ||
        error.code == CockpitTestErrorCode.unsupportedAction ||
        error.code == CockpitTestErrorCode.unsupportedLocator;
    _recorder.finishStep(
      handle,
      status: blocked
          ? CockpitTestStepStatus.blocked
          : CockpitTestStepStatus.failed,
      requestedPlane: requestedPlane,
      actualPlane: actualPlane,
      driverId: driverId,
      locatorResolution: locatorResolution,
      degradationReason: degradationReason,
      error: error,
      evidence: evidence,
    );
  }

  CockpitTestPlane? _requestedPlane(
    CockpitTestExecutionNode node,
    CockpitTestExecutionPlan plan,
  ) => switch (node.operation) {
    CockpitTestActionPlanOperation() ||
    CockpitTestIfPlanOperation() ||
    CockpitTestLoopPlanOperation() => cockpitRequestedPlane(
      node,
      plan.target.plane,
    ),
    _ => null,
  };
}

CockpitTestError? _conditionError(
  CockpitTestKernelConditionResult result,
  String stepId,
) {
  if (result.evaluation.state != CockpitTestConditionState.error) {
    return null;
  }
  final error = result.evaluation.error;
  return error ??
      CockpitTestError(
        code: CockpitTestErrorCode.conditionError,
        message: 'Condition evaluation failed.',
        stepId: stepId,
      );
}

final class _KernelNodeOutcome {
  const _KernelNodeOutcome({
    this.error,
    this.actualPlane,
    this.driverId,
    this.locatorResolution,
    this.degradationReason,
    this.evidence = const <String>[],
  });

  final CockpitTestError? error;
  final CockpitTestPlane? actualPlane;
  final String? driverId;
  final CockpitLocatorResolution? locatorResolution;
  final String? degradationReason;
  final List<String> evidence;
}

final class _KernelOccurrence {
  const _KernelOccurrence({this.retryAttempt, this.loopIteration});

  final int? retryAttempt;
  final int? loopIteration;

  _KernelOccurrence copyWith({int? retryAttempt, int? loopIteration}) =>
      _KernelOccurrence(
        retryAttempt: retryAttempt ?? this.retryAttempt,
        loopIteration: loopIteration ?? this.loopIteration,
      );
}

abstract final class _KernelErrors {
  static CockpitTestError timeout([String? stepId]) => CockpitTestError(
    code: CockpitTestErrorCode.timeout,
    message: 'Step exceeded its monotonic deadline.',
    stepId: stepId,
  );

  static CockpitTestError cancelled([String? stepId]) => CockpitTestError(
    code: CockpitTestErrorCode.cancelled,
    message: 'Case execution was cancelled.',
    stepId: stepId,
  );

  static CockpitTestError hardShutdown([String? stepId]) => CockpitTestError(
    code: CockpitTestErrorCode.hardShutdown,
    message: 'Case execution was stopped by hard shutdown.',
    stepId: stepId,
  );
}
