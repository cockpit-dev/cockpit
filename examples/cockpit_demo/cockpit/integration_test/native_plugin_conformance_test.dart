import 'dart:ui' as ui;

import 'package:cockpit_demo/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runConsentFlow = bool.fromEnvironment(
    'COCKPIT_NATIVE_CONSENT',
    defaultValue: false,
  );

  testWidgets('public native plugin conformance', (tester) async {
    final report = <String, Object?>{
      'status': 'passed',
      'platform': _platformName(),
      'capabilitySnapshot': <String, Object?>{},
      'capture': <String, Object?>{},
      'recording': <String, Object?>{},
      'assertions': <String, Object?>{},
    };

    try {
      app.main();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final nativeCapture = const CockpitNativeCapture();
      final nativeRecording = const CockpitNativeRecording();
      final captureAvailable = await nativeCapture.queryAvailability();
      final capabilities = await nativeRecording.queryCapabilities();
      report['capabilitySnapshot'] = <String, Object?>{
        'nativeCaptureAvailable': captureAvailable,
        ...capabilities.toJson(),
      };

      final captureReport = <String, Object?>{
        'available': captureAvailable,
        'validated': false,
      };
      if (captureAvailable) {
        final request = const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'native_plugin_conformance',
          profile: CockpitCaptureProfile.acceptance,
          allowFallback: false,
        );
        final screenshot = await nativeCapture.capture(
          request: request,
          profile: CockpitCaptureProfile.acceptance,
        );
        final bytes = screenshot.bytes;
        expect(bytes, isA<Uint8List>());
        expect(bytes, isNotEmpty);
        expect(await _hasVisiblePixels(bytes), isTrue);
        captureReport['byteLength'] = bytes.length;
        captureReport['validated'] = true;
      } else {
        captureReport['reason'] = 'nativeCaptureUnavailable';
      }
      report['capture'] = captureReport;

      final recordingReport = <String, Object?>{
        'supportsNativeRecording': capabilities.supportsNativeRecording,
        'duplicateStartRejected': false,
        'postFinalizeStopRejected': false,
      };
      if (capabilities.supportsNativeRecording && runConsentFlow) {
        final request = CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'native_plugin_conformance',
          mode: CockpitRecordingMode.native,
          layer: capabilities.preferredLayer,
          allowFallback: false,
        );
        final session = await nativeRecording.startRecording(request: request);
        expect(session.state, CockpitRecordingState.recording);

        try {
          await nativeRecording.startRecording(request: request);
        } on Object catch (error) {
          recordingReport['duplicateStartRejected'] = true;
          recordingReport['duplicateStartError'] = '$error';
        }
        expect(recordingReport['duplicateStartRejected'], isTrue);

        await tester.pump(const Duration(seconds: 3));
        final stopped = await nativeRecording.stopRecording(session: session);
        expect(stopped.state, CockpitRecordingState.completed);
        expect(stopped.artifact, isNotNull);
        recordingReport['completed'] = true;
        recordingReport['recordingKind'] = stopped.recordingKind?.name;
        recordingReport['sourceFilePath'] = stopped.sourceFilePath;
        recordingReport['durationMs'] = stopped.durationMs;

        final postFinalize = await nativeRecording.stopRecording(
          session: session,
        );
        recordingReport['postFinalizeStopRejected'] =
            postFinalize.state == CockpitRecordingState.failed;
        recordingReport['postFinalizeStopState'] = postFinalize.state.name;
        expect(recordingReport['postFinalizeStopRejected'], isTrue);
      } else {
        recordingReport['unavailableBranchTested'] = true;
        recordingReport['reason'] = capabilities.supportsNativeRecording
            ? 'recordingConsentRequired'
            : 'recordingUnavailable';
        // MediaProjection/screen-recording prompts belong to the host/system
        // plane. They cannot be accepted from an in-app integration isolate;
        // run this test with COCKPIT_NATIVE_CONSENT=true only when the host
        // Cockpit driver is configured to resolve the system prompt.
        if (kIsWeb) {
          expect(capabilities.supportsNativeRecording, isFalse);
          expect(captureAvailable, isFalse);
        }
      }
      report['recording'] = recordingReport;
      report['assertions'] = <String, Object?>{
        'capabilitySnapshot': true,
        'acceptanceScreenshotValidation': captureReport['validated'] == true,
        'acceptanceVideoValidation':
            recordingReport['completed'] == true ||
            recordingReport['unavailableBranchTested'] == true,
      };
    } catch (error, stackTrace) {
      report['status'] = 'failed';
      report['error'] = '$error';
      report['stackTrace'] = '$stackTrace';
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    binding.reportData = <String, dynamic>{'nativePluginConformance': report};
    expect(report['status'], 'passed');
  });
}

Future<bool> _hasVisiblePixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      return false;
    }
    for (var index = 3; index < data.lengthInBytes; index += 4) {
      if (data.getUint8(index) != 0) {
        return true;
      }
    }
    return false;
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

String _platformName() {
  if (kIsWeb) {
    return 'web';
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.linux => 'linux',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
