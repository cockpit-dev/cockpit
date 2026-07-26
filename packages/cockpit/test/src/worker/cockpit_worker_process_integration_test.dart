import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/supervisor/cockpit_local_worker_launcher.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_run_projection.dart';
import 'package:cockpit/src/supervisor/cockpit_worker_pool.dart';
import 'package:cockpit/src/supervisor/cockpit_worker_resource_authority.dart';
import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_case_completion.dart';
import 'package:cockpit/src/worker/cockpit_worker_operation_journal.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_case_run_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'worker pool launches and shuts down a real workspace worker',
    () async {
      const environmentSecret = 'worker-environment-secret-value';
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-process-',
      );
      final workspace = await Directory(
        p.join(temporary.path, 'workspace'),
      ).create();
      final state = await Directory(p.join(temporary.path, 'state')).create();
      final remoteSession = await _RemoteSessionServer.start();
      final mainEntrypoint = await File(
        p.join(workspace.path, 'main.dart'),
      ).writeAsString('void main() {}\n');
      final indexedCase =
          await File(p.join(workspace.path, 'indexed_case.yaml')).writeAsString(
            '''
schemaVersion: cockpit.test/v2
kind: case
id: indexedCase
target: {platform: flutter, targetKind: flutterApp, plane: semantic}
steps:
  - stepId: goBack
    action: {type: back}
''',
          );
      await File(p.join(workspace.path, 'suite_case_one.yaml')).writeAsString(
        '''
schemaVersion: cockpit.test/v2
kind: case
id: suiteCaseOne
target: {platform: flutter, targetKind: flutterApp, plane: semantic}
steps:
  - stepId: enterFirst
    action: {type: enterText, text: first}
''',
      );
      await File(p.join(workspace.path, 'suite_case_two.yaml')).writeAsString(
        '''
schemaVersion: cockpit.test/v2
kind: case
id: suiteCaseTwo
target: {platform: flutter, targetKind: flutterApp, plane: semantic}
steps:
  - stepId: enterSecond
    action: {type: enterText, text: second}
''',
      );
      await File(p.join(workspace.path, 'regression_suite.yaml')).writeAsString(
        '''
schemaVersion: cockpit.test/v2
kind: suite
id: regressionSuite
execution: {isolation: sharedSession}
cases:
  - id: firstEntry
    source:
      kind: file
      relativePath: suite_case_one.yaml
      caseId: suiteCaseOne
  - id: secondEntry
    dependsOn: [firstEntry]
    source:
      kind: file
      relativePath: suite_case_two.yaml
      caseId: suiteCaseTwo
''',
      );
      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:cockpit/cockpit.dart'),
      );
      if (packageLibrary == null) {
        throw StateError('Unable to resolve the cockpit package root.');
      }
      final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
      final completionCrashControl = File(
        p.join(temporary.path, 'completion-crash-control.json'),
      );
      final workerEntrypoint = p.join(
        packageRoot,
        'test',
        'support',
        'cockpit_worker_completion_probe.dart',
      );
      final authority = _GrantingAuthority();
      final launcher = CockpitLocalWorkerLauncher(
        dartExecutable: Platform.resolvedExecutable,
        workerEntrypoint: workerEntrypoint,
        retentionIndex: const _RunRetentionIndex(),
        resourceAuthorityFactory: (_, _) => authority,
        environment: <String, String>{
          'PATH': ?Platform.environment['PATH'],
          'HOME': ?Platform.environment['HOME'],
          'SystemRoot': ?Platform.environment['SystemRoot'],
          'API_TOKEN': environmentSecret,
          'COCKPIT_COMPLETION_CRASH_CONTROL': completionCrashControl.path,
        },
        allowedEnvironmentSecretNames: const <String>['API_TOKEN'],
      );
      final pool = CockpitWorkerPool(
        launcher: launcher,
        heartbeatInterval: const Duration(seconds: 30),
      );
      final spec = CockpitWorkspaceWorkerSpec(
        key: CockpitWorkspaceWorkerKey(
          workspaceId: 'workspaceA',
          engineVersion: 'engineA',
        ),
        projectId: 'projectA',
        workspaceRoot: await workspace.resolveSymbolicLinks(),
        stateRoot: await state.resolveSymbolicLinks(),
        supportedFeatures: const <String>['featureA'],
        allowedTargetEnvironments: const <CockpitTestTargetEnvironment>{
          CockpitTestTargetEnvironment.development,
        },
        allowedSafetyEffects: const <CockpitTestSafetyEffect>{
          CockpitTestSafetyEffect.credentialSensitive,
        },
      );
      addTearDown(() async {
        await pool.close(grace: const Duration(seconds: 2));
        await remoteSession.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final initialized = CockpitWorkerInitializeResult.fromJson(
        await pool.call(
          spec,
          method: 'initialize',
          idempotencyKey: 'initialize-workerA',
          deadline: _deadline(),
          params: <String, Object?>{
            'engineVersion': spec.key.engineVersion,
            'workspaceRoot': spec.workspaceRoot,
            'supportedFeatures': spec.supportedFeatures,
          },
        ),
      );
      expect(initialized.workspaceId, spec.key.workspaceId);
      expect(initialized.negotiatedFeatures, spec.supportedFeatures);

      final capabilities = CockpitWorkerCapabilitiesResult.fromJson(
        await pool.call(
          spec,
          method: 'capabilities',
          idempotencyKey: 'capabilities-workerA',
          deadline: _deadline(),
        ),
      );
      expect(
        capabilities.operationKinds,
        containsAll(<String>[
          'analyze.workspace',
          'app.launch',
          'case.run',
          'case.validate',
          'document.index',
          'suite.run',
          'target.get',
          'target.inspect',
          'target.list',
        ]),
      );
      expect(capabilities.operationKinds, isNot(contains('target.discover')));
      expect(capabilities.operationKinds, isNot(contains('package.search')));
      expect(capabilities.operationKinds, isNot(contains('worker.port.bind')));

      final indexed = await _callOperation(
        pool,
        spec,
        kind: 'document.index',
        idempotencyKey: 'document-index-workerA',
      );
      expect(indexed.outcome, CockpitOperationOutcome.succeeded);
      final documents = indexed.output!['documents']! as List<Object?>;
      final mainDocument = documents.cast<Map<Object?, Object?>>().singleWhere(
        (document) => document['kind'] == 'source',
      );
      final caseDocument = documents.cast<Map<Object?, Object?>>().singleWhere(
        (document) =>
            document['kind'] == 'case' &&
            document['authoredId'] == 'indexedCase',
        orElse: () => throw StateError('Indexed case was not found.'),
      );
      final suiteDocument = documents.cast<Map<Object?, Object?>>().singleWhere(
        (document) => document['kind'] == 'suite',
        orElse: () => throw StateError('Indexed suite was not found.'),
      );
      final registered = await _callOperation(
        pool,
        spec,
        kind: 'worker.target.register',
        idempotencyKey: 'target-register-workerA',
        input: <String, Object?>{
          'platform': 'macos',
          'deviceId': 'deviceA',
          'entrypointDocumentId': mainDocument['documentId'],
          'environment': 'development',
          'appId': 'com.example.cockpit',
        },
      );
      expect(registered.outcome, CockpitOperationOutcome.succeeded);
      final targetId = registered.output!['targetId']! as String;
      expect(targetId, startsWith('target_'));
      final listedTargets = await _callOperation(
        pool,
        spec,
        kind: 'target.list',
        idempotencyKey: 'target-list-workerA',
      );
      final targetResources =
          (listedTargets.output!['targets']! as List<Object?>)
              .cast<Map<Object?, Object?>>();
      expect(targetResources, hasLength(1));
      expect(targetResources.single['targetId'], targetId);
      expect(targetResources.single['appId'], 'com.example.cockpit');
      expect(targetResources.single, isNot(contains('state')));
      final readTarget = await _callOperation(
        pool,
        spec,
        kind: 'target.get',
        idempotencyKey: 'target-get-workerA',
        input: <String, Object?>{'targetId': targetId},
      );
      expect(
        (readTarget.output!['target']! as Map<Object?, Object?>)['targetId'],
        targetId,
      );
      final nativeWithEntrypoint = await _callOperation(
        pool,
        spec,
        kind: 'worker.target.register',
        idempotencyKey: 'target-register-native-entrypoint',
        input: <String, Object?>{
          'platform': 'macos',
          'deviceId': 'deviceNative',
          'entrypointDocumentId': mainDocument['documentId'],
          'targetKind': 'nativeApp',
          'environment': 'test',
          'appId': 'com.example.native',
        },
      );
      expect(nativeWithEntrypoint.outcome, CockpitOperationOutcome.succeeded);
      final nativeWithEntrypointId =
          nativeWithEntrypoint.output!['targetId']! as String;
      for (final invalidRegistration in <(String, Map<String, Object?>)>[
        (
          'missing',
          <String, Object?>{
            'platform': 'android',
            'deviceId': 'deviceMissingAppId',
            'targetKind': 'nativeApp',
          },
        ),
        (
          'blank',
          <String, Object?>{
            'platform': 'android',
            'deviceId': 'deviceBlankAppId',
            'targetKind': 'nativeApp',
            'appId': '   ',
          },
        ),
      ]) {
        final rejected = await _callOperation(
          pool,
          spec,
          kind: 'worker.target.register',
          idempotencyKey: 'target-register-${invalidRegistration.$1}-app-id',
          input: invalidRegistration.$2,
        );
        expect(rejected.outcome, CockpitOperationOutcome.failed);
        expect(
          rejected.failure!.primary.code,
          invalidRegistration.$1 == 'missing'
              ? 'targetAppIdRequired'
              : 'targetAppIdInvalid',
        );
      }

      await pool.shutdownWorkspace(spec.key, grace: const Duration(seconds: 5));
      final replayedRegistration = await _callOperation(
        pool,
        spec,
        kind: 'worker.target.register',
        idempotencyKey: 'target-register-workerA',
        input: <String, Object?>{
          'platform': 'macos',
          'deviceId': 'deviceA',
          'entrypointDocumentId': mainDocument['documentId'],
          'environment': 'development',
          'appId': 'com.example.cockpit',
        },
      );
      expect(replayedRegistration.outcome, CockpitOperationOutcome.succeeded);
      expect(replayedRegistration.output!['targetId'], targetId);
      await expectLater(
        _callOperation(
          pool,
          spec,
          kind: 'worker.target.register',
          idempotencyKey: 'target-register-workerA',
          input: <String, Object?>{
            'platform': 'macos',
            'deviceId': 'deviceB',
            'entrypointDocumentId': mainDocument['documentId'],
            'environment': 'development',
          },
        ),
        throwsA(
          isA<CockpitJsonRpcRemoteException>().having(
            (error) => error.error.workerCode,
            'workerCode',
            'idempotencyConflict',
          ),
        ),
      );

      await pool.shutdownWorkspace(spec.key, grace: const Duration(seconds: 5));
      final operationJournal = CockpitFileWorkerOperationJournal(
        path: p.join(spec.stateRoot, 'operations'),
        permissionHardener: Platform.isWindows
            ? const CockpitWindowsInheritedAclPermissionHardener()
            : const CockpitPosixPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      );
      final preparedInvocation = _targetRegistrationInvocation(
        idempotencyKey: 'target-register-prepared',
        deviceId: 'devicePrepared',
      );
      final preparedAdmission = await operationJournal.admit(
        invocation: preparedInvocation,
        submittedAt: DateTime.now().toUtc(),
      );
      final resumedRegistration = await _callOperation(
        pool,
        spec,
        kind: preparedInvocation.kind,
        idempotencyKey: preparedInvocation.idempotencyKey!.value,
        input: preparedInvocation.input,
      );
      expect(resumedRegistration.outcome, CockpitOperationOutcome.succeeded);
      expect(resumedRegistration.operationId, preparedAdmission.operationId);

      await pool.shutdownWorkspace(spec.key, grace: const Duration(seconds: 5));
      final runningInvocation = _targetRegistrationInvocation(
        idempotencyKey: 'target-register-running',
        deviceId: 'deviceRunning',
      );
      final runningAdmission = await operationJournal.admit(
        invocation: runningInvocation,
        submittedAt: DateTime.now().toUtc(),
      );
      await operationJournal.markRunning(
        idempotencyKey: runningInvocation.idempotencyKey!.value,
        startedAt: DateTime.now().toUtc(),
      );
      final interruptedRegistration = await _callOperation(
        pool,
        spec,
        kind: runningInvocation.kind,
        idempotencyKey: runningInvocation.idempotencyKey!.value,
        input: runningInvocation.input,
      );
      expect(interruptedRegistration.operationId, runningAdmission.operationId);
      expect(interruptedRegistration.outcome, CockpitOperationOutcome.failed);
      expect(
        interruptedRegistration.failure!.primary.code,
        'operationInterrupted',
      );

      authority.resetObservations();
      await indexedCase.writeAsString('invalidated indexed case\n');
      final staleCase = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-stale-document',
        input: CockpitRunSubmission(
          workspaceId: 'workspaceA',
          source: CockpitIndexedCaseSource(
            reference: CockpitIndexedCaseReference(
              documentId: caseDocument['documentId']! as String,
              caseId: caseDocument['authoredId']! as String,
              documentSha256: caseDocument['sourceSha256']! as String,
            ),
          ),
          targetId: targetId,
          idempotencyKey: CockpitIdempotencyKey('case-run-stale-document'),
        ).toJson(),
      );
      expect(staleCase.outcome, CockpitOperationOutcome.failed);
      expect(authority.acquiredKinds, isEmpty);
      await indexedCase.writeAsString('''
schemaVersion: cockpit.test/v2
kind: case
id: indexedCase
target: {platform: flutter, targetKind: flutterApp, plane: semantic}
steps:
  - stepId: goBack
    action: {type: back}
''');

      authority.resetObservations();
      await mainEntrypoint.rename('${mainEntrypoint.path}.replaced');
      final outsideEntrypoint = await File(
        p.join(temporary.path, 'outside-main.dart'),
      ).writeAsString('void main() => print(1);\n');
      var linkedEntrypoint = true;
      try {
        await Link(mainEntrypoint.path).create(outsideEntrypoint.path);
      } on FileSystemException {
        linkedEntrypoint = false;
        await File(
          mainEntrypoint.path,
        ).writeAsString('void main() => print(1);\n');
      }
      final readableStaleTarget = await _callOperation(
        pool,
        spec,
        kind: 'target.get',
        idempotencyKey: 'target-get-stale-entrypoint',
        input: <String, Object?>{'targetId': targetId},
      );
      expect(readableStaleTarget.outcome, CockpitOperationOutcome.succeeded);
      final inspectNativeWithStaleEntrypoint = await _callOperation(
        pool,
        spec,
        kind: 'target.inspect',
        idempotencyKey: 'target-inspect-native-stale-entrypoint',
        input: <String, Object?>{'targetId': nativeWithEntrypointId},
      );
      expect(
        inspectNativeWithStaleEntrypoint.outcome,
        CockpitOperationOutcome.succeeded,
        reason: '${inspectNativeWithStaleEntrypoint.failure?.toJson()}',
      );
      authority.resetObservations();
      final staleTarget = await _callOperation(
        pool,
        spec,
        kind: 'target.launch',
        idempotencyKey: 'target-launch-stale-entrypoint',
        input: <String, Object?>{'targetId': targetId},
      );
      expect(staleTarget.outcome, CockpitOperationOutcome.failed);
      expect(staleTarget.failure!.primary.code, 'targetEntrypointStale');
      expect(authority.acquiredKinds, isEmpty);
      if (linkedEntrypoint) {
        expect(
          await FileSystemEntity.type(mainEntrypoint.path, followLinks: false),
          FileSystemEntityType.link,
        );
      }
      await File(mainEntrypoint.path).delete();
      await File('${mainEntrypoint.path}.replaced').rename(mainEntrypoint.path);

      final printEnvironment = await _callOperation(
        pool,
        spec,
        kind: 'shell.run',
        idempotencyKey: 'shell-print-environment-secret',
        input: <String, Object?>{
          'command': Platform.isWindows
              ? <String>['cmd.exe', '/c', 'echo', '%API_TOKEN%']
              : <String>['printenv', 'API_TOKEN'],
        },
      );
      expect(printEnvironment.outcome, CockpitOperationOutcome.succeeded);
      expect(printEnvironment.output!['stdout'], isNot(environmentSecret));
      expect(
        printEnvironment.toJson().toString(),
        isNot(contains(environmentSecret)),
      );

      const plaintextSecret = 'must-never-cross-worker-rpc';
      authority.resetObservations();
      final rejectedSecretInput = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-secret-input',
        input: _submission(
          targetId,
          idempotencyKey: 'case-run-secret-input',
          inputs: const <String, Object?>{'apiToken': plaintextSecret},
        ).toJson(),
      );
      expect(rejectedSecretInput.outcome, CockpitOperationOutcome.failed);
      expect(authority.acquiredKinds, isEmpty);
      expect(
        await state
            .list(recursive: true)
            .where(
              (entity) =>
                  entity is File &&
                  p.basename(entity.path) == 'preparation.json',
            )
            .isEmpty,
        isTrue,
      );

      authority.resetObservations();
      final missingOuterFeature = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-nested-feature',
        input: _submission(
          targetId,
          idempotencyKey: 'case-run-nested-feature',
          requiredFeatures: const <String>['featureA'],
        ).toJson(),
      );
      expect(missingOuterFeature.outcome, CockpitOperationOutcome.failed);
      expect(
        missingOuterFeature.failure!.primary.code,
        'requiredFeatureMissing',
      );
      expect(authority.acquiredKinds, isEmpty);
      expect(
        await state
            .list(recursive: true)
            .where(
              (entity) =>
                  entity is File &&
                  p.basename(entity.path) == 'preparation.json',
            )
            .isEmpty,
        isTrue,
      );

      await pool.shutdownWorkspace(spec.key, grace: const Duration(seconds: 5));
      final permissionHardener = Platform.isWindows
          ? const CockpitWindowsInheritedAclPermissionHardener()
          : const CockpitPosixPermissionHardener();
      CockpitWorkerRuntimeRegistry openRuntimeRegistry() =>
          CockpitWorkerRuntimeRegistry(
            workspaceId: spec.key.workspaceId,
            workspaceRoot: spec.workspaceRoot,
            stateRoot: spec.stateRoot,
            stateStore: CockpitFileWorkerRuntimeStateStore(
              root: p.join(spec.stateRoot, 'runtime'),
              permissionHardener: permissionHardener,
              directorySyncer: const _NoopDirectorySyncer(),
            ),
            runOwnershipAuthority: CockpitWorkerCaseRunStore.file(
              workspaceId: spec.key.workspaceId,
              path: p.join(spec.stateRoot, 'case_runs'),
              permissionHardener: permissionHardener,
              directorySyncer: const _NoopDirectorySyncer(),
            ),
          );
      final liveTargetId = resumedRegistration.output!['targetId']! as String;
      final liveRegistry = openRuntimeRegistry();
      final liveApp = await liveRegistry.recordApp(
        targetId: liveTargetId,
        handle: CockpitAppHandle.fromRemoteSession(
          CockpitRemoteSessionHandle(
            platform: 'macos',
            deviceId: 'devicePrepared',
            projectDir: spec.workspaceRoot,
            target: 'macos',
            appId: 'fake-app',
            platformAppIdKnown: true,
            host: '127.0.0.1',
            hostPort: remoteSession.port,
            devicePort: remoteSession.port,
            baseUrl: remoteSession.baseUri.toString(),
            launchedAt: DateTime.now().toUtc(),
          ),
        ),
      );
      final liveSessionId = await liveRegistry.sessionIdForApp(liveApp.appId);

      authority.resetObservations();
      final activeRead = await _callOperation(
        pool,
        spec,
        kind: 'session.remote.status',
        idempotencyKey: 'session-status-workerA',
        input: <String, Object?>{'sessionId': liveSessionId},
      );
      expect(activeRead.outcome, CockpitOperationOutcome.succeeded);
      expect(authority.acquiredKinds, <CockpitLeaseResourceKind>[
        CockpitLeaseResourceKind.device,
        CockpitLeaseResourceKind.session,
      ]);
      expect(authority.releaseCount, 2);

      authority.resetObservations();
      final successfulSubmission = _submission(liveTargetId);
      expect(
        successfulSubmission.toJson().toString(),
        isNot(contains(environmentSecret)),
      );
      final caseResult = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-workerA',
        input: successfulSubmission.toJson(),
      );
      final successfulCaseRecord = await _readCaseRecord(
        state,
        'case-run-workerA',
      );
      expect(
        caseResult.outcome,
        CockpitOperationOutcome.succeeded,
        reason: <String, Object?>{
          'operation': caseResult.toJson(),
          'caseRecord': successfulCaseRecord,
          'acquiredKinds': authority.acquiredKinds
              .map((kind) => kind.name)
              .toList(),
          'releaseCount': authority.releaseCount,
        }.toString(),
      );
      expect(
        authority.acquiredKinds,
        unorderedEquals(<CockpitLeaseResourceKind>[
          CockpitLeaseResourceKind.device,
          CockpitLeaseResourceKind.session,
          CockpitLeaseResourceKind.capture,
          CockpitLeaseResourceKind.recording,
        ]),
      );
      expect(authority.releaseCount, 4);
      expect(remoteSession.commands, hasLength(1));
      expect(
        remoteSession.commands.single.commandType,
        CockpitCommandType.enterText,
      );
      expect(
        remoteSession.commands.single.parameters['text'],
        environmentSecret,
      );
      expect(
        caseResult.toJson().toString(),
        isNot(contains(environmentSecret)),
      );
      final successfulOutput = caseResult.output!;
      final successfulRunId = successfulOutput['runId']! as String;
      final successfulResult = Map<String, Object?>.from(
        successfulOutput['result']! as Map<Object?, Object?>,
      );
      expect(successfulResult['outcome'], CockpitTestOutcome.passed.name);
      expect(successfulResult.containsKey('bundlePath'), isFalse);
      final bundleReference = Map<String, Object?>.from(
        successfulResult['artifactRef']! as Map<Object?, Object?>,
      );
      expect(bundleReference['kind'], 'caseAttemptBundle');
      expect(caseResult.toJson().toString(), isNot(contains('retainedPath')));
      final bundleBinding = await openRuntimeRegistry().requireArtifact(
        bundleReference['artifactId']! as String,
      );
      expect(bundleBinding.ownerId, successfulRunId);
      expect(
        bundleBinding.retainedPath,
        startsWith(
          p.join(spec.stateRoot, 'runs', successfulRunId, 'artifacts'),
        ),
      );
      final retainedArtifact = File(
        p.join(bundleBinding.retainedPath, 'screenshots', 'dispatch.png'),
      );
      expect(await retainedArtifact.readAsBytes(), <int>[1, 2, 3, 4]);
      final sourceArtifact = await _singleFileNamed(
        Directory(p.join(spec.stateRoot, 'runs', successfulRunId, 'cases')),
        'dispatch.png',
      );
      await sourceArtifact.writeAsBytes(<int>[9, 9, 9], flush: true);
      expect(await sourceArtifact.readAsBytes(), <int>[9, 9, 9]);
      expect(await retainedArtifact.readAsBytes(), <int>[1, 2, 3, 4]);

      final preparations = await state
          .list(recursive: true)
          .where(
            (entity) =>
                entity is File && p.basename(entity.path) == 'preparation.json',
          )
          .cast<File>()
          .toList();
      expect(preparations, hasLength(1));
      final preparation =
          jsonDecode(await preparations.single.readAsString())
              as Map<String, Object?>;
      expect(preparation['secretReferences'], <String, Object?>{
        'apiToken': 'env:API_TOKEN',
      });
      expect(preparation['resolvedInputs'], <String, Object?>{
        'constantValue': 'constant',
        'defaultValue': 'default',
        'runtimeValue': 'runtime',
      });
      expect(preparation.toString(), isNot(contains(plaintextSecret)));
      expect(preparation.toString(), isNot(contains(environmentSecret)));
      await _expectTreeExcludes(state, environmentSecret);

      authority.resetObservations();
      final suiteCommandsBefore = remoteSession.commands.length;
      final suiteSubmission = CockpitRunSubmission(
        workspaceId: spec.key.workspaceId,
        source: CockpitIndexedSuiteSource(
          reference: CockpitIndexedSuiteReference(
            documentId: suiteDocument['documentId']! as String,
            suiteId: suiteDocument['authoredId']! as String,
            documentSha256: suiteDocument['sourceSha256']! as String,
          ),
        ),
        idempotencyKey: CockpitIdempotencyKey('suite-run-workerA'),
      );
      final suiteResult = await _callOperation(
        pool,
        spec,
        kind: 'suite.run',
        idempotencyKey: 'suite-run-workerA',
        input: suiteSubmission.toJson(),
      );
      expect(
        suiteResult.outcome,
        CockpitOperationOutcome.succeeded,
        reason: <String, Object?>{
          'operation': suiteResult.toJson(),
          'acquiredKinds': authority.acquiredKinds
              .map((kind) => kind.name)
              .toList(),
          'releaseCount': authority.releaseCount,
        }.toString(),
      );
      final suiteOutput = suiteResult.output!;
      final suiteRunId = suiteOutput['runId']! as String;
      final report = CockpitTestSuiteReport.fromJson(suiteOutput['report']);
      expect(report.runId, suiteRunId);
      expect(report.suiteId, 'regressionSuite');
      expect(
        report.outcome,
        CockpitRunOutcome.passed,
        reason: <String, Object?>{
          'report': report.toJson(),
          'commands': remoteSession.commands
              .skip(suiteCommandsBefore)
              .map((command) => command.toJson())
              .toList(),
          'acquiredKinds': authority.acquiredKinds
              .map((kind) => kind.name)
              .toList(),
          'releaseCount': authority.releaseCount,
        }.toString(),
      );
      expect(report.counts.total, 2);
      expect(report.counts.passed, 2);
      expect(
        remoteSession.commands
            .skip(suiteCommandsBefore)
            .map((command) => command.parameters['text']),
        <Object?>['first', 'second'],
        reason: <String, Object?>{
          'report': report.toJson(),
          'acquiredKinds': authority.acquiredKinds
              .map((kind) => kind.name)
              .toList(),
        }.toString(),
      );
      expect(
        authority.acquiredKinds.where(
          (kind) => kind == CockpitLeaseResourceKind.run,
        ),
        hasLength(1),
      );
      expect(
        authority.acquiredKinds.where(
          (kind) => kind == CockpitLeaseResourceKind.device,
        ),
        hasLength(2),
      );
      expect(authority.releaseCount, authority.acquiredKinds.length);

      expect(report.cases.map((item) => item.caseId), <String>[
        'suiteCaseOne',
        'suiteCaseTwo',
      ]);
      final suiteEvents = await _readRunEvents(state, suiteRunId);
      expect(
        suiteEvents
            .where((event) => event.kind == 'attempt.completed')
            .map((event) => event.caseId),
        <String>['suiteCaseOne', 'suiteCaseTwo'],
      );
      expect(
        suiteEvents.where((event) => event.kind == 'run.completed'),
        hasLength(1),
      );
      expect(suiteEvents.map((event) => event.runId).toSet(), <String>{
        suiteRunId,
      });

      final reportArtifacts = (suiteOutput['reportArtifacts']! as List<Object?>)
          .map(CockpitArtifactResource.fromJson)
          .toList(growable: false);
      expect(reportArtifacts.map((artifact) => artifact.kind).toSet(), <String>{
        'report.json',
        'report.junit',
        'report.html',
        'report.aiSummary',
      });
      expect(
        reportArtifacts.every(
          (artifact) =>
              artifact.runId == suiteRunId && artifact.attemptId == null,
        ),
        isTrue,
      );
      final reportProjection = CockpitSupervisorRunProjection(
        workspaceId: spec.key.workspaceId,
        stateRoot: spec.stateRoot,
        permissionHardener: permissionHardener,
        directorySyncer: const _NoopDirectorySyncer(),
        retentionIndex: const _RunRetentionIndex(),
      );
      final retainedReportFiles = await Future.wait(
        reportArtifacts.map(
          (artifact) => reportProjection.requireArtifactFile(
            suiteRunId,
            artifact.artifactId,
          ),
        ),
      );
      expect(
        retainedReportFiles.map((resolved) => p.basename(resolved.file.path)),
        unorderedEquals(const <String>[
          'report.json',
          'junit.xml',
          'report.html',
          'ai-summary.md',
        ]),
      );
      expect(
        retainedReportFiles.every(
          (resolved) => p.isWithin(
            p.join(spec.stateRoot, 'runs', suiteRunId, 'artifacts'),
            resolved.file.path,
          ),
        ),
        isTrue,
      );

      final suiteOperationId = suiteResult.operationId;
      await pool.shutdownWorkspace(spec.key, grace: const Duration(seconds: 5));
      authority.resetObservations();
      final commandsBeforeSuiteReplay = remoteSession.commands.length;
      final replayedSuite = await _callOperation(
        pool,
        spec,
        kind: 'suite.run',
        idempotencyKey: 'suite-run-workerA',
        input: suiteSubmission.toJson(),
      );
      expect(replayedSuite.outcome, CockpitOperationOutcome.succeeded);
      expect(replayedSuite.operationId, suiteOperationId);
      expect(replayedSuite.output!['runId'], suiteRunId);
      expect(remoteSession.commands, hasLength(commandsBeforeSuiteReplay));
      expect(authority.acquiredKinds, isEmpty);
      expect(authority.releaseCount, 0);

      remoteSession.artifactBytes = utf8.encode(environmentSecret);
      final rejectedCase = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-secret-artifact',
        input: _submission(
          liveTargetId,
          idempotencyKey: 'case-run-secret-artifact',
        ).toJson(),
      );
      expect(rejectedCase.outcome, CockpitOperationOutcome.succeeded);
      final rejectedOutput = rejectedCase.output!;
      final rejectedRunId = rejectedOutput['runId']! as String;
      final rejectedAttemptId = rejectedOutput['attemptId']! as String;
      final rejectedResult = Map<String, Object?>.from(
        rejectedOutput['result']! as Map<Object?, Object?>,
      );
      expect(rejectedResult['outcome'], CockpitTestOutcome.failed.name);
      expect(rejectedResult.containsKey('artifactRef'), isFalse);
      final primaryError = Map<String, Object?>.from(
        rejectedResult['primaryError']! as Map<Object?, Object?>,
      );
      expect(primaryError['code'], 'bundlePublicationFailed');
      expect(
        (primaryError['details']! as Map<Object?, Object?>)['reason'],
        'plaintextSecretRejected',
      );
      final rejectedBundlePath = p.join(
        spec.stateRoot,
        'runs',
        rejectedRunId,
        'cases',
        rejectedAttemptId,
        'bundle',
      );
      expect(await Directory(rejectedBundlePath).exists(), isFalse);
      final rejectedBundleParent = Directory(p.dirname(rejectedBundlePath));
      expect(
        await rejectedBundleParent
            .list(followLinks: false)
            .where(
              (entity) =>
                  entity is Directory &&
                  p
                      .basename(entity.path)
                      .startsWith('.$rejectedAttemptId.staging-'),
            )
            .isEmpty,
        isTrue,
      );
      await _expectTreeExcludes(state, environmentSecret);
      expect(remoteSession.commands.last.parameters['text'], environmentSecret);
      remoteSession.commands.removeLast();
      remoteSession.artifactBytes = <int>[1, 2, 3, 4];

      authority.resetObservations();
      final commandsBeforeRunningCrash = remoteSession.commands.length;
      final runningBlock = remoteSession.blockNextCommand();
      final runningConnection = await pool.connectionFor(spec);
      final runningPid = runningConnection.processId;
      final runningCall = _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-crash-running',
        input: _submission(
          liveTargetId,
          idempotencyKey: 'case-run-crash-running',
        ).toJson(),
      );
      final runningCallFailure = expectLater(runningCall, throwsA(anything));
      final blockedCommand = await runningBlock.entered.future.timeout(
        const Duration(seconds: 10),
      );
      expect(blockedCommand.parameters['text'], environmentSecret);
      final runningCaseBeforeCrash = await _readCaseRecord(
        state,
        'case-run-crash-running',
      );
      final runningOperationBeforeCrash = await _readOperationRecord(
        state,
        'case-run-crash-running',
      );
      final originalRunningRunId = runningCaseBeforeCrash['runId']! as String;
      final originalRunningAttemptId =
          ((runningCaseBeforeCrash['attempts']! as List<Object?>).single!
                  as Map<String, Object?>)['attemptId']!
              as String;
      expect(
        ((runningCaseBeforeCrash['attempts']! as List<Object?>).single!
            as Map<String, Object?>)['status'],
        'running',
      );
      expect(runningOperationBeforeCrash['state'], 'running');
      await runningConnection.terminate(force: true);
      runningBlock.release();
      await runningCallFailure;
      await _waitForWorkerRestart(pool, spec, previousPid: runningPid);
      final recoveredRunning = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-crash-running',
        input: _submission(
          liveTargetId,
          idempotencyKey: 'case-run-crash-running',
        ).toJson(),
      );
      expect(recoveredRunning.outcome, CockpitOperationOutcome.succeeded);
      expect(
        recoveredRunning.operationId,
        runningOperationBeforeCrash['operationId'],
      );
      expect(recoveredRunning.output!['runId'], originalRunningRunId);
      expect(
        recoveredRunning.output!['attemptId'],
        isNot(originalRunningAttemptId),
      );
      final runningCaseAfterRecovery = await _readCaseRecord(
        state,
        'case-run-crash-running',
      );
      final recoveredAttempts =
          runningCaseAfterRecovery['attempts']! as List<Object?>;
      expect(recoveredAttempts, hasLength(2));
      expect(
        recoveredAttempts.map(
          (value) => (value! as Map<String, Object?>)['status'],
        ),
        <String>['interrupted', 'completed'],
      );
      expect(remoteSession.commands, hasLength(commandsBeforeRunningCrash + 2));
      expect(authority.acquiredKinds, hasLength(8));
      expect(authority.releaseCount, 4);

      for (final phase in CockpitWorkerCaseCompletionPhase.values) {
        authority.resetObservations();
        final key = 'case-run-crash-${phase.name}';
        await completionCrashControl.writeAsString(
          jsonEncode(<String, Object?>{
            'phase': phase.name,
            'idempotencyKey': key,
            'consumed': false,
          }),
          flush: true,
        );
        final connection = await pool.connectionFor(spec);
        final processId = connection.processId;
        final commandsBeforeRun = remoteSession.commands.length;
        await expectLater(
          _callOperation(
            pool,
            spec,
            kind: 'case.run',
            idempotencyKey: key,
            input: _submission(liveTargetId, idempotencyKey: key).toJson(),
          ),
          throwsA(anything),
        );
        final control =
            jsonDecode(await completionCrashControl.readAsString())
                as Map<String, Object?>;
        expect(control['consumed'], isTrue, reason: phase.name);
        final caseBeforeReplay = await _readCaseRecord(state, key);
        final operationBeforeReplay = await _readOperationRecord(state, key);
        final attemptsBeforeReplay =
            caseBeforeReplay['attempts']! as List<Object?>;
        expect(attemptsBeforeReplay, hasLength(1), reason: phase.name);
        final attemptBeforeReplay =
            attemptsBeforeReplay.single! as Map<String, Object?>;
        expect(operationBeforeReplay['state'], 'running', reason: phase.name);
        expect(
          remoteSession.commands,
          hasLength(commandsBeforeRun + 1),
          reason: phase.name,
        );
        if (phase == CockpitWorkerCaseCompletionPhase.completionCommitted) {
          expect(attemptBeforeReplay['status'], 'completed');
          expect(attemptBeforeReplay, isNot(contains('completionIntent')));
        } else {
          expect(attemptBeforeReplay['status'], 'running');
          expect(attemptBeforeReplay, contains('completionIntent'));
        }
        final eventsBeforeReplay = await _readRunEvents(
          state,
          caseBeforeReplay['runId']! as String,
        );
        expect(
          eventsBeforeReplay.any((event) => event.kind == 'run.completed'),
          phase != CockpitWorkerCaseCompletionPhase.intentPersisted,
          reason: phase.name,
        );

        await _waitForWorkerRestart(pool, spec, previousPid: processId);
        final replay = await _callOperation(
          pool,
          spec,
          kind: 'case.run',
          idempotencyKey: key,
          input: _submission(liveTargetId, idempotencyKey: key).toJson(),
        );
        expect(replay.outcome, CockpitOperationOutcome.succeeded);
        expect(
          replay.operationId,
          operationBeforeReplay['operationId'],
          reason: phase.name,
        );
        expect(replay.output!['runId'], caseBeforeReplay['runId']);
        expect(
          replay.output!['attemptId'],
          attemptBeforeReplay['attemptId'],
          reason: phase.name,
        );
        expect(
          remoteSession.commands,
          hasLength(commandsBeforeRun + 1),
          reason: 'runner executed more than once at ${phase.name}',
        );
        final completedCase = await _readCaseRecord(state, key);
        final completedAttempt =
            (completedCase['attempts']! as List<Object?>).single!
                as Map<String, Object?>;
        expect(completedAttempt['status'], 'completed', reason: phase.name);
        expect(completedAttempt, isNot(contains('completionIntent')));
        expect(completedAttempt, contains('completionReceipt'));
      }
      await _expectTreeExcludes(state, environmentSecret);

      final commandsBeforeDeniedRun = remoteSession.commands.length;
      final deniedFinancial = await _callOperation(
        pool,
        spec,
        kind: 'case.run',
        idempotencyKey: 'case-run-financial-denied',
        input: _submission(
          liveTargetId,
          idempotencyKey: 'case-run-financial-denied',
          safetyEffects: const <CockpitTestSafetyEffect>{
            CockpitTestSafetyEffect.credentialSensitive,
            CockpitTestSafetyEffect.financial,
          },
        ).toJson(),
      );
      expect(deniedFinancial.outcome, CockpitOperationOutcome.succeeded);
      final deniedFinancialResult = Map<String, Object?>.from(
        deniedFinancial.output!['result']! as Map<Object?, Object?>,
      );
      expect(deniedFinancialResult['outcome'], CockpitTestOutcome.blocked.name);
      expect(
        (deniedFinancialResult['primaryError']!
            as Map<Object?, Object?>)['code'],
        CockpitTestErrorCode.safetyDenied.name,
      );
      expect(remoteSession.commands, hasLength(commandsBeforeDeniedRun));

      await pool.shutdownWorkspace(spec.key, grace: const Duration(seconds: 5));
      final runtimeState = await CockpitFileWorkerRuntimeStateStore(
        root: p.join(spec.stateRoot, 'runtime'),
        permissionHardener: permissionHardener,
        directorySyncer: const _NoopDirectorySyncer(),
      ).read();
      final persisted = jsonEncode(runtimeState);
      expect(persisted, contains('main.dart'));
      expect(persisted, isNot(contains(spec.workspaceRoot)));
      expect(persisted, isNot(contains('secret')));
      expect(runtimeState['targets'], hasLength(3));
      expect(pool.activeKeys, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

DateTime _deadline() => DateTime.now().toUtc().add(const Duration(seconds: 20));

CockpitOperationInvocation _targetRegistrationInvocation({
  required String idempotencyKey,
  required String deviceId,
}) => CockpitOperationInvocation(
  kind: 'worker.target.register',
  workspaceId: 'workspaceA',
  idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
  deadline: _deadline(),
  input: <String, Object?>{
    'platform': 'macos',
    'deviceId': deviceId,
    'environment': 'development',
  },
);

CockpitRunSubmission _submission(
  String targetId, {
  String idempotencyKey = 'case-run-workerA',
  Map<String, Object?> inputs = const <String, Object?>{
    'runtimeValue': 'runtime',
  },
  Iterable<String> requiredFeatures = const <String>[],
  Iterable<CockpitTestSafetyEffect> safetyEffects =
      const <CockpitTestSafetyEffect>{
        CockpitTestSafetyEffect.credentialSensitive,
      },
}) => CockpitRunSubmission(
  workspaceId: 'workspaceA',
  source: CockpitInlineCaseSource(
    testCase: CockpitTestCase(
      id: 'caseA',
      target: CockpitTestTargetRequirements(
        platform: 'flutter',
        targetKind: 'flutterApp',
        plane: CockpitTestPlane.semantic,
      ),
      variables: <String, CockpitTestVariableDeclaration>{
        'constantValue': CockpitTestVariableDeclaration(
          source: CockpitTestVariableSource.constant,
          valueType: CockpitTestValueType.string,
          value: 'constant',
        ),
        'defaultValue': CockpitTestVariableDeclaration(
          source: CockpitTestVariableSource.input,
          valueType: CockpitTestValueType.string,
          defaultValue: 'default',
          required: false,
        ),
        'runtimeValue': CockpitTestVariableDeclaration(
          source: CockpitTestVariableSource.input,
          valueType: CockpitTestValueType.string,
        ),
        'apiToken': CockpitTestVariableDeclaration(
          source: CockpitTestVariableSource.secret,
          valueType: CockpitTestValueType.string,
          secretReference: 'env:API_TOKEN',
        ),
      },
      steps: <CockpitTestStepTemplate>[
        CockpitTestStepTemplate(
          stepId: 'dispatchSecret',
          safety: CockpitTestSafetyDeclaration(
            effects: safetyEffects,
            reason: 'Authenticate the development test session.',
          ),
          operation: CockpitTestActionOperationTemplate(
            CockpitTestActionTemplate(
              kind: CockpitTestActionKind.enterText,
              values: <CockpitTestActionField, CockpitTestTemplateValue>{
                CockpitTestActionField.text: CockpitTestTemplateValue.variable(
                  'apiToken',
                  expectedType: CockpitTestValueType.string,
                ),
              },
            ),
          ),
        ),
      ],
    ),
    sourceSha256: List<String>.filled(64, 'a').join(),
  ),
  targetId: targetId,
  inputs: inputs,
  requiredFeatures: requiredFeatures,
  idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
);

Future<CockpitOperationResult> _callOperation(
  CockpitWorkerPool pool,
  CockpitWorkspaceWorkerSpec spec, {
  required String kind,
  required String idempotencyKey,
  Map<String, Object?> input = const <String, Object?>{},
}) async {
  final deadline = _deadline();
  return CockpitWorkerOperationResult.fromJson(
    await pool.call(
      spec,
      method: 'operation',
      idempotencyKey: idempotencyKey,
      deadline: deadline,
      params: <String, Object?>{
        'invocation': CockpitOperationInvocation(
          kind: kind,
          input: input,
          workspaceId: spec.key.workspaceId,
          idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
          deadline: deadline,
        ).toJson(),
      },
    ),
  ).result;
}

Future<File> _singleFileNamed(Directory root, String basename) async {
  final matches = await root
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File && p.basename(entity.path) == basename)
      .cast<File>()
      .toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected one $basename beneath ${root.path}, found ${matches.length}.',
    );
  }
  return matches.single;
}

