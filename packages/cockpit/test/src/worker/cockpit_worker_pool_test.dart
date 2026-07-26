import 'dart:async';

import 'package:cockpit/src/supervisor/cockpit_worker_pool.dart';
import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('allows two minutes for the default worker initialization', () async {
    final now = DateTime.utc(2026, 7, 25, 12);
    final launcher = _FakeLauncher();
    final pool = CockpitWorkerPool(
      launcher: launcher,
      utcNow: () => now,
      heartbeatInterval: const Duration(seconds: 30),
    );
    addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));

    final connection =
        await pool.connectionFor(_spec('workspaceA')) as _FakeConnection;

    expect(
      connection.initializationDeadline,
      now.add(const Duration(minutes: 2)),
    );
  });

  test('rejects invalid worker initialization timeouts', () {
    for (final timeout in <Duration>[
      Duration.zero,
      const Duration(minutes: 10, microseconds: 1),
    ]) {
      expect(
        () => CockpitWorkerPool(
          launcher: _FakeLauncher(),
          initializationTimeout: timeout,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'deduplicates each worker key and targets operation cancellation',
    () async {
      final launcher = _FakeLauncher();
      final pool = CockpitWorkerPool(
        launcher: launcher,
        heartbeatInterval: const Duration(seconds: 30),
        initialRestartBackoff: const Duration(milliseconds: 1),
        maximumRestartBackoff: const Duration(milliseconds: 1),
      );
      final spec = _spec('workspaceA');
      addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));

      final connections = await Future.wait(
        <Future<CockpitWorkspaceWorkerConnection>>[
          pool.connectionFor(spec),
          pool.connectionFor(spec),
        ],
      );
      expect(identical(connections.first, connections.last), isTrue);
      expect(launcher.launchCount('workspaceA'), 1);

      final operation = pool.startCall(
        spec,
        method: 'operation',
        idempotencyKey: 'operationA',
        deadline: _deadline(),
        params: const <String, Object?>{'invocation': <String, Object?>{}},
      );
      final connection = connections.first as _FakeConnection;
      await connection.operationStarted;
      final cancellation = await pool.cancel(
        spec,
        targetRequestId: operation.requestId,
        deadline: _deadline(),
      );
      expect(cancellation.targetRequestId, operation.requestId);
      expect(cancellation.cancelled, isTrue);
      expect(connection.cancelledRequestIds, <String>[operation.requestId]);
      expect(await operation.result, <String, Object?>{'cancelled': true});
    },
  );

  test('restarts only the worker whose process exits', () async {
    final launcher = _FakeLauncher();
    final pool = CockpitWorkerPool(
      launcher: launcher,
      heartbeatInterval: const Duration(seconds: 30),
      initialRestartBackoff: const Duration(milliseconds: 1),
      maximumRestartBackoff: const Duration(milliseconds: 1),
    );
    final specA = _spec('workspaceA');
    final specB = _spec('workspaceB');
    addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));
    final connectionA = await pool.connectionFor(specA) as _FakeConnection;
    final connectionB = await pool.connectionFor(specB) as _FakeConnection;

    connectionA.exit(77);
    await launcher.waitForLaunchCount('workspaceA', 2);
    final restartedA = await pool.connectionFor(specA);
    final retainedB = await pool.connectionFor(specB);
    expect(restartedA, isNot(same(connectionA)));
    expect(retainedB, same(connectionB));
    expect(launcher.launchCount('workspaceA'), 2);
    expect(launcher.launchCount('workspaceB'), 1);
  });

  test('restarts a worker after its heartbeat becomes unhealthy', () async {
    final launcher = _FakeLauncher(unhealthyFirstConnection: true);
    final pool = CockpitWorkerPool(
      launcher: launcher,
      heartbeatInterval: const Duration(milliseconds: 5),
      heartbeatTimeout: const Duration(milliseconds: 20),
      heartbeatFailureThreshold: 1,
      initialRestartBackoff: const Duration(milliseconds: 1),
      maximumRestartBackoff: const Duration(milliseconds: 1),
    );
    final spec = _spec('workspaceA');
    addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));
    final first = await pool.connectionFor(spec) as _FakeConnection;

    await launcher.waitForLaunchCount('workspaceA', 2);
    final restarted = await pool.connectionFor(spec) as _FakeConnection;
    expect(first.isClosed, isTrue);
    expect(restarted, isNot(same(first)));
    expect(restarted.unhealthy, isFalse);
  });

  test('does not overlap heartbeat requests for one worker', () async {
    final launcher = _FakeLauncher(
      healthDelay: const Duration(milliseconds: 30),
    );
    final pool = CockpitWorkerPool(
      launcher: launcher,
      heartbeatInterval: const Duration(milliseconds: 5),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));

    final connection =
        await pool.connectionFor(_spec('workspaceA')) as _FakeConnection;
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(connection.maximumConcurrentHealthCalls, 1);
  });

  test('force terminates and restarts a worker whose peer closes', () async {
    final launcher = _FakeLauncher();
    final pool = CockpitWorkerPool(
      launcher: launcher,
      heartbeatInterval: const Duration(milliseconds: 5),
      heartbeatTimeout: const Duration(milliseconds: 20),
      initialRestartBackoff: const Duration(milliseconds: 1),
      maximumRestartBackoff: const Duration(milliseconds: 1),
    );
    final spec = _spec('workspaceA');
    addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));
    final first = await pool.connectionFor(spec) as _FakeConnection;

    first.closePeer();
    await launcher.waitForLaunchCount('workspaceA', 2);

    expect(await first.exitCode, -9);
    expect(await pool.connectionFor(spec), isNot(same(first)));
  });

  test('rejects safety-authority changes for an active worker key', () async {
    final launcher = _FakeLauncher();
    final pool = CockpitWorkerPool(
      launcher: launcher,
      heartbeatInterval: const Duration(seconds: 30),
    );
    addTearDown(() => pool.close(grace: const Duration(milliseconds: 50)));
    final baseline = _spec(
      'workspaceA',
      allowedTargetEnvironments: const <CockpitTestTargetEnvironment>{
        CockpitTestTargetEnvironment.development,
      },
      allowedSafetyEffects: const <CockpitTestSafetyEffect>{
        CockpitTestSafetyEffect.credentialSensitive,
      },
    );
    await pool.connectionFor(baseline);

    for (final changed in <CockpitWorkspaceWorkerSpec>[
      _spec(
        'workspaceA',
        allowedTargetEnvironments: const <CockpitTestTargetEnvironment>{
          CockpitTestTargetEnvironment.test,
        },
        allowedSafetyEffects: baseline.allowedSafetyEffects,
      ),
      _spec(
        'workspaceA',
        allowedTargetEnvironments: baseline.allowedTargetEnvironments,
        allowedSafetyEffects: const <CockpitTestSafetyEffect>{
          CockpitTestSafetyEffect.financial,
        },
      ),
    ]) {
      expect(
        () => pool.connectionFor(changed),
        throwsA(
          isA<CockpitWorkerPoolException>().having(
            (error) => error.code,
            'code',
            'workspaceIdentityMismatch',
          ),
        ),
      );
    }
    expect(launcher.launchCount('workspaceA'), 1);
  });
}

