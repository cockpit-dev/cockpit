import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_suite_execution_plan.dart';

abstract interface class CockpitSuiteAttemptExecutor {
  Future<CockpitTestAttemptReport> execute({
    required CockpitSuitePlanNode node,
    required String runId,
    required String attemptId,
    required int attemptNumber,
    required CockpitSuiteCancellation cancellation,
  });
}

abstract interface class CockpitSuiteCancellation {
  bool get isCancelled;

  Future<void> get whenCancelled;
}

abstract interface class CockpitSuiteSchedulerObserver {
  Future<void> nodeStarted(CockpitSuitePlanNode node, DateTime startedAt);

  Future<void> attemptStarted(
    CockpitSuitePlanNode node,
    String attemptId,
    int attemptNumber,
    DateTime startedAt,
  );

  Future<void> attemptCompleted(
    CockpitSuitePlanNode node,
    CockpitTestAttemptReport attempt,
  );

  Future<void> nodeCompleted(
    CockpitSuitePlanNode node,
    CockpitSuiteNodeExecution execution,
  );
}

final class CockpitSuiteActiveAttempt {
  const CockpitSuiteActiveAttempt({
    required this.attemptId,
    required this.number,
    required this.startedAt,
    required this.targetId,
  });

  final String attemptId;
  final int number;
  final DateTime startedAt;
  final String targetId;

  Map<String, Object?> toJson() => <String, Object?>{
    'attemptId': attemptId,
    'number': number,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'targetId': targetId,
  };

  factory CockpitSuiteActiveAttempt.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected active suite attempt at $path.');
    }
    final json = Map<String, Object?>.from(value);
    if (json.length != 4 ||
        !const <String>{
          'attemptId',
          'number',
          'startedAt',
          'targetId',
        }.every(json.containsKey) ||
        json['attemptId'] is! String ||
        json['number'] is! int ||
        json['targetId'] is! String) {
      throw FormatException('Invalid active suite attempt at $path.');
    }
    final startedAt = json['startedAt'] is String
        ? DateTime.tryParse(json['startedAt']! as String)
        : null;
    final number = json['number']! as int;
    if (startedAt == null ||
        !startedAt.isUtc ||
        number < 1 ||
        (json['attemptId']! as String).isEmpty ||
        (json['targetId']! as String).isEmpty) {
      throw FormatException('Invalid active suite attempt at $path.');
    }
    return CockpitSuiteActiveAttempt(
      attemptId: json['attemptId']! as String,
      number: number,
      startedAt: startedAt,
      targetId: json['targetId']! as String,
    );
  }
}

final class CockpitSuiteNodeProgress {
  CockpitSuiteNodeProgress({
    required this.nodeId,
    required this.entryId,
    required this.kind,
    required this.startedAt,
    required Iterable<CockpitTestAttemptReport> completedAttempts,
    required this.activeAttempt,
  }) : completedAttempts = List<CockpitTestAttemptReport>.unmodifiable(
         completedAttempts,
       ) {
    for (var index = 0; index < this.completedAttempts.length; index += 1) {
      if (this.completedAttempts[index].number != index + 1) {
        throw const FormatException(
          'Persisted suite attempts must be contiguous.',
        );
      }
    }
    if (activeAttempt != null &&
        activeAttempt!.number != this.completedAttempts.length + 1) {
      throw const FormatException('Active suite attempt is not contiguous.');
    }
  }

  final String nodeId;
  final String entryId;
  final CockpitSuitePlanNodeKind kind;
  final DateTime startedAt;
  final List<CockpitTestAttemptReport> completedAttempts;
  final CockpitSuiteActiveAttempt? activeAttempt;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    'entryId': entryId,
    'kind': kind.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'completedAttempts': completedAttempts
        .map((attempt) => attempt.toJson())
        .toList(),
    if (activeAttempt != null) 'activeAttempt': activeAttempt!.toJson(),
  };

  factory CockpitSuiteNodeProgress.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected suite node progress at $path.');
    }
    final json = Map<String, Object?>.from(value);
    const allowed = <String>{
      'nodeId',
      'entryId',
      'kind',
      'startedAt',
      'completedAttempts',
      'activeAttempt',
    };
    if (json.keys.any((key) => !allowed.contains(key)) ||
        !const <String>{
          'nodeId',
          'entryId',
          'kind',
          'startedAt',
          'completedAttempts',
        }.every(json.containsKey) ||
        json['nodeId'] is! String ||
        json['entryId'] is! String ||
        json['kind'] is! String ||
        json['completedAttempts'] is! List<Object?>) {
      throw FormatException('Invalid suite node progress at $path.');
    }
    final kind = CockpitSuitePlanNodeKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    final startedAt = json['startedAt'] is String
        ? DateTime.tryParse(json['startedAt']! as String)
        : null;
    if (kind == null ||
        startedAt == null ||
        !startedAt.isUtc ||
        (json['nodeId']! as String).isEmpty ||
        (json['entryId']! as String).isEmpty) {
      throw FormatException('Invalid suite node progress at $path.');
    }
    final attempts = json['completedAttempts']! as List<Object?>;
    return CockpitSuiteNodeProgress(
      nodeId: json['nodeId']! as String,
      entryId: json['entryId']! as String,
      kind: kind,
      startedAt: startedAt,
      completedAttempts: <CockpitTestAttemptReport>[
        for (var index = 0; index < attempts.length; index += 1)
          CockpitTestAttemptReport.fromJson(
            attempts[index],
            path: '$path.completedAttempts[$index]',
          ),
      ],
      activeAttempt: json['activeAttempt'] == null
          ? null
          : CockpitSuiteActiveAttempt.fromJson(
              json['activeAttempt'],
              path: '$path.activeAttempt',
            ),
    );
  }
}

