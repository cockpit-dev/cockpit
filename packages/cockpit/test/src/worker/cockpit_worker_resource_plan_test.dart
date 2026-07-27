import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_identity.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
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
      expect(appReadPlan.primaryResourceId, firstPlan.primaryResourceId);
      expect(appReadPlan.deviceResourceId, firstPlan.deviceResourceId);
      expect(targetReadPlan.primaryResourceId, firstPlan.deviceResourceId);
      expect(targetReadPlan.deviceResourceId, isNull);
      expect(installedFlutterLaunchPlan.requiresPort, isFalse);
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
