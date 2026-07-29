import 'dart:async';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/suite/cockpit_suite_compiler.dart';
import 'package:cockpit/src/suite/cockpit_suite_execution_plan.dart';
import 'package:cockpit/src/suite/cockpit_suite_report_assembler.dart';
import 'package:cockpit/src/suite/cockpit_suite_report_renderer.dart';
import 'package:cockpit/src/suite/cockpit_suite_row_attempt_executor.dart';
import 'package:cockpit/src/suite/cockpit_suite_scheduler.dart';
import 'package:cockpit/src/test/cockpit_test_document_compiler.dart';
import 'package:cockpit/src/worker/cockpit_suite_run_adapter.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'suite runtime preserves isolation, fixture, and dependency order',
    () async {
      final plan = await _compilePlan(_orderedSuite());
      final executor = _RecordingExecutor();

      final result = await _run(
        runId: 'run_ordered',
        plan: plan,
        executor: executor,
      );

      expect(executor.calls, <String>[
        'fixtureSetup:suiteSetup',
        'isolation:firstEntry',
        'fixtureSetup:attemptSetup',
        'testCase:firstCase',
        'fixtureTeardown:attemptTeardown',
        'isolation:secondEntry',
        'fixtureSetup:attemptSetup',
        'testCase:secondCase',
        'fixtureTeardown:attemptTeardown',
        'fixtureTeardown:suiteTeardown',
      ]);
      expect(
        result.executions.every(
          (execution) => execution.outcome == CockpitRunOutcome.passed,
        ),
        isTrue,
      );
    },
  );

  test(
    'non-retryable isolation failure blocks the case and skips unstarted cleanup',
    () async {
      final plan = await _compilePlan(
        _singleCaseSuite(
          isolation: CockpitTestSuiteIsolation.restartApp,
          maxAttempts: 3,
        ),
      );
      final executor = _RecordingExecutor(
        resultFor: (node, attemptId, attemptNumber) =>
            node.kind == CockpitSuitePlanNodeKind.isolation
            ? _attempt(
                attemptId,
                attemptNumber,
                outcome: CockpitRunOutcome.blocked,
                retryable: false,
              )
            : _attempt(attemptId, attemptNumber),
      );

      final result = await _run(
        runId: 'run_blocked',
        plan: plan,
        executor: executor,
      );

      expect(executor.calls, <String>['isolation:onlyEntry']);
      final testCase = result.executions.singleWhere(
        (execution) => execution.kind == CockpitSuitePlanNodeKind.testCase,
      );
      expect(testCase.outcome, CockpitRunOutcome.blocked);
      expect(testCase.attempts, hasLength(1));
      expect(
        plan.nodes.map((node) => node.kind),
        isNot(contains(CockpitSuitePlanNodeKind.isolation)),
      );
    },
  );

  test('every retry repeats the complete case-attempt lifecycle', () async {
    final plan = await _compilePlan(
      _singleCaseSuite(
        isolation: CockpitTestSuiteIsolation.restartApp,
        maxAttempts: 2,
      ),
    );
    final executor = _RecordingExecutor(
      resultFor: (node, attemptId, attemptNumber) =>
          node.kind == CockpitSuitePlanNodeKind.testCase && attemptNumber == 1
          ? _attempt(
              attemptId,
              attemptNumber,
              outcome: CockpitRunOutcome.interrupted,
              retryable: true,
            )
          : _attempt(attemptId, attemptNumber),
    );

    final result = await _run(
      runId: 'run_retry',
      plan: plan,
      executor: executor,
    );

    expect(executor.calls, <String>[
      'isolation:onlyEntry',
      'fixtureSetup:attemptSetup',
      'testCase:onlyCase',
      'fixtureTeardown:attemptTeardown',
      'isolation:onlyEntry',
      'fixtureSetup:attemptSetup',
      'testCase:onlyCase',
      'fixtureTeardown:attemptTeardown',
    ]);
    final execution = result.executions.single;
    expect(execution.attempts, hasLength(2));
    expect(execution.outcome, CockpitRunOutcome.passed);
    expect(execution.stability, CockpitRunStability.flaky);
  });

  test('cancellation still runs teardown whose setup was attempted', () async {
    final plan = await _compilePlan(
      _singleCaseSuite(isolation: CockpitTestSuiteIsolation.sharedSession),
    );
    final cancellation = _Cancellation();
    final executor = _RecordingExecutor(
      onExecute: (node) {
        if (node.kind == CockpitSuitePlanNodeKind.testCase) {
          cancellation.cancel();
        }
      },
      resultFor: (node, attemptId, attemptNumber) =>
          node.kind == CockpitSuitePlanNodeKind.testCase
          ? _attempt(
              attemptId,
              attemptNumber,
              outcome: CockpitRunOutcome.cancelled,
            )
          : _attempt(attemptId, attemptNumber),
    );

    final result = await _run(
      runId: 'run_cancelled',
      plan: plan,
      executor: executor,
      cancellation: cancellation,
    );

    expect(executor.calls, <String>[
      'isolation:onlyEntry',
      'fixtureSetup:attemptSetup',
      'testCase:onlyCase',
      'fixtureTeardown:attemptTeardown',
    ]);
    expect(result.executions.single.outcome, CockpitRunOutcome.cancelled);
  });

  test('successful teardown does not hide an upstream case failure', () async {
    final plan = await _compilePlan(_orderedSuite(failFast: false));
    final executor = _RecordingExecutor(
      resultFor: (node, attemptId, attemptNumber) =>
          node.kind == CockpitSuitePlanNodeKind.testCase &&
              node.entryId == 'firstEntry'
          ? _attempt(
              attemptId,
              attemptNumber,
              outcome: CockpitRunOutcome.failed,
            )
          : _attempt(attemptId, attemptNumber),
    );

    final result = await _run(
      runId: 'run_dependency',
      plan: plan,
      executor: executor,
    );

    expect(executor.calls, isNot(contains('isolation:secondEntry')));
    expect(
      result.executions
          .singleWhere(
            (execution) =>
                execution.kind == CockpitSuitePlanNodeKind.testCase &&
                execution.entryId == 'secondEntry',
          )
          .outcome,
      CockpitRunOutcome.blocked,
    );
  });

  test('excluded case does not activate fail fast', () async {
    final plan = await _compilePlan(_selectionSuite());
    final executor = _RecordingExecutor();

    final result = await _run(
      runId: 'run_selection',
      plan: plan,
      executor: executor,
    );

    expect(executor.calls, <String>['isolation:beta', 'testCase:betaCase']);
    expect(
      result.executions
          .singleWhere((execution) => execution.entryId == 'alpha')
          .outcome,
      CockpitRunOutcome.skipped,
    );
    expect(
      result.executions
          .singleWhere((execution) => execution.entryId == 'beta')
          .outcome,
      CockpitRunOutcome.passed,
    );
  });

  test(
    'case-attempt teardown failure is included in case and suite reports',
    () async {
      final plan = await _compilePlan(
        _singleCaseSuite(isolation: CockpitTestSuiteIsolation.sharedSession),
      );
      final executor = _RecordingExecutor(
        resultFor: (node, attemptId, attemptNumber) =>
            node.kind == CockpitSuitePlanNodeKind.fixtureTeardown
            ? _attempt(
                attemptId,
                attemptNumber,
                outcome: CockpitRunOutcome.failed,
              )
            : _attempt(attemptId, attemptNumber),
      );
      final startedAt = DateTime.utc(2026, 7, 23, 10);
      final schedule = await _run(
        runId: 'run_cleanup',
        plan: plan,
        executor: executor,
      );

      final report = const CockpitSuiteReportAssembler().assemble(
        projectId: 'projectA',
        workspaceId: 'workspaceA',
        runId: 'run_cleanup',
        plan: plan,
        schedule: schedule,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 1)),
      );

      expect(report.outcome, CockpitRunOutcome.failed);
      expect(report.cases.single.outcome, CockpitRunOutcome.failed);
      expect(report.cases.single.attempts, hasLength(1));
      expect(
        report.cases.single.attempts.single.failure?.primary.code,
        'suiteIsolationUnsupported',
      );
    },
  );

  test('suite teardown failure remains separate from business cases', () async {
    final plan = await _compilePlan(_orderedSuite(failFast: false));
    final executor = _RecordingExecutor(
      resultFor: (node, attemptId, attemptNumber) =>
          node.kind == CockpitSuitePlanNodeKind.fixtureTeardown &&
              node.caseNodeId == null
          ? _attempt(
              attemptId,
              attemptNumber,
              outcome: CockpitRunOutcome.failed,
              code: 'suiteFixtureTeardownFailed',
              message: 'Suite fixture teardown failed.',
            )
          : _attempt(attemptId, attemptNumber),
    );
    final startedAt = DateTime.utc(2026, 7, 23, 10);
    final schedule = await _run(
      runId: 'run_suite_cleanup',
      plan: plan,
      executor: executor,
    );

    final report = const CockpitSuiteReportAssembler().assemble(
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      runId: 'run_suite_cleanup',
      plan: plan,
      schedule: schedule,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(seconds: 1)),
    );

    expect(report.outcome, CockpitRunOutcome.failed);
    expect(report.failure?.primary.code, 'suiteFixtureTeardownFailed');
    expect(report.counts.total, 2);
    expect(report.counts.passed, 2);
    expect(report.counts.failed, 0);
    expect(
      report.cases,
      everyElement(
        isA<CockpitTestCaseReport>()
            .having(
              (testCase) => testCase.outcome,
              'outcome',
              CockpitRunOutcome.passed,
            )
            .having((testCase) => testCase.attempts, 'attempts', hasLength(1)),
      ),
    );
    expect(
      CockpitTestSuiteReport.fromJson(report.toJson()).failure?.primary.code,
      'suiteFixtureTeardownFailed',
    );

    const renderer = CockpitSuiteReportRenderer();
    final bundle = CockpitTestReportBundle(
      generatedAt: report.finishedAt.toUtc(),
      report: report,
      executions: const <CockpitTestReportExecution>[],
    );
    expect(renderer.json(report), contains('"failure"'));
    expect(renderer.junit(report), contains('[suite cleanup]'));
    expect(
      renderer.summary(bundle),
      contains('Suite fixture teardown failed.'),
    );
    final html = renderer.html(bundle);
    expect(html, contains('Suite fixture teardown failed.'));
    expect(html, contains('id="cockpit-report-data"'));
    expect(html, contains('data-lens="summary"'));
    expect(html, contains('data-lens="coverage"'));
    expect(html, contains('data-lens="executions"'));
    expect(html, contains('data-lens="evidence"'));
    expect(html, contains('data-lens="diagnostics"'));
    expect(html, contains('data-lens="environment"'));
    expect(html, contains('data-filter-input'));
    expect(html, contains('Outcome distribution'));
    expect(html, contains('Release gate'));
    expect(html, contains("compact.matches?'horizontal':'vertical'"));
    expect(
      html,
      contains(
        'h1,h2,h3,p,dd,td,code,a,strong,time,.tag,.case-meta span{overflow-wrap:anywhere}',
      ),
    );
    expect(
      html,
      contains(
        '.title-row>*,.meta>*,.section-head>*,.filter-bar>*,.case-row-head>*,.execution>summary>*,.step>*{min-width:0}',
      ),
    );
    expect(html, contains('.lens-tab{width:auto;min-height:44px'));
    expect(
      html,
      contains('input[type="search"],select,.quiet-button{min-height:44px}'),
    );
    expect(html, contains('Effective configuration'));
    expect(html, isNot(contains('border-left:4px')));
    expect(html, isNot(contains('class="eyebrow"')));
    expect(html, isNot(contains('>Product<')));
    expect(html, isNot(contains('>Quality<')));
    expect(html, isNot(contains('>Engineering<')));
    expect(html, isNot(contains('src="http')));
    expect(html, isNot(contains('href="http')));

    final missingFailure = <String, Object?>{...report.toJson()}
      ..remove('failure');
    expect(
      () => CockpitTestSuiteReport.fromJson(missingFailure),
      throwsA(isA<FormatException>()),
    );
  });

  test('suite row primary session is stable across its main target', () async {
    final plan = await _compilePlan(
      _singleCaseSuite(
        isolation: CockpitTestSuiteIsolation.sharedSession,
        secondaryFixtureTargetId: 'secondaryTarget',
      ),
    );
    final affinity = CockpitSuiteRowSessionAffinity(plan);
    final isolation = plan.attemptNodes.singleWhere(
      (node) => node.kind == CockpitSuitePlanNodeKind.isolation,
    );
    final testCase = plan.caseNodes.single;
    final defaultTargetTeardown = plan.attemptNodes.singleWhere(
      (node) =>
          node.kind == CockpitSuitePlanNodeKind.fixtureTeardown &&
          node.targetId == testCase.targetId,
    );
    final secondaryFixture = plan.attemptNodes.singleWhere(
      (node) =>
          node.kind == CockpitSuitePlanNodeKind.fixtureSetup &&
          node.targetId == 'secondaryTarget',
    );

    expect(
      affinity.resolveBoundaryResourceId(isolation, 'sessionPrimary'),
      'sessionPrimary',
    );
    expect(
      affinity.resolveBoundaryResourceId(
        defaultTargetTeardown,
        'sessionPrimary',
      ),
      'sessionPrimary',
    );
    expect(
      () => affinity.resolveBoundaryResourceId(testCase, 'sessionDrifted'),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.code,
          'code',
          'suiteSessionDrift',
        ),
      ),
    );
    expect(
      affinity.resolveBoundaryResourceId(secondaryFixture, 'sessionSecondary'),
      'sessionSecondary',
    );
    affinity.release(testCase.nodeId);
    expect(
      affinity.resolveBoundaryResourceId(testCase, 'sessionReplacement'),
      'sessionReplacement',
    );
  });

  test('durable resume persists only complete case rows', () async {
    final plan = await _compilePlan(
      _singleCaseSuite(isolation: CockpitTestSuiteIsolation.restartApp),
    );
    final firstExecutor = _RecordingExecutor();
    final first = await _run(
      runId: 'run_resume',
      plan: plan,
      executor: firstExecutor,
    );
    final resumedExecutor = _RecordingExecutor();

    final resumed = await _run(
      runId: 'run_resume',
      plan: plan,
      executor: resumedExecutor,
      initialExecutions: first.executions,
    );

    expect(plan.nodes, hasLength(1));
    expect(plan.attemptNodes, hasLength(3));
    expect(resumedExecutor.calls, isEmpty);
    expect(resumed.executions.single.outcome, CockpitRunOutcome.passed);
  });

  test(
    'durable resume converts an active attempt into a retry checkpoint',
    () async {
      final plan = await _compilePlan(
        _singleCaseSuite(
          isolation: CockpitTestSuiteIsolation.restartApp,
          maxAttempts: 2,
        ),
      );
      final node = plan.caseNodes.single;
      final observer = _CheckpointObserver();
      final executor = _RecordingExecutor();
      final startedAt = DateTime.now().toUtc().subtract(
        const Duration(seconds: 1),
      );

      final result = await _run(
        runId: 'run_interrupted_resume',
        plan: plan,
        executor: executor,
        observer: observer,
        initialProgress: <CockpitSuiteNodeProgress>[
          CockpitSuiteNodeProgress(
            nodeId: node.nodeId,
            entryId: node.entryId,
            kind: node.kind,
            startedAt: startedAt,
            completedAttempts: const <CockpitTestAttemptReport>[],
            activeAttempt: CockpitSuiteActiveAttempt(
              attemptId: 'attempt_${node.nodeId}_1',
              number: 1,
              startedAt: startedAt,
              targetId: 'targetA',
            ),
          ),
        ],
      );

      final execution = result.executions.single;
      expect(execution.outcome, CockpitRunOutcome.passed);
      expect(execution.stability, CockpitRunStability.flaky);
      expect(
        execution.attempts.map((attempt) => attempt.outcome),
        <CockpitRunOutcome>[
          CockpitRunOutcome.interrupted,
          CockpitRunOutcome.passed,
        ],
      );
      expect(observer.startedNodes, isEmpty);
      expect(observer.startedAttempts, <String>['attempt_${node.nodeId}_2']);
      expect(observer.completedAttempts, <String>[
        'attempt_${node.nodeId}_1',
        'attempt_${node.nodeId}_2',
      ]);
    },
  );
}

