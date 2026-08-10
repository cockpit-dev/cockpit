import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CockpitCaptureKind round-trips through json', () {
    for (final kind in <CockpitCaptureKind>[
      CockpitCaptureKind.hostSystem,
      CockpitCaptureKind.appNative,
      CockpitCaptureKind.flutterView,
      CockpitCaptureKind.nativeAcceptance,
    ]) {
      expect(CockpitCaptureKind.fromJson(kind.name), kind);
    }
  });

  test('CockpitCaptureProfile round-trips through json', () {
    expect(
      CockpitCaptureProfile.fromJson(
        CockpitCaptureProfile.nativePreferred.name,
      ),
      CockpitCaptureProfile.nativePreferred,
    );
  });

  test('Web automatic acceptance capture prefers Flutter', () {
    expect(
      cockpitCaptureProfilePrefersNative(
        CockpitCaptureProfile.acceptance,
        isWeb: true,
      ),
      isFalse,
    );
    expect(
      cockpitCaptureProfilePrefersNative(
        CockpitCaptureProfile.nativePreferred,
        isWeb: true,
      ),
      isTrue,
    );
  });

  test('automatic acceptance capture is native only on mobile', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      expect(
        cockpitCaptureProfilePrefersNative(
          CockpitCaptureProfile.acceptance,
          isWeb: false,
          platform: platform,
        ),
        isTrue,
        reason: platform.name,
      );
    }
    for (final platform in <TargetPlatform>[
      TargetPlatform.fuchsia,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        cockpitCaptureProfilePrefersNative(
          CockpitCaptureProfile.acceptance,
          isWeb: false,
          platform: platform,
        ),
        isFalse,
        reason: platform.name,
      );
    }
  });

  test('CockpitScreenshotRequest preserves capture routing intent', () {
    const request = CockpitScreenshotRequest(
      reason: CockpitScreenshotReason.acceptance,
      name: 'native-proof',
      includeSnapshot: true,
      attachToStep: true,
      profile: CockpitCaptureProfile.nativePreferred,
      allowFallback: false,
      cropLocator: CockpitLocator(text: 'Settings'),
    );

    expect(CockpitScreenshotRequest.fromJson(request.toJson()), request);
    expect(request.allowsFallback, isFalse);
    expect(request.copyWith(allowFallback: true).allowsFallback, isTrue);
    final automatic = request.copyWith(profile: null, allowFallback: null);
    expect(automatic.profile, isNull);
    expect(automatic.allowFallback, isNull);
    expect(automatic.cropLocator?.text, 'Settings');
  });

  test('CockpitScreenshotRequest keeps routing fields optional by default', () {
    const request = CockpitScreenshotRequest(
      reason: CockpitScreenshotReason.afterAction,
      name: 'after-action',
    );

    expect(request.toJson(), isNot(contains('profile')));
    expect(request.toJson(), isNot(contains('allowFallback')));
    expect(request.allowsFallback, isTrue);
  });

  test('CockpitCommandResult preserves capture routing metadata', () {
    final result = CockpitCommandResult(
      success: true,
      commandId: 'cmd-capture',
      commandType: CockpitCommandType.captureScreenshot,
      durationMs: 65,
      artifacts: const [
        CockpitArtifactRef(
          role: 'screenshot',
          relativePath: 'screenshots/acceptance_home.png',
        ),
      ],
      requestedCaptureProfile: CockpitCaptureProfile.acceptance,
      resolvedCaptureKind: CockpitCaptureKind.nativeAcceptance,
      usedCaptureFallback: true,
      degradationReason: 'native capture unavailable, fell back to Flutter',
    );

    expect(CockpitCommandResult.fromJson(result.toJson()), result);
  });

  test(
    'cockpitScreenshotRelativePathFor emits sorted readable screenshot paths',
    () {
      final path = cockpitScreenshotRelativePathFor(
        const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: '../Home Screen',
        ),
        now: DateTime.utc(2026, 5, 30, 6, 3, 4, 5, 6),
      );

      expect(
        path,
        'screenshots/20260530T060304005006Z_home_screen_acceptance.png',
      );
    },
  );

  test('CockpitRunManifest preserves delivery metadata', () {
    final manifest = CockpitRunManifest(
      sessionId: 'session-acceptance',
      taskId: 'task-home',
      platform: 'android',
      status: CockpitTaskStatus.completed,
      startedAt: DateTime.utc(2026, 3, 20, 12),
      finishedAt: DateTime.utc(2026, 3, 20, 12, 1),
      nativeScreenshotCount: 1,
      flutterScreenshotCount: 2,
      deliveryArtifactsReady: true,
    );

    expect(CockpitRunManifest.fromJson(manifest.toJson()), manifest);
  });

  test(
    'CockpitNativeCapture converts platform bytes into a screenshot artifact',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channel = MethodChannel('dev.cockpit.flutter_cockpit/capture');

      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'captureAcceptanceScreenshot');
        return <String, Object?>{
          'bytes': Uint8List.fromList(<int>[137, 80, 78, 71]),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final capture = await CockpitNativeCapture(channel: channel).capture(
        request: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'home',
          includeSnapshot: true,
          attachToStep: true,
        ),
        profile: CockpitCaptureProfile.acceptance,
        snapshot: CockpitSnapshot(routeName: '/home'),
      );

      expect(capture.artifact.relativePath, contains('screenshots/'));
      expect(
        capture.artifact.relativePath,
        matches(RegExp(r'^screenshots/\d{8}T\d{12}Z_home_acceptance\.png$')),
      );
      expect(capture.snapshot?.routeName, '/home');
      expect(capture.bytes, <int>[137, 80, 78, 71]);
    },
  );

  test('CockpitNativeCapture queries native capture availability', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channel = MethodChannel('dev.cockpit.flutter_cockpit/capture');

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'queryNativeCaptureAvailability');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final isAvailable = await CockpitNativeCapture(
      channel: channel,
    ).queryAvailability();

    expect(isAvailable, isTrue);
  });
}
