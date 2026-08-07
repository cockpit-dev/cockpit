import 'dart:io';

import 'package:cockpit/src/worker/cockpit_worker_application_support.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:path/path.dart' as p;
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
  test('artifact temp files remain confined to the producer root', () async {
    final stateDirectory = await Directory.systemTemp.createTemp(
      'cockpit_worker_artifact_factory_',
    );
    addTearDown(() async {
      if (await stateDirectory.exists()) {
        await stateDirectory.delete(recursive: true);
      }
    });
    final producerDirectory = await Directory(
      p.join(stateDirectory.path, 'producer'),
    ).create();
    await Directory(p.join(producerDirectory.path, 'tmp')).create();
    final producerRoot = p.normalize(
      await producerDirectory.resolveSymbolicLinks(),
    );

    final file = await cockpitWorkerArtifactTempFileFactory(producerRoot)(
      '../unsafe screenshot?.png',
    );

    expect(p.isWithin(p.join(producerRoot, 'tmp'), file.path), isTrue);
    expect(p.basename(file.path), 'unsafe_screenshot_.png');
    await file.writeAsBytes(const <int>[1, 2, 3], flush: true);
    expect(await file.readAsBytes(), const <int>[1, 2, 3]);
  });
}
