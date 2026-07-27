import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_application_service_exception.dart';
import '../runner/cockpit_case_execution_control.dart';
import '../runner/cockpit_case_runner.dart';
import '../suite/cockpit_suite_compiler.dart';
import '../suite/cockpit_suite_execution_plan.dart';
import '../suite/cockpit_suite_report_assembler.dart';
import '../suite/cockpit_suite_report_writer.dart';
import '../suite/cockpit_suite_row_attempt_executor.dart';
import '../suite/cockpit_suite_scheduler.dart';
import '../test/cockpit_test_document_compiler.dart';
import '../test/cockpit_test_safety_policy.dart';
import '../test/cockpit_test_secret_resolver.dart';
import '../test/cockpit_test_variable_binder.dart';
import 'cockpit_case_run_adapter.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_artifact_publisher.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_resource_scope.dart';
import 'cockpit_worker_run_event_store.dart';
import 'cockpit_worker_suite_run_store.dart';
import 'cockpit_worker_logger.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitSuiteRunAdapterFactory {
  CockpitSuiteRunAdapterFactory({
    required this.workspaceId,
    required this.projectId,
    required this.engineVersion,
    this.authorizationMode = CockpitAuthorizationMode.restricted,
    required this.runStateRoot,
    required CockpitWorkerDocumentIndex documents,
    required CockpitWorkerSessionProvider sessions,
    required CockpitWorkerResourceAuthorityClient resourceAuthority,
    required CockpitTestSecretResolver secretResolver,
    required CockpitTestSafetyPolicy safetyPolicy,
    required CockpitWorkerLogRedactor redactor,
    required CockpitWorkerLogger logger,
    required CockpitWorkerRunEventStore eventStore,
    required CockpitWorkerSuiteRunStore runStore,
    CockpitWorkerArtifactPublisher? artifactPublisher,
    DateTime Function()? utcNow,
  }) : _documents = documents,
       _sessions = sessions,
       _resourceAuthority = resourceAuthority,
       _secretResolver = secretResolver,
       _safetyPolicy = safetyPolicy,
       _redactor = redactor,
       _logger = logger,
       _eventStore = eventStore,
       _runStore = runStore,
       _artifactPublisher = artifactPublisher,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final String workspaceId;
  final String projectId;
  final String engineVersion;
  final CockpitAuthorizationMode authorizationMode;
  final String runStateRoot;
  final CockpitWorkerDocumentIndex _documents;
  final CockpitWorkerSessionProvider _sessions;
  final CockpitWorkerResourceAuthorityClient _resourceAuthority;
  final CockpitTestSecretResolver _secretResolver;
  final CockpitTestSafetyPolicy _safetyPolicy;
  final CockpitWorkerLogRedactor _redactor;
  final CockpitWorkerLogger _logger;
  final CockpitWorkerRunEventStore _eventStore;
  final CockpitWorkerSuiteRunStore _runStore;
  final CockpitWorkerArtifactPublisher? _artifactPublisher;
  final DateTime Function() _utcNow;

  CockpitWorkspaceOperationAdapter
  runAdapter() => CockpitWorkspaceOperationAdapter(
    kind: 'suite.run',
    mutationClass: CockpitMutationClass.mutating,
    resourceKinds: const <String>['workspace.runs'],
    prepare: (context, input) async {
      final submission = CockpitRunSubmission.fromJson(input);
      final source = submission.source;
      if (source is! CockpitSuiteSubmissionSource) {
        throw const FormatException('Suite run requires a suite source.');
      }
      if (submission.workspaceId != workspaceId ||
          submission.idempotencyKey.value != context.idempotencyKey) {
        throw const FormatException('Suite run identity mismatch.');
      }
      final missing = submission.requiredFeatures
          .where((feature) => !context.requiredFeatures.contains(feature))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        throw FormatException(
          'Suite run required features are unavailable: ${missing.join(', ')}.',
        );
      }
      final compiled = await _compiled(source);
      final plan = await const CockpitSuiteCompiler().compile(
        compiledSuite: compiled,
        resolver: _documents,
      );
      final runId = 'run_${context.requestId}';
      final reservation = await _runStore.reserve(
        runId: runId,
        idempotencyKey: context.idempotencyKey,
        requestFingerprint: _fingerprint(submission, plan),
        suiteId: compiled.suite.id,
        sourceSha256: compiled.sourceSha256,
        startedAt: _utcNow(),
      );
      if (reservation.completed) {
        return CockpitPreparedWorkspaceOperation(
          resources: const <CockpitWorkerResourceRequest>[],
          isIdempotentReplay: true,
          execute: (_) async => reservation.completedOutput!,
        );
      }
      return CockpitPreparedWorkspaceOperation(
        resources: <CockpitWorkerResourceRequest>[
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.run,
            resourceId: runId,
            ttl: _resourceTtl(context.deadline),
          ),
        ],
        cancellationGrace: _cancellationGrace(context.deadline),
        execute: (_) => _execute(
          context: context,
          submission: submission,
          plan: plan,
          reservation: reservation,
        ),
      );
    },
  );

  Future<CockpitCompiledTestSuite> _compiled(
    CockpitSuiteSubmissionSource source,
  ) => switch (source) {
    CockpitInlineSuiteSource() => Future<CockpitCompiledTestSuite>.value(
      CockpitCompiledTestSuite(
        suite: source.suite,
        sourceSha256: source.sourceSha256,
        sourceMap: const <String, CockpitTestSourceLocation>{},
      ),
    ),
    CockpitIndexedSuiteSource() => _documents.resolveSuite(source.reference),
  };

  Future<Map<String, Object?>> _execute({
    required CockpitWorkspaceOperationContext context,
    required CockpitRunSubmission submission,
    required CockpitSuiteExecutionPlan plan,
    required CockpitWorkerSuiteReservation reservation,
  }) async {
    final runId = reservation.runId;
    await _initializeEvents(runId);
    final execution = _SuiteAttemptExecution(
      workspaceId: workspaceId,
      projectId: projectId,
      engineVersion: engineVersion,
      authorizationMode: authorizationMode,
      runStateRoot: runStateRoot,
      context: context,
      runId: runId,
      plan: plan,
      sessions: _sessions,
      resourceAuthority: _resourceAuthority,
      secretResolver: _secretResolver,
      safetyPolicy: _safetyPolicy,
      redactor: _redactor,
      logger: _logger,
      eventStore: _eventStore,
      runStore: _runStore,
      artifactPublisher: _artifactPublisher,
      initialSessionBindings: reservation.sessionBindings,
      utcNow: _utcNow,
    );
    CockpitSuiteScheduleResult schedule;
    CockpitFailure? executionFailure;
    try {
      schedule =
          await CockpitSuiteScheduler(
            executor: CockpitSuiteRowAttemptExecutor(
              plan: plan,
              delegate: execution,
              onAttemptFinished: execution.closeRowResourceBoundary,
              utcNow: _utcNow,
            ),
            observer: execution,
            utcNow: _utcNow,
          ).run(
            runId: runId,
            plan: plan,
            cancellation: execution,
            initialExecutions: reservation.executions,
            initialProgress: reservation.progress,
          );
    } on Object catch (error, stackTrace) {
      _logger.log(
        'error',
        'Suite execution failed.',
        fields: <String, Object?>{
          'runId': runId,
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
      executionFailure = _suiteExecutionFailure();
      schedule = await _finalizeFailedSchedule(
        plan: plan,
        execution: execution,
        failure: executionFailure,
      );
    } finally {
      await execution.closeResourceBoundaries();
    }
    final finishedAt = _utcNow();
    final report = const CockpitSuiteReportAssembler().assemble(
      projectId: projectId,
      workspaceId: workspaceId,
      runId: runId,
      plan: plan,
      schedule: schedule,
      startedAt: reservation.startedAt,
      finishedAt: finishedAt,
      failure: executionFailure,
      environment: <String, Object?>{
        'engineVersion': engineVersion,
        'authorizationMode': authorizationMode.name,
        'requiredFeatures': submission.requiredFeatures,
      },
      artifacts: execution.publishedArtifacts.map(
        (artifact) => artifact.reference,
      ),
    );
    await execution.publishCaseCompletions(plan, report);
    final reportRoot = p.join(runStateRoot, 'runs', runId, 'report');
    CockpitSuiteReportFiles? files;
    var reportArtifacts = const <CockpitArtifactResource>[];
    CockpitFailure? finalizationFailure;
    try {
      files = await const CockpitSuiteReportWriter().write(
        report: report,
        runRoot: reportRoot,
        sourceRunRoot: p.join(runStateRoot, 'runs', runId),
        artifactResources: execution.publishedArtifacts,
      );
      if (_artifactPublisher case final publisher?) {
        reportArtifacts = await publisher.publishSuiteReport(
          report: report,
          reportRoot: reportRoot,
          deadline: _utcNow().add(const Duration(minutes: 1)),
          cancellation: CockpitRpcCancellation.detached(),
        );
      }
    } on Object catch (error, stackTrace) {
      _logger.log(
        'error',
        'Suite report finalization or publication failed.',
        fields: <String, Object?>{
          'workspaceId': workspaceId,
          'runId': runId,
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
      finalizationFailure = _suiteFinalizationFailure();
    }
    final terminalOutcome = finalizationFailure == null
        ? report.outcome
        : CockpitRunOutcome.internalError;
    final failure = _mergeFailures(_reportFailure(report), finalizationFailure);
    await _eventStore.append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'report.completed',
        entityKind: CockpitRunEventEntityKind.report,
        outcome: terminalOutcome,
        stability: report.stability,
        failure: failure,
        artifacts: reportArtifacts
            .map((artifact) => artifact.reference)
            .toList(growable: false),
      ),
    );
    await _eventStore.append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'suite.completed',
        entityKind: CockpitRunEventEntityKind.suite,
        lifecycle: CockpitRunLifecycle.completed,
        outcome: terminalOutcome,
        stability: report.stability,
        failure: failure,
      ),
    );
    await _eventStore.append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'run.completed',
        entityKind: CockpitRunEventEntityKind.run,
        lifecycle: CockpitRunLifecycle.completed,
        outcome: terminalOutcome,
        stability: report.stability,
        failure: failure,
      ),
    );
    final output = <String, Object?>{
      'runId': runId,
      'outcome': terminalOutcome.name,
      'report': report.toJson(),
      'reportFiles': <String, Object?>{
        for (final entry
            in files?.paths.entries ??
                const <MapEntry<CockpitTestReportFormat, String>>[])
          entry.key.name: p.basename(entry.value),
      },
      'reportArtifacts': reportArtifacts
          .map((artifact) => artifact.toJson())
          .toList(growable: false),
      if (finalizationFailure != null)
        'finalizationFailure': finalizationFailure.toJson(),
    };
    await _runStore.complete(runId: runId, output: output);
    return output;
  }

  Future<CockpitSuiteScheduleResult> _finalizeFailedSchedule({
    required CockpitSuiteExecutionPlan plan,
    required _SuiteAttemptExecution execution,
    required CockpitFailure failure,
  }) async {
    final checkpoint = await _runStore.read(execution.runId);
    final completed = <String, CockpitSuiteNodeExecution>{
      for (final item in checkpoint.executions) item.nodeId: item,
    };
    final progress = <String, CockpitSuiteNodeProgress>{
      for (final item in checkpoint.progress) item.nodeId: item,
    };
    for (final node in plan.nodes) {
      if (completed.containsKey(node.nodeId)) continue;
      final nodeProgress = progress[node.nodeId];
      final attempts = <CockpitTestAttemptReport>[
        ...?nodeProgress?.completedAttempts,
      ];
      if (nodeProgress?.activeAttempt case final active?) {
        final now = _utcNow();
        final finishedAt = now.isBefore(active.startedAt)
            ? active.startedAt
            : now;
        final attempt = CockpitTestAttemptReport(
          attemptId: active.attemptId,
          number: active.number,
          outcome: CockpitRunOutcome.internalError,
          startedAt: active.startedAt,
          finishedAt: finishedAt,
          durationMs: finishedAt.difference(active.startedAt).inMilliseconds,
          targetId: active.targetId,
          failure: failure,
        );
        attempts.add(attempt);
        await execution.attemptCompleted(node, attempt);
      }
      final nodeExecution = CockpitSuiteNodeExecution(
        nodeId: node.nodeId,
        entryId: node.entryId,
        kind: node.kind,
        outcome: CockpitRunOutcome.internalError,
        stability: CockpitRunStability.unknown,
        attempts: attempts,
        startedAt: nodeProgress?.startedAt,
        finishedAt: _utcNow(),
      );
      await execution.nodeCompleted(node, nodeExecution);
      completed[node.nodeId] = nodeExecution;
    }
    return CockpitSuiteScheduleResult(
      runId: execution.runId,
      executions: plan.nodes.map((node) => completed[node.nodeId]!),
    );
  }

  Future<void> _initializeEvents(String runId) async {
    final existing = await _eventStore.eventsForRun(runId);
    if (existing.isNotEmpty) return;
    for (final entity in const <CockpitRunEventEntityKind>[
      CockpitRunEventEntityKind.run,
      CockpitRunEventEntityKind.suite,
    ]) {
      await _eventStore.append(
        runId,
        CockpitWorkerEventDraft(
          kind: '${entity.wireName}.queued',
          entityKind: entity,
          lifecycle: CockpitRunLifecycle.queued,
        ),
      );
    }
    for (final entity in const <CockpitRunEventEntityKind>[
      CockpitRunEventEntityKind.run,
      CockpitRunEventEntityKind.suite,
    ]) {
      await _eventStore.append(
        runId,
        CockpitWorkerEventDraft(
          kind: '${entity.wireName}.running',
          entityKind: entity,
          lifecycle: CockpitRunLifecycle.running,
        ),
      );
    }
  }

  String _fingerprint(
    CockpitRunSubmission submission,
    CockpitSuiteExecutionPlan plan,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode(
            _canonical(<String, Object?>{
              'submission': submission.toJson(),
              'plan': plan.toJson(),
            }),
          ),
        ),
      )
      .toString();

  Duration _resourceTtl(DateTime deadline) {
    final remaining = deadline.difference(_utcNow());
    if (remaining < const Duration(seconds: 1)) {
      return const Duration(seconds: 1);
    }
    return remaining > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : remaining;
  }

  Duration _cancellationGrace(DateTime deadline) {
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) return const Duration(seconds: 1);
    const maximum = Duration(minutes: 5);
    return remaining < maximum ? remaining : maximum;
  }
}

