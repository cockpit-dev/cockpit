import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../suite/cockpit_suite_execution_plan.dart';
import '../suite/cockpit_suite_scheduler.dart';
import 'cockpit_worker_value_reader.dart';

final class CockpitWorkerSuiteReservation {
  const CockpitWorkerSuiteReservation({
    required this.runId,
    required this.startedAt,
    required this.executions,
    required this.progress,
    required this.sessionBindings,
    required this.completedOutput,
  });

  final String runId;
  final DateTime startedAt;
  final List<CockpitSuiteNodeExecution> executions;
  final List<CockpitSuiteNodeProgress> progress;
  final Map<String, String> sessionBindings;
  final Map<String, Object?>? completedOutput;

  bool get completed => completedOutput != null;
}

final class CockpitWorkerSuiteRunStore {
  CockpitWorkerSuiteRunStore({
    required this.workspaceId,
    required String path,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    this.maximumRuns = 10000,
  }) : _store = CockpitLockedJsonStore<Map<String, Object?>>(
         path: path,
         codec: const _SuiteRunCodec(),
         createInitial: () => <String, Object?>{
           'schemaVersion': 'cockpit.worker.suite-runs/v3',
           'workspaceId': workspaceId,
           'runs': <String, Object?>{},
         },
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
         maximumBytes: 64 * 1024 * 1024,
       ) {
    workerId(workspaceId, r'$.workspaceId');
    if (maximumRuns < 1 || maximumRuns > 100000) {
      throw ArgumentError.value(maximumRuns, 'maximumRuns');
    }
  }

  final String workspaceId;
  final int maximumRuns;
  final CockpitLockedJsonStore<Map<String, Object?>> _store;

  Future<CockpitWorkerSuiteReservation> read(String runId) async {
    workerId(runId, r'$.runId');
    final state = _state(await _store.read());
    return _run(state.runs[runId], runId).reservation;
  }

  Future<CockpitWorkerSuiteReservation> reserve({
    required String runId,
    required String idempotencyKey,
    required String requestFingerprint,
    required String suiteId,
    required String sourceSha256,
    required DateTime startedAt,
  }) => _store.transact((raw) {
    final state = _state(raw);
    final runs = state.runs;
    final existingRaw = runs[runId];
    if (existingRaw != null) {
      final existing = _run(existingRaw, runId);
      if (existing.idempotencyKey != idempotencyKey ||
          existing.requestFingerprint != requestFingerprint ||
          existing.suiteId != suiteId ||
          existing.sourceSha256 != sourceSha256) {
        throw const FormatException('Suite run idempotency conflict.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, existing.reservation);
    }
    if (runs.length >= maximumRuns) {
      throw const FormatException('Suite run store bound was exceeded.');
    }
    final run = _SuiteRunState(
      runId: runId,
      idempotencyKey: idempotencyKey,
      requestFingerprint: requestFingerprint,
      suiteId: suiteId,
      sourceSha256: sourceSha256,
      startedAt: startedAt,
      executions: const <CockpitSuiteNodeExecution>[],
      progress: const <CockpitSuiteNodeProgress>[],
      sessionBindings: const <String, String>{},
      completedOutput: null,
    );
    runs[runId] = run.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), run.reservation);
  });

