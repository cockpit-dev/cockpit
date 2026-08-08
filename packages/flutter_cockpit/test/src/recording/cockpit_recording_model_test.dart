import 'package:flutter_cockpit/flutter_cockpit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CockpitRecordingMode round-trips through json', () {
    expect(
      CockpitRecordingMode.fromJson(CockpitRecordingMode.full.jsonValue),
      CockpitRecordingMode.full,
    );
  });

  test('CockpitRecordingLayer accepts only canonical wire values', () {
    expect(
      CockpitRecordingLayer.fromJson(
        CockpitRecordingLayer.hostScreen.jsonValue,
      ),
      CockpitRecordingLayer.hostScreen,
    );
    expect(
      () => CockpitRecordingLayer.fromJson('appWindow'),
      throwsArgumentError,
    );
  });

  test('CockpitRecordingPurpose round-trips through json', () {
    expect(
      CockpitRecordingPurpose.fromJson(CockpitRecordingPurpose.acceptance.name),
      CockpitRecordingPurpose.acceptance,
    );
    expect(
      () => CockpitRecordingPurpose.fromJson('diagnostic'),
      throwsArgumentError,
    );
  });

  test('CockpitRecordingState round-trips through json', () {
    expect(
      CockpitRecordingState.fromJson(CockpitRecordingState.recording.name),
      CockpitRecordingState.recording,
    );
  });

  test(
    'CockpitRecordingRequest preserves policy, attachment, and tail stabilization metadata',
    () {
      final request = CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'home_acceptance',
        mode: CockpitRecordingMode.full,
        layer: CockpitRecordingLayer.hostScreen,
        allowFallback: false,
        attachToStep: true,
        tailStabilizationDelay: const Duration(milliseconds: 1450),
      );

      expect(CockpitRecordingRequest.fromJson(request.toJson()), request);
      expect(request.toJson()['mode'], CockpitRecordingMode.full.jsonValue);
      expect(
        request.toJson()['layer'],
        CockpitRecordingLayer.hostScreen.jsonValue,
      );
      expect(request.toJson()['allowFallback'], isFalse);
      expect(request.toJson()['tailStabilizationMs'], 1450);
    },
  );

  test(
    'CockpitRecordingRequest derives fallback defaults from mode and layer',
    () {
      const autoRequest = CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'auto_recording',
      );
      const preciseLayerRequest = CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'flutter_recording',
        layer: CockpitRecordingLayer.flutter,
      );
      const strictNativeRequest = CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'native_recording',
        mode: CockpitRecordingMode.native,
      );

      expect(autoRequest.allowsFallback, isTrue);
      expect(preciseLayerRequest.allowsFallback, isFalse);
      expect(strictNativeRequest.allowsFallback, isFalse);
    },
  );

  test('CockpitRecordingRequest rejects incomplete input', () {
    expect(
      () => CockpitRecordingRequest.fromJson(<String, Object?>{
        'purpose': 'acceptance',
      }),
      throwsFormatException,
    );
  });

  test(
    'CockpitRecordingResult preserves requested, effective, and fallback metadata',
    () {
      final result = CockpitRecordingResult(
        state: CockpitRecordingState.completed,
        purpose: CockpitRecordingPurpose.acceptance,
        recordingKind: CockpitRecordingKind.nativeScreen,
        requestedMode: CockpitRecordingMode.full,
        requestedLayer: CockpitRecordingLayer.system,
        effectiveLayer: CockpitRecordingLayer.hostScreen,
        fallbackUsed: true,
        fallbackReason: 'System-layer recording is unavailable on macOS.',
        artifact: const CockpitArtifactRef(
          role: 'recording',
          relativePath: 'recordings/home_acceptance.mp4',
        ),
        durationMs: 4200,
        bytes: const [1, 2, 3, 4],
      );

      expect(CockpitRecordingResult.fromJson(result.toJson()), result);
      expect(result.toJson()['fallbackUsed'], isTrue);
    },
  );

  test(
    'CockpitRecordingCapabilities preserves supported and preferred layers',
    () {
      final capabilities = CockpitRecordingCapabilities(
        supportsNativeRecording: true,
        preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        supportedLayers: const <CockpitRecordingLayer>[
          CockpitRecordingLayer.appWindow,
          CockpitRecordingLayer.hostScreen,
        ],
        preferredLayer: CockpitRecordingLayer.appWindow,
        recordingLimitations: const <String>['Window chrome is excluded.'],
      );

      expect(
        CockpitRecordingCapabilities.fromJson(capabilities.toJson()),
        capabilities,
      );
      expect(capabilities.toJson()['supportedLayers'], <String>[
        'app-window',
        'host-screen',
      ]);
    },
  );

  test('CockpitRunManifest preserves recording delivery metadata', () {
    final manifest = CockpitRunManifest(
      sessionId: 'session-recording',
      taskId: 'task-home',
      platform: 'android',
      status: CockpitTaskStatus.completed,
      startedAt: DateTime.utc(2026, 3, 20, 13),
      finishedAt: DateTime.utc(2026, 3, 20, 13, 2),
      recordingCount: 1,
      nativeRecordingCount: 1,
      deliveryVideoReady: true,
    );

    expect(CockpitRunManifest.fromJson(manifest.toJson()), manifest);
  });

  test('CockpitContextBundle preserves delivery video metadata', () {
    final bundle = CockpitContextBundle(
      manifest: CockpitRunManifest(
        sessionId: 'session-recording',
        taskId: 'task-home',
        platform: 'ios',
        status: CockpitTaskStatus.completed,
        startedAt: DateTime.utc(2026, 3, 20, 13),
        finishedAt: DateTime.utc(2026, 3, 20, 13, 1),
        recordingCount: 1,
        nativeRecordingCount: 1,
        deliveryVideoReady: true,
      ),
      environment: const CockpitEnvironment(
        platform: 'ios',
        flutterVersion: '3.38.9',
        dartVersion: '3.10.8',
      ),
      acceptanceMarkdown: '# Acceptance\n\nRecorded.',
      handoff: const {'status': 'completed'},
      delivery: const <String, Object?>{
        'primaryRecordingRef': 'recordings/home_acceptance.mp4',
        'videoAttachmentRefs': ['recordings/home_acceptance.mp4'],
        'deliveryVideoReady': true,
      },
    );

    expect(CockpitContextBundle.fromJson(bundle.toJson()), bundle);
  });
}