final class _SuiteAttemptExecution
    implements
        CockpitSuiteAttemptExecutor,
        CockpitSuiteSchedulerObserver,
        CockpitSuiteCancellation {
  _SuiteAttemptExecution({
    required this.workspaceId,
    required this.projectId,
    required this.engineVersion,
    required this.authorizationMode,
    required this.runStateRoot,
    required this.context,
    required this.runId,
    required this.plan,
    required CockpitWorkerSessionProvider sessions,
    required CockpitWorkerResourceAuthorityClient resourceAuthority,
    required CockpitTestSecretResolver secretResolver,
    required CockpitTestSafetyPolicy safetyPolicy,
    required CockpitWorkerLogRedactor redactor,
    required CockpitWorkerLogger logger,
    required CockpitWorkerRunEventStore eventStore,
    required CockpitWorkerSuiteRunStore runStore,
    required CockpitWorkerArtifactPublisher? artifactPublisher,
    required Map<String, String> initialSessionBindings,
    required DateTime Function() utcNow,
  }) : _sessions = sessions,
       _resourceAuthority = resourceAuthority,
       _secretResolver = secretResolver,
       _safetyPolicy = safetyPolicy,
       _redactor = redactor,
       _logger = logger,
       _eventStore = eventStore,
       _runStore = runStore,
       _artifactPublisher = artifactPublisher,
       _utcNow = utcNow,
       _rowSessionAffinity = CockpitSuiteRowSessionAffinity(
         plan,
         initialBindings: initialSessionBindings,
       );

  final String workspaceId;
  final String projectId;
  final String engineVersion;
  final CockpitAuthorizationMode authorizationMode;
  final String runStateRoot;
  final CockpitWorkspaceOperationContext context;
  final String runId;
  final CockpitSuiteExecutionPlan plan;
  final CockpitWorkerSessionProvider _sessions;
  final CockpitWorkerResourceAuthorityClient _resourceAuthority;
  final CockpitTestSecretResolver _secretResolver;
  final CockpitTestSafetyPolicy _safetyPolicy;
  final CockpitWorkerLogRedactor _redactor;
  final CockpitWorkerLogger _logger;
  final CockpitWorkerRunEventStore _eventStore;
  final CockpitWorkerSuiteRunStore _runStore;
  final CockpitWorkerArtifactPublisher? _artifactPublisher;
  final DateTime Function() _utcNow;
  final CockpitSuiteRowSessionAffinity _rowSessionAffinity;
  final Map<String, Map<String, Future<_SuiteRowResourceBoundary>>>
  _rowBoundaries = <String, Map<String, Future<_SuiteRowResourceBoundary>>>{};
  final Map<String, CockpitArtifactResource> _publishedArtifacts =
      <String, CockpitArtifactResource>{};

  List<CockpitArtifactResource> get publishedArtifacts =>
      List<CockpitArtifactResource>.unmodifiable(
        _publishedArtifacts.values.toList(growable: false)
          ..sort((left, right) => left.artifactId.compareTo(right.artifactId)),
      );

  @override
  bool get isCancelled => context.cancellation.isCancelled;

  @override
  Future<void> get whenCancelled => context.cancellation.whenCancelled;

  @override
  Future<void> nodeStarted(
    CockpitSuitePlanNode node,
    DateTime startedAt,
  ) async {
    await _runStore.recordNodeStarted(
      runId: runId,
      nodeId: node.nodeId,
      entryId: node.entryId,
      kind: node.kind,
      startedAt: startedAt,
    );
    if (node.kind != CockpitSuitePlanNodeKind.testCase) return;
    await _eventStore.append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'case.running',
        entityKind: CockpitRunEventEntityKind.testCase,
        caseId: node.compiledCase.testCase.id,
        targetId: node.targetId,
        requestedPlane: node.compiledCase.testCase.target.plane,
      ),
    );
  }

  @override
  Future<void> attemptStarted(
    CockpitSuitePlanNode node,
    String attemptId,
    int attemptNumber,
    DateTime startedAt,
  ) => _runStore.recordAttemptStarted(
    runId: runId,
    nodeId: node.nodeId,
    attemptId: attemptId,
    attemptNumber: attemptNumber,
    startedAt: startedAt,
    targetId: node.targetId ?? 'unassigned',
  );

  @override
  Future<void> attemptCompleted(
    CockpitSuitePlanNode node,
    CockpitTestAttemptReport attempt,
  ) async {
    await _runStore.recordAttemptCompleted(
      runId: runId,
      nodeId: node.nodeId,
      attempt: attempt,
    );
    if (node.kind != CockpitSuitePlanNodeKind.testCase) return;
    final existing = await _eventStore.eventsForRun(runId);
    if (existing.any(
      (event) =>
          event.entityKind == CockpitRunEventEntityKind.attempt &&
          event.attemptId == attempt.attemptId &&
          event.outcome != null,
    )) {
      return;
    }
    await _eventStore.append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'attempt.completed',
        entityKind: CockpitRunEventEntityKind.attempt,
        caseId: node.compiledCase.testCase.id,
        attemptId: attempt.attemptId,
        outcome: attempt.outcome,
        targetId: attempt.targetId,
        requestedPlane: node.compiledCase.testCase.target.plane,
        failure: attempt.failure,
        artifacts: attempt.artifacts,
      ),
    );
  }

  @override
  Future<void> nodeCompleted(
    CockpitSuitePlanNode node,
    CockpitSuiteNodeExecution execution,
  ) async {
    final releasedKeys = _rowSessionAffinity.bindingsReleasedBy(node);
    await _runStore.recordExecution(
      runId: runId,
      execution: execution,
      releasedSessionBindingKeys: releasedKeys,
    );
    _rowSessionAffinity.releaseBindings(releasedKeys);
  }

  @override
  Future<CockpitTestAttemptReport> execute({
    required CockpitSuitePlanNode node,
    required String runId,
    required String attemptId,
    required int attemptNumber,
    required CockpitSuiteCancellation cancellation,
  }) async {
    if (node.kind == CockpitSuitePlanNodeKind.isolation) {
      return _executeIsolation(
        node: node,
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        cancellation: cancellation,
      );
    }
    final compiled = node.compiledCase;
    final testCase = compiled.testCase;
    final plan = CockpitTestVariableBinder().bind(
      compiled,
      inputs: node.inputs,
    );
    late final CockpitWorkerHealthySession session;
    late final _SuiteRowResourceBoundary? rowBoundary;
    final startedAt = _utcNow();
    try {
      session = await _selectSession(node);
      rowBoundary = await _rowResourceBoundary(node, session);
    } on CockpitApplicationServiceException catch (error) {
      if (error.code != 'suiteSessionDrift' &&
          error.code != 'suiteSessionUnavailable') {
        rethrow;
      }
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: node.targetId ?? 'unassigned',
        code: error.code,
        message: error.message,
        category: CockpitErrorCategory.environment,
        retryable: false,
        details: error.details,
      );
    }
    final ttl = _resourceTtl();
    final holderDigest = sha256
        .convert(utf8.encode('$runId\u0000${node.nodeId}\u0000$attemptId'))
        .toString();
    final operationCancellation = node.alwaysRun
        ? CockpitRpcCancellation.detached()
        : context.cancellation;
    final scope = await CockpitWorkerResourceScope.acquire(
      authority: _resourceAuthority,
      cancellation: operationCancellation,
      requests: <CockpitWorkerResourceRequest>[
        if (rowBoundary == null) ...<CockpitWorkerResourceRequest>[
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.device,
            resourceId: session.deviceResourceId,
            ttl: ttl,
          ),
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.session,
            resourceId: session.resourceId,
            ttl: ttl,
          ),
        ],
        for (final kind in const <CockpitLeaseResourceKind>[
          CockpitLeaseResourceKind.capture,
          CockpitLeaseResourceKind.recording,
        ])
          CockpitWorkerResourceRequest(
            resourceKind: kind,
            resourceId: session.resourceId,
            ttl: ttl,
          ),
      ],
      workspaceId: workspaceId,
      holderId: 'suite-attempt-${holderDigest.substring(0, 32)}',
      idempotencyKey: '${context.idempotencyKey}-${node.nodeId}-$attemptNumber',
      deadline: context.deadline,
    );
    void Function()? unregisterForceAbort;
    var stage = 'attemptEvent';
    try {
      await _eventStore.append(
        runId,
        CockpitWorkerEventDraft(
          kind: 'attempt.running',
          entityKind: CockpitRunEventEntityKind.attempt,
          caseId: testCase.id,
          attemptId: attemptId,
          targetId: session.targetId,
          requestedPlane: testCase.target.plane,
        ),
      );
      stage = 'healthCheck';
      if (!await session.healthCheck()) {
        throw const FormatException(
          'Selected automation session is unhealthy.',
        );
      }
      final control = CockpitCaseExecutionControl(
        forceAbort: session.forceAbort,
      );
      if (session.forceAbort case final forceAbort?) {
        unregisterForceAbort = operationCancellation.registerForceAbort(
          forceAbort,
        );
      }
      unawaited(cancellation.whenCancelled.then((_) => control.cancel()));
      stage = 'attemptDirectory';
      final attemptRoot = p.join(
        runStateRoot,
        'runs',
        runId,
        'cases',
        testCase.id,
        'attempts',
        attemptId,
      );
      await Directory(attemptRoot).create(recursive: true);
      final scanner = CockpitCaseAttemptRedactionScanner(
        runStateRoot: runStateRoot,
        redactor: _redactor,
        deadline: context.deadline,
        isCancelled: () => cancellation.isCancelled,
        utcNow: _utcNow,
      );
      final runner = CockpitCaseRunner(
        automationAdapter: session.automationAdapter,
        captureAdapter: session.captureAdapter,
        recordingAdapter: session.recordingAdapter,
        systemAutomationAdapter: session.systemAutomationAdapter,
        systemCaptureAdapter: session.systemCaptureAdapter,
        systemRecordingAdapter: session.systemRecordingAdapter,
        lowerer: session.lowerer,
        secretResolver: _secretResolver,
        safetyPolicy: _safetyPolicy,
        bundlePrePublicationValidator: scanner.validateForPublication,
      );
      stage = 'caseRun';
      final run = scope.guard(
        runner.run(
          compiled: compiled,
          preparedPlan: plan,
          context: CockpitTestRunContext(
            projectId: projectId,
            workspaceId: workspaceId,
            runId: runId,
            caseId: testCase.id,
            attemptId: attemptId,
            engineVersion: engineVersion,
            authorizationMode: authorizationMode,
          ),
          targetId: session.targetId,
          targetEnvironment: session.environment,
          reportRoot: attemptRoot,
          control: control,
        ),
      );
      final result = await (rowBoundary == null
          ? run
          : rowBoundary.scope.guard(run));
      stage = 'redactionVerification';
      await scanner.verify(attemptRoot);
      var artifacts = const <CockpitArtifactResource>[];
      if (_artifactPublisher case final publisher?
          when result.bundlePath != null) {
        stage = 'artifactPublication';
        artifacts = await publisher.publishAttemptBundle(
          runId: runId,
          caseId: testCase.id,
          attemptId: attemptId,
          bundleRoot: result.bundlePath!,
          deadline: context.deadline,
          cancellation: operationCancellation,
        );
        for (final artifact in artifacts) {
          final existing = _publishedArtifacts[artifact.artifactId];
          if (existing != null &&
              jsonEncode(existing.toJson()) != jsonEncode(artifact.toJson())) {
            throw const FormatException(
              'Published attempt artifact identity changed during the suite.',
            );
          }
          _publishedArtifacts[artifact.artifactId] = artifact;
        }
      }
      stage = 'resultEvents';
      await _appendResultEvents(
        result,
        artifacts,
        includeAttemptCompletion:
            node.kind != CockpitSuitePlanNodeKind.testCase,
      );
      return _attemptReport(result, attemptNumber, artifacts);
    } on Object catch (error, stackTrace) {
      _logger.log(
        'error',
        'Suite attempt execution failed.',
        fields: <String, Object?>{
          'workspaceId': workspaceId,
          'runId': runId,
          'caseId': testCase.id,
          'attemptId': attemptId,
          'targetId': session.targetId,
          'stage': stage,
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
      rethrow;
    } finally {
      unregisterForceAbort?.call();
      try {
        await scope.close(cancel: cancellation.isCancelled);
      } on Object catch (error, stackTrace) {
        _logger.log(
          'error',
          'Suite attempt resource release failed.',
          fields: <String, Object?>{
            'workspaceId': workspaceId,
            'runId': runId,
            'caseId': testCase.id,
            'attemptId': attemptId,
            'targetId': session.targetId,
            'stage': 'resourceRelease',
            'errorType': error.runtimeType.toString(),
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        );
        rethrow;
      }
    }
  }

  Future<CockpitTestAttemptReport> _executeIsolation({
    required CockpitSuitePlanNode node,
    required String attemptId,
    required int attemptNumber,
    required CockpitSuiteCancellation cancellation,
  }) async {
    final startedAt = _utcNow();
    if (cancellation.isCancelled) {
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: node.targetId ?? 'unassigned',
        code: CockpitErrorCode.cancelled,
        message: 'Suite isolation was cancelled.',
        category: CockpitErrorCategory.cancelled,
        retryable: false,
      );
    }
    final isolation = node.isolation!;
    late final CockpitWorkerHealthySession session;
    try {
      session = await _selectSession(node);
    } on CockpitApplicationServiceException catch (error) {
      if (error.code != 'suiteSessionDrift' &&
          error.code != 'suiteSessionUnavailable') {
        rethrow;
      }
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: node.targetId ?? 'unassigned',
        code: error.code,
        message: error.message,
        category: CockpitErrorCategory.environment,
        retryable: false,
        details: error.details,
      );
    }
    final rowBoundary = await _rowResourceBoundary(node, session);
    if (rowBoundary == null) {
      throw StateError('Suite isolation is missing its case row boundary.');
    }
    if (isolation == CockpitTestSuiteIsolation.sharedSession) {
      final finishedAt = _utcNow();
      return CockpitTestAttemptReport(
        attemptId: attemptId,
        number: attemptNumber,
        outcome: CockpitRunOutcome.passed,
        startedAt: startedAt,
        finishedAt: finishedAt,
        durationMs: finishedAt.difference(startedAt).inMilliseconds,
        targetId: session.targetId,
      );
    }
    final isolate = session.isolate;
    if (isolate == null) {
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: session.targetId,
        code: 'suiteIsolationUnsupported',
        message:
            '${isolation.name} is not supported by the selected driver session.',
        category: CockpitErrorCategory.unsupported,
        retryable: false,
      );
    }
    void Function()? unregisterForceAbort;
    try {
      if (session.forceAbort case final forceAbort?) {
        unregisterForceAbort = context.cancellation.registerForceAbort(
          forceAbort,
        );
      }
      await rowBoundary.scope.guard(isolate(isolation, context.deadline));
      if (cancellation.isCancelled) {
        return _suiteRuntimeFailure(
          attemptId: attemptId,
          attemptNumber: attemptNumber,
          startedAt: startedAt,
          targetId: session.targetId,
          code: CockpitErrorCode.cancelled,
          message: 'Suite isolation was cancelled.',
          category: CockpitErrorCategory.cancelled,
          retryable: false,
        );
      }
      final refreshed = await _selectSession(node);
      await _rowResourceBoundary(node, refreshed);
    } on CockpitApplicationServiceException catch (error) {
      if (cancellation.isCancelled) {
        return _suiteRuntimeFailure(
          attemptId: attemptId,
          attemptNumber: attemptNumber,
          startedAt: startedAt,
          targetId: session.targetId,
          code: CockpitErrorCode.cancelled,
          message: 'Suite isolation was cancelled.',
          category: CockpitErrorCategory.cancelled,
          retryable: false,
        );
      }
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: session.targetId,
        code: error.code,
        message: error.message,
        category: error.code == 'suiteIsolationUnsupported'
            ? CockpitErrorCategory.unsupported
            : CockpitErrorCategory.environment,
        retryable: error.code != 'suiteIsolationUnsupported',
        details: error.details,
      );
    } on TimeoutException {
      if (cancellation.isCancelled) {
        return _suiteRuntimeFailure(
          attemptId: attemptId,
          attemptNumber: attemptNumber,
          startedAt: startedAt,
          targetId: session.targetId,
          code: CockpitErrorCode.cancelled,
          message: 'Suite isolation was cancelled.',
          category: CockpitErrorCategory.cancelled,
          retryable: false,
        );
      }
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: session.targetId,
        code: CockpitErrorCode.interrupted,
        message: 'Suite isolation exceeded the run deadline.',
        category: CockpitErrorCategory.interrupted,
        retryable: true,
      );
    } on Object {
      if (!cancellation.isCancelled) rethrow;
      return _suiteRuntimeFailure(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        startedAt: startedAt,
        targetId: session.targetId,
        code: CockpitErrorCode.cancelled,
        message: 'Suite isolation was cancelled.',
        category: CockpitErrorCategory.cancelled,
        retryable: false,
      );
    } finally {
      unregisterForceAbort?.call();
    }
    final finishedAt = _utcNow();
    return CockpitTestAttemptReport(
      attemptId: attemptId,
      number: attemptNumber,
      outcome: CockpitRunOutcome.passed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: finishedAt.difference(startedAt).inMilliseconds,
      targetId: session.targetId,
    );
  }

  Future<CockpitWorkerHealthySession> _selectSession(
    CockpitSuitePlanNode node,
  ) async {
    final preferredResourceId = _rowSessionAffinity.preferredResourceId(node);
    late final CockpitWorkerHealthySession session;
    try {
      session = await _sessions.selectHealthySession(
        targetId: node.targetId,
        requirements: node.compiledCase.testCase.target,
        preferredResourceId: preferredResourceId,
      );
    } on CockpitApplicationServiceException catch (error) {
      if (preferredResourceId == null ||
          error.code != 'healthySessionNotFound') {
        rethrow;
      }
      throw CockpitApplicationServiceException(
        code: 'suiteSessionUnavailable',
        message:
            'The session required by the durable suite checkpoint is unavailable.',
        details: <String, Object?>{
          'nodeId': node.nodeId,
          'sessionResourceId': preferredResourceId,
        },
      );
    }
    final binding = _rowSessionAffinity.resolveBinding(
      node,
      session.resourceId,
    );
    await _runStore.bindSession(
      runId: runId,
      bindingKey: binding.key,
      sessionResourceId: binding.resourceId,
    );
    return session;
  }

  Future<_SuiteRowResourceBoundary?> _rowResourceBoundary(
    CockpitSuitePlanNode node,
    CockpitWorkerHealthySession session,
  ) async {
    final caseNodeId = node.caseNodeId;
    if (caseNodeId == null) return null;
    final boundaryResourceId = session.resourceId;
    final boundaries = _rowBoundaries.putIfAbsent(
      caseNodeId,
      () => <String, Future<_SuiteRowResourceBoundary>>{},
    );
    return boundaries.putIfAbsent(
      boundaryResourceId,
      () => _acquireRowResourceBoundary(caseNodeId, session),
    );
  }

  Future<_SuiteRowResourceBoundary> _acquireRowResourceBoundary(
    String caseNodeId,
    CockpitWorkerHealthySession session,
  ) async {
    final digest = sha256
        .convert(
          utf8.encode('$runId\u0000$caseNodeId\u0000${session.resourceId}'),
        )
        .toString();
    final scope = await CockpitWorkerResourceScope.acquire(
      authority: _resourceAuthority,
      cancellation: CockpitRpcCancellation.detached(),
      requests: <CockpitWorkerResourceRequest>[
        CockpitWorkerResourceRequest(
          resourceKind: CockpitLeaseResourceKind.device,
          resourceId: session.deviceResourceId,
          ttl: _resourceTtl(),
        ),
        CockpitWorkerResourceRequest(
          resourceKind: CockpitLeaseResourceKind.session,
          resourceId: session.resourceId,
          ttl: _resourceTtl(),
        ),
      ],
      workspaceId: workspaceId,
      holderId: 'suite-row-${digest.substring(0, 32)}',
      idempotencyKey:
          '${context.idempotencyKey}-row-${digest.substring(0, 32)}',
      deadline: context.deadline,
    );
    return _SuiteRowResourceBoundary(scope: scope);
  }

  Future<void> closeRowResourceBoundary(CockpitSuitePlanNode caseNode) =>
      _closeRowResourceBoundary(caseNode.nodeId);

  Future<void> _closeRowResourceBoundary(String caseNodeId) async {
    final boundaries = _rowBoundaries.remove(caseNodeId);
    if (boundaries != null) {
      for (final pending in boundaries.values) {
        try {
          final boundary = await pending;
          await boundary.scope.close(cancel: context.cancellation.isCancelled);
        } on Object {
          // Lease recovery remains owned by the Supervisor after release failure.
        }
      }
    }
    final releasedKeys = _rowSessionAffinity.release(caseNodeId);
    await _runStore.releaseSessionBindings(
      runId: runId,
      bindingKeys: releasedKeys,
    );
  }

  Future<void> closeResourceBoundaries() async {
    for (final caseNodeId in _rowBoundaries.keys.toList(growable: false)) {
      await _closeRowResourceBoundary(caseNodeId);
    }
  }

  Future<void> publishCaseCompletions(
    CockpitSuiteExecutionPlan plan,
    CockpitTestSuiteReport report,
  ) async {
    final caseNodes = plan.caseNodes.toList(growable: false);
    if (caseNodes.length != report.cases.length) {
      throw StateError('Suite case report projection is incomplete.');
    }
    final existing = await _eventStore.eventsForRun(runId);
    final completedAttemptIds = existing
        .where(
          (event) =>
              event.entityKind == CockpitRunEventEntityKind.attempt &&
              event.outcome != null &&
              event.attemptId != null,
        )
        .map((event) => event.attemptId!)
        .toSet();
    for (var index = 0; index < caseNodes.length; index += 1) {
      final node = caseNodes[index];
      final testCase = report.cases[index];
      for (final attempt in testCase.attempts) {
        if (!completedAttemptIds.add(attempt.attemptId)) continue;
        await _eventStore.append(
          runId,
          CockpitWorkerEventDraft(
            kind: 'attempt.completed',
            entityKind: CockpitRunEventEntityKind.attempt,
            caseId: testCase.caseId,
            attemptId: attempt.attemptId,
            outcome: attempt.outcome,
            targetId: attempt.targetId,
            requestedPlane: node.compiledCase.testCase.target.plane,
            failure: attempt.failure,
            artifacts: attempt.artifacts,
          ),
        );
      }
      final attemptId = testCase.attempts.lastOrNull?.attemptId;
      final alreadyCompleted = existing.any(
        (event) =>
            event.kind == 'case.completed' &&
            event.entityKind == CockpitRunEventEntityKind.testCase &&
            event.caseId == testCase.caseId &&
            event.attemptId == attemptId &&
            event.outcome == testCase.outcome,
      );
      if (alreadyCompleted) continue;
      await _eventStore.append(
        runId,
        CockpitWorkerEventDraft(
          kind: 'case.completed',
          entityKind: CockpitRunEventEntityKind.testCase,
          caseId: testCase.caseId,
          attemptId: attemptId,
          outcome: testCase.outcome,
          stability: testCase.stability,
          targetId: testCase.targetId,
          requestedPlane: node.compiledCase.testCase.target.plane,
          failure:
              testCase.attempts.lastOrNull?.failure ??
              _outcomeFailure(testCase.outcome, 'Suite case did not pass.'),
        ),
      );
    }
  }

  CockpitTestAttemptReport _suiteRuntimeFailure({
    required String attemptId,
    required int attemptNumber,
    required DateTime startedAt,
    required String targetId,
    required String code,
    required String message,
    required CockpitErrorCategory category,
    required bool retryable,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final finishedAt = _utcNow();
    return CockpitTestAttemptReport(
      attemptId: attemptId,
      number: attemptNumber,
      outcome: switch (category) {
        CockpitErrorCategory.cancelled => CockpitRunOutcome.cancelled,
        CockpitErrorCategory.interrupted => CockpitRunOutcome.interrupted,
        _ => CockpitRunOutcome.blocked,
      },
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: finishedAt.difference(startedAt).inMilliseconds,
      targetId: targetId,
      failure: CockpitFailure(
        primary: CockpitApiError(
          code: code,
          category: category,
          message: message,
          retryable: retryable,
          responsibleLayer: CockpitResponsibleLayer.worker,
          redactedDetails: details,
        ),
      ),
    );
  }

  Future<void> _appendResultEvents(
    CockpitTestAttemptResult result,
    List<CockpitArtifactResource> artifacts, {
    required bool includeAttemptCompletion,
  }) async {
    for (final step in result.steps) {
      await _eventStore.append(
        runId,
        CockpitWorkerEventDraft(
          kind: 'step.${step.status.name}',
          entityKind: CockpitRunEventEntityKind.step,
          caseId: result.context.caseId,
          attemptId: result.context.attemptId,
          stepExecutionId: step.executionId,
          stepStatus: step.status,
          sourceLocation: step.sourceLocation,
          targetId: result.targetId,
          requestedPlane: step.requestedPlane ?? result.requestedPlane,
          actualPlane: step.actualPlane ?? result.actualPlane,
          driverId: step.driverId,
          degradation: step.degradationReason,
          locatorSummary:
              step.locatorResolution?.toJson() ?? const <String, Object?>{},
          failure: step.error == null
              ? null
              : CockpitFailure(primary: _apiError(step.error!)),
          artifacts: artifacts
              .where((artifact) => artifact.stepExecutionId == step.executionId)
              .map((artifact) => artifact.reference)
              .toList(growable: false),
        ),
      );
    }
    if (!includeAttemptCompletion) return;
    final outcome = _runOutcome(result.outcome);
    final failure = result.primaryError == null
        ? null
        : CockpitFailure(
            primary: _apiError(result.primaryError!),
            warnings: <CockpitApiWarning>[
              for (final warning in result.cleanupErrors)
                CockpitApiWarning(
                  stage: CockpitWarningStage.cleanup,
                  error: _apiError(warning),
                ),
            ],
          );
    await _eventStore.append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'attempt.completed',
        entityKind: CockpitRunEventEntityKind.attempt,
        caseId: result.context.caseId,
        attemptId: result.context.attemptId,
        outcome: outcome,
        targetId: result.targetId,
        requestedPlane: result.requestedPlane,
        actualPlane: result.actualPlane,
        failure: failure,
        artifacts: artifacts
            .where((artifact) => artifact.kind == 'attempt.manifest')
            .map((artifact) => artifact.reference)
            .toList(growable: false),
      ),
    );
  }

  CockpitTestAttemptReport _attemptReport(
    CockpitTestAttemptResult result,
    int attemptNumber,
    List<CockpitArtifactResource> artifacts,
  ) {
    final outcome = _runOutcome(result.outcome);
    return CockpitTestAttemptReport(
      attemptId: result.context.attemptId,
      number: attemptNumber,
      outcome: outcome,
      startedAt: result.startedAt,
      finishedAt: result.finishedAt,
      durationMs: result.durationMs,
      targetId: result.targetId,
      failure: result.primaryError == null
          ? null
          : CockpitFailure(
              primary: _apiError(result.primaryError!),
              warnings: <CockpitApiWarning>[
                for (final warning in result.cleanupErrors)
                  CockpitApiWarning(
                    stage: CockpitWarningStage.cleanup,
                    error: _apiError(warning),
                  ),
              ],
            ),
      artifacts: artifacts.map((artifact) => artifact.reference),
    );
  }

  Duration _resourceTtl() {
    final remaining = context.deadline.difference(_utcNow());
    if (remaining < const Duration(seconds: 1)) {
      return const Duration(seconds: 1);
    }
    return remaining > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : remaining;
  }
}

