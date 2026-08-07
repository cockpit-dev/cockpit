import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';

import 'cockpit_json_rpc_message.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_artifact_registry.dart';
import 'cockpit_worker_protocol_request.dart';
import 'cockpit_worker_protocol_result.dart';
import 'cockpit_worker_protocol_schema.dart';
import 'cockpit_worker_value_reader.dart';

abstract interface class CockpitWorkerOperationDispatcher {
  List<String> get operationKinds;
  List<String> get resourceKinds;

  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation, {
    required String requestId,
    required CockpitRpcCancellation cancellation,
  });
}

abstract interface class CockpitWorkerEventExchange {
  Future<CockpitWorkerReplayEventsResult> replay(
    CockpitWorkerReplayEventsRequest request,
  );

  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  );
}

abstract interface class CockpitWorkerArtifactExchange {
  Future<CockpitWorkerPublishArtifactBatchResult> publishArtifacts(
    CockpitWorkerPublishArtifactBatchRequest request,
  );
}

final class CockpitWorkerServer {
  CockpitWorkerServer({
    required this.workspaceId,
    required this.engineVersion,
    required this.workspaceRoot,
    required Iterable<String> supportedFeatures,
    required CockpitWorkerOperationDispatcher operations,
    required CockpitWorkerEventExchange events,
    CockpitWorkerArtifactRegistry? artifacts,
    FutureOr<void> Function()? onInitialized,
    FutureOr<void> Function()? onShutdown,
    DateTime Function()? utcNow,
  }) : supportedFeatures = Set<String>.unmodifiable(supportedFeatures),
       _operations = operations,
       _events = events,
       _artifacts = artifacts,
       _onInitialized = onInitialized,
       _onShutdown = onShutdown,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
    workerId(engineVersion, r'$.engineVersion');
    workerString(workspaceRoot, r'$.workspaceRoot', maximum: 32768);
    for (final feature in this.supportedFeatures) {
      workerId(feature, r'$.supportedFeatures[]');
    }
  }

  final String workspaceId;
  final String engineVersion;
  final String workspaceRoot;
  final Set<String> supportedFeatures;
  final CockpitWorkerOperationDispatcher _operations;
  final CockpitWorkerEventExchange _events;
  final CockpitWorkerArtifactRegistry? _artifacts;
  final FutureOr<void> Function()? _onInitialized;
  final FutureOr<void> Function()? _onShutdown;
  final DateTime Function() _utcNow;
  final Map<String, _ActiveOperation> _activeOperations =
      <String, _ActiveOperation>{};
  CockpitJsonRpcPeer? _peer;
  Set<String> _negotiatedFeatures = const <String>{};
  var _initializationPhase = _WorkerInitializationPhase.uninitialized;
  Future<void>? _initialization;
  Set<String>? _initializingFeatures;
  var _draining = false;
  var _shutdown = false;

  bool get isInitialized =>
      _initializationPhase == _WorkerInitializationPhase.initialized;
  bool get isDraining => _draining;
  int get activeOperationCount => _activeOperations.length;

  void bindPeer(CockpitJsonRpcPeer peer) {
    if (_peer != null) throw StateError('Worker server peer is already bound.');
    _peer = peer;
  }

  Future<Object?> handle(
    CockpitJsonRpcRequest request,
    CockpitRpcCancellation cancellation,
  ) async {
    _validateEnvelopeBeforeDispatch(request);
    CockpitWorkerProtocolSchema.validateRequest(request.method, request.params);
    final decoded = CockpitWorkerProtocolRequest.fromJson(
      request.method,
      request.params,
    );
    if (decoded.requestId != request.id) {
      throw _rpcError(
        'requestIdMismatch',
        'Worker request id does not match its JSON-RPC envelope.',
      );
    }
    final result = await switch (decoded) {
      CockpitWorkerInitializeRequest() => _initialize(decoded),
      CockpitWorkerCapabilitiesRequest() => _capabilities(decoded),
      CockpitWorkerOperationRequest() => _operation(decoded, cancellation),
      CockpitWorkerCancelRequest() => _cancel(decoded),
      CockpitWorkerDrainRequest() => _drain(decoded, cancellation),
      CockpitWorkerHealthRequest() => _health(decoded),
      CockpitWorkerShutdownRequest() => _shutdownWorker(decoded, cancellation),
      CockpitWorkerReplayEventsRequest() => _events.replay(decoded),
      CockpitWorkerPublishEventBatchRequest() => _events.publish(decoded),
      CockpitWorkerPublishArtifactBatchRequest() => throw _rpcError(
        'methodUnavailable',
        'Artifact publication is only accepted by the Supervisor peer.',
      ),
      CockpitWorkerReadSessionArtifactRequest() => _readSessionArtifact(
        decoded,
      ),
    };
    final json = result.toJson();
    CockpitWorkerProtocolSchema.validateResult(result.method, json);
    return json;
  }

  Future<CockpitWorkerReadSessionArtifactResult> _readSessionArtifact(
    CockpitWorkerReadSessionArtifactRequest request,
  ) async {
    final artifacts = _artifacts;
    if (artifacts == null) {
      throw _rpcError(
        'methodUnavailable',
        'Session artifact reads are unavailable in this worker.',
      );
    }
    final binding = await artifacts.requireArtifact(request.artifactId);
    if (binding.ownerKind != 'session' ||
        binding.ownerId != request.sessionId) {
      throw _rpcError(
        'artifactNotFound',
        'Session artifact was not found for this owner.',
      );
    }
    final file = File(binding.retainedPath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size < 1) {
      throw _rpcError(
        'artifactUnavailable',
        'Session artifact file is unavailable.',
      );
    }
    final digest = (await sha256.bind(file.openRead()).first).toString();
    return CockpitWorkerReadSessionArtifactResult(
      sessionId: request.sessionId,
      artifactId: binding.artifactId,
      kind: binding.kind,
      name: binding.name,
      mediaType: binding.mediaType,
      retainedPath: binding.retainedPath,
      sizeBytes: stat.size,
      sha256: digest,
    );
  }

  void _validateEnvelopeBeforeDispatch(CockpitJsonRpcRequest request) {
    final params = request.params;
    final protocolVersion = params['protocolVersion'];
    if (protocolVersion != cockpitWorkerProtocolVersion) {
      throw _rpcError(
        'upgradeRequired',
        'Worker protocol version is incompatible.',
        details: <String, Object?>{
          'supported': cockpitWorkerProtocolVersion,
          if (protocolVersion is String) 'received': protocolVersion,
        },
      );
    }
    final requestWorkspaceId = params['workspaceId'];
    if (requestWorkspaceId != workspaceId) {
      throw _rpcError(
        'workspaceMismatch',
        'Worker request belongs to another workspace.',
      );
    }
    if (_shutdown && request.method != 'health') {
      throw _rpcError('workerShuttingDown', 'Worker shutdown has started.');
    }
    final recoveringReplay =
        _initializationPhase == _WorkerInitializationPhase.recovering &&
        request.method == 'replayEvents';
    if (!isInitialized &&
        !recoveringReplay &&
        request.method != 'initialize' &&
        request.method != 'health' &&
        request.method != 'shutdown') {
      throw _rpcError('notInitialized', 'Worker is not initialized.');
    }
  }

  Future<CockpitWorkerInitializeResult> _initialize(
    CockpitWorkerInitializeRequest request,
  ) async {
    if (request.engineVersion != engineVersion ||
        request.workspaceRoot != workspaceRoot) {
      throw _rpcError(
        'workerIdentityMismatch',
        'Worker initialization identity is inconsistent.',
      );
    }
    final negotiated = request.supportedFeatures
        .where(supportedFeatures.contains)
        .toSet();
    if (isInitialized && !_sameFeatures(negotiated, _negotiatedFeatures)) {
      throw _rpcError(
        'initializeConflict',
        'Worker was initialized with different negotiated features.',
      );
    }
    if (isInitialized) return _initializeResult(negotiated);

    final activeInitialization = _initialization;
    if (activeInitialization != null) {
      if (!_sameFeatures(negotiated, _initializingFeatures!)) {
        throw _rpcError(
          'initializeConflict',
          'Worker is initializing with different negotiated features.',
        );
      }
      await activeInitialization;
      return _initializeResult(negotiated);
    }

    final features = Set<String>.unmodifiable(negotiated);
    _initializationPhase = _WorkerInitializationPhase.recovering;
    final initialization = Future<void>.sync(() async {
      if (_onInitialized != null) await Future<void>.sync(_onInitialized);
      if (_shutdown) {
        throw _rpcError(
          'workerShuttingDown',
          'Worker shutdown started before initialization completed.',
        );
      }
      _negotiatedFeatures = features;
      _initializationPhase = _WorkerInitializationPhase.initialized;
    });
    _initializingFeatures = features;
    _initialization = initialization;
    try {
      await initialization;
    } on Object {
      if (_initializationPhase == _WorkerInitializationPhase.recovering) {
        _initializationPhase = _WorkerInitializationPhase.uninitialized;
      }
      rethrow;
    } finally {
      if (identical(_initialization, initialization)) {
        _initialization = null;
        _initializingFeatures = null;
      }
    }
    return _initializeResult(negotiated);
  }

  CockpitWorkerInitializeResult _initializeResult(Set<String> negotiated) =>
      CockpitWorkerInitializeResult(
        protocolVersion: cockpitWorkerProtocolVersion,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        negotiatedFeatures: negotiated,
      );

  Future<CockpitWorkerCapabilitiesResult> _capabilities(
    CockpitWorkerCapabilitiesRequest _,
  ) async => CockpitWorkerCapabilitiesResult(
    workspaceId: workspaceId,
    operationKinds: _operations.operationKinds,
    resourceKinds: _operations.resourceKinds,
    features: _negotiatedFeatures,
  );

  Future<CockpitWorkerOperationResult> _operation(
    CockpitWorkerOperationRequest request,
    CockpitRpcCancellation cancellation,
  ) async {
    if (_draining) {
      throw _rpcError('workerDraining', 'Worker is not accepting new work.');
    }
    final missingFeatures =
        request.invocation.requiredFeatures
            .where((feature) => !_negotiatedFeatures.contains(feature))
            .toList(growable: false)
          ..sort();
    if (missingFeatures.isNotEmpty) {
      throw _rpcError(
        'requiredFeatureMissing',
        'Worker operation requires features that were not negotiated.',
        details: <String, Object?>{'missingFeatures': missingFeatures},
      );
    }
    final active = _ActiveOperation(cancellation);
    _activeOperations[request.requestId] = active;
    try {
      final result = await _operations.execute(
        request.invocation,
        requestId: request.requestId,
        cancellation: cancellation,
      );
      return CockpitWorkerOperationResult(result);
    } finally {
      _activeOperations.remove(request.requestId);
      active.complete();
    }
  }

  Future<CockpitWorkerCancelResult> _cancel(
    CockpitWorkerCancelRequest request,
  ) async {
    final result =
        _peer?.cancelInbound(request.targetRequestId) ??
        CockpitRpcCancellationResult.unknown;
    return CockpitWorkerCancelResult(
      targetRequestId: request.targetRequestId,
      cancelled: result == CockpitRpcCancellationResult.cancelled,
      alreadyTerminal: result == CockpitRpcCancellationResult.alreadyTerminal,
    );
  }

  Future<CockpitWorkerDrainResult> _drain(
    CockpitWorkerDrainRequest request,
    CockpitRpcCancellation cancellation,
  ) async {
    _draining = true;
    await _waitForOperations(
      Duration(milliseconds: request.cancellationGraceMs),
      cancellation,
    );
    return CockpitWorkerDrainResult(
      draining: true,
      activeRequestCount: _activeOperations.length,
    );
  }

  Future<CockpitWorkerHealthResult> _health(
    CockpitWorkerHealthRequest _,
  ) async => CockpitWorkerHealthResult(
    workspaceId: workspaceId,
    healthy: !_shutdown,
    draining: _draining,
    activeRequestCount: _activeOperations.length,
    checkedAt: _utcNow(),
  );

  Future<CockpitWorkerShutdownResult> _shutdownWorker(
    CockpitWorkerShutdownRequest request,
    CockpitRpcCancellation cancellation,
  ) async {
    _draining = true;
    if (request.force) {
      for (final operation in _activeOperations.values) {
        operation.cancellation.cancel();
      }
    } else {
      await _waitForOperations(
        request.deadline.difference(_utcNow()),
        cancellation,
      );
    }
    _shutdown = true;
    final callback = _onShutdown;
    if (callback != null) await Future<void>.sync(callback);
    return const CockpitWorkerShutdownResult(accepted: true);
  }

  Future<void> _waitForOperations(
    Duration grace,
    CockpitRpcCancellation cancellation,
  ) async {
    if (_activeOperations.isEmpty) return;
    final bounded = grace.isNegative ? Duration.zero : grace;
    final active = _activeOperations.values
        .map((operation) => operation.done)
        .toList(growable: false);
    await Future.any<void>(<Future<void>>[
      Future.wait(active),
      Future<void>.delayed(bounded),
      cancellation.whenCancelled,
    ]);
    if (_activeOperations.isNotEmpty) {
      for (final operation in _activeOperations.values) {
        operation.cancellation.cancel();
      }
    }
  }
}

enum _WorkerInitializationPhase { uninitialized, recovering, initialized }

final class _ActiveOperation {
  _ActiveOperation(this.cancellation);

  final CockpitRpcCancellation cancellation;
  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}

bool _sameFeatures(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

CockpitJsonRpcRemoteException _rpcError(
  String workerCode,
  String message, {
  Map<String, Object?> details = const <String, Object?>{},
}) => CockpitJsonRpcRemoteException(
  CockpitJsonRpcError(
    code: -32000,
    message: message,
    workerCode: workerCode,
    details: details,
  ),
);
