import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../worker/cockpit_json_rpc_message.dart';
import '../worker/cockpit_json_rpc_peer.dart';
import '../worker/cockpit_worker_protocol_request.dart';
import '../worker/cockpit_worker_protocol_result.dart';
import '../worker/cockpit_worker_protocol_schema.dart';
import '../worker/cockpit_worker_value_reader.dart';
import '../worker/cockpit_worker_server.dart';
import 'cockpit_supervisor_run_projection.dart';
import 'cockpit_lease_support.dart';
import 'cockpit_worker_resource_authority.dart';

typedef CockpitSupervisorWorkerReplayClient =
    Future<CockpitWorkerReplayEventsResult> Function({
      required String runId,
      required int afterSequence,
      required DateTime deadline,
    });

final class CockpitSupervisorWorkerEndpoint {
  CockpitSupervisorWorkerEndpoint({
    required this.workspaceId,
    required CockpitWorkerEventExchange events,
    CockpitWorkerArtifactExchange? artifacts,
    required CockpitSupervisorWorkerResourceAuthority resourceAuthority,
    this.maximumReplayEvents = 100000,
    DateTime Function()? utcNow,
  }) : _events = events,
       _artifacts = artifacts,
       _runTruth = events is CockpitSupervisorRunTruthProjection
           ? events
           : null,
       _resourceAuthority = resourceAuthority,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
    if (maximumReplayEvents < 1 || maximumReplayEvents > 1000000) {
      throw ArgumentError.value(maximumReplayEvents, 'maximumReplayEvents');
    }
  }

  final String workspaceId;
  final int maximumReplayEvents;
  final CockpitWorkerEventExchange _events;
  final CockpitWorkerArtifactExchange? _artifacts;
  final CockpitSupervisorRunTruthProjection? _runTruth;
  final CockpitSupervisorWorkerResourceAuthority _resourceAuthority;
  final DateTime Function() _utcNow;
  final Map<String, Future<void>> _recoveries = <String, Future<void>>{};
  _ReplayBinding? _replayBinding;

  void bindReplayClient({
    required Object connectionIdentity,
    required CockpitSupervisorWorkerReplayClient replay,
  }) {
    if (_replayBinding != null) {
      throw StateError('Supervisor replay client is already bound.');
    }
    _replayBinding = _ReplayBinding(
      connectionIdentity: connectionIdentity,
      replay: replay,
    );
  }

  void unbindReplayClient(Object connectionIdentity) {
    final binding = _replayBinding;
    if (binding == null ||
        !identical(binding.connectionIdentity, connectionIdentity)) {
      return;
    }
    binding.cancelled = true;
    _replayBinding = null;
    _recoveries.clear();
  }

  Future<Object?> handle(
    CockpitJsonRpcRequest request,
    CockpitRpcCancellation cancellation,
  ) async {
    if (request.params['protocolVersion'] != cockpitWorkerProtocolVersion) {
      throw _endpointError(
        'upgradeRequired',
        'Worker protocol version is incompatible.',
      );
    }
    if (request.params['workspaceId'] != workspaceId) {
      throw _endpointError(
        'workspaceMismatch',
        'Worker request belongs to another workspace.',
      );
    }
    CockpitWorkerProtocolSchema.validateRequest(request.method, request.params);
    final decoded = CockpitWorkerProtocolRequest.fromJson(
      request.method,
      request.params,
    );
    if (decoded.requestId != request.id) {
      throw _endpointError(
        'requestIdMismatch',
        'Worker request id does not match its JSON-RPC envelope.',
      );
    }
    cancellation.throwIfCancelled();
    final result = switch (decoded) {
      CockpitWorkerPublishEventBatchRequest() => (await _publishEvents(
        decoded,
        cancellation,
      )).toJson(),
      CockpitWorkerPublishArtifactBatchRequest() =>
        (await (_artifacts ??
                    (throw _endpointError(
                      'methodUnavailable',
                      'Artifact publication is not configured.',
                    )))
                .publishArtifacts(decoded))
            .toJson(),
      CockpitWorkerOperationRequest() => CockpitWorkerOperationResult(
        await _executeOperation(decoded.invocation),
      ).toJson(),
      _ => throw _endpointError(
        'methodUnavailable',
        'Method ${decoded.method} is not accepted by the Supervisor peer.',
      ),
    };
    CockpitWorkerProtocolSchema.validateResult(decoded.method, result);
    return result;
  }

  Future<CockpitOperationResult> _executeOperation(
    CockpitOperationInvocation invocation,
  ) async {
    try {
      return await _resourceAuthority.execute(invocation);
    } on CockpitLeaseException catch (error) {
      throw CockpitJsonRpcRemoteException(
        CockpitJsonRpcError(
          code: -32000,
          message: error.message,
          workerCode: error.code,
          details: <String, Object?>{
            if (error.lease != null) 'lease': error.lease!.toJson(),
          },
        ),
      );
    }
  }

  Future<CockpitWorkerPublishEventBatchResult> _publishEvents(
    CockpitWorkerPublishEventBatchRequest request,
    CockpitRpcCancellation cancellation,
  ) async {
    final initial = await _events.publish(request);
    if (!initial.hasGap) return initial;
    final runTruth = _runTruth;
    final binding = _replayBinding;
    if (runTruth == null || binding == null || binding.cancelled) {
      throw _endpointError(
        'eventReplayUnavailable',
        'Supervisor event gap recovery is unavailable.',
      );
    }
    final recovery =
        _recoveries[request.runId] ??
        _startRecovery(runTruth: runTruth, binding: binding, request: request);
    await Future.any<void>(<Future<void>>[
      recovery,
      cancellation.whenCancelled.then<void>((_) {
        throw const CockpitRpcCancelledException();
      }),
    ]);
    cancellation.throwIfCancelled();
    _checkDeadline(request.deadline);
    _requireBinding(binding);
    final rebuilt = await _events.publish(request);
    if (rebuilt.hasGap) {
      throw const FormatException(
        'Supervisor event gap remained after worker truth rebuild.',
      );
    }
    return rebuilt;
  }

  Future<void> _startRecovery({
    required CockpitSupervisorRunTruthProjection runTruth,
    required _ReplayBinding binding,
    required CockpitWorkerPublishEventBatchRequest request,
  }) {
    late final Future<void> recovery;
    recovery =
        _recoverFromWorkerTruth(
          runTruth: runTruth,
          binding: binding,
          runId: request.runId,
          deadline: request.deadline,
        ).whenComplete(() {
          if (identical(_recoveries[request.runId], recovery)) {
            _recoveries.remove(request.runId);
          }
        });
    _recoveries[request.runId] = recovery;
    return recovery;
  }

  Future<void> _recoverFromWorkerTruth({
    required CockpitSupervisorRunTruthProjection runTruth,
    required _ReplayBinding binding,
    required String runId,
    required DateTime deadline,
  }) async {
    final events = <CockpitRunEvent>[];
    String? projectId;
    var cursor = 0;
    while (true) {
      _checkDeadline(deadline);
      _requireBinding(binding);
      final page = await binding.replay(
        runId: runId,
        afterSequence: cursor,
        deadline: deadline,
      );
      _checkDeadline(deadline);
      _requireBinding(binding);
      if (page.runId != runId || page.afterSequence != cursor) {
        throw const FormatException(
          'Worker event replay page identity is inconsistent.',
        );
      }
      if (page.events.length > 256) {
        throw const FormatException('Worker event replay page is too large.');
      }
      if (page.events.isEmpty) break;
      CockpitRunEvent.validateSequence(page.events, afterSequence: cursor);
      for (final event in page.events) {
        if (event.workspaceId != workspaceId || event.runId != runId) {
          throw const FormatException(
            'Worker event replay crosses Supervisor authority.',
          );
        }
        projectId ??= event.projectId;
        if (event.projectId != projectId) {
          throw const FormatException(
            'Worker event replay changes run ownership.',
          );
        }
      }
      if (events.length + page.events.length > maximumReplayEvents) {
        throw const FormatException(
          'Worker event replay total bound was exceeded.',
        );
      }
      events.addAll(page.events);
      cursor = page.events.last.sequence;
      if (page.events.length < 256) break;
    }
    if (events.isEmpty) {
      throw const FormatException('Worker event replay returned no run truth.');
    }
    _checkDeadline(deadline);
    _requireBinding(binding);
    await runTruth.rebuildRunFromWorkerTruth(runId: runId, events: events);
    _checkDeadline(deadline);
    _requireBinding(binding);
  }

  void _checkDeadline(DateTime deadline) {
    if (!deadline.toUtc().isAfter(_utcNow().toUtc())) {
      throw TimeoutException('Supervisor event recovery deadline expired.');
    }
  }

  void _requireBinding(_ReplayBinding binding) {
    if (binding.cancelled || !identical(_replayBinding, binding)) {
      throw const CockpitJsonRpcPeerClosedException();
    }
  }
}

final class _ReplayBinding {
  _ReplayBinding({required this.connectionIdentity, required this.replay});

  final Object connectionIdentity;
  final CockpitSupervisorWorkerReplayClient replay;
  var cancelled = false;
}

CockpitJsonRpcRemoteException _endpointError(String code, String message) =>
    CockpitJsonRpcRemoteException(
      CockpitJsonRpcError(code: -32000, message: message, workerCode: code),
    );