final class _SuiteRowResourceBoundary {
  const _SuiteRowResourceBoundary({required this.scope});

  final CockpitWorkerResourceScope scope;
}

final class CockpitSuiteRowSessionAffinity {
  CockpitSuiteRowSessionAffinity(
    CockpitSuiteExecutionPlan plan, {
    Map<String, String> initialBindings = const <String, String>{},
  }) : _caseNodes = <String, CockpitSuitePlanNode>{
         for (final node in plan.caseNodes) node.nodeId: node,
       },
       _suiteFixtureSetups = <String, CockpitSuitePlanNode>{
         for (final node in plan.nodes)
           if (node.kind == CockpitSuitePlanNodeKind.fixtureSetup &&
               node.caseNodeId == null)
             node.nodeId: node,
       },
       _attemptNodes = plan.attemptNodes,
       _bindings = <String, String>{...initialBindings} {
    final allowed = <String>{
      for (final node in plan.caseNodes)
        _rowBindingKey(node.nodeId, node.targetId),
      for (final node in plan.attemptNodes)
        _rowBindingKey(node.caseNodeId!, node.targetId),
      for (final node in plan.nodes)
        if (node.kind == CockpitSuitePlanNodeKind.fixtureSetup &&
            node.caseNodeId == null)
          _suiteFixtureBindingKey(node.nodeId),
    };
    if (_bindings.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException(
        'Persisted suite session binding does not belong to the plan.',
      );
    }
  }