final class CockpitSuiteNodeExecution {
  CockpitSuiteNodeExecution({
    required this.nodeId,
    required this.entryId,
    required this.kind,
    required this.outcome,
    required this.stability,
    required Iterable<CockpitTestAttemptReport> attempts,
    required this.startedAt,
    required this.finishedAt,
  }) : attempts = List<CockpitTestAttemptReport>.unmodifiable(attempts);

  final String nodeId;
  final String entryId;
  final CockpitSuitePlanNodeKind kind;
  final CockpitRunOutcome outcome;
  final CockpitRunStability stability;
  final List<CockpitTestAttemptReport> attempts;
  final DateTime? startedAt;
  final DateTime finishedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    'entryId': entryId,
    'kind': kind.name,
    'outcome': outcome.name,
    'stability': stability.name,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
  };

  factory CockpitSuiteNodeExecution.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected suite node execution at $path.');
    }
    final json = Map<String, Object?>.from(value);
    const fields = <String>{
      'nodeId',
      'entryId',
      'kind',
      'outcome',
      'stability',
      'attempts',
      'startedAt',
      'finishedAt',
    };
    if (json.keys.any((key) => !fields.contains(key)) ||
        !const <String>{
          'nodeId',
          'entryId',
          'kind',
          'outcome',
          'stability',
          'attempts',
          'finishedAt',
        }.every(json.containsKey) ||
        json['attempts'] is! List<Object?>) {
      throw FormatException('Invalid suite node execution at $path.');
    }
    T parseEnum<T extends Enum>(Object? raw, List<T> values, String field) {
      if (raw is! String) {
        throw FormatException('Invalid $field at $path.$field.');
      }
      return values.where((value) => value.name == raw).singleOrNull ??
          (throw FormatException('Invalid $field at $path.$field.'));
    }

    DateTime parseTime(Object? raw, String field) {
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      if (parsed == null || !parsed.isUtc) {
        throw FormatException('Invalid timestamp at $path.$field.');
      }
      return parsed;
    }

    final rawAttempts = json['attempts']! as List<Object?>;
    return CockpitSuiteNodeExecution(
      nodeId: json['nodeId']! as String,
      entryId: json['entryId']! as String,
      kind: parseEnum(json['kind'], CockpitSuitePlanNodeKind.values, 'kind'),
      outcome: parseEnum(json['outcome'], CockpitRunOutcome.values, 'outcome'),
      stability: parseEnum(
        json['stability'],
        CockpitRunStability.values,
        'stability',
      ),
      attempts: <CockpitTestAttemptReport>[
        for (var index = 0; index < rawAttempts.length; index += 1)
          CockpitTestAttemptReport.fromJson(
            rawAttempts[index],
            path: '$path.attempts[$index]',
          ),
      ],
      startedAt: json['startedAt'] == null
          ? null
          : parseTime(json['startedAt'], 'startedAt'),
      finishedAt: parseTime(json['finishedAt'], 'finishedAt'),
    );
  }
}

final class CockpitSuiteScheduleResult {
  CockpitSuiteScheduleResult({
    required this.runId,
    required Iterable<CockpitSuiteNodeExecution> executions,
  }) : executions = List<CockpitSuiteNodeExecution>.unmodifiable(executions);

  final String runId;
  final List<CockpitSuiteNodeExecution> executions;

  CockpitSuiteNodeExecution executionFor(String nodeId) =>
      executions.singleWhere((execution) => execution.nodeId == nodeId);
}

