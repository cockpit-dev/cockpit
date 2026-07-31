import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/supervisor/cockpit_local_worker_launcher.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_run_projection.dart';
import 'package:cockpit/src/supervisor/cockpit_worker_pool.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_request.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String stateRoot;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-projection-');
    stateRoot = await temporary.resolveSymbolicLinks();
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'duplicate publish converges after the persisted response is lost',
    () async {
      final request = _publish(
        'runA',
        afterSequence: 0,
        events: [_event('runA', 1)],
      );
      expect(
        (await _projection(
          stateRoot,
        ).publish(request)).highestContiguousSequence,
        1,
      );

      final restarted = _projection(stateRoot);
      final duplicate = await restarted.publish(request);

      expect(duplicate.highestContiguousSequence, 1);
      expect(
        (await restarted.readEvents('runA', afterSequence: 0)).events,
        hasLength(1),
      );
    },
  );

  test('rejects a global event id conflict across runs', () async {
    final projection = _projection(stateRoot);
    await projection.publish(
      _publish(
        'runA',
        afterSequence: 0,
        events: [_event('runA', 1, id: 'shared')],
      ),
    );

    await expectLater(
      projection.publish(
        _publish(
          'runB',
          afterSequence: 0,
          events: [_event('runB', 1, id: 'shared')],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('reports an explicit contiguous publication gap', () async {
    final projection = _projection(stateRoot);
    await projection.publish(
      _publish('runA', afterSequence: 0, events: [_event('runA', 1)]),
    );

    final gap = await projection.publish(
      _publish('runA', afterSequence: 2, events: [_event('runA', 3)]),
    );

    expect(gap.highestContiguousSequence, 1);
    expect(gap.replayAfterSequence, 1);
  });

  test(
    'preflights the event owner bound without a partial projection write',
    () async {
      final projection = _projection(stateRoot, maximumEventOwners: 3);
      await projection.publish(
        _publish(
          'runA',
          afterSequence: 0,
          events: [_event('runA', 1), _event('runA', 2)],
        ),
      );

      await expectLater(
        projection.publish(
          _publish(
            'runA',
            afterSequence: 2,
            events: [_event('runA', 3), _event('runA', 4)],
          ),
        ),
        throwsA(isA<FormatException>()),
      );

      final reopened = _projection(stateRoot, maximumEventOwners: 3);
      final replay = await reopened.readEvents('runA', afterSequence: 0);
      expect(
        replay.events.map((event) => event.sequence),
        orderedEquals(<int>[1, 2]),
      );
    },
  );

  test('validates the persisted event owner bound when reopening', () async {
    final projection = _projection(stateRoot, maximumEventOwners: 2);
    await projection.publish(
      _publish(
        'runA',
        afterSequence: 0,
        events: [_event('runA', 1), _event('runA', 2)],
      ),
    );

    await expectLater(
      _projection(
        stateRoot,
        maximumEventOwners: 1,
      ).readEvents('runA', afterSequence: 0),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'exposes a retained-buffer replay boundary instead of skipping',
    () async {
      final projection = _projection(
        stateRoot,
        maximumRetainedEventsPerRun: 256,
      );
      await projection.publish(
        _publish(
          'runA',
          afterSequence: 0,
          events: [
            for (var sequence = 1; sequence <= 256; sequence++)
              _event('runA', sequence),
          ],
        ),
      );
      await projection.publish(
        _publish(
          'runA',
          afterSequence: 256,
          events: [
            for (var sequence = 257; sequence <= 300; sequence++)
              _event('runA', sequence),
          ],
        ),
      );

      final replay = await projection.readEvents('runA', afterSequence: 0);

      expect(replay.events, isEmpty);
      expect(replay.boundary?.hasGap, isTrue);
      expect(replay.boundary?.earliestAvailableSequence, 45);
      expect(replay.boundary?.latestAvailableSequence, 300);
      await expectLater(
        projection.publish(
          _publish(
            'runB',
            afterSequence: 0,
            events: <CockpitRunEvent>[_event('runB', 1, id: 'event-runA-1')],
          ),
        ),
        throwsA(isA<FormatException>()),
      );

      final exactReplay = await projection.publish(
        _publish(
          'runA',
          afterSequence: 0,
          events: <CockpitRunEvent>[_event('runA', 1)],
        ),
      );
      expect(exactReplay.highestContiguousSequence, 300);
      await expectLater(
        projection.publish(
          _publish(
            'runA',
            afterSequence: 0,
            events: <CockpitRunEvent>[
              _event('runA', 1, id: 'changed-event-id'),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        projection.publish(
          _publish(
            'runA',
            afterSequence: 0,
            events: <CockpitRunEvent>[
              _event('runA', 1, timestamp: DateTime.utc(2026, 7, 23)),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('rebuild indexes owners for events outside the replay buffer', () async {
    final projection = _projection(
      stateRoot,
      maximumRetainedEventsPerRun: 256,
      maximumEventOwners: 300,
    );
    await projection.rebuildRunFromWorkerTruth(
      runId: 'runA',
      events: <CockpitRunEvent>[
        for (var sequence = 1; sequence <= 300; sequence++)
          _event('runA', sequence),
      ],
    );

    final replay = await projection.readEvents('runA', afterSequence: 44);
    expect(replay.boundary?.earliestAvailableSequence, 45);
    await expectLater(
      projection.publish(
        _publish(
          'runB',
          afterSequence: 0,
          events: [_event('runB', 1, id: 'event-runA-1')],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('keeps a failed release durable and rejects further writes', () async {
    final retention = _FailingReleaseRetentionIndex(failBeforeRelease: true);
    final projection = _projection(stateRoot, retentionIndex: retention);
    await projection.publish(
      _publish(
        'runA',
        afterSequence: 0,
        events: [_event('runA', 1, id: 'shared')],
      ),
    );

    await expectLater(
      projection.releaseRetainedRun('runA'),
      throwsA(isA<StateError>()),
    );
    expect(
      (await projection.readEvents('runA', afterSequence: 0)).events,
      hasLength(1),
    );
    await expectLater(
      projection.publish(
        _publish('runA', afterSequence: 1, events: [_event('runA', 2)]),
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      projection.rebuildRunFromWorkerTruth(
        runId: 'runA',
        events: [_event('runA', 1)],
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      projection.publish(
        _publish(
          'runB',
          afterSequence: 0,
          events: [_event('runB', 1, id: 'shared')],
        ),
      ),
      throwsA(isA<FormatException>()),
    );

    await projection.releaseRetainedRun('runA');
    expect(retention.releaseAttempts, 2);
    expect(
      (await projection.publish(
        _publish(
          'runB',
          afterSequence: 0,
          events: [_event('runB', 1, id: 'shared')],
        ),
      )).highestContiguousSequence,
      1,
    );
  });

  test('resumes an ambiguous retention release after restart', () async {
    final retention = _FailingReleaseRetentionIndex(failAfterRelease: true);
    final projection = _projection(stateRoot, retentionIndex: retention);
    await projection.publish(
      _publish(
        'runA',
        afterSequence: 0,
        events: [_event('runA', 1, id: 'shared')],
      ),
    );

    await expectLater(
      projection.releaseRetainedRun('runA'),
      throwsA(isA<StateError>()),
    );
    expect(retention.releaseAttempts, 1);
    expect(retention.externalReleases, 1);

    final restarted = _projection(stateRoot, retentionIndex: retention);
    await restarted.resumePendingRetentionReleases();

    expect(retention.releaseAttempts, 2);
    expect(retention.externalReleases, 1);
    expect(
      (await restarted.readEvents('runA', afterSequence: 0)).events,
      isEmpty,
    );
    expect(
      (await restarted.publish(
        _publish(
          'runB',
          afterSequence: 0,
          events: [_event('runB', 1, id: 'shared')],
        ),
      )).highestContiguousSequence,
      1,
    );
  });

  test('launcher resumes pending releases before spawning a worker', () async {
    final retention = _FailingReleaseRetentionIndex(failAfterRelease: true);
    final projection = _projection(stateRoot, retentionIndex: retention);
    await projection.publish(
      _publish('runA', afterSequence: 0, events: [_event('runA', 1)]),
    );
    await expectLater(
      projection.releaseRetainedRun('runA'),
      throwsA(isA<StateError>()),
    );
    final processes = _RejectingProcessManager();
    final launcher = CockpitLocalWorkerLauncher(
      dartExecutable: 'dart',
      workerEntrypoint: 'worker.dart',
      retentionIndex: retention,
      resourceAuthorityFactory: (_, _) => throw StateError('unreachable'),
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
      processManager: processes,
    );

    await expectLater(
      launcher.launch(
        CockpitWorkspaceWorkerSpec(
          key: CockpitWorkspaceWorkerKey(
            workspaceId: 'workspaceA',
            engineVersion: 'engineA',
          ),
          projectId: 'projectA',
          workspaceRoot: stateRoot,
          stateRoot: stateRoot,
          supportedFeatures: const <String>[],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(processes.startCalls, 1);
    final workerTemporaryPath = processes.startEnvironment!['TMPDIR']!;
    expect(processes.startEnvironment!['TMP'], workerTemporaryPath);
    expect(processes.startEnvironment!['TEMP'], workerTemporaryPath);
    if (!Platform.isWindows) {
      expect(p.dirname(workerTemporaryPath), '/tmp');
      expect(workerTemporaryPath.length, lessThan(64));
    }
    expect(await Directory(workerTemporaryPath).exists(), isFalse);
    expect(retention.releaseAttempts, 2);
    expect(
      (await _projection(
        stateRoot,
        retentionIndex: retention,
      ).readEvents('runA', afterSequence: 0)).events,
      isEmpty,
    );
  });

  test('retries a lost final response without releasing twice', () async {
    final retention = _FailingReleaseRetentionIndex();
    final projection = _projection(stateRoot, retentionIndex: retention);
    await projection.publish(
      _publish('runA', afterSequence: 0, events: [_event('runA', 1)]),
    );

    await projection.releaseRetainedRun('runA');
    await projection.releaseRetainedRun('runA');

    expect(retention.releaseAttempts, 1);
    expect(retention.externalReleases, 1);
  });

  test('validates durable event index ownership in both directions', () async {
    final projection = _projection(stateRoot);
    await projection.publish(
      _publish('runA', afterSequence: 0, events: [_event('runA', 1)]),
    );
    final file = File(
      p.join(stateRoot, 'supervisor_projection', 'projection.json'),
    );
    final original = jsonDecode(await file.readAsString());
    for (final mutate in <void Function(Map<String, Object?>)>[
      (value) {
        final owners = value['eventOwners']! as Map<String, Object?>;
        owners['event-runA-1'] = 'runA:2';
      },
      (value) {
        final runs = value['runs']! as Map<String, Object?>;
        final run = runs['runA']! as Map<String, Object?>;
        final index = run['eventIndex']! as Map<String, Object?>;
        final first = index['1']! as Map<String, Object?>;
        first['sha256'] = List<String>.filled(64, 'b').join();
      },
    ]) {
      final corrupted =
          jsonDecode(jsonEncode(original)) as Map<String, Object?>;
      mutate(corrupted);
      await file.writeAsString(jsonEncode(corrupted), flush: true);
      await expectLater(
        _projection(stateRoot).readEvents('runA', afterSequence: 0),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('rejects invalid event owner bounds at construction', () {
    expect(
      () => _projection(stateRoot, maximumEventOwners: 0),
      throwsArgumentError,
    );
    expect(
      () => _projection(stateRoot, maximumEventOwners: 1000001),
      throwsArgumentError,
    );
  });
}

CockpitSupervisorRunProjection _projection(
  String stateRoot, {
  int maximumRetainedEventsPerRun = 4096,
  int maximumEventOwners = 100000,
  CockpitSupervisorRunRetentionIndex retentionIndex = const _RetentionIndex(),
}) => CockpitSupervisorRunProjection(
  workspaceId: 'workspaceA',
  stateRoot: stateRoot,
  permissionHardener: const _NoopPermissionHardener(),
  directorySyncer: const _NoopDirectorySyncer(),
  retentionIndex: retentionIndex,
  maximumRetainedEventsPerRun: maximumRetainedEventsPerRun,
  maximumEventOwners: maximumEventOwners,
);

CockpitWorkerPublishEventBatchRequest _publish(
  String runId, {
  required int afterSequence,
  required List<CockpitRunEvent> events,
}) => CockpitWorkerPublishEventBatchRequest(
  protocolVersion: cockpitWorkerProtocolVersion,
  workspaceId: 'workspaceA',
  requestId: 'publish-$runId-$afterSequence',
  deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
  idempotencyKey: 'publish-$runId-$afterSequence',
  runId: runId,
  afterSequence: afterSequence,
  events: events,
);

CockpitRunEvent _event(
  String runId,
  int sequence, {
  String? id,
  DateTime? timestamp,
}) => CockpitRunEvent(
  eventId: id ?? 'event-$runId-$sequence',
  sequence: sequence,
  timestamp: timestamp ?? DateTime.utc(2026, 7, 22),
  kind: 'run.progress',
  entityKind: CockpitRunEventEntityKind.run,
  projectId: 'projectA',
  workspaceId: 'workspaceA',
  runId: runId,
  lifecycle: CockpitRunLifecycle.running,
);

final class _RetentionIndex implements CockpitSupervisorRunRetentionIndex {
  const _RetentionIndex();

  @override
  Future<void> releaseRun({
    required String workspaceId,
    required String runId,
  }) async {}

  @override
  Future<void> retainRun({
    required String workspaceId,
    required String runId,
    required bool active,
    required int artifactCount,
  }) async {}
}

final class _FailingReleaseRetentionIndex
    implements CockpitSupervisorRunRetentionIndex {
  _FailingReleaseRetentionIndex({
    this.failBeforeRelease = false,
    this.failAfterRelease = false,
  });

  final bool failBeforeRelease;
  final bool failAfterRelease;
  int releaseAttempts = 0;
  int externalReleases = 0;

  @override
  Future<void> releaseRun({
    required String workspaceId,
    required String runId,
  }) async {
    releaseAttempts += 1;
    if (releaseAttempts == 1 && failBeforeRelease) {
      throw StateError('release failed before external mutation');
    }
    if (externalReleases == 0) externalReleases += 1;
    if (releaseAttempts == 1 && failAfterRelease) {
      throw StateError('release response lost after external mutation');
    }
  }

  @override
  Future<void> retainRun({
    required String workspaceId,
    required String runId,
    required bool active,
    required int artifactCount,
  }) async {}
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

final class _RejectingProcessManager implements CockpitProcessManager {
  var startCalls = 0;
  Map<String, String>? startEnvironment;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) => throw StateError('process run is not expected');

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    startCalls += 1;
    startEnvironment = environment;
    throw StateError('process start sentinel');
  }
}
