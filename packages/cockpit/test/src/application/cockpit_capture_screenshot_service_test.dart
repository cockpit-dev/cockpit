import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/application/cockpit_app_reference_resolver.dart';
import 'package:test/test.dart';

void main() {
  test(
    'capture screenshot service builds an AI-first screenshot command',
    () async {
      CockpitRunCommandRequest? capturedRequest;
      final service = CockpitCaptureScreenshotService(
        runCommand: (request) async {
          capturedRequest = request;
          return const CockpitCaptureScreenshotResult(
            command: CockpitInteractiveCommandCore(
              commandId: 'capture-screenshot',
              commandType: 'captureScreenshot',
              success: true,
              durationMs: 12,
              usedCaptureFallback: false,
            ),
            artifacts: <CockpitInteractiveArtifactDescriptor>[],
          );
        },
      );

      await service.capture(
        CockpitCaptureScreenshotRequest(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
      );

      final request = capturedRequest;
      expect(request, isNotNull);
      expect(request!.baseUri, Uri.parse('http://127.0.0.1:47331'));
      expect(request.command.commandId, 'capture-screenshot');
      expect(request.command.commandType, CockpitCommandType.captureScreenshot);
      expect(request.resultProfile.name.jsonValue, 'standard');
      expect(request.defaultCommandTimeout, const Duration(seconds: 30));

      final screenshot = request.command.screenshotRequest;
      expect(screenshot, isNotNull);
      expect(screenshot!.reason, CockpitScreenshotReason.acceptance);
      expect(screenshot.name, 'screenshot');
      expect(screenshot.includeSnapshot, isFalse);
      expect(screenshot.attachToStep, isTrue);
      expect(screenshot.profile, isNull);
      expect(screenshot.allowFallback, isNull);
    },
  );

  test(
    'capture screenshot service forwards explicit evidence options',
    () async {
      CockpitRunCommandRequest? capturedRequest;
      final service = CockpitCaptureScreenshotService(
        runCommand: (request) async {
          capturedRequest = request;
          return const CockpitCaptureScreenshotResult(
            command: CockpitInteractiveCommandCore(
              commandId: 'capture-screenshot',
              commandType: 'captureScreenshot',
              success: true,
              durationMs: 12,
              usedCaptureFallback: false,
            ),
            artifacts: <CockpitInteractiveArtifactDescriptor>[],
          );
        },
      );

      await service.capture(
        CockpitCaptureScreenshotRequest(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
          name: 'before edit',
          reason: CockpitScreenshotReason.baseline,
          includeSnapshot: true,
          attachToStep: false,
          captureProfile: CockpitCaptureProfile.nativePreferred,
          allowFallback: false,
          resultProfile: CockpitInteractiveResultProfile.evidence(),
          defaultCommandTimeout: Duration(seconds: 9),
        ),
      );

      final request = capturedRequest!;
      expect(request.baseUri, Uri.parse('http://127.0.0.1:47331'));
      expect(request.resultProfile.name.jsonValue, 'evidence');
      expect(request.defaultCommandTimeout, const Duration(seconds: 9));
      expect(request.command.screenshotRequest?.name, 'before edit');
      expect(
        request.command.screenshotRequest?.reason,
        CockpitScreenshotReason.baseline,
      );
      expect(request.command.screenshotRequest?.includeSnapshot, isTrue);
      expect(request.command.screenshotRequest?.attachToStep, isFalse);
      expect(
        request.command.screenshotRequest?.profile,
        CockpitCaptureProfile.nativePreferred,
      );
      expect(request.command.screenshotRequest?.allowFallback, isFalse);
    },
  );

  test('capture screenshot service prefers app capture on desktop', () async {
    final hostAdapter = _FakeCaptureAdapter(
      execution: CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'capture-screenshot',
          commandType: CockpitCommandType.captureScreenshot,
          durationMs: 12,
          artifacts: const <CockpitArtifactRef>[
            CockpitArtifactRef(
              role: 'screenshot',
              relativePath: 'screenshots/system_acceptance.png',
            ),
          ],
          requestedCaptureProfile: CockpitCaptureProfile.acceptance,
          resolvedCaptureKind: CockpitCaptureKind.hostSystem,
        ),
        artifactSourcePaths: const <String, String>{
          'screenshots/system_acceptance.png': '/tmp/system_acceptance.png',
        },
      ),
    );
    final remoteAdapter = _FakeCaptureAdapter(
      execution: CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'capture-screenshot',
          commandType: CockpitCommandType.captureScreenshot,
          durationMs: 8,
          artifacts: const <CockpitArtifactRef>[
            CockpitArtifactRef(
              role: 'screenshot',
              relativePath: 'screenshots/app_acceptance.png',
            ),
          ],
          requestedCaptureProfile: CockpitCaptureProfile.acceptance,
          resolvedCaptureKind: CockpitCaptureKind.appNative,
        ),
      ),
    );
    final service = CockpitCaptureScreenshotService(
      captureStrategyResolver: CockpitCaptureStrategyResolver(
        remoteAdapterFactory: (_) => remoteAdapter,
        adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
        simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
        macosAdapterFactory: (_, {processId}) => hostAdapter,
      ),
    );

    final result = await service.capture(
      CockpitCaptureScreenshotRequest(
        app: _macosAppHandle(),
        name: 'acceptance',
        reason: CockpitScreenshotReason.acceptance,
        resultProfile: const CockpitInteractiveResultProfile.inspect(),
      ),
    );

    expect(hostAdapter.captureCount, 0);
    expect(remoteAdapter.captureCount, 1);
    expect(result.command.resolvedCaptureKind, 'appNative');
    expect(
      result.artifacts.single.relativePath,
      'screenshots/app_acceptance.png',
    );
  });

  test(
    'capture screenshot service reports app-native to Flutter fallback',
    () async {
      final hostAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 12,
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.hostSystem,
          ),
        ),
      );
      final remoteAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 8,
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.flutterView,
            usedCaptureFallback: true,
            degradationReason: 'nativeCaptureUnavailable',
          ),
        ),
      );
      final service = CockpitCaptureScreenshotService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => remoteAdapter,
          adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
          simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
          macosAdapterFactory: (_, {processId}) => hostAdapter,
        ),
      );

      final result = await service.capture(
        CockpitCaptureScreenshotRequest(
          app: _macosAppHandle(),
          name: 'acceptance',
          reason: CockpitScreenshotReason.acceptance,
        ),
      );

      expect(result.selectedPlane, CockpitPlaneKind.flutterSemanticPlane);
      expect(result.fallbackTrail, <CockpitPlaneKind>[
        CockpitPlaneKind.nativeUiPlane,
      ]);
    },
  );

  test(
    'capture screenshot service does not invent app subplanes after transport failure',
    () async {
      final hostAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 12,
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.hostSystem,
            surface: const <String, Object?>{
              'relation': 'differentApp',
              'app': 'dev.cockpit.demo',
              'front': 'com.example.other',
            },
            degradationReason: 'systemSurfaceMismatch',
          ),
        ),
      );
      final remoteAdapter = _ThrowingCaptureAdapter();
      final service = CockpitCaptureScreenshotService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => remoteAdapter,
          adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
          simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
          macosAdapterFactory: (_, {processId}) => hostAdapter,
        ),
      );

      final result = await service.capture(
        CockpitCaptureScreenshotRequest(
          app: _macosAppHandle(),
          name: 'acceptance',
          reason: CockpitScreenshotReason.acceptance,
        ),
      );

      expect(result.selectedPlane, CockpitPlaneKind.deviceSystemPlane);
      expect(result.fallbackTrail, <CockpitPlaneKind>[
        CockpitPlaneKind.flutterSemanticPlane,
      ]);
    },
  );

  test(
    'capture screenshot service falls back to app capture when system capture fails',
    () async {
      final remoteServer = await _RemoteStatusServer.start(
        supportsFlutterViewCapture: true,
        supportedCommands: const <String>['captureScreenshot'],
      );
      addTearDown(remoteServer.close);

      final hostAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: false,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 12,
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            error: CockpitCommandError.captureFailed(
              message: 'host capture unavailable',
            ),
          ),
        ),
      );
      final remoteAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 8,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/app_acceptance.png',
              ),
            ],
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.flutterView,
          ),
        ),
      );
      final service = CockpitCaptureScreenshotService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => remoteAdapter,
          adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
          simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
          macosAdapterFactory: (_, {processId}) => hostAdapter,
        ),
      );

      final result = await service.capture(
        CockpitCaptureScreenshotRequest(
          app: _macosAppHandle(baseUrl: remoteServer.baseUrl),
          name: 'acceptance',
          reason: CockpitScreenshotReason.acceptance,
          captureProfile: CockpitCaptureProfile.nativePreferred,
        ),
      );

      expect(hostAdapter.captureCount, 1);
      expect(remoteAdapter.captureCount, 1);
      expect(result.command.resolvedCaptureKind, 'flutterView');
      expect(result.command.usedCaptureFallback, isTrue);
      expect(result.command.degradationReason, 'hostCaptureFailed');
      expect(
        result.artifacts.single.relativePath,
        'screenshots/app_acceptance.png',
      );
    },
  );

  test(
    'capture screenshot service reports only the attempted primary plane when all sources fail',
    () async {
      final hostAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: false,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 12,
            error: CockpitCommandError.captureFailed(
              message: 'host capture unavailable',
            ),
          ),
        ),
      );
      final remoteAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: false,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 8,
            error: CockpitCommandError.captureFailed(
              message: 'app capture unavailable',
            ),
          ),
        ),
      );
      final service = CockpitCaptureScreenshotService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => remoteAdapter,
          adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
          simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
          macosAdapterFactory: (_, {processId}) => hostAdapter,
        ),
      );

      final result = await service.capture(
        CockpitCaptureScreenshotRequest(
          app: _macosAppHandle(),
          name: 'acceptance',
          reason: CockpitScreenshotReason.acceptance,
          captureProfile: CockpitCaptureProfile.nativePreferred,
        ),
      );

      expect(result.command.success, isFalse);
      expect(result.command.resolvedCaptureKind, isNull);
      expect(result.selectedPlane, CockpitPlaneKind.deviceSystemPlane);
      expect(result.fallbackTrail, isEmpty);
      expect(result.command.degradationReason, contains('appFallbackFailed'));
    },
  );

  test(
    'capture screenshot service uses Android system capture with baseUri and device id',
    () async {
      Uri? capturedRemoteBaseUri;
      final hostAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 12,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/android_system.png',
              ),
            ],
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.hostSystem,
            surface: const <String, Object?>{
              'relation': 'differentApp',
              'app': 'dev.cockpit.demo',
              'front': 'com.example.other',
            },
            degradationReason: 'systemSurfaceMismatch',
          ),
        ),
      );
      final remoteAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 8,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/app.png',
              ),
            ],
          ),
        ),
      );
      final service = CockpitCaptureScreenshotService(
        appReferenceResolver: CockpitAppReferenceResolver(
          portForwarder: CockpitAndroidPortForwarder(
            processRunner: (_, _) async =>
                ProcessResult(0, 0, 'emulator-5554 tcp:61331 tcp:47331\n', ''),
            hostPortAllocator: () async => 61331,
            hostPortAvailabilityChecker: (_) async => true,
          ),
        ),
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (client) {
            capturedRemoteBaseUri = client.baseUri;
            return remoteAdapter;
          },
          adbAdapterFactory: (deviceId, platformAppId) {
            expect(deviceId, 'emulator-5554');
            expect(platformAppId, isNull);
            return hostAdapter;
          },
          simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
        ),
      );

      final result = await service.capture(
        CockpitCaptureScreenshotRequest(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
          androidDeviceId: 'emulator-5554',
          name: 'android-system',
          reason: CockpitScreenshotReason.acceptance,
        ),
      );

      expect(hostAdapter.captureCount, 1);
      expect(remoteAdapter.captureCount, 0);
      expect(capturedRemoteBaseUri?.host, '127.0.0.1');
      expect(capturedRemoteBaseUri?.port, 61331);
      expect(result.command.resolvedCaptureKind, 'hostSystem');
      expect(result.command.degradationReason, 'systemSurfaceMismatch');
      expect(result.command.surface?['relation'], 'differentApp');
      expect(
        result.artifacts.single.relativePath,
        'screenshots/android_system.png',
      );
    },
  );

  test(
    'capture screenshot service uses iOS simulator system capture with baseUri and device id',
    () async {
      final hostAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 12,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/ios_system.png',
              ),
            ],
            requestedCaptureProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.hostSystem,
          ),
        ),
      );
      final remoteAdapter = _FakeCaptureAdapter(
        execution: CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-screenshot',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 8,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/app.png',
              ),
            ],
          ),
        ),
      );
      final service = CockpitCaptureScreenshotService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => remoteAdapter,
          adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
          simctlAdapterFactory: (deviceId) {
            expect(deviceId, '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC');
            return hostAdapter;
          },
        ),
      );

      final result = await service.capture(
        CockpitCaptureScreenshotRequest(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
          iosDeviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          name: 'ios-system',
          reason: CockpitScreenshotReason.acceptance,
        ),
      );

      expect(hostAdapter.captureCount, 1);
      expect(remoteAdapter.captureCount, 0);
      expect(result.command.resolvedCaptureKind, 'hostSystem');
      expect(
        result.artifacts.single.relativePath,
        'screenshots/ios_system.png',
      );
    },
  );

  test('capture screenshot service prefers app capture for web apps', () async {
    final hostAdapter = _FakeCaptureAdapter(
      execution: CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'capture-screenshot',
          commandType: CockpitCommandType.captureScreenshot,
          durationMs: 12,
          artifacts: const <CockpitArtifactRef>[
            CockpitArtifactRef(
              role: 'screenshot',
              relativePath: 'screenshots/web_host.png',
            ),
          ],
          requestedCaptureProfile: CockpitCaptureProfile.acceptance,
          resolvedCaptureKind: CockpitCaptureKind.hostSystem,
        ),
        artifactSourcePaths: const <String, String>{
          'screenshots/web_host.png': '/tmp/web_host.png',
        },
      ),
    );
    final remoteAdapter = _FakeCaptureAdapter(
      execution: CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'capture-screenshot',
          commandType: CockpitCommandType.captureScreenshot,
          durationMs: 8,
          artifacts: const <CockpitArtifactRef>[
            CockpitArtifactRef(
              role: 'screenshot',
              relativePath: 'screenshots/web_remote.png',
            ),
          ],
          resolvedCaptureKind: CockpitCaptureKind.flutterView,
        ),
      ),
    );
    final service = CockpitCaptureScreenshotService(
      captureStrategyResolver: CockpitCaptureStrategyResolver(
        remoteAdapterFactory: (_) => remoteAdapter,
        adbAdapterFactory: (_, _) => throw StateError('adb not expected'),
        simctlAdapterFactory: (_) => throw StateError('simctl not expected'),
        macosAdapterFactory: (appId, {processId}) {
          expect(appId, 'com.google.Chrome');
          return hostAdapter;
        },
        browserHostAppIdResolver: (deviceId) {
          expect(deviceId, 'chrome');
          return 'com.google.Chrome';
        },
        hostPlatformResolver: () => 'macos',
      ),
    );

    final result = await service.capture(
      CockpitCaptureScreenshotRequest(
        app: _webAppHandle(),
        name: 'web-host',
        reason: CockpitScreenshotReason.acceptance,
      ),
    );

    expect(hostAdapter.captureCount, 0);
    expect(remoteAdapter.captureCount, 1);
    expect(result.command.resolvedCaptureKind, 'flutterView');
    expect(result.artifacts.single.relativePath, 'screenshots/web_remote.png');
  });
}

