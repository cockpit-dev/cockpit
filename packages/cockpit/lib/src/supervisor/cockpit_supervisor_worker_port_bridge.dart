import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../worker/cockpit_worker_protocol_result.dart';
import '../worker/cockpit_worker_value_reader.dart';
import 'cockpit_lease_support.dart';
import 'cockpit_port_models.dart';
import 'cockpit_supervisor_port_ownership_inspector.dart';

typedef CockpitSupervisorWorkerPeerCall =
    Future<Object?> Function({
      required String method,
      required Map<String, Object?> params,
      required DateTime deadline,
    });

final class CockpitSupervisorWorkerPortBridge {
  CockpitSupervisorWorkerPortBridge({
    required this.workspaceId,
    required this.workerOwnerId,
    required this.workerProcessId,
    required this.processStartIdentity,
    required CockpitSupervisorWorkerPeerCall call,
    required CockpitSupervisorPortOwnershipInspector ownershipInspector,
  }) : _call = call,
       _ownershipInspector = ownershipInspector {
    workerId(workspaceId, r'$.workspaceId');
    workerId(workerOwnerId, r'$.workerOwnerId');
    workerString(processStartIdentity, r'$.processStartIdentity', maximum: 512);
    if (workerProcessId <= 0) {
      throw const FormatException('Worker process id is invalid.');
    }
  }

  final String workspaceId;
  final String workerOwnerId;
  final int workerProcessId;
  final String processStartIdentity;
  final CockpitSupervisorWorkerPeerCall _call;
  final CockpitSupervisorPortOwnershipInspector _ownershipInspector;
  final Map<String, CockpitExpectedPortOwner> _expectedOwners =
      <String, CockpitExpectedPortOwner>{};
  final Map<String, String> _handoffTokens = <String, String>{};
  var _sequence = 0;

  CockpitPortBinder binderFor(String grantId) {
    workerId(grantId, r'$.grantId');
    return _WorkerPeerPortBinder(this, grantId);
  }

  CockpitPortOwnerProbe ownerProbeFor(String grantId) {
    workerId(grantId, r'$.grantId');
    return _WorkerPeerPortOwnerProbe(this, grantId);
  }

  CockpitExpectedPortOwner expectedOwnerFor(
    String grantId, {
    required String sessionId,
  }) {
    workerId(grantId, r'$.grantId');
    workerId(sessionId, r'$.sessionId');
    final owner = CockpitExpectedPortOwner(
      ownerId: workerOwnerId,
      processId: workerProcessId,
      processStartIdentity: processStartIdentity,
      sessionId: sessionId,
    );
    _expectedOwners[grantId] = owner;
    return owner;
  }

  Future<void> _bind(String grantId, CockpitPortBindRequest request) async {
    final output = await _operation(
      kind: 'worker.port.bind',
      grantId: grantId,
      input: <String, Object?>{
        'grantId': grantId,
        'port': request.port,
        'handoffToken': request.handoffToken,
      },
      deadline: request.deadline,
    );
    if (output['bound'] != true) {
      throw const CockpitLeaseException(
        code: 'portWorkerBindFailed',
        message: 'Worker did not confirm the forwarded-port bind.',
      );
    }
    _handoffTokens[grantId] = request.handoffToken;
  }

  Future<CockpitObservedPortOwner?> _inspect(
    String grantId, {
    required int port,
    required DateTime deadline,
  }) async {
    final expected = _expectedOwners[grantId];
    final handoffToken = _handoffTokens[grantId];
    if (expected == null || handoffToken == null) {
      throw const CockpitLeaseException(
        code: 'portHandoffEvidenceMissing',
        message: 'Supervisor port handoff evidence is incomplete.',
      );
    }
    final evidence = await _ownershipInspector.inspect(
      address: InternetAddress.loopbackIPv4,
      port: port,
      deadline: deadline,
    );
    if (evidence == null) return null;
    // The authenticated bind callback completes only after the worker has
    // launched and verified the requested session. Desktop applications and
    // mobile forwarding tools are intentionally not worker descendants, so
    // process ancestry is diagnostic rather than handoff authority.
    return CockpitObservedPortOwner(
      ownerId: expected.ownerId,
      processId: expected.processId,
      processStartIdentity: expected.processStartIdentity,
      sessionId: expected.sessionId,
      handoffToken: handoffToken,
    );
  }

  Future<Map<String, Object?>> _operation({
    required String kind,
    required String grantId,
    required Map<String, Object?> input,
    required DateTime deadline,
  }) async {
    final idempotencyKey = 'port-${++_sequence}-$grantId';
    final raw = await _call(
      method: 'operation',
      params: <String, Object?>{
        'protocolVersion': cockpitWorkerProtocolVersion,
        'workspaceId': workspaceId,
        'idempotencyKey': idempotencyKey,
        'invocation': CockpitOperationInvocation(
          kind: kind,
          input: input,
          workspaceId: workspaceId,
          idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
          deadline: deadline,
        ).toJson(),
      },
      deadline: deadline,
    );
    final result = CockpitWorkerOperationResult.fromJson(raw).result;
    if (result.outcome != CockpitOperationOutcome.succeeded ||
        result.output == null) {
      throw const CockpitLeaseException(
        code: 'portWorkerOperationFailed',
        message: 'Worker port handoff operation failed.',
      );
    }
    return result.output!;
  }
}

final class _WorkerPeerPortBinder implements CockpitPortBinder {
  const _WorkerPeerPortBinder(this.bridge, this.grantId);

  final CockpitSupervisorWorkerPortBridge bridge;
  final String grantId;

  @override
  Future<void> bind(CockpitPortBindRequest request) =>
      bridge._bind(grantId, request);
}

final class _WorkerPeerPortOwnerProbe implements CockpitPortOwnerProbe {
  const _WorkerPeerPortOwnerProbe(this.bridge, this.grantId);

  final CockpitSupervisorWorkerPortBridge bridge;
  final String grantId;

  @override
  Future<CockpitObservedPortOwner?> inspect({
    required InternetAddress address,
    required int port,
    required DateTime deadline,
  }) => bridge._inspect(grantId, port: port, deadline: deadline);
}
