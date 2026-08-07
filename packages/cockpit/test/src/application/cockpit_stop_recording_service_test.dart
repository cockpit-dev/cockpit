import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitStopRecordingService', () {
    test(
      'uses remote runtime recording for iOS apps when no host recording session is active',
      () async {
        final sourceFile = await _recordingSourceFile('ios-native-recording');
        final nativeAdapter = _FakeRecordingAdapter(
          onStop: () async => CockpitRecordingResult(
            state: CockpitRecordingState.completed,
            purpose: CockpitRecordingPurpose.acceptance,
            recordingKind: CockpitRecordingKind.nativeScreen,
            effectiveLayer: CockpitRecordingLayer.system,
            artifact: const CockpitArtifactRef(
              role: 'recording',
              relativePath: 'recordings/ios-native-recording.mp4',
            ),
            durationMs: 2400,
            sourceFilePath: sourceFile.path,
          ),
        );
        final service = CockpitStopRecordingService(
          stopService: CockpitStopRemoteRecordingService(
            stopRecording: (_) async {
              throw StateError(
                'stop service should not be used when resolver selects an adapter',
              );
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => nativeAdapter,
            adbAdapterFactory: (_) => _FakeRecordingAdapter(),
            simctlAdapterFactory: (_) => _FakeRecordingAdapter(
              onStop: () async => throw StateError(
                'simctl should not be used without an active host session',
              ),
            ),
          ),
        );

        final result = await service.stop(
          CockpitStopRecordingRequest(app: _iosAppHandle()),
        );

        expect(result.state, CockpitRecordingState.completed);
        expect(
          result.artifact?.relativePath,
          'recordings/ios-native-recording.mp4',
        );
        expect(result.artifact?.sourcePath, sourceFile.path);
        expect(result.artifact?.byteLength, sourceFile.lengthSync());
        expect(result.effectiveLayer, CockpitRecordingLayer.system);
      },
    );

    test(
      'uses macOS host recording when an active host session exists for the session app id',
      () async {
        final sourceFile = await _recordingSourceFile('macos-host-recording');
        addTearDown(() {
          cockpitClearActiveHostRecordingSession(
            'macos:dev.cockpit.cockpitDemo.session',
          );
        });
        cockpitStoreActiveHostRecordingSession(
          'macos:dev.cockpit.cockpitDemo.session',
          CockpitHostRecordingRuntimeSession(
            process: _FakeProcess(),
            request: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'active-recording',
            ),
            outputFile: File('/tmp/active-recording.mp4'),
            stderrSubscription: null,
            stopwatch: Stopwatch(),
          ),
        );

        var remoteStopCalled = false;
        String? capturedAppId;
        final hostAdapter = _FakeRecordingAdapter(
          onStop: () async => CockpitRecordingResult(
            state: CockpitRecordingState.completed,
            purpose: CockpitRecordingPurpose.acceptance,
            recordingKind: CockpitRecordingKind.nativeScreen,
            effectiveLayer: CockpitRecordingLayer.hostScreen,
            artifact: const CockpitArtifactRef(
              role: 'recording',
              relativePath: 'recordings/macos-host-recording.mp4',
            ),
            durationMs: 3200,
            sourceFilePath: sourceFile.path,
          ),
        );
        final service = CockpitStopRecordingService(
          stopService: CockpitStopRemoteRecordingService(
            stopRecording: (_) async {
              remoteStopCalled = true;
              throw StateError(
                'remote stop should not be used for macOS active host recording',
              );
            },
          ),
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            remoteAdapterFactory: (_) => _FakeRecordingAdapter(
              onStop: () async => throw StateError(
                'remote adapter should not be used when active macOS host recording exists',
              ),
            ),
            adbAdapterFactory: (_) => _FakeRecordingAdapter(),
            simctlAdapterFactory: (_) => _FakeRecordingAdapter(),
            macosAdapterFactory: (appId, {processId}) {
              capturedAppId = appId;
              return hostAdapter;
            },
          ),
        );

        final result = await service.stop(
          CockpitStopRecordingRequest(app: _macosAppHandle()),
        );

        expect(remoteStopCalled, isFalse);
        expect(capturedAppId, 'dev.cockpit.cockpitDemo.session');
        expect(result.state, CockpitRecordingState.completed);
        expect(result.effectiveLayer, CockpitRecordingLayer.hostScreen);
        expect(result.artifact?.byteLength, sourceFile.lengthSync());
        expect(
          result.sessionHandle?.toJson(),
          _macosAppHandle().remoteSession?.toJson(),
        );
      },
    );

    test(
      'marks app-aware completed recording failed when host source file is empty',
      () async {
        final emptySourceFile = await _recordingSourceFile(
          'empty-macos-host-recording',
          contents: '',
        );
        addTearDown(() {
          cockpitClearActiveHostRecordingSession(
            'macos:dev.cockpit.cockpitDemo.session',
          );
        });
        cockpitStoreActiveHostRecordingSession(
          'macos:dev.cockpit.cockpitDemo.session',
          CockpitHostRecordingRuntimeSession(
            process: _FakeProcess(),
            request: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'active-recording',
            ),
            outputFile: File('/tmp/empty-active-recording.mp4'),
            stderrSubscription: null,
            stopwatch: Stopwatch(),
          ),
        );
        final hostAdapter = _FakeRecordingAdapter(
          onStop: () async => CockpitRecordingResult(
            state: CockpitRecordingState.completed,
            purpose: CockpitRecordingPurpose.acceptance,
            recordingKind: CockpitRecordingKind.nativeScreen,
            effectiveLayer: CockpitRecordingLayer.hostScreen,
            artifact: const CockpitArtifactRef(
              role: 'recording',
              relativePath: 'recordings/empty-macos-host-recording.mp4',
            ),
            durationMs: 3200,
            sourceFilePath: emptySourceFile.path,
          ),
        );
        final service = CockpitStopRecordingService(
          recordingStrategyResolver: CockpitRecordingStrategyResolver(
            macosAdapterFactory: (_, {processId}) => hostAdapter,
          ),
        );

        final result = await service.stop(
          CockpitStopRecordingRequest(app: _macosAppHandle()),
        );

        expect(result.state, CockpitRecordingState.failed);
        expect(result.artifact?.byteLength, 0);
        expect(result.artifact?.sourcePath, emptySourceFile.path);
        expect(result.failureReason, contains('source file is empty'));
      },
    );
  });
}

Future<File> _recordingSourceFile(String name, {String? contents}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'flutter_cockpit_stop_recording_test_',
  );
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
  return File('${tempDir.path}${Platform.pathSeparator}$name.mp4')
    ..writeAsStringSync(contents ?? name);
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

final class _FakeRecordingAdapter implements CockpitRecordingAdapter {
  _FakeRecordingAdapter({this.onStop});

  final Future<CockpitRecordingSession> Function(
    CockpitRecordingRequest request,
  )?
  onStart = null;
  final Future<CockpitRecordingResult> Function()? onStop;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
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