CockpitTestSuite _orderedSuite({bool failFast = true}) => CockpitTestSuite(
  id: 'orderedSuite',
  execution: CockpitTestSuiteExecutionPolicy(
    maxConcurrency: 1,
    isolation: CockpitTestSuiteIsolation.restartApp,
    failFast: failFast,
  ),
  fixtures: <CockpitTestFixture>[
    CockpitTestFixture(
      id: 'suiteFixture',
      scope: CockpitTestFixtureScope.suite,
      setup: _source('suiteSetup'),
      teardown: _source('suiteTeardown'),
    ),
    CockpitTestFixture(
      id: 'attemptFixture',
      setup: _source('attemptSetup'),
      teardown: _source('attemptTeardown'),
      dependsOn: const <String>['suiteFixture'],
    ),
  ],
  cases: <CockpitTestSuiteEntry>[
    CockpitTestSuiteEntry(
      id: 'firstEntry',
      source: _source('firstCase'),
      fixtures: const <String>['attemptFixture'],
    ),
    CockpitTestSuiteEntry(
      id: 'secondEntry',
      source: _source('secondCase'),
      dependsOn: const <String>['firstEntry'],
      fixtures: const <String>['attemptFixture'],
    ),
  ],
);

CockpitTestSuite _singleCaseSuite({
  required CockpitTestSuiteIsolation isolation,
  int maxAttempts = 1,
  String? secondaryFixtureTargetId,
}) => CockpitTestSuite(
  id: 'singleCaseSuite',
  execution: CockpitTestSuiteExecutionPolicy(
    maxConcurrency: 1,
    isolation: isolation,
    retry: CockpitTestSuiteRetryPolicy(maxAttempts: maxAttempts),
  ),
  fixtures: <CockpitTestFixture>[
    CockpitTestFixture(
      id: 'attemptFixture',
      setup: _source('attemptSetup'),
      teardown: _source('attemptTeardown'),
    ),
    if (secondaryFixtureTargetId != null)
      CockpitTestFixture(
        id: 'secondaryFixture',
        setup: _source('secondarySetup'),
        targetId: secondaryFixtureTargetId,
      ),
  ],
  cases: <CockpitTestSuiteEntry>[
    CockpitTestSuiteEntry(
      id: 'onlyEntry',
      source: _source('onlyCase'),
      fixtures: <String>[
        'attemptFixture',
        if (secondaryFixtureTargetId != null) 'secondaryFixture',
      ],
    ),
  ],
);

