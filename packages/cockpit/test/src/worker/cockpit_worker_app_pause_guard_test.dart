import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/development/cockpit_app_pause_guard.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/worker/cockpit_worker_application_support.dart';
import 'package:cockpit/src/worker/cockpit_worker_artifact_retainer.dart';
import 'package:cockpit/src/worker/cockpit_worker_development_session_runtime.dart';
import 'package:cockpit/src/worker/cockpit_worker_document_index.dart';
import 'package:cockpit/src/worker/cockpit_worker_interactive_operations.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_process_manager.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Wire-level coverage for the pre-dispatch app-pause guard: operations that
/// dial the app's in-app control plane must fail fast with `appPaused` while
/// the development isolate is paused, without spending the request budget on
/// a dial that can never be answered.
void main() {
  test('command.run fails fast when the app is paused', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.pauseGuard!.failure = const CockpitApplicationServiceException(
      code: 'appPaused',
      message: 'The app isolate is paused (PauseInterrupted).',
    );

    await expectLater(
      harness.executeCommandRun(),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having((error) => error.code, 'code', 'appPaused'),
      ),
    );
    expect(harness.pauseGuard!.calls, 1);
    expect(harness.app.requestCount, 0);
  });

  test('grant-less read operations fail fast when the app is paused', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.pauseGuard!.failure = const CockpitApplicationServiceException(
      code: 'appPaused',
      message: 'The app isolate is paused (PauseBreakpoint).',
    );

    await expectLater(
      harness.execute('logs.read', <String, Object?>{
        'sessionId': harness.sessionId,
      }, grants: const <CockpitWorkerResourceGrant>[]),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having((error) => error.code, 'code', 'appPaused'),
      ),
    );
    expect(harness.pauseGuard!.calls, 1);
    expect(harness.app.requestCount, 0);
  });

  test('command.run proceeds when the app is running', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);

    final result = await harness.executeCommandRun();

    expect(harness.pauseGuard!.calls, 1);
    expect(harness.app.requestCount, 1);
    expect(result['selectedPlane'], isNotEmpty);
  });

  test('guard probe failures fail open end to end', () async {
    final harness = await _Harness.create(
      // Nothing listens on the VM service URI, so the real guard cannot
      // determine the pause state and must let the operation proceed.
      pauseGuard: CockpitVmAppPauseGuard(),
    );
    addTearDown(harness.dispose);

    final result = await harness.executeCommandRun();

    expect(harness.app.requestCount, 1);
    expect(result['selectedPlane'], isNotEmpty);
  });

  test('sessions without a development VM service skip the guard', () async {
    final harness = await _Harness.create(development: false);
    addTearDown(harness.dispose);
    harness.pauseGuard!.failure = const CockpitApplicationServiceException(
      code: 'appPaused',
      message: 'must not be consulted',
    );

    final result = await harness.executeCommandRun();

    expect(harness.pauseGuard!.calls, 0);
    expect(harness.app.requestCount, 1);
    expect(result['selectedPlane'], isNotEmpty);
  });
}

final class _Harness {
  _Harness._(
    this._temporary,
    this.app,
    this.pauseGuard,
    this._operations,
    this._sanitizer,
    this._context,
    this._grants,
    this.sessionId,
  );

  final Directory _temporary;
  final _FakeCommandApp app;
  final _FakePauseGuard? pauseGuard;
  final CockpitWorkerInteractiveOperations _operations;
  final CockpitWorkerResultSanitizer _sanitizer;
  final CockpitWorkspaceOperationContext _context;
  final List<CockpitWorkerResourceGrant> _grants;
  final String sessionId;

