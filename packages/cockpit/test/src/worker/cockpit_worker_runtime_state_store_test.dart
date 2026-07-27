import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/development/cockpit_development_probe.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/foundation/cockpit_ids.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/targets/cockpit_target_handle.dart';
import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_worker_run_ownership_authority.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('replaces the stale session when the same app is relaunched', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-app-relaunch-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    final stateRoot = await Directory(p.join(workspaceRoot, 'state')).create();
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot.path,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    final targetId = await registry.registerTarget(
      const CockpitWorkerTargetRegistration(
        workspaceId: 'workspaceA',
        platform: 'android',
        deviceId: 'emulator-5554',
      ),
    );
    final first = await registry.recordApp(
      targetId: targetId,
      handle: CockpitAppHandle.fromRemoteSession(_remoteSession(workspaceRoot)),
    );
    final firstSessionId = await registry.sessionIdForApp(first.appId);
    final relaunchedRemote = CockpitRemoteSessionHandle(
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: workspaceRoot,
      target: 'android',
      appId: 'internal-app-A',
      platformAppIdKnown: false,
      host: '127.0.0.1',
      hostPort: 9102,
      devicePort: 8102,
      baseUrl: 'http://127.0.0.1:9102',
      launchedAt: DateTime.utc(2026, 7, 23),
    );

    final relaunched = await registry.recordApp(
      targetId: targetId,
      handle: CockpitAppHandle.fromRemoteSession(relaunchedRemote),
    );
    final relaunchedSessionId = await registry.sessionIdForApp(
      relaunched.appId,
    );

    expect(relaunched.appId, first.appId);
    expect(relaunchedSessionId, isNot(firstSessionId));
    await expectLater(
      registry.requireSession(firstSessionId),
      throwsA(isA<CockpitApplicationServiceException>()),
    );
  });

  test(
    'records an installed Flutter target as a system-owned app session',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-system-target-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final canonicalRoot = await temporary.resolveSymbolicLinks();
      final stateRoot = await Directory(
        p.join(canonicalRoot, 'state'),
      ).create();
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: canonicalRoot,
        stateRoot: stateRoot.path,
        stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
      );
      final targetId = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          targetKind: CockpitTargetKind.flutterApp,
          mode: CockpitAppMode.automation,
          environment: CockpitTestTargetEnvironment.test,
        ),
      );

      final app = await registry.recordSystemTargetLaunch(
        targetId: targetId,
        launchedAt: DateTime.utc(2026, 7, 24),
      );

      expect(app.handle.platformAppId, 'dev.cockpit.example');
      expect(app.handle.remoteSession?.baseUri.scheme, 'cockpit-system');
      final sessionId = await registry.sessionIdForApp(app.appId);
      final session = await registry.requireSession(sessionId);
      expect(session.targetId, targetId);
      final target = await registry.requireTarget(
        workspaceId: 'workspaceA',
        targetId: targetId,
      );
      expect(target.handle?.targetKind.name, 'flutterApp');
    },
  );

  test(
    'round trips registry state larger than the legacy 8 MiB limit',
    () async {
      final fixture = await _RuntimeStoreFixture.create();
      addTearDown(fixture.dispose);
      final suffix = List<String>.filled(420, 'x').join();
      final artifacts = <Object?>[
        for (var index = 0; index < 18000; index += 1)
          <String, Object?>{
            'artifactId': 'artifact_$index',
            'ownerKind': 'run',
            'ownerId': 'run_A',
            'kind': 'screenshot',
            'name': 'capture_${index}_$suffix.png',
            'mediaType': 'image/png',
            'retainedPath': p.join(
              fixture.stateRoot,
              'runs',
              'run_A',
              'artifacts',
              'capture_$index.png',
            ),
            'createdAt': DateTime.utc(2026, 7, 22).toIso8601String(),
          },
      ];
      final state = _runtimeState(artifacts: artifacts);
      expect(
        utf8.encode(jsonEncode(state)).length,
        greaterThan(8 * 1024 * 1024),
      );

      await fixture.store.write(state);
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: fixture.workspaceRoot,
        stateRoot: fixture.stateRoot,
        stateStore: fixture.store,
        runOwnershipAuthority: const _FixedRunOwnershipAuthority(<String>{
          'run_A',
        }),
      );
      await registry.flush();
      final reopened = await fixture.store.read();

      expect(reopened['artifacts'], hasLength(18000));
      expect((reopened['artifacts']! as List<Object?>).last, artifacts.last);
      expect(
        await Directory(
          p.join(fixture.runtimeRoot, 'generations'),
        ).list(followLinks: false).length,
        2,
      );
    },
  );

  test('allows one near-2 MiB record while enforcing its hard bound', () async {
    final fixture = await _RuntimeStoreFixture.create();
    addTearDown(fixture.dispose);
    final payload = List<String>.filled(
      CockpitFileWorkerRuntimeStateStore.maximumRecordBytes - 128,
      'x',
    ).join();
    final state = _runtimeState(
      probes: <Object?>[
        <String, Object?>{'payload': payload},
      ],
    );

    await fixture.store.write(state);
    final reopened = await fixture.store.read();
    final manifest =
        jsonDecode(
              await File(
                p.join(fixture.runtimeRoot, 'manifest.json'),
              ).readAsString(),
            )!
            as Map<String, Object?>;
    final generation = manifest['generation']! as String;
    final probeShard =
        await Directory(
          p.join(fixture.runtimeRoot, 'generations', generation),
        ).list().firstWhere(
          (entity) => p.basename(entity.path).startsWith('probes-'),
        );

    expect(reopened, state);
    expect(
      await File(probeShard.path).length(),
      greaterThan(CockpitFileWorkerRuntimeStateStore.targetShardBytes),
    );
    expect(
      await File(probeShard.path).length(),
      lessThan(CockpitFileWorkerRuntimeStateStore.maximumShardBytes),
    );
    final oversized = List<String>.filled(
      CockpitFileWorkerRuntimeStateStore.maximumRecordBytes,
      'y',
    ).join();
    await expectLater(
      fixture.store.write(
        _runtimeState(
          probes: <Object?>[
            <String, Object?>{'payload': oversized},
          ],
        ),
      ),
      throwsA(isA<CockpitStorageException>()),
    );
    expect(await fixture.store.read(), state);
  });

  test(
    'cleans exact manifest temporaries and rejects malformed ones',
    () async {
      final fixture = await _RuntimeStoreFixture.create();
      addTearDown(fixture.dispose);
      await fixture.store.write(_runtimeState());
      final exact = await File(
        p.join(
          fixture.runtimeRoot,
          '.manifest.json.$pid.${List<String>.filled(24, 'a').join()}.tmp',
        ),
      ).writeAsString('{}');

      await fixture.store.read();
      expect(await exact.exists(), isFalse);

      await File(
        p.join(fixture.runtimeRoot, '.manifest.json.invalid.tmp'),
      ).writeAsString('{}');
      await expectLater(
        fixture.store.read(),
        throwsA(isA<FileSystemException>()),
      );
      await File(
        p.join(fixture.runtimeRoot, '.manifest.json.invalid.tmp'),
      ).delete();
      final wrongTarget = await File(
        p.join(
          fixture.runtimeRoot,
          '.other.json.$pid.${List<String>.filled(24, 'b').join()}.tmp',
        ),
      ).writeAsString('{}');
      await expectLater(
        fixture.store.read(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await wrongTarget.exists(), isTrue);
    },
  );

  test('rejects extra generation entries and symlink substitutions', () async {
    final fixture = await _RuntimeStoreFixture.create();
    addTearDown(fixture.dispose);
    await fixture.store.write(_runtimeState());
    final generation = await _currentGenerationDirectory(fixture.runtimeRoot);
    final unexpected = await File(
      p.join(generation.path, 'unexpected.json'),
    ).writeAsString('{}');

    await expectLater(
      fixture.store.read(),
      throwsA(isA<FileSystemException>()),
    );
    await unexpected.delete();

    if (!Platform.isWindows) {
      final metadata = File(p.join(generation.path, 'metadata.json'));
      final replacement = await File(
        p.join(fixture.temporary.path, 'metadata-copy.json'),
      ).writeAsBytes(await metadata.readAsBytes());
      await metadata.delete();
      await Link(metadata.path).create(replacement.path);
      await expectLater(
        fixture.store.read(),
        throwsA(isA<FileSystemException>()),
      );
    }
  });

  test(
    'rejects unknown generation entries and missing manifest evidence',
    () async {
      final fixture = await _RuntimeStoreFixture.create();
      addTearDown(fixture.dispose);
      await fixture.store.write(_runtimeState());
      final unknown = await File(
        p.join(fixture.runtimeRoot, 'generations', 'unknown-entry'),
      ).writeAsString('invalid');

      await expectLater(
        fixture.store.read(),
        throwsA(isA<FileSystemException>()),
      );
      await unknown.delete();
      await File(p.join(fixture.runtimeRoot, 'manifest.json')).delete();
      await expectLater(
        fixture.store.read(),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('does not fall back when the published generation is corrupt', () async {
    final fixture = await _RuntimeStoreFixture.create();
    addTearDown(fixture.dispose);
    await fixture.store.write(_runtimeState());
    await fixture.store.write(
      _runtimeState(
        artifacts: <Object?>[
          <String, Object?>{'published': true},
        ],
      ),
    );
    final generation = await _currentGenerationDirectory(fixture.runtimeRoot);
    final shard = await generation
        .list()
        .where((entity) => p.basename(entity.path).startsWith('artifacts-'))
        .cast<File>()
        .single;
    await shard.writeAsString('corrupt', mode: FileMode.append);

    await expectLater(fixture.store.read(), throwsA(isA<FormatException>()));
  });

  test(
    'persists typed handle identities and rebuilds workspace-owned paths',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-handle-codec-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final workspaceRoot = await temporary.resolveSymbolicLinks();
      final projectDir = await Directory(
        p.join(workspaceRoot, 'packages', 'demo'),
      ).create(recursive: true);
      final stateRoot = await Directory(
        p.join(workspaceRoot, 'state'),
      ).create();
      final supervisorLog = await File(
        p.join(stateRoot.path, 'logs', 'supervisor.log'),
      ).create(recursive: true);
      final store = CockpitInMemoryWorkerRuntimeStateStore();
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      final targetId = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
          environment: CockpitTestTargetEnvironment.development,
        ),
      );
      final remote = _remoteSession(projectDir.path);
      final development = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'development-session-A',
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: projectDir.path,
        target: 'android',
        appId: remote.appId,
        appBaseUrl: remote.baseUrl,
        supervisorBaseUrl: 'http://127.0.0.1:9201',
        launchedAt: DateTime.utc(2026, 7, 22),
        reloadGeneration: 1,
        remoteSessionHandle: remote,
      );
      final appHandle = CockpitAppHandle.fromDevelopmentSession(
        development,
        supervisorLogPath: supervisorLog.path,
      );
      await registry.recordTargetHandle(
        targetId: targetId,
        handle: CockpitTargetHandle.fromAppHandle(appHandle),
      );
      final app = await registry.recordApp(
        targetId: targetId,
        handle: appHandle,
      );
      final sessionId = await registry.sessionIdForApp(app.appId);

      final persisted = await store.read();
      final persistedJson = jsonEncode(persisted);
      expect(persistedJson, isNot(contains(workspaceRoot)));
      expect(persistedJson, isNot(contains(stateRoot.path)));
      expect(persistedJson, contains('projectIdentity'));
      expect(persistedJson, contains('supervisorLogIdentity'));

      final reopened = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      final reopenedTarget = await reopened.requireTarget(
        workspaceId: 'workspaceA',
        targetId: targetId,
      );
      final reopenedApp = await reopened.requireApp(app.appId);
      final reopenedSession = await reopened.requireSession(sessionId);

      expect(reopenedTarget.handle?.projectDir, projectDir.path);
      expect(
        (reopenedTarget.handle?.metadata['remoteSession']
            as Map<String, Object?>)['projectDir'],
        projectDir.path,
      );
      expect(
        reopenedTarget.handle?.metadata['supervisorLogPath'],
        supervisorLog.path,
      );
      expect(reopenedApp.handle.projectDir, projectDir.path);
      expect(reopenedApp.handle.remoteSession?.projectDir, projectDir.path);
      expect(
        reopenedApp.handle.developmentSession?.projectDir,
        projectDir.path,
      );
      expect(reopenedApp.handle.supervisorLogPath, supervisorLog.path);
      expect(reopenedSession.remoteHandle.projectDir, projectDir.path);
      expect(reopenedSession.developmentHandle?.projectDir, projectDir.path);

      await supervisorLog.parent.delete(recursive: true);
      final reopenedAfterLogRemoval = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      final appAfterLogRemoval = await reopenedAfterLogRemoval.requireApp(
        app.appId,
      );
      expect(appAfterLogRemoval.handle.supervisorLogPath, supervisorLog.path);
      await reopenedAfterLogRemoval.removeApp(app.appId);
      expect(
        (await reopenedAfterLogRemoval.readTarget(targetId)).handle,
        isNull,
      );
      expect(
        await reopenedAfterLogRemoval.latestSessionIdsByTarget(),
        isNot(contains(targetId)),
      );
      final reopenedAfterStop = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      expect((await reopenedAfterStop.readTarget(targetId)).handle, isNull);
    },
  );

  test('rejects absolute and escaping persisted handle identities', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-handle-corruption-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    final projectDir = await Directory(
      p.join(workspaceRoot, 'packages', 'demo'),
    ).create(recursive: true);
    final stateRoot = await Directory(p.join(workspaceRoot, 'state')).create();
    final supervisorLog = await File(
      p.join(stateRoot.path, 'logs', 'supervisor.log'),
    ).create(recursive: true);
    final sourceStore = CockpitInMemoryWorkerRuntimeStateStore();
    final source = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot.path,
      stateStore: sourceStore,
    );
    final targetId = await source.registerTarget(
      const CockpitWorkerTargetRegistration(
        workspaceId: 'workspaceA',
        platform: 'android',
        deviceId: 'emulator-5554',
      ),
    );
    final remote = _remoteSession(projectDir.path);
    final development = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'development-session-A',
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: projectDir.path,
      target: 'android',
      appId: remote.appId,
      appBaseUrl: remote.baseUrl,
      supervisorBaseUrl: 'http://127.0.0.1:9201',
      launchedAt: DateTime.utc(2026, 7, 22),
      reloadGeneration: 1,
      remoteSessionHandle: remote,
    );
    final appHandle = CockpitAppHandle.fromDevelopmentSession(
      development,
      supervisorLogPath: supervisorLog.path,
    );
    await source.recordTargetHandle(
      targetId: targetId,
      handle: CockpitTargetHandle.fromAppHandle(appHandle),
    );
    await source.recordApp(targetId: targetId, handle: appHandle);
    final valid = await sourceStore.read();
    final corruptions = <void Function(Map<String, Object?>)>[
      (state) => _targetHandle(state)['projectIdentity'] = workspaceRoot,
      (state) => _targetRemote(state)['projectIdentity'] = '../outside',
      (state) =>
          _targetMetadata(state)['supervisorLogIdentity'] = '../outside.log',
      (state) => _appHandle(state)['projectIdentity'] = workspaceRoot,
      (state) => _appRemote(state)['projectIdentity'] = '../outside',
      (state) => _appDevelopment(state)['projectIdentity'] = '../outside',
      (state) => _sessionRemote(state)['projectIdentity'] = workspaceRoot,
      (state) => _sessionDevelopment(state)['projectIdentity'] = '../outside',
      (state) => _appHandle(state)['supervisorLogIdentity'] = workspaceRoot,
    ];
    if (!Platform.isWindows) {
      final outside = await Directory.systemTemp.createTemp(
        'cockpit-worker-handle-outside-',
      );
      addTearDown(() => outside.delete(recursive: true));
      await Link(
        p.join(workspaceRoot, 'linked-outside-project'),
      ).create(outside.path);
      await File(p.join(outside.path, 'supervisor.log')).create();
      await Link(
        p.join(stateRoot.path, 'linked-outside-state'),
      ).create(outside.path);
      corruptions.add(
        (state) =>
            _appHandle(state)['projectIdentity'] = 'linked-outside-project',
      );
      corruptions.add(
        (state) => _appHandle(state)['supervisorLogIdentity'] =
            'linked-outside-state/supervisor.log',
      );
    }

    for (var index = 0; index < corruptions.length; index += 1) {
      final corrupted = Map<String, Object?>.from(
        jsonDecode(jsonEncode(valid)) as Map<Object?, Object?>,
      );
      corruptions[index](corrupted);
      final store = CockpitInMemoryWorkerRuntimeStateStore();
      await store.write(corrupted);
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      await expectLater(
        registry.flush(),
        throwsA(anyOf(isA<FormatException>(), isA<FileSystemException>())),
        reason: 'corruption $index',
      );
    }
  });

  test(
    'write failure restores persisted and transient registry state',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-runtime-rollback-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final canonicalRoot = await temporary.resolveSymbolicLinks();
      final stateRoot = await Directory(
        p.join(canonicalRoot, 'state'),
      ).create();
      final store = _FailingRuntimeStateStore();
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: canonicalRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      final targetId = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );
      final app = await registry.recordApp(
        targetId: targetId,
        handle: CockpitAppHandle.fromRemoteSession(
          _remoteSession(canonicalRoot),
        ),
      );
      final sessionId = await registry.sessionIdForApp(app.appId);
      final snapshotRef = await registry.recordSnapshotRef(
        sessionId: sessionId,
        retainedRef: 'retained-snapshot-A',
      );

      store.failNextWrite = true;
      await expectLater(registry.removeSession(sessionId), throwsStateError);

      expect((await registry.requireSession(sessionId)).appId, app.appId);
      expect(
        await registry.resolveSnapshotRef(
          sessionId: sessionId,
          snapshotRef: snapshotRef,
        ),
        'retained-snapshot-A',
      );
    },
  );

  test(
    'serializes snapshot refs after a failing persisted transaction rollback',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-runtime-snapshot-race-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final canonicalRoot = await temporary.resolveSymbolicLinks();
      final stateRoot = await Directory(
        p.join(canonicalRoot, 'state'),
      ).create();
      final store = _BlockingFailingRuntimeStateStore();
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: canonicalRoot,
        stateRoot: stateRoot.path,
        stateStore: store,
      );
      final targetId = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );
      final app = await registry.recordApp(
        targetId: targetId,
        handle: CockpitAppHandle.fromRemoteSession(
          _remoteSession(canonicalRoot),
        ),
      );
      final sessionId = await registry.sessionIdForApp(app.appId);

      store.blockAndFailNextWrite = true;
      final failingFlush = registry.flush();
      await store.writeEntered.future;
      var snapshotCompleted = false;
      final snapshotFuture = registry.recordSnapshotRef(
        sessionId: sessionId,
        retainedRef: 'retained-during-write',
      );
      unawaited(snapshotFuture.then<void>((_) => snapshotCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(snapshotCompleted, isFalse);

      store.releaseWrite.complete();
      await expectLater(failingFlush, throwsStateError);
      final snapshotRef = await snapshotFuture;
      expect(
        await registry.resolveSnapshotRef(
          sessionId: sessionId,
          snapshotRef: snapshotRef,
        ),
        'retained-during-write',
      );
    },
  );

  test(
    'bounds transient snapshot refs without eviction and clears lifecycle state',
    () async {
      final fixture = await _RuntimeGraphFixture.create();
      addTearDown(fixture.dispose);
      final store = _DirectRuntimeStateStore(_deepCopyState(fixture.baseState));
      final registry = fixture.open(store);
      await registry.requireSession(fixture.sessionId);
      final refs = <String>[];
      for (
        var index = 0;
        index < CockpitWorkerRuntimeRegistry.maximumTransientSnapshots;
        index += 1
      ) {
        refs.add(
          await registry.recordSnapshotRef(
            sessionId: fixture.sessionId,
            retainedRef: 'retained-snapshot-$index',
          ),
        );
      }

      expect(
        await registry.recordSnapshotRef(
          sessionId: fixture.sessionId,
          retainedRef: 'retained-snapshot-0',
        ),
        refs.first,
      );
      await expectLater(
        registry.recordSnapshotRef(
          sessionId: fixture.sessionId,
          retainedRef: 'retained-snapshot-overflow',
        ),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'workerSnapshotCapacityExceeded',
          ),
        ),
      );
      expect(
        await registry.resolveSnapshotRef(
          sessionId: fixture.sessionId,
          snapshotRef: refs.last,
        ),
        'retained-snapshot-${refs.length - 1}',
      );

      await registry.flush();
      final reopened = fixture.open(store);
      await reopened.requireSession(fixture.sessionId);
      await expectLater(
        reopened.resolveSnapshotRef(
          sessionId: fixture.sessionId,
          snapshotRef: refs.first,
        ),
        throwsA(isA<CockpitApplicationServiceException>()),
      );

      await registry.removeSession(fixture.sessionId);
      await expectLater(
        registry.resolveSnapshotRef(
          sessionId: fixture.sessionId,
          snapshotRef: refs.last,
        ),
        throwsA(isA<CockpitApplicationServiceException>()),
      );
    },
  );

  test(
    'enforces every registry collection limit with rollback and reopen',
    () async {
      final fixture = await _RuntimeGraphFixture.create();
      addTearDown(fixture.dispose);
      final cases = <(String, int)>[
        ('targets', CockpitWorkerRuntimeRegistry.maximumTargets),
        ('apps', CockpitWorkerRuntimeRegistry.maximumApps),
        ('sessions', CockpitWorkerRuntimeRegistry.maximumSessions),
        ('recordings', CockpitWorkerRuntimeRegistry.maximumRecordings),
        ('artifacts', CockpitWorkerRuntimeRegistry.maximumArtifacts),
        ('probes', CockpitWorkerRuntimeRegistry.maximumRetainedProbes),
      ];

      for (final (collection, maximum) in cases) {
        final state = _expandedCollection(
          fixture.baseState,
          collection,
          maximum,
        );
        final store = _DirectRuntimeStateStore(state);
        final registry = fixture.open(store);

        await expectLater(
          fixture.addOne(registry, collection),
          throwsA(anything),
          reason: collection,
        );
        await registry.flush();
        expect(
          (store.state[collection]! as List<Object?>),
          hasLength(maximum),
          reason: collection,
        );
        await fixture.open(store).flush();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('rejects cross-owner persisted graph corruption', () async {
    final fixture = await _RuntimeGraphFixture.create();
    addTearDown(fixture.dispose);
    final sessionId =
        _firstRecord(fixture.baseState, 'sessions')['sessionId']! as String;
    final corruptions = <void Function(Map<String, Object?>)>[
      (state) => _firstRecord(state, 'apps')['targetId'] = 'target_missing',
      (state) => _firstRecord(state, 'sessions')['appId'] = 'app_missing',
      (state) => _firstRecord(state, 'recordings')['appId'] = 'app_missing',
      (state) {
        final artifact = _firstRecord(state, 'artifacts');
        artifact['ownerKind'] = 'session';
        artifact['ownerId'] = 'session_missing';
      },
      (state) => _firstRecord(state, 'artifacts')['retainedPath'] = p.join(
        fixture.stateRoot,
        'runs',
        'run_other',
        'artifacts',
        'base.bin',
      ),
      (state) => _firstRecord(state, 'probes')['sessionId'] = 'session_missing',
      (state) => _targetHandle(state)['deviceId'] = 'other-device',
      (state) => _targetRemote(state)['platform'] = 'ios',
      (state) => _targetRemote(state)['deviceId'] = 'other-device',
      (state) => _targetRemote(state)['target'] = 'other-target',
      (state) => _targetRemote(state)['appId'] = 'other-app',
      (state) => _targetRemote(state)['baseUrl'] = 'http://127.0.0.1:9999',
      (state) => _appRemote(state)['deviceId'] = 'other-device',
      (state) => _sessionRemote(state)['hostPort'] = 9999,
      (state) =>
          _probePayload(state)['sessionId'] = 'development-session-other',
      (state) {
        final artifact = _firstRecord(state, 'artifacts');
        artifact['ownerKind'] = 'session';
        artifact['ownerId'] = sessionId;
        artifact['kind'] = 'caseAttemptBundle';
        artifact['retainedPath'] = p.join(
          fixture.stateRoot,
          'retained_artifacts',
          'session',
          sessionId,
          'bundle',
        );
      },
    ];

    for (var index = 0; index < corruptions.length; index += 1) {
      final corrupted = _deepCopyState(fixture.baseState);
      corruptions[index](corrupted);
      await expectLater(
        fixture.open(_DirectRuntimeStateStore(corrupted)).flush(),
        throwsA(anyOf(isA<FormatException>(), isA<FileSystemException>())),
        reason: 'corruption $index',
      );
    }
  });

  test('rejects cross-owner probe identity before persistence', () async {
    final fixture = await _RuntimeGraphFixture.create();
    addTearDown(fixture.dispose);
    final store = _DirectRuntimeStateStore(_deepCopyState(fixture.baseState));
    final registry = fixture.open(store);
    final before = jsonEncode(store.state);

    await expectLater(
      registry.recordProbe(
        sessionId: fixture.sessionId,
        probe: CockpitDevelopmentProbe(
          probeId: 'probe_payload_wrong',
          sessionId: 'development-session-other',
          reloadGeneration: 0,
          capturedAt: DateTime.utc(2026, 7, 22),
          reason: CockpitDevelopmentProbeReason.manual,
          profile: CockpitDevelopmentProbeProfile.quick,
          routeName: '/',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(jsonEncode(store.state), before);
  });
}

Map<String, Object?> _expandedCollection(
  Map<String, Object?> source,
  String collection,
  int maximum,
) {
  final state = Map<String, Object?>.from(source);
  final template = _firstRecord(source, collection);
  final idField = switch (collection) {
    'targets' => 'targetId',
    'apps' => 'appId',
    'sessions' => 'sessionId',
    'recordings' => 'recordingId',
    'artifacts' => 'artifactId',
    'probes' => 'probeId',
    _ => throw ArgumentError.value(collection, 'collection'),
  };
  state[collection] = <Object?>[
    for (var index = 0; index < maximum; index += 1)
      <String, Object?>{
        ...template,
        idField: index == 0 ? template[idField] : '${idField}_limit_$index',
      },
  ];
  return state;
}

Map<String, Object?> _deepCopyState(Map<String, Object?> source) =>
    Map<String, Object?>.from(
      jsonDecode(jsonEncode(source))! as Map<Object?, Object?>,
    );

Map<String, Object?> _runtimeState({
  List<Object?> artifacts = const <Object?>[],
  List<Object?> probes = const <Object?>[],
}) => <String, Object?>{
  'schemaVersion': 'cockpit.worker.runtime/v4',
  'workspaceId': 'workspaceA',
  'targets': <Object?>[],
  'apps': <Object?>[],
  'sessions': <Object?>[],
  'recordings': <Object?>[],
  'artifacts': artifacts,
  'probes': probes,
};

CockpitRemoteSessionHandle _remoteSession(String projectDir) =>
    CockpitRemoteSessionHandle(
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: projectDir,
      target: 'android',
      appId: 'internal-app-A',
      platformAppIdKnown: false,
      host: '127.0.0.1',
      hostPort: 9101,
      devicePort: 8101,
      baseUrl: 'http://127.0.0.1:9101',
      launchedAt: DateTime.utc(2026, 7, 22),
    );

Map<String, Object?> _firstRecord(
  Map<String, Object?> state,
  String collection,
) => ((state[collection]! as List<Object?>).first! as Map<Object?, Object?>)
    .cast<String, Object?>();

Map<String, Object?> _nested(Map<String, Object?> value, String key) =>
    (value[key]! as Map<Object?, Object?>).cast<String, Object?>();

Map<String, Object?> _targetHandle(Map<String, Object?> state) =>
    _nested(_firstRecord(state, 'targets'), 'handle');

Map<String, Object?> _targetMetadata(Map<String, Object?> state) =>
    _nested(_targetHandle(state), 'metadata');

Map<String, Object?> _targetRemote(Map<String, Object?> state) =>
    _nested(_targetMetadata(state), 'remoteSession');

Map<String, Object?> _appHandle(Map<String, Object?> state) =>
    _nested(_firstRecord(state, 'apps'), 'handle');

Map<String, Object?> _appRemote(Map<String, Object?> state) =>
    _nested(_appHandle(state), 'remoteSession');

Map<String, Object?> _appDevelopment(Map<String, Object?> state) =>
    _nested(_appHandle(state), 'developmentSession');

Map<String, Object?> _sessionRemote(Map<String, Object?> state) =>
    _nested(_firstRecord(state, 'sessions'), 'remoteHandle');

Map<String, Object?> _sessionDevelopment(Map<String, Object?> state) =>
    _nested(_firstRecord(state, 'sessions'), 'developmentHandle');

Map<String, Object?> _probePayload(Map<String, Object?> state) =>
    _nested(_firstRecord(state, 'probes'), 'probe');

Future<Directory> _currentGenerationDirectory(String runtimeRoot) async {
  final manifest =
      jsonDecode(
            await File(p.join(runtimeRoot, 'manifest.json')).readAsString(),
          )!
          as Map<String, Object?>;
  return Directory(
    p.join(runtimeRoot, 'generations', manifest['generation']! as String),
  );
}

final class _RuntimeStoreFixture {
  const _RuntimeStoreFixture({
    required this.temporary,
    required this.workspaceRoot,
    required this.stateRoot,
    required this.runtimeRoot,
    required this.store,
  });

  final Directory temporary;
  final String workspaceRoot;
  final String stateRoot;
  final String runtimeRoot;
  final CockpitFileWorkerRuntimeStateStore store;

  static Future<_RuntimeStoreFixture> create() async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-runtime-store-',
    );
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    final state = await Directory(p.join(workspaceRoot, 'state')).create();
    final runtimeRoot = p.join(state.path, 'runtime');
    return _RuntimeStoreFixture(
      temporary: temporary,
      workspaceRoot: workspaceRoot,
      stateRoot: state.path,
      runtimeRoot: runtimeRoot,
      store: CockpitFileWorkerRuntimeStateStore(
        root: runtimeRoot,
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      ),
    );
  }

  Future<void> dispose() => temporary.delete(recursive: true);
}

final class _FailingRuntimeStateStore
    implements CockpitWorkerRuntimeStateStore {
  final CockpitInMemoryWorkerRuntimeStateStore _delegate =
      CockpitInMemoryWorkerRuntimeStateStore();
  var failNextWrite = false;

  @override
  Future<Map<String, Object?>> read() => _delegate.read();

  @override
  Future<void> write(Map<String, Object?> state) {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('injected runtime state write failure');
    }
    return _delegate.write(state);
  }
}

final class _BlockingFailingRuntimeStateStore
    implements CockpitWorkerRuntimeStateStore {
  final CockpitInMemoryWorkerRuntimeStateStore _delegate =
      CockpitInMemoryWorkerRuntimeStateStore();
  final Completer<void> writeEntered = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();
  var blockAndFailNextWrite = false;

  @override
  Future<Map<String, Object?>> read() => _delegate.read();

  @override
  Future<void> write(Map<String, Object?> state) async {
    if (blockAndFailNextWrite) {
      blockAndFailNextWrite = false;
      writeEntered.complete();
      await releaseWrite.future;
      throw StateError('injected blocked runtime state write failure');
    }
    await _delegate.write(state);
  }
}

final class _DirectRuntimeStateStore implements CockpitWorkerRuntimeStateStore {
  _DirectRuntimeStateStore(this.state);

  Map<String, Object?> state;

  @override
  Future<Map<String, Object?>> read() async => state;

  @override
  Future<void> write(Map<String, Object?> state) async {
    this.state = state;
  }
}

final class _RuntimeGraphFixture {
  const _RuntimeGraphFixture({
    required this.temporary,
    required this.workspaceRoot,
    required this.stateRoot,
    required this.baseState,
    required this.sessionId,
  });

  final Directory temporary;
  final String workspaceRoot;
  final String stateRoot;
  final Map<String, Object?> baseState;
  final String sessionId;

  static Future<_RuntimeGraphFixture> create() async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-runtime-graph-',
    );
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    final stateRoot = (await Directory(
      p.join(workspaceRoot, 'state'),
    ).create()).path;
    final store = CockpitInMemoryWorkerRuntimeStateStore();
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot,
      stateStore: store,
      runOwnershipAuthority: const _FixedRunOwnershipAuthority(<String>{
        'run_A',
      }),
      tokenGenerator: _SequenceTokenGenerator('base'),
      utcNow: () => DateTime.utc(2026, 7, 22),
    );
    final targetId = await registry.registerTarget(
      const CockpitWorkerTargetRegistration(
        workspaceId: 'workspaceA',
        platform: 'android',
        deviceId: 'emulator-5554',
        environment: CockpitTestTargetEnvironment.development,
      ),
    );
    final remote = _remoteSessionForGraph(workspaceRoot, 'base');
    final development = _developmentSessionForGraph(remote, 'base');
    final app = await registry.recordApp(
      targetId: targetId,
      handle: CockpitAppHandle.fromDevelopmentSession(development),
    );
    await registry.recordTargetHandle(
      targetId: targetId,
      handle: CockpitTargetHandle.fromAppHandle(app.handle),
    );
    final sessionId = await registry.sessionIdForApp(app.appId);
    await registry.recordRecording(sessionId: sessionId);
    await registry.recordProbe(
      sessionId: sessionId,
      probe: CockpitDevelopmentProbe(
        probeId: 'probe_payload_A',
        sessionId: development.developmentSessionId,
        reloadGeneration: 0,
        capturedAt: DateTime.utc(2026, 7, 22),
        reason: CockpitDevelopmentProbeReason.manual,
        profile: CockpitDevelopmentProbeProfile.quick,
        routeName: '/',
      ),
    );
    final artifact = await File(
      p.join(stateRoot, 'runs', 'run_A', 'artifacts', 'base.bin'),
    ).create(recursive: true);
    await registry.registerArtifact(
      ownerKind: 'run',
      ownerId: 'run_A',
      kind: 'screenshot',
      name: 'base.bin',
      mediaType: 'application/octet-stream',
      retainedPath: artifact.path,
    );
    return _RuntimeGraphFixture(
      temporary: temporary,
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot,
      baseState: await store.read(),
      sessionId: sessionId,
    );
  }

  CockpitWorkerRuntimeRegistry open(CockpitWorkerRuntimeStateStore store) =>
      CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot,
        stateStore: store,
        runOwnershipAuthority: const _FixedRunOwnershipAuthority(<String>{
          'run_A',
        }),
        tokenGenerator: _SequenceTokenGenerator('new'),
        utcNow: () => DateTime.utc(2026, 7, 22),
      );

  Future<void> addOne(
    CockpitWorkerRuntimeRegistry registry,
    String collection,
  ) async {
    switch (collection) {
      case 'targets':
        await registry.registerTarget(
          const CockpitWorkerTargetRegistration(
            workspaceId: 'workspaceA',
            platform: 'android',
            deviceId: 'new-device',
          ),
        );
        return;
      case 'apps' || 'sessions':
        final targetId =
            _firstRecord(baseState, 'targets')['targetId']! as String;
        await registry.recordApp(
          targetId: targetId,
          handle: CockpitAppHandle.fromRemoteSession(
            _remoteSessionForGraph(workspaceRoot, 'new'),
          ),
        );
        return;
      case 'recordings':
        await registry.recordRecording(sessionId: sessionId);
        return;
      case 'artifacts':
        final artifact = await File(
          p.join(stateRoot, 'runs', 'run_A', 'artifacts', 'new.bin'),
        ).create(recursive: true);
        await registry.registerArtifact(
          ownerKind: 'run',
          ownerId: 'run_A',
          kind: 'trace',
          name: 'new.bin',
          mediaType: 'application/octet-stream',
          retainedPath: artifact.path,
        );
        return;
      case 'probes':
        final developmentSessionId =
            _sessionDevelopment(baseState)['developmentSessionId']! as String;
        await registry.recordProbe(
          sessionId: sessionId,
          probe: CockpitDevelopmentProbe(
            probeId: 'probe_payload_new',
            sessionId: developmentSessionId,
            reloadGeneration: 1,
            capturedAt: DateTime.utc(2026, 7, 22),
            reason: CockpitDevelopmentProbeReason.postAction,
            profile: CockpitDevelopmentProbeProfile.quick,
            routeName: '/',
          ),
        );
        return;
      default:
        throw ArgumentError.value(collection, 'collection');
    }
  }

  Future<void> dispose() => temporary.delete(recursive: true);
}