  Future<void> recordNodeStarted({
    required String runId,
    required String nodeId,
    required String entryId,
    required CockpitSuitePlanNodeKind kind,
    required DateTime startedAt,
  }) => _store.transact<void>((raw) {
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    _requireMutable(run);
    if (run.executions.any((item) => item.nodeId == nodeId)) {
      throw const FormatException('Completed suite node cannot be restarted.');
    }
    final existing = run.progress
        .where((item) => item.nodeId == nodeId)
        .singleOrNull;
    final progress = CockpitSuiteNodeProgress(
      nodeId: nodeId,
      entryId: entryId,
      kind: kind,
      startedAt: startedAt.toUtc(),
      completedAttempts: const <CockpitTestAttemptReport>[],
      activeAttempt: null,
    );
    if (existing != null) {
      if (_canonical(existing.toJson()) != _canonical(progress.toJson())) {
        throw const FormatException('Suite node progress conflicts.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, null);
    }
    final updated = run.copyWith(
      progress: <CockpitSuiteNodeProgress>[...run.progress, progress],
    );
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  Future<void> recordAttemptStarted({
    required String runId,
    required String nodeId,
    required String attemptId,
    required int attemptNumber,
    required DateTime startedAt,
    required String targetId,
  }) => _store.transact<void>((raw) {
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    _requireMutable(run);
    final index = run.progress.indexWhere((item) => item.nodeId == nodeId);
    if (index < 0) {
      throw const FormatException('Suite node was not started.');
    }
    final current = run.progress[index];
    final active = CockpitSuiteActiveAttempt(
      attemptId: attemptId,
      number: attemptNumber,
      startedAt: startedAt.toUtc(),
      targetId: targetId,
    );
    if (current.activeAttempt case final existing?) {
      if (_canonical(existing.toJson()) != _canonical(active.toJson())) {
        throw const FormatException('Active suite attempt conflicts.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, null);
    }
    if (attemptNumber != current.completedAttempts.length + 1) {
      throw const FormatException('Suite attempt sequence is invalid.');
    }
    final progress = <CockpitSuiteNodeProgress>[...run.progress];
    progress[index] = CockpitSuiteNodeProgress(
      nodeId: current.nodeId,
      entryId: current.entryId,
      kind: current.kind,
      startedAt: current.startedAt,
      completedAttempts: current.completedAttempts,
      activeAttempt: active,
    );
    final updated = run.copyWith(progress: progress);
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  Future<void> recordAttemptCompleted({
    required String runId,
    required String nodeId,
    required CockpitTestAttemptReport attempt,
  }) => _store.transact<void>((raw) {
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    _requireMutable(run);
    final index = run.progress.indexWhere((item) => item.nodeId == nodeId);
    if (index < 0) {
      throw const FormatException('Suite node was not started.');
    }
    final current = run.progress[index];
    final existing = current.completedAttempts
        .where((item) => item.attemptId == attempt.attemptId)
        .singleOrNull;
    if (existing != null) {
      if (_canonical(existing.toJson()) != _canonical(attempt.toJson())) {
        throw const FormatException('Completed suite attempt conflicts.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, null);
    }
    final active = current.activeAttempt;
    if (active == null ||
        active.attemptId != attempt.attemptId ||
        active.number != attempt.number) {
      throw const FormatException('Suite attempt completion is inconsistent.');
    }
    final progress = <CockpitSuiteNodeProgress>[...run.progress];
    progress[index] = CockpitSuiteNodeProgress(
      nodeId: current.nodeId,
      entryId: current.entryId,
      kind: current.kind,
      startedAt: current.startedAt,
      completedAttempts: <CockpitTestAttemptReport>[
        ...current.completedAttempts,
        attempt,
      ],
      activeAttempt: null,
    );
    final updated = run.copyWith(progress: progress);
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  Future<void> bindSession({
    required String runId,
    required String bindingKey,
    required String sessionResourceId,
  }) => _store.transact<void>((raw) {
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    _requireMutable(run);
    final existing = run.sessionBindings[bindingKey];
    if (existing != null) {
      if (existing != sessionResourceId) {
        throw const FormatException('Suite session binding conflicts.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, null);
    }
    final updated = run.copyWith(
      sessionBindings: <String, String>{
        ...run.sessionBindings,
        bindingKey: sessionResourceId,
      },
    );
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  Future<void> releaseSessionBindings({
    required String runId,
    required Iterable<String> bindingKeys,
  }) => _store.transact<void>((raw) {
    final keys = bindingKeys.toSet();
    if (keys.isEmpty) return CockpitLockedJsonUpdate.readOnly(raw, null);
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    _requireMutable(run);
    final bindings = <String, String>{...run.sessionBindings};
    var changed = false;
    for (final key in keys) {
      changed = bindings.remove(key) != null || changed;
    }
    if (!changed) return CockpitLockedJsonUpdate.readOnly(raw, null);
    final updated = run.copyWith(sessionBindings: bindings);
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  Future<void> recordExecution({
    required String runId,
    required CockpitSuiteNodeExecution execution,
    Iterable<String> releasedSessionBindingKeys = const <String>[],
  }) => _store.transact<void>((raw) {
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    if (run.completedOutput != null) {
      throw const FormatException('Completed suite run is immutable.');
    }
    final existing = run.executions
        .where((item) => item.nodeId == execution.nodeId)
        .singleOrNull;
    if (existing != null) {
      if (_canonical(existing.toJson()) != _canonical(execution.toJson())) {
        throw const FormatException('Suite node execution conflicts.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, null);
    }
    final releasedKeys = releasedSessionBindingKeys.toSet();
    final updated = run.copyWith(
      executions: <CockpitSuiteNodeExecution>[...run.executions, execution],
      progress: run.progress
          .where((item) => item.nodeId != execution.nodeId)
          .toList(growable: false),
      sessionBindings: <String, String>{
        for (final entry in run.sessionBindings.entries)
          if (!releasedKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
    final progress = run.progress
        .where((item) => item.nodeId == execution.nodeId)
        .singleOrNull;
    if (progress != null &&
        _canonical(
              progress.completedAttempts.map((item) => item.toJson()).toList(),
            ) !=
            _canonical(
              execution.attempts.map((item) => item.toJson()).toList(),
            )) {
      throw const FormatException('Suite node execution loses progress.');
    }
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  Future<void> complete({
    required String runId,
    required Map<String, Object?> output,
  }) => _store.transact<void>((raw) {
    final state = _state(raw);
    final run = _run(state.runs[runId], runId);
    if (run.completedOutput != null) {
      if (_canonical(run.completedOutput) != _canonical(output)) {
        throw const FormatException('Completed suite output is immutable.');
      }
      return CockpitLockedJsonUpdate.readOnly(raw, null);
    }
    if (run.progress.isNotEmpty) {
      throw const FormatException('Suite run has unfinished node progress.');
    }
    final updated = run.copyWith(
      completedOutput: output,
      sessionBindings: const <String, String>{},
    );
    state.runs[runId] = updated.toJson();
    return CockpitLockedJsonUpdate.write(state.toJson(), null);
  });

  _SuiteStoreState _state(Map<String, Object?> raw) {
    final json = workerObject(raw, r'$');
    workerKeys(
      json,
      const <String>{'schemaVersion', 'workspaceId', 'runs'},
      r'$',
      required: const <String>{'schemaVersion', 'workspaceId', 'runs'},
    );
    if (json['schemaVersion'] != 'cockpit.worker.suite-runs/v3' ||
        json['workspaceId'] != workspaceId) {
      throw const FormatException('Suite run store identity is invalid.');
    }
    final runs = workerObject(json['runs'], r'$.runs');
    if (runs.length > maximumRuns) {
      throw const FormatException('Suite run store bound was exceeded.');
    }
    return _SuiteStoreState(workspaceId: workspaceId, runs: runs);
  }

  _SuiteRunState _run(Object? value, String runId) {
    if (value == null) throw const FormatException('Suite run was not found.');
    final run = _SuiteRunState.fromJson(value, runId: runId);
    if (run.runId != runId) {
      throw const FormatException('Suite run identity is invalid.');
    }
    return run;
  }
}

void _requireMutable(_SuiteRunState run) {
  if (run.completedOutput != null) {
    throw const FormatException('Completed suite run is immutable.');
  }
}

final class _SuiteStoreState {
  const _SuiteStoreState({required this.workspaceId, required this.runs});

  final String workspaceId;
  final Map<String, Object?> runs;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 'cockpit.worker.suite-runs/v3',
    'workspaceId': workspaceId,
    'runs': runs,
  };
}

final class _SuiteRunState {
  const _SuiteRunState({
    required this.runId,
    required this.idempotencyKey,
    required this.requestFingerprint,
    required this.suiteId,
    required this.sourceSha256,
    required this.startedAt,
    required this.executions,
    required this.progress,
    required this.sessionBindings,
    required this.completedOutput,
  });

  final String runId;
  final String idempotencyKey;
  final String requestFingerprint;
  final String suiteId;
  final String sourceSha256;
  final DateTime startedAt;
  final List<CockpitSuiteNodeExecution> executions;
  final List<CockpitSuiteNodeProgress> progress;
  final Map<String, String> sessionBindings;
  final Map<String, Object?>? completedOutput;

  CockpitWorkerSuiteReservation get reservation =>
      CockpitWorkerSuiteReservation(
        runId: runId,
        startedAt: startedAt,
        executions: executions,
        progress: progress,
        sessionBindings: sessionBindings,
        completedOutput: completedOutput,
      );

  _SuiteRunState copyWith({
    List<CockpitSuiteNodeExecution>? executions,
    List<CockpitSuiteNodeProgress>? progress,
    Map<String, String>? sessionBindings,
    Map<String, Object?>? completedOutput,
  }) => _SuiteRunState(
    runId: runId,
    idempotencyKey: idempotencyKey,
    requestFingerprint: requestFingerprint,
    suiteId: suiteId,
    sourceSha256: sourceSha256,
    startedAt: startedAt,
    executions: executions ?? this.executions,
    progress: progress ?? this.progress,
    sessionBindings: sessionBindings ?? this.sessionBindings,
    completedOutput: completedOutput ?? this.completedOutput,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'idempotencyKey': idempotencyKey,
    'requestFingerprint': requestFingerprint,
    'suiteId': suiteId,
    'sourceSha256': sourceSha256,
    'startedAt': startedAt.toIso8601String(),
    'executions': executions.map((item) => item.toJson()).toList(),
    'progress': progress.map((item) => item.toJson()).toList(),
    'sessionBindings': sessionBindings,
    if (completedOutput != null) 'completedOutput': completedOutput,
  };

  factory _SuiteRunState.fromJson(Object? value, {required String runId}) {
    final json = workerObject(value, '\$.runs.$runId');
    workerKeys(
      json,
      const <String>{
        'runId',
        'idempotencyKey',
        'requestFingerprint',
        'suiteId',
        'sourceSha256',
        'startedAt',
        'executions',
        'progress',
        'sessionBindings',
        'completedOutput',
      },
      '\$.runs.$runId',
      required: const <String>{
        'runId',
        'idempotencyKey',
        'requestFingerprint',
        'suiteId',
        'sourceSha256',
        'startedAt',
        'executions',
        'progress',
        'sessionBindings',
      },
    );
    final rawExecutions = workerList(
      json['executions'],
      '\$.runs.$runId.executions',
    );
    final rawProgress = workerList(json['progress'], '\$.runs.$runId.progress');
    final rawBindings = workerObject(
      json['sessionBindings'],
      '\$.runs.$runId.sessionBindings',
    );
    final output = json['completedOutput'] == null
        ? null
        : workerJsonObject(
            json['completedOutput'],
            '\$.runs.$runId.completedOutput',
          );
    return _SuiteRunState(
      runId: workerId(json['runId'], '\$.runs.$runId.runId'),
      idempotencyKey: workerString(
        json['idempotencyKey'],
        '\$.runs.$runId.idempotencyKey',
        maximum: 256,
      ),
      requestFingerprint: _sha(
        json['requestFingerprint'],
        '\$.runs.$runId.requestFingerprint',
      ),
      suiteId: workerId(json['suiteId'], '\$.runs.$runId.suiteId'),
      sourceSha256: _sha(json['sourceSha256'], '\$.runs.$runId.sourceSha256'),
      startedAt: workerUtcDateTime(
        json['startedAt'],
        '\$.runs.$runId.startedAt',
      ),
      executions: <CockpitSuiteNodeExecution>[
        for (var index = 0; index < rawExecutions.length; index += 1)
          CockpitSuiteNodeExecution.fromJson(
            rawExecutions[index],
            path: '\$.runs.$runId.executions[$index]',
          ),
      ],
      progress: <CockpitSuiteNodeProgress>[
        for (var index = 0; index < rawProgress.length; index += 1)
          CockpitSuiteNodeProgress.fromJson(
            rawProgress[index],
            path: '\$.runs.$runId.progress[$index]',
          ),
      ],
      sessionBindings: <String, String>{
        for (final entry in rawBindings.entries)
          workerString(
            entry.key,
            '\$.runs.$runId.sessionBindings.key',
            minimum: 1,
            maximum: 512,
          ): workerId(
            entry.value,
            '\$.runs.$runId.sessionBindings.${entry.key}',
          ),
      },
      completedOutput: output,
    );
  }
}

String _sha(Object? value, String path) {
  final result = workerString(value, path, minimum: 64, maximum: 64);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(result)) {
    throw FormatException('Invalid digest at $path.');
  }
  return result;
}

String _canonical(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is List<Object?>) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  return value;
}

final class _SuiteRunCodec implements CockpitJsonCodec<Map<String, Object?>> {
  const _SuiteRunCodec();

  @override
  Map<String, Object?> decode(Object? json) => workerObject(json, r'$');

  @override
  Object? encode(Map<String, Object?> value) => value;
}
