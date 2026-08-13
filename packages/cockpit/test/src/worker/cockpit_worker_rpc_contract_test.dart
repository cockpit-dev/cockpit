import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_inspect_surface_service.dart';
import 'package:cockpit/src/application/cockpit_inspect_ui_service.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_worker_endpoint.dart';
import 'package:cockpit/src/supervisor/cockpit_worker_resource_authority.dart';
import 'package:cockpit/src/targets/cockpit_target_handle.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_message.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_case_run_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_memory_event_exchange.dart';
import 'package:cockpit/src/worker/cockpit_worker_operation_journal.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_request.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_schema.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_server.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:cockpit/src/worker/cockpit_worker_interactive_operations.dart';
import 'package:cockpit/src/worker/cockpit_workspace_application_adapters.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const workspaceId = 'workspaceA';
  const engineVersion = 'engineA';
  const workspaceRoot = '/workspace/a';

  group('shared worker RPC corpus', () {
    for (final invalid in _invalidEnvelopeCorpus) {
      test('worker endpoint rejects ${invalid.name}', () async {
        final server = CockpitWorkerServer(
          workspaceId: workspaceId,
          engineVersion: engineVersion,
          workspaceRoot: workspaceRoot,
          supportedFeatures: const <String>['featureA'],
          operations: const _TestOperationDispatcher(),
          events: CockpitWorkerMemoryEventExchange(),
        );
        final harness = _PeerHarness(server.handle);
        server.bindPeer(harness.server);
        harness.start();
        addTearDown(harness.close);
        await _initialize(
          harness.client,
          workspaceId: workspaceId,
          engineVersion: engineVersion,
          workspaceRoot: workspaceRoot,
        );

        await expectLater(
          harness.client.call(
            method: 'capabilities',
            params: invalid.apply(<String, Object?>{
              'protocolVersion': cockpitWorkerProtocolVersion,
              'workspaceId': workspaceId,
              'idempotencyKey': 'capabilities-${invalid.name}',
            }),
            deadline: _deadline(),
          ),
          throwsA(
            isA<CockpitJsonRpcRemoteException>().having(
              (error) => error.error.workerCode,
              'workerCode',
              invalid.workerCode,
            ),
          ),
        );
      });

      test('Supervisor endpoint rejects ${invalid.name}', () async {
        final endpoint = CockpitSupervisorWorkerEndpoint(
          workspaceId: workspaceId,
          events: CockpitWorkerMemoryEventExchange(),
          resourceAuthority: const _TestResourceAuthority(),
        );
        final harness = _PeerHarness(endpoint.handle)..start();
        addTearDown(harness.close);
        final deadline = _deadline();
        final key = 'resource-${invalid.name}';
        final invocation = CockpitOperationInvocation(
          kind: 'resource.heartbeat',
          workspaceId: workspaceId,
          idempotencyKey: CockpitIdempotencyKey(key),
          deadline: deadline,
          input: const <String, Object?>{'grantId': 'grantA'},
        );

        await expectLater(
          harness.client.call(
            method: 'operation',
            params: invalid.apply(<String, Object?>{
              'protocolVersion': cockpitWorkerProtocolVersion,
              'workspaceId': workspaceId,
              'idempotencyKey': key,
              'invocation': invocation.toJson(),
            }),
            deadline: deadline,
          ),
          throwsA(
            isA<CockpitJsonRpcRemoteException>().having(
              (error) => error.error.workerCode,
              'workerCode',
              invalid.workerCode,
            ),
          ),
        );
      });
    }
  });

  group('bidirectional peer contract corpus', () {
    for (final direction in const <_ContractDirection>[
      _ContractDirection.worker(),
      _ContractDirection.supervisor(),
    ]) {
      test('${direction.name} rejects unknown methods', () async {
        final harness = direction.openRaw();
        harness.start();
        addTearDown(harness.close);
        final response = await harness.send(
          CockpitJsonRpcRequest(
            id: 'unknownA',
            method: 'unknownMethod',
            params: const <String, Object?>{},
          ),
        );
        expect(response.error?.workerCode, 'methodNotFound');
      });

      test('${direction.name} rejects duplicate request ids', () async {
        final harness = direction.open();
        await harness.start();
        addTearDown(harness.close);
        expect(
          CockpitWorkerPublishEventBatchResult.fromJson(
            await harness.peer.call(
              method: 'publishEventBatch',
              params: _publishParams(
                key: 'duplicate-first',
                runId: 'runDuplicate',
                afterSequence: 0,
                eventSequence: 1,
              ),
              deadline: _deadline(),
              requestId: 'duplicateA',
            ),
          ).highestContiguousSequence,
          1,
        );
        await expectLater(
          harness.peer.call(
            method: 'publishEventBatch',
            params: _publishParams(
              key: 'duplicate-second',
              runId: 'runDuplicateOther',
              afterSequence: 0,
              eventSequence: 1,
            ),
            deadline: _deadline(),
            requestId: 'duplicateA',
          ),
          throwsA(_remoteCode('duplicateRequestId')),
        );
      });

      test(
        '${direction.name} permits unrelated calls during timeout cleanup',
        () async {
          final protocolErrors = <Object>[];
          final harness = direction.open(
            decorate: (base) => (request, cancellation) async {
              if (request.id == 'lateA') {
                await Future<void>.delayed(const Duration(milliseconds: 80));
              }
              return base(request, cancellation);
            },
            receiverUtcNow: () =>
                DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
            callerProtocolError: (error, _) => protocolErrors.add(error),
          );
          await harness.start();
          addTearDown(harness.close);
          var completed = false;
          final call = harness.peer.call(
            method: 'publishEventBatch',
            params: _publishParams(
              key: 'late',
              runId: 'runLate',
              afterSequence: 0,
              eventSequence: 1,
            ),
            deadline: DateTime.now().toUtc().add(
              const Duration(milliseconds: 20),
            ),
            requestId: 'lateA',
          );
          unawaited(
            call.then<void>(
              (_) => completed = true,
              onError: (_, _) => completed = true,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(completed, isFalse);
          expect(harness.peer.isOutboundCleanupPending, isTrue);
          expect(
            CockpitWorkerPublishEventBatchResult.fromJson(
              await harness.peer.call(
                method: 'publishEventBatch',
                params: _publishParams(
                  key: 'during-cleanup',
                  runId: 'runDuringCleanup',
                  afterSequence: 0,
                  eventSequence: 1,
                ),
                deadline: _deadline(),
              ),
            ).highestContiguousSequence,
            1,
          );
          expect(harness.peer.isOutboundCleanupPending, isTrue);
          await expectLater(call, throwsA(isA<TimeoutException>()));
          expect(protocolErrors, isEmpty);
          expect(harness.peer.isOutboundCleanupPending, isFalse);
          expect(
            CockpitWorkerPublishEventBatchResult.fromJson(
              await harness.peer.call(
                method: 'publishEventBatch',
                params: _publishParams(
                  key: 'after-late',
                  runId: 'runAfterLate',
                  afterSequence: 0,
                  eventSequence: 1,
                ),
                deadline: _deadline(),
              ),
            ).highestContiguousSequence,
            1,
          );
        },
      );

      test(
        '${direction.name} closes when terminal cleanup never arrives',
        () async {
          final never = Completer<Object?>();
          final harness = direction.open(
            decorate: (base) =>
                (request, cancellation) => request.id == 'neverA'
                ? never.future
                : base(request, cancellation),
            clientCancellationGrace: const Duration(milliseconds: 5),
            clientForcedAbortGrace: const Duration(milliseconds: 20),
          );
          await harness.start();
          addTearDown(harness.close);
          final call = harness.peer.call(
            method: 'publishEventBatch',
            params: _publishParams(
              key: 'never-terminal',
              runId: 'runNeverTerminal',
              afterSequence: 0,
              eventSequence: 1,
            ),
            deadline: DateTime.now().toUtc().add(
              const Duration(milliseconds: 10),
            ),
            requestId: 'neverA',
          );
          await expectLater(call, throwsA(isA<TimeoutException>()));
          await harness.peer.done;
          expect(harness.peer.isClosed, isTrue);
        },
      );

      test('${direction.name} resolves cancellation races once', () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final protocolErrors = <Object>[];
        final harness = direction.open(
          decorate: (base) => (request, cancellation) async {
            if (request.id == 'cancelRaceA') {
              entered.complete();
              await Future.any<void>(<Future<void>>[
                release.future,
                cancellation.whenCancelled,
              ]);
              cancellation.throwIfCancelled();
            }
            return base(request, cancellation);
          },
          callerProtocolError: (error, _) => protocolErrors.add(error),
        );
        await harness.start();
        addTearDown(harness.close);
        final call = harness.peer.call(
          method: 'publishEventBatch',
          params: _publishParams(
            key: 'cancel-race',
            runId: 'runCancelRace',
            afterSequence: 0,
            eventSequence: 1,
          ),
          deadline: _deadline(),
          requestId: 'cancelRaceA',
        );
        await entered.future;
        expect(
          harness.receiver.cancelInbound('cancelRaceA'),
          CockpitRpcCancellationResult.cancelled,
        );
        release.complete();
        await expectLater(call, throwsA(_remoteCode('cancelled')));
        expect(harness.receiver.activeInboundRequestCount, 0);
        expect(protocolErrors, isEmpty);
        expect(
          CockpitWorkerPublishEventBatchResult.fromJson(
            await harness.peer.call(
              method: 'publishEventBatch',
              params: _publishParams(
                key: 'after-cancel',
                runId: 'runAfterCancel',
                afterSequence: 0,
                eventSequence: 1,
              ),
              deadline: _deadline(),
            ),
          ).highestContiguousSequence,
          1,
        );
      });

      test('${direction.name} reports event gaps', () async {
        final harness = direction.open();
        await harness.start();
        addTearDown(harness.close);
        final first = CockpitWorkerPublishEventBatchResult.fromJson(
          await harness.peer.call(
            method: 'publishEventBatch',
            params: _publishParams(
              key: 'event-first',
              runId: 'runGap',
              afterSequence: 0,
              eventSequence: 1,
            ),
            deadline: _deadline(),
          ),
        );
        expect(first.highestContiguousSequence, 1);
        expect(first.replayAfterSequence, isNull);
        final gapCall = harness.peer.call(
          method: 'publishEventBatch',
          params: _publishParams(
            key: 'event-gap',
            runId: 'runGap',
            afterSequence: 2,
            eventSequence: 3,
          ),
          deadline: _deadline(),
        );
        if (direction.worker) {
          final gap = CockpitWorkerPublishEventBatchResult.fromJson(
            await gapCall,
          );
          expect(gap.highestContiguousSequence, 1);
          expect(gap.replayAfterSequence, 1);
        } else {
          await expectLater(
            gapCall,
            throwsA(_remoteCode('eventReplayUnavailable')),
          );
        }
      });

      test('${direction.name} enforces event replay direction', () async {
        final harness = direction.open();
        await harness.start();
        addTearDown(harness.close);
        await harness.peer.call(
          method: 'publishEventBatch',
          params: _publishParams(
            key: 'replay-source',
            runId: 'runReplayDirection',
            afterSequence: 0,
            eventSequence: 1,
          ),
          deadline: _deadline(),
        );
        final replay = harness.peer.call(
          method: 'replayEvents',
          params: <String, Object?>{
            'protocolVersion': cockpitWorkerProtocolVersion,
            'workspaceId': 'workspaceA',
            'idempotencyKey': 'replay-direction',
            'runId': 'runReplayDirection',
            'afterSequence': 0,
          },
          deadline: _deadline(),
        );
        if (direction.worker) {
          expect(
            CockpitWorkerReplayEventsResult.fromJson(await replay).events,
            hasLength(1),
          );
        } else {
          await expectLater(replay, throwsA(_remoteCode('methodUnavailable')));
        }
      });

      test(
        '${direction.name} enforces artifact publication direction',
        () async {
          final harness = direction.open();
          await harness.start();
          addTearDown(harness.close);
          final publication = harness.peer.call(
            method: 'publishArtifactBatch',
            params: _artifactPublishParams(),
            deadline: _deadline(),
          );
          if (direction.worker) {
            await expectLater(
              publication,
              throwsA(_remoteCode('methodUnavailable')),
            );
          } else {
            final result = CockpitWorkerPublishArtifactBatchResult.fromJson(
              await publication,
            );
            expect(result.runId, 'runArtifactDirection');
            expect(result.artifactIds, <String>['artifactDirection']);
          }
        },
      );
    }
  });

  test('artifact publication requires strict project and case identity', () {
    final params = <String, Object?>{
      ..._artifactPublishParams(),
      'requestId': 'artifact-strict',
      'deadline': _deadline().toIso8601String(),
    };
    final decoded = CockpitWorkerPublishArtifactBatchRequest.fromJson(params);
    expect(decoded.projectId, 'projectA');
    expect(decoded.caseId, 'caseA');
    CockpitWorkerProtocolSchema.validateRequest('publishArtifactBatch', params);
    for (final field in const <String>['projectId', 'caseId']) {
      final missing = <String, Object?>{...params}..remove(field);
      expect(
        () => CockpitWorkerPublishArtifactBatchRequest.fromJson(missing),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CockpitWorkerProtocolSchema.validateRequest(
          'publishArtifactBatch',
          missing,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'worker negotiates capabilities without advertising internal routes',
    () async {
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>['featureA', 'featureB'],
        operations: const _TestOperationDispatcher(),
        events: CockpitWorkerMemoryEventExchange(),
      );
      final harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);
      await _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
      );

      final raw = await harness.client.call(
        method: 'capabilities',
        params: const <String, Object?>{
          'protocolVersion': cockpitWorkerProtocolVersion,
          'workspaceId': workspaceId,
          'idempotencyKey': 'capabilities-valid',
        },
        deadline: _deadline(),
      );
      final result = CockpitWorkerCapabilitiesResult.fromJson(raw);
      expect(result.operationKinds, const <String>['analyze.workspace']);
      expect(result.features, const <String>['featureA']);
      expect(result.operationKinds, isNot(contains('worker.port.bind')));
    },
  );

  test(
    'worker keeps recovery atomic across concurrent initialization',
    () async {
      final recoveryEntered = Completer<void>();
      final releaseRecovery = Completer<void>();
      var recoveryCalls = 0;
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>['featureA', 'featureB'],
        operations: const _TestOperationDispatcher(),
        events: CockpitWorkerMemoryEventExchange(),
        onInitialized: () async {
          recoveryCalls += 1;
          recoveryEntered.complete();
          await releaseRecovery.future;
        },
      );
      final harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);

      final primary = _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        idempotencyKey: 'initialize-primary',
      );
      await recoveryEntered.future;
      expect(server.isInitialized, isFalse);
      final recoveryReplay = CockpitWorkerReplayEventsResult.fromJson(
        await harness.client.call(
          method: 'replayEvents',
          params: const <String, Object?>{
            'protocolVersion': cockpitWorkerProtocolVersion,
            'workspaceId': workspaceId,
            'idempotencyKey': 'replay-during-recovery',
            'runId': 'runRecovery',
            'afterSequence': 0,
          },
          deadline: _deadline(),
        ),
      );
      expect(recoveryReplay.runId, 'runRecovery');
      expect(recoveryReplay.events, isEmpty);
      await expectLater(
        harness.client.call(
          method: 'capabilities',
          params: const <String, Object?>{
            'protocolVersion': cockpitWorkerProtocolVersion,
            'workspaceId': workspaceId,
            'idempotencyKey': 'capabilities-during-recovery',
          },
          deadline: _deadline(),
        ),
        throwsA(_remoteCode('notInitialized')),
      );
      await expectLater(
        _callOperation(
          harness.client,
          CockpitOperationInvocation(
            kind: 'analyze.workspace',
            workspaceId: workspaceId,
            idempotencyKey: CockpitIdempotencyKey('operation-during-recovery'),
            deadline: _deadline(),
          ),
        ),
        throwsA(_remoteCode('notInitialized')),
      );
      await expectLater(
        harness.client.call(
          method: 'drain',
          params: <String, Object?>{
            'protocolVersion': cockpitWorkerProtocolVersion,
            'workspaceId': workspaceId,
            'idempotencyKey': 'drain-during-recovery',
            'deadline': _deadline().toIso8601String(),
          },
          deadline: _deadline(),
        ),
        throwsA(_remoteCode('notInitialized')),
      );

      final follower = _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        idempotencyKey: 'initialize-follower',
      );
      await expectLater(
        _initialize(
          harness.client,
          workspaceId: workspaceId,
          engineVersion: engineVersion,
          workspaceRoot: workspaceRoot,
          supportedFeatures: const <String>['featureB'],
          idempotencyKey: 'initialize-conflict',
        ),
        throwsA(_remoteCode('initializeConflict')),
      );
      await expectLater(
        _initialize(
          harness.client,
          workspaceId: workspaceId,
          engineVersion: 'engineB',
          workspaceRoot: workspaceRoot,
          idempotencyKey: 'initialize-identity-conflict',
        ),
        throwsA(_remoteCode('workerIdentityMismatch')),
      );
      expect(recoveryCalls, 1);

      releaseRecovery.complete();
      await Future.wait<void>(<Future<void>>[primary, follower]);
      expect(server.isInitialized, isTrue);
      expect(recoveryCalls, 1);
    },
  );

  test('worker retries initialization after recovery fails', () async {
    var failRecovery = true;
    var recoveryCalls = 0;
    final server = CockpitWorkerServer(
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>['featureA'],
      operations: const _TestOperationDispatcher(),
      events: CockpitWorkerMemoryEventExchange(),
      onInitialized: () {
        recoveryCalls += 1;
        if (failRecovery) throw StateError('simulated recovery failure');
      },
    );
    final harness = _PeerHarness(server.handle);
    server.bindPeer(harness.server);
    harness.start();
    addTearDown(harness.close);

    await expectLater(
      _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        idempotencyKey: 'initialize-failing-recovery',
      ),
      throwsA(_remoteCode('internalError')),
    );
    expect(server.isInitialized, isFalse);
    expect(recoveryCalls, 1);
    await expectLater(
      harness.client.call(
        method: 'replayEvents',
        params: const <String, Object?>{
          'protocolVersion': cockpitWorkerProtocolVersion,
          'workspaceId': workspaceId,
          'idempotencyKey': 'replay-after-failed-recovery',
          'runId': 'runRecovery',
          'afterSequence': 0,
        },
        deadline: _deadline(),
      ),
      throwsA(_remoteCode('notInitialized')),
    );

    failRecovery = false;
    await _initialize(
      harness.client,
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      idempotencyKey: 'initialize-retry',
    );
    expect(server.isInitialized, isTrue);
    expect(recoveryCalls, 2);
  });

  test('worker rejects operation features that were not negotiated', () async {
    final server = CockpitWorkerServer(
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>['featureA', 'featureB'],
      operations: const _TestOperationDispatcher(),
      events: CockpitWorkerMemoryEventExchange(),
    );
    final harness = _PeerHarness(server.handle);
    server.bindPeer(harness.server);
    harness.start();
    addTearDown(harness.close);
    await _initialize(
      harness.client,
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
    );
    final deadline = _deadline();
    const key = 'missing-feature';

    await expectLater(
      harness.client.call(
        method: 'operation',
        params: <String, Object?>{
          'protocolVersion': cockpitWorkerProtocolVersion,
          'workspaceId': workspaceId,
          'idempotencyKey': key,
          'invocation': CockpitOperationInvocation(
            kind: 'analyze.workspace',
            workspaceId: workspaceId,
            idempotencyKey: CockpitIdempotencyKey(key),
            deadline: deadline,
            requiredFeatures: const <String>['featureB'],
          ).toJson(),
        },
        deadline: deadline,
      ),
      throwsA(_remoteCode('requiredFeatureMissing')),
    );
  });

  test(
    'safe reads stay unleased while same-session mutations remain exclusive',
    () async {
      final backend = _ReadMutationBackend();
      final resolver = _ReadMutationResourceResolver();
      final authority = _ExclusiveSessionResourceAuthority();
      final adapters = CockpitWorkspaceApplicationAdapters(
        workspaceId: workspaceId,
        backend: backend,
        resourceResolver: resolver,
      ).create();
      for (final kind in const <String>{
        'app.get',
        'target.get',
        'target.inspect',
        'session.remote.get',
        'session.remote.status',
        'snapshot.remote.read',
        'session.development.get',
        'ui.inspect',
        'surface.inspect',
        'logs.read',
        'network.read',
        'errors.read',
        'session.logs.read',
      }) {
        expect(
          adapters.singleWhere((adapter) => adapter.kind == kind).mutationClass,
          CockpitMutationClass.readOnly,
          reason: kind,
        );
      }
      expect(
        adapters
            .singleWhere((adapter) => adapter.kind == 'command.run')
            .mutationClass,
        CockpitMutationClass.mutating,
      );
      final registry = CockpitWorkspaceOperationRegistry(
        workspaceId: workspaceId,
        workspaceRoot: workspaceRoot,
        adapters: adapters,
        resourceAuthority: authority,
        operationJournal: CockpitInMemoryWorkerOperationJournal(),
        terminateUnsafeWorker: () async {},
      );
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
        operations: registry,
        events: CockpitWorkerMemoryEventExchange(),
      );
      final harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);
      await _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
      );

      final read = _callOperation(
        harness.client,
        _applicationInvocation('session.remote.status', 'unleased-read'),
      );
      await backend.readEntered.future;
      final mutation = _callOperation(
        harness.client,
        _applicationInvocation('command.run', 'session-mutation'),
      );
      await backend.mutationEntered.future.timeout(const Duration(seconds: 1));

      backend.releaseRead.complete();
      final results = await Future.wait<CockpitOperationResult>(
        <Future<CockpitOperationResult>>[read, mutation],
      );
      expect(
        results.map((result) => result.outcome),
        everyElement(CockpitOperationOutcome.succeeded),
      );
      expect(backend.mutationEntered.isCompleted, isTrue);
      expect(authority.sessionAcquisitions, <String>['session_resource_A']);

      final registryRead = await _callOperation(
        harness.client,
        _applicationInvocation(
          'app.list',
          'local-app-list',
          input: const <String, Object?>{},
        ),
      );
      final localCompare = await _callOperation(
        harness.client,
        _applicationInvocation(
          'development.probe.compare',
          'local-probe-compare',
        ),
      );
      final networkBody = await _callOperation(
        harness.client,
        _applicationInvocation(
          'network.body',
          'network-body-capture-grant',
          input: const <String, Object?>{
            'sessionId': 'sessionA',
            'requestId': '37',
            'body': 'response',
          },
        ),
      );
      final screenshot = await _callOperation(
        harness.client,
        _applicationInvocation(
          'evidence.screenshot.capture',
          'screenshot-device-capture-grants',
        ),
      );
      expect(registryRead.outcome, CockpitOperationOutcome.succeeded);
      expect(localCompare.outcome, CockpitOperationOutcome.succeeded);
      expect(networkBody.outcome, CockpitOperationOutcome.succeeded);
      expect(screenshot.outcome, CockpitOperationOutcome.succeeded);
      expect(resolver.resolvedKinds, <String>[
        'command.run',
        'network.body',
        'evidence.screenshot.capture',
      ]);
      expect(backend.grantCountByKind['session.remote.status'], 0);
      expect(backend.grantCountByKind['app.list'], 0);
      expect(backend.grantCountByKind['development.probe.compare'], 0);
      final screenshotRequests = authority.requests.where(
        (request) =>
            request.wait != null &&
            (request.resourceKind == CockpitLeaseResourceKind.device ||
                request.resourceKind == CockpitLeaseResourceKind.capture),
      );
      expect(screenshotRequests, hasLength(2));
      expect(
        screenshotRequests.map((request) => request.wait),
        everyElement(const Duration(seconds: 3)),
      );
    },
  );

  test(
    'resource authority failures preserve Supervisor error details',
    () async {
      final authority = _RejectingResourceAuthority();
      final registry = CockpitWorkspaceOperationRegistry(
        workspaceId: workspaceId,
        workspaceRoot: workspaceRoot,
        adapters: <CockpitWorkspaceOperationAdapter>[
          CockpitWorkspaceOperationAdapter(
            kind: 'device.busy',
            mutationClass: CockpitMutationClass.mutating,
            resourceKinds: const <String>['workspace.device'],
            prepare: (context, input) => CockpitPreparedWorkspaceOperation(
              resources: <CockpitWorkerResourceRequest>[
                CockpitWorkerResourceRequest(
                  resourceKind: CockpitLeaseResourceKind.device,
                  resourceId: 'device_resource_A',
                  wait: const Duration(seconds: 3),
                ),
              ],
              execute: (_) async => const <String, Object?>{},
            ),
          ),
        ],
        resourceAuthority: authority,
        operationJournal: CockpitInMemoryWorkerOperationJournal(),
        terminateUnsafeWorker: () async {},
      );
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
        operations: registry,
        events: CockpitWorkerMemoryEventExchange(),
      );
      final harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);
      await _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
      );

      final result = await _callOperation(
        harness.client,
        _applicationInvocation('device.busy', 'device-busy'),
      );

      expect(result.outcome, CockpitOperationOutcome.failed);
      expect(result.failure?.primary.code, CockpitErrorCode.resourceBusy);
      expect(result.failure?.primary.category, CockpitErrorCategory.resource);
      expect(
        result.failure?.primary.responsibleLayer,
        CockpitResponsibleLayer.supervisor,
      );
      expect(result.failure?.primary.retryable, isTrue);
      expect(result.failure?.primary.redactedDetails['lease'], isNotNull);
    },
  );

  test('development probe collection is a leased journaled mutation', () async {
    final backend = _ProbeBackend();
    final resolver = _ProbeResourceResolver();
    final authority = _RecordingResourceAuthority();
    final journal = CockpitInMemoryWorkerOperationJournal();
    final adapters = CockpitWorkspaceApplicationAdapters(
      workspaceId: workspaceId,
      backend: backend,
      resourceResolver: resolver,
    ).create();
    final probeAdapter = adapters.singleWhere(
      (adapter) => adapter.kind == 'development.probe.collect',
    );
    expect(probeAdapter.mutationClass, CockpitMutationClass.mutating);
    expect(probeAdapter.resourceKinds, const <String>['workspace.probes']);
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: adapters,
      resourceAuthority: authority,
      operationJournal: journal,
      terminateUnsafeWorker: () async {},
    );
    final server = CockpitWorkerServer(
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>[],
      operations: registry,
      events: CockpitWorkerMemoryEventExchange(),
    );
    final harness = _PeerHarness(server.handle);
    server.bindPeer(harness.server);
    harness.start();
    addTearDown(harness.close);
    await _initialize(
      harness.client,
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>[],
    );
    final invocation = _probeInvocation('probe-completed');

    final first = await _callOperation(harness.client, invocation);
    final replay = await _callOperation(harness.client, invocation);

    expect(first.outcome, CockpitOperationOutcome.succeeded);
    expect(replay.toJson(), first.toJson());
    expect(backend.recordCount, 1);
    expect(resolver.resolveCount, 1);
    expect(
      authority.requests.map((request) => request.resourceKind),
      <CockpitLeaseResourceKind>[CockpitLeaseResourceKind.session],
    );
    expect(authority.releaseCount, 1);
  });

  test('completed application failure releases leases normally', () async {
    final authority = _RecordingResourceAuthority();
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: <CockpitWorkspaceOperationAdapter>[
        CockpitWorkspaceOperationAdapter(
          kind: 'read.failure',
          mutationClass: CockpitMutationClass.readOnly,
          resourceKinds: const <String>['workspace.readFailure'],
          prepare: (context, input) => CockpitPreparedWorkspaceOperation(
            resources: <CockpitWorkerResourceRequest>[
              CockpitWorkerResourceRequest(
                resourceKind: CockpitLeaseResourceKind.device,
                resourceId: 'device_resource_A',
                ttl: Duration(seconds: 30),
              ),
            ],
            execute: (_) => throw CockpitApplicationServiceException(
              code: 'expectedFailure',
              message: 'The read completed with an application failure.',
            ),
          ),
        ),
      ],
      resourceAuthority: authority,
      operationJournal: CockpitInMemoryWorkerOperationJournal(),
      terminateUnsafeWorker: () async {},
    );
    final result = await registry.execute(
      CockpitOperationInvocation(
        kind: 'read.failure',
        workspaceId: workspaceId,
        deadline: _deadline(),
      ),
      requestId: 'request-read-failure',
      cancellation: CockpitRpcCancellation.detached(),
    );

    expect(result.outcome, CockpitOperationOutcome.failed);
    expect(result.failure?.primary.code, 'expectedFailure');
    expect(authority.releaseCancellations, <bool>[false]);
  });

  test('invalid worker input is reported as invalid request', () async {
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: <CockpitWorkspaceOperationAdapter>[
        CockpitWorkspaceOperationAdapter(
          kind: 'read.invalidInput',
          mutationClass: CockpitMutationClass.readOnly,
          resourceKinds: const <String>[],
          prepare: (context, input) => CockpitPreparedWorkspaceOperation(
            resources: const <CockpitWorkerResourceRequest>[],
            execute: (_) => throw const FormatException(
              r'Invalid integer at $.input.timeoutMs.',
            ),
          ),
        ),
      ],
      resourceAuthority: _RecordingResourceAuthority(),
      operationJournal: CockpitInMemoryWorkerOperationJournal(),
      terminateUnsafeWorker: () async {},
    );

    final result = await registry.execute(
      CockpitOperationInvocation(
        kind: 'read.invalidInput',
        workspaceId: workspaceId,
        deadline: _deadline(),
      ),
      requestId: 'request-invalid-input',
      cancellation: CockpitRpcCancellation.detached(),
    );

    expect(result.outcome, CockpitOperationOutcome.failed);
    expect(result.failure?.primary.code, CockpitErrorCode.invalidRequest);
    expect(result.failure?.primary.category, CockpitErrorCategory.invalidInput);
    expect(result.failure?.primary.message, contains('timeoutMs'));
  });

  test('internal failure cancels resource leases', () async {
    final authority = _RecordingResourceAuthority();
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: <CockpitWorkspaceOperationAdapter>[
        CockpitWorkspaceOperationAdapter(
          kind: 'read.internalFailure',
          mutationClass: CockpitMutationClass.readOnly,
          resourceKinds: const <String>['workspace.internalFailure'],
          prepare: (context, input) => CockpitPreparedWorkspaceOperation(
            resources: <CockpitWorkerResourceRequest>[
              CockpitWorkerResourceRequest(
                resourceKind: CockpitLeaseResourceKind.device,
                resourceId: 'device_resource_A',
                ttl: Duration(seconds: 30),
              ),
            ],
            execute: (_) => throw StateError('unexpected internal failure'),
          ),
        ),
      ],
      resourceAuthority: authority,
      operationJournal: CockpitInMemoryWorkerOperationJournal(),
      terminateUnsafeWorker: () async {},
    );

    final result = await registry.execute(
      CockpitOperationInvocation(
        kind: 'read.internalFailure',
        workspaceId: workspaceId,
        deadline: _deadline(),
      ),
      requestId: 'request-internal-failure',
      cancellation: CockpitRpcCancellation.detached(),
    );

    expect(result.failure?.primary.category, CockpitErrorCategory.internal);
    expect(authority.releaseCancellations, <bool>[true]);
  });

  test('rollback cleanup failure cancels resource leases', () async {
    final authority = _RecordingResourceAuthority();
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: <CockpitWorkspaceOperationAdapter>[
        CockpitWorkspaceOperationAdapter(
          kind: 'mutation.rollbackFailure',
          mutationClass: CockpitMutationClass.mutating,
          resourceKinds: const <String>['workspace.rollbackFailure'],
          prepare: (context, input) => CockpitPreparedWorkspaceOperation(
            resources: <CockpitWorkerResourceRequest>[
              CockpitWorkerResourceRequest(
                resourceKind: CockpitLeaseResourceKind.device,
                resourceId: 'device_resource_A',
                ttl: Duration(seconds: 30),
              ),
            ],
            execute: (_) => throw CockpitWorkerOperationRollbackException(
              primary: CockpitApplicationServiceException(
                code: 'commitFailed',
                message: 'The operation could not be committed.',
              ),
              cleanupError: StateError('rollback failed'),
              warningCode: 'rollbackFailed',
              warningMessage: 'The rollback could not be completed.',
            ),
          ),
        ),
      ],
      resourceAuthority: authority,
      operationJournal: CockpitInMemoryWorkerOperationJournal(),
      terminateUnsafeWorker: () async {},
    );

    final result = await registry.execute(
      CockpitOperationInvocation(
        kind: 'mutation.rollbackFailure',
        workspaceId: workspaceId,
        deadline: _deadline(),
        idempotencyKey: CockpitIdempotencyKey('rollback-failure-key'),
      ),
      requestId: 'request-rollback-failure',
      cancellation: CockpitRpcCancellation.detached(),
    );

    expect(result.failure?.warnings.single.error.code, 'rollbackFailed');
    expect(authority.releaseCancellations, <bool>[true]);
  });

  test('recovered running probe collection is not recorded again', () async {
    final backend = _ProbeBackend();
    final resolver = _ProbeResourceResolver();
    final authority = _RecordingResourceAuthority();
    final journal = CockpitInMemoryWorkerOperationJournal();
    final invocation = _probeInvocation('probe-running');
    final submittedAt = DateTime.now().toUtc();
    await journal.admit(invocation: invocation, submittedAt: submittedAt);
    await journal.markRunning(
      idempotencyKey: 'probe-running',
      startedAt: submittedAt,
    );
    await journal.recover(now: submittedAt.add(const Duration(seconds: 1)));
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: CockpitWorkspaceApplicationAdapters(
        workspaceId: workspaceId,
        backend: backend,
        resourceResolver: resolver,
      ).create(),
      resourceAuthority: authority,
      operationJournal: journal,
      terminateUnsafeWorker: () async {},
    );
    final server = CockpitWorkerServer(
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>[],
      operations: registry,
      events: CockpitWorkerMemoryEventExchange(),
    );
    final harness = _PeerHarness(server.handle);
    server.bindPeer(harness.server);
    harness.start();
    addTearDown(harness.close);
    await _initialize(
      harness.client,
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>[],
    );

    final result = await _callOperation(harness.client, invocation);

    expect(result.outcome, CockpitOperationOutcome.failed);
    expect(result.failure?.primary.code, 'operationInterrupted');
    expect(backend.recordCount, 0);
    expect(resolver.resolveCount, 0);
    expect(authority.requests, isEmpty);
  });

  test(
    'dispatcher re-admits case.run with the same run and a new attempt',
    () async {
      final fixture = await _CaseRecoveryFixture.create();
      addTearDown(fixture.dispose);
      final invocation = _caseRunInvocation('case-running');
      final submittedAt = DateTime.now().toUtc();
      final original = await fixture.caseStore.reserve(
        idempotencyKey: 'case-running',
        requestFingerprint: _caseRequestFingerprint,
        caseId: 'caseA',
        proposedRunId: 'run_original',
        proposedAttemptId: 'attempt_original',
        now: submittedAt,
      );
      await fixture.caseStore.markRunning(
        idempotencyKey: 'case-running',
        runId: original.runId,
        attemptId: original.attemptId,
        now: submittedAt,
      );
      final admission = await fixture.journal.admit(
        invocation: invocation,
        submittedAt: submittedAt,
      );
      await fixture.journal.markRunning(
        idempotencyKey: 'case-running',
        startedAt: submittedAt,
      );

      expect(
        await fixture.caseStore.recover(
          now: submittedAt.add(const Duration(seconds: 1)),
        ),
        1,
      );
      await fixture.journal.recover(
        now: submittedAt.add(const Duration(seconds: 1)),
      );
      final adapter = _RecoverableCaseAdapter(fixture.caseStore);
      final harness = await fixture.open(adapter);
      addTearDown(harness.close);

      final result = await _callOperation(harness.client, invocation);
      final replay = await _callOperation(harness.client, invocation);
      final record = await fixture.readCaseRecord();
      final attempts = record['attempts']! as List<Object?>;

      expect(result.operationId, admission.operationId);
      expect(result.outcome, CockpitOperationOutcome.succeeded);
      expect(result.output?['runId'], original.runId);
      expect(result.output?['attemptId'], isNot(original.attemptId));
      expect(replay.toJson(), result.toJson());
      expect(adapter.driverExecutions, 1);
      expect(attempts, hasLength(2));
      expect(
        (attempts.first! as Map<String, Object?>)['status'],
        CockpitWorkerCaseAttemptStatus.interrupted.name,
      );
      expect(
        (attempts.last! as Map<String, Object?>)['status'],
        CockpitWorkerCaseAttemptStatus.completed.name,
      );
    },
  );

  test(
    'dispatcher replays completed case output from a stale journal',
    () async {
      final fixture = await _CaseRecoveryFixture.create();
      addTearDown(fixture.dispose);
      final invocation = _caseRunInvocation('case-completed-window');
      final submittedAt = DateTime.now().toUtc();
      final original = await fixture.caseStore.reserve(
        idempotencyKey: 'case-completed-window',
        requestFingerprint: _caseRequestFingerprint,
        caseId: 'caseA',
        proposedRunId: 'run_completed',
        proposedAttemptId: 'attempt_completed',
        now: submittedAt,
      );
      await fixture.caseStore.markRunning(
        idempotencyKey: 'case-completed-window',
        runId: original.runId,
        attemptId: original.attemptId,
        now: submittedAt,
      );
      final completedOutput = <String, Object?>{
        'runId': original.runId,
        'attemptId': original.attemptId,
        'driverResult': 'completed-before-journal',
      };
      await fixture.caseStore.markCompleted(
        idempotencyKey: 'case-completed-window',
        runId: original.runId,
        attemptId: original.attemptId,
        output: completedOutput,
        now: submittedAt,
      );
      final admission = await fixture.journal.admit(
        invocation: invocation,
        submittedAt: submittedAt,
      );
      await fixture.journal.markRunning(
        idempotencyKey: 'case-completed-window',
        startedAt: submittedAt,
      );
      await fixture.caseStore.recover(
        now: submittedAt.add(const Duration(seconds: 1)),
      );
      await fixture.journal.recover(
        now: submittedAt.add(const Duration(seconds: 1)),
      );
      final adapter = _RecoverableCaseAdapter(fixture.caseStore);
      final harness = await fixture.open(adapter);
      addTearDown(harness.close);

      final result = await _callOperation(harness.client, invocation);
      final replay = await _callOperation(harness.client, invocation);

      expect(result.operationId, admission.operationId);
      expect(result.output, completedOutput);
      expect(replay.toJson(), result.toJson());
      expect(adapter.driverExecutions, 0);
      expect((await fixture.readCaseRecord())['attempts'], hasLength(1));
    },
  );

  test('resource heartbeats are serialized within one operation', () async {
    final authority = _SerialHeartbeatAuthority(expectedHeartbeats: 3);
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      adapters: <CockpitWorkspaceOperationAdapter>[
        _heartbeatOperationAdapter((_) async {
          await authority.firstRound;
          return const <String, Object?>{'completed': true};
        }, resourceCount: 3),
      ],
      resourceAuthority: authority,
      operationJournal: CockpitInMemoryWorkerOperationJournal(),
      terminateUnsafeWorker: () async =>
          fail('Serialized heartbeats must not terminate the worker.'),
    );
    final server = CockpitWorkerServer(
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>[],
      operations: registry,
      events: CockpitWorkerMemoryEventExchange(),
    );
    final harness = _PeerHarness(server.handle);
    server.bindPeer(harness.server);
    harness.start();
    addTearDown(harness.close);
    await _initialize(
      harness.client,
      workspaceId: workspaceId,
      engineVersion: engineVersion,
      workspaceRoot: workspaceRoot,
      supportedFeatures: const <String>[],
    );

    final deadline = _deadline();
    final result = CockpitWorkerOperationResult.fromJson(
      await harness.client.call(
        method: 'operation',
        params: _operationParams('serialized-heartbeats', deadline),
        deadline: deadline,
      ),
    ).result;

    expect(result.outcome, CockpitOperationOutcome.succeeded);
    expect(authority.maxConcurrentHeartbeats, 1);
  });

  test(
    'heartbeat failure waits for cooperative execution before lease release',
    () async {
      var executionStopped = false;
      var unsafeTerminationCount = 0;
      final authority = _HeartbeatFailureAuthority(
        executionStopped: () => executionStopped,
      );
      final registry = CockpitWorkspaceOperationRegistry(
        workspaceId: workspaceId,
        workspaceRoot: workspaceRoot,
        adapters: <CockpitWorkspaceOperationAdapter>[
          _heartbeatOperationAdapter((context) async {
            await context.cancellation.whenCancelled;
            executionStopped = true;
            return const <String, Object?>{'stopped': true};
          }),
        ],
        resourceAuthority: authority,
        operationJournal: CockpitInMemoryWorkerOperationJournal(),
        terminateUnsafeWorker: () async => unsafeTerminationCount += 1,
        cancellationGrace: const Duration(milliseconds: 50),
        forcedAbortGrace: const Duration(milliseconds: 50),
      );
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
        operations: registry,
        events: CockpitWorkerMemoryEventExchange(),
      );
      final harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);
      await _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
      );

      final deadline = _deadline();
      final result = CockpitWorkerOperationResult.fromJson(
        await harness.client.call(
          method: 'operation',
          params: _operationParams('cooperative-heartbeat', deadline),
          deadline: deadline,
        ),
      ).result;

      expect(result.outcome, CockpitOperationOutcome.failed);
      expect(result.failure!.primary.code, 'resourceHeartbeatFailed');
      expect(executionStopped, isTrue);
      expect(authority.releaseCount, 1);
      expect(authority.releasedBeforeExecutionStopped, isFalse);
      expect(unsafeTerminationCount, 0);
    },
  );

  test(
    'heartbeat failure terminates an unsafe worker without releasing lease',
    () async {
      final execution = Completer<Map<String, Object?>>();
      final unsafeTermination = Completer<void>();
      final authority = _HeartbeatFailureAuthority(
        executionStopped: () => false,
      );
      late final _PeerHarness harness;
      final registry = CockpitWorkspaceOperationRegistry(
        workspaceId: workspaceId,
        workspaceRoot: workspaceRoot,
        adapters: <CockpitWorkspaceOperationAdapter>[
          _heartbeatOperationAdapter((_) => execution.future),
        ],
        resourceAuthority: authority,
        operationJournal: CockpitInMemoryWorkerOperationJournal(),
        terminateUnsafeWorker: () async {
          if (!unsafeTermination.isCompleted) unsafeTermination.complete();
          await harness.server.close();
        },
        cancellationGrace: const Duration(milliseconds: 10),
        forcedAbortGrace: const Duration(milliseconds: 10),
      );
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
        operations: registry,
        events: CockpitWorkerMemoryEventExchange(),
      );
      harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);
      await _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
      );

      final deadline = _deadline();
      await expectLater(
        harness.client.call(
          method: 'operation',
          params: _operationParams('unsafe-heartbeat', deadline),
          deadline: deadline,
        ),
        throwsA(isA<CockpitJsonRpcPeerClosedException>()),
      );
      await unsafeTermination.future.timeout(const Duration(seconds: 2));
      expect(authority.releaseCount, 0);
    },
  );

  test(
    'operation-specific cancellation grace permits bounded cleanup',
    () async {
      var executionStopped = false;
      var unsafeTerminationCount = 0;
      final authority = _HeartbeatFailureAuthority(
        executionStopped: () => executionStopped,
      );
      final registry = CockpitWorkspaceOperationRegistry(
        workspaceId: workspaceId,
        workspaceRoot: workspaceRoot,
        adapters: <CockpitWorkspaceOperationAdapter>[
          _heartbeatOperationAdapter((context) async {
            await context.cancellation.whenCancelled;
            await Future<void>.delayed(const Duration(milliseconds: 60));
            executionStopped = true;
            return const <String, Object?>{'cleaned': true};
          }, cancellationGrace: const Duration(milliseconds: 100)),
        ],
        resourceAuthority: authority,
        operationJournal: CockpitInMemoryWorkerOperationJournal(),
        terminateUnsafeWorker: () async => unsafeTerminationCount += 1,
        cancellationGrace: const Duration(milliseconds: 10),
        forcedAbortGrace: const Duration(milliseconds: 10),
      );
      final server = CockpitWorkerServer(
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
        operations: registry,
        events: CockpitWorkerMemoryEventExchange(),
      );
      final harness = _PeerHarness(server.handle);
      server.bindPeer(harness.server);
      harness.start();
      addTearDown(harness.close);
      await _initialize(
        harness.client,
        workspaceId: workspaceId,
        engineVersion: engineVersion,
        workspaceRoot: workspaceRoot,
        supportedFeatures: const <String>[],
      );

      final deadline = _deadline();
      final result = CockpitWorkerOperationResult.fromJson(
        await harness.client.call(
          method: 'operation',
          params: _operationParams('bounded-cleanup', deadline),
          deadline: deadline,
        ),
      ).result;

      expect(result.failure?.primary.code, 'resourceHeartbeatFailed');
      expect(executionStopped, isTrue);
      expect(unsafeTerminationCount, 0);
      expect(authority.releaseCount, 1);
    },
  );

  test('bounded locator output never crosses the worker frame limit', () {
    final snapshot = CockpitSnapshot(
      routeName: '/large',
      visibleTargets: List<CockpitSnapshotTarget>.generate(
        2000,
        (index) => CockpitSnapshotTarget(
          registrationId: 'target-$index',
          text: 'Target $index ${'x' * 800}',
          routeName: '/large',
          supportedCommands: const <CockpitCommandType>[CockpitCommandType.tap],
        ),
      ),
    );
    final output = cockpitWorkerInspectUiOutput(
      CockpitInspectUiResult(
        routeName: '/large',
        diagnosticLevel: 'baseline',
        truncated: false,
        snapshot: snapshot,
        locator: const <String, Object?>{
          'query': 'Target 1999',
          'count': 1,
          'matches': <Object?>[
            <String, Object?>{'sel': 'Target 1999', 'can': 'tap'},
          ],
        },
      ),
    );

    expect(output, isNot(contains('snapshot')));
    expect(output['locator'], isA<Map<Object?, Object?>>());
    expect(
      utf8.encode(jsonEncode(output)).length,
      lessThan(cockpitWorkerMaximumPayloadBytes),
    );
  });

  test('surface locator output also omits its complete snapshot', () {
    final output = cockpitWorkerInspectSurfaceOutput(
      CockpitInspectSurfaceResult(
        target: CockpitTargetHandle(
          targetId: 'target-1',
          targetKind: CockpitTargetKind.flutterApp,
          platform: 'android',
          deviceId: 'emulator-5554',
          projectDir: '/workspace/a/app',
          target: 'cockpit/main.dart',
          connection: const CockpitTargetConnection(
            baseUrl: 'http://127.0.0.1:61331',
          ),
          launchedAt: DateTime.utc(2026, 8, 12),
        ),
        capabilityProfile: CockpitCapabilityProfile(
          targetKind: CockpitTargetKind.flutterApp,
        ),
        surfaceKind: CockpitSurfaceKind.flutterSemantic,
        selectedPlane: CockpitPlaneKind.flutterSemanticPlane,
        recommendedNextStep: 'runNextCommand',
        diagnosticLevel: 'baseline',
        truncated: false,
        snapshot: CockpitSnapshot(
          routeName: '/large',
          visibleTargets: List<CockpitSnapshotTarget>.generate(
            2000,
            (index) => CockpitSnapshotTarget(
              registrationId: 'target-$index',
              text: 'Target $index ${'x' * 800}',
              routeName: '/large',
            ),
          ),
        ),
        locator: const <String, Object?>{
          'query': 'Target 1999',
          'count': 1,
          'matches': <Object?>[
            <String, Object?>{'sel': 'Target 1999'},
          ],
        },
      ),
    );

    expect(output, isNot(contains('snapshot')));
    expect(output['locator'], isA<Map<Object?, Object?>>());
    expect(
      utf8.encode(jsonEncode(output)).length,
      lessThan(cockpitWorkerMaximumPayloadBytes),
    );
  });

  test('evidence output externalizes UI but preserves full diagnostics', () {
    final result = CockpitInspectUiResult(
      routeName: '/failure',
      diagnosticLevel: 'forensic',
      truncated: false,
      snapshot: CockpitSnapshot(
        routeName: '/failure',
        visibleTargets: <CockpitSnapshotTarget>[
          CockpitSnapshotTarget(
            registrationId: 'failure-target',
            text: 'Failure target ${'x' * 800000}',
            routeName: '/failure',
          ),
        ],
      ),
      diagnostics: <String, Object?>{
        'level': 'full',
        'runtime': <String, Object?>{
          'totalEntryCount': 1,
          'errorCount': 1,
          'entries': <Object?>[
            <String, Object?>{'message': 'Complete runtime evidence'},
          ],
        },
      },
      artifactDownloads: const <CockpitRemoteArtifactDownload>[
        CockpitRemoteArtifactDownload(
          artifact: CockpitArtifactRef(
            role: 'diagnostics',
            relativePath: 'diagnostics/evidence.json',
          ),
          downloadPath: '/artifacts/evidence.json',
        ),
      ],
    );

    final output = cockpitWorkerInspectUiOutput(
      result,
      externalizeSnapshot: true,
    );

    expect(output, isNot(contains('snapshot')));
    expect(
      output['diagnostics'].toString(),
      contains('Complete runtime evidence'),
    );
    expect(output['artifactDownloads'], isA<List<Object?>>());
    expect(
      utf8.encode(jsonEncode(output)).length,
      lessThan(cockpitWorkerMaximumPayloadBytes),
    );
  });
}

