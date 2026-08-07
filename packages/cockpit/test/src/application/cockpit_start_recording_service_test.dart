import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/application/cockpit_app_reference_resolver.dart';
import 'package:cockpit/src/application/cockpit_session_registry.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitStartRecordingService', () {
    test(
      'appId-based recording prefers the most recently updated remote session over an older development session',
      () async {
        final registry = CockpitSessionRegistry(
          now: _clockFrom(<DateTime>[
            DateTime.utc(2026, 5, 10, 10, 0, 0),
            DateTime.utc(2026, 5, 10, 10, 5, 0),
          ]),
        );
        registry.recordDevelopmentSession(
          handle: CockpitDevelopmentSessionHandle(
            developmentSessionId: 'dev-session-1',
            platform: 'android',
            deviceId: 'emulator-5554',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            appId: 'dev.example.app',
            appBaseUrl: 'http://127.0.0.1:57331',
            supervisorBaseUrl: 'http://127.0.0.1:59331',
            launchedAt: DateTime.utc(2026, 5, 10),
            reloadGeneration: 0,
          ),
          status: CockpitDevelopmentSessionStatus(
            developmentSessionId: 'dev-session-1',
            state: CockpitDevelopmentSessionState.ready,
            appReachable: true,
            remoteSessionReachable: true,
            reloadGeneration: 0,
            lastStatusAt: DateTime.utc(2026, 5, 10, 10, 0, 0),
          ),
        );
        registry.recordRemoteSession(
          handle: CockpitRemoteSessionHandle(
            platform: 'android',
            deviceId: 'emulator-5554',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            appId: 'dev.example.app',
            host: '127.0.0.1',
            hostPort: 58331,
            devicePort: 47331,
            baseUrl: 'http://127.0.0.1:58331',
            launchedAt: DateTime.utc(2026, 5, 10),
          ),
          status: _androidRemoteStatus(),
          recommendedNextStep: 'ready',
        );

        var remoteStartCalled = false;
        final hostAdapter = _FakeRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
        );
        final service = CockpitStartRecordingService(
          registry: registry,
          appReferenceResolver: CockpitAppReferenceResolver(
            registry: registry,
            portForwarder: CockpitAndroidPortForwarder(
              processRunner: (_, _) async => ProcessResult(
                0,
                0,
                'emulator-5554 tcp:58331 tcp:47331\n',
                '',
              ),
              hostPortAllocator: () async => 58331,
              hostPortAvailabilityChecker: (_) async => true,
            ),
          ),
          startService: CockpitStartRemoteRecordingService(
            startRecording: (_, _) async {
              remoteStartCalled = true;
              throw StateError('remote start should not be used');
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => _FakeRecordingAdapter(),
            adbAdapterFactory: (_) => hostAdapter,
            simctlAdapterFactory: (_) => _FakeRecordingAdapter(),
          ),
        );

        final result = await service.start(
          const CockpitStartRecordingRequest(
            appId: 'dev.example.app',
            recording: CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'latest-remote-session',
            ),
          ),
        );

        expect(remoteStartCalled, isFalse);
        expect(result.recordingSession.state, CockpitRecordingState.recording);
        expect(
          hostAdapter.startedRequests.single.name,
          'latest-remote-session',
        );
      },
    );

    test(
      'uses adb host recording for Android apps when auto mode has a device handle',
      () async {
        var remoteStartCalled = false;
        final hostAdapter = _FakeRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
        );
        final service = CockpitStartRecordingService(
          startService: CockpitStartRemoteRecordingService(
            startRecording: (_, _) async {
              remoteStartCalled = true;
              throw StateError(
                'remote start should not be used for Android host recording',
              );
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => _FakeRecordingAdapter(),
            adbAdapterFactory: (_) => hostAdapter,
            simctlAdapterFactory: (_) => _FakeRecordingAdapter(),
          ),
        );

        final result = await service.start(
          CockpitStartRecordingRequest(
            app: _androidAppHandle(),
            recording: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'android-host-recording',
            ),
          ),
        );

        expect(remoteStartCalled, isFalse);
        expect(result.recordingSession.state, CockpitRecordingState.recording);
        expect(
          hostAdapter.startedRequests.single.name,
          'android-host-recording',
        );
      },
    );

    test(
      'uses simctl host recording for iOS apps instead of remote runtime recording',
      () async {
        var remoteStartCalled = false;
        final hostAdapter = _FakeRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
        );
        final service = CockpitStartRecordingService(
          startService: CockpitStartRemoteRecordingService(
            startRecording: (_, _) async {
              remoteStartCalled = true;
              throw StateError(
                'remote start should not be used for iOS host recording',
              );
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => _FakeRecordingAdapter(),
            adbAdapterFactory: (_) => _FakeRecordingAdapter(),
            simctlAdapterFactory: (_) => hostAdapter,
          ),
        );

        final result = await service.start(
          CockpitStartRecordingRequest(
            app: _iosAppHandle(),
            recording: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'ios-host-recording',
            ),
          ),
        );

        expect(remoteStartCalled, isFalse);
        expect(result.recordingSession.state, CockpitRecordingState.recording);
        expect(hostAdapter.startedRequests.single.name, 'ios-host-recording');
      },
    );

    test('uses remote native recording for iOS native mode', () async {
      var remoteStartCalled = false;
      final nativeAdapter = _FakeRecordingAdapter(
        onStart: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
      );
      final simctlAdapter = _FakeRecordingAdapter(
        onStart: (_) async =>
            throw StateError('simctl should not be used for native mode'),
      );
      final service = CockpitStartRecordingService(
        startService: CockpitStartRemoteRecordingService(
          startRecording: (_, _) async {
            remoteStartCalled = true;
            throw StateError(
              'remote start service should not be used when resolver selects a native adapter',
            );
          },
        ),
        recordingStrategyResolver: CockpitRecordingStrategyResolver(
          remoteAdapterFactory: (_) => nativeAdapter,
          adbAdapterFactory: (_) => _FakeRecordingAdapter(),
          simctlAdapterFactory: (_) => simctlAdapter,
        ),
      );

      final result = await service.start(
        CockpitStartRecordingRequest(
          app: _iosAppHandle(),
          recording: const CockpitRecordingRequest(
            purpose: CockpitRecordingPurpose.acceptance,
            name: 'ios-native-recording',
            mode: CockpitRecordingMode.native,
          ),
        ),
      );

      expect(remoteStartCalled, isFalse);
      expect(result.recordingSession.state, CockpitRecordingState.recording);
      expect(
        nativeAdapter.startedRequests.single.mode,
        CockpitRecordingMode.native,
      );
    });

    test(
      'uses macOS host recording with the resolved platform app id for full mode',
      () async {
        var remoteStartCalled = false;
        String? capturedAppId;
        final hostAdapter = _FakeRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
        );
        final service = CockpitStartRecordingService(
          startService: CockpitStartRemoteRecordingService(
            startRecording: (_, _) async {
              remoteStartCalled = true;
              throw StateError(
                'remote start should not be used for macOS full host recording',
              );
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => _FakeRecordingAdapter(),
            adbAdapterFactory: (_) => _FakeRecordingAdapter(),
            simctlAdapterFactory: (_) => _FakeRecordingAdapter(),
            macosAdapterFactory: (appId, {processId}) {
              capturedAppId = appId;
              return hostAdapter;
            },
          ),
        );

        final result = await service.start(
          CockpitStartRecordingRequest(
            app: _macosAppHandle(),
            recording: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'macos-host-recording',
              mode: CockpitRecordingMode.full,
            ),
          ),
        );

        expect(remoteStartCalled, isFalse);
        expect(capturedAppId, 'dev.cockpit.cockpitDemo.host');
        expect(result.recordingSession.state, CockpitRecordingState.recording);
        expect(
          result.sessionHandle?.toJson(),
          _macosAppHandle().remoteSession?.toJson(),
        );
        expect(hostAdapter.startedRequests.single.name, 'macos-host-recording');
      },
    );

    test(
      'uses process-scoped Windows host recording when the app handle carries a process id without a remote session',
      () async {
        var remoteStartCalled = false;
        String? capturedAppId;
        int? capturedProcessId;
        final hostAdapter = _FakeRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
        );
        final service = CockpitStartRecordingService(
          startService: CockpitStartRemoteRecordingService(
            startRecording: (_, _) async {
              remoteStartCalled = true;
              throw StateError(
                'remote start should not be used for Windows host recording',
              );
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => _FakeRecordingAdapter(),
            adbAdapterFactory: (_) => _FakeRecordingAdapter(),
            simctlAdapterFactory: (_) => _FakeRecordingAdapter(),
            windowsAdapterFactory: (appId, {processId}) {
              capturedAppId = appId;
              capturedProcessId = processId;
              return hostAdapter;
            },
          ),
        );

        final result = await service.start(
          CockpitStartRecordingRequest(
            app: CockpitAppHandle(
              appId: 'windows-app',
              platformAppId: 'cockpit_demo',
              processId: 4101,
              mode: CockpitAppMode.automation,
              platform: 'windows',
              deviceId: 'windows',
              projectDir: '/workspace/examples/cockpit_demo',
              target: 'cockpit/main.dart',
              baseUrl: 'http://127.0.0.1:47331',
              launchedAt: DateTime.utc(2026, 4, 17),
            ),
            recording: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'windows-host-recording',
              mode: CockpitRecordingMode.full,
            ),
          ),
        );

        expect(remoteStartCalled, isFalse);
        expect(capturedAppId, 'cockpit_demo');
        expect(capturedProcessId, 4101);
        expect(result.recordingSession.state, CockpitRecordingState.recording);
        expect(
          hostAdapter.startedRequests.single.name,
          'windows-host-recording',
        );
      },
    );
  });
}

