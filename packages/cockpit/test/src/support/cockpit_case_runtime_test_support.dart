import 'dart:async';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/runner/cockpit_case_execution_kernel.dart';
import 'package:cockpit/src/runner/cockpit_case_operation_lease.dart';
import 'package:cockpit/src/test/cockpit_test_execution_plan.dart';
import 'package:cockpit/src/test/cockpit_test_secret_resolver.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

final class ManualCockpitClock implements CockpitMonotonicClock {
  Duration _elapsed = Duration.zero;
  final List<_ScheduledDelay> _delays = <_ScheduledDelay>[];

  @override
  Duration get elapsed => _elapsed;

  @override
  DateTime get utcNow => DateTime.utc(2026, 7, 20).add(_elapsed);

  @override
  Future<void> delay(Duration duration) {
    final completer = Completer<void>();
    _delays.add(_ScheduledDelay(_elapsed + duration, completer));
    return completer.future;
  }

  void elapse(Duration duration) {
    _elapsed += duration;
    for (final delay in _delays.toList(growable: false)) {
      if (!delay.completer.isCompleted && delay.due <= _elapsed) {
        delay.completer.complete();
      }
    }
    _delays.removeWhere((delay) => delay.completer.isCompleted);
  }
}

final class DeterministicCaseDelegate implements CockpitCaseExecutionDelegate {
  final List<String> events = <String>[];
  final Map<String, List<CockpitTestKernelOperationResult>> actionResults =
      <String, List<CockpitTestKernelOperationResult>>{};
  final List<CockpitTestKernelConditionResult> conditionResults =
      <CockpitTestKernelConditionResult>[];
  final Map<String, Completer<CockpitTestKernelConditionResult>>
  hangingConditions = <String, Completer<CockpitTestKernelConditionResult>>{};
  final Map<String, Completer<CockpitTestKernelOperationResult>>
  hangingActions = <String, Completer<CockpitTestKernelOperationResult>>{};
  final Map<String, Duration> actionTimeouts = <String, Duration>{};
  final Map<String, Duration> conditionTimeouts = <String, Duration>{};
  CockpitTestError? residualError;

  @override
  CockpitTestExecutionNode get residualCleanupNode => actionNode(
    'residualCleanup',
    'finally',
    executionId: 'finally/residualCleanup',
  );

  @override
  Future<CockpitTestKernelOperationResult> executeAction({
    required CockpitTestExecutionNode node,
    required CockpitTestAction action,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) {
    events.add('action:${node.stepId}:${cleanup ? 'cleanup' : 'primary'}');
    actionTimeouts[node.stepId] = timeout;
    final hanging = hangingActions[node.stepId];
    if (hanging != null) return hanging.future;
    final results = actionResults[node.stepId];
    if (results == null || results.isEmpty) {
      return Future<CockpitTestKernelOperationResult>.value(
        const CockpitTestKernelOperationResult.success(),
      );
    }
    return Future<CockpitTestKernelOperationResult>.value(results.removeAt(0));
  }

  @override
  Future<CockpitTestKernelConditionResult> evaluateCondition({
    required CockpitTestExecutionNode node,
    required CockpitTestCondition condition,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) {
    events.add('condition:${node.stepId}:${cleanup ? 'cleanup' : 'primary'}');
    conditionTimeouts[node.stepId] = timeout;
    final hanging = hangingConditions[node.stepId];
    if (hanging != null) return hanging.future;
    return Future<CockpitTestKernelConditionResult>.value(
      conditionResults.removeAt(0),
    );
  }

  @override
  Future<CockpitTestKernelOperationResult> startRecording({
    required CockpitTestExecutionNode node,
    required CockpitTestStartRecordingPlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) async {
    events.add('recording:start:${node.stepId}');
    return const CockpitTestKernelOperationResult.success();
  }

  @override
  Future<CockpitTestKernelOperationResult> stopRecording({
    required CockpitTestExecutionNode node,
    required CockpitTestStopRecordingPlanOperation operation,
    required Duration timeout,
    required bool cleanup,
    required CockpitCaseOperationLease lease,
  }) async {
    events.add('recording:stop:${node.stepId}');
    return const CockpitTestKernelOperationResult.success();
  }

  @override
  Future<CockpitTestKernelOperationResult> cleanupResidual({
    required Duration timeout,
    required CockpitCaseOperationLease lease,
  }) async {
    events.add('cleanup:residual');
    final error = residualError;
    return error == null
        ? const CockpitTestKernelOperationResult.success()
        : CockpitTestKernelOperationResult.failure(error);
  }
}

CockpitTestExecutionPlan testExecutionPlan({
  Iterable<CockpitTestExecutionNode> setup = const <CockpitTestExecutionNode>[],
  required Iterable<CockpitTestExecutionNode> steps,
  Iterable<CockpitTestExecutionNode> finallySteps =
      const <CockpitTestExecutionNode>[],
  bool failFast = true,
  int cleanupTimeoutMs = 1000,
}) => CockpitTestExecutionPlan(
  caseId: 'runtimeCase',
  sourceSha256: List<String>.filled(64, '0').join(),
  target: CockpitTestTargetRequirements(
    platform: 'android',
    targetKind: 'flutterApp',
    plane: CockpitTestPlane.semantic,
  ),
  defaults: CockpitTestCaseDefaults(
    commandTimeoutMs: 1000,
    cleanupTimeoutMs: cleanupTimeoutMs,
    failFast: failFast,
  ),
  setup: setup,
  steps: steps,
  finallySteps: finallySteps,
  resolvedInputs: const <String, Object?>{},
  secretBindings: CockpitTestSecretBindings(const <String, String>{}),
);

CockpitTestExecutionNode actionNode(
  String id,
  String section, {
  String? executionId,
}) => CockpitTestExecutionNode(
  stepId: id,
  executionId: executionId ?? '$section/$id',
  section: section,
  timeoutMs: 1000,
  evidence: const CockpitTestEvidencePolicy(
    screenshot: CockpitTestEvidenceMode.none,
    snapshot: CockpitTestEvidenceMode.none,
  ),
  safety: CockpitTestSafetyDeclaration(),
  sourcePath: '\$.$section[0]',
  operation: CockpitTestActionPlanOperation(
    CockpitTestAction(kind: CockpitTestActionKind.back),
  ),
);

CockpitTestError testDriverError(String stepId) => CockpitTestError(
  code: CockpitTestErrorCode.driverFailed,
  message: 'Deterministic driver failure.',
  stepId: stepId,
);

final class _ScheduledDelay {
  const _ScheduledDelay(this.due, this.completer);

  final Duration due;
  final Completer<void> completer;
}