Future<Map<String, Object?>> _readCaseRecord(
  Directory state,
  String idempotencyKey,
) async {
  final records = await Directory(p.join(state.path, 'case_runs'))
      .list(recursive: true, followLinks: false)
      .where(
        (entity) => entity is File && p.basename(entity.path) == 'record.json',
      )
      .cast<File>()
      .toList();
  for (final file in records) {
    final record = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map<Object?, Object?>,
    );
    if (record['idempotencyKey'] == idempotencyKey) return record;
  }
  throw StateError('Case record $idempotencyKey was not found.');
}

Future<List<CockpitRunEvent>> _readRunEvents(
  Directory state,
  String runId,
) async {
  final file = File(p.join(state.path, 'runs', runId, 'events.ndjson'));
  return const LineSplitter()
      .convert(await file.readAsString())
      .where((line) => line.isNotEmpty)
      .map((line) => CockpitRunEvent.fromJson(jsonDecode(line)))
      .toList(growable: false);
}

Future<Map<String, Object?>> _readOperationRecord(
  Directory state,
  String idempotencyKey,
) async {
  final records = await Directory(p.join(state.path, 'operations'))
      .list(recursive: true, followLinks: false)
      .where(
        (entity) => entity is File && p.basename(entity.path) == 'record.json',
      )
      .cast<File>()
      .toList();
  for (final file in records) {
    final document = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map<Object?, Object?>,
    );
    final value = document['record'];
    if (value is! Map<Object?, Object?>) continue;
    final record = Map<String, Object?>.from(value);
    if (record['idempotencyKey'] == idempotencyKey) return record;
  }
  throw StateError('Operation record $idempotencyKey was not found.');
}