  final Map<String, CockpitSuitePlanNode> _caseNodes;
  final Map<String, CockpitSuitePlanNode> _suiteFixtureSetups;
  final List<CockpitSuitePlanNode> _attemptNodes;
  final Map<String, String> _bindings;

  String? preferredResourceId(CockpitSuitePlanNode node) {
    final direct = _bindings[_bindingKey(node)];
    if (direct != null || node.caseNodeId == null) return direct;
    final caseNode = _requireCaseNode(node.caseNodeId!);
    final inherited = <String>{};
    for (final dependency in caseNode.dependencies) {
      final setup = _suiteFixtureSetups[dependency];
      if (setup == null || setup.targetId != node.targetId) continue;
      final resourceId = _bindings[_suiteFixtureBindingKey(setup.nodeId)];
      if (resourceId != null) inherited.add(resourceId);
    }
    if (inherited.length > 1) {
      throw CockpitApplicationServiceException(
        code: 'suiteSessionDrift',
        message: 'Suite fixtures require conflicting sessions for a case row.',
        details: <String, Object?>{
          'caseNodeId': caseNode.nodeId,
          'sessionResourceIds': inherited.toList()..sort(),
        },
      );
    }
    return inherited.firstOrNull;
  }

  CockpitSuiteSessionBinding resolveBinding(
    CockpitSuitePlanNode node,
    String sessionResourceId,
  ) {
    final key = _bindingKey(node);
    final expected = preferredResourceId(node);
    if (expected != null && expected != sessionResourceId) {
      throw CockpitApplicationServiceException(
        code: 'suiteSessionDrift',
        message: 'A suite lifecycle resolved to a different session.',
        details: <String, Object?>{
          'nodeId': node.nodeId,
          'expectedSessionResourceId': expected,
          'actualSessionResourceId': sessionResourceId,
        },
      );
    }
    _bindings[key] = sessionResourceId;
    return CockpitSuiteSessionBinding(key: key, resourceId: sessionResourceId);
  }