CockpitWorkspaceWorkerSpec _spec(
  String workspaceId, {
  Iterable<CockpitTestTargetEnvironment> allowedTargetEnvironments =
      const <CockpitTestTargetEnvironment>[],
  Iterable<CockpitTestSafetyEffect> allowedSafetyEffects =
      const <CockpitTestSafetyEffect>[],
}) => CockpitWorkspaceWorkerSpec(
  key: CockpitWorkspaceWorkerKey(
    workspaceId: workspaceId,
    engineVersion: 'engineA',
  ),
  projectId: 'projectA',
  workspaceRoot: '/workspace/$workspaceId',
  stateRoot: '/state/$workspaceId',
  supportedFeatures: const <String>[],
  allowedTargetEnvironments: allowedTargetEnvironments,
  allowedSafetyEffects: allowedSafetyEffects,
);

DateTime _deadline() => DateTime.now().toUtc().add(const Duration(seconds: 5));

final class _FakeLauncher implements CockpitWorkspaceWorkerLauncher {
  _FakeLauncher({
    this.unhealthyFirstConnection = false,
    this.healthDelay = Duration.zero,
  });

  final bool unhealthyFirstConnection;
  final Duration healthDelay;
  final Map<String, List<_FakeConnection>> connections =
      <String, List<_FakeConnection>>{};
  final Map<String, List<_LaunchWaiter>> _waiters =
      <String, List<_LaunchWaiter>>{};