Future<CockpitWorkspaceWorkerConnection> _waitForWorkerRestart(
  CockpitWorkerPool pool,
  CockpitWorkspaceWorkerSpec spec, {
  required int previousPid,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final connection = await pool
          .connectionFor(spec)
          .timeout(const Duration(seconds: 1));
      if (!connection.isClosed && connection.processId != previousPid) {
        return connection;
      }
    } on Object {
      // The slot exposes a failed generation until its restart is scheduled.
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('Worker process $previousPid did not restart.');
}

Future<void> _expectTreeExcludes(Directory root, String value) async {
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final text = utf8.decode(await entity.readAsBytes(), allowMalformed: true);
    expect(text, isNot(contains(value)), reason: entity.path);
  }
}

final class _RemoteCommandBlock {
  final Completer<CockpitCommand> entered = Completer<CockpitCommand>();
  final Completer<void> _released = Completer<void>();

  Future<void> get whenReleased => _released.future;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

final class _RunRetentionIndex implements CockpitSupervisorRunRetentionIndex {
  const _RunRetentionIndex();

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

final class _RemoteSessionServer {
  _RemoteSessionServer._(this._server);

  final HttpServer _server;
  final List<CockpitCommand> commands = <CockpitCommand>[];
  List<int> artifactBytes = <int>[1, 2, 3, 4];
  _RemoteCommandBlock? _nextCommandBlock;