  String resolveBoundaryResourceId(
    CockpitSuitePlanNode node,
    String sessionResourceId,
  ) => resolveBinding(node, sessionResourceId).resourceId;

  Set<String> release(String caseNodeId) {
    _requireCaseNode(caseNodeId);
    final keys = <String>{
      for (final key in _bindings.keys)
        if (key.startsWith('row:$caseNodeId:')) key,
    };
    releaseBindings(keys);
    return keys;
  }

  Set<String> bindingsReleasedBy(CockpitSuitePlanNode node) {
    if (node.kind != CockpitSuitePlanNodeKind.fixtureTeardown ||
        node.caseNodeId != null) {
      return const <String>{};
    }
    return <String>{_bindingKey(node)};
  }

  void releaseBindings(Iterable<String> keys) {
    for (final key in keys) {
      _bindings.remove(key);
    }
  }

  CockpitSuitePlanNode _requireCaseNode(String caseNodeId) =>
      _caseNodes[caseNodeId] ??
      (throw StateError('Suite row references an unknown case node.'));

  String _bindingKey(CockpitSuitePlanNode node) {
    final caseNodeId = node.caseNodeId;
    if (caseNodeId != null) {
      _requireCaseNode(caseNodeId);
      if (!identical(_caseNodes[caseNodeId], node) &&
          !_attemptNodes.contains(node)) {
        throw StateError('Suite row node does not belong to this plan.');
      }
      return _rowBindingKey(caseNodeId, node.targetId);
    }
    if (node.kind == CockpitSuitePlanNodeKind.fixtureSetup) {
      if (!_suiteFixtureSetups.containsKey(node.nodeId)) {
        throw StateError('Suite fixture setup does not belong to this plan.');
      }
      return _suiteFixtureBindingKey(node.nodeId);
    }
    if (node.kind == CockpitSuitePlanNodeKind.fixtureTeardown &&
        node.cleanupGuardNodeId != null &&
        _suiteFixtureSetups.containsKey(node.cleanupGuardNodeId)) {
      return _suiteFixtureBindingKey(node.cleanupGuardNodeId!);
    }
    throw StateError('Suite node has no durable session binding.');
  }
}