  @override
  Future<CockpitWorkspaceWorkerConnection> launch(
    CockpitWorkspaceWorkerSpec spec,
  ) async {
    final existing = connections.putIfAbsent(
      spec.key.workspaceId,
      () => <_FakeConnection>[],
    );
    final connection = _FakeConnection(
      spec,
      unhealthy: unhealthyFirstConnection && existing.isEmpty,
      healthDelay: healthDelay,
    );
    final launched = existing..add(connection);
    final waiters = _waiters[spec.key.workspaceId] ?? const <_LaunchWaiter>[];
    for (final waiter in waiters.toList(growable: false)) {
      if (launched.length >= waiter.count && !waiter.done.isCompleted) {
        waiter.done.complete();
      }
    }
    return connection;
  }

  int launchCount(String workspaceId) => connections[workspaceId]?.length ?? 0;

  Future<void> waitForLaunchCount(String workspaceId, int count) {
    if (launchCount(workspaceId) >= count) return Future<void>.value();
    final waiter = _LaunchWaiter(count);
    _waiters.putIfAbsent(workspaceId, () => <_LaunchWaiter>[]).add(waiter);
    return waiter.done.future.timeout(const Duration(seconds: 2));
  }
}

final class _LaunchWaiter {
  _LaunchWaiter(this.count);

  final int count;
  final Completer<void> done = Completer<void>();
}

final class _FakeConnection implements CockpitWorkspaceWorkerConnection {
  _FakeConnection(
    this.spec, {
    this.unhealthy = false,
    this.healthDelay = Duration.zero,
  });

  final CockpitWorkspaceWorkerSpec spec;
  final bool unhealthy;
  final Duration healthDelay;
  final Completer<int> _exitCode = Completer<int>();
  final Completer<void> _operationStarted = Completer<void>();
  final Map<String, Completer<Object?>> _operations =
      <String, Completer<Object?>>{};
  final List<String> cancelledRequestIds = <String>[];
  DateTime? initializationDeadline;
  var _closed = false;
  var _activeHealthCalls = 0;
  var maximumConcurrentHealthCalls = 0;

  Future<void> get operationStarted => _operationStarted.future;

  @override
  int get processId => 100;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool get isClosed => _closed;

  @override
  Future<Object?> call({
    required String method,
    required Map<String, Object?> params,
    required DateTime deadline,
    String? requestId,
  }) async {
    return switch (method) {
      'initialize' => _initialize(deadline),
      'operation' => await _operation(requestId!),
      'cancel' => _cancel(params['targetRequestId']! as String),
      'health' => await _health(),
      'drain' => CockpitWorkerDrainResult(
        draining: true,
        activeRequestCount: 0,
      ).toJson(),
      'shutdown' => const CockpitWorkerShutdownResult(accepted: true).toJson(),
      _ => throw StateError('Unexpected fake worker method $method.'),
    };
  }

  Future<Map<String, Object?>> _health() async {
    _activeHealthCalls += 1;
    if (_activeHealthCalls > maximumConcurrentHealthCalls) {
      maximumConcurrentHealthCalls = _activeHealthCalls;
    }
    try {
      if (healthDelay > Duration.zero) await Future<void>.delayed(healthDelay);
      return CockpitWorkerHealthResult(
        workspaceId: spec.key.workspaceId,
        healthy: !unhealthy,
        draining: false,
        activeRequestCount: 0,
        checkedAt: DateTime.now().toUtc(),
      ).toJson();
    } finally {
      _activeHealthCalls -= 1;
    }
  }

  Map<String, Object?> _initialize(DateTime deadline) {
    initializationDeadline = deadline;
    return CockpitWorkerInitializeResult(
      protocolVersion: 'cockpit.worker/v2',
      workspaceId: spec.key.workspaceId,
      engineVersion: spec.key.engineVersion,
      negotiatedFeatures: const <String>[],
    ).toJson();
  }

  Future<Object?> _operation(String requestId) {
    final result = Completer<Object?>();
    _operations[requestId] = result;
    if (!_operationStarted.isCompleted) _operationStarted.complete();
    return result.future;
  }

  Map<String, Object?> _cancel(String targetRequestId) {
    cancelledRequestIds.add(targetRequestId);
    _operations.remove(targetRequestId)?.complete(const <String, Object?>{
      'cancelled': true,
    });
    return CockpitWorkerCancelResult(
      targetRequestId: targetRequestId,
      cancelled: true,
      alreadyTerminal: false,
    ).toJson();
  }

  void exit(int code) {
    _closed = true;
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  void closePeer() => _closed = true;

  @override
  Future<void> terminate({required bool force}) async => exit(force ? -9 : 0);
}