Future<void> _initialize(
  CockpitJsonRpcPeer peer, {
  required String workspaceId,
  required String engineVersion,
  required String workspaceRoot,
  List<String> supportedFeatures = const <String>['featureA'],
  String idempotencyKey = 'initialize',
}) async {
  final raw = await peer.call(
    method: 'initialize',
    params: <String, Object?>{
      'protocolVersion': cockpitWorkerProtocolVersion,
      'workspaceId': workspaceId,
      'idempotencyKey': idempotencyKey,
      'engineVersion': engineVersion,
      'workspaceRoot': workspaceRoot,
      'supportedFeatures': supportedFeatures,
    },
    deadline: _deadline(),
  );
  expect(
    CockpitWorkerInitializeResult.fromJson(raw).negotiatedFeatures,
    supportedFeatures,
  );
}

CockpitOperationInvocation _probeInvocation(String key) =>
    CockpitOperationInvocation(
      kind: 'development.probe.collect',
      workspaceId: 'workspaceA',
      idempotencyKey: CockpitIdempotencyKey(key),
      deadline: _deadline(),
      input: const <String, Object?>{'sessionId': 'sessionA'},
    );

CockpitOperationInvocation _applicationInvocation(
  String kind,
  String key, {
  Map<String, Object?> input = const <String, Object?>{'sessionId': 'sessionA'},
}) => CockpitOperationInvocation(
  kind: kind,
  workspaceId: 'workspaceA',
  idempotencyKey: CockpitIdempotencyKey(key),
  deadline: _deadline(),
  input: input,
);