CockpitRemoteSessionHandle _remoteSessionForGraph(
  String projectDir,
  String suffix,
) => CockpitRemoteSessionHandle(
  platform: 'android',
  deviceId: 'emulator-5554',
  projectDir: projectDir,
  target: 'android',
  appId: 'internal-app-$suffix',
  platformAppIdKnown: false,
  host: '127.0.0.1',
  hostPort: suffix == 'base' ? 9101 : 9102,
  devicePort: suffix == 'base' ? 8101 : 8102,
  baseUrl: 'http://127.0.0.1:${suffix == 'base' ? 9101 : 9102}',
  launchedAt: DateTime.utc(2026, 7, 22),
);

CockpitDevelopmentSessionHandle _developmentSessionForGraph(
  CockpitRemoteSessionHandle remote,
  String suffix,
) => CockpitDevelopmentSessionHandle(
  developmentSessionId: 'development-session-$suffix',
  platform: remote.platform,
  deviceId: remote.deviceId,
  projectDir: remote.projectDir,
  target: remote.target,
  appId: remote.appId,
  appBaseUrl: remote.baseUrl,
  supervisorBaseUrl: 'http://127.0.0.1:${suffix == 'base' ? 9201 : 9202}',
  launchedAt: remote.launchedAt,
  reloadGeneration: 0,
  remoteSessionHandle: remote,
);

final class _SequenceTokenGenerator implements CockpitTokenGenerator {
  _SequenceTokenGenerator(this._prefix);

  final String _prefix;
  var _next = 0;

  @override
  String nextToken({int byteLength = 32}) => '${_prefix}_${_next++}';
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

final class _FixedRunOwnershipAuthority
    implements CockpitWorkerRunOwnershipAuthority {
  const _FixedRunOwnershipAuthority(this.runIds);

  final Set<String> runIds;

  @override
  Future<Set<String>> findOwnedRunIds({
    required String workspaceId,
    required Set<String> candidateRunIds,
  }) async => <String>{
    for (final runId in candidateRunIds)
      if (workspaceId == 'workspaceA' && runIds.contains(runId)) runId,
  };
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