CockpitAppHandle _macosAppHandle({String baseUrl = 'http://127.0.0.1:47331'}) {
  final baseUri = Uri.parse(baseUrl);
  return CockpitAppHandle(
    appId: 'macos-app',
    mode: CockpitAppMode.automation,
    platform: 'macos',
    deviceId: 'macos',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    baseUrl: baseUrl,
    launchedAt: DateTime.utc(2026, 6, 16),
    platformAppId: 'dev.cockpit.demo',
    remoteSession: CockpitRemoteSessionHandle(
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'cockpit/main.dart',
      appId: 'dev.cockpit.demo',
      host: baseUri.host,
      hostPort: baseUri.port,
      devicePort: baseUri.port,
      baseUrl: baseUrl,
      launchedAt: DateTime.utc(2026, 6, 16),
    ),
  );
}

CockpitAppHandle _webAppHandle() {
  return CockpitAppHandle(
    appId: 'web-app',
    mode: CockpitAppMode.development,
    platform: 'web',
    deviceId: 'chrome',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    baseUrl: 'http://127.0.0.1:47331',
    launchedAt: DateTime.utc(2026, 6, 16),
    remoteSession: CockpitRemoteSessionHandle(
      platform: 'web',
      deviceId: 'chrome',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'cockpit/main.dart',
      appId: 'web-app',
      platformAppIdKnown: false,
      host: '127.0.0.1',
      hostPort: 47331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:47331',
      launchedAt: DateTime.utc(2026, 6, 16),
    ),
  );
}