  int get port => _server.port;
  Uri get baseUri => Uri(scheme: 'http', host: '127.0.0.1', port: port);

  static Future<_RemoteSessionServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final result = _RemoteSessionServer._(server);
    server.listen(result._handle);
    return result;
  }

  _RemoteCommandBlock blockNextCommand() {
    if (_nextCommandBlock != null) {
      throw StateError('A remote command is already blocked.');
    }
    return _nextCommandBlock = _RemoteCommandBlock();
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('GET', '/ping'):
        request.response.write(jsonEncode(const <String, Object?>{'ok': true}));
      case ('GET', '/ready'):
        request.response.write(
          jsonEncode(const <String, Object?>{
            'ok': true,
            'ready': true,
            'supportsInAppControl': true,
          }),
        );
      case ('GET', '/health'):
        request.response.write(jsonEncode(_remoteStatus().toJson()));
      case ('POST', '/commands/execute'):
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        final command = CockpitCommand.fromJson(
          Map<String, Object?>.from(body as Map<Object?, Object?>),
        );
        commands.add(command);
        final block = _nextCommandBlock;
        if (block != null) {
          _nextCommandBlock = null;
          block.entered.complete(command);
          await block.whenReleased;
        }
        request.response.write(
          jsonEncode(
            CockpitRemoteCommandResponse(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 4,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/dispatch.png',
                  ),
                ],
              ),
              artifactPayloads: <CockpitRemoteArtifactPayload>[
                CockpitRemoteArtifactPayload(
                  artifact: const CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/dispatch.png',
                  ),
                  bytes: artifactBytes,
                ),
              ],
            ).toJson(),
          ),
        );
      default:
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(
          jsonEncode(const <String, Object?>{'error': 'notFound'}),
        );
    }
    await request.response.close();
  }
}

