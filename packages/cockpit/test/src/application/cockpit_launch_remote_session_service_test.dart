import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/application/cockpit_launch_remote_session_service.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/platform/android/cockpit_android_device_readiness.dart';
import 'package:cockpit/src/application/cockpit_entrypoint_resolver.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/infrastructure/cockpit_sdk_environment.dart';
import 'package:cockpit/src/session/cockpit_flutter_launch_configuration.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/session/cockpit_remote_session_launch_options.dart';
import 'package:cockpit/src/session/cockpit_remote_session_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('maps Android readiness failures to structured launch errors', () async {
    final project = await Directory.systemTemp.createTemp(
      'cockpit-remote-android-readiness-',
    );
    addTearDown(() => project.delete(recursive: true));
    final entrypoint = File(p.join(project.path, 'cockpit', 'main.dart'));
    await entrypoint.parent.create(recursive: true);
    await entrypoint.writeAsString('void main() {}');
    final service = CockpitLaunchRemoteSessionService(
      launcher: _ThrowingLauncher(
        const CockpitAndroidDeviceReadinessException(
          'androidDeviceUnresponsive',
          'Android device emulator-5554 is unresponsive.',
        ),
      ),
      flutterVersionForExecutableReader: (_) async => '3.44.0',
      sessionPortAvailabilityChecker: (_) async => true,
    );

    await expectLater(
      service.launch(
        CockpitLaunchRemoteSessionRequest(
          projectDir: project.path,
          platform: 'android',
          deviceId: 'emulator-5554',
          sessionPort: 47331,
        ),
      ),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having((error) => error.code, 'code', 'androidDeviceUnresponsive')
            .having(
              (error) => error.message,
              'message',
              'Android device emulator-5554 is unresponsive.',
            ),
      ),
    );
  });

  test(
    'launch service returns a reusable session handle, health, and optional persisted json',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_launch_remote_session_service',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final expectedHandle = CockpitRemoteSessionHandle(
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 58421,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:58421',
        launchedAt: DateTime.utc(2026, 3, 21, 0, 0),
      );
      final expectedStatus = CockpitRemoteSessionStatus(
        sessionId: 'launch-demo',
        platform: 'android',
        transportType: 'remoteHttp',
        currentRouteName: '/home',
        capabilities: CockpitCapabilities(
          platform: 'android',
          transportType: 'remoteHttp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: true,
          supportsHostAutomation: false,
          supportedCommands: <CockpitCommandType>[CockpitCommandType.tap],
          supportedLocatorStrategies: CockpitLocatorKind.values,
        ),
        recordingCapabilities: CockpitRecordingCapabilities(
          supportsNativeRecording: true,
          preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        ),
        snapshot: CockpitSnapshot(routeName: '/home'),
      );

      final outputFile = File(p.join(tempDir.path, 'sessionHandle.json'));
      final service = CockpitLaunchRemoteSessionService(
        entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
        launcher: _FakeRemoteSessionLauncher(expectedHandle),
        statusReader: (baseUri) async {
          expect(baseUri.toString(), expectedHandle.baseUrl);
          return expectedStatus;
        },
      );

      final result = await service.launch(
        CockpitLaunchRemoteSessionRequest(
          projectDir: expectedHandle.projectDir,
          target: expectedHandle.target,
          platform: expectedHandle.platform,
          deviceId: expectedHandle.deviceId,
          sessionPort: expectedHandle.devicePort,
          launchTimeout: const Duration(seconds: 45),
          persistHandlePath: outputFile.path,
        ),
      );

      expect(result.sessionHandle.toJson(), expectedHandle.toJson());
      expect(result.health.sessionId, 'launch-demo');
      expect(result.persistedHandlePath, outputFile.path);

      final persistedJson =
          jsonDecode(await outputFile.readAsString()) as Map<String, Object?>;
      expect(persistedJson['platform'], 'android');
      expect(persistedJson['deviceId'], 'emulator-5554');
      expect(persistedJson['baseUrl'], 'http://127.0.0.1:58421');
    },
  );

  test(
    'launch service infers cockpit/main.dart when target is omitted',
    () async {
      final expectedHandle = CockpitRemoteSessionHandle(
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 58421,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:58421',
        launchedAt: DateTime.utc(2026, 3, 21, 0, 0),
      );
      final expectedStatus = CockpitRemoteSessionStatus(
        sessionId: 'launch-demo',
        platform: 'macos',
        transportType: 'remoteHttp',
        currentRouteName: '/home',
        capabilities: CockpitCapabilities(
          platform: 'macos',
          transportType: 'remoteHttp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: true,
          supportsHostAutomation: true,
          supportedCommands: <CockpitCommandType>[CockpitCommandType.tap],
          supportedLocatorStrategies: CockpitLocatorKind.values,
        ),
        recordingCapabilities: CockpitRecordingCapabilities(
          supportsNativeRecording: true,
          preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        ),
        snapshot: CockpitSnapshot(routeName: '/home'),
      );

      final service = CockpitLaunchRemoteSessionService(
        entrypointResolver: CockpitEntrypointResolver(
          exists: (path) =>
              path == '/workspace/examples/cockpit_demo/cockpit/main.dart',
        ),
        launcher: _FakeRemoteSessionLauncher(expectedHandle),
        statusReader: (_) async => expectedStatus,
      );

      final result = await service.launch(
        CockpitLaunchRemoteSessionRequest(
          projectDir: expectedHandle.projectDir,
          platform: expectedHandle.platform,
          deviceId: expectedHandle.deviceId,
          sessionPort: expectedHandle.devicePort,
        ),
      );

      expect(result.sessionHandle.target, 'cockpit/main.dart');
    },
  );

  test('launch service passes configured SDK executable and version', () async {
    String? versionExecutable;
    CockpitRemoteSessionLaunchOptions? capturedOptions;
    final expectedHandle = CockpitRemoteSessionHandle(
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'cockpit/main.dart',
      appId: 'dev.cockpit.cockpit_demo',
      host: '127.0.0.1',
      hostPort: 47331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:47331',
      launchedAt: DateTime.utc(2026, 3, 21, 0, 0),
    );

    final service = CockpitLaunchRemoteSessionService(
      sdkEnvironment: const CockpitSdkEnvironment(
        dartExecutable: '/opt/flutter/bin/cache/dart-sdk/bin/dart',
        flutterExecutable: '/opt/flutter/bin/flutter',
      ),
      flutterVersionForExecutableReader: (executable) async {
        versionExecutable = executable;
        return '3.32.0';
      },
      entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
      launcher: _CapturingRemoteSessionLauncher(
        handle: expectedHandle,
        onLaunch: (options) {
          capturedOptions = options;
        },
      ),
      statusReader: (_) async => CockpitRemoteSessionStatus(
        sessionId: 'launch-demo',
        platform: 'macos',
        transportType: 'remoteHttp',
        currentRouteName: '/home',
        capabilities: CockpitCapabilities(
          platform: 'macos',
          transportType: 'remoteHttp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: true,
          supportsHostAutomation: true,
        ),
        recordingCapabilities: CockpitRecordingCapabilities(
          supportsNativeRecording: true,
        ),
        snapshot: CockpitSnapshot(routeName: '/home'),
      ),
    );

    await service.launch(
      const CockpitLaunchRemoteSessionRequest(
        projectDir: '/workspace/examples/cockpit_demo',
        platform: 'macos',
        deviceId: 'macos',
        sessionPort: 47331,
      ),
    );

    expect(versionExecutable, '/opt/flutter/bin/flutter');
    expect(capturedOptions?.flutterExecutable, '/opt/flutter/bin/flutter');
    expect(capturedOptions?.flutterVersion, '3.32.0');
    expect(capturedOptions?.launchId, matches(RegExp(r'^r[a-z0-9]{10}$')));
  });

  test(
    'launch service remaps the iOS simulator session port when the preferred host port is occupied',
    () async {
      CockpitRemoteSessionLaunchOptions? capturedOptions;
      final expectedHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: 'FC5B7D0F-B7FB-4A7A-B1B0-FF28BC289BC2',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 59331,
        devicePort: 59331,
        baseUrl: 'http://127.0.0.1:59331',
        launchedAt: DateTime.utc(2026, 3, 21, 0, 0),
      );

      final service = CockpitLaunchRemoteSessionService(
        entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
        launcher: _CapturingRemoteSessionLauncher(
          handle: expectedHandle,
          onLaunch: (options) {
            capturedOptions = options;
          },
        ),
        statusReader: (_) async => CockpitRemoteSessionStatus(
          sessionId: 'remote-ios-sim',
          platform: 'ios',
          transportType: 'remoteHttp',
          currentRouteName: '/',
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
          snapshot: CockpitSnapshot(routeName: '/'),
        ),
        sessionPortAvailabilityChecker: (_) async => false,
        sessionPortAllocator: () async => 59331,
      );

      final result = await service.launch(
        const CockpitLaunchRemoteSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          platform: 'ios',
          deviceId: 'FC5B7D0F-B7FB-4A7A-B1B0-FF28BC289BC2',
          sessionPort: 57331,
        ),
      );

      expect(capturedOptions?.sessionPort, 59331);
      expect(result.sessionHandle.baseUrl, 'http://127.0.0.1:59331');
    },
  );

  test(
    'desktop remote app temp survives worker replacement and excludes the build',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit-remote-app-temp-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final appTempRoot = p.join(tempDir.path, 'apps');
      final store = CockpitAppTempStore(
        root: appTempRoot,
        permissionHardener: const _NoopPermissionHardener(),
      );
      CockpitRemoteSessionLaunchOptions? capturedOptions;
      final expectedHandle = CockpitRemoteSessionHandle(
        platform: 'linux',
        deviceId: 'linux',
        projectDir: tempDir.path,
        target: 'cockpit/main.dart',
        appId: 'cockpit_demo',
        host: '127.0.0.1',
        hostPort: 47331,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:47331',
        launchedAt: DateTime.utc(2026, 8, 10),
      );
      final service = CockpitLaunchRemoteSessionService(
        appTempStore: store,
        sdkEnvironment: const CockpitSdkEnvironment(
          dartExecutable: '/opt/flutter/bin/cache/dart-sdk/bin/dart',
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
        flutterVersionForExecutableReader: (_) async => '3.44.0',
        entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
        launcher: _CapturingRemoteSessionLauncher(
          handle: expectedHandle,
          onLaunch: (options) {
            capturedOptions = options;
          },
        ),
        statusReader: (_) async => _status(platform: 'linux'),
      );

      await service.launch(
        CockpitLaunchRemoteSessionRequest(
          projectDir: tempDir.path,
          platform: 'linux',
          deviceId: 'linux',
          sessionPort: 47331,
          launchConfiguration: CockpitFlutterLaunchConfiguration(
            environment: const <String, String>{'LOG_LEVEL': 'debug'},
          ),
        ),
      );

      expect(capturedOptions?.launchConfiguration.environment, <String, String>{
        'LOG_LEVEL': 'debug',
      });
      final environment = capturedOptions!.appEnvironment!;
      final path = environment['TMPDIR']!;
      expect(environment, <String, String>{
        'LOG_LEVEL': 'debug',
        'TMPDIR': path,
        'TMP': path,
        'TEMP': path,
      });
      expect(await Directory(path).exists(), isTrue);

      final replacement = CockpitAppTempStore(
        root: appTempRoot,
        permissionHardener: const _NoopPermissionHardener(),
      );
      expect(
        await replacement.prepare(
          cockpitRemoteAppTempKey(platform: 'linux', hostPort: 47331),
        ),
        path,
      );
    },
  );

  test('desktop remote app temp is released when launch fails', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit-failed-remote-app-temp-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final appTempRoot = p.join(tempDir.path, 'apps');
    final service = CockpitLaunchRemoteSessionService(
      appTempStore: CockpitAppTempStore(
        root: appTempRoot,
        permissionHardener: const _NoopPermissionHardener(),
      ),
      sdkEnvironment: const CockpitSdkEnvironment(
        dartExecutable: '/opt/flutter/bin/cache/dart-sdk/bin/dart',
        flutterExecutable: '/opt/flutter/bin/flutter',
      ),
      flutterVersionForExecutableReader: (_) async => '3.44.0',
      entrypointResolver: CockpitEntrypointResolver(exists: (_) => true),
      launcher: const _ThrowingRemoteSessionLauncher(),
    );

    await expectLater(
      () => service.launch(
        CockpitLaunchRemoteSessionRequest(
          projectDir: tempDir.path,
          platform: 'windows',
          deviceId: 'windows',
          sessionPort: 47331,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      await Directory(
        p.join(
          appTempRoot,
          cockpitRemoteAppTempKey(platform: 'windows', hostPort: 47331),
        ),
      ).exists(),
      isFalse,
    );
  });
}