final class _FakeCaptureAdapter implements CockpitCaptureAdapter {
  _FakeCaptureAdapter({required this.execution});

  final CockpitCommandExecution execution;
  int captureCount = 0;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    captureCount += 1;
    return execution;
  }
}

final class _ThrowingCaptureAdapter implements CockpitCaptureAdapter {
  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) {
    throw StateError('Remote transport failed before app capture.');
  }
}

final class _RemoteStatusServer {
  const _RemoteStatusServer._(this._server);

  final HttpServer _server;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<_RemoteStatusServer> start({
    required bool supportsFlutterViewCapture,
    required List<String> supportedCommands,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"sessionId":"test-session","platform":"macos","transportType":"http",'
          '"capabilities":{"platform":"macos","transportType":"http",'
          '"supportsInAppControl":true,'
          '"supportsFlutterViewCapture":$supportsFlutterViewCapture,'
          '"supportsNativeScreenCapture":false,'
          '"supportsHostAutomation":false,'
          '"supportedCommands":${_jsonStringList(supportedCommands)},'
          '"supportedLocatorStrategies":[]},'
          '"recordingCapabilities":{"available":false,"drivers":[]},'
          '"snapshot":{"schemaVersion":1,"capturedAt":"2026-06-16T00:00:00.000Z",'
          '"platform":"macos","currentRouteName":"/"}}',
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });
    return _RemoteStatusServer._(server);
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}

String _jsonStringList(List<String> values) {
  return '[${values.map((value) => '"$value"').join(',')}]';
}
