import 'dart:async';
import 'dart:math';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../test/cockpit_test_safety_policy.dart';
import '../worker/cockpit_worker_protocol_result.dart';
import '../worker/cockpit_worker_value_reader.dart';

final class CockpitWorkspaceWorkerKey {
  CockpitWorkspaceWorkerKey({
    required this.workspaceId,
    required this.engineVersion,
  }) {
    workerId(workspaceId, r'$.workspaceId');
    workerId(engineVersion, r'$.engineVersion');
  }

  final String workspaceId;
  final String engineVersion;

  @override
  bool operator ==(Object other) =>
      other is CockpitWorkspaceWorkerKey &&
      other.workspaceId == workspaceId &&
      other.engineVersion == engineVersion;

  @override
  int get hashCode => Object.hash(workspaceId, engineVersion);

  @override
  String toString() => '$workspaceId@$engineVersion';
}

final class CockpitWorkspaceWorkerSpec {
  CockpitWorkspaceWorkerSpec({
    required this.key,
    required this.projectId,
    required this.workspaceRoot,
    required this.stateRoot,
    required Iterable<String> supportedFeatures,
    this.authorizationMode = CockpitAuthorizationMode.restricted,
    Iterable<CockpitTestTargetEnvironment> allowedTargetEnvironments =
        const <CockpitTestTargetEnvironment>[],
    Iterable<CockpitTestSafetyEffect> allowedSafetyEffects =
        const <CockpitTestSafetyEffect>[],
  }) : supportedFeatures = List<String>.unmodifiable(supportedFeatures),
       allowedTargetEnvironments = _uniqueEnumSet(
         allowedTargetEnvironments,
         'allowedTargetEnvironments',
       ),
       allowedSafetyEffects = _uniqueEnumSet(
         allowedSafetyEffects,
         'allowedSafetyEffects',
       ) {
    workerId(projectId, r'$.projectId');
    workerString(workspaceRoot, r'$.workspaceRoot', maximum: 32768);
    workerString(stateRoot, r'$.stateRoot', maximum: 32768);
    final unique = <String>{};
    for (final feature in this.supportedFeatures) {
      workerId(feature, r'$.supportedFeatures[]');
      if (!unique.add(feature)) {
        throw FormatException('Duplicate worker feature $feature.');
      }
    }
  }

  final CockpitWorkspaceWorkerKey key;
  final String projectId;
  final String workspaceRoot;
  final String stateRoot;
  final List<String> supportedFeatures;
  final CockpitAuthorizationMode authorizationMode;
  final Set<CockpitTestTargetEnvironment> allowedTargetEnvironments;
  final Set<CockpitTestSafetyEffect> allowedSafetyEffects;
}

Set<T> _uniqueEnumSet<T extends Enum>(Iterable<T> values, String name) {
  final result = <T>{};
  for (final value in values) {
    if (!result.add(value)) {
      throw FormatException('Duplicate $name value ${value.name}.');
    }
  }
  return Set<T>.unmodifiable(result);
}

abstract interface class CockpitWorkspaceWorkerConnection {
  int get processId;
  Future<int> get exitCode;
  bool get isClosed;

  Future<Object?> call({
    required String method,
    required Map<String, Object?> params,
    required DateTime deadline,
    String? requestId,
  });

  Future<void> terminate({required bool force});
}

abstract interface class CockpitWorkspaceWorkerLauncher {
  Future<CockpitWorkspaceWorkerConnection> launch(
    CockpitWorkspaceWorkerSpec spec,
  );
}

final class CockpitWorkerPoolException implements Exception {
  const CockpitWorkerPoolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CockpitWorkerPoolException($code): $message';
}

final class CockpitWorkspaceWorkerCall {
  const CockpitWorkspaceWorkerCall({
    required this.requestId,
    required this.result,
  });

  final String requestId;
  final Future<Object?> result;
}

