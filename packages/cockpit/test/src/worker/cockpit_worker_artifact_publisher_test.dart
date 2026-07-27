import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/artifacts/cockpit_test_attempt_bundle_writer.dart';
import 'package:cockpit/src/artifacts/cockpit_test_attempt_recorder.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_message.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_artifact_publisher.dart';
import 'package:cockpit/src/worker/cockpit_worker_artifact_retainer.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_request.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_run_event_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'preflights unique catalog capacity and retries without side effects',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final artifacts = _ArtifactPeer();
      addTearDown(artifacts.close);
      final publisher = fixture.publisher(artifacts.peer);
      final operations = _PublisherPeer(publisher);
      addTearDown(operations.close);
      final first = await fixture.bundle('attemptA');

      await operations.publish(first);
      await operations.publish(first);

      expect(await fixture.catalogLength(), 2);
      expect(await fixture.retainedBundles(), hasLength(1));
      expect(await fixture.eventCount(), 2);
      expect(artifacts.calls, 2);
      expect(
        artifacts.requests,
        everyElement(
          isA<CockpitWorkerPublishArtifactBatchRequest>()
              .having((request) => request.projectId, 'projectId', 'projectA')
              .having((request) => request.caseId, 'caseId', 'caseA'),
        ),
      );

      final overflow = await fixture.bundle('attemptB');
      final retainedBeforeOverflow = await fixture.retainedSnapshot();
      final mutationsBeforeOverflow = fixture.retainedMutationCount;
      await expectLater(operations.publish(overflow), throwsA(anything));

      expect(await fixture.catalogLength(), 2);
      expect(await fixture.retainedBundles(), hasLength(1));
      expect(await fixture.retainedSnapshot(), retainedBeforeOverflow);
      expect(fixture.retainedMutationCount, mutationsBeforeOverflow);
      expect(await fixture.eventCount(), 2);
      expect(artifacts.calls, 2);

      final reopened = _PublisherPeer(fixture.publisher(artifacts.peer));
      addTearDown(reopened.close);
      final mutationsBeforeReopen = fixture.retainedMutationCount;
      await expectLater(reopened.publish(overflow), throwsA(anything));

      expect(await fixture.catalogLength(), 2);
      expect(await fixture.retainedBundles(), hasLength(1));
      expect(await fixture.retainedSnapshot(), retainedBeforeOverflow);
      expect(fixture.retainedMutationCount, mutationsBeforeReopen);
      expect(await fixture.eventCount(), 2);
      expect(artifacts.calls, 2);
    },
  );

  test(
    'rejects invalid ownership and digest before retained mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final artifacts = _ArtifactPeer();
      addTearDown(artifacts.close);
      final operations = _PublisherPeer(fixture.publisher(artifacts.peer));
      addTearDown(operations.close);

      final invalidDigest = await fixture.bundle('attemptDigest');
      await File(
        p.join(invalidDigest.path, 'screenshots', 'evidence.png'),
      ).writeAsBytes(const <int>[9, 9, 9]);
      final beforeDigest = await fixture.retainedSnapshot();
      final mutationsBeforeDigest = fixture.retainedMutationCount;

      await expectLater(operations.publish(invalidDigest), throwsA(anything));

      expect(await fixture.retainedSnapshot(), beforeDigest);
      expect(fixture.retainedMutationCount, mutationsBeforeDigest);
      expect(await fixture.catalogExists(), isFalse);

      final invalidOwner = await fixture.bundle('attemptOwner');
      final beforeOwner = await fixture.retainedSnapshot();
      final mutationsBeforeOwner = fixture.retainedMutationCount;

      await expectLater(
        operations.publish(invalidOwner, caseId: 'caseOther'),
        throwsA(anything),
      );

      expect(await fixture.retainedSnapshot(), beforeOwner);
      expect(fixture.retainedMutationCount, mutationsBeforeOwner);
      expect(await fixture.catalogExists(), isFalse);
      expect(artifacts.calls, 0);
    },
  );

  test('rejects a corrupt catalog before retained mutation', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final artifacts = _ArtifactPeer();
    addTearDown(artifacts.close);
    final operations = _PublisherPeer(fixture.publisher(artifacts.peer));
    addTearDown(operations.close);
    await operations.publish(await fixture.bundle('attemptA'));
    await fixture.corruptCatalogIdentity();
    final retainedBefore = await fixture.retainedSnapshot();
    final mutationsBefore = fixture.retainedMutationCount;

    await expectLater(
      operations.publish(await fixture.bundle('attemptB')),
      throwsA(anything),
    );

    expect(await fixture.retainedSnapshot(), retainedBefore);
    expect(fixture.retainedMutationCount, mutationsBefore);
    expect(artifacts.calls, 1);
  });

  test(
    'recovers only unindexed bundles and retains cataloged ack failures',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final artifacts = _ArtifactPeer();
      var artifactsClosed = false;
      addTearDown(() async {
        if (!artifactsClosed) await artifacts.close();
      });
      final failingHardener = _CatalogFailingPermissionHardener();
      final failingPublisher = fixture.publisher(
        artifacts.peer,
        permissionHardener: failingHardener,
      );
      final failingOperations = _PublisherPeer(failingPublisher);
      addTearDown(failingOperations.close);
      final orphaned = await fixture.bundle('attemptA');

      await expectLater(failingOperations.publish(orphaned), throwsA(anything));

      expect(await fixture.catalogExists(), isFalse);
      expect(await fixture.retainedBundles(), hasLength(1));
      expect(await fixture.eventCount(), 0);
      expect(artifacts.calls, 0);

      await fixture.publisher(artifacts.peer).resume();

      expect(await fixture.retainedBundles(), isEmpty);
      expect(artifacts.calls, 0);

      final cataloged = await fixture.bundle('attemptB');
      artifacts.reject = true;
      final catalogingOperations = _PublisherPeer(
        fixture.publisher(artifacts.peer),
      );
      addTearDown(catalogingOperations.close);
      await expectLater(
        catalogingOperations.publish(cataloged),
        throwsA(anything),
      );
      final live = (await fixture.retainedBundles()).single;
      expect(await fixture.catalogLength(), 2);
      expect(await fixture.eventCount(), 2);
      expect(artifacts.calls, 1);

      await artifacts.close();
      artifactsClosed = true;
      final recoveredArtifacts = _ArtifactPeer();
      addTearDown(recoveredArtifacts.close);
      await fixture.publisher(recoveredArtifacts.peer).resume();

      expect(await Directory(live).exists(), isTrue);
      expect(await fixture.catalogLength(), 2);
      expect(artifacts.calls, 1);
      expect(recoveredArtifacts.calls, 1);
      expect(recoveredArtifacts.requests.single.projectId, 'projectA');
      expect(recoveredArtifacts.requests.single.caseId, 'caseA');
    },
  );

  test(
    'resume skips artifacts already acknowledged by the Supervisor',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final artifacts = _ArtifactPeer();
      addTearDown(artifacts.close);
      final publisher = fixture.publisher(artifacts.peer);
      final operations = _PublisherPeer(publisher);
      addTearDown(operations.close);

      await operations.publish(await fixture.bundle('attemptA'));
      await fixture.publisher(artifacts.peer).resume();

      expect(await fixture.catalogLength(), 2);
      expect(artifacts.calls, 1);
    },
  );
}

