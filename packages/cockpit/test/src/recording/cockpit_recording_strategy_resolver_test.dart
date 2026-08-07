import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:test/test.dart';

void main() {
  const autoRequest = CockpitRecordingRequest(
    purpose: CockpitRecordingPurpose.acceptance,
    name: 'acceptance-demo',
    attachToStep: true,
  );
  const nativeRequest = CockpitRecordingRequest(
    purpose: CockpitRecordingPurpose.acceptance,
    name: 'native-demo',
    mode: CockpitRecordingMode.native,
  );
  const fullRequest = CockpitRecordingRequest(
    purpose: CockpitRecordingPurpose.acceptance,
    name: 'full-demo',
    mode: CockpitRecordingMode.full,
  );
  const strictFlutterLayerRequest = CockpitRecordingRequest(
    purpose: CockpitRecordingPurpose.acceptance,
    name: 'flutter-layer-demo',
    layer: CockpitRecordingLayer.flutter,
  );
  const fallbackSystemLayerRequest = CockpitRecordingRequest(
    purpose: CockpitRecordingPurpose.acceptance,
    name: 'system-fallback-demo',
    layer: CockpitRecordingLayer.system,
    allowFallback: true,
  );

  test('prefers adb system recording for Android auto mode', () {
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
    );

    final resolution = resolver.resolveDetailed(
      platform: 'android',
      recording: autoRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      androidDeviceId: 'emulator-5554',
    );

    expect(resolution?.implementation, 'adb');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.system);
    expect(resolution?.fallbackUsed, isFalse);
    expect(resolution?.adapter, isNotNull);
  });

  test(
    'uses simctl system recording for iOS auto mode when a simulator device ID is provided',
    () {
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'ios',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        iosDeviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      );

      expect(resolution?.implementation, 'simctl');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.system);
      expect(resolution?.fallbackUsed, isFalse);
    },
  );

  test(
    'uses remote native recording for iOS native mode even when a simulator device ID is provided',
    () {
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'ios',
        recording: nativeRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        iosDeviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      );

      expect(resolution?.implementation, 'remote');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.system);
      expect(resolution?.fallbackUsed, isFalse);
    },
  );

  test(
    'uses remote recording for physical iOS device IDs instead of simctl',
    () {
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'ios',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        iosDeviceId: '00008110-0009341C2EF3801E',
      );

      expect(resolution?.implementation, 'remote');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.system);
      expect(resolution?.fallbackUsed, isFalse);
    },
  );

  test('leaves remote recording provenance unclassified', () {
    final remoteAdapter = CockpitRemoteRecordingAdapter(
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
    );
    expect(remoteAdapter, isNot(isA<CockpitRecordingProvenanceProvider>()));

    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
    );
    final resolution = resolver.resolveDetailed(
      platform: 'ios',
      recording: nativeRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      iosDeviceId: '00008110-0009341C2EF3801E',
    );

    final provider = resolution!.adapter! as CockpitRecordingProvenanceProvider;
    expect(provider.recordingProvenance, isNull);
  });

  test('leaves a custom adapter without provenance unclassified', () {
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
    );
    final resolution = resolver.resolveDetailed(
      platform: 'ios',
      recording: autoRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      iosDeviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
    );

    final provider = resolution!.adapter! as CockpitRecordingProvenanceProvider;
    expect(provider.recordingProvenance, isNull);
  });

  test('uses host-screen recording for macOS full mode', () {
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      macosAdapterFactory: (appId, {processId}) => _FakeRecordingAdapter(),
    );

    final resolution = resolver.resolveDetailed(
      platform: 'macos',
      recording: fullRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      platformAppId: 'dev.cockpit.cockpitDemo',
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

    expect(resolution?.implementation, 'macosHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    expect(resolution?.fallbackUsed, isFalse);
  });

  test('uses host-screen recording for macOS auto mode', () {
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      macosAdapterFactory: (appId, {processId}) => _FakeRecordingAdapter(),
    );

    final resolution = resolver.resolveDetailed(
      platform: 'macos',
      recording: autoRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      platformAppId: 'dev.cockpit.cockpitDemo',
    );

    expect(resolution?.implementation, 'macosHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    expect(resolution?.fallbackUsed, isFalse);
  });

  test(
    'falls back to app-window recording when host-screen recording fails to start in auto mode',
    () async {
      final remoteAdapter = _FakeRecordingAdapter();
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) => _ThrowingRecordingAdapter(
          StateError('Screen Recording permission is missing.'),
        ),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        platformAppId: 'dev.cockpit.cockpitDemo',
      );

      expect(resolution?.implementation, 'macosHost');
      final session = await resolution!.adapter!.startRecording(autoRequest);
      final result = await resolution.adapter!.stopRecording();

      expect(session.request, autoRequest);
      expect(remoteAdapter.startCallCount, 1);
      expect(result.effectiveLayer, CockpitRecordingLayer.appWindow);
      expect(result.fallbackUsed, isTrue);
      expect(result.fallbackReason, contains('host-screen'));
      expect(result.fallbackReason, contains('app-window'));
      expect(result.fallbackReason, contains('Screen Recording permission'));
    },
  );

  test(
    'does not fall back when an explicit recording layer fails to start',
    () async {
      final remoteAdapter = _FakeRecordingAdapter();
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) =>
            _ThrowingRecordingAdapter(StateError('host unavailable')),
      );
      const request = CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'strict-host',
        layer: CockpitRecordingLayer.hostScreen,
      );

      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: request,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        platformAppId: 'dev.cockpit.cockpitDemo',
      );

      await expectLater(
        resolution!.adapter!.startRecording(request),
        throwsStateError,
      );
      expect(remoteAdapter.startCallCount, 0);
    },
  );

  test(
    'falls back at runtime when an explicit recording layer allows fallback',
    () async {
      final remoteAdapter = _FakeRecordingAdapter();
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) =>
            _ThrowingRecordingAdapter(StateError('host unavailable')),
      );
      const request = CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'strict-host-with-fallback',
        layer: CockpitRecordingLayer.hostScreen,
        allowFallback: true,
      );

      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: request,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        platformAppId: 'dev.cockpit.cockpitDemo',
      );

      await resolution!.adapter!.startRecording(request);
      final result = await resolution.adapter!.stopRecording();

      expect(remoteAdapter.startCallCount, 1);
      expect(result.effectiveLayer, CockpitRecordingLayer.appWindow);
      expect(result.fallbackUsed, isTrue);
      expect(result.fallbackReason, contains('host-screen'));
      expect(result.fallbackReason, contains('app-window'));
    },
  );

  test(
    'reports every runtime recording fallback failure when no candidate can start',
    () async {
      final remoteAdapter = _ThrowingRecordingAdapter(
        StateError('app window recorder has no active window'),
      );
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => remoteAdapter,
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) => _ThrowingRecordingAdapter(
          StateError('host recorder has no screen input'),
        ),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        platformAppId: 'dev.cockpit.cockpitDemo',
      );

      await expectLater(
        resolution!.adapter!.startRecording(autoRequest),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('host-screen failed to start'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('app-window fallback failed'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('host recorder has no screen input'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('app window recorder has no active window'),
              ),
        ),
      );
    },
  );

  test(
    'exposes custom app-native provenance for an iOS simulator adapter',
    () async {
      final adapter = _AppNativeRecordingAdapter();
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => adapter,
      );
      final resolution = resolver.resolveDetailed(
        platform: 'ios',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        iosDeviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      );

      final provenance =
          resolution!.adapter! as CockpitRecordingProvenanceProvider;
      expect(provenance.recordingProvenance!.implementation, 'ios-app-native');
      expect(
        provenance.recordingProvenance!.sourcePlane,
        CockpitRecordingSourcePlane.app,
      );
      await resolution.adapter!.startRecording(autoRequest);
      expect(provenance.recordingProvenance!.implementation, 'ios-app-native');
    },
  );

  test(
    'switches provenance atomically when runtime recording fallback starts',
    () async {
      final fallbackAdapter = _AppNativeRecordingAdapter();
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => fallbackAdapter,
        macosAdapterFactory: (appId, {processId}) =>
            _ThrowingHostRecordingAdapter(
              StateError('screen permission missing'),
            ),
      );
      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        platformAppId: 'dev.cockpit.demo',
      );
      final provenance =
          resolution!.adapter! as CockpitRecordingProvenanceProvider;

      expect(provenance.recordingProvenance!.implementation, 'macosHost');
      expect(
        provenance.recordingProvenance!.sourcePlane,
        CockpitRecordingSourcePlane.host,
      );
      await resolution.adapter!.startRecording(autoRequest);
      expect(provenance.recordingProvenance!.implementation, 'ios-app-native');
      expect(
        provenance.recordingProvenance!.sourcePlane,
        CockpitRecordingSourcePlane.app,
      );
      final result = await resolution.adapter!.stopRecording();
      expect(result.fallbackUsed, isTrue);
      expect(result.fallbackReason, contains('screen permission missing'));
    },
  );

  test(
    'clears provenance when runtime fallback uses an unknown adapter',
    () async {
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) =>
            _ThrowingHostRecordingAdapter(
              StateError('screen permission missing'),
            ),
      );
      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        platformAppId: 'dev.cockpit.demo',
      );
      final provider =
          resolution!.adapter! as CockpitRecordingProvenanceProvider;

      expect(provider.recordingProvenance, isNotNull);
      await resolution.adapter!.startRecording(autoRequest);
      expect(provider.recordingProvenance, isNull);
    },
  );

  test('uses the host marker when an explicit provider returns null', () {
    final resolver = CockpitRecordingStrategyResolver(
      macosAdapterFactory: (appId, {processId}) =>
          _NullProvenanceHostRecordingAdapter(),
    );
    final resolution = resolver.resolveDetailed(
      platform: 'macos',
      recording: autoRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      platformAppId: 'dev.cockpit.demo',
    );
    final provider = resolution!.adapter! as CockpitRecordingProvenanceProvider;

    expect(provider.recordingProvenance?.implementation, 'macosHost');
    expect(
      provider.recordingProvenance?.sourcePlane,
      CockpitRecordingSourcePlane.host,
    );
  });

  test('uses process-scoped host recording for Windows full mode', () {
    String? capturedAppId;
    int? capturedProcessId;
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      windowsAdapterFactory: (appId, {processId}) {
        capturedAppId = appId;
        capturedProcessId = processId;
        return _FakeRecordingAdapter();
      },
    );

    final resolution = resolver.resolveDetailed(
      platform: 'windows',
      recording: fullRequest,
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

    expect(resolution?.implementation, 'windowsHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    expect(resolution?.fallbackUsed, isFalse);
    expect(capturedAppId, 'cockpit_demo');
    expect(capturedProcessId, 4101);
  });

  test('uses process-scoped host recording for Windows auto mode', () {
    String? capturedAppId;
    int? capturedProcessId;
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      windowsAdapterFactory: (appId, {processId}) {
        capturedAppId = appId;
        capturedProcessId = processId;
        return _FakeRecordingAdapter();
      },
    );

    final resolution = resolver.resolveDetailed(
      platform: 'windows',
      recording: autoRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      platformAppId: 'cockpit_demo',
      processId: 4101,
    );

    expect(resolution?.implementation, 'windowsHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    expect(resolution?.fallbackUsed, isFalse);
    expect(capturedAppId, 'cockpit_demo');
    expect(capturedProcessId, 4101);
  });

  test(
    'uses process-scoped host recording for Windows full mode when only a process id is available',
    () {
      String? capturedAppId;
      int? capturedProcessId;
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        windowsAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return _FakeRecordingAdapter();
        },
      );

      final resolution = resolver.resolveDetailed(
        platform: 'windows',
        recording: fullRequest,
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

      expect(resolution?.implementation, 'windowsHost');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
      expect(resolution?.fallbackUsed, isFalse);
      expect(capturedAppId, 'pid-4101');
      expect(capturedProcessId, 4101);
    },
  );

  test('reuses an active Windows host recording session by process id', () {
    addTearDown(() {
      cockpitClearActiveHostRecordingSession('windows:4101');
    });
    cockpitStoreActiveHostRecordingSession(
      'windows:4101',
      CockpitHostRecordingRuntimeSession(
        process: _FakeProcess(),
        request: autoRequest,
        outputFile: File('/tmp/windows-active-recording.mp4'),
        stderrSubscription: null,
        stopwatch: Stopwatch(),
      ),
    );

    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      windowsAdapterFactory: (appId, {processId}) => _FakeRecordingAdapter(),
    );

    final resolution = resolver.resolveDetailed(
      platform: 'windows',
      recording: autoRequest,
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
        launchedAt: DateTime.utc(2026, 4, 13),
      ),
      preferActiveHostSession: true,
    );

    expect(resolution?.implementation, 'windowsHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
  });

  test('uses process-scoped host recording for Linux full mode', () {
    String? capturedAppId;
    int? capturedProcessId;
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      linuxAdapterFactory: (appId, {processId}) {
        capturedAppId = appId;
        capturedProcessId = processId;
        return _FakeRecordingAdapter();
      },
    );

    final resolution = resolver.resolveDetailed(
      platform: 'linux',
      recording: fullRequest,
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

    expect(resolution?.implementation, 'linuxHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    expect(resolution?.fallbackUsed, isFalse);
    expect(capturedAppId, 'cockpit_demo');
    expect(capturedProcessId, 5101);
  });

  test('uses process-scoped host recording for Linux auto mode', () {
    String? capturedAppId;
    int? capturedProcessId;
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      linuxAdapterFactory: (appId, {processId}) {
        capturedAppId = appId;
        capturedProcessId = processId;
        return _FakeRecordingAdapter();
      },
    );

    final resolution = resolver.resolveDetailed(
      platform: 'linux',
      recording: autoRequest,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      platformAppId: 'cockpit_demo',
      processId: 5101,
    );

    expect(resolution?.implementation, 'linuxHost');
    expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    expect(resolution?.fallbackUsed, isFalse);
    expect(capturedAppId, 'cockpit_demo');
    expect(capturedProcessId, 5101);
  });

  test(
    'uses process-scoped host recording for Linux full mode when only a process id is available',
    () {
      String? capturedAppId;
      int? capturedProcessId;
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        linuxAdapterFactory: (appId, {processId}) {
          capturedAppId = appId;
          capturedProcessId = processId;
          return _FakeRecordingAdapter();
        },
      );

      final resolution = resolver.resolveDetailed(
        platform: 'linux',
        recording: fullRequest,
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

      expect(resolution?.implementation, 'linuxHost');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
      expect(resolution?.fallbackUsed, isFalse);
      expect(capturedAppId, 'pid-5101');
      expect(capturedProcessId, 5101);
    },
  );

  test(
    'falls back to app-window recording when macOS system-layer recording is requested with fallback enabled',
    () {
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: fallbackSystemLayerRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
      );

      expect(resolution?.implementation, 'remote');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.appWindow);
      expect(resolution?.fallbackUsed, isTrue);
      expect(resolution?.fallbackReason, contains('system'));
    },
  );

  test(
    'reports unsupported flutter-layer recording when fallback is disabled',
    () {
      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'ios',
        recording: strictFlutterLayerRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
      );

      expect(resolution?.adapter, isNull);
      expect(resolution?.unsupportedReason, contains('flutter'));
    },
  );

  test('returns null when the script does not request recording', () {
    final resolver = CockpitRecordingStrategyResolver(
      remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
      adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
      macosAdapterFactory: (appId, {processId}) => _FakeRecordingAdapter(),
    );

    final resolution = resolver.resolveDetailed(
      platform: 'android',
      recording: null,
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:47331'),
      ),
      androidDeviceId: 'emulator-5554',
    );

    expect(resolution, isNull);
  });

  test(
    'prefers an active macOS host recording session when stop flow requests active host reuse',
    () {
      addTearDown(() {
        cockpitClearActiveHostRecordingSession(
          'macos:dev.cockpit.cockpitDemo.session',
        );
      });
      cockpitStoreActiveHostRecordingSession(
        'macos:dev.cockpit.cockpitDemo.session',
        CockpitHostRecordingRuntimeSession(
          process: _FakeProcess(),
          request: autoRequest,
          outputFile: File('/tmp/active-recording.mp4'),
          stderrSubscription: null,
          stopwatch: Stopwatch(),
        ),
      );

      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) => _FakeRecordingAdapter(),
      );

      final resolution = resolver.resolveDetailed(
        platform: 'macos',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        sessionHandle: CockpitRemoteSessionHandle(
          platform: 'macos',
          deviceId: 'macos',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          appId: 'dev.cockpit.cockpitDemo.session',
          host: '127.0.0.1',
          hostPort: 47331,
          devicePort: 47331,
          baseUrl: 'http://127.0.0.1:47331',
          launchedAt: DateTime.utc(2026, 4, 13),
        ),
        preferActiveHostSession: true,
      );

      expect(resolution?.implementation, 'macosHost');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.hostScreen);
    },
  );

  test(
    'falls back to remote stop when a persisted macOS host recording session is stale',
    () async {
      const sessionKey = 'macos:dev.cockpit.staleHost';
      addTearDown(() {
        cockpitClearPersistedHostRecordingSession(sessionKey);
      });
      await cockpitPersistHostRecordingSession(
        sessionKey,
        CockpitHostRecordingPersistedSession(
          pid: 999999,
          request: autoRequest,
          outputFilePath: '/tmp/stale-host-recording.mp4',
          startedAt: DateTime.utc(2026, 4, 13),
        ),
      );

      final resolver = CockpitRecordingStrategyResolver(
        remoteAdapterFactory: (client) => _FakeRecordingAdapter(),
        adbAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        simctlAdapterFactory: (deviceId) => _FakeRecordingAdapter(),
        macosAdapterFactory: (appId, {processId}) => _FakeRecordingAdapter(),
      );

      final resolution = await resolver.resolveDetailedForStop(
        platform: 'macos',
        recording: autoRequest,
        client: CockpitRemoteSessionClient(
          baseUri: Uri.parse('http://127.0.0.1:47331'),
        ),
        sessionHandle: CockpitRemoteSessionHandle(
          platform: 'macos',
          deviceId: 'macos',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          appId: 'dev.cockpit.staleHost',
          host: '127.0.0.1',
          hostPort: 47331,
          devicePort: 47331,
          baseUrl: 'http://127.0.0.1:47331',
          launchedAt: DateTime.utc(2026, 4, 13),
        ),
      );

      expect(resolution?.implementation, 'remote');
      expect(resolution?.effectiveLayer, CockpitRecordingLayer.appWindow);
      expect(cockpitReadPersistedHostRecordingSession(sessionKey), isNull);
    },
  );
}

