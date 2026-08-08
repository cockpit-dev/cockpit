import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/artifacts/cockpit_test_attempt_bundle_writer.dart';
import 'package:cockpit/src/artifacts/cockpit_test_attempt_recorder.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_run_projection.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_worker_endpoint.dart';
import 'package:cockpit/src/supervisor/cockpit_worker_resource_authority.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_request.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_run_event_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_server.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String stateRoot;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-artifacts-');
    stateRoot = await temporary.resolveSymbolicLinks();
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'detects canonical artifact byte replacement after publication',
    () async {
      final fixture = await _bundle(stateRoot);
      final projection = _projection(stateRoot);
      await _projectRun(projection);
      await projection.publishArtifacts(_publication(fixture.resource));

      await File(fixture.filePath).writeAsBytes([9, 9, 9], flush: true);

      await expectLater(
        projection.requireArtifact('runA', fixture.resource.artifactId),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('rejects symlink replacement of a canonical artifact', () async {
    final fixture = await _bundle(stateRoot);
    final projection = _projection(stateRoot);
    await _projectRun(projection);
    await projection.publishArtifacts(_publication(fixture.resource));
    final outside = await File(
      p.join(stateRoot, 'outside.png'),
    ).writeAsBytes([1, 2, 3, 4]);
    await File(fixture.filePath).delete();
    await Link(fixture.filePath).create(outside.path);

    await expectLater(
      projection.requireArtifact('runA', fixture.resource.artifactId),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'rejects size, digest, and redaction failures without indexing',
    () async {
      final fixture = await _bundle(stateRoot);
      final projection = _projection(stateRoot);
      await _projectRun(projection);
      for (final invalid in <CockpitArtifactResource>[
        _resource(fixture, sizeBytes: fixture.resource.sizeBytes + 1),
        _resource(
          fixture,
          sha256:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
      ]) {
        await expectLater(
          projection.publishArtifacts(_publication(invalid)),
          throwsA(isA<FormatException>()),
        );
      }

      final rejecting = _projection(
        stateRoot,
        redactor: (value) {
          if (value is Map<Object?, Object?> && value['artifactId'] != null) {
            throw StateError('redaction failed');
          }
          return value;
        },
      );
      await expectLater(
        rejecting.publishArtifacts(_publication(fixture.resource)),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        projection.requireArtifact('runA', fixture.resource.artifactId),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'bootstraps a zero-event run from verified artifact ownership',
    () async {
      final fixture = await _bundle(stateRoot);
      final projection = _projection(stateRoot);

      await projection.publishArtifacts(_publication(fixture.resource));

      expect(
        (await projection.requireArtifact(
          'runA',
          fixture.resource.artifactId,
        )).toJson(),
        fixture.resource.toJson(),
      );
      expect(
        (await projection.readEvents('runA', afterSequence: 0)).events,
        isEmpty,
      );
    },
  );

  test('event-only rebuild preserves indexed artifacts', () async {
    final fixture = await _bundle(stateRoot);
    final projection = _projection(stateRoot);
    await projection.publishArtifacts(_publication(fixture.resource));

    await projection.rebuildRunFromWorkerTruth(
      runId: 'runA',
      events: <CockpitRunEvent>[
        CockpitRunEvent(
          eventId: 'eventRebuilt',
          sequence: 1,
          timestamp: DateTime.utc(2026, 7, 22),
          kind: 'run.progress',
          entityKind: CockpitRunEventEntityKind.run,
          projectId: 'projectA',
          workspaceId: 'workspaceA',
          runId: 'runA',
          lifecycle: CockpitRunLifecycle.running,
        ),
      ],
    );

    expect(
      (await projection.requireArtifact(
        'runA',
        fixture.resource.artifactId,
      )).toJson(),
      fixture.resource.toJson(),
    );
  });

  test(
    'failed nested replay preserves ack and initialization retry converges',
    () async {
      final artifact = await _bundle(stateRoot);
      final projection = _projection(stateRoot);
      await projection.publishArtifacts(_publication(artifact.resource));
      final publisher = _SwitchingEventPublisher(
        const _AcknowledgeEventPublisher(),
      );
      final eventStore = CockpitWorkerRunEventStore(
        projectId: 'projectA',
        workspaceId: 'workspaceA',
        stateRoot: stateRoot,
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
        redactor: (value) => value,
        publisher: publisher,
      );
      for (var sequence = 1; sequence <= 256; sequence += 1) {
        await eventStore.append(
          'runA',
          _eventDraft(sequence == 1 ? 'run.started' : 'run.progress'),
          publishImmediately: false,
        );
      }
      await eventStore.publishRun('runA');
      await eventStore.append(
        'runA',
        _eventDraft('run.progress'),
        publishImmediately: false,
      );

      late final CockpitWorkerServer workerServer;
      workerServer = CockpitWorkerServer(
        workspaceId: 'workspaceA',
        engineVersion: 'engineA',
        workspaceRoot: stateRoot,
        supportedFeatures: const <String>[],
        operations: const _NoopOperationDispatcher(),
        events: eventStore,
        onInitialized: eventStore.resume,
      );
      final endpoint = CockpitSupervisorWorkerEndpoint(
        workspaceId: 'workspaceA',
        events: projection,
        artifacts: projection,
        resourceAuthority: const _NoopResourceAuthority(),
      );
      var failReplay = true;
      final replayPages = <int>[];
      final peers = _BidirectionalPeerHarness(
        workerHandler: (request, cancellation) {
          if (request.method == 'replayEvents') {
            replayPages.add(request.params['afterSequence']! as int);
            if (failReplay) {
              throw StateError('simulated worker replay failure');
            }
          }
          return workerServer.handle(request, cancellation);
        },
        supervisorHandler: endpoint.handle,
      );
      workerServer.bindPeer(peers.worker);
      publisher.delegate = CockpitRpcWorkerEventPublisher(
        workspaceId: 'workspaceA',
        peer: peers.worker,
      );
      var replayCalls = 0;
      final connectionIdentity = Object();
      endpoint.bindReplayClient(
        connectionIdentity: connectionIdentity,
        replay: ({required runId, required afterSequence, required deadline}) {
          replayCalls += 1;
          return peers.supervisor
              .call(
                method: 'replayEvents',
                params: <String, Object?>{
                  'protocolVersion': cockpitWorkerProtocolVersion,
                  'workspaceId': 'workspaceA',
                  'idempotencyKey': 'nested-replay-$replayCalls',
                  'runId': runId,
                  'afterSequence': afterSequence,
                },
                deadline: deadline,
              )
              .then(CockpitWorkerReplayEventsResult.fromJson);
        },
      );
      peers.start();
      addTearDown(() async {
        endpoint.unbindReplayClient(connectionIdentity);
        await peers.close();
      });

      Future<Object?> initialize(String idempotencyKey) => peers.supervisor
          .call(
            method: 'initialize',
            params: <String, Object?>{
              'protocolVersion': cockpitWorkerProtocolVersion,
              'workspaceId': 'workspaceA',
              'idempotencyKey': idempotencyKey,
              'engineVersion': 'engineA',
              'workspaceRoot': stateRoot,
              'supportedFeatures': const <String>[],
            },
            deadline: DateTime.now().toUtc().add(const Duration(seconds: 5)),
          )
          .timeout(const Duration(seconds: 5));

      await expectLater(
        initialize('initialize-failed-replay'),
        throwsA(
          isA<CockpitJsonRpcRemoteException>().having(
            (error) => error.error.workerCode,
            'workerCode',
            'internalError',
          ),
        ),
      );
      expect(replayPages, <int>[0]);
      expect(publisher.requests.last.afterSequence, 256);
      expect(publisher.lastResult?.highestContiguousSequence, 256);
      expect(
        (await projection.readEvents('runA', afterSequence: 0)).events,
        isEmpty,
      );
      expect(
        (jsonDecode(
              await File(
                p.join(stateRoot, 'runs', 'runA', 'relay.json'),
              ).readAsString(),
            )
            as Map<String, Object?>)['sequence'],
        256,
      );

      failReplay = false;
      await initialize('initialize-retry-replay');

      expect(replayCalls, 3);
      expect(replayPages, <int>[0, 0, 256]);
      expect(publisher.requests.last.afterSequence, 256);
      expect(publisher.lastResult?.highestContiguousSequence, 257);
      expect(publisher.lastResult?.replayAfterSequence, isNull);
      expect(
        (await projection.readEvents('runA', afterSequence: 0)).events,
        hasLength(256),
      );
      expect(
        (await projection.readEvents('runA', afterSequence: 256)).events,
        hasLength(1),
      );
      expect(
        (await projection.requireArtifact(
          'runA',
          artifact.resource.artifactId,
        )).artifactId,
        artifact.resource.artifactId,
      );
      final relay =
          jsonDecode(
                await File(
                  p.join(stateRoot, 'runs', 'runA', 'relay.json'),
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(relay['sequence'], 257);
    },
  );

  test('existing run rejects request owner before inspecting files', () async {
    final fixture = await _bundle(stateRoot);
    final projection = _projection(stateRoot);
    await _projectRun(projection);
    await Directory(fixture.bundlePath).delete(recursive: true);

    await expectLater(
      projection.publishArtifacts(
        _publication(
          fixture.resource,
          projectId: 'projectOther',
          caseId: 'caseOther',
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('ownership'),
        ),
      ),
    );
  });

  test('rejects bundles outside the direct retained bundle layout', () async {
    final fixture = await _bundle(stateRoot);
    final legacyRoot = p.join(
      stateRoot,
      'runs',
      'runA',
      'artifacts',
      'legacy_bundle',
    );
    await Directory(fixture.bundlePath).rename(legacyRoot);
    final legacyFile = p.join(legacyRoot, 'screenshots', 'evidence.png');
    final legacyResource = _resource(
      fixture,
      relativePath: p
          .relative(legacyFile, from: p.join(stateRoot, 'runs', 'runA'))
          .replaceAll('\\', '/'),
    );
    final projection = _projection(stateRoot);
    await _projectRun(projection);

    await expectLater(
      projection.publishArtifacts(_publication(legacyResource)),
      throwsA(isA<FormatException>()),
    );
  });

  test('binds manifest project and case to the projected owner', () async {
    final fixture = await _bundle(
      stateRoot,
      projectId: 'projectOther',
      caseId: 'caseOther',
    );
    final projection = _projection(stateRoot);
    await _projectRun(projection);

    await expectLater(
      projection.publishArtifacts(_publication(fixture.resource)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rechecks the projected owner before indexing', () async {
    final fixture = await _bundle(stateRoot);
    final owner = _projection(stateRoot);
    await _projectRun(owner);
    var changed = false;
    final racing = _projection(
      stateRoot,
      redactor: (value) {
        if (!changed &&
            value is Map<Object?, Object?> &&
            value['artifactId'] != null) {
          changed = true;
          final file = File(
            p.join(stateRoot, 'supervisor_projection', 'projection.json'),
          );
          final projection =
              jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
          final runs = projection['runs']! as Map<String, Object?>;
          final run = runs['runA']! as Map<String, Object?>;
          run['projectId'] = 'projectOther';
          final events = run['events']! as List<Object?>;
          final event = events.single! as Map<String, Object?>;
          event['projectId'] = 'projectOther';
          final canonicalEvent = CockpitRunEvent.fromJson(event);
          final index = run['eventIndex']! as Map<String, Object?>;
          final indexed = index['1']! as Map<String, Object?>;
          indexed['sha256'] = sha256
              .convert(utf8.encode(jsonEncode(canonicalEvent.toJson())))
              .toString();
          file.writeAsStringSync('${jsonEncode(projection)}\n', flush: true);
        }
        return value;
      },
    );

    await expectLater(
      racing.publishArtifacts(_publication(fixture.resource)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('owner changed'),
        ),
      ),
    );
    expect(changed, isTrue);
  });

  test('release reclaims artifact ids for another run', () async {
    final first = await _bundle(
      stateRoot,
      runId: 'runA',
      attemptId: 'attemptA',
      artifactId: 'sharedArtifact',
    );
    final projection = _projection(stateRoot);
    await _projectRun(projection, runId: 'runA', eventId: 'eventA');
    await projection.publishArtifacts(_publication(first.resource));

    await projection.releaseRetainedRun('runA');

    final second = await _bundle(
      stateRoot,
      runId: 'runB',
      attemptId: 'attemptB',
      artifactId: 'sharedArtifact',
    );
    await _projectRun(projection, runId: 'runB', eventId: 'eventB');
    await projection.publishArtifacts(_publication(second.resource));

    expect(
      (await projection.requireArtifact('runB', 'sharedArtifact')).runId,
      'runB',
    );
  });

  test('rejects artifact writes while run retention is releasing', () async {
    final fixture = await _bundle(stateRoot);
    final projection = _projection(
      stateRoot,
      retentionIndex: const _RejectingRetentionIndex(),
    );
    await _projectRun(projection);
    await expectLater(
      projection.releaseRetainedRun('runA'),
      throwsA(isA<StateError>()),
    );

    await expectLater(
      projection.publishArtifacts(_publication(fixture.resource)),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<({String bundlePath, String filePath, CockpitArtifactResource resource})>
_bundle(
  String stateRoot, {
  String runId = 'runA',
  String projectId = 'projectA',
  String caseId = 'caseA',
  String attemptId = 'attemptA',
  String artifactId = 'artifactA',
}) async {
  final context = CockpitTestRunContext(
    projectId: projectId,
    workspaceId: 'workspaceA',
    runId: runId,
    caseId: caseId,
    attemptId: attemptId,
    engineVersion: 'engineA',
  );
  final result = CockpitTestAttemptResult(
    context: context,
    lifecycle: CockpitTestLifecycle.completed,
    outcome: CockpitTestOutcome.passed,
    stability: CockpitTestStability.stable,
    startedAt: DateTime.utc(2026, 7, 22),
    finishedAt: DateTime.utc(2026, 7, 22, 0, 0, 1),
    durationMs: 1000,
    targetId: 'targetA',
    platform: 'macos',
    requestedPlane: CockpitTestPlane.semantic,
    actualPlane: CockpitTestPlane.semantic,
    steps: <CockpitTestStepResult>[
      CockpitTestStepResult(
        stepId: 'capture',
        executionId: 'main/capture',
        section: 'main',
        status: CockpitTestStepStatus.passed,
        startedAt: DateTime.utc(2026, 7, 22),
        durationMs: 10,
        evidence: const <String>['recordedArtifact'],
      ),
    ],
  );
  final summary = await const CockpitTestAttemptBundleWriter().write(
    rootPath: p.join(stateRoot, 'artifact_sources', runId, attemptId),
    context: context,
    sourceSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    result: result,
    artifacts: <CockpitTestRecordedArtifact>[
      CockpitTestRecordedArtifact(
        artifactId: 'recordedArtifact',
        kind: 'screenshot',
        relativePath: 'screenshots/evidence.png',
        mediaType: 'image/png',
        stepExecutionId: 'main/capture',
        bytes: const <int>[1, 2, 3, 4],
      ),
    ],
    createdAt: DateTime.utc(2026, 7, 22),
  );
  final artifactRoot = await Directory(
    p.join(stateRoot, 'runs', runId, 'artifacts'),
  ).create(recursive: true);
  final bundlePath = p.join(
    artifactRoot.path,
    'bundle_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  await Directory(summary.path).rename(bundlePath);
  final manifest = await const CockpitTestAttemptBundleReader().readAndVerify(
    path: bundlePath,
  );
  final entry = manifest.artifacts.single;
  final filePath = p.join(bundlePath, entry.relativePath);
  return (
    bundlePath: bundlePath,
    filePath: filePath,
    resource: CockpitArtifactResource(
      artifactId: artifactId,
      workspaceId: 'workspaceA',
      runId: runId,
      attemptId: attemptId,
      stepExecutionId: entry.stepExecutionId,
      kind: 'attempt.screenshot',
      relativePath: p
          .relative(filePath, from: p.join(stateRoot, 'runs', runId))
          .replaceAll('\\', '/'),
      mediaType: entry.mediaType,
      sizeBytes: entry.sizeBytes,
      sha256: entry.sha256,
      createdAt: manifest.createdAt,
      downloadUrl: '/api/v2/runs/$runId/artifacts/$artifactId',
    ),
  );
}

CockpitArtifactResource _resource(
  ({String bundlePath, String filePath, CockpitArtifactResource resource})
  fixture, {
  int? sizeBytes,
  String? sha256,
  String? relativePath,
}) => CockpitArtifactResource(
  artifactId: fixture.resource.artifactId,
  workspaceId: fixture.resource.workspaceId,
  runId: fixture.resource.runId,
  attemptId: fixture.resource.attemptId,
  stepExecutionId: fixture.resource.stepExecutionId,
  kind: fixture.resource.kind,
  relativePath: relativePath ?? fixture.resource.relativePath,
  mediaType: fixture.resource.mediaType,
  sizeBytes: sizeBytes ?? fixture.resource.sizeBytes,
  sha256: sha256 ?? fixture.resource.sha256,
  createdAt: fixture.resource.createdAt,
  downloadUrl: fixture.resource.downloadUrl,
);

CockpitWorkerPublishArtifactBatchRequest _publication(
  CockpitArtifactResource resource, {
  String projectId = 'projectA',
  String caseId = 'caseA',
}) => CockpitWorkerPublishArtifactBatchRequest(
  protocolVersion: cockpitWorkerProtocolVersion,
  workspaceId: 'workspaceA',
  requestId: 'publish-${resource.sha256.substring(0, 8)}',
  deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
  idempotencyKey: 'publish-${resource.sha256.substring(0, 8)}',
  projectId: projectId,
  runId: resource.runId,
  caseId: caseId,
  artifacts: <CockpitArtifactResource>[resource],
);

Future<void> _projectRun(
  CockpitSupervisorRunProjection projection, {
  String runId = 'runA',
  String eventId = 'eventA',
}) => projection
    .publish(
      CockpitWorkerPublishEventBatchRequest(
        protocolVersion: cockpitWorkerProtocolVersion,
        workspaceId: 'workspaceA',
        requestId: 'publish-run',
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        idempotencyKey: 'publish-run',
        runId: runId,
        afterSequence: 0,
        events: <CockpitRunEvent>[
          CockpitRunEvent(
            eventId: eventId,
            sequence: 1,
            timestamp: DateTime.utc(2026, 7, 22),
            kind: 'run.progress',
            entityKind: CockpitRunEventEntityKind.run,
            projectId: 'projectA',
            workspaceId: 'workspaceA',
            runId: runId,
            lifecycle: CockpitRunLifecycle.running,
          ),
        ],
      ),
    )
    .then((_) {});

CockpitSupervisorRunProjection _projection(
  String stateRoot, {
  CockpitSupervisorMetadataRedactor? redactor,
  CockpitSupervisorRunRetentionIndex retentionIndex = const _RetentionIndex(),
}) => CockpitSupervisorRunProjection(
  workspaceId: 'workspaceA',
  stateRoot: stateRoot,
  permissionHardener: const _NoopPermissionHardener(),
  directorySyncer: const _NoopDirectorySyncer(),
  retentionIndex: retentionIndex,
  redactor: redactor,
);

CockpitWorkerEventDraft _eventDraft(String kind) => CockpitWorkerEventDraft(
  kind: kind,
  entityKind: CockpitRunEventEntityKind.run,
  lifecycle: CockpitRunLifecycle.running,
);

final class _SwitchingEventPublisher implements CockpitWorkerEventPublisher {
  _SwitchingEventPublisher(this.delegate);

  CockpitWorkerEventPublisher delegate;
  final List<CockpitWorkerPublishEventBatchRequest> requests =
      <CockpitWorkerPublishEventBatchRequest>[];
  CockpitWorkerPublishEventBatchResult? lastResult;

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    requests.add(request);
    final result = await delegate.publish(request);
    lastResult = result;
    return result;
  }
}

final class _AcknowledgeEventPublisher implements CockpitWorkerEventPublisher {
  const _AcknowledgeEventPublisher();

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async => CockpitWorkerPublishEventBatchResult(
    runId: request.runId,
    highestContiguousSequence: request.events.last.sequence,
    terminal: false,
  );
}

final class _BidirectionalPeerHarness {
  factory _BidirectionalPeerHarness({
    required CockpitJsonRpcRequestHandler workerHandler,
    required CockpitJsonRpcRequestHandler supervisorHandler,
  }) {
    final workerInput = StreamController<List<int>>();
    final supervisorInput = StreamController<List<int>>();
    return _BidirectionalPeerHarness._(
      worker: CockpitJsonRpcPeer(
        input: workerInput.stream,
        output: supervisorInput.sink,
        requestHandler: workerHandler,
      ),
      supervisor: CockpitJsonRpcPeer(
        input: supervisorInput.stream,
        output: workerInput.sink,
        requestHandler: supervisorHandler,
      ),
    );
  }

  const _BidirectionalPeerHarness._({
    required this.worker,
    required this.supervisor,
  });

  final CockpitJsonRpcPeer worker;
  final CockpitJsonRpcPeer supervisor;

  void start() {
    worker.start();
    supervisor.start();
  }

  Future<void> close() async {
    await worker.close();
    await supervisor.close(closeOutput: false);
  }
}

final class _NoopOperationDispatcher
    implements CockpitWorkerOperationDispatcher {
  const _NoopOperationDispatcher();

  @override
  List<String> get operationKinds => const <String>[];

  @override
  List<String> get resourceKinds => const <String>[];

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation, {
    required String requestId,
    required CockpitRpcCancellation cancellation,
  }) => throw UnimplementedError();
}

final class _NoopResourceAuthority
    implements CockpitSupervisorWorkerResourceAuthority {
  const _NoopResourceAuthority();

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation,
  ) => throw UnimplementedError();
}

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

final class _RejectingRetentionIndex
    implements CockpitSupervisorRunRetentionIndex {
  const _RejectingRetentionIndex();

  @override
  Future<void> releaseRun({
    required String workspaceId,
    required String runId,
  }) => throw StateError('retention release unavailable');

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
