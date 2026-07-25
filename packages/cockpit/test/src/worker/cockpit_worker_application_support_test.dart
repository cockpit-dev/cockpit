import 'package:cockpit/src/worker/cockpit_worker_application_support.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:test/test.dart';

void main() {
  test('transactional launch rolls back when commit fails', () async {
    var rolledBack = false;

    await expectLater(
      runWorkerTransactionalLaunch<int, void>(
        launch: () async => 42,
        commit: (_) async => throw StateError('commit failed'),
        rollback: (launched) async {
          expect(launched, 42);
          rolledBack = true;
        },
      ),
      throwsStateError,
    );

    expect(rolledBack, isTrue);
  });

  test('application launch rolls back cancellation after activation', () async {
    final cancellation = CockpitRpcCancellation.detached();
    final context = CockpitWorkspaceOperationContext(
      workspaceId: 'workspaceA',
      workspaceRoot: '/workspace',
      requestId: 'requestA',
      deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      idempotencyKey: 'launch-cancel',
      requiredFeatures: const <String>[],
      cancellation: cancellation,
    );
    var committed = false;
    var rolledBack = false;

    await expectLater(
      runWorkerTransactionalApplicationLaunch<int, void>(
        context: context,
        launch: () async {
          cancellation.cancel();
          return 42;
        },
        commit: (_) async {
          committed = true;
        },
        rollback: (launched) async {
          expect(launched, 42);
          rolledBack = true;
        },
      ),
      throwsA(isA<CockpitRpcCancelledException>()),
    );

    expect(committed, isFalse);
    expect(rolledBack, isTrue);
  });
}