CockpitTestSuite _selectionSuite() => CockpitTestSuite(
  id: 'selectionSuite',
  includeTags: const <String>['selected'],
  execution: CockpitTestSuiteExecutionPolicy(
    maxConcurrency: 1,
    isolation: CockpitTestSuiteIsolation.sharedSession,
    failFast: true,
  ),
  cases: <CockpitTestSuiteEntry>[
    CockpitTestSuiteEntry(
      id: 'alpha',
      source: _source('alphaCase'),
      tags: const <String>['excluded'],
    ),
    CockpitTestSuiteEntry(
      id: 'beta',
      source: _source('betaCase'),
      tags: const <String>['selected'],
    ),
  ],
);

CockpitTestSuiteInlineCaseSource _source(String caseId) =>
    CockpitTestSuiteInlineCaseSource(testCase: _testCase(caseId));

CockpitTestCase _testCase(String caseId) =>
    CockpitTestCase.fromJson(<String, Object?>{
      'schemaVersion': 'cockpit.test/v2',
      'kind': 'case',
      'id': caseId,
      'target': <String, Object?>{
        'platform': 'flutter',
        'targetKind': 'flutterApp',
        'plane': 'semantic',
      },
      'steps': <Object?>[
        <String, Object?>{
          'stepId': 'waitUntilIdle',
          'action': <String, Object?>{'type': 'waitForUiIdle', 'quietMs': 100},
        },
      ],
    });

