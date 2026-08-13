import 'dart:async';
import 'dart:convert';

import 'package:cockpit/src/worker/cockpit_json_rpc_message.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_rpc_resource_authority_client.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('rejects a reused inbound request id', () async {
    final harness = _PeerHarness((_, _) => <String, Object?>{'ok': true});
    harness.start();
    addTearDown(harness.close);

    expect(
      await harness.client.call(
        method: 'health',
        params: _params('first'),
        deadline: _deadline(),
        requestId: 'duplicateA',
      ),
      <String, Object?>{'ok': true},
    );
    await expectLater(
      harness.client.call(
        method: 'health',
        params: _params('second'),
        deadline: _deadline(),
        requestId: 'duplicateA',
      ),
      throwsA(_remoteCode('duplicateRequestId')),
    );
  });

  test(
    'rejects an active original id after bounded history eviction',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var originalCancelled = false;
      final harness = _RawServerHarness((request, cancellation) async {
        if (request.params['shared'] == true) {
          if (!entered.isCompleted) entered.complete();
          unawaited(
            cancellation.whenCancelled.then<void>(
              (_) => originalCancelled = true,
            ),
          );
          await Future.any<void>(<Future<void>>[
            release.future,
            cancellation.whenCancelled,
          ]);
          cancellation.throwIfCancelled();
        }
        return <String, Object?>{'requestId': request.id};
      }, maximumRememberedRequestIds: 128);
      harness.start();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await harness.close();
      });
      final sharedParams = <String, Object?>{
        ..._params('evicted-original'),
        'shared': true,
      };

      harness.sendRequest(
        id: 'evictedOriginalA',
        method: 'health',
        params: sharedParams,
      );
      await entered.future;
      await _fillInboundHistory(harness, prefix: 'originalHistory');

      final duplicate = await harness.sendAndWait(
        id: 'evictedOriginalA',
        method: 'health',
        params: sharedParams,
      );
      expect(duplicate.error?.workerCode, 'duplicateRequestId');
      expect(harness.peer.activeInboundRequestCount, 1);

      final cancelledReply = harness.nextResponse('evictedOriginalA');
      expect(
        harness.peer.cancelInbound('evictedOriginalA'),
        CockpitRpcCancellationResult.cancelled,
      );
      expect((await cancelledReply).error?.workerCode, 'cancelled');
      expect(originalCancelled, isTrue);
      expect(harness.peer.activeInboundRequestCount, 0);
      expect(
        harness
            .responsesFor('evictedOriginalA')
            .map((response) => response.error?.workerCode),
        <String?>['duplicateRequestId', 'cancelled'],
      );

      final unrelated = await harness.sendAndWait(
        id: 'afterEvictedOriginalA',
        method: 'health',
        params: const <String, Object?>{},
      );
      expect(unrelated.result, <String, Object?>{
        'requestId': 'afterEvictedOriginalA',
      });
      expect(harness.peer.isClosed, isFalse);
      expect(harness.protocolErrors, isEmpty);
    },
  );

  test(
    'rejects an active follower id after bounded history eviction',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var originalCancelled = false;
      final harness = _RawServerHarness(
        (request, cancellation) async {
          if (request.params['shared'] == true) {
            if (!entered.isCompleted) entered.complete();
            unawaited(
              cancellation.whenCancelled.then<void>(
                (_) => originalCancelled = true,
              ),
            );
            await release.future;
            cancellation.throwIfCancelled();
          }
          return <String, Object?>{'requestId': request.id};
        },
        maximumRememberedRequestIds: 128,
        maximumActiveIdempotentFollowers: 2,
      );
      harness.start();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await harness.close();
      });
      final sharedParams = <String, Object?>{
        ..._params('evicted-follower'),
        'shared': true,
      };

      harness.sendRequest(
        id: 'followerOriginalB',
        method: 'health',
        params: sharedParams,
      );
      await entered.future;
      harness.sendRequest(
        id: 'evictedFollowerB',
        method: 'health',
        params: sharedParams,
      );
      expect(harness.peer.activeInboundRequestCount, 2);
      await _fillInboundHistory(harness, prefix: 'followerHistory');

      final duplicate = await harness.sendAndWait(
        id: 'evictedFollowerB',
        method: 'health',
        params: sharedParams,
      );
      expect(duplicate.error?.workerCode, 'duplicateRequestId');
      expect(harness.peer.activeInboundRequestCount, 2);

      final cancelledReply = harness.nextResponse('evictedFollowerB');
      expect(
        harness.peer.cancelInbound('evictedFollowerB'),
        CockpitRpcCancellationResult.cancelled,
      );
      expect((await cancelledReply).error?.workerCode, 'cancelled');
      expect(originalCancelled, isFalse);
      expect(harness.peer.activeInboundRequestCount, 1);

      harness.sendRequest(
        id: 'replacementFollowerB1',
        method: 'health',
        params: sharedParams,
      );
      harness.sendRequest(
        id: 'replacementFollowerB2',
        method: 'health',
        params: sharedParams,
      );
      expect(harness.peer.activeInboundRequestCount, 3);
      final unrelated = await harness.sendAndWait(
        id: 'duringEvictedFollowerB',
        method: 'health',
        params: const <String, Object?>{},
      );
      expect(unrelated.error, isNull);

      final originalReply = harness.nextResponse('followerOriginalB');
      final replacementReply1 = harness.nextResponse('replacementFollowerB1');
      final replacementReply2 = harness.nextResponse('replacementFollowerB2');
      release.complete();
      expect((await originalReply).error, isNull);
      expect((await replacementReply1).error, isNull);
      expect((await replacementReply2).error, isNull);
      expect(originalCancelled, isFalse);
      expect(harness.peer.activeInboundRequestCount, 0);
      expect(
        harness
            .responsesFor('evictedFollowerB')
            .map((response) => response.error?.workerCode),
        <String?>['duplicateRequestId', 'cancelled'],
      );
      expect(harness.responsesFor('followerOriginalB'), hasLength(1));
      expect(harness.responsesFor('replacementFollowerB1'), hasLength(1));
      expect(harness.responsesFor('replacementFollowerB2'), hasLength(1));
      expect(harness.peer.isClosed, isFalse);
      expect(harness.protocolErrors, isEmpty);
    },
  );

  test(
    'allows unrelated calls while a timeout awaits terminal cleanup',
    () async {
      final protocolErrors = <Object>[];
      final harness = _PeerHarness(
        (request, _) async {
          if (request.params['delay'] == true) {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          return <String, Object?>{'requestId': request.id};
        },
        serverUtcNow: () =>
            DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        clientProtocolError: (error, _) => protocolErrors.add(error),
      );
      harness.start();
      addTearDown(harness.close);

      var completed = false;
      final call = harness.client.call(
        method: 'health',
        params: <String, Object?>{..._params('late'), 'delay': true},
        deadline: DateTime.now().toUtc().add(const Duration(milliseconds: 20)),
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
      expect(harness.client.isOutboundCleanupPending, isTrue);
      expect(
        await harness.client.call(
          method: 'health',
          params: _params('during-cleanup'),
          deadline: _deadline(),
        ),
        isA<Map<String, Object?>>(),
      );
      expect(harness.client.isOutboundCleanupPending, isTrue);
      await expectLater(call, throwsA(isA<TimeoutException>()));
      expect(protocolErrors, isEmpty);
      expect(harness.client.isOutboundCleanupPending, isFalse);
      expect(
        await harness.client.call(
          method: 'health',
          params: _params('after-late'),
          deadline: _deadline(),
        ),
        isA<Map<String, Object?>>(),
      );
    },
  );

  test(
    'closes after a timed-out request never reaches a terminal response',
    () async {
      final never = Completer<Object?>();
      final harness = _PeerHarness(
        (request, _) => request.id == 'neverA'
            ? never.future
            : <String, Object?>{'requestId': request.id},
        clientCancellationGrace: const Duration(milliseconds: 5),
        clientForcedAbortGrace: const Duration(milliseconds: 20),
      );
      harness.start();
      addTearDown(harness.close);

      final call = harness.client.call(
        method: 'health',
        params: _params('never-terminal'),
        deadline: DateTime.now().toUtc().add(const Duration(milliseconds: 10)),
        requestId: 'neverA',
      );
      await expectLater(call, throwsA(isA<TimeoutException>()));
      await harness.client.done;
      expect(harness.client.isClosed, isTrue);
    },
  );

  test('generated request ids use a guaranteed valid prefix', () async {
    final harness = _PeerHarness(
      (request, _) => <String, Object?>{'requestId': request.id},
    );
    harness.start();
    addTearDown(harness.close);

    expect(
      await harness.client.call(
        method: 'health',
        params: _params('generated-request-id'),
        deadline: _deadline(),
      ),
      <String, Object?>{'requestId': startsWith('rpc_')},
    );
  });

  test('targets cancellation without affecting another call', () async {
    late _PeerHarness harness;
    harness = _PeerHarness((request, cancellation) async {
      if (request.method == 'cancel') {
        return <String, Object?>{
          'result': harness.server
              .cancelInbound(request.params['targetRequestId']! as String)
              .name,
        };
      }
      if (request.params['slow'] == true) {
        await cancellation.whenCancelled;
        cancellation.throwIfCancelled();
      }
      return <String, Object?>{'requestId': request.id};
    });
    harness.start();
    addTearDown(harness.close);
    final slow = harness.client.call(
      method: 'operation',
      params: <String, Object?>{..._params('slow'), 'slow': true},
      deadline: _deadline(),
      requestId: 'operationA',
    );
    final slowExpectation = expectLater(
      slow,
      throwsA(_remoteCode('cancelled')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      await harness.client.call(
        method: 'cancel',
        params: <String, Object?>{
          ..._params('cancel'),
          'targetRequestId': 'operationA',
        },
        deadline: _deadline(),
      ),
      <String, Object?>{'result': 'cancelled'},
    );
    await slowExpectation;
    expect(
      await harness.client.call(
        method: 'health',
        params: _params('unaffected'),
        deadline: _deadline(),
      ),
      isA<Map<String, Object?>>(),
    );
  });

  test('replays matching idempotency and rejects conflicts', () async {
    var executions = 0;
    final harness = _PeerHarness((request, _) {
      executions += 1;
      return <String, Object?>{
        'execution': executions,
        'value': request.params['value'],
      };
    });
    harness.start();
    addTearDown(harness.close);

    final first = await harness.client.call(
      method: 'health',
      params: <String, Object?>{
        ..._params('replay'),
        'value': 1,
        'requiredFeatures': <String>['featureB', 'featureA'],
      },
      deadline: _deadline(),
    );
    final replay = await harness.client.call(
      method: 'health',
      params: <String, Object?>{
        ..._params('replay'),
        'value': 1,
        'requiredFeatures': <String>['featureA', 'featureB'],
      },
      deadline: _deadline(),
    );
    expect(replay, first);
    expect(executions, 1);
    await expectLater(
      harness.client.call(
        method: 'health',
        params: <String, Object?>{..._params('replay'), 'value': 2},
        deadline: _deadline(),
      ),
      throwsA(_remoteCode('idempotencyConflict')),
    );
    expect(executions, 1);
  });

  test(
    'replays operation invocations with refreshed transport deadlines',
    () async {
      var executions = 0;
      final harness = _PeerHarness((_, _) {
        executions += 1;
        return <String, Object?>{'execution': executions};
      });
      harness.start();
      addTearDown(harness.close);

      Map<String, Object?> params({
        required String transportDeadline,
        required String semanticDeadline,
      }) => <String, Object?>{
        ..._params('operation-replay'),
        'invocation': <String, Object?>{
          'kind': 'command.batch',
          'deadline': transportDeadline,
          'input': <String, Object?>{'deadline': semanticDeadline},
        },
      };

      final first = await harness.client.call(
        method: 'operation',
        params: params(
          transportDeadline: '2026-08-02T15:00:00Z',
          semanticDeadline: '2030-01-01T00:00:00Z',
        ),
        deadline: _deadline(),
      );
      final replay = await harness.client.call(
        method: 'operation',
        params: params(
          transportDeadline: '2026-08-02T16:00:00Z',
          semanticDeadline: '2030-01-01T00:00:00Z',
        ),
        deadline: _deadline(),
      );

      expect(replay, first);
      expect(executions, 1);
      await expectLater(
        harness.client.call(
          method: 'operation',
          params: params(
            transportDeadline: '2026-08-02T17:00:00Z',
            semanticDeadline: '2031-01-01T00:00:00Z',
          ),
          deadline: _deadline(),
        ),
        throwsA(_remoteCode('idempotencyConflict')),
      );
      expect(executions, 1);
    },
  );

  test('uses a fresh idempotency key for each lease heartbeat', () async {
    var heartbeats = 0;
    final harness = _PeerHarness((request, _) {
      heartbeats += 1;
      final now = DateTime.now().toUtc();
      return CockpitWorkerOperationResult(
        CockpitOperationResult(
          operationId: 'heartbeat$heartbeats',
          kind: 'resource.heartbeat',
          workspaceId: 'workspaceA',
          lifecycle: CockpitOperationLifecycle.completed,
          outcome: CockpitOperationOutcome.succeeded,
          submittedAt: now,
          startedAt: now,
          finishedAt: now,
          output: const <String, Object?>{'renewed': true},
        ),
      ).toJson();
    });
    harness.start();
    addTearDown(harness.close);
    final authority = CockpitRpcResourceAuthorityClient(
      workspaceId: 'workspaceA',
      peer: harness.client,
    );
    final grant = CockpitWorkerResourceGrant(
      grantId: 'grantA',
      leaseId: 'leaseA',
      workspaceId: 'workspaceA',
      holderId: 'operationA',
      resourceKind: CockpitLeaseResourceKind.session,
      resourceId: 'sessionA',
      expiresAt: _deadline(),
    );

    await authority.heartbeat(grant);
    await authority.heartbeat(grant);
    expect(heartbeats, 2);
  });

  test('resource client preserves a remote resource rejection', () async {
    final harness = _PeerHarness((request, _) {
      throw CockpitJsonRpcRemoteException(
        CockpitJsonRpcError(
          code: -32000,
          message: 'Lease wait timeout expired.',
          workerCode: CockpitErrorCode.resourceBusy,
          details: const <String, Object?>{
            'lease': <String, Object?>{'resourceKind': 'device'},
          },
        ),
      );
    });
    harness.start();
    addTearDown(harness.close);
    final authority = CockpitRpcResourceAuthorityClient(
      workspaceId: 'workspaceA',
      peer: harness.client,
    );

    await expectLater(
      authority.acquire(
        CockpitWorkerResourceRequest(
          resourceKind: CockpitLeaseResourceKind.device,
          resourceId: 'deviceA',
          wait: const Duration(seconds: 3),
        ),
        workspaceId: 'workspaceA',
        holderId: 'operationA',
        idempotencyKey: 'device-busy',
        deadline: _deadline(),
      ),
      throwsA(
        isA<CockpitWorkerResourceException>()
            .having(
              (error) => error.code,
              'code',
              CockpitErrorCode.resourceBusy,
            )
            .having((error) => error.details['lease'], 'lease', isNotNull),
      ),
    );
  });

  test('does not evict in-flight idempotency entries at capacity', () async {
    final allEntered = Completer<void>();
    final release = Completer<void>();
    var entered = 0;
    final harness = _PeerHarness((request, _) async {
      entered += 1;
      if (entered == 32) allEntered.complete();
      await release.future;
      return <String, Object?>{'slot': request.params['slot']};
    }, maximumIdempotencyEntries: 32);
    harness.start();
    addTearDown(harness.close);
    final pending = <Future<Object?>>[
      for (var index = 0; index < 32; index += 1)
        harness.client.call(
          method: 'health',
          params: <String, Object?>{
            ..._params('capacity-$index'),
            'slot': index,
          },
          deadline: _deadline(),
        ),
    ];
    await allEntered.future;

    await expectLater(
      harness.client.call(
        method: 'health',
        params: <String, Object?>{..._params('capacity-overflow'), 'slot': 32},
        deadline: _deadline(),
      ),
      throwsA(_remoteCode('idempotencyCapacityExceeded')),
    );
    expect(entered, 32);
    release.complete();
    expect(await Future.wait(pending), hasLength(32));
  });

  test(
    'cancels and bounds followers without affecting their shared execution',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final protocolErrors = <Object>[];
      var executions = 0;
      late _PeerHarness harness;
      harness = _PeerHarness(
        (request, _) async {
          if (request.method == 'cancel') {
            return <String, Object?>{
              'result': harness.server
                  .cancelInbound(request.params['targetRequestId']! as String)
                  .name,
            };
          }
          if (request.params['shared'] == true) {
            executions += 1;
            if (!entered.isCompleted) entered.complete();
            await release.future;
            return <String, Object?>{'execution': executions};
          }
          return <String, Object?>{'requestId': request.id};
        },
        clientProtocolError: (error, _) => protocolErrors.add(error),
        maximumActiveIdempotentFollowers: 1,
      );
      harness.start();
      addTearDown(harness.close);

      final original = harness.client.call(
        method: 'health',
        params: <String, Object?>{..._params('shared'), 'shared': true},
        deadline: _deadline(),
        requestId: 'originalA',
      );
      await entered.future;
      final follower = harness.client.call(
        method: 'health',
        params: <String, Object?>{..._params('shared'), 'shared': true},
        deadline: _deadline(),
        requestId: 'followerA',
      );
      final followerExpectation = expectLater(
        follower,
        throwsA(_remoteCode('cancelled')),
      );
      await expectLater(
        harness.client.call(
          method: 'health',
          params: <String, Object?>{..._params('shared'), 'shared': true},
          deadline: _deadline(),
          requestId: 'overflowFollowerA',
        ),
        throwsA(_remoteCode('idempotencyFollowerCapacityExceeded')),
      );

      expect(
        await harness.client.call(
          method: 'cancel',
          params: <String, Object?>{
            ..._params('cancel-follower'),
            'targetRequestId': 'followerA',
          },
          deadline: _deadline(),
        ),
        <String, Object?>{'result': 'cancelled'},
      );
      await followerExpectation;
      final replacementFollower = harness.client.call(
        method: 'health',
        params: <String, Object?>{..._params('shared'), 'shared': true},
        deadline: _deadline(),
        requestId: 'replacementFollowerA',
      );
      expect(
        await harness.client.call(
          method: 'health',
          params: _params('unrelated-during-shared-execution'),
          deadline: _deadline(),
        ),
        isA<Map<String, Object?>>(),
      );
      expect(harness.client.isClosed, isFalse);
      expect(harness.server.isClosed, isFalse);

      release.complete();
      expect(await original, <String, Object?>{'execution': 1});
      expect(await replacementFollower, <String, Object?>{'execution': 1});
      expect(executions, 1);
      expect(protocolErrors, isEmpty);
    },
  );

  test(
    'follower deadline terminates only that follower and keeps peer open',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final protocolErrors = <Object>[];
      final harness = _PeerHarness(
        (request, _) async {
          if (request.params['shared'] == true) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
            return <String, Object?>{'requestId': request.id};
          }
          return <String, Object?>{'requestId': request.id};
        },
        clientProtocolError: (error, _) => protocolErrors.add(error),
        clientCancellationGrace: const Duration(milliseconds: 5),
        clientForcedAbortGrace: const Duration(milliseconds: 20),
      );
      harness.start();
      addTearDown(harness.close);

      final original = harness.client.call(
        method: 'health',
        params: <String, Object?>{
          ..._params('deadline-shared'),
          'shared': true,
        },
        deadline: _deadline(),
        requestId: 'deadlineOriginalA',
      );
      await entered.future;
      final follower = harness.client.call(
        method: 'health',
        params: <String, Object?>{
          ..._params('deadline-shared'),
          'shared': true,
        },
        deadline: DateTime.now().toUtc().add(const Duration(milliseconds: 30)),
        requestId: 'deadlineFollowerA',
      );
      await expectLater(
        follower,
        throwsA(
          anyOf(isA<TimeoutException>(), _remoteCode('deadlineExceeded')),
        ),
      );

      expect(harness.client.isClosed, isFalse);
      expect(harness.server.isClosed, isFalse);
      expect(
        await harness.client.call(
          method: 'health',
          params: _params('unrelated-after-follower-deadline'),
          deadline: _deadline(),
        ),
        isA<Map<String, Object?>>(),
      );
      release.complete();
      expect(await original, <String, Object?>{
        'requestId': 'deadlineOriginalA',
      });
      expect(protocolErrors, isEmpty);
    },
  );
}

