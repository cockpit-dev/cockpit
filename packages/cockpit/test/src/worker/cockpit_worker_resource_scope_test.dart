import 'dart:async';

import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_scope.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('heartbeat failures remain observable before the first guard', () async {
    final authority = _FailingHeartbeatAuthority();
    final scope = await CockpitWorkerResourceScope.acquire(
      authority: authority,
      cancellation: CockpitRpcCancellation.detached(),
      requests: <CockpitWorkerResourceRequest>[
        CockpitWorkerResourceRequest(
          resourceKind: CockpitLeaseResourceKind.session,
          resourceId: 'session_resource',
          ttl: const Duration(seconds: 1),
        ),
      ],
      workspaceId: 'workspace_resource_scope',
      holderId: 'holder_resource_scope',
      idempotencyKey: 'resource_scope_test',
      deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );
    addTearDown(() => scope.close(cancel: true));

    await authority.heartbeatAttempted.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await expectLater(
      scope.guard(Completer<void>().future),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'heartbeat failed',
        ),
      ),
    );
  });
}

final class _FailingHeartbeatAuthority
    implements CockpitWorkerResourceAuthorityClient {
  final Completer<void> heartbeatAttempted = Completer<void>();

  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async => CockpitWorkerResourceGrant(
    grantId: 'grant_resource_scope',
    leaseId: 'lease_resource_scope',
    workspaceId: workspaceId,
    holderId: holderId,
    resourceKind: request.resourceKind,
    resourceId: request.resourceId,
    expiresAt: deadline,
  );

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {
    if (!heartbeatAttempted.isCompleted) heartbeatAttempted.complete();
    throw StateError('heartbeat failed');
  }

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {}
}