final class CockpitSuiteScheduler {
  CockpitSuiteScheduler({
    required CockpitSuiteAttemptExecutor executor,
    CockpitSuiteSchedulerObserver? observer,
    DateTime Function()? utcNow,
    Future<void> Function(Duration)? delay,
  }) : _executor = executor,
       _observer = observer,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _delay = delay ?? Future<void>.delayed;

  final CockpitSuiteAttemptExecutor _executor;
  final CockpitSuiteSchedulerObserver? _observer;
  final DateTime Function() _utcNow;
  final Future<void> Function(Duration) _delay;

  Future<CockpitSuiteScheduleResult> run({
    required String runId,
    required CockpitSuiteExecutionPlan plan,
    required CockpitSuiteCancellation cancellation,
    Iterable<CockpitSuiteNodeExecution> initialExecutions =
        const <CockpitSuiteNodeExecution>[],
    Iterable<CockpitSuiteNodeProgress> initialProgress =
        const <CockpitSuiteNodeProgress>[],
  }) async {
    final nodes = <String, CockpitSuitePlanNode>{
      for (final node in plan.nodes) node.nodeId: node,
    };
    final completed = <String, CockpitSuiteNodeExecution>{};
    for (final execution in initialExecutions) {
      final node = nodes[execution.nodeId];
      if (node == null ||
          execution.entryId != node.entryId ||
          execution.kind != node.kind ||
          completed.putIfAbsent(execution.nodeId, () => execution) !=
              execution) {
        throw const FormatException('Persisted suite execution is invalid.');
      }
    }
    final progress = <String, CockpitSuiteNodeProgress>{};
    for (final checkpoint in initialProgress) {
      final node = nodes[checkpoint.nodeId];
      if (node == null ||
          checkpoint.entryId != node.entryId ||
          checkpoint.kind != node.kind ||
          completed.containsKey(checkpoint.nodeId) ||
          progress.putIfAbsent(checkpoint.nodeId, () => checkpoint) !=
              checkpoint ||
          checkpoint.completedAttempts.length > node.retry.maxAttempts ||
          (checkpoint.activeAttempt != null &&
              checkpoint.activeAttempt!.number > node.retry.maxAttempts)) {
        throw const FormatException('Persisted suite progress is invalid.');
      }
    }
    final pending = <String, CockpitSuitePlanNode>{
      for (final node in plan.nodes)
        if (!completed.containsKey(node.nodeId)) node.nodeId: node,
    };
    final running = <String, Future<CockpitSuiteNodeExecution>>{};
    var failFast =
        plan.suite.execution.failFast &&
        completed.values.any(
          (execution) =>
              execution.kind == CockpitSuitePlanNodeKind.testCase &&
              execution.outcome != CockpitRunOutcome.passed,
        );

    while (pending.isNotEmpty || running.isNotEmpty) {
      final ready =
          pending.values
              .where((node) => node.dependencies.every(completed.containsKey))
              .toList()
            ..sort((left, right) => left.nodeId.compareTo(right.nodeId));
      var completedWithoutRunning = false;
      for (final node in ready) {
        if (running.length >= plan.suite.execution.maxConcurrency) break;
        pending.remove(node.nodeId);
        final dependencyFailed = node.dependencies.any(
          (id) => completed[id]!.outcome != CockpitRunOutcome.passed,
        );
        final skipOutcome = !node.selected
            ? CockpitRunOutcome.skipped
            : cancellation.isCancelled && !node.alwaysRun
            ? CockpitRunOutcome.cancelled
            : failFast && !node.alwaysRun
            ? CockpitRunOutcome.skipped
            : dependencyFailed && !node.alwaysRun
            ? CockpitRunOutcome.blocked
            : node.cleanupGuardNodeId != null &&
                  completed[node.cleanupGuardNodeId]!.attempts.isEmpty
            ? CockpitRunOutcome.skipped
            : null;
        if (skipOutcome != null) {
          final inheritedAttempt =
              skipOutcome == CockpitRunOutcome.blocked &&
                  node.kind == CockpitSuitePlanNodeKind.testCase
              ? _blockedAttempt(node, nodes, completed)
              : null;
          final skipped = _withoutAttempt(
            node,
            skipOutcome,
            attempt: inheritedAttempt,
          );
          await _observer?.nodeCompleted(node, skipped);
          completed[node.nodeId] = skipped;
          if (plan.suite.execution.failFast &&
              node.kind == CockpitSuitePlanNodeKind.testCase &&
              skipped.outcome != CockpitRunOutcome.passed) {
            failFast = true;
          }
          completedWithoutRunning = true;
          continue;
        }
        running[node.nodeId] = _executeNode(
          runId: runId,
          node: node,
          cancellation: cancellation,
          progress: progress.remove(node.nodeId),
        );
      }

      if (running.isEmpty) {
        if (pending.isNotEmpty) {
          if (completedWithoutRunning) continue;
          throw StateError(
            'Suite scheduler made no progress on an acyclic DAG.',
          );
        }
        break;
      }
      final execution = await Future.any(running.values);
      running.remove(execution.nodeId);
      completed[execution.nodeId] = execution;
      if (plan.suite.execution.failFast &&
          execution.kind == CockpitSuitePlanNodeKind.testCase &&
          execution.outcome != CockpitRunOutcome.passed) {
        failFast = true;
      }
    }
    return CockpitSuiteScheduleResult(
      runId: runId,
      executions: plan.nodes.map((node) => completed[node.nodeId]!),
    );
  }