  static Future<_Harness> create({
    bool development = true,
    CockpitAppPauseGuard? pauseGuard,
  }) async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-pause-',
    );
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    final stateRoot = p.join(workspaceRoot, 'state');
    await Directory(stateRoot).create();
    final app = await _FakeCommandApp.start();
    final pauseGuardForHarness = pauseGuard ?? _FakePauseGuard();
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    final targetId = await registry.registerTarget(
      const CockpitWorkerTargetRegistration(
        workspaceId: 'workspaceA',
        platform: 'macos',
        deviceId: 'macos-1',
      ),
    );
    final remote = CockpitRemoteSessionHandle(
      platform: 'macos',
      deviceId: 'macos-1',
      projectDir: workspaceRoot,
      target: 'lib/main.dart',
      appId: 'pause-guard-app',
      platformAppIdKnown: false,
      host: app.endpoint.host,
      hostPort: app.endpoint.port,
      devicePort: app.endpoint.port,
      baseUrl: app.endpoint.toString(),
      launchedAt: DateTime.utc(2026, 10, 7, 9),
    );
    final handle = development
        ? CockpitAppHandle.fromDevelopmentSession(
            CockpitDevelopmentSessionHandle(
              developmentSessionId: 's_pause1',
              platform: 'macos',
              deviceId: 'macos-1',
              projectDir: workspaceRoot,
              target: 'lib/main.dart',
              appId: 'pause-guard-app',
              appBaseUrl: app.endpoint.toString(),
              supervisorBaseUrl: 'cockpit-worker://development/s_pause1',
              launchedAt: DateTime.utc(2026, 10, 7, 9),
              reloadGeneration: 0,
              remoteSessionHandle: remote,
              vmServiceUri: Uri.parse('http://127.0.0.1:9/ws'),
            ),
          )
        : CockpitAppHandle.fromRemoteSession(remote);
    final recorded = await registry.recordApp(targetId: targetId, handle: handle);
    final sessionId = await registry.sessionIdForApp(recorded.appId);
    final operations = CockpitWorkerInteractiveOperations(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      registry: registry,
      developmentRuntime: CockpitWorkerDevelopmentSessionRuntime(
        appTempStore: CockpitAppTempStore(
          root: p.join(stateRoot, 'app-temp'),
          permissionHardener: const CockpitPosixPermissionHardener(),
        ),
      ),
      documents: CockpitWorkerDocumentIndex(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot,
        permissionHardener: const CockpitPosixPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      ),
      producerRoot: p.join(stateRoot, 'producer'),
      targets: registry,
      processManager: CockpitWorkerProcessManager(),
      appPauseGuard: pauseGuardForHarness,
    );
    final binding = await registry.requireSession(sessionId);
    final now = DateTime.now().toUtc();
    final grants = <CockpitWorkerResourceGrant>[
      CockpitWorkerResourceGrant(
        grantId: 'grant-pause-1',
        leaseId: 'lease-pause-1',
        workspaceId: 'workspaceA',
        holderId: 'holder-1',
        resourceKind: CockpitLeaseResourceKind.session,
        resourceId: binding.resourceId,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    ];
    return _Harness._(
      temporary,
      app,
      pauseGuardForHarness is _FakePauseGuard ? pauseGuardForHarness : null,
      operations,
      CockpitWorkerResultSanitizer(
        workspaceRoot: workspaceRoot,
        registry: registry,
        artifactRetainer: CockpitWorkerArtifactRetainer(
          stateRoot: stateRoot,
          producerRoot: p.join(stateRoot, 'producer'),
          permissionHardener: const CockpitPosixPermissionHardener(),
          directorySyncer: const _NoopDirectorySyncer(),
        ),
      ),
      CockpitWorkspaceOperationContext(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        requestId: 'request-pause-1',
        deadline: now.add(const Duration(minutes: 2)),
        idempotencyKey: 'idem-pause-1',
        requiredFeatures: const <String>[],
        cancellation: CockpitRpcCancellation.detached(),
      ),
      grants,
      sessionId,
    );
  }

  Future<Map<String, Object?>> execute(
    String kind,
    Map<String, Object?> input, {
    List<CockpitWorkerResourceGrant>? grants,
  }) => _operations.execute(
    kind: kind,
    input: input,
    context: _context,
    grants: grants ?? _grants,
    sanitizer: _sanitizer,
  );

  Future<Map<String, Object?>> executeCommandRun() => execute(
    'command.run',
    <String, Object?>{
      'sessionId': sessionId,
      'profile': 'minimal',
      'command': <String, Object?>{
        'commandId': 'c1',
        'commandType': 'tap',
        'timeoutMs': 5000,
      },
    },
  );

  Future<void> dispose() async {
    await app.close();
    await _temporary.delete(recursive: true);
  }
}

final class _FakePauseGuard implements CockpitAppPauseGuard {
  Object? failure;

  int calls = 0;

  @override
  Future<void> ensureRunning({required Uri vmServiceUri}) async {
    calls += 1;
    final error = failure;
    if (error == null) return;
    throw error;
  }
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}

/// Serves the command execution route of one live app behind a loopback port.
final class _FakeCommandApp {
  _FakeCommandApp._(this._server);

  final HttpServer _server;
  int requestCount = 0;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_FakeCommandApp> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final app = _FakeCommandApp._(server);
    server.listen(app._handle);
    return app;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requestCount++;
    request.response.headers.contentType = ContentType.json;
    if (request.method == 'POST' && request.uri.path == '/commands/execute') {
      request.response.write(
        jsonEncode(
          <String, Object?>{
            'result': <String, Object?>{
              'success': true,
              'commandId': 'c1',
              'commandType': 'tap',
              'durationMs': 5,
            },
            'runtimeSteps': <Object>[],
          },
        ),
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}