Future<CockpitOperationResult> _callOperation(
  CockpitJsonRpcPeer peer,
  CockpitOperationInvocation invocation,
) async {
  final deadline = invocation.deadline!;
  final raw = await peer.call(
    method: 'operation',
    params: <String, Object?>{
      'protocolVersion': cockpitWorkerProtocolVersion,
      'workspaceId': invocation.workspaceId,
      'idempotencyKey': invocation.idempotencyKey!.value,
      'invocation': invocation.toJson(),
    },
    deadline: deadline,
  );
  return CockpitWorkerOperationResult.fromJson(raw).result;
}

Map<String, Object?> _operationParams(String key, DateTime deadline) {
  return <String, Object?>{
    'protocolVersion': cockpitWorkerProtocolVersion,
    'workspaceId': 'workspaceA',
    'idempotencyKey': key,
    'invocation': CockpitOperationInvocation(
      kind: 'mutate.test',
      workspaceId: 'workspaceA',
      idempotencyKey: CockpitIdempotencyKey(key),
      deadline: deadline,
    ).toJson(),
  };
}

CockpitWorkspaceOperationAdapter _heartbeatOperationAdapter(
  Future<Map<String, Object?>> Function(CockpitWorkspaceOperationContext)
  execute, {
  Duration? cancellationGrace,
  int resourceCount = 1,
}) => CockpitWorkspaceOperationAdapter(
  kind: 'mutate.test',
  mutationClass: CockpitMutationClass.mutating,
  resourceKinds: const <String>['device.mutation'],
  prepare: (context, _) => CockpitPreparedWorkspaceOperation(
    resources: List<CockpitWorkerResourceRequest>.generate(
      resourceCount,
      (index) => CockpitWorkerResourceRequest(
        resourceKind: CockpitLeaseResourceKind.device,
        resourceId: 'device$index',
        ttl: const Duration(seconds: 1),
      ),
    ),
    cancellationGrace: cancellationGrace,
    execute: (_) => execute(context),
  ),
);