typedef _Bundle = ({
  String runId,
  String caseId,
  String attemptId,
  String path,
});

final class _Fixture {
  const _Fixture._(
    this.temporary,
    this.stateRoot,
    this.producerRoot,
    this.hardener,
    this.syncer,
  );

  final Directory temporary;
  final String stateRoot;
  final String producerRoot;
  final _RecordingPermissionHardener hardener;
  final _RecordingDirectorySyncer syncer;

  static Future<_Fixture> create() async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-artifact-publisher-',
    );
    final stateRoot = await temporary.resolveSymbolicLinks();
    final producerRoot = (await Directory(
      p.join(stateRoot, 'producer_artifacts'),
    ).create()).path;
    return _Fixture._(
      temporary,
      stateRoot,
      producerRoot,
      _RecordingPermissionHardener(),
      _RecordingDirectorySyncer(),
    );
  }

  CockpitDurableWorkerArtifactPublisher publisher(
    CockpitJsonRpcPeer peer, {
    CockpitPermissionHardener? permissionHardener,
  }) {
    final effectiveHardener = permissionHardener ?? hardener;
    final events = CockpitWorkerRunEventStore(
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      stateRoot: stateRoot,
      permissionHardener: effectiveHardener,
      directorySyncer: syncer,
      redactor: (value) => value,
    );
    return CockpitDurableWorkerArtifactPublisher(
      workspaceId: 'workspaceA',
      stateRoot: stateRoot,
      peer: peer,
      events: events,
      artifactRetainer: CockpitWorkerArtifactRetainer(
        stateRoot: stateRoot,
        producerRoot: producerRoot,
        permissionHardener: effectiveHardener,
        directorySyncer: syncer,
      ),
      permissionHardener: effectiveHardener,
      directorySyncer: syncer,
      redactor: (value) => value,
      maximumArtifactsPerAttempt: 2,
      maximumArtifactsPerRun: 2,
    );
  }

  Future<_Bundle> bundle(String attemptId) async {
    const runId = 'runA';
    const caseId = 'caseA';
    final context = CockpitTestRunContext(
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      runId: runId,
      caseId: caseId,
      attemptId: attemptId,
      engineVersion: 'engineA',
    );
    final startedAt = DateTime.utc(2026, 7, 22);
    final result = CockpitTestAttemptResult(
      context: context,
      lifecycle: CockpitTestLifecycle.completed,
      outcome: CockpitTestOutcome.passed,
      stability: CockpitTestStability.stable,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(seconds: 1)),
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
          startedAt: startedAt,
          durationMs: 10,
          evidence: const <String>['recordedArtifact'],
        ),
      ],
    );
    final summary = await const CockpitTestAttemptBundleWriter().write(
      rootPath: p.join(stateRoot, 'runs', runId, 'cases', 'source_$attemptId'),
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
      createdAt: startedAt,
    );
    return (
      runId: runId,
      caseId: caseId,
      attemptId: attemptId,
      path: summary.path,
    );
  }

  Future<bool> catalogExists() =>
      File(p.join(stateRoot, 'runs', 'runA', 'artifacts.json')).exists();

  Future<int> catalogLength() async {
    final json =
        jsonDecode(
              await File(
                p.join(stateRoot, 'runs', 'runA', 'artifacts.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    return (json['artifacts']! as List<Object?>).length;
  }

  Future<List<String>> retainedBundles() async {
    final root = Directory(p.join(stateRoot, 'runs', 'runA', 'artifacts'));
    if (!await root.exists()) return const <String>[];
    return root
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .map((entity) => entity.path)
        .toList();
  }

  int get retainedMutationCount {
    final root = p.join(stateRoot, 'runs', 'runA', 'artifacts');
    bool retained(String path) =>
        p.equals(path, root) || p.isWithin(root, path);
    return hardener.paths.where(retained).length +
        syncer.paths.where(retained).length;
  }

  Future<Map<String, Object?>> retainedSnapshot() async {
    final root = Directory(p.join(stateRoot, 'runs', 'runA', 'artifacts'));
    if (!await root.exists()) return const <String, Object?>{'exists': false};
    final entities =
        await root.list(recursive: true, followLinks: false).toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final rootStat = await root.stat();
    return <String, Object?>{
      'exists': true,
      'modified': rootStat.modified.toUtc().toIso8601String(),
      'changed': rootStat.changed.toUtc().toIso8601String(),
      'entries': <Object?>[
        for (final entity in entities)
          () {
            final stat = FileStat.statSync(entity.path);
            return <String, Object?>{
              'path': p.relative(entity.path, from: root.path),
              'type': stat.type.toString(),
              'size': stat.size,
              'modified': stat.modified.toUtc().toIso8601String(),
              'changed': stat.changed.toUtc().toIso8601String(),
            };
          }(),
      ],
    };
  }

  Future<void> corruptCatalogIdentity() async {
    final file = File(p.join(stateRoot, 'runs', 'runA', 'artifacts.json'));
    final value = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    value['schemaVersion'] = 'cockpit.worker.artifacts/corrupt';
    await file.writeAsString(jsonEncode(value), flush: true);
  }

  Future<int> eventCount() async {
    final file = File(p.join(stateRoot, 'runs', 'runA', 'events.ndjson'));
    if (!await file.exists()) return 0;
    return const LineSplitter().convert(await file.readAsString()).length;
  }

  Future<void> dispose() => temporary.delete(recursive: true);
}

final class _PublisherPeer {
  _PublisherPeer(CockpitDurableWorkerArtifactPublisher publisher)
    : _harness = _PeerHarness((request, cancellation) async {
        try {
          final resources = await publisher.publishAttemptBundle(
            runId: request.params['runId']! as String,
            caseId: request.params['caseId']! as String,
            attemptId: request.params['attemptId']! as String,
            bundleRoot: request.params['bundleRoot']! as String,
            deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
            cancellation: cancellation,
          );
          return resources.map((resource) => resource.toJson()).toList();
        } on Object catch (error) {
          throw CockpitJsonRpcRemoteException(
            CockpitJsonRpcError(
              code: -32000,
              message: '$error',
              workerCode: 'testFailure',
            ),
          );
        }
      }) {
    _harness.start();
  }

  final _PeerHarness _harness;
  var _sequence = 0;

  Future<Object?> publish(_Bundle bundle, {String? caseId}) =>
      _harness.client.call(
        method: 'operation',
        params: <String, Object?>{
          'protocolVersion': cockpitWorkerProtocolVersion,
          'workspaceId': 'workspaceA',
          'idempotencyKey': 'test-publish-${++_sequence}',
          'runId': bundle.runId,
          'caseId': caseId ?? bundle.caseId,
          'attemptId': bundle.attemptId,
          'bundleRoot': bundle.path,
        },
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );

  Future<void> close() => _harness.close();
}

final class _ArtifactPeer {
  factory _ArtifactPeer() {
    late final _ArtifactPeer result;
    final harness = _PeerHarness((request, _) {
      final decoded = CockpitWorkerPublishArtifactBatchRequest.fromJson(
        request.params,
      );
      result.requests.add(decoded);
      result.calls += 1;
      if (result.reject) throw StateError('artifact ack unavailable');
      return Future<Object?>.value(
        CockpitWorkerPublishArtifactBatchResult(
          runId: decoded.runId,
          artifactIds: decoded.artifacts.map((artifact) => artifact.artifactId),
        ).toJson(),
      );
    });
    result = _ArtifactPeer._(harness);
    harness.start();
    return result;
  }

  _ArtifactPeer._(this._harness);

  final _PeerHarness _harness;
  final List<CockpitWorkerPublishArtifactBatchRequest> requests =
      <CockpitWorkerPublishArtifactBatchRequest>[];
  var calls = 0;
  var reject = false;

  CockpitJsonRpcPeer get peer => _harness.client;

  Future<void> close() => _harness.close();
}

final class _PeerHarness {
  factory _PeerHarness(CockpitJsonRpcRequestHandler serverHandler) {
    final clientInput = StreamController<List<int>>();
    final serverInput = StreamController<List<int>>();
    return _PeerHarness._(
      client: CockpitJsonRpcPeer(
        input: clientInput.stream,
        output: serverInput.sink,
        requestHandler: _unexpectedRequest,
      ),
      server: CockpitJsonRpcPeer(
        input: serverInput.stream,
        output: clientInput.sink,
        requestHandler: serverHandler,
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

final class _CatalogFailingPermissionHardener
    implements CockpitPermissionHardener {
  var _failed = false;

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {
    if (!_failed &&
        cockpitAtomicJsonTemporaryTargetName(p.basename(file.path)) ==
            'artifacts.json') {
      _failed = true;
      throw FileSystemException('simulated catalog write failure', file.path);
    }
  }
}

final class _RecordingPermissionHardener implements CockpitPermissionHardener {
  final List<String> paths = <String>[];

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {
    paths.add(p.normalize(directory.path));
  }

  @override
  Future<void> hardenFile(File file) async {
    paths.add(p.normalize(file.path));
  }
}

final class _RecordingDirectorySyncer implements CockpitDirectorySyncer {
  final List<String> paths = <String>[];

  @override
  Future<void> sync(String directoryPath) async {
    paths.add(p.normalize(directoryPath));
  }
}