CockpitRemoteSessionStatus _remoteStatus() => CockpitRemoteSessionStatus(
  sessionId: 'remote-session-1',
  platform: 'macos',
  transportType: 'remoteHttp',
  currentRouteName: '/test',
  capabilities: CockpitCapabilities(
    platform: 'macos',
    transportType: 'remoteHttp',
    supportsInAppControl: true,
    supportsFlutterViewCapture: true,
    supportsNativeScreenCapture: true,
    supportsHostAutomation: false,
    supportedCommands: <CockpitCommandType>[CockpitCommandType.enterText],
  ),
  recordingCapabilities: CockpitRecordingCapabilities(
    supportsNativeRecording: true,
  ),
  snapshot: CockpitSnapshot(routeName: '/test'),
);

final class _GrantingAuthority
    implements CockpitSupervisorWorkerResourceAuthority {
  var _grantSequence = 0;
  var releaseCount = 0;
  Future<void> Function()? onAcquire;
  Future<void> Function()? onRelease;
  final List<CockpitLeaseResourceKind> acquiredKinds =
      <CockpitLeaseResourceKind>[];

  void resetObservations() {
    acquiredKinds.clear();
    releaseCount = 0;
    onAcquire = null;
    onRelease = null;
  }

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation,
  ) async {
    final now = DateTime.now().toUtc();
    final output = switch (invocation.kind) {
      'resource.acquire' => await _acquire(invocation, now),
      'resource.heartbeat' => const <String, Object?>{'renewed': true},
      'resource.release' => await _release(),
      _ => throw StateError(
        'Unexpected resource operation ${invocation.kind}.',
      ),
    };
    return CockpitOperationResult(
      operationId: 'resource_operation_$_grantSequence',
      kind: invocation.kind,
      workspaceId: invocation.workspaceId,
      lifecycle: CockpitOperationLifecycle.completed,
      outcome: CockpitOperationOutcome.succeeded,
      submittedAt: now,
      startedAt: now,
      finishedAt: now,
      output: output,
    );
  }

  Future<Map<String, Object?>> _acquire(
    CockpitOperationInvocation invocation,
    DateTime now,
  ) async {
    await onAcquire?.call();
    final kind = CockpitLeaseResourceKind.values.byName(
      invocation.input['resourceKind']! as String,
    );
    acquiredKinds.add(kind);
    return <String, Object?>{
      'grant': CockpitWorkerResourceGrant(
        grantId: 'grant_${++_grantSequence}',
        leaseId: 'lease_$_grantSequence',
        workspaceId: invocation.workspaceId!,
        holderId: invocation.input['holderId']! as String,
        resourceKind: kind,
        resourceId: invocation.input['resourceId']! as String,
        expiresAt: now.add(const Duration(seconds: 30)),
      ).toJson(),
    };
  }

  Future<Map<String, Object?>> _release() async {
    releaseCount += 1;
    await onRelease?.call();
    return <String, Object?>{'released': true, 'releaseCount': releaseCount};
  }
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