DateTime Function() _clockFrom(List<DateTime> instants) {
  var index = 0;
  return () {
    final value = instants[index];
    if (index < instants.length - 1) {
      index += 1;
    }
    return value;
  };
}

CockpitAppHandle _androidAppHandle() {
  return CockpitAppHandle(
    appId: 'android-app',
    mode: CockpitAppMode.development,
    platform: 'android',
    deviceId: 'emulator-5554',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    baseUrl: 'http://127.0.0.1:47331',
    launchedAt: DateTime.utc(2026, 4, 13),
  );
}

CockpitRemoteSessionStatus _androidRemoteStatus() {
  return CockpitRemoteSessionStatus(
    sessionId: 'session-1',
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
    ),
    recordingCapabilities: CockpitRecordingCapabilities(
      supportsNativeRecording: true,
      preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
      supportedLayers: const <CockpitRecordingLayer>[
        CockpitRecordingLayer.system,
      ],
    ),
    snapshot: CockpitSnapshot(
      routeName: '/home',
      summary: const CockpitSnapshotSummary(
        visibleTargetCount: 0,
        targetsWithCockpitIdCount: 0,
        targetsWithTextCount: 0,
        styleDetailsIncluded: false,
        diagnosticPropertiesIncluded: false,
        ancestorSummariesIncluded: false,
        rebuildSummaryIncluded: false,
        accessibilitySummaryIncluded: false,
      ),
    ),
  );
}