Map<String, Object?> _params(String key) => <String, Object?>{
  'workspaceId': 'workspaceA',
  'idempotencyKey': key,
};

DateTime _deadline() => DateTime.now().toUtc().add(const Duration(seconds: 5));

Matcher _remoteCode(String code) => isA<CockpitJsonRpcRemoteException>().having(
  (error) => error.error.workerCode,
  'workerCode',
  code,
);

Future<void> _fillInboundHistory(
  _RawServerHarness harness, {
  required String prefix,
}) async {
  for (var index = 0; index < 128; index += 1) {
    final response = await harness.sendAndWait(
      id: '$prefix$index',
      method: 'health',
      params: <String, Object?>{'index': index},
    );
    expect(response.error, isNull);
  }
}

final class _RawServerHarness {
  factory _RawServerHarness(
    CockpitJsonRpcRequestHandler requestHandler, {
    required int maximumRememberedRequestIds,
    int maximumActiveIdempotentFollowers = 2048,
  }) {
    final input = StreamController<List<int>>(sync: true);
    final output = StreamController<List<int>>(sync: true);
    final responseEvents = StreamController<CockpitJsonRpcResponse>.broadcast(
      sync: true,
    );
    final responses = <CockpitJsonRpcResponse>[];
    final protocolErrors = <Object>[];
    final outputSubscription = output.stream.listen((bytes) {
      final raw =
          jsonDecode(utf8.decode(bytes).trim())! as Map<Object?, Object?>;
      final message = CockpitJsonRpcMessage.fromJson(
        raw.cast<String, Object?>(),
      );
      if (message is! CockpitJsonRpcResponse) {
        throw StateError('Raw server emitted a non-response message.');
      }
      responses.add(message);
      responseEvents.add(message);
    });
    return _RawServerHarness._(
      input: input,
      responseEvents: responseEvents,
      responses: responses,
      protocolErrors: protocolErrors,
      outputSubscription: outputSubscription,
      peer: CockpitJsonRpcPeer(
        input: input.stream,
        output: output.sink,
        requestHandler: requestHandler,
        onProtocolError: (error, _) => protocolErrors.add(error),
        maximumRememberedRequestIds: maximumRememberedRequestIds,
        maximumActiveIdempotentFollowers: maximumActiveIdempotentFollowers,
      ),
    );
  }