final class _FakeRecordingAdapter implements CockpitRecordingAdapter {
  int startCallCount = 0;
  CockpitRecordingRequest? request;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    startCallCount += 1;
    this.request = request;
    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: request?.purpose,
      recordingKind: CockpitRecordingKind.nativeScreen,
      artifact: const CockpitArtifactRef(
        role: 'recording',
        relativePath: 'recordings/fake.mp4',
      ),
    );
  }
}

final class _ThrowingRecordingAdapter implements CockpitRecordingAdapter {
  const _ThrowingRecordingAdapter(this.error);

  final Object error;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    throw error;
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    throw StateError('Recording was never started.');
  }
}

final class _AppNativeRecordingAdapter
    implements CockpitRecordingAdapter, CockpitRecordingProvenanceProvider {
  CockpitRecordingRequest? request;

  @override
  CockpitRecordingProvenance get recordingProvenance =>
      const CockpitRecordingProvenance(
        implementation: 'ios-app-native',
        sourcePlane: CockpitRecordingSourcePlane.app,
      );

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    this.request = request;
    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: request?.purpose,
      recordingKind: CockpitRecordingKind.nativeScreen,
    );
  }
}

final class _ThrowingHostRecordingAdapter
    implements CockpitHostRecordingAdapter {
  const _ThrowingHostRecordingAdapter(this.error);

  final Object error;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    throw error;
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    throw StateError('Recording was never started.');
  }
}

final class _NullProvenanceHostRecordingAdapter
    implements CockpitHostRecordingAdapter, CockpitRecordingProvenanceProvider {
  @override
  CockpitRecordingProvenance? get recordingProvenance => null;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    throw StateError('Recording was never started.');
  }
}

final class _FakeProcess implements Process {
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  Future<int> get exitCode async => 0;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();
}
