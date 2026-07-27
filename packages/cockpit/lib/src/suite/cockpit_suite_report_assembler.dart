import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_suite_execution_plan.dart';
import 'cockpit_suite_scheduler.dart';

final class CockpitSuiteReportAssembler {
  const CockpitSuiteReportAssembler();

  CockpitTestSuiteReport assemble({
    required String projectId,
    required String workspaceId,
    required String runId,
    required CockpitSuiteExecutionPlan plan,
    required CockpitSuiteScheduleResult schedule,
    required DateTime startedAt,
    required DateTime finishedAt,
    CockpitFailure? failure,
    Map<String, Object?> environment = const <String, Object?>{},
    Iterable<CockpitArtifactReference> artifacts =
        const <CockpitArtifactReference>[],
  }) {
    final cases = <CockpitTestCaseReport>[];
    final caseNodes = plan.caseNodes.toList(growable: false);
    final failedSuiteCleanup = <CockpitSuiteNodeExecution>[
      for (final node in plan.nodes)
        if (node.kind == CockpitSuitePlanNodeKind.fixtureTeardown &&
            node.caseNodeId == null)
          schedule.executionFor(node.nodeId),
    ].where(_isFailedCleanup).toList(growable: false);
    for (var caseIndex = 0; caseIndex < caseNodes.length; caseIndex += 1) {
      final node = caseNodes[caseIndex];
      final execution = schedule.executionFor(node.nodeId);
      final targetId = execution.attempts.isEmpty
          ? node.targetId ?? 'unassigned'
          : execution.attempts.last.targetId;
      cases.add(
        CockpitTestCaseReport(
          entryId: node.entryId,
          caseId: node.compiledCase.testCase.id,
          definition: node.compiledCase.testCase,
          sourceSha256: node.compiledCase.sourceSha256,
          outcome: execution.outcome,
          stability: execution.stability,
          targetId: targetId,
          matrix: node.matrix,
          attempts: execution.attempts,
        ),
      );
    }
    final outcome = _outcome(<CockpitRunOutcome>[
      ...cases.map((item) => item.outcome),
      ...failedSuiteCleanup.map((cleanup) => cleanup.outcome),
    ]);
    final stability =
        cases.any((item) => item.stability == CockpitRunStability.flaky)
        ? CockpitRunStability.flaky
        : CockpitRunStability.stable;
    return CockpitTestSuiteReport(
      projectId: projectId,
      workspaceId: workspaceId,
      runId: runId,
      suiteId: plan.suite.id,
      definition: plan.suite,
      sourceSha256: plan.sourceSha256,
      outcome: outcome,
      stability: stability,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: finishedAt.difference(startedAt).inMilliseconds,
      execution: plan.suite.execution,
      reportPolicy: plan.suite.report,
      failure: failure ?? _suiteCleanupFailure(failedSuiteCleanup),
      environment: environment,
      matrixAxes: plan.suite.matrix.axes,
      cases: cases,
      artifacts: artifacts,
    );
  }
}

CockpitFailure? _suiteCleanupFailure(
  List<CockpitSuiteNodeExecution> executions,
) {
  if (executions.isEmpty) return null;
  final failures = executions.map(_cleanupFailure).toList(growable: false);
  return CockpitFailure(
    primary: failures.first.primary,
    warnings: <CockpitApiWarning>[
      ...failures.first.warnings,
      for (final failure in failures.skip(1)) ...<CockpitApiWarning>[
        CockpitApiWarning(
          stage: CockpitWarningStage.cleanup,
          error: failure.primary,
        ),
        ...failure.warnings,
      ],
    ],
  );
}

CockpitFailure _cleanupFailure(CockpitSuiteNodeExecution execution) =>
    execution.attempts.lastOrNull?.failure ??
    CockpitFailure(
      primary: CockpitApiError(
        code: 'suiteFixtureTeardownFailed',
        category: CockpitErrorCategory.environment,
        message: 'Suite fixture teardown did not complete successfully.',
        retryable: execution.outcome == CockpitRunOutcome.interrupted,
        responsibleLayer: CockpitResponsibleLayer.worker,
      ),
    );

bool _isFailedCleanup(CockpitSuiteNodeExecution execution) =>
    execution.outcome != CockpitRunOutcome.passed &&
    execution.outcome != CockpitRunOutcome.skipped;

CockpitRunOutcome _outcome(Iterable<CockpitRunOutcome> outcomes) {
  final values = outcomes.toSet();
  for (final candidate in const <CockpitRunOutcome>[
    CockpitRunOutcome.internalError,
    CockpitRunOutcome.interrupted,
    CockpitRunOutcome.cancelled,
    CockpitRunOutcome.failed,
    CockpitRunOutcome.blocked,
  ]) {
    if (values.contains(candidate)) return candidate;
  }
  return CockpitRunOutcome.passed;
}