final class CockpitSuiteSessionBinding {
  const CockpitSuiteSessionBinding({
    required this.key,
    required this.resourceId,
  });

  final String key;
  final String resourceId;
}

String _rowBindingKey(String caseNodeId, String? targetId) =>
    'row:$caseNodeId:${targetId ?? 'default'}';

String _suiteFixtureBindingKey(String setupNodeId) => 'fixture:$setupNodeId';

CockpitRunOutcome _runOutcome(CockpitTestOutcome outcome) => switch (outcome) {
  CockpitTestOutcome.passed => CockpitRunOutcome.passed,
  CockpitTestOutcome.failed => CockpitRunOutcome.failed,
  CockpitTestOutcome.blocked => CockpitRunOutcome.blocked,
  CockpitTestOutcome.skipped => CockpitRunOutcome.skipped,
  CockpitTestOutcome.cancelled => CockpitRunOutcome.cancelled,
  CockpitTestOutcome.interrupted => CockpitRunOutcome.interrupted,
  CockpitTestOutcome.internalError => CockpitRunOutcome.internalError,
};

CockpitApiError _apiError(CockpitTestError error) => CockpitApiError(
  code: switch (error.code) {
    CockpitTestErrorCode.assertionFailed => CockpitErrorCode.assertionFailed,
    CockpitTestErrorCode.cancelled => CockpitErrorCode.cancelled,
    CockpitTestErrorCode.driverFailed ||
    CockpitTestErrorCode.hardShutdown => CockpitErrorCode.driverUnavailable,
    CockpitTestErrorCode.evidenceFailed ||
    CockpitTestErrorCode.recordingFailed ||
    CockpitTestErrorCode.bundlePublicationFailed ||
    CockpitTestErrorCode.bundleIntegrityFailed =>
      CockpitErrorCode.evidenceFailed,
    CockpitTestErrorCode.internalFailure => CockpitErrorCode.internalError,
    _ => CockpitErrorCode.invalidRequest,
  },
  category: switch (error.code) {
    CockpitTestErrorCode.assertionFailed => CockpitErrorCategory.assertion,
    CockpitTestErrorCode.cancelled => CockpitErrorCategory.cancelled,
    CockpitTestErrorCode.driverFailed ||
    CockpitTestErrorCode.hardShutdown => CockpitErrorCategory.driver,
    CockpitTestErrorCode.evidenceFailed ||
    CockpitTestErrorCode.recordingFailed ||
    CockpitTestErrorCode.bundlePublicationFailed ||
    CockpitTestErrorCode.bundleIntegrityFailed => CockpitErrorCategory.evidence,
    CockpitTestErrorCode.internalFailure => CockpitErrorCategory.internal,
    _ => CockpitErrorCategory.invalidInput,
  },
  message: error.message,
  retryable: const <CockpitTestErrorCode>{
    CockpitTestErrorCode.timeout,
    CockpitTestErrorCode.hardShutdown,
    CockpitTestErrorCode.driverFailed,
    CockpitTestErrorCode.recordingFailed,
    CockpitTestErrorCode.evidenceFailed,
    CockpitTestErrorCode.bundlePublicationFailed,
    CockpitTestErrorCode.bundleIntegrityFailed,
  }.contains(error.code),
  responsibleLayer:
      error.code == CockpitTestErrorCode.driverFailed ||
          error.code == CockpitTestErrorCode.recordingFailed
      ? CockpitResponsibleLayer.driver
      : CockpitResponsibleLayer.worker,
  redactedDetails: <String, Object?>{
    ...error.details,
    if (error.path != null) 'path': error.path,
    if (error.stepId != null) 'stepId': error.stepId,
    if (error.location != null) 'location': error.location!.toJson(),
  },
);