Future<CockpitSuiteExecutionPlan> _compilePlan(CockpitTestSuite suite) =>
    const CockpitSuiteCompiler().compile(
      compiledSuite: CockpitCompiledTestSuite(
        suite: suite,
        sourceSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sourceMap: const <String, CockpitTestSourceLocation>{},
      ),
      resolver: const _NoFileCases(),
    );

Future<CockpitSuiteScheduleResult> _run({
  required String runId,
  required CockpitSuiteExecutionPlan plan,
  required _RecordingExecutor executor,
  CockpitSuiteCancellation? cancellation,
  Iterable<CockpitSuiteNodeExecution> initialExecutions =
      const <CockpitSuiteNodeExecution>[],
  Iterable<CockpitSuiteNodeProgress> initialProgress =
      const <CockpitSuiteNodeProgress>[],
  CockpitSuiteSchedulerObserver? observer,
}) =>
    CockpitSuiteScheduler(
      executor: CockpitSuiteRowAttemptExecutor(plan: plan, delegate: executor),
      observer: observer,
    ).run(
      runId: runId,
      plan: plan,
      cancellation: cancellation ?? _Cancellation(),
      initialExecutions: initialExecutions,
      initialProgress: initialProgress,
    );

final class _CheckpointObserver implements CockpitSuiteSchedulerObserver {
  final List<String> startedNodes = <String>[];
  final List<String> startedAttempts = <String>[];
  final List<String> completedAttempts = <String>[];

