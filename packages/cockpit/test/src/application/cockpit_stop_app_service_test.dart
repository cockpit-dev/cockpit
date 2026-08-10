import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:test/test.dart';

void main() {
  test('app reachability requires the remote health endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = request.uri.path == '/status'
          ? HttpStatus.ok
          : HttpStatus.notFound;
      await request.response.close();
    });

    final reachable = await cockpitProbeAppReachability(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );

    expect(reachable, isFalse);
  });

  test(
    'stop app stops development apps through the development stop path',
    () async {
      final handle = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'dev-session-1',
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.demo',
        appBaseUrl: 'http://127.0.0.1:57331',
        supervisorBaseUrl: 'http://127.0.0.1:59331',
        launchedAt: DateTime.utc(2026, 3, 30),
        reloadGeneration: 0,
      );
      final app = CockpitAppHandle.fromDevelopmentSession(handle);
      CockpitStopDevelopmentSessionRequest? capturedRequest;

      final service = CockpitStopAppService(
        stopDevelopment: (request) async {
          capturedRequest = request;
          return CockpitStopDevelopmentSessionResult(
            sessionHandle: handle,
            status: CockpitDevelopmentSessionStatus(
              developmentSessionId: handle.developmentSessionId,
              state: CockpitDevelopmentSessionState.stopped,
              appReachable: false,
              remoteSessionReachable: false,
              reloadGeneration: handle.reloadGeneration,
              lastStatusAt: DateTime.utc(2026, 3, 30, 0, 1),
            ),
          );
        },
      );

      final result = await service.stop(CockpitStopAppRequest(app: app));

      expect(
        capturedRequest?.sessionHandle?.developmentSessionId,
        'dev-session-1',
      );
      expect(result.status.mode, CockpitAppMode.development);
      expect(result.status.state, 'stopped');
      expect(result.status.appReachable, isFalse);
    },
  );

  test(
    'stop app best-effort stops platform process for development apps',
    () async {
      final launchedAt = DateTime.utc(2026, 3, 30);
      final remoteSession = CockpitRemoteSessionHandle(
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'remote-dev-session',
        platformAppId: 'dev.cockpit.demo',
        host: '127.0.0.1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://127.0.0.1:57331',
        launchedAt: launchedAt,
      );
      final handle = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'dev-session-1',
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.demo',
        appBaseUrl: 'http://127.0.0.1:57331',
        supervisorBaseUrl: 'http://127.0.0.1:59331',
        launchedAt: launchedAt,
        reloadGeneration: 0,
        remoteSessionHandle: remoteSession,
      );
      final app = CockpitAppHandle.fromDevelopmentSession(handle);
      CockpitAppHandle? stoppedPlatformApp;

      final service = CockpitStopAppService(
        stopDevelopment: (request) async {
          return CockpitStopDevelopmentSessionResult(
            sessionHandle: handle,
            status: CockpitDevelopmentSessionStatus(
              developmentSessionId: handle.developmentSessionId,
              state: CockpitDevelopmentSessionState.stopped,
              appReachable: false,
              remoteSessionReachable: false,
              reloadGeneration: handle.reloadGeneration,
              lastStatusAt: DateTime.utc(2026, 3, 30, 0, 1),
            ),
          );
        },
        stopAutomation: (resolvedApp) async {
          stoppedPlatformApp = resolvedApp;
        },
      );

      await service.stop(CockpitStopAppRequest(app: app));

      expect(stoppedPlatformApp?.platform, 'macos');
      expect(stoppedPlatformApp?.platformAppId, 'dev.cockpit.demo');
    },
  );

  test(
    'stop app cleans platform process when development supervisor is stale',
    () async {
      final launchedAt = DateTime.utc(2026, 3, 30);
      final handle = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'dev-session-1',
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.demo',
        appBaseUrl: 'http://127.0.0.1:57331',
        supervisorBaseUrl: 'http://127.0.0.1:59331',
        launchedAt: launchedAt,
        reloadGeneration: 0,
        remoteSessionHandle: CockpitRemoteSessionHandle(
          platform: 'macos',
          deviceId: 'macos',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          appId: 'remote-dev-session',
          platformAppId: 'dev.cockpit.demo',
          host: '127.0.0.1',
          hostPort: 57331,
          devicePort: 57331,
          baseUrl: 'http://127.0.0.1:57331',
          launchedAt: launchedAt,
        ),
      );
      final app = CockpitAppHandle.fromDevelopmentSession(handle);
      CockpitAppHandle? stoppedPlatformApp;

      final service = CockpitStopAppService(
        stopDevelopment: (_) async {
          throw StateError('supervisor unavailable');
        },
        stopAutomation: (resolvedApp) async {
          stoppedPlatformApp = resolvedApp;
        },
        probeReachability: (_) async => false,
      );

      final result = await service.stop(CockpitStopAppRequest(app: app));

      expect(stoppedPlatformApp?.platformAppId, 'dev.cockpit.demo');
      expect(result.status.state, 'stopped');
      expect(result.status.lastError, contains('supervisor unavailable'));
    },
  );

  test(
    'stop app stops automation apps through the automation stop path',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.demo',
        mode: CockpitAppMode.automation,
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:57331',
        launchedAt: DateTime.utc(2026, 3, 30),
        platformAppId: 'dev.cockpit.demo',
      );
      CockpitAppHandle? stoppedApp;
      var probeCalls = 0;

      final service = CockpitStopAppService(
        stopAutomation: (resolvedApp) async {
          stoppedApp = resolvedApp;
        },
        probeReachability: (_) async {
          probeCalls += 1;
          return false;
        },
      );

      final result = await service.stop(CockpitStopAppRequest(app: app));

      expect(stoppedApp?.appId, 'dev.cockpit.demo');
      expect(probeCalls, greaterThanOrEqualTo(1));
      expect(result.status.mode, CockpitAppMode.automation);
      expect(result.status.state, 'stopped');
      expect(result.status.remoteSessionReachable, isFalse);
    },
  );

  test('stop app releases managed desktop application temp', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit-stop-app-temp-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final store = CockpitAppTempStore(
      root: '${tempDir.path}/apps',
      permissionHardener: const _NoopPermissionHardener(),
    );
    final remote = CockpitRemoteSessionHandle(
      platform: 'windows',
      deviceId: 'windows',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'cockpit/main.dart',
      appId: 'cockpit_demo',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 57331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 8, 10),
    );
    final key = cockpitRemoteAppTempKey(
      platform: remote.platform,
      hostPort: remote.hostPort,
    );
    final path = await store.prepare(key);

    final result =
        await CockpitStopAppService(
          appTempStore: store,
          stopAutomation: (_) async {},
          probeReachability: (_) async => false,
        ).stop(
          CockpitStopAppRequest(
            app: CockpitAppHandle.fromRemoteSession(remote),
          ),
        );

    expect(result.status.state, 'stopped');
    expect(result.status.lastError, isNull);
    expect(await Directory(path).exists(), isFalse);
  });

  test(
    'stop app fails fast for physical iOS automation apps without a resolved bundle id',
    () async {
      var stopCalls = 0;
      var probeCalls = 0;
      final service = CockpitStopAppService(
        stopAutomation: (_) async {
          stopCalls += 1;
        },
        probeReachability: (_) async {
          probeCalls += 1;
          return true;
        },
      );

      await expectLater(
        () => service.stop(
          CockpitStopAppRequest(
            app: CockpitAppHandle(
              appId: 'remote-session-1',
              mode: CockpitAppMode.automation,
              platform: 'ios',
              deviceId: '00008110-0009341C2EF3801E',
              projectDir: '/workspace/examples/cockpit_demo',
              target: 'cockpit/main.dart',
              baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
              launchedAt: DateTime.utc(2026, 5, 10),
            ),
          ),
        ),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'missingPlatformAppId')
              .having(
                (error) => error.details['deviceId'],
                'deviceId',
                '00008110-0009341C2EF3801E',
              ),
        ),
      );

      expect(stopCalls, 0);
      expect(probeCalls, 0);
    },
  );
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