  Future<CockpitSuiteNodeExecution> _executeNode({
    required String runId,
    required CockpitSuitePlanNode node,
    required CockpitSuiteCancellation cancellation,
    CockpitSuiteNodeProgress? progress,
  }) async {
    final startedAt = progress?.startedAt ?? _utcNow();
    if (progress == null) await _observer?.nodeStarted(node, startedAt);
    final attempts = <CockpitTestAttemptReport>[
      ...?progress?.completedAttempts,
    ];
    final attemptCancellation = node.alwaysRun
        ? const _NeverCancelled()
        : cancellation;
    if (progress?.activeAttempt case final active?) {
      final now = _utcNow();
      final finishedAt = now.isBefore(active.startedAt)
          ? active.startedAt
          : now;
      final interrupted = CockpitTestAttemptReport(
        attemptId: active.attemptId,
        number: active.number,
        outcome: CockpitRunOutcome.interrupted,
        startedAt: active.startedAt,
        finishedAt: finishedAt,
        durationMs: finishedAt.difference(active.startedAt).inMilliseconds,
        targetId: active.targetId,
        failure: CockpitFailure(
          primary: CockpitApiError(
            code: CockpitErrorCode.interrupted,
            category: CockpitErrorCategory.interrupted,
            message: 'Suite attempt was interrupted by worker termination.',
            retryable: true,
            responsibleLayer: CockpitResponsibleLayer.worker,
          ),
        ),
      );
      attempts.add(interrupted);
      await _observer?.attemptCompleted(node, interrupted);
    }
    if (attempts.isNotEmpty) {
      final last = attempts.last;
      if (last.outcome == CockpitRunOutcome.passed ||
          last.number >= node.retry.maxAttempts ||
          !_shouldRetry(last, node.retry)) {
        return _complete(
          node,
          last.outcome,
          last.outcome == CockpitRunOutcome.passed && attempts.length > 1
              ? CockpitRunStability.flaky
              : CockpitRunStability.stable,
          attempts,
          startedAt,
        );
      }
      if (node.retry.delayMs > 0) {
        await _retryDelay(
          Duration(milliseconds: node.retry.delayMs),
          attemptCancellation,
        );
      }
    }
    for (
      var number = attempts.length + 1;
      number <= node.retry.maxAttempts;
      number += 1
    ) {
      if (attemptCancellation.isCancelled) {
        return _complete(
          node,
          CockpitRunOutcome.cancelled,
          CockpitRunStability.unknown,
          attempts,
          startedAt,
        );
      }
      final attemptId = 'attempt_${node.nodeId}_$number';
      final attemptStartedAt = _utcNow();
      await _observer?.attemptStarted(
        node,
        attemptId,
        number,
        attemptStartedAt,
      );
      CockpitTestAttemptReport attempt;
      try {
        attempt = await _executor.execute(
          node: node,
          runId: runId,
          attemptId: attemptId,
          attemptNumber: number,
          cancellation: attemptCancellation,
        );
      } on Object {
        final failedAt = _utcNow();
        attempt = CockpitTestAttemptReport(
          attemptId: attemptId,
          number: number,
          outcome: CockpitRunOutcome.internalError,
          startedAt: attemptStartedAt,
          finishedAt: failedAt,
          durationMs: failedAt.difference(attemptStartedAt).inMilliseconds,
          targetId: node.targetId ?? 'unassigned',
          failure: CockpitFailure(
            primary: CockpitApiError(
              code: CockpitErrorCode.internalError,
              category: CockpitErrorCategory.internal,
              message: 'Suite attempt failed internally.',
              retryable: number < node.retry.maxAttempts,
              responsibleLayer: CockpitResponsibleLayer.worker,
            ),
          ),
        );
      }
      attempts.add(attempt);
      await _observer?.attemptCompleted(node, attempt);
      if (attempt.outcome == CockpitRunOutcome.passed) {
        return _complete(
          node,
          attempt.outcome,
          attempts.length > 1
              ? CockpitRunStability.flaky
              : CockpitRunStability.stable,
          attempts,
          startedAt,
        );
      }
      if (number >= node.retry.maxAttempts ||
          !_shouldRetry(attempt, node.retry)) {
        return _complete(
          node,
          attempt.outcome,
          CockpitRunStability.stable,
          attempts,
          startedAt,
        );
      }
      if (node.retry.delayMs > 0) {
        await _retryDelay(
          Duration(milliseconds: node.retry.delayMs),
          attemptCancellation,
        );
      }
    }
    throw StateError('Suite retry loop terminated without a result.');
  }

