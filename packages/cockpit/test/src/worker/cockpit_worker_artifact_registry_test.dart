import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/worker/cockpit_worker_application_support.dart';
import 'package:cockpit/src/worker/cockpit_worker_artifact_retainer.dart';
import 'package:cockpit/src/worker/cockpit_worker_case_run_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_run_ownership_authority.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('sanitizer preserves Flutter routes without exposing paths', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-route-sanitizer-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final workspace = await Directory(
      p.join(temporary.path, 'workspace'),
    ).create();
    final stateRoot = await Directory(p.join(temporary.path, 'state')).create();
    await Directory(p.join(stateRoot.path, 'producer_artifacts')).create();
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspace.path,
      stateRoot: stateRoot.path,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    final outsidePath = p.join(
      p.rootPrefix(stateRoot.path),
      'private',
      'application.dart',
    );

    final result =
        await CockpitWorkerResultSanitizer(
          workspaceRoot: workspace.path,
          registry: registry,
          artifactRetainer: _retainer(stateRoot.path),
        ).sanitize(<String, Object?>{
          'snapshot': <String, Object?>{
            'routeName': '/operations',
            'visibleTargets': <Object?>[
              <String, Object?>{
                'route': '/operations',
                'loc': '/scaffold/textbutton',
                'text': '/inspect Inspect the current project',
                'textParts': <String>[
                  '/inspect',
                  'Inspect the current project',
                ],
                'source': outsidePath,
                'workspaceSource': p.join(workspace.path, 'lib', 'main.dart'),
              },
            ],
          },
        });

    final snapshot = result['snapshot']! as Map<String, Object?>;
    expect(snapshot['routeName'], '/operations');
    final target =
        (snapshot['visibleTargets']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(target['route'], '/operations');
    expect(target['loc'], '/scaffold/textbutton');
    expect(target['text'], '/inspect Inspect the current project');
    expect(target['textParts'], <String>[
      '/inspect',
      'Inspect the current project',
    ]);
    expect(target['source'], '<redacted-path>');
    expect(
      target['workspaceSource'],
      p.join('<workspace-path>', 'lib', 'main.dart'),
    );
  });

  test('sanitizer persists opaque run-owned artifact references', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-artifacts-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final workspace = await Directory(
      p.join(temporary.path, 'workspace'),
    ).create();
    final stateRoot = await Directory(p.join(temporary.path, 'state')).create();
    final stateRootPath = await stateRoot.resolveSymbolicLinks();
    final producerRoot = await Directory(
      p.join(stateRootPath, 'producer_artifacts'),
    ).create();
    final source = await File(
      p.join(producerRoot.path, 'capture-source.png'),
    ).writeAsBytes(<int>[1, 2, 3]);
    final statePath = p.join(stateRootPath, 'runtime');
    final hardener = Platform.isWindows
        ? const CockpitWindowsInheritedAclPermissionHardener()
        : const CockpitPosixPermissionHardener();
    CockpitWorkerCaseRunStore runAuthority() => CockpitWorkerCaseRunStore.file(
      workspaceId: 'workspaceA',
      path: p.join(stateRootPath, 'case_runs'),
      permissionHardener: hardener,
      directorySyncer: const _NoopDirectorySyncer(),
    );
    await runAuthority().reserve(
      idempotencyKey: 'artifact-run-A',
      requestFingerprint: List<String>.filled(64, 'a').join(),
      caseId: 'case_artifact_A',
      proposedRunId: 'run_A',
      proposedAttemptId: 'attempt_A',
      now: DateTime.utc(2026, 7, 22),
    );
    CockpitFileWorkerRuntimeStateStore runtimeStore() =>
        CockpitFileWorkerRuntimeStateStore(
          root: statePath,
          permissionHardener: hardener,
          directorySyncer: const _NoopDirectorySyncer(),
        );
    CockpitWorkerRuntimeRegistry registry() => CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspace.path,
      stateRoot: stateRootPath,
      stateStore: runtimeStore(),
      runOwnershipAuthority: runAuthority(),
    );

    final first = registry();
    final retainer = _retainer(stateRootPath, hardener);
    final sanitized =
        await CockpitWorkerResultSanitizer(
          workspaceRoot: workspace.path,
          registry: first,
          artifactRetainer: retainer,
        ).sanitize(<String, Object?>{
          'artifacts': <Object?>[
            <String, Object?>{
              'role': 'screenshot',
              'relativePath': 'screenshots/acceptance.png',
            },
          ],
          'artifactSourcePaths': <String, Object?>{
            'screenshots/acceptance.png': source.path,
          },
        }, runId: 'run_A');

    expect(sanitized.toString(), isNot(contains(source.path)));
    expect(sanitized.toString(), isNot(contains('relativePath')));
    expect(sanitized.toString(), isNot(contains('artifactSourcePaths')));
    final artifact =
        (sanitized['artifacts']! as List<Object?>).single!
            as Map<String, Object?>;
    final reference = artifact['artifactRef']! as Map<String, Object?>;
    expect(reference['kind'], 'screenshot');
    expect(reference['name'], 'acceptance.png');
    expect(reference['mediaType'], 'image/png');
    final artifactId = reference['artifactId']! as String;

    final reopened = registry();
    final binding = await reopened.requireArtifact(artifactId);
    expect(binding.ownerKind, 'run');
    expect(binding.ownerId, 'run_A');
    expect(
      binding.retainedPath,
      startsWith(p.join(stateRootPath, 'runs', 'run_A', 'artifacts')),
    );
    expect(await File(binding.retainedPath).readAsBytes(), <int>[1, 2, 3]);

    final unknownPath = p.join(
      stateRootPath,
      'runs',
      'run_unknown',
      'artifacts',
      'unknown.png',
    );
    await File(unknownPath).create(recursive: true);
    await expectLater(
      reopened.registerArtifact(
        ownerKind: 'run',
        ownerId: 'run_unknown',
        kind: 'screenshot',
        name: 'unknown.png',
        mediaType: 'image/png',
        retainedPath: unknownPath,
      ),
      throwsA(isA<FormatException>()),
    );
    expect((await reopened.requireArtifact(artifactId)).ownerId, 'run_A');

    final corrupted = await runtimeStore().read();
    final artifactJson =
        (corrupted['artifacts']! as List<Object?>).single!
            as Map<String, Object?>;
    artifactJson['ownerId'] = 'run_unknown';
    artifactJson['retainedPath'] = unknownPath;
    await runtimeStore().write(corrupted);
    await expectLater(registry().flush(), throwsA(isA<FormatException>()));
  });

  test(
    'direct artifact paths use recording ownership and safe metadata',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'cockpit-worker-recording-artifact-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final stateRoot = await Directory(
        p.join(workspace.path, 'state'),
      ).create();
      final workspaceRoot = await workspace.resolveSymbolicLinks();
      final stateRootPath = await stateRoot.resolveSymbolicLinks();
      final producerRoot = await Directory(
        p.join(stateRootPath, 'producer_artifacts'),
      ).create();
      final source = await File(
        p.join(producerRoot.path, 'private-recording.mov'),
      ).writeAsBytes(<int>[1]);
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRootPath,
        stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
      );
      final owner = await _seedRuntimeOwner(registry, workspaceRoot);
      final result =
          await CockpitWorkerResultSanitizer(
            workspaceRoot: workspace.path,
            registry: registry,
            artifactRetainer: _retainer(stateRootPath),
          ).sanitize(<String, Object?>{
            'artifact': <String, Object?>{
              'role': 'recording',
              'relativePath': 'recordings/flow.mov',
            },
            'sourceFilePath': source.path,
          }, recordingId: owner.$2);
      expect(result.containsKey('sourceFilePath'), isFalse);
      final artifact = result['artifact']! as Map<String, Object?>;
      final reference = artifact['artifactRef']! as Map<String, Object?>;
      final binding = await registry.requireArtifact(
        reference['artifactId']! as String,
      );
      expect(binding.ownerKind, 'recording');
      expect(binding.ownerId, owner.$2);
      expect(binding.name, 'flow.mov');
      expect(binding.mediaType, 'video/quicktime');
    },
  );

  test('interactive source paths become opaque session artifacts', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'cockpit-worker-interactive-artifact-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final stateRoot = await Directory(p.join(workspace.path, 'state')).create();
    final workspaceRoot = await workspace.resolveSymbolicLinks();
    final stateRootPath = await stateRoot.resolveSymbolicLinks();
    final producerRoot = await Directory(
      p.join(stateRootPath, 'producer_artifacts'),
    ).create();
    final source = await File(
      p.join(producerRoot.path, 'interactive-capture.png'),
    ).writeAsBytes(<int>[1]);
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRootPath,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
      runOwnershipAuthority: const _FixedRunOwnershipAuthority(<String>{
        'run_A',
      }),
    );
    final owner = await _seedRuntimeOwner(registry, workspaceRoot);

    final result =
        await CockpitWorkerResultSanitizer(
          workspaceRoot: workspace.path,
          registry: registry,
          artifactRetainer: _retainer(stateRootPath),
        ).sanitize(<String, Object?>{
          'artifacts': <Object?>[
            <String, Object?>{
              'role': 'screenshot',
              'relativePath': 'screenshots/current.png',
              'sourcePath': source.path,
            },
          ],
        }, sessionId: owner.$1);

    expect(result.toString(), isNot(contains(source.path)));
    expect(result.toString(), isNot(contains('sourcePath')));
    final artifact =
        (result['artifacts']! as List<Object?>).single! as Map<String, Object?>;
    final reference = artifact['artifactRef']! as Map<String, Object?>;
    final binding = await registry.requireArtifact(
      reference['artifactId']! as String,
    );
    expect(binding.ownerKind, 'session');
    expect(binding.ownerId, owner.$1);
    expect(
      binding.retainedPath,
      startsWith(p.join(stateRootPath, 'retained_artifacts')),
    );
    expect(await File(binding.retainedPath).readAsBytes(), <int>[1]);
  });

  test('bundle paths retain an opaque bundle and nested artifact', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'cockpit-worker-bundle-artifacts-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final stateRoot = await Directory(p.join(workspace.path, 'state')).create();
    final stateRootPath = await stateRoot.resolveSymbolicLinks();
    final bundle = await Directory(
      p.join(stateRootPath, 'runs', 'run_A', 'cases', 'attempt_A', 'bundle'),
    ).create(recursive: true);
    final source = await File(
      p.join(bundle.path, 'screenshots', 'acceptance.png'),
    ).create(recursive: true);
    await source.writeAsBytes(<int>[1]);
    final runAuthority = CockpitWorkerCaseRunStore.memory(
      workspaceId: 'workspaceA',
    );
    await runAuthority.reserve(
      idempotencyKey: 'bundle-run-A',
      requestFingerprint: List<String>.filled(64, 'b').join(),
      caseId: 'case_bundle_A',
      proposedRunId: 'run_A',
      proposedAttemptId: 'attempt_A',
      now: DateTime.utc(2026, 7, 22),
    );
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspace.path,
      stateRoot: stateRootPath,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
      runOwnershipAuthority: runAuthority,
    );

    final result =
        await CockpitWorkerResultSanitizer(
          workspaceRoot: workspace.path,
          registry: registry,
          artifactRetainer: _retainer(stateRootPath),
        ).sanitize(
          <String, Object?>{
            'bundlePath': bundle.path,
            'steps': <Object?>[
              <String, Object?>{
                'artifacts': <Object?>[
                  <String, Object?>{
                    'role': 'screenshot',
                    'relativePath': 'screenshots/acceptance.png',
                  },
                ],
              },
            ],
          },
          runId: 'run_A',
          committedBundleRoot: bundle.path,
        );

    expect(result.containsKey('bundlePath'), isFalse);
    final bundleReference = result['artifactRef']! as Map<String, Object?>;
    final bundleArtifactId = bundleReference['artifactId']! as String;
    final bundleBinding = await registry.requireArtifact(bundleArtifactId);
    expect(bundleBinding.ownerKind, 'run');
    expect(bundleBinding.ownerId, 'run_A');
    expect(bundleBinding.kind, 'caseAttemptBundle');
    expect(bundleBinding.mediaType, 'application/vnd.cockpit.attempt-bundle');
    expect(
      bundleBinding.retainedPath,
      startsWith(p.join(stateRootPath, 'runs', 'run_A', 'artifacts')),
    );
    expect(
      bundleBinding.retainedPath,
      isNot(p.normalize(bundle.absolute.path)),
    );
    final steps = result['steps']! as List<Object?>;
    final step = steps.single! as Map<String, Object?>;
    final artifacts = step['artifacts']! as List<Object?>;
    final artifact = artifacts.single! as Map<String, Object?>;
    final reference = artifact['artifactRef']! as Map<String, Object?>;
    final binding = await registry.requireArtifact(
      reference['artifactId']! as String,
    );
    expect(binding.ownerKind, 'run');
    expect(binding.ownerId, 'run_A');
    expect(binding.retainedPath, startsWith(bundleBinding.retainedPath));
    expect(await File(binding.retainedPath).readAsBytes(), <int>[1]);
    await source.writeAsBytes(<int>[7, 8, 9]);
    expect(await File(binding.retainedPath).readAsBytes(), <int>[1]);
    if (!Platform.isWindows) {
      final outside = await File(
        p.join(workspace.path, 'outside-after-commit.png'),
      ).writeAsBytes(<int>[9]);
      await Link(
        p.join(bundle.path, 'late-outside-link.png'),
      ).create(outside.path);
      expect(
        (await registry.requireArtifact(bundleArtifactId)).artifactId,
        bundleArtifactId,
      );
      expect(await File(binding.retainedPath).readAsBytes(), <int>[1]);
    }
  });

  test(
    'rejects unconstrained artifact paths and non-regular sources',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-artifact-boundary-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final stateRoot = await Directory(
        p.join(temporary.path, 'state'),
      ).create();
      final stateRootPath = await stateRoot.resolveSymbolicLinks();
      final outside = await File(
        p.join(temporary.path, 'outside.png'),
      ).writeAsBytes(<int>[1]);
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: temporary.path,
        stateRoot: stateRootPath,
        stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
        runOwnershipAuthority: const _FixedRunOwnershipAuthority(<String>{
          'run_A',
        }),
      );
      await expectLater(
        registry.registerArtifact(
          ownerKind: 'run',
          ownerId: 'run_A',
          kind: 'screenshot',
          name: 'outside.png',
          mediaType: 'image/png',
          retainedPath: p.join(stateRootPath, '..', 'outside.png'),
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: outside.path,
          allowDirectory: true,
          committedRoot: outside.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: outside.path,
          allowDirectory: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final internalState = await Directory(
        p.join(stateRootPath, 'internal-state'),
      ).create();
      await File(
        p.join(internalState.path, 'operations.json'),
      ).writeAsString('sensitive journal');
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: internalState.path,
          allowDirectory: true,
          committedRoot: internalState.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final otherRunBundle = await Directory(
        p.join(stateRootPath, 'runs', 'run_B', 'cases', 'attempt_B'),
      ).create(recursive: true);
      final otherRunArtifact = await File(
        p.join(otherRunBundle.path, 'capture.png'),
      ).writeAsBytes(<int>[4, 5, 6]);
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: otherRunBundle.path,
          allowDirectory: true,
          committedRoot: otherRunBundle.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: otherRunArtifact.path,
          allowDirectory: false,
          committedRoot: otherRunBundle.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      final unsafeBundle = await Directory(
        p.join(stateRootPath, 'runs', 'run_A', 'cases', 'unsafe-bundle'),
      ).create(recursive: true);
      final link = Link(p.join(unsafeBundle.path, 'outside-link.png'));
      try {
        await link.create(outside.path);
      } on FileSystemException {
        return;
      }
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: unsafeBundle.path,
          allowDirectory: true,
          committedRoot: unsafeBundle.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        _retainer(stateRootPath).retain(
          ownerKind: 'run',
          ownerId: 'run_A',
          sourcePath: link.path,
          allowDirectory: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}

Future<(String, String)> _seedRuntimeOwner(
  CockpitWorkerRuntimeRegistry registry,
  String workspaceRoot,
) async {
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
      CockpitRemoteSessionHandle(
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: workspaceRoot,
        target: 'android',
        appId: 'internal-app-A',
        platformAppIdKnown: false,
        host: '127.0.0.1',
        hostPort: 9101,
        devicePort: 8101,
        baseUrl: 'http://127.0.0.1:9101',
        launchedAt: DateTime.utc(2026, 7, 22),
      ),
    ),
  );
  final sessionId = await registry.sessionIdForApp(app.appId);
  final recording = await registry.recordRecording(sessionId: sessionId);
  return (sessionId, recording.recordingId);
}

CockpitWorkerArtifactRetainer _retainer(
  String stateRoot, [
  CockpitPermissionHardener? permissionHardener,
]) => CockpitWorkerArtifactRetainer(
  stateRoot: stateRoot,
  producerRoot: p.join(stateRoot, 'producer_artifacts'),
  permissionHardener:
      permissionHardener ??
      (Platform.isWindows
          ? const CockpitWindowsInheritedAclPermissionHardener()
          : const CockpitPosixPermissionHardener()),
  directorySyncer: const _NoopDirectorySyncer(),
);

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
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