  @override
  Future<void> nodeStarted(
    CockpitSuitePlanNode node,
    DateTime startedAt,
  ) async {
    startedNodes.add(node.nodeId);
  }

  @override
  Future<void> attemptStarted(
    CockpitSuitePlanNode node,
    String attemptId,
    int attemptNumber,
    DateTime startedAt,
  ) async {
    startedAttempts.add(attemptId);
  }

  @override
  Future<void> attemptCompleted(
    CockpitSuitePlanNode node,
    CockpitTestAttemptReport attempt,
  ) async {
    completedAttempts.add(attempt.attemptId);
  }

  @override
  Future<void> nodeCompleted(
    CockpitSuitePlanNode node,
    CockpitSuiteNodeExecution execution,
  ) async {}
}

typedef _AttemptResultFactory =
    CockpitTestAttemptReport Function(
      CockpitSuitePlanNode node,
      String attemptId,
      int attemptNumber,
    );

final class _RecordingExecutor implements CockpitSuiteAttemptExecutor {
  _RecordingExecutor({this.resultFor, this.onExecute});

  final _AttemptResultFactory? resultFor;
  final void Function(CockpitSuitePlanNode node)? onExecute;
  final List<String> calls = <String>[];

  @override
  Future<CockpitTestAttemptReport> execute({
    required CockpitSuitePlanNode node,
    required String runId,
    required String attemptId,
    required int attemptNumber,
    required CockpitSuiteCancellation cancellation,
  }) async {
    calls.add(
      '${node.kind.name}:${node.kind == CockpitSuitePlanNodeKind.isolation ? node.entryId : node.compiledCase.testCase.id}',
    );
    onExecute?.call(node);
    return resultFor?.call(node, attemptId, attemptNumber) ??
        _attempt(attemptId, attemptNumber);
  }
}

