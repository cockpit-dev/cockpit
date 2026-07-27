import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_application_service_exception.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_protocol_result.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_value_reader.dart';

final class CockpitRpcResourceAuthorityClient
    implements CockpitWorkerResourceAuthorityClient {
  CockpitRpcResourceAuthorityClient({
    required this.workspaceId,
    required CockpitJsonRpcPeer peer,
    DateTime Function()? utcNow,
    Duration heartbeatTimeout = const Duration(minutes: 1),
    Duration releaseTimeout = const Duration(minutes: 1),
  }) : _peer = peer,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _heartbeatTimeout = heartbeatTimeout,
       _releaseTimeout = releaseTimeout {
    workerId(workspaceId, r'$.workspaceId');
    if (heartbeatTimeout <= Duration.zero || releaseTimeout <= Duration.zero) {
      throw ArgumentError('Resource authority RPC timeouts must be positive.');
    }
  }

  final String workspaceId;
  final CockpitJsonRpcPeer _peer;
  final DateTime Function() _utcNow;
  final Duration _heartbeatTimeout;
  final Duration _releaseTimeout;
  var _heartbeatSequence = 0;

  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async {
    if (workspaceId != this.workspaceId) {
      throw const CockpitApplicationServiceException(
        code: 'workspaceMismatch',
        message: 'Resource request belongs to another workspace.',
      );
    }
    final result = await _call(
      kind: 'resource.acquire',
      input: <String, Object?>{...request.toJson(), 'holderId': holderId},
      idempotencyKey: idempotencyKey,
      deadline: deadline,
    );
    return CockpitWorkerResourceGrant.fromJson(result.output!['grant']);
  }

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {
    _validateGrant(grant);
    await _call(
      kind: 'resource.heartbeat',
      input: <String, Object?>{'grantId': grant.grantId},
      idempotencyKey: '${grant.grantId}-heartbeat-${++_heartbeatSequence}',
      deadline: _utcNow().add(_heartbeatTimeout),
    );
  }

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {
    _validateGrant(grant);
    await _call(
      kind: 'resource.release',
      input: <String, Object?>{'grantId': grant.grantId, 'cancel': cancel},
      idempotencyKey: '${grant.grantId}-release',
      deadline: _utcNow().add(_releaseTimeout),
    );
  }

  Future<CockpitOperationResult> _call({
    required String kind,
    required Map<String, Object?> input,
    required String idempotencyKey,
    required DateTime deadline,
  }) async {
    final invocation = CockpitOperationInvocation(
      kind: kind,
      input: input,
      workspaceId: workspaceId,
      idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
      deadline: deadline,
    );
    final raw = await _peer.call(
      method: 'operation',
      params: <String, Object?>{
        'protocolVersion': cockpitWorkerProtocolVersion,
        'workspaceId': workspaceId,
        'idempotencyKey': idempotencyKey,
        'invocation': invocation.toJson(),
      },
      deadline: deadline,
    );
    final result = CockpitWorkerOperationResult.fromJson(raw).result;
    if (result.outcome != CockpitOperationOutcome.succeeded ||
        result.output == null) {
      throw const CockpitApplicationServiceException(
        code: 'resourceAuthorityFailed',
        message: 'Supervisor resource authority rejected the request.',
      );
    }
    return result;
  }

  void _validateGrant(CockpitWorkerResourceGrant grant) {
    if (grant.workspaceId != workspaceId) {
      throw const CockpitApplicationServiceException(
        code: 'workspaceMismatch',
        message: 'Resource grant belongs to another workspace.',
      );
    }
  }
}