DateTime _deadline() => DateTime.now().toUtc().add(const Duration(seconds: 5));

Map<String, Object?> _publishParams({
  required String key,
  required String runId,
  required int afterSequence,
  required int eventSequence,
}) => <String, Object?>{
  'protocolVersion': cockpitWorkerProtocolVersion,
  'workspaceId': 'workspaceA',
  'idempotencyKey': key,
  'runId': runId,
  'afterSequence': afterSequence,
  'events': <Object?>[
    CockpitRunEvent(
      eventId: 'event$eventSequence',
      sequence: eventSequence,
      timestamp: DateTime.utc(2026, 7, 22),
      kind: 'run.progress',
      entityKind: CockpitRunEventEntityKind.run,
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      runId: runId,
      lifecycle: CockpitRunLifecycle.running,
    ).toJson(),
  ],
};

Map<String, Object?> _artifactPublishParams() => <String, Object?>{
  'protocolVersion': cockpitWorkerProtocolVersion,
  'workspaceId': 'workspaceA',
  'idempotencyKey': 'artifact-direction',
  'projectId': 'projectA',
  'runId': 'runArtifactDirection',
  'caseId': 'caseA',
  'artifacts': <Object?>[
    CockpitArtifactResource(
      artifactId: 'artifactDirection',
      workspaceId: 'workspaceA',
      runId: 'runArtifactDirection',
      attemptId: 'attemptDirection',
      kind: 'attempt.screenshot',
      relativePath: 'artifacts/bundleDirection/screenshot.png',
      mediaType: 'image/png',
      sizeBytes: 4,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      createdAt: DateTime.utc(2026, 7, 22),
      downloadUrl:
          '/api/v2/runs/runArtifactDirection/artifacts/artifactDirection',
    ).toJson(),
  ],
};