CockpitRemoteSessionStatus _status({required String platform}) =>
    CockpitRemoteSessionStatus(
      sessionId: 'remote-$platform-session',
      platform: platform,
      transportType: 'remoteHttp',
      currentRouteName: '/',
      capabilities: CockpitCapabilities(
        platform: platform,
        transportType: 'remoteHttp',
        supportsInAppControl: true,
        supportsFlutterViewCapture: true,
        supportsNativeScreenCapture: true,
        supportsHostAutomation: true,
      ),
      recordingCapabilities: CockpitRecordingCapabilities(
        supportsNativeRecording: true,
      ),
      snapshot: CockpitSnapshot(routeName: '/'),
    );

final class _FakeRemoteSessionLauncher implements CockpitRemoteSessionLauncher {
  const _FakeRemoteSessionLauncher(this.handle);

  final CockpitRemoteSessionHandle handle;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) async {
    expect(options.projectDir, handle.projectDir);
    expect(options.target, handle.target);
    expect(options.platform, handle.platform);
    expect(options.deviceId, handle.deviceId);
    expect(options.sessionPort, handle.devicePort);
    return handle;
  }
}

final class _CapturingRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  const _CapturingRemoteSessionLauncher({
    required this.handle,
    required this.onLaunch,
  });

  final CockpitRemoteSessionHandle handle;
  final void Function(CockpitRemoteSessionLaunchOptions options) onLaunch;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) async {
    onLaunch(options);
    return handle;
  }
}

final class _ThrowingRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  const _ThrowingRemoteSessionLauncher();

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) => throw StateError('launch failed');
}

final class _ThrowingLauncher implements CockpitRemoteSessionLauncher {
  const _ThrowingLauncher(this.error);

  final Object error;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) => Future<CockpitRemoteSessionHandle>.error(error);
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