CockpitFailure? _outcomeFailure(CockpitRunOutcome outcome, String message) {
  if (outcome == CockpitRunOutcome.passed ||
      outcome == CockpitRunOutcome.skipped) {
    return null;
  }
  return CockpitFailure(
    primary: CockpitApiError(
      code: outcome == CockpitRunOutcome.cancelled
          ? CockpitErrorCode.cancelled
          : 'suiteCaseFailed',
      category: outcome == CockpitRunOutcome.cancelled
          ? CockpitErrorCategory.cancelled
          : CockpitErrorCategory.assertion,
      message: message,
      retryable:
          outcome == CockpitRunOutcome.interrupted ||
          outcome == CockpitRunOutcome.internalError,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  );
}

CockpitFailure? _reportFailure(CockpitTestSuiteReport report) {
  if (report.outcome == CockpitRunOutcome.passed) return null;
  return report.failure ??
      report.cases
          .expand((testCase) => testCase.attempts)
          .map((attempt) => attempt.failure)
          .whereType<CockpitFailure>()
          .firstOrNull ??
      _outcomeFailure(report.outcome, 'Suite execution did not pass.');
}

CockpitFailure _suiteFinalizationFailure() => CockpitFailure(
  primary: CockpitApiError(
    code: 'suiteReportPublicationFailed',
    category: CockpitErrorCategory.evidence,
    message: 'Suite report finalization or publication failed.',
    retryable: true,
    responsibleLayer: CockpitResponsibleLayer.worker,
  ),
);

CockpitFailure _suiteExecutionFailure() => CockpitFailure(
  primary: CockpitApiError(
    code: 'suiteExecutionInternalError',
    category: CockpitErrorCategory.internal,
    message: 'Suite scheduling failed internally.',
    retryable: false,
    responsibleLayer: CockpitResponsibleLayer.worker,
  ),
);

CockpitFailure? _mergeFailures(
  CockpitFailure? execution,
  CockpitFailure? finalization,
) {
  if (execution == null) return finalization;
  if (finalization == null) return execution;
  return CockpitFailure(
    primary: execution.primary,
    warnings: <CockpitApiWarning>[
      ...execution.warnings,
      CockpitApiWarning(
        stage: CockpitWarningStage.evidence,
        error: finalization.primary,
      ),
    ],
  );
}

Object? _canonical(Object? value) {
  if (value is List<Object?>) {
    return value.map(_canonical).toList(growable: false);
  }
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  return value;
}
