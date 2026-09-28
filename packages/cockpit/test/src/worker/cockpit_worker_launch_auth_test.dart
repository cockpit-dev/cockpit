import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/application/cockpit_launch_target_service.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/targets/cockpit_target_handle.dart';
import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_application_support.dart';
import 'package:cockpit/src/worker/cockpit_worker_artifact_retainer.dart';
import 'package:cockpit/src/worker/cockpit_worker_development_session_runtime.dart';
import 'package:cockpit/src/worker/cockpit_worker_forwarded_port_handoff.dart';
import 'package:cockpit/src/worker/cockpit_worker_lifecycle_operations.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('launch operations reject enabled authentication without a token', () {
    for (final kind in const <String>[
      'target.launch',
      'session.development.launch',
      'app.launch',
    ]) {
      expect(
        _executeLaunch(kind, const <String, Object?>{
          'authenticationEnabled': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'authenticationEnabled requires a non-empty authToken.',
          ),
        ),
        reason: kind,
      );
    }
  });

  test('launch operations reject a token without enabled authentication', () {
    for (final kind in const <String>[
      'target.launch',
      'session.development.launch',
      'app.launch',
    ]) {
      expect(
        _executeLaunch(kind, const <String, Object?>{
          'authenticationEnabled': false,
          'authToken': 'wire-dev-auth-token',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'authToken requires authenticationEnabled to be true.',
          ),
        ),
        reason: kind,
      );
    }
  });

  test('target.launch threads the pair to the launch service', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);

    await harness.execute('target.launch', <String, Object?>{
      'authenticationEnabled': true,
      'authToken': 'wire-dev-auth-token',
    });

    expect(harness.capturedLaunch, isNotNull);
    expect(harness.capturedLaunch!.authenticationEnabled, isTrue);
    expect(harness.capturedLaunch!.authToken, 'wire-dev-auth-token');
  });
}

Future<void> _executeLaunch(String kind, Map<String, Object?> auth) async {
  final harness = await _Harness.create();
  addTearDown(harness.dispose);
  await harness.execute(kind, auth);
}

final class _Harness {
  _Harness._(
    this._root,
    this._registry,
    this._workspaceRoot,
    this._stateRoot,
    this._producerRoot,
    this.operations,
    this.targetId,
    this.deviceResourceId,
    this._captureLaunch,
  );

  final Directory _root;
  final CockpitWorkerRuntimeRegistry _registry;
  final String _workspaceRoot;
  final String _stateRoot;
  final String _producerRoot;
  final CockpitWorkerLifecycleOperations operations;
  final String targetId;
  final String deviceResourceId;
  final CockpitLaunchTargetRequest? Function() _captureLaunch;

  CockpitLaunchTargetRequest? get capturedLaunch => _captureLaunch();

  static Future<_Harness> create() async {
    final root = await Directory.systemTemp.createTemp('cockpit-launch-auth-');
    final workspaceRoot = await root.resolveSymbolicLinks();
    final stateRoot = p.join(workspaceRoot, 'state');
    final producerRoot = p.join(stateRoot, 'producer');
    await Directory(producerRoot).create(recursive: true);

    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspace-1',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    final targetId = await registry.registerTarget(
      const CockpitWorkerTargetRegistration(
        workspaceId: 'workspace-1',
        platform: 'macos',
        deviceId: 'macos',
        targetKind: CockpitTargetKind.flutterApp,
        mode: CockpitAppMode.automation,
        environment: CockpitTestTargetEnvironment.test,
      ),
    );
    final deviceResourceId = (await registry.requireTarget(
      workspaceId: 'workspace-1',
      targetId: targetId,
    )).deviceResourceId;
    final appTempStore = CockpitAppTempStore(
      root: p.join(stateRoot, 'app-temp'),
      permissionHardener: const _NoopPermissionHardener(),
    );
    CockpitLaunchTargetRequest? capturedLaunch;
    final now = DateTime.now().toUtc();
    final operations = CockpitWorkerLifecycleOperations(
      workspaceId: 'workspace-1',
      registry: registry,
      targets: registry,
      portHandoff: const _ImmediatePortHandoff(57331),
      developmentRuntime: CockpitWorkerDevelopmentSessionRuntime(
        appTempStore: appTempStore,
      ),
      appTempStore: appTempStore,
      launchTargetService: CockpitLaunchTargetService(
        launchTarget: (request) async {
          capturedLaunch = request;
          return CockpitLaunchTargetResult(
            target: CockpitTargetHandle(
              targetId: targetId,
              targetKind: CockpitTargetKind.flutterApp,
              platform: 'macos',
              deviceId: 'macos',
              projectDir: workspaceRoot,
              target: 'lib/main.dart',
              connection: const CockpitTargetConnection(
                baseUrl: 'http://127.0.0.1:57331',
              ),
              launchedAt: now,
            ),
          );
        },
      ),
      sensitiveValueRegistrar: (_) {},
    );
    return _Harness._(
      root,
      registry,
      workspaceRoot,
      stateRoot,
      producerRoot,
      operations,
      targetId,
      deviceResourceId,
      () => capturedLaunch,
    );
  }

  Future<void> execute(String kind, Map<String, Object?> input) {
    final now = DateTime.now().toUtc();
    final expiry = now.add(const Duration(hours: 1));
    return operations.execute(
      kind: kind,
      input: <String, Object?>{'targetId': targetId, ...input},
      context: CockpitWorkspaceOperationContext(
        workspaceId: 'workspace-1',
        workspaceRoot: _workspaceRoot,
        requestId: 'request-1',
        deadline: now.add(const Duration(minutes: 30)),
        idempotencyKey: 'launch-1',
        requiredFeatures: const <String>[],
        cancellation: CockpitRpcCancellation.detached(),
      ),
      grants: <CockpitWorkerResourceGrant>[
        CockpitWorkerResourceGrant(
          grantId: 'device-grant',
          leaseId: 'device-lease',
          workspaceId: 'workspace-1',
          holderId: 'operation-1',
          resourceKind: CockpitLeaseResourceKind.device,
          resourceId: deviceResourceId,
          expiresAt: expiry,
        ),
        CockpitWorkerResourceGrant(
          grantId: 'port-grant',
          leaseId: 'port-lease',
          workspaceId: 'workspace-1',
          holderId: 'operation-1',
          resourceKind: CockpitLeaseResourceKind.forwardedPort,
          resourceId: 'tcp:57331',
          expiresAt: expiry,
          port: 57331,
          handoffToken: '0123456789abcdef',
        ),
      ],
      sanitizer: CockpitWorkerResultSanitizer(
        workspaceRoot: _workspaceRoot,
        registry: _registry,
        artifactRetainer: CockpitWorkerArtifactRetainer(
          stateRoot: _stateRoot,
          producerRoot: _producerRoot,
          permissionHardener: const _NoopPermissionHardener(),
          directorySyncer: const _NoopDirectorySyncer(),
        ),
      ),
    );
  }

  Future<void> dispose() => _root.delete(recursive: true);
}

final class _ImmediatePortHandoff implements CockpitWorkerForwardedPortHandoff {
  const _ImmediatePortHandoff(this.port);

  final int port;

  @override
  Future<T> launchWithGrant<T>({
    required CockpitWorkerResourceGrant grant,
    required DateTime deadline,
    required Future<T> Function(int port) launch,
  }) => launch(port);
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
