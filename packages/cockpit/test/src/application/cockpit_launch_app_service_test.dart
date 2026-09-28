import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/development/cockpit_development_session_machine_launcher.dart';
import 'package:test/test.dart';

void main() {
  test('launch-app request defaults launch timeout to 600 seconds', () {
    const request = CockpitLaunchAppRequest(
      projectDir: '/workspace/examples/cockpit_demo',
      platform: 'macos',
      deviceId: 'macos',
      sessionPort: 57331,
    );

    expect(request.launchTimeout, const Duration(seconds: 600));
  });

  test(
    'launch-app stops an existing desktop app from the same workspace before relaunching',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'flutter_cockpit_launch_app_service_existing_desktop_',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final appHandlePath = '${tempDirectory.path}/latest_app.json';
      final existingApp = CockpitAppHandle(
        appId: 'dev.voxflow.old',
        mode: CockpitAppMode.development,
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:57331',
        launchedAt: DateTime.utc(2026, 6, 5, 3, 21),
      );
      await File(appHandlePath).writeAsString(jsonEncode(existingApp.toJson()));

      CockpitAppHandle? stoppedApp;
      var developmentLaunchCount = 0;

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            developmentLaunchCount += 1;
            expect(stoppedApp?.appId, existingApp.appId);
            return _developmentBootstrap(
              platform: 'macos',
              deviceId: 'macos',
              projectDir: '/workspace/examples/cockpit_demo',
              target: 'cockpit/main_onboarding.dart',
            );
          },
        ),
        stopExistingDesktopApp: (app) async {
          stoppedApp = app;
        },
      );

      final result = await service.launch(
        CockpitLaunchAppRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main_onboarding.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 57331,
          appHandlePath: appHandlePath,
        ),
      );

      expect(developmentLaunchCount, 1);
      expect(stoppedApp?.target, 'cockpit/main.dart');
      expect(result.app.target, 'cockpit/main_onboarding.dart');
    },
  );

  test(
    'launch-app falls back to automation when physical iOS development launch fails',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpitDemo',
        host: 'fd69:8f18:f0a9::1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
        launchedAt: DateTime.utc(2026, 4, 15),
      );

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw const CockpitDevelopmentSessionFallbackException(
              code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              message:
                  'The iOS physical-device remote session became reachable, but flutter run --machine exited before app.start. Automation fallback is safe.',
            );
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _FakeRemoteSessionLauncher(remoteHandle),
          statusReader: (_, {String authToken = ''}) async =>
              CockpitRemoteSessionStatus(
                sessionId: 'ios-profile-session',
                platform: 'ios',
                transportType: 'remoteHttp',
                currentRouteName: '/inbox',
                capabilities: CockpitCapabilities(
                  platform: 'ios',
                  transportType: 'remoteHttp',
                  supportsInAppControl: true,
                  supportsFlutterViewCapture: true,
                  supportsNativeScreenCapture: true,
                  supportsHostAutomation: false,
                ),
                recordingCapabilities: CockpitRecordingCapabilities(
                  supportsNativeRecording: true,
                ),
                snapshot: CockpitSnapshot(routeName: '/inbox'),
              ),
        ),
      );

      final result = await service.launch(
        const CockpitLaunchAppRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          sessionPort: 57331,
        ),
      );

      expect(result.app.mode, CockpitAppMode.automation);
      expect(result.app.baseUrl, 'http://[fd69:8f18:f0a9::1]:57331');
      expect(result.supervisorLogPath, isNull);
    },
  );

  test(
    'launch-app does not silently downgrade physical iOS to automation for unrelated development failures',
    () async {
      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw StateError('flutter build failed: missing entitlement.');
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _FakeRemoteSessionLauncher(
            CockpitRemoteSessionHandle(
              platform: 'ios',
              deviceId: '00008110-0009341C2EF3801E',
              projectDir: '/workspace/examples/cockpit_demo',
              target: 'cockpit/main.dart',
              appId: 'dev.cockpit.cockpitDemo',
              host: 'fd69:8f18:f0a9::1',
              hostPort: 57331,
              devicePort: 57331,
              baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
              launchedAt: DateTime.utc(2026, 4, 15),
            ),
          ),
        ),
      );

      await expectLater(
        () => service.launch(
          const CockpitLaunchAppRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'ios',
            deviceId: '00008110-0009341C2EF3801E',
            sessionPort: 57331,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('missing entitlement'),
          ),
        ),
      );
    },
  );

  test(
    'launch-app falls back only when physical iOS development reports a safe fallback code',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpitDemo',
        host: 'fd69:8f18:f0a9::1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
        launchedAt: DateTime.utc(2026, 4, 15),
      );

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw const CockpitDevelopmentSessionFallbackException(
              code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              message: 'Automation fallback is safe.',
            );
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _FakeRemoteSessionLauncher(remoteHandle),
          statusReader: (_, {String authToken = ''}) async =>
              CockpitRemoteSessionStatus(
                sessionId: 'ios-profile-session',
                platform: 'ios',
                transportType: 'remoteHttp',
                currentRouteName: '/inbox',
                capabilities: CockpitCapabilities(
                  platform: 'ios',
                  transportType: 'remoteHttp',
                  supportsInAppControl: true,
                  supportsFlutterViewCapture: true,
                  supportsNativeScreenCapture: true,
                  supportsHostAutomation: false,
                ),
                recordingCapabilities: CockpitRecordingCapabilities(
                  supportsNativeRecording: true,
                ),
                snapshot: CockpitSnapshot(routeName: '/inbox'),
              ),
        ),
      );

      final result = await service.launch(
        const CockpitLaunchAppRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          sessionPort: 57331,
        ),
      );

      expect(result.app.mode, CockpitAppMode.automation);
      expect(result.app.baseUrl, 'http://[fd69:8f18:f0a9::1]:57331');
    },
  );

  test(
    'launch-app reuses the ready physical iOS remote session instead of relaunching automation',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpitDemo',
        host: 'fd69:8f18:f0a9::1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
        launchedAt: DateTime.utc(2026, 4, 15),
      );
      var remoteLaunchCount = 0;
      var remoteStatusReadCount = 0;

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw CockpitDevelopmentSessionFallbackException(
              code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              message: 'Automation fallback is safe.',
              remoteSessionHandle: remoteHandle,
            );
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _CapturingRemoteSessionLauncher(
            onLaunch: (_) => remoteLaunchCount += 1,
          ),
        ),
        remoteStatusReader: (baseUri, {String authToken = ''}) async {
          remoteStatusReadCount += 1;
          expect(baseUri, remoteHandle.baseUri);
          return CockpitRemoteSessionStatus(
            sessionId: 'ios-profile-session',
            platform: 'ios',
            transportType: 'remoteHttp',
            currentRouteName: '/inbox',
            capabilities: CockpitCapabilities(
              platform: 'ios',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: true,
            ),
            snapshot: CockpitSnapshot(routeName: '/inbox'),
          );
        },
      );

      final result = await service.launch(
        const CockpitLaunchAppRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          sessionPort: 57331,
        ),
      );

      expect(remoteLaunchCount, 0);
      expect(remoteStatusReadCount, 1);
      expect(result.app.mode, CockpitAppMode.automation);
      expect(result.app.remoteSession?.baseUrl, remoteHandle.baseUrl);
    },
  );

  test(
    'launch-app still reuses the ready physical iOS remote session when follow-up status probing fails',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpitDemo',
        host: 'fd69:8f18:f0a9::1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
        launchedAt: DateTime.utc(2026, 4, 15),
      );
      var remoteLaunchCount = 0;

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw CockpitDevelopmentSessionFallbackException(
              code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              message: 'Automation fallback is safe.',
              remoteSessionHandle: remoteHandle,
            );
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _CapturingRemoteSessionLauncher(
            onLaunch: (_) => remoteLaunchCount += 1,
          ),
        ),
        remoteStatusReader: (_, {String authToken = ''}) async {
          throw StateError('transient health probe failure');
        },
      );

      final result = await service.launch(
        const CockpitLaunchAppRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          sessionPort: 57331,
        ),
      );

      expect(remoteLaunchCount, 0);
      expect(result.app.mode, CockpitAppMode.automation);
      expect(result.app.remoteSession?.baseUrl, remoteHandle.baseUrl);
    },
  );

  test(
    'launch-app reuse keeps platform app id absent when physical iOS fallback could not resolve a bundle id',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'remote-session-1',
        platformAppIdKnown: false,
        host: 'fd69:8f18:f0a9::1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
        launchedAt: DateTime.utc(2026, 4, 15),
      );

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw CockpitDevelopmentSessionFallbackException(
              code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              message: 'Automation fallback is safe.',
              remoteSessionHandle: remoteHandle,
            );
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _CapturingRemoteSessionLauncher(onLaunch: (_) {}),
        ),
        remoteStatusReader: (_, {String authToken = ''}) async =>
            CockpitRemoteSessionStatus(
              sessionId: 'ios-profile-session',
              platform: 'ios',
              transportType: 'remoteHttp',
              currentRouteName: '/inbox',
              capabilities: CockpitCapabilities(
                platform: 'ios',
                transportType: 'remoteHttp',
                supportsInAppControl: true,
                supportsFlutterViewCapture: true,
                supportsNativeScreenCapture: true,
                supportsHostAutomation: false,
              ),
              recordingCapabilities: CockpitRecordingCapabilities(
                supportsNativeRecording: true,
              ),
              snapshot: CockpitSnapshot(routeName: '/inbox'),
            ),
      );

      final result = await service.launch(
        const CockpitLaunchAppRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          sessionPort: 57331,
        ),
      );

      expect(result.app.appId, 'remote-session-1');
      expect(result.app.platformAppId, isNull);
    },
  );

  test(
    'launch-app does not silently relaunch automation when fallback session reuse cannot persist the app handle',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpitDemo',
        host: 'fd69:8f18:f0a9::1',
        hostPort: 57331,
        devicePort: 57331,
        baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
        launchedAt: DateTime.utc(2026, 4, 15),
      );
      var remoteLaunchCount = 0;
      final tempDirectory = await Directory.systemTemp.createTemp(
        'flutter_cockpit_launch_app_service_test_',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final service = CockpitLaunchAppService(
        developmentService: CockpitLaunchDevelopmentSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: (_) async {
            throw CockpitDevelopmentSessionFallbackException(
              code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              message: 'Automation fallback is safe.',
              remoteSessionHandle: remoteHandle,
            );
          },
        ),
        remoteService: CockpitLaunchRemoteSessionService(
          entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
          launcher: _CapturingRemoteSessionLauncher(
            onLaunch: (_) => remoteLaunchCount += 1,
          ),
        ),
        remoteStatusReader: (_, {String authToken = ''}) async =>
            CockpitRemoteSessionStatus(
              sessionId: 'ios-profile-session',
              platform: 'ios',
              transportType: 'remoteHttp',
              currentRouteName: '/inbox',
              capabilities: CockpitCapabilities(
                platform: 'ios',
                transportType: 'remoteHttp',
                supportsInAppControl: true,
                supportsFlutterViewCapture: true,
                supportsNativeScreenCapture: true,
                supportsHostAutomation: false,
              ),
              recordingCapabilities: CockpitRecordingCapabilities(
                supportsNativeRecording: true,
              ),
              snapshot: CockpitSnapshot(routeName: '/inbox'),
            ),
      );

      await expectLater(
        () => service.launch(
          CockpitLaunchAppRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'ios',
            deviceId: '00008110-0009341C2EF3801E',
            sessionPort: 57331,
            appHandlePath: tempDirectory.path,
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(remoteLaunchCount, 0);
    },
  );
}