Matcher _remoteCode(String code) => isA<CockpitJsonRpcRemoteException>().having(
  (error) => error.error.workerCode,
  'workerCode',
  code,
);

final List<_InvalidEnvelopeCase> _invalidEnvelopeCorpus =
    <_InvalidEnvelopeCase>[
      _InvalidEnvelopeCase(
        'protocol-version',
        'upgradeRequired',
        (params) => <String, Object?>{
          ...params,
          'protocolVersion': 'cockpit.worker/v999',
        },
      ),
      _InvalidEnvelopeCase(
        'workspace-spoofing',
        'workspaceMismatch',
        (params) => <String, Object?>{...params, 'workspaceId': 'workspaceB'},
      ),
      _InvalidEnvelopeCase(
        'unknown-field',
        'invalidRequest',
        (params) => <String, Object?>{...params, 'unexpected': true},
      ),
    ];

typedef _EnvelopeMutation =
    Map<String, Object?> Function(Map<String, Object?> params);

final class _InvalidEnvelopeCase {
  const _InvalidEnvelopeCase(this.name, this.workerCode, this.apply);

  final String name;
  final String workerCode;
  final _EnvelopeMutation apply;
}

typedef _RequestHandlerDecorator =
    CockpitJsonRpcRequestHandler Function(CockpitJsonRpcRequestHandler base);

