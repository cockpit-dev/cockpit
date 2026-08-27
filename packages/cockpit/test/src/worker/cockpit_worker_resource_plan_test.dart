import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/test/cockpit_test_safety_policy.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_identity.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('reuses and replaces orphaned Flutter development targets', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-target-reconcile-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    await File(
      p.join(workspaceRoot, 'pubspec.yaml'),
    ).writeAsString('name: target_reconcile\n');
    final entrypoint = await File(
      p.join(workspaceRoot, 'main.dart'),
    ).writeAsString('void main() {}\n');
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: p.join(workspaceRoot, 'state'),
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    CockpitWorkerTargetRegistration registration(String hash) =>
        CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
          entrypoint: 'main.dart',
          entrypointSha256: hash,
          mode: CockpitAppMode.development,
          environment: CockpitTestTargetEnvironment.development,
        );

    final firstHash = sha256
        .convert(utf8.encode('void main() {}\n'))
        .toString();
    final first = await registry.registerTarget(registration(firstHash));
    final reused = await registry.registerTarget(registration(firstHash));
    expect(reused, first);
    expect(
      (await registry.listTargets()).map((target) => target.targetId),
      <String>[first],
    );

    await entrypoint.writeAsString('void main() => print(1);\n');
    final secondHash = sha256
        .convert(utf8.encode('void main() => print(1);\n'))
        .toString();
    final second = await registry.registerTarget(registration(secondHash));
    expect(second, isNot(first));
    expect(
      (await registry.listTargets()).map((target) => target.targetId),
      <String>[second],
    );
  });

  test(
    'plans one shared device lease for distinct sessions on one device',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-resource-plan-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final workspaceRoot = await temporary.resolveSymbolicLinks();
      final stateRoot = await Directory(
        p.join(workspaceRoot, 'state'),
      ).create();
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
      );
      final targetA = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );
      final targetB = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );
      final installedFlutterTarget = await registry.registerTarget(
        const CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
          targetKind: CockpitTargetKind.flutterApp,
          mode: CockpitAppMode.automation,
          appId: 'dev.cockpit.installed',
        ),
      );
      final first = await registry.recordApp(
        targetId: targetA,
        handle: CockpitAppHandle.fromRemoteSession(
          _remoteSession(
            appId: 'first-app',
            devicePort: 8101,
            projectDir: workspaceRoot,
          ),
        ),
      );
      final second = await registry.recordApp(
        targetId: targetB,
        handle: CockpitAppHandle.fromRemoteSession(
          _remoteSession(
            appId: 'second-app',
            devicePort: 8102,
            projectDir: workspaceRoot,
          ),
        ),
      );
      final firstSessionId = await registry.sessionIdForApp(first.appId);
      final secondSessionId = await registry.sessionIdForApp(second.appId);
      final firstPlan = await registry.resolveApplicationResourcePlan(
        kind: 'app.reload',
        input: <String, Object?>{'sessionId': firstSessionId},
      );
      final secondPlan = await registry.resolveApplicationResourcePlan(
        kind: 'app.reload',
        input: <String, Object?>{'sessionId': secondSessionId},
      );
      final probePlan = await registry.resolveApplicationResourcePlan(
        kind: 'development.probe.collect',
        input: <String, Object?>{'sessionId': firstSessionId},
      );
      final viewportPlan = await registry.resolveApplicationResourcePlan(
        kind: 'viewport.set',
        input: <String, Object?>{'sessionId': firstSessionId},
      );
      final appReadPlan = await registry.resolveApplicationResourcePlan(
        kind: 'app.get',
        input: <String, Object?>{'appId': first.appId},
      );
      final targetReadPlan = await registry.resolveApplicationResourcePlan(
        kind: 'target.inspect',
        input: <String, Object?>{'targetId': targetA},
      );
      final installedFlutterLaunchPlan = await registry
          .resolveApplicationResourcePlan(
            kind: 'target.launch',
            input: <String, Object?>{'targetId': installedFlutterTarget},
          );
      final sessionSystemActionPlan = await registry
          .resolveApplicationResourcePlan(
            kind: 'system.action',
            input: <String, Object?>{'sessionId': firstSessionId},
          );
      final targetSystemActionPlan = await registry
          .resolveApplicationResourcePlan(
            kind: 'system.action',
            input: <String, Object?>{'targetId': targetA},
          );

      expect(firstSessionId, isNot(secondSessionId));
      expect(firstPlan.primaryResourceId, isNot(secondPlan.primaryResourceId));
      expect(firstPlan.deviceResourceId, secondPlan.deviceResourceId);
      expect(
        firstPlan.deviceResourceId,
        cockpitCanonicalDeviceResourceId(
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );
      expect(
        firstPlan.deviceResourceId,
        isNot(equals(firstPlan.primaryResourceId)),
      );
      expect(probePlan.primaryResourceId, firstPlan.primaryResourceId);
      expect(probePlan.deviceResourceId, firstPlan.deviceResourceId);
      expect(viewportPlan.primaryResourceId, firstPlan.primaryResourceId);
      expect(viewportPlan.deviceResourceId, firstPlan.deviceResourceId);
      expect(appReadPlan.primaryResourceId, firstPlan.primaryResourceId);
      expect(appReadPlan.deviceResourceId, firstPlan.deviceResourceId);
      expect(targetReadPlan.primaryResourceId, firstPlan.deviceResourceId);
      expect(targetReadPlan.deviceResourceId, isNull);
      expect(installedFlutterLaunchPlan.requiresPort, isFalse);
      expect(
        sessionSystemActionPlan.primaryResourceId,
        firstPlan.deviceResourceId,
      );
      expect(
        targetSystemActionPlan.primaryResourceId,
        firstPlan.deviceResourceId,
      );
      expect(sessionSystemActionPlan.deviceResourceId, isNull);
      expect(targetSystemActionPlan.deviceResourceId, isNull);
      await expectLater(
        registry.resolveApplicationResourcePlan(
          kind: 'system.action',
          input: const <String, Object?>{},
        ),
        throwsFormatException,
      );
      await expectLater(
        registry.resolveApplicationResourcePlan(
          kind: 'system.action',
          input: <String, Object?>{
            'sessionId': firstSessionId,
            'targetId': targetA,
          },
        ),
        throwsFormatException,
      );
      for (final kind in const <String>{
        'session.remote.get',
        'session.remote.status',
        'snapshot.remote.read',
        'session.development.get',
        'ui.inspect',
        'surface.inspect',
        'logs.read',
        'network.read',
        'errors.read',
        'session.logs.read',
      }) {
        final readPlan = await registry.resolveApplicationResourcePlan(
          kind: kind,
          input: <String, Object?>{'sessionId': firstSessionId},
        );
        expect(
          readPlan.primaryResourceId,
          firstPlan.primaryResourceId,
          reason: kind,
        );
        expect(
          readPlan.deviceResourceId,
          firstPlan.deviceResourceId,
          reason: kind,
        );
      }
    },
  );

  test(
    'entrypoint edits block relaunch without blocking a live session',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-worker-entrypoint-refresh-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final workspaceRoot = await temporary.resolveSymbolicLinks();
      final stateRoot = await Directory(
        p.join(workspaceRoot, 'state'),
      ).create();
      await File(p.join(workspaceRoot, 'pubspec.yaml')).writeAsString('''
name: cockpit_entrypoint_fixture
environment:
  sdk: '>=3.8.0 <4.0.0'
''');
      const original = 'void main() {}\n';
      final entrypoint = await File(
        p.join(workspaceRoot, 'main.dart'),
      ).writeAsString(original);
      final registry = CockpitWorkerRuntimeRegistry(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot.path,
        stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
      );
      final targetId = await registry.registerTarget(
        CockpitWorkerTargetRegistration(
          workspaceId: 'workspaceA',
          platform: 'android',
          deviceId: 'emulator-5554',
          entrypoint: 'main.dart',
          entrypointSha256: sha256.convert(utf8.encode(original)).toString(),
        ),
      );
      final app = await registry.recordApp(
        targetId: targetId,
        handle: CockpitAppHandle.fromRemoteSession(
          _remoteSession(
            appId: 'live-app',
            devicePort: 8201,
            projectDir: workspaceRoot,
          ),
        ),
      );
      final sessionId = await registry.sessionIdForApp(app.appId);

      await entrypoint.writeAsString('Future<void> main() async {}\n');

      expect(
        (await registry.requireTarget(
          workspaceId: 'workspaceA',
          targetId: targetId,
        )).targetId,
        targetId,
      );
      for (final kind in const <String>['ui.inspect', 'surface.inspect']) {
        final plan = await registry.resolveApplicationResourcePlan(
          kind: kind,
          input: <String, Object?>{'sessionId': sessionId},
        );
        expect(plan.primaryResourceId, isNotEmpty, reason: kind);
      }
      final inspectPlan = await registry.resolveApplicationResourcePlan(
        kind: 'target.inspect',
        input: <String, Object?>{'targetId': targetId},
      );
      expect(inspectPlan.primaryResourceId, isNotEmpty);
      await expectLater(
        registry.resolveApplicationResourcePlan(
          kind: 'target.launch',
          input: <String, Object?>{'targetId': targetId},
        ),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'targetEntrypointStale',
          ),
        ),
      );
    },
  );
}

CockpitRemoteSessionHandle _remoteSession({
  required String appId,
  required int devicePort,
  required String projectDir,
}) => CockpitRemoteSessionHandle(
  platform: 'android',
  deviceId: 'emulator-5554',
  projectDir: projectDir,
  target: 'android',
  appId: appId,
  platformAppIdKnown: false,
  host: '127.0.0.1',
  hostPort: devicePort + 1000,
  devicePort: devicePort,
  baseUrl: 'http://127.0.0.1:${devicePort + 1000}',
  launchedAt: DateTime.utc(2026, 7, 20),
);