CockpitDevelopmentSessionBootstrap _developmentBootstrap({
  required String platform,
  required String deviceId,
  required String projectDir,
  required String target,
}) {
  final remoteSession = CockpitRemoteSessionHandle(
    platform: platform,
    deviceId: deviceId,
    projectDir: projectDir,
    target: target,
    appId: 'dev.example.app',
    platformAppId: 'dev.example.platform',
    host: '127.0.0.1',
    hostPort: 57331,
    devicePort: 57331,
    baseUrl: 'http://127.0.0.1:57331',
    launchedAt: DateTime.utc(2026, 6, 5, 3, 24),
  );
  final handle = CockpitDevelopmentSessionHandle(
    developmentSessionId: 'dev-session-1',
    platform: platform,
    deviceId: deviceId,
    projectDir: projectDir,
    target: target,
    appId: 'dev.example.app',
    appBaseUrl: 'http://127.0.0.1:57331',
    supervisorBaseUrl: 'http://127.0.0.1:57332',
    launchedAt: DateTime.utc(2026, 6, 5, 3, 24),
    reloadGeneration: 0,
    remoteSessionHandle: remoteSession,
  );
  return CockpitDevelopmentSessionBootstrap(
    sessionHandle: handle,
    status: CockpitDevelopmentSessionStatus(
      developmentSessionId: handle.developmentSessionId,
      state: CockpitDevelopmentSessionState.ready,
      appReachable: true,
      remoteSessionReachable: true,
      reloadGeneration: 0,
      lastStatusAt: DateTime.utc(2026, 6, 5, 3, 24),
    ),
  );
}

final class _FakeRemoteSessionLauncher implements CockpitRemoteSessionLauncher {
  const _FakeRemoteSessionLauncher(this.handle);

  final CockpitRemoteSessionHandle handle;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) async {
    expect(options.platform, handle.platform);
    expect(options.deviceId, handle.deviceId);
    return handle;
  }
}

final class _CapturingRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  _CapturingRemoteSessionLauncher({required this.onLaunch});

  final void Function(CockpitRemoteSessionLaunchOptions options) onLaunch;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) {
    onLaunch(options);
    throw StateError('remote launch should not have been called');
  }
}