final class _ContractDirection {
  const _ContractDirection.worker() : name = 'worker-bound', worker = true;
  const _ContractDirection.supervisor()
    : name = 'Supervisor-bound',
      worker = false;

  final String name;
  final bool worker;

  _ContractHarness open({
    _RequestHandlerDecorator? decorate,
    DateTime Function()? receiverUtcNow,
    CockpitJsonRpcProtocolErrorHandler? callerProtocolError,
    Duration clientCancellationGrace = const Duration(milliseconds: 250),
    Duration clientForcedAbortGrace = const Duration(seconds: 2),
  }) {
    final events = CockpitWorkerMemoryEventExchange();
    CockpitWorkerServer? server;
    final CockpitJsonRpcRequestHandler base;
    if (worker) {
      server = CockpitWorkerServer(
        workspaceId: 'workspaceA',
        engineVersion: 'engineA',
        workspaceRoot: '/workspace/a',
        supportedFeatures: const <String>['featureA'],
        operations: const _TestOperationDispatcher(),
        events: events,
      );
      base = server.handle;
    } else {
      base = CockpitSupervisorWorkerEndpoint(
        workspaceId: 'workspaceA',
        events: events,
        artifacts: events,
        resourceAuthority: const _TestResourceAuthority(),
      ).handle;
    }
    final harness = _PeerHarness(
      decorate?.call(base) ?? base,
      serverUtcNow: receiverUtcNow,
      clientProtocolError: callerProtocolError,
      clientCancellationGrace: clientCancellationGrace,
      clientForcedAbortGrace: clientForcedAbortGrace,
    );
    server?.bindPeer(harness.server);
    return _ContractHarness(harness: harness, initializeWorker: worker);
  }

