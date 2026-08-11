import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_launch_target_service.dart';
import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_stop_app_service.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
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
  test('worker preserves launch configuration and long timeout', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-launch-configuration-',
    );
    addTearDown(() => root.delete(recursive: true));
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
      CockpitWorkerTargetRegistration(
        workspaceId: 'workspace-1',
        platform: 'macos',
        deviceId: 'macos',
        targetKind: CockpitTargetKind.flutterApp,
        mode: CockpitAppMode.automation,
        environment: CockpitTestTargetEnvironment.test,
      ),
    );
    final target = await registry.requireTarget(
      workspaceId: 'workspace-1',
      targetId: targetId,
    );
    final appTempStore = CockpitAppTempStore(
      root: p.join(stateRoot, 'app-temp'),
      permissionHardener: const _NoopPermissionHardener(),
    );
    CockpitLaunchTargetRequest? captured;
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
          captured = request;
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
    );
    final expiry = now.add(const Duration(hours: 1));
    final grants = <CockpitWorkerResourceGrant>[
      CockpitWorkerResourceGrant(
        grantId: 'device-grant',
        leaseId: 'device-lease',
        workspaceId: 'workspace-1',
        holderId: 'operation-1',
        resourceKind: CockpitLeaseResourceKind.device,
        resourceId: target.deviceResourceId,
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
    ];
    final sanitizer = CockpitWorkerResultSanitizer(
      workspaceRoot: workspaceRoot,
      registry: registry,
      artifactRetainer: CockpitWorkerArtifactRetainer(
        stateRoot: stateRoot,
        producerRoot: producerRoot,
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      ),
    );

    await operations.execute(
      kind: 'target.launch',
      input: <String, Object?>{
        'targetId': targetId,
        'launchTimeoutMs': const Duration(minutes: 29).inMilliseconds,
        'launchConfiguration': <String, Object?>{
          'dartDefines': <String>['API_URL=https://example.test'],
          'dartDefineFromFiles': <String>['config/staging.json'],
          'flutterArgs': <String>['--track-widget-creation'],
          'environment': <String, String>{'LOG_LEVEL': 'debug'},
        },
      },
      context: CockpitWorkspaceOperationContext(
        workspaceId: 'workspace-1',
        workspaceRoot: workspaceRoot,
        requestId: 'request-1',
        deadline: now.add(const Duration(minutes: 30)),
        idempotencyKey: 'launch-1',
        requiredFeatures: const <String>[],
        cancellation: CockpitRpcCancellation.detached(),
      ),
      grants: grants,
      sanitizer: sanitizer,
    );

    expect(captured, isNotNull);
    expect(captured!.launchTimeout, const Duration(minutes: 29));
    expect(captured!.launchConfiguration.dartDefines, <String>[
      'API_URL=https://example.test',
    ]);
    expect(captured!.launchConfiguration.dartDefineFromFiles, <String>[
      'config/staging.json',
    ]);
    expect(captured!.launchConfiguration.flutterArgs, <String>[
      '--track-widget-creation',
    ]);
    expect(captured!.launchConfiguration.environment, <String, String>{
      'LOG_LEVEL': 'debug',
    });
  });

  test(
    'worker replaces only the existing app for the launched target',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cockpit-launch-replaces-target-app-',
      );
      addTearDown(() => root.delete(recursive: true));
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
      final launchedTargetId = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspace-1',
          platform: 'macos',
          deviceId: 'macos',
          targetKind: CockpitTargetKind.flutterApp,
          mode: CockpitAppMode.automation,
          environment: CockpitTestTargetEnvironment.test,
        ),
      );
      final preservedTargetId = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspace-1',
          platform: 'macos',
          deviceId: 'macos-secondary',
          targetKind: CockpitTargetKind.flutterApp,
          mode: CockpitAppMode.automation,
          environment: CockpitTestTargetEnvironment.test,
        ),
      );
      final oldApp = CockpitAppHandle.fromRemoteSession(
        _remoteSession(
          workspaceRoot: workspaceRoot,
          appId: 'old-app',
          port: 57330,
        ),
      );
      final preservedApp = CockpitAppHandle.fromRemoteSession(
        _remoteSession(
          workspaceRoot: workspaceRoot,
          appId: 'preserved-app',
          deviceId: 'macos-secondary',
          port: 57329,
        ),
      );
      final oldBinding = await registry.recordApp(
        targetId: launchedTargetId,
        handle: oldApp,
      );
      final preservedBinding = await registry.recordApp(
        targetId: preservedTargetId,
        handle: preservedApp,
      );
      final stoppedAppIds = <String>[];
      final appTempStore = CockpitAppTempStore(
        root: p.join(stateRoot, 'app-temp'),
        permissionHardener: const _NoopPermissionHardener(),
      );
      final now = DateTime.now().toUtc();
      final launchedApp = CockpitAppHandle.fromRemoteSession(
        _remoteSession(
          workspaceRoot: workspaceRoot,
          appId: 'new-app',
          port: 57331,
          launchedAt: now,
        ),
      );
      final operations = CockpitWorkerLifecycleOperations(
        workspaceId: 'workspace-1',
        registry: registry,
        targets: registry,
        portHandoff: const _ImmediatePortHandoff(57331),
        developmentRuntime: CockpitWorkerDevelopmentSessionRuntime(
          appTempStore: appTempStore,
        ),
        appTempStore: appTempStore,
        stopAppService: CockpitStopAppService(
          stopAutomation: (app) async => stoppedAppIds.add(app.appId),
          probeReachability: (_) async => false,
        ),
        launchTargetService: CockpitLaunchTargetService(
          launchTarget: (request) async {
            expect(stoppedAppIds, <String>['old-app']);
            await expectLater(
              registry.requireApp(oldBinding.appId),
              throwsA(isA<CockpitApplicationServiceException>()),
            );
            expect(
              (await registry.requireApp(preservedBinding.appId)).handle.appId,
              'preserved-app',
            );
            return CockpitLaunchTargetResult(
              target: CockpitTargetHandle.fromAppHandle(
                launchedApp,
              ).copyWith(targetId: launchedTargetId),
              app: launchedApp,
            );
          },
        ),
      );
      final launchedTarget = await registry.requireTarget(
        workspaceId: 'workspace-1',
        targetId: launchedTargetId,
      );
      final expiry = now.add(const Duration(hours: 1));
      final sanitizer = CockpitWorkerResultSanitizer(
        workspaceRoot: workspaceRoot,
        registry: registry,
        artifactRetainer: CockpitWorkerArtifactRetainer(
          stateRoot: stateRoot,
          producerRoot: producerRoot,
          permissionHardener: const _NoopPermissionHardener(),
          directorySyncer: const _NoopDirectorySyncer(),
        ),
      );

      await operations.execute(
        kind: 'target.launch',
        input: <String, Object?>{'targetId': launchedTargetId},
        context: CockpitWorkspaceOperationContext(
          workspaceId: 'workspace-1',
          workspaceRoot: workspaceRoot,
          requestId: 'request-1',
          deadline: now.add(const Duration(minutes: 3)),
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
            resourceId: launchedTarget.deviceResourceId,
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
        sanitizer: sanitizer,
      );

      expect(stoppedAppIds, <String>['old-app']);
      final apps = await registry.listApps();
      expect(
        apps.map((app) => app.handle.appId),
        unorderedEquals(<String>['new-app', 'preserved-app']),
      );
    },
  );
}

CockpitRemoteSessionHandle _remoteSession({
  required String workspaceRoot,
  required String appId,
  required int port,
  String deviceId = 'macos',
  DateTime? launchedAt,
}) => CockpitRemoteSessionHandle(
  platform: 'macos',
  deviceId: deviceId,
  projectDir: workspaceRoot,
  target: 'lib/main.dart',
  appId: appId,
  host: '127.0.0.1',
  hostPort: port,
  devicePort: port,
  baseUrl: 'http://127.0.0.1:$port',
  launchedAt: launchedAt ?? DateTime.utc(2026, 8, 11),
);

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