final class CockpitWorkerPool {
  CockpitWorkerPool({
    required CockpitWorkspaceWorkerLauncher launcher,
    DateTime Function()? utcNow,
    Duration initializationTimeout = const Duration(minutes: 2),
    Duration heartbeatInterval = const Duration(seconds: 5),
    Duration heartbeatTimeout = const Duration(seconds: 10),
    Duration initialRestartBackoff = const Duration(milliseconds: 100),
    Duration maximumRestartBackoff = const Duration(seconds: 10),
    int heartbeatFailureThreshold = 3,
  }) : _launcher = launcher,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _initializationTimeout = initializationTimeout,
       _heartbeatTimeout = heartbeatTimeout,
       _initialRestartBackoff = initialRestartBackoff,
       _maximumRestartBackoff = maximumRestartBackoff,
       _heartbeatFailureThreshold = heartbeatFailureThreshold {
    if (initializationTimeout <= Duration.zero ||
        initializationTimeout > const Duration(minutes: 10) ||
        heartbeatInterval <= Duration.zero ||
        heartbeatTimeout <= Duration.zero ||
        initialRestartBackoff < Duration.zero ||
        maximumRestartBackoff < initialRestartBackoff ||
        heartbeatFailureThreshold < 1 ||
        heartbeatFailureThreshold > 10) {
      throw ArgumentError('Invalid worker pool timing configuration.');
    }
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => unawaited(_heartbeatAll()),
    );
  }

  final CockpitWorkspaceWorkerLauncher _launcher;
  final DateTime Function() _utcNow;
  final Duration _initializationTimeout;
  final Duration _heartbeatTimeout;
  final Duration _initialRestartBackoff;
  final Duration _maximumRestartBackoff;
  final int _heartbeatFailureThreshold;
  final Map<CockpitWorkspaceWorkerKey, _WorkerSlot> _slots =
      <CockpitWorkspaceWorkerKey, _WorkerSlot>{};
  late final Timer _heartbeatTimer;
  var _internalRequestSequence = 0;
  var _closed = false;

  Iterable<CockpitWorkspaceWorkerKey> get activeKeys =>
      List<CockpitWorkspaceWorkerKey>.unmodifiable(_slots.keys);

  Future<CockpitWorkspaceWorkerConnection> connectionFor(
    CockpitWorkspaceWorkerSpec spec,
  ) {
    if (_closed) {
      throw const CockpitWorkerPoolException(
        'workerPoolClosed',
        'Worker pool is closed.',
      );
    }
    final existing = _slots[spec.key];
    if (existing != null) {
      if (existing.spec.workspaceRoot != spec.workspaceRoot) {
        throw const CockpitWorkerPoolException(
          'workspaceIdentityMismatch',
          'Active worker root does not match its workspace identity.',
        );
      }
      if (existing.spec.projectId != spec.projectId ||
          existing.spec.stateRoot != spec.stateRoot ||
          !_sameSet(
            existing.spec.allowedTargetEnvironments,
            spec.allowedTargetEnvironments,
          ) ||
          !_sameSet(
            existing.spec.allowedSafetyEffects,
            spec.allowedSafetyEffects,
          )) {
        throw const CockpitWorkerPoolException(
          'workspaceIdentityMismatch',
          'Active worker state identity does not match its workspace.',
        );
      }
      return existing.ready;
    }
    final slot = _WorkerSlot(spec);
    _slots[spec.key] = slot;
    _start(slot);
    return slot.ready;
  }

  Future<Object?> call(
    CockpitWorkspaceWorkerSpec spec, {
    required String method,
    required String idempotencyKey,
    required DateTime deadline,
    Map<String, Object?> params = const <String, Object?>{},
  }) => startCall(
    spec,
    method: method,
    idempotencyKey: idempotencyKey,
    deadline: deadline,
    params: params,
  ).result;

  CockpitWorkspaceWorkerCall startCall(
    CockpitWorkspaceWorkerSpec spec, {
    required String method,
    required String idempotencyKey,
    required DateTime deadline,
    String? requestId,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    workerMethod(method, r'$.method');
    workerId(idempotencyKey, r'$.idempotencyKey');
    final effectiveRequestId =
        requestId ?? 'supervisor-call-${++_internalRequestSequence}';
    workerId(effectiveRequestId, r'$.requestId');
    final connection = connectionFor(spec);
    final slot = _slots[spec.key]!;
    slot.activeCalls += 1;
    final result = connection
        .then(
          (connection) => connection.call(
            method: method,
            params: <String, Object?>{
              ...params,
              'protocolVersion': cockpitWorkerProtocolVersion,
              'workspaceId': spec.key.workspaceId,
              'idempotencyKey': idempotencyKey,
            },
            deadline: deadline,
            requestId: effectiveRequestId,
          ),
        )
        .whenComplete(() => slot.activeCalls -= 1);
    return CockpitWorkspaceWorkerCall(
      requestId: effectiveRequestId,
      result: result,
    );
  }

  Future<CockpitWorkerCancelResult> cancel(
    CockpitWorkspaceWorkerSpec spec, {
    required String targetRequestId,
    required DateTime deadline,
  }) async {
    workerId(targetRequestId, r'$.targetRequestId');
    final raw = await call(
      spec,
      method: 'cancel',
      idempotencyKey: 'supervisor-cancel-${++_internalRequestSequence}',
      deadline: deadline,
      params: <String, Object?>{'targetRequestId': targetRequestId},
    );
    return CockpitWorkerCancelResult.fromJson(raw);
  }

  Future<void> shutdownWorkspace(
    CockpitWorkspaceWorkerKey key, {
    Duration grace = const Duration(seconds: 10),
    bool force = false,
  }) async {
    final slot = _slots.remove(key);
    if (slot == null) return;
    slot.desired = false;
    slot.restartTimer?.cancel();
    CockpitWorkspaceWorkerConnection? connection;
    try {
      connection = await slot.ready.timeout(grace);
      if (!force) {
        await connection.call(
          method: 'drain',
          params: _internalParams(
            key.workspaceId,
            'drain',
            extra: <String, Object?>{
              'cancellationGraceMs': grace.inMilliseconds.clamp(0, 300000),
            },
          ),
          deadline: _utcNow().add(grace),
        );
      }
      await connection.call(
        method: 'shutdown',
        params: _internalParams(
          key.workspaceId,
          'shutdown',
          extra: <String, Object?>{'force': force},
        ),
        deadline: _utcNow().add(grace),
      );
    } on Object {
      force = true;
    } finally {
      await connection?.terminate(force: force);
    }
  }

  Future<void> close({Duration grace = const Duration(seconds: 10)}) async {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer.cancel();
    final keys = _slots.keys.toList(growable: false);
    await Future.wait<void>(
      keys.map((key) => shutdownWorkspace(key, grace: grace)),
    );
  }

  void _start(_WorkerSlot slot) {
    final generation = ++slot.generation;
    final launch = _launchAndInitialize(slot.spec);
    slot.launch = launch;
    launch.then(
      (connection) {
        if (!slot.desired ||
            generation != slot.generation ||
            _slots[slot.spec.key] != slot) {
          unawaited(connection.terminate(force: false));
          return;
        }
        slot.connection = connection;
        slot.heartbeatFailures = 0;
        if (!slot.readyCompleter.isCompleted) {
          slot.readyCompleter.complete(connection);
        }
        connection.exitCode.then(
          (exitCode) => _connectionExited(slot, generation, exitCode),
          onError: (Object _, StackTrace _) =>
              _connectionExited(slot, generation, -1),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!slot.readyCompleter.isCompleted) {
          slot.readyCompleter.completeError(error, stackTrace);
        }
        slot.readyCompleter = _workerReadyCompleter();
        _scheduleRestart(slot, generation);
      },
    );
  }

  Future<CockpitWorkspaceWorkerConnection> _launchAndInitialize(
    CockpitWorkspaceWorkerSpec spec,
  ) async {
    final connection = await _launcher.launch(spec);
    try {
      final deadline = _utcNow().add(_initializationTimeout);
      final raw = await connection.call(
        method: 'initialize',
        params: _internalParams(
          spec.key.workspaceId,
          'initialize',
          extra: <String, Object?>{
            'engineVersion': spec.key.engineVersion,
            'workspaceRoot': spec.workspaceRoot,
            'supportedFeatures': spec.supportedFeatures,
          },
        ),
        deadline: deadline,
      );
      final result = CockpitWorkerInitializeResult.fromJson(raw);
      if (result.workspaceId != spec.key.workspaceId ||
          result.engineVersion != spec.key.engineVersion) {
        throw const CockpitWorkerPoolException(
          'workerIdentityMismatch',
          'Worker initialization returned a different identity.',
        );
      }
      return connection;
    } on Object {
      await connection.terminate(force: true);
      rethrow;
    }
  }

  void _connectionExited(_WorkerSlot slot, int generation, int _) {
    if (generation != slot.generation) return;
    slot.connection = null;
    if (slot.readyCompleter.isCompleted) {
      slot.readyCompleter = _workerReadyCompleter();
    }
    _scheduleRestart(slot, generation);
  }

  void _scheduleRestart(_WorkerSlot slot, int generation) {
    if (_closed ||
        !slot.desired ||
        generation != slot.generation ||
        _slots[slot.spec.key] != slot ||
        slot.restartTimer != null) {
      return;
    }
    slot.restartFailures += 1;
    final multiplier = 1 << min(slot.restartFailures - 1, 16);
    final delayMs = min(
      _initialRestartBackoff.inMilliseconds * multiplier,
      _maximumRestartBackoff.inMilliseconds,
    );
    slot.restartTimer = Timer(Duration(milliseconds: delayMs), () {
      slot.restartTimer = null;
      if (!slot.desired || _closed) return;
      _start(slot);
    });
  }

  Future<void> _heartbeatAll() async {
    if (_closed) return;
    final slots = _slots.values.toList(growable: false);
    await Future.wait<void>(slots.map(_heartbeat));
  }

  Future<void> _heartbeat(_WorkerSlot slot) async {
    final connection = slot.connection;
    if (connection == null || !slot.desired || slot.heartbeatInFlight) return;
    if (slot.activeCalls > 0) {
      slot.heartbeatFailures = 0;
      return;
    }
    slot.heartbeatInFlight = true;
    try {
      if (connection.isClosed) {
        await connection.terminate(force: true);
        return;
      }
      final deadline = _utcNow().add(_heartbeatTimeout);
      final raw = await connection.call(
        method: 'health',
        params: _internalParams(slot.spec.key.workspaceId, 'health'),
        deadline: deadline,
      );
      final health = CockpitWorkerHealthResult.fromJson(raw);
      if (!health.healthy || health.workspaceId != slot.spec.key.workspaceId) {
        throw const CockpitWorkerPoolException(
          'workerUnhealthy',
          'Worker health response is unhealthy or mismatched.',
        );
      }
      slot.heartbeatFailures = 0;
      slot.restartFailures = 0;
    } on Object {
      slot.heartbeatFailures += 1;
      if (slot.heartbeatFailures >= _heartbeatFailureThreshold) {
        await connection.terminate(force: true);
      }
    } finally {
      slot.heartbeatInFlight = false;
    }
  }

  Map<String, Object?> _internalParams(
    String workspaceId,
    String purpose, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => <String, Object?>{
    'protocolVersion': cockpitWorkerProtocolVersion,
    'workspaceId': workspaceId,
    'idempotencyKey': 'supervisor-$purpose-${++_internalRequestSequence}',
    ...extra,
  };
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

final class _WorkerSlot {
  _WorkerSlot(this.spec) : readyCompleter = _workerReadyCompleter();

  final CockpitWorkspaceWorkerSpec spec;
  Completer<CockpitWorkspaceWorkerConnection> readyCompleter;
  Future<CockpitWorkspaceWorkerConnection>? launch;
  CockpitWorkspaceWorkerConnection? connection;
  Timer? restartTimer;
  var generation = 0;
  var heartbeatFailures = 0;
  var heartbeatInFlight = false;
  var restartFailures = 0;
  var activeCalls = 0;
  var desired = true;

  Future<CockpitWorkspaceWorkerConnection> get ready =>
      connection == null ? readyCompleter.future : Future.value(connection);
}

Completer<CockpitWorkspaceWorkerConnection> _workerReadyCompleter() {
  final completer = Completer<CockpitWorkspaceWorkerConnection>();
  completer.future.ignore();
  return completer;
}