  const _RawServerHarness._({
    required StreamController<List<int>> input,
    required StreamController<CockpitJsonRpcResponse> responseEvents,
    required List<CockpitJsonRpcResponse> responses,
    required this.protocolErrors,
    required StreamSubscription<List<int>> outputSubscription,
    required this.peer,
  }) : _input = input,
       _responseEvents = responseEvents,
       _responses = responses,
       _outputSubscription = outputSubscription;

  final CockpitJsonRpcPeer peer;
  final StreamController<List<int>> _input;
  final StreamController<CockpitJsonRpcResponse> _responseEvents;
  final List<CockpitJsonRpcResponse> _responses;
  final List<Object> protocolErrors;
  final StreamSubscription<List<int>> _outputSubscription;

  void start() => peer.start();

  void sendRequest({
    required String id,
    required String method,
    required Map<String, Object?> params,
  }) {
    final request = CockpitJsonRpcRequest(
      id: id,
      method: method,
      params: params,
    );
    _input.add(utf8.encode('${jsonEncode(request.toJson())}\n'));
  }

  Future<CockpitJsonRpcResponse> sendAndWait({
    required String id,
    required String method,
    required Map<String, Object?> params,
  }) {
    final response = nextResponse(id);
    sendRequest(id: id, method: method, params: params);
    return response;
  }

  Future<CockpitJsonRpcResponse> nextResponse(String id) =>
      _responseEvents.stream.firstWhere((response) => response.id == id);

  List<CockpitJsonRpcResponse> responsesFor(String id) =>
      _responses.where((response) => response.id == id).toList(growable: false);

  Future<void> close() async {
    await peer.close();
    await _input.close();
    await _outputSubscription.cancel();
    await _responseEvents.close();
  }
}

final class _PeerHarness {
  factory _PeerHarness(
    CockpitJsonRpcRequestHandler serverHandler, {
    DateTime Function()? serverUtcNow,
    CockpitJsonRpcProtocolErrorHandler? clientProtocolError,
    int maximumIdempotencyEntries = 2048,
    int maximumActiveIdempotentFollowers = 2048,
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
        maximumIdempotencyEntries: maximumIdempotencyEntries,
        maximumActiveIdempotentFollowers: maximumActiveIdempotentFollowers,
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
) => throw StateError('Client requests are not expected.');