  _RawPeerHarness openRaw() {
    final events = CockpitWorkerMemoryEventExchange();
    CockpitWorkerServer? server;
    final CockpitJsonRpcRequestHandler handler;
    if (worker) {
      server = CockpitWorkerServer(
        workspaceId: 'workspaceA',
        engineVersion: 'engineA',
        workspaceRoot: '/workspace/a',
        supportedFeatures: const <String>['featureA'],
        operations: const _TestOperationDispatcher(),
        events: events,
      );
      handler = server.handle;
    } else {
      handler = CockpitSupervisorWorkerEndpoint(
        workspaceId: 'workspaceA',
        events: events,
        artifacts: events,
        resourceAuthority: const _TestResourceAuthority(),
      ).handle;
    }
    final harness = _RawPeerHarness(handler);
    server?.bindPeer(harness.peer);
    return harness;
  }
}

final class _ContractHarness {
  const _ContractHarness({
    required this.harness,
    required this.initializeWorker,
  });

  final _PeerHarness harness;
  final bool initializeWorker;

  CockpitJsonRpcPeer get peer => harness.client;
  CockpitJsonRpcPeer get receiver => harness.server;

  Future<void> start() async {
    harness.start();
    if (initializeWorker) {
      await _initialize(
        peer,
        workspaceId: 'workspaceA',
        engineVersion: 'engineA',
        workspaceRoot: '/workspace/a',
      );
    }
  }

  Future<void> close() => harness.close();
}

final class _RawPeerHarness {
  _RawPeerHarness(CockpitJsonRpcRequestHandler handler)
    : _input = StreamController<List<int>>(),
      _output = StreamController<List<int>>() {
    peer = CockpitJsonRpcPeer(
      input: _input.stream,
      output: _output.sink,
      requestHandler: handler,
    );
    _subscription = _output.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final response = CockpitJsonRpcResponse.fromJson(
            Map<String, Object?>.from(
              jsonDecode(line) as Map<Object?, Object?>,
            ),
          );
          final pending = _responses.remove(response.id);
          pending?.complete(response);
        });
  }

  final StreamController<List<int>> _input;
  final StreamController<List<int>> _output;
  final Map<String, Completer<CockpitJsonRpcResponse>> _responses =
      <String, Completer<CockpitJsonRpcResponse>>{};
  late final CockpitJsonRpcPeer peer;
  late final StreamSubscription<String> _subscription;

  void start() => peer.start();

  Future<CockpitJsonRpcResponse> send(CockpitJsonRpcRequest request) {
    final completer = Completer<CockpitJsonRpcResponse>();
    _responses[request.id] = completer;
    _input.add(utf8.encode('${jsonEncode(request.toJson())}\n'));
    return completer.future;
  }

  Future<void> close() async {
    await peer.close(closeOutput: false);
    await _input.close();
    await _output.close();
    await _subscription.cancel();
  }
}

final class _PeerHarness {
  factory _PeerHarness(
    CockpitJsonRpcRequestHandler serverHandler, {
    DateTime Function()? serverUtcNow,
    CockpitJsonRpcProtocolErrorHandler? clientProtocolError,
    Duration clientCancellationGrace = const Duration(milliseconds: 250),
    Duration clientForcedAbortGrace = const Duration(seconds: 2),
  }) {
    final clientInput = StreamController<List<int>>();
    final serverInput = StreamController<List<int>>();
    return _PeerHarness._(
      client: CockpitJsonRpcPeer(
        input: clientInput.stream,
        output: serverInput.sink,
        requestHandler: _unexpectedRequest,
        onProtocolError: clientProtocolError,
        cancellationGrace: clientCancellationGrace,
        forcedAbortGrace: clientForcedAbortGrace,
      ),
      server: CockpitJsonRpcPeer(
        input: serverInput.stream,
        output: clientInput.sink,
        requestHandler: serverHandler,
        utcNow: serverUtcNow,
      ),
    );
  }

  const _PeerHarness._({required this.client, required this.server});

  final CockpitJsonRpcPeer client;
  final CockpitJsonRpcPeer server;

  void start() {
    client.start();
    server.start();
  }

  Future<void> close() async {
    await client.close();
    await server.close(closeOutput: false);
  }
}

Future<Object?> _unexpectedRequest(
  CockpitJsonRpcRequest _,
  CockpitRpcCancellation _,
) => throw StateError('The client peer does not accept requests in this test.');

final class _TestOperationDispatcher
    implements CockpitWorkerOperationDispatcher {
  const _TestOperationDispatcher();

  @override
  List<String> get operationKinds => const <String>['analyze.workspace'];

  @override
  List<String> get resourceKinds => const <String>['workspace.tooling'];

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation, {
    required String requestId,
    required CockpitRpcCancellation cancellation,
  }) => throw UnimplementedError();
}

final class _TestResourceAuthority
    implements CockpitSupervisorWorkerResourceAuthority {
  const _TestResourceAuthority();

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation,
  ) => throw UnimplementedError();
}

const String _caseRequestFingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

CockpitOperationInvocation _caseRunInvocation(String key) =>
    CockpitOperationInvocation(
      kind: 'case.run',
      workspaceId: 'workspaceA',
      idempotencyKey: CockpitIdempotencyKey(key),
      deadline: _deadline(),
      input: const <String, Object?>{'caseId': 'caseA'},
    );

final class _RecoverableCaseAdapter {
  _RecoverableCaseAdapter(this.store);

  final CockpitWorkerCaseRunStore store;
  var prepareCount = 0;
  var driverExecutions = 0;

  CockpitWorkspaceOperationAdapter create() => CockpitWorkspaceOperationAdapter(
    kind: 'case.run',
    mutationClass: CockpitMutationClass.mutating,
    resourceKinds: const <String>['workspace.runs'],
    prepare: (context, input) async {
      expect(input, const <String, Object?>{'caseId': 'caseA'});
      prepareCount += 1;
      final reservation = await store.reserve(
        idempotencyKey: context.idempotencyKey,
        requestFingerprint: _caseRequestFingerprint,
        caseId: 'caseA',
        proposedRunId: 'run_proposed_$prepareCount',
        proposedAttemptId: 'attempt_recovered_$prepareCount',
        now: DateTime.now().toUtc(),
      );
      if (reservation.replayed) {
        return CockpitPreparedWorkspaceOperation(
          resources: const <CockpitWorkerResourceRequest>[],
          isIdempotentReplay: true,
          execute: (_) async => reservation.completedOutput!,
        );
      }
      return CockpitPreparedWorkspaceOperation(
        resources: <CockpitWorkerResourceRequest>[
          CockpitWorkerResourceRequest(
            resourceKind: CockpitLeaseResourceKind.workspaceMutation,
            resourceId: context.workspaceId,
          ),
        ],
        execute: (_) async {
          await store.markRunning(
            idempotencyKey: context.idempotencyKey,
            runId: reservation.runId,
            attemptId: reservation.attemptId,
            now: DateTime.now().toUtc(),
          );
          driverExecutions += 1;
          final output = <String, Object?>{
            'runId': reservation.runId,
            'attemptId': reservation.attemptId,
            'driverResult': 'execution-$driverExecutions',
          };
          await store.markCompleted(
            idempotencyKey: context.idempotencyKey,
            runId: reservation.runId,
            attemptId: reservation.attemptId,
            output: output,
            now: DateTime.now().toUtc(),
          );
          return output;
        },
      );
    },
  );
}

final class _CaseRecoveryFixture {
  const _CaseRecoveryFixture({
    required this.temporary,
    required this.root,
    required this.caseStore,
    required this.journal,
  });

  final Directory temporary;
  final String root;
  final CockpitWorkerCaseRunStore caseStore;
  final CockpitFileWorkerOperationJournal journal;

