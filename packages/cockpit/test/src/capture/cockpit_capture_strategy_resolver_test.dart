import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/capture/cockpit_prioritized_capture_adapter.dart';
import 'package:cockpit/src/platform/web/cockpit_browser_host_app_id.dart';
import 'package:test/test.dart';

void main() {
  test('prefers adb system capture on Android', () async {
    final remoteAdapter = _SuccessfulCaptureAdapter(
      CockpitCaptureKind.flutterView,
    );
    final adbAdapter = _SuccessfulCaptureAdapter(CockpitCaptureKind.hostSystem);
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => adbAdapter,
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
    );

    final adapter = resolver.resolve(
      platform: 'android',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      androidDeviceId: 'emulator-5554',
    );

    final execution = await adapter.capture(_acceptanceScreenshot());

    expect(execution.result.resolvedCaptureKind, CockpitCaptureKind.hostSystem);
    expect(adbAdapter.captureCount, 1);
    expect(remoteAdapter.captureCount, 0);
  });

  test('prefers simctl system capture on an iOS simulator', () async {
    final remoteAdapter = _SuccessfulCaptureAdapter(
      CockpitCaptureKind.flutterView,
    );
    final simctlAdapter = _SuccessfulCaptureAdapter(
      CockpitCaptureKind.hostSystem,
    );
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => simctlAdapter,
    );

    final adapter = resolver.resolve(
      platform: 'ios',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      iosDeviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
    );

    final execution = await adapter.capture(_acceptanceScreenshot());

    expect(execution.result.resolvedCaptureKind, CockpitCaptureKind.hostSystem);
    expect(simctlAdapter.captureCount, 1);
    expect(remoteAdapter.captureCount, 0);
  });

  test('prefers WDA system capture on a physical iOS device', () async {
    final remoteAdapter = _SuccessfulCaptureAdapter(
      CockpitCaptureKind.flutterView,
    );
    final wdaAdapter = _SuccessfulCaptureAdapter(CockpitCaptureKind.hostSystem);
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      wdaAdapterFactory: (baseUri) {
        expect(baseUri, Uri.parse('http://127.0.0.1:8100'));
        return wdaAdapter;
      },
    );

    final adapter = resolver.resolve(
      platform: 'ios',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:1'),
      ),
      iosDeviceId: '00008110-0009341C2EF3801E',
      iosWdaBaseUri: Uri.parse('http://127.0.0.1:8100'),
    );
    final execution = await adapter.capture(_acceptanceScreenshot());

    expect(execution.result.resolvedCaptureKind, CockpitCaptureKind.hostSystem);
    expect(wdaAdapter.captureCount, 1);
    expect(remoteAdapter.captureCount, 0);
  });

  test('uses remote capture for physical iOS device IDs', () {
    final remoteAdapter = _FakeCaptureAdapter();
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
    );

    final adapter = resolver.resolve(
      platform: 'ios',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      iosDeviceId: '00008110-0009341C2EF3801E',
    );

    expect(adapter, same(remoteAdapter));
  });

  test('uses prioritized capture on macos when an app id is available', () {
    final remoteAdapter = _FakeCaptureAdapter();
    final macosAdapter = _FakeCaptureAdapter();
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      macosAdapterFactory: (appId, {processId}) => macosAdapter,
    );

    final adapter = resolver.resolve(
      platform: 'macos',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      sessionHandle: CockpitRemoteSessionHandle(
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'dev.cockpit.cockpitDemo',
        host: '127.0.0.1',
        hostPort: 47331,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:47331',
        launchedAt: DateTime.utc(2026, 3, 24),
      ),
    );

    expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
  });

  test('uses prioritized capture on windows when an app id is available', () {
    final remoteAdapter = _FakeCaptureAdapter();
    final windowsAdapter = _FakeCaptureAdapter();
    String? capturedAppId;
    int? capturedProcessId;
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      macosAdapterFactory: (appId, {processId}) => _FakeCaptureAdapter(),
      windowsAdapterFactory: (appId, {processId}) {
        capturedAppId = appId;
        capturedProcessId = processId;
        return windowsAdapter;
      },
    );

    final adapter = resolver.resolve(
      platform: 'windows',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      sessionHandle: CockpitRemoteSessionHandle(
        platform: 'windows',
        deviceId: 'windows',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'cockpit_demo',
        processId: 4101,
        host: '127.0.0.1',
        hostPort: 47331,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:47331',
        launchedAt: DateTime.utc(2026, 3, 24),
      ),
    );

    expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
    expect(capturedAppId, 'cockpit_demo');
    expect(capturedProcessId, 4101);
  });

  test(
    'uses prioritized capture on windows when only a process id is available',
    () {
      final remoteAdapter = _FakeCaptureAdapter();
      final windowsAdapter = _FakeCaptureAdapter();
      String? capturedAppId;
      int? capturedProcessId;
      final resolver = CockpitCaptureStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        windowsAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return windowsAdapter;
        },
      );

      final adapter = resolver.resolve(
        platform: 'windows',
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        sessionHandle: CockpitRemoteSessionHandle(
          platform: 'windows',
          deviceId: 'windows',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          appId: 'app-with-unknown-platform-id',
          platformAppIdKnown: false,
          processId: 4101,
          host: '127.0.0.1',
          hostPort: 47331,
          devicePort: 47331,
          baseUrl: 'http://127.0.0.1:47331',
          launchedAt: DateTime.utc(2026, 3, 24),
        ),
      );

      expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
      expect(capturedAppId, 'pid-4101');
      expect(capturedProcessId, 4101);
    },
  );

  test('uses prioritized capture on linux when an app id is available', () {
    final remoteAdapter = _FakeCaptureAdapter();
    final linuxAdapter = _FakeCaptureAdapter();
    String? capturedAppId;
    int? capturedProcessId;
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      macosAdapterFactory: (appId, {processId}) => _FakeCaptureAdapter(),
      linuxAdapterFactory: (appId, {processId}) {
        capturedAppId = appId;
        capturedProcessId = processId;
        return linuxAdapter;
      },
    );

    final adapter = resolver.resolve(
      platform: 'linux',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      sessionHandle: CockpitRemoteSessionHandle(
        platform: 'linux',
        deviceId: 'linux',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'cockpit_demo',
        processId: 5101,
        host: '127.0.0.1',
        hostPort: 47331,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:47331',
        launchedAt: DateTime.utc(2026, 3, 24),
      ),
    );

    expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
    expect(capturedAppId, 'cockpit_demo');
    expect(capturedProcessId, 5101);
  });

  test(
    'uses prioritized capture on linux when only a process id is available',
    () {
      final remoteAdapter = _FakeCaptureAdapter();
      final linuxAdapter = _FakeCaptureAdapter();
      String? capturedAppId;
      int? capturedProcessId;
      final resolver = CockpitCaptureStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        linuxAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return linuxAdapter;
        },
      );

      final adapter = resolver.resolve(
        platform: 'linux',
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        sessionHandle: CockpitRemoteSessionHandle(
          platform: 'linux',
          deviceId: 'linux',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          appId: 'app-with-unknown-platform-id',
          platformAppIdKnown: false,
          processId: 5101,
          host: '127.0.0.1',
          hostPort: 47331,
          devicePort: 47331,
          baseUrl: 'http://127.0.0.1:47331',
          launchedAt: DateTime.utc(2026, 3, 24),
        ),
      );

      expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
      expect(capturedAppId, 'pid-5101');
      expect(capturedProcessId, 5101);
    },
  );

  test(
    'uses browser host capture on web when a supported browser device is available',
    () {
      final remoteAdapter = _FakeCaptureAdapter();
      final hostAdapter = _FakeCaptureAdapter();
      String? capturedAppId;
      int? capturedProcessId;
      final resolver = CockpitCaptureStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        macosAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          return hostAdapter;
        },
        windowsAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return hostAdapter;
        },
        linuxAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return hostAdapter;
        },
        browserHostAppIdResolver: (deviceId) {
          expect(deviceId, 'chrome');
          return 'com.google.Chrome';
        },
        hostPlatformResolver: () => 'macos',
      );

      final adapter = resolver.resolve(
        platform: 'web',
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        sessionHandle: CockpitRemoteSessionHandle(
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
          launchedAt: DateTime.utc(2026, 3, 24),
        ),
      );

      expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
      expect(capturedAppId, 'com.google.Chrome');
      expect(capturedProcessId, isNull);
    },
  );

  test(
    'uses browser host capture on linux hosts when a browser app id is available',
    () {
      final remoteAdapter = _FakeCaptureAdapter();
      final linuxAdapter = _FakeCaptureAdapter();
      String? capturedAppId;
      int? capturedProcessId;
      final resolver = CockpitCaptureStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
        linuxAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return linuxAdapter;
        },
        browserHostAppIdResolver: (deviceId) => 'google-chrome',
        hostPlatformResolver: () => 'linux',
      );

      final adapter = resolver.resolve(
        platform: 'web',
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        deviceId: 'chrome',
      );

      expect(adapter, isA<CockpitPrioritizedCaptureAdapter>());
      expect(capturedAppId, 'google-chrome');
      expect(capturedProcessId, isNull);
    },
  );

  test('uses remote capture on web when the browser host is unsupported', () {
    final remoteAdapter = _FakeCaptureAdapter();
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      browserHostAppIdResolver: (deviceId) => null,
    );

    final adapter = resolver.resolve(
      platform: 'web',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      sessionHandle: CockpitRemoteSessionHandle(
        platform: 'web',
        deviceId: 'unknown-browser',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        appId: 'web-app',
        platformAppIdKnown: false,
        host: '127.0.0.1',
        hostPort: 47331,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:47331',
        launchedAt: DateTime.utc(2026, 3, 24),
      ),
    );

    expect(adapter, same(remoteAdapter));
  });

  test('falls back to remote capture when no host context is available', () {
    final remoteAdapter = _FakeCaptureAdapter();
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      macosAdapterFactory: (appId, {processId}) => _FakeCaptureAdapter(),
      browserHostAppIdResolver: cockpitResolveBrowserHostAppId,
    );

    final adapter = resolver.resolve(
      platform: 'macos',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
    );

    expect(adapter, same(remoteAdapter));
  });

  test('uses app-first acceptance routing on desktop platforms', () async {
    final remoteAdapter = _SuccessfulCaptureAdapter(
      CockpitCaptureKind.appNative,
    );
    final hostAdapter = _SuccessfulCaptureAdapter(
      CockpitCaptureKind.hostSystem,
    );
    final resolver = CockpitCaptureStrategyResolver(
      remoteAdapterFactory: (client) => remoteAdapter,
      adbAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeCaptureAdapter(),
      macosAdapterFactory: (appId, {processId}) => hostAdapter,
    );

    final adapter = resolver.resolve(
      platform: 'macos',
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:1'),
      ),
      platformAppId: 'dev.cockpit.demo',
    );
    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'acceptance',
        ),
      ),
    );

    expect(remoteAdapter.captureCount, 1);
    expect(hostAdapter.captureCount, 0);
    expect(execution.result.resolvedCaptureKind, CockpitCaptureKind.appNative);
  });
}

final class _FakeCaptureAdapter implements CockpitCaptureAdapter {
  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) {
    throw UnimplementedError();
  }
}

final class _SuccessfulCaptureAdapter implements CockpitCaptureAdapter {
  _SuccessfulCaptureAdapter(this.kind);

  final CockpitCaptureKind kind;
  int captureCount = 0;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    captureCount += 1;
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 1,
        resolvedCaptureKind: kind,
      ),
    );
  }
}

CockpitCommand _acceptanceScreenshot() => CockpitCommand(
  commandId: 'capture',
  commandType: CockpitCommandType.captureScreenshot,
  screenshotRequest: const CockpitScreenshotRequest(
    reason: CockpitScreenshotReason.acceptance,
    name: 'acceptance',
  ),
);