  bool _shouldRetry(
    CockpitTestAttemptReport attempt,
    CockpitTestSuiteRetryPolicy policy,
  ) {
    if (attempt.failure?.primary.retryable == false) return false;
    final reason = switch (attempt.outcome) {
      CockpitRunOutcome.blocked => CockpitTestSuiteRetryReason.blocked,
      CockpitRunOutcome.interrupted => CockpitTestSuiteRetryReason.interrupted,
      CockpitRunOutcome.internalError =>
        CockpitTestSuiteRetryReason.internalError,
      _ => null,
    };
    return reason != null && policy.retryOn.contains(reason);
  }

  Future<void> _retryDelay(
    Duration duration,
    CockpitSuiteCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) return;
    await Future.any<void>(<Future<void>>[
      _delay(duration),
      cancellation.whenCancelled,
    ]);
  }

  CockpitSuiteNodeExecution _withoutAttempt(
    CockpitSuitePlanNode node,
    CockpitRunOutcome outcome, {
    CockpitTestAttemptReport? attempt,
  }) => CockpitSuiteNodeExecution(
    nodeId: node.nodeId,
    entryId: node.entryId,
    kind: node.kind,
    outcome: outcome,
    stability: CockpitRunStability.unknown,
    attempts: <CockpitTestAttemptReport>[?attempt],
    startedAt: null,
    finishedAt: _utcNow(),
  );

  CockpitTestAttemptReport _blockedAttempt(
    CockpitSuitePlanNode node,
    Map<String, CockpitSuitePlanNode> nodes,
    Map<String, CockpitSuiteNodeExecution> completed,
  ) {
    CockpitTestAttemptReport? source;
    final visited = <String>{};
    void visit(String nodeId) {
      if (source != null || !visited.add(nodeId)) return;
      final execution = completed[nodeId];
      if (execution == null) return;
      source = execution.attempts.reversed
          .where((attempt) => attempt.failure != null)
          .firstOrNull;
      if (source != null) return;
      final dependencies = nodes[nodeId]!.dependencies.toList()..sort();
      for (final dependency in dependencies) {
        visit(dependency);
      }
    }

    final dependencies = node.dependencies.toList()..sort();
    for (final dependency in dependencies) {
      visit(dependency);
    }
    final timestamp = _utcNow();
    return CockpitTestAttemptReport(
      attemptId: 'attempt_${node.nodeId}_blocked',
      number: 1,
      outcome: CockpitRunOutcome.blocked,
      startedAt: timestamp,
      finishedAt: timestamp,
      durationMs: 0,
      targetId: source?.targetId ?? node.targetId ?? 'unassigned',
      failure:
          source?.failure ??
          CockpitFailure(
            primary: CockpitApiError(
              code: 'suiteDependencyFailed',
              category: CockpitErrorCategory.environment,
              message: 'A suite dependency did not complete successfully.',
              retryable: false,
              responsibleLayer: CockpitResponsibleLayer.worker,
            ),
          ),
    );
  }

  Future<CockpitSuiteNodeExecution> _complete(
    CockpitSuitePlanNode node,
    CockpitRunOutcome outcome,
    CockpitRunStability stability,
    List<CockpitTestAttemptReport> attempts,
    DateTime startedAt,
  ) async {
    final execution = CockpitSuiteNodeExecution(
      nodeId: node.nodeId,
      entryId: node.entryId,
      kind: node.kind,
      outcome: outcome,
      stability: stability,
      attempts: attempts,
      startedAt: startedAt,
      finishedAt: _utcNow(),
    );
    await _observer?.nodeCompleted(node, execution);
    return execution;
  }
}

final class _NeverCancelled implements CockpitSuiteCancellation {
  const _NeverCancelled();

  static final Completer<void> _never = Completer<void>();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never.future;
}
