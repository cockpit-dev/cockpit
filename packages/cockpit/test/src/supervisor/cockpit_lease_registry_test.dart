import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/supervisor/cockpit_lease_registry.dart';
import 'package:cockpit/src/supervisor/cockpit_lease_registry_activity.dart';
import 'package:cockpit/src/supervisor/cockpit_lease_support.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_identity.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

import 'cockpit_lease_test_support.dart';

void main() {
  group('durable lease admission', () {
    test(
      'serializes the same canonical physical device across workspaces',
      () async {
        final fixture = await CockpitLeaseTestFixture.create();
        addTearDown(fixture.dispose);
        final firstResourceId = cockpitCanonicalDeviceResourceId(
          platform: ' Android ',
          deviceId: 'emulator-5554',
        );
        final secondResourceId = cockpitCanonicalDeviceResourceId(
          platform: 'android',
          deviceId: 'emulator-5554',
        );

        expect(secondResourceId, firstResourceId);
        final first = await fixture.registry.acquire(
          leaseRequest(
            key: 'physical-device.workspace-a',
            resourceId: firstResourceId,
          ),
        );
        await expectLater(
          fixture.registry.acquire(
            leaseRequest(
              key: 'physical-device.workspace-b',
              resourceId: secondResourceId,
              workspaceId: 'workspaceB',
              holderId: 'runB',
              waitTimeoutMs: 0,
            ),
          ),
          throwsLease('resourceBusy'),
        );

        await fixture.registry.release(first.leaseId, holderId: first.holderId);
      },
    );

    test(
      'replays idempotently and grants one resource in FIFO order',
      () async {
        final fixture = await CockpitLeaseTestFixture.create();
        addTearDown(fixture.dispose);
        final firstRequest = leaseRequest(
          key: 'request.first',
          resourceId: 'device-1',
          waitTimeoutMs: 0,
        );
        final first = await fixture.registry.acquire(firstRequest);
        final replay = await fixture.registry.acquire(firstRequest);
        expect(replay.leaseId, first.leaseId);
        await expectLater(
          fixture.registry.acquire(
            leaseRequest(
              key: 'request.first',
              resourceId: 'device-2',
              waitTimeoutMs: 0,
            ),
          ),
          throwsLease('idempotencyConflict'),
        );

        final secondFuture = fixture.registry.acquire(
          leaseRequest(
            key: 'request.second',
            resourceId: 'device-1',
            holderId: 'runB',
            waitTimeoutMs: 5000,
          ),
        );
        await waitForLeaseCondition(() async {
          final leases = await fixture.registry.list(resourceId: 'device-1');
          return leases.any(
            (lease) =>
                lease.holderId == 'runB' &&
                lease.state == CockpitLeaseState.queued,
          );
        });
        final thirdFuture = fixture.registry.acquire(
          leaseRequest(
            key: 'request.third',
            resourceId: 'device-1',
            holderId: 'runC',
            waitTimeoutMs: 5000,
          ),
        );
        await waitForLeaseCondition(() async {
          final leases = await fixture.registry.list(resourceId: 'device-1');
          return leases
                  .where((lease) => lease.state == CockpitLeaseState.queued)
                  .length ==
              2;
        });

        final independent = await fixture.registry.acquire(
          leaseRequest(
            key: 'request.independent',
            resourceId: 'device-2',
            workspaceId: 'workspaceB',
            holderId: 'runD',
            waitTimeoutMs: 0,
          ),
        );
        expect(independent.state, CockpitLeaseState.active);

        await fixture.registry.release(first.leaseId, holderId: first.holderId);
        final second = await secondFuture;
        expect(second.holderId, 'runB');
        expect(second.state, CockpitLeaseState.active);
        expect(
          (await fixture.registry.get(
            (await fixture.registry.list(
              resourceId: 'device-1',
            )).singleWhere((lease) => lease.holderId == 'runC').leaseId,
          )).queuePosition,
          0,
        );

        await fixture.registry.release(
          second.leaseId,
          holderId: second.holderId,
        );
        final third = await thirdFuture;
        expect(third.holderId, 'runC');
        await fixture.registry.release(third.leaseId, holderId: third.holderId);
        await fixture.registry.release(
          independent.leaseId,
          holderId: independent.holderId,
        );
      },
    );

    test('covers every exclusive Workstream 1 resource kind', () async {
      final fixture = await CockpitLeaseTestFixture.create();
      addTearDown(fixture.dispose);
      for (final kind in CockpitLeaseResourceKind.values) {
        final lease = await fixture.registry.acquire(
          leaseRequest(
            key: 'kind.${kind.name}',
            resourceId: 'resource-${kind.name}',
            resourceKind: kind,
            waitTimeoutMs: 0,
          ),
        );
        expect(lease.resourceKind, kind);
        expect(
          (await fixture.registry.release(
            lease.leaseId,
            holderId: lease.holderId,
          )).state,
          CockpitLeaseState.released,
        );
      }
    });

    test('shares root admission fences with workspace retirement', () async {
      final fixture = await CockpitLeaseTestFixture.create();
      addTearDown(fixture.dispose);
      final entered = Completer<void>();
      final releaseFence = Completer<void>();
      final fence = fixture.registry.withAdmissionFence(
        <String>{'rootA'},
        const <String>{},
        () async {
          entered.complete();
          await releaseFence.future;
        },
      );
      await entered.future;
      var completed = false;
      final acquisition = fixture.registry
          .acquire(
            leaseRequest(
              key: 'fenced.request',
              resourceId: 'fenced-device',
              waitTimeoutMs: 0,
            ),
          )
          .then((lease) {
            completed = true;
            return lease;
          });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(completed, isFalse);
      releaseFence.complete();
      await fence;
      final lease = await acquisition;
      expect(await fixture.registry.activeReferenceCount('workspaceA'), 1);
      await fixture.registry.release(lease.leaseId, holderId: lease.holderId);
      expect(await fixture.registry.activeReferenceCount('workspaceA'), 0);
    });

    test(
      'cancels while waiting behind the workspace admission fence',
      () async {
        final fixture = await CockpitLeaseTestFixture.create();
        addTearDown(fixture.dispose);
        final entered = Completer<void>();
        final releaseFence = Completer<void>();
        final fence = fixture.registry.withAdmissionFence(
          <String>{'rootA'},
          <String>{'workspaceA'},
          () async {
            entered.complete();
            await releaseFence.future;
          },
        );
        await entered.future;
        final cancellation = CockpitLeaseCancellationToken();
        final acquisition = fixture.registry.acquire(
          leaseRequest(
            key: 'fenced.cancelled',
            resourceId: 'fenced-cancelled-device',
            waitTimeoutMs: 0,
          ),
          cancellation: cancellation,
        );
        final cancelled = expectLater(
          acquisition,
          throwsLease('leaseCancelled'),
        );
        cancellation.cancel();
        releaseFence.complete();
        await fence;
        await cancelled;
        expect(await fixture.registry.list(), isEmpty);
      },
    );

    test(
      'coordinates FIFO ownership across independent registry instances',
      () async {
        final fixture = await CockpitLeaseTestFixture.create();
        addTearDown(fixture.dispose);
        final restarted = fixture.reopen();
        final first = await fixture.registry.acquire(
          leaseRequest(
            key: 'process.first',
            resourceId: 'shared-process-resource',
            waitTimeoutMs: 0,
          ),
        );
        final secondFuture = restarted.acquire(
          leaseRequest(
            key: 'process.second',
            resourceId: 'shared-process-resource',
            holderId: 'runB',
            waitTimeoutMs: 5000,
          ),
        );
        await waitForLeaseCondition(() async {
          final records = await fixture.registry.list(
            resourceId: 'shared-process-resource',
          );
          return records.any(
            (lease) =>
                lease.holderId == 'runB' &&
                lease.state == CockpitLeaseState.queued,
          );
        });
        await fixture.registry.release(first.leaseId, holderId: first.holderId);
        final second = await secondFuture;
        expect(second.state, CockpitLeaseState.active);
        await restarted.release(second.leaseId, holderId: second.holderId);
      },
    );
  });

  group('lease lifecycle and recovery', () {
    test('heartbeats, renews, cancels, and bounds queued waits', () async {
      final clock = TestLeaseClock();
      final fixture = await CockpitLeaseTestFixture.create(clock: clock);
      addTearDown(fixture.dispose);
      final first = await fixture.registry.acquire(
        leaseRequest(
          key: 'lifecycle.first',
          resourceId: 'device-lifecycle',
          waitTimeoutMs: 0,
          ttlMs: 2000,
        ),
      );
      clock.advance(const Duration(seconds: 1));
      final heartbeat = await fixture.registry.heartbeat(
        first.leaseId,
        holderId: first.holderId,
      );
      expect(heartbeat.expiresAt, clock.utcNow.add(const Duration(seconds: 2)));
      final renewed = await fixture.registry.renew(
        first.leaseId,
        holderId: first.holderId,
        ttl: const Duration(seconds: 5),
      );
      expect(renewed.expiresAt, clock.utcNow.add(const Duration(seconds: 5)));
      await expectLater(
        fixture.registry.heartbeat(first.leaseId, holderId: 'runWrong'),
        throwsLease('leaseHolderMismatch'),
      );

      final cancellation = CockpitLeaseCancellationToken();
      final cancelled = fixture.registry.acquire(
        leaseRequest(
          key: 'lifecycle.cancelled',
          resourceId: 'device-lifecycle',
          holderId: 'runB',
        ),
        cancellation: cancellation,
      );
      await waitForLeaseCondition(() async {
        final leases = await fixture.registry.list(
          resourceId: 'device-lifecycle',
        );
        return leases.any(
          (lease) =>
              lease.holderId == 'runB' &&
              lease.state == CockpitLeaseState.queued,
        );
      });
      cancellation.cancel();
      await expectLater(cancelled, throwsLease('leaseCancelled'));

      final timedOut = fixture.registry.acquire(
        leaseRequest(
          key: 'lifecycle.timeout',
          resourceId: 'device-lifecycle',
          holderId: 'runC',
          waitTimeoutMs: 1000,
        ),
      );
      await waitForLeaseCondition(() async {
        final leases = await fixture.registry.list(
          resourceId: 'device-lifecycle',
        );
        return leases.any(
          (lease) =>
              lease.holderId == 'runC' &&
              lease.state == CockpitLeaseState.queued,
        );
      });
      clock.advance(const Duration(milliseconds: 1001));
      await expectLater(timedOut, throwsLease('resourceBusy'));
      await fixture.registry.release(first.leaseId, holderId: first.holderId);
    });

    test(
      'cancels a queued request even when it becomes active first',
      () async {
        final fixture = await CockpitLeaseTestFixture.create();
        addTearDown(fixture.dispose);
        final first = await fixture.registry.acquire(
          leaseRequest(
            key: 'cancel-grant.first',
            resourceId: 'cancel-grant-device',
            waitTimeoutMs: 0,
          ),
        );
        final cancellation = _SilentLeaseCancellationSignal();
        final second = fixture.registry.acquire(
          leaseRequest(
            key: 'cancel-grant.second',
            resourceId: 'cancel-grant-device',
            holderId: 'runB',
          ),
          cancellation: cancellation,
        );
        final cancelled = expectLater(second, throwsLease('leaseCancelled'));
        await waitForLeaseCondition(() async {
          final leases = await fixture.registry.list(
            resourceId: 'cancel-grant-device',
          );
          return leases.any(
            (lease) =>
                lease.holderId == 'runB' &&
                lease.state == CockpitLeaseState.queued,
          );
        });
        cancellation.cancelWithoutNotification();
        await fixture.registry.release(first.leaseId, holderId: first.holderId);
        await cancelled;
        final replay = (await fixture.registry.list(
          resourceId: 'cancel-grant-device',
        )).singleWhere((lease) => lease.holderId == 'runB');
        expect(replay.state, CockpitLeaseState.released);
      },
    );

    test(
      'never reassigns an expired resource before healthy cleanup',
      () async {
        final clock = TestLeaseClock();
        final fixture = await CockpitLeaseTestFixture.create(clock: clock);
        addTearDown(fixture.dispose);
        final first = await fixture.registry.acquire(
          leaseRequest(
            key: 'quarantine.first',
            resourceId: 'device-quarantine',
            waitTimeoutMs: 0,
            ttlMs: 1000,
          ),
        );
        fixture.cleanup.enqueue(
          Future<CockpitLeaseCleanupResult>.value(
            CockpitLeaseCleanupResult.quarantined(
              testLeaseFailure('cleanupRejected'),
            ),
          ),
        );
        clock.advance(const Duration(milliseconds: 1001));
        expect(
          (await fixture.registry.get(first.leaseId)).state,
          CockpitLeaseState.expired,
        );
        await fixture.registry.recover();
        expect(
          (await fixture.registry.get(first.leaseId)).state,
          CockpitLeaseState.quarantined,
        );

        final secondRequest = leaseRequest(
          key: 'quarantine.second',
          resourceId: 'device-quarantine',
          holderId: 'runB',
        );
        await expectLater(
          fixture.registry.acquire(secondRequest),
          throwsLease('resourceQuarantined'),
        );
        expect(
          (await fixture.registry.list(
            resourceId: 'device-quarantine',
          )).where((lease) => lease.holderId == 'runB'),
          isEmpty,
        );

        await fixture.registry.recoverResource(
          CockpitLeaseResourceKind.device,
          'device-quarantine',
        );
        clock.advance(const Duration(milliseconds: 5));
        final second = await fixture.registry.acquire(secondRequest);
        expect(second.state, CockpitLeaseState.active);
        await fixture.registry.release(
          second.leaseId,
          holderId: second.holderId,
        );
      },
    );

    test(
      'explicit force release recovers quarantined logical resources',
      () async {
        final clock = TestLeaseClock();
        final fixture = await CockpitLeaseTestFixture.create(clock: clock);
        addTearDown(fixture.dispose);
        final lease = await fixture.registry.acquire(
          leaseRequest(
            key: 'force-recovery.first',
            resourceId: 'force-recovery-device',
            waitTimeoutMs: 0,
            ttlMs: 1000,
          ),
        );
        fixture.cleanup.enqueue(
          Future<CockpitLeaseCleanupResult>.value(
            CockpitLeaseCleanupResult.quarantined(
              testLeaseFailure('forceRecoveryRequired'),
            ),
          ),
        );
        clock.advance(const Duration(milliseconds: 1001));
        await fixture.registry.recover();

        final released = await fixture.registry.forceReleaseQuarantined(
          leaseId: lease.leaseId,
          workspaceId: lease.workspaceId,
          resourceKind: lease.resourceKind,
          resourceId: lease.resourceId,
          holderId: lease.holderId,
        );
        expect(released.before.state, CockpitLeaseState.quarantined);
        expect(released.after.state, CockpitLeaseState.released);
        expect(released.forceReleased, isTrue);

        final replay = await fixture.registry.forceReleaseQuarantined(
          leaseId: lease.leaseId,
          workspaceId: lease.workspaceId,
          resourceKind: lease.resourceKind,
          resourceId: lease.resourceId,
          holderId: lease.holderId,
        );
        expect(replay.forceReleased, isFalse);
        await expectLater(
          fixture.registry.forceReleaseQuarantined(
            leaseId: lease.leaseId,
            workspaceId: lease.workspaceId,
            resourceKind: CockpitLeaseResourceKind.forwardedPort,
            resourceId: lease.resourceId,
            holderId: lease.holderId,
          ),
          throwsLease('leaseForceReleaseForbidden'),
        );
      },
    );

    test(
      'reclaims crash-expired resources and cleans different resources in parallel',
      () async {
        final clock = TestLeaseClock();
        final fixture = await CockpitLeaseTestFixture.create(clock: clock);
        addTearDown(fixture.dispose);
        final first = await fixture.registry.acquire(
          leaseRequest(
            key: 'recovery.first',
            resourceId: 'device-recovery-a',
            waitTimeoutMs: 0,
            ttlMs: 1000,
          ),
        );
        final second = await fixture.registry.acquire(
          leaseRequest(
            key: 'recovery.second',
            resourceId: 'device-recovery-b',
            waitTimeoutMs: 0,
            ttlMs: 1000,
          ),
        );
        final firstCleanup = Completer<CockpitLeaseCleanupResult>();
        final secondCleanup = Completer<CockpitLeaseCleanupResult>();
        fixture.cleanup
          ..enqueue(firstCleanup.future)
          ..enqueue(secondCleanup.future);
        clock.advance(const Duration(milliseconds: 1001));

        final restarted = fixture.reopen();
        var recovered = false;
        final recovery = restarted.recover().then((_) => recovered = true);
        await waitForLeaseCondition(
          () async => fixture.cleanup.contexts.length == 2,
        );
        expect(recovered, isFalse);
        expect(
          (await restarted.get(first.leaseId)).state,
          CockpitLeaseState.expired,
        );
        expect(
          (await restarted.get(second.leaseId)).state,
          CockpitLeaseState.expired,
        );
        firstCleanup.complete(const CockpitLeaseCleanupResult.restored());
        secondCleanup.complete(const CockpitLeaseCleanupResult.restored());
        await recovery;
        expect(
          (await restarted.get(first.leaseId)).state,
          CockpitLeaseState.released,
        );
        expect(
          (await restarted.get(second.leaseId)).state,
          CockpitLeaseState.released,
        );
      },
    );

    test(
      'waits for an abandoned cleanup claim and reclaims it before startup completes',
      () async {
        final clock = TestLeaseClock();
        final fixture = await CockpitLeaseTestFixture.create(clock: clock);
        addTearDown(fixture.dispose);
        final lease = await fixture.registry.acquire(
          leaseRequest(
            key: 'recovery.claim',
            resourceId: 'device-abandoned-claim',
            waitTimeoutMs: 0,
            ttlMs: 1000,
          ),
        );
        clock.advance(const Duration(milliseconds: 1001));
        final file = File(fixture.paths.leaseRegistry);
        final document =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        final record =
            (document['leases']! as List<Object?>).single!
                as Map<String, Object?>;
        record
          ..['state'] = CockpitLeaseState.expired.name
          ..['cleanupReason'] = CockpitLeaseCleanupReason.expiry.name
          ..['cleanupClaimId'] = 'cleanup_abandoned'
          ..['cleanupClaimExpiresAt'] = clock.utcNow
              .add(const Duration(seconds: 1))
              .toIso8601String();
        await file.writeAsString('${jsonEncode(document)}\n');

        final restartedCleanup = TestLeaseCleanupProbe();
        final restarted = fixture.reopen(
          cleanupProbes: CockpitLeaseCleanupProbeMap(
            <CockpitLeaseResourceKind, CockpitLeaseCleanupProbe>{
              for (final kind in CockpitLeaseResourceKind.values)
                kind: restartedCleanup,
            },
          ),
        );
        var completed = false;
        final recovery = restarted.recover().then((_) => completed = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(completed, isFalse);
        expect(restartedCleanup.contexts, isEmpty);

        clock.advance(const Duration(milliseconds: 1001));
        await recovery;
        expect(restartedCleanup.contexts, hasLength(1));
        expect(
          (await restarted.get(lease.leaseId)).state,
          CockpitLeaseState.released,
        );
      },
    );

    test('drains workspace leases without cancelling active work', () async {
      final fixture = await CockpitLeaseTestFixture.create();
      addTearDown(fixture.dispose);
      final lease = await fixture.registry.acquire(
        leaseRequest(
          key: 'activity.first',
          resourceId: 'activity-device',
          waitTimeoutMs: 0,
        ),
      );
      final controller = CockpitLeaseRegistryActivityController(
        leases: fixture.registry,
      );
      var completed = false;
      final drain = controller
          .drainWorkspaces(<String>{'workspaceA'}, const Duration(seconds: 2))
          .then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(completed, isFalse);
      expect(fixture.cleanup.contexts, isEmpty);

      await fixture.registry.release(lease.leaseId, holderId: lease.holderId);
      await drain;
      expect(await fixture.registry.activeReferenceCount('workspaceA'), 0);
      expect(
        fixture.cleanup.contexts.single.reason,
        CockpitLeaseCleanupReason.release,
      );
    });

    test('force accepts quarantine as a terminal workspace state', () async {
      final fixture = await CockpitLeaseTestFixture.create();
      addTearDown(fixture.dispose);
      fixture.cleanup.enqueue(
        Future<CockpitLeaseCleanupResult>.value(
          CockpitLeaseCleanupResult.quarantined(
            testLeaseFailure('activity.cleanup.failed'),
          ),
        ),
      );
      final lease = await fixture.registry.acquire(
        leaseRequest(
          key: 'activity.force',
          resourceId: 'activity-force-device',
          waitTimeoutMs: 0,
        ),
      );

      await CockpitLeaseRegistryActivityController(
        leases: fixture.registry,
      ).forceWorkspaces(<String>{'workspaceA'});

      expect(
        (await fixture.registry.get(lease.leaseId)).state,
        CockpitLeaseState.quarantined,
      );
      expect(await fixture.registry.activeReferenceCount('workspaceA'), 0);
    });
  });

  group('lease persistence validation', () {
    test(
      'rejects unknown and semantically conflicting durable state',
      () async {
        final fixture = await CockpitLeaseTestFixture.create();
        addTearDown(fixture.dispose);
        final lease = await fixture.registry.acquire(
          leaseRequest(
            key: 'persistence.first',
            resourceId: 'persistence-device',
            waitTimeoutMs: 0,
          ),
        );
        final file = File(fixture.paths.leaseRegistry);
        final original =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        final first = Map<String, Object?>.of(
          (original['leases']! as List<Object?>).single!
              as Map<String, Object?>,
        );
        final duplicate = Map<String, Object?>.of(first)
          ..['leaseId'] = 'lease_conflict'
          ..['idempotencyKey'] = 'persistence.conflict'
          ..['holderId'] = 'runB'
          ..['sequence'] = 1;
        original['nextSequence'] = 2;
        original['leases'] = <Object?>[first, duplicate];
        await file.writeAsString(jsonEncode(original));
        await expectLater(
          fixture.registry.list(),
          throwsA(
            isA<CockpitStorageException>().having(
              (error) => error.code,
              'code',
              'storageCorrupt',
            ),
          ),
        );
        expect(await file.readAsString(), contains(lease.leaseId));

        original
          ..['leases'] = <Object?>[]
          ..['nextSequence'] = 0
          ..['unknown'] = true;
        await file.writeAsString(jsonEncode(original));
        await expectLater(
          fixture.registry.list(),
          throwsA(isA<CockpitStorageException>()),
        );
        expect(await file.readAsString(), contains('"unknown":true'));
      },
    );
  });
}

Matcher throwsLease(String code) => throwsA(
  isA<CockpitLeaseException>().having((error) => error.code, 'code', code),
);

final class _SilentLeaseCancellationSignal
    implements CockpitLeaseCancellationSignal {
  bool _cancelled = false;
  final Completer<void> _notification = Completer<void>();

  @override
  bool get isCancelled => _cancelled;

  @override
  Future<void> get whenCancelled => _notification.future;

  void cancelWithoutNotification() {
    _cancelled = true;
  }
}