  static Future<_CaseRecoveryFixture> create() async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-dispatcher-case-recovery-',
    );
    final root = await temporary.resolveSymbolicLinks();
    const hardener = _NoopPermissionHardener();
    const syncer = _NoopDirectorySyncer();
    return _CaseRecoveryFixture(
      temporary: temporary,
      root: root,
      caseStore: CockpitWorkerCaseRunStore.file(
        workspaceId: 'workspaceA',
        path: p.join(root, 'case_runs'),
        permissionHardener: hardener,
        directorySyncer: syncer,
      ),
      journal: CockpitFileWorkerOperationJournal(
        path: p.join(root, 'operations'),
        permissionHardener: hardener,
        directorySyncer: syncer,
        recoveryPolicies: const <String, CockpitWorkerOperationRecoveryPolicy>{
          'case.run': CockpitWorkerOperationRecoveryPolicy.retryPrepared,
        },
      ),
    );
  }

  Future<_PeerHarness> open(_RecoverableCaseAdapter adapter) async {
    final registry = CockpitWorkspaceOperationRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: root,
      adapters: <CockpitWorkspaceOperationAdapter>[adapter.create()],
      resourceAuthority: _RecordingResourceAuthority(),
      operationJournal: journal,
      terminateUnsafeWorker: () async {},
    );
    final server = CockpitWorkerServer(
      workspaceId: 'workspaceA',
      engineVersion: 'engineA',
      workspaceRoot: root,
      supportedFeatures: const <String>[],
      operations: registry,
      events: CockpitWorkerMemoryEventExchange(),
    );
    final harness = _PeerHarness(server.handle);
    server.bindPeer(harness.server);
    harness.start();
    await _initialize(
      harness.client,
      workspaceId: 'workspaceA',
      engineVersion: 'engineA',
      workspaceRoot: root,
      supportedFeatures: const <String>[],
    );
    return harness;
  }

  Future<Map<String, Object?>> readCaseRecord() async {
    final records = await Directory(p.join(root, 'case_runs'))
        .list(recursive: true, followLinks: false)
        .where(
          (entity) =>
              entity is File && p.basename(entity.path) == 'record.json',
        )
        .cast<File>()
        .toList();
    expect(records, hasLength(1));
    return Map<String, Object?>.from(
      jsonDecode(await records.single.readAsString())! as Map,
    );
  }

  Future<void> dispose() => temporary.delete(recursive: true);
}

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}

final class _ProbeBackend implements CockpitWorkerApplicationBackend {
  int recordCount = 0;

  @override
  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
  }) async {
    expect(kind, 'development.probe.collect');
    expect(input, const <String, Object?>{'sessionId': 'sessionA'});
    expect(context.idempotencyKey, isNotEmpty);
    expect(grants, hasLength(1));
    recordCount += 1;
    return <String, Object?>{'probeId': 'probe_$recordCount'};
  }
}

final class _ReadMutationBackend implements CockpitWorkerApplicationBackend {
  final Completer<void> readEntered = Completer<void>();
  final Completer<void> releaseRead = Completer<void>();
  final Completer<void> mutationEntered = Completer<void>();
  final Map<String, int> grantCountByKind = <String, int>{};

  @override
  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
  }) async {
    grantCountByKind[kind] = grants.length;
    if (kind == 'session.remote.status') {
      expect(grants, isEmpty);
      readEntered.complete();
      await releaseRead.future;
    } else if (kind == 'command.run') {
      expect(
        grants.where(
          (grant) =>
              grant.resourceKind == CockpitLeaseResourceKind.session &&
              grant.resourceId == 'session_resource_A',
        ),
        hasLength(1),
      );
      mutationEntered.complete();
    } else if (kind == 'network.body') {
      expect(
        grants.where(
          (grant) =>
              grant.resourceKind == CockpitLeaseResourceKind.capture &&
              grant.resourceId == 'session_resource_A',
        ),
        hasLength(1),
      );
    } else if (kind == 'evidence.screenshot.capture') {
      expect(
        grants.map((grant) => grant.resourceKind),
        <CockpitLeaseResourceKind>[
          CockpitLeaseResourceKind.device,
          CockpitLeaseResourceKind.capture,
        ],
      );
    } else {
      expect(grants, isEmpty);
    }
    return <String, Object?>{'kind': kind};
  }
}

final class _ReadMutationResourceResolver
    implements CockpitWorkerApplicationResourceResolver {
  final List<String> resolvedKinds = <String>[];

  @override
  Future<CockpitWorkerApplicationResourcePlan> resolveApplicationResourcePlan({
    required String kind,
    required Map<String, Object?> input,
  }) async {
    resolvedKinds.add(kind);
    return CockpitWorkerApplicationResourcePlan(
      primaryResourceId: 'session_resource_A',
      deviceResourceId: 'device_resource_A',
    );
  }
}

final class _ExclusiveSessionResourceAuthority
    implements CockpitWorkerResourceAuthorityClient {
  final List<CockpitWorkerResourceRequest> requests =
      <CockpitWorkerResourceRequest>[];
  final List<String> sessionAcquisitions = <String>[];
  final Map<String, Completer<void>> _activeSessions =
      <String, Completer<void>>{};
  final Map<String, Completer<void>> _releasesByGrant =
      <String, Completer<void>>{};
  var _sequence = 0;

  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async {
    requests.add(request);
    if (request.resourceKind == CockpitLeaseResourceKind.session) {
      while (true) {
        final active = _activeSessions[request.resourceId];
        if (active == null) break;
        await active.future;
      }
      final release = Completer<void>();
      _activeSessions[request.resourceId] = release;
      sessionAcquisitions.add(request.resourceId);
      _sequence += 1;
      final grantId = 'exclusive_grant_$_sequence';
      _releasesByGrant[grantId] = release;
      return CockpitWorkerResourceGrant(
        grantId: grantId,
        leaseId: 'exclusive_lease_$_sequence',
        workspaceId: workspaceId,
        holderId: holderId,
        resourceKind: request.resourceKind,
        resourceId: request.resourceId,
        expiresAt: deadline,
      );
    }
    _sequence += 1;
    return CockpitWorkerResourceGrant(
      grantId: 'shared_grant_$_sequence',
      leaseId: 'shared_lease_$_sequence',
      workspaceId: workspaceId,
      holderId: holderId,
      resourceKind: request.resourceKind,
      resourceId: request.resourceId,
      expiresAt: deadline,
    );
  }

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {}

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {
    final release = _releasesByGrant.remove(grant.grantId);
    if (release == null) return;
    _activeSessions.remove(grant.resourceId);
    release.complete();
  }
}

final class _ProbeResourceResolver
    implements CockpitWorkerApplicationResourceResolver {
  int resolveCount = 0;

  @override
  Future<CockpitWorkerApplicationResourcePlan> resolveApplicationResourcePlan({
    required String kind,
    required Map<String, Object?> input,
  }) async {
    expect(kind, 'development.probe.collect');
    expect(input['sessionId'], 'sessionA');
    resolveCount += 1;
    return CockpitWorkerApplicationResourcePlan(
      primaryResourceId: 'session_resource_A',
      deviceResourceId: 'device_resource_A',
    );
  }
}

final class _RecordingResourceAuthority
    implements CockpitWorkerResourceAuthorityClient {
  final List<CockpitWorkerResourceRequest> requests =
      <CockpitWorkerResourceRequest>[];
  final List<bool> releaseCancellations = <bool>[];
  int releaseCount = 0;

  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async {
    requests.add(request);
    final sequence = requests.length;
    return CockpitWorkerResourceGrant(
      grantId: 'grant_$sequence',
      leaseId: 'lease_$sequence',
      workspaceId: workspaceId,
      holderId: holderId,
      resourceKind: request.resourceKind,
      resourceId: request.resourceId,
      expiresAt: deadline,
    );
  }

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {}

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {
    releaseCount += 1;
    releaseCancellations.add(cancel);
  }
}

final class _RejectingResourceAuthority
    implements CockpitWorkerResourceAuthorityClient {
  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) {
    throw const CockpitWorkerResourceException(
      code: CockpitErrorCode.resourceBusy,
      message: 'Lease wait timeout expired.',
      details: <String, Object?>{
        'lease': <String, Object?>{'resourceKind': 'device'},
      },
    );
  }

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {}

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {}
}

final class _HeartbeatFailureAuthority
    implements CockpitWorkerResourceAuthorityClient {
  _HeartbeatFailureAuthority({required bool Function() executionStopped})
    : _executionStopped = executionStopped;

  final bool Function() _executionStopped;
  var releaseCount = 0;
  var releasedBeforeExecutionStopped = false;

  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async => CockpitWorkerResourceGrant(
    grantId: 'grantA',
    leaseId: 'leaseA',
    workspaceId: workspaceId,
    holderId: holderId,
    resourceKind: request.resourceKind,
    resourceId: request.resourceId,
    expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 2)),
  );

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {
    throw StateError('heartbeat failed');
  }

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {
    releaseCount += 1;
    releasedBeforeExecutionStopped = !_executionStopped();
  }
}

final class _SerialHeartbeatAuthority
    implements CockpitWorkerResourceAuthorityClient {
  _SerialHeartbeatAuthority({required this.expectedHeartbeats});

  final int expectedHeartbeats;
  final Completer<void> _firstRound = Completer<void>();
  var _sequence = 0;
  var _heartbeatCount = 0;
  var _concurrentHeartbeats = 0;
  var maxConcurrentHeartbeats = 0;

  Future<void> get firstRound => _firstRound.future;

  @override
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async {
    _sequence += 1;
    return CockpitWorkerResourceGrant(
      grantId: 'serial_grant_$_sequence',
      leaseId: 'serial_lease_$_sequence',
      workspaceId: workspaceId,
      holderId: holderId,
      resourceKind: request.resourceKind,
      resourceId: request.resourceId,
      expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 2)),
    );
  }

  @override
  Future<void> heartbeat(CockpitWorkerResourceGrant grant) async {
    _concurrentHeartbeats += 1;
    if (_concurrentHeartbeats > maxConcurrentHeartbeats) {
      maxConcurrentHeartbeats = _concurrentHeartbeats;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _concurrentHeartbeats -= 1;
    _heartbeatCount += 1;
    if (_heartbeatCount >= expectedHeartbeats && !_firstRound.isCompleted) {
      _firstRound.complete();
    }
  }

  @override
  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  }) async {}
}