CockpitTestAttemptReport _attempt(
  String attemptId,
  int attemptNumber, {
  CockpitRunOutcome outcome = CockpitRunOutcome.passed,
  bool retryable = false,
  String code = 'suiteIsolationUnsupported',
  String message = 'Isolation is unsupported.',
}) {
  final startedAt = DateTime.utc(2026, 7, 23, 10, 0, attemptNumber);
  final finishedAt = startedAt.add(const Duration(milliseconds: 10));
  return CockpitTestAttemptReport(
    attemptId: attemptId,
    number: attemptNumber,
    outcome: outcome,
    startedAt: startedAt,
    finishedAt: finishedAt,
    durationMs: 10,
    targetId: 'targetA',
    failure: outcome == CockpitRunOutcome.passed
        ? null
        : CockpitFailure(
            primary: CockpitApiError(
              code: code,
              category: CockpitErrorCategory.unsupported,
              message: message,
              retryable: retryable,
              responsibleLayer: CockpitResponsibleLayer.worker,
            ),
          ),
  );
}

final class _Cancellation implements CockpitSuiteCancellation {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class _NoFileCases implements CockpitSuiteCaseResolver {
  const _NoFileCases();

  @override
  Future<CockpitCompiledTestCase> resolveFile(
    CockpitTestSuiteFileCaseSource source,
  ) => throw StateError('The contract suite uses inline cases only.');
}