CockpitAppHandle _iosAppHandle() {
  return CockpitAppHandle(
    appId: 'ios-app',
    mode: CockpitAppMode.development,
    platform: 'ios',
    deviceId: 'FC5B7D0F-B7FB-4A7A-B1B0-FF28BC289BC2',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    baseUrl: 'http://127.0.0.1:47331',
    launchedAt: DateTime.utc(2026, 4, 13),
  );
}

CockpitAppHandle _macosAppHandle() {
  return CockpitAppHandle(
    appId: 'macos-app',
    platformAppId: 'dev.cockpit.cockpitDemo.host',
    mode: CockpitAppMode.automation,
    platform: 'macos',
    deviceId: 'macos',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    baseUrl: 'http://127.0.0.1:47331',
    remoteSession: CockpitRemoteSessionHandle(
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
    launchedAt: DateTime.utc(2026, 4, 13),
  );
}

final class _FakeRecordingAdapter implements CockpitRecordingAdapter {
  _FakeRecordingAdapter({this.onStart});

  final Future<CockpitRecordingSession> Function(
    CockpitRecordingRequest request,
  )?
  onStart;
  final Future<CockpitRecordingResult> Function()? onStop = null;
  final List<CockpitRecordingRequest> startedRequests =
      <CockpitRecordingRequest>[];

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    startedRequests.add(request);
    final onStart = this.onStart;
    if (onStart != null) {
      return onStart(request);
    }
    throw UnimplementedError();
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    final onStop = this.onStop;
    if (onStop != null) {
      return onStop();
    }
    throw UnimplementedError();
  }
}
