import 'package:flutter/services.dart';

import '../recording/cockpit_recording_kind.dart';
import '../recording/cockpit_recording_state.dart';

const String cockpitWebCaptureChannelName =
    'dev.cockpit.flutter_cockpit/capture';
const String cockpitWebRecordingChannelName =
    'dev.cockpit.flutter_cockpit/recording';
const String cockpitWebViewportChannelName =
    'dev.cockpit.flutter_cockpit/viewport';
const String cockpitWebNativeCaptureUnavailableMessage =
    'Native acceptance capture is unavailable on web. Use Flutter view capture instead.';
const String cockpitWebNativeRecordingUnavailableMessage =
    'Native in-app recording is unavailable on web. Use host-side recording through cockpit instead.';

Future<Object?> cockpitWebHandleCaptureMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'queryNativeCaptureAvailability':
      return false;
    case 'captureAcceptanceScreenshot':
      throw PlatformException(
        code: 'nativeCaptureUnavailable',
        message: cockpitWebNativeCaptureUnavailableMessage,
      );
  }

  throw PlatformException(
    code: 'unimplemented',
    message: 'Method ${call.method} is not implemented on web.',
  );
}

Future<Object?> cockpitWebHandleRecordingMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'queryRecordingCapabilities':
      return <String, Object?>{
        'supportsNativeRecording': false,
        'preferredAcceptanceRecordingKind':
            CockpitRecordingKind.nativeScreen.name,
        'supportedLayers': const <String>[],
        'recordingLimitations': <String>[
          cockpitWebNativeRecordingUnavailableMessage,
        ],
      };
    case 'startRecording':
      throw PlatformException(
        code: 'nativeRecordingUnavailable',
        message: cockpitWebNativeRecordingUnavailableMessage,
      );
    case 'stopRecording':
      return <String, Object?>{
        'state': CockpitRecordingState.failed.name,
        'recordingKind': CockpitRecordingKind.nativeScreen.name,
        'effectiveLayer': 'host-screen',
        'failureReason': 'recordingNotActive',
      };
  }

  throw PlatformException(
    code: 'unimplemented',
    message: 'Method ${call.method} is not implemented on web.',
  );
}

Future<Object?> cockpitWebHandleViewportMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'queryViewportAvailability':
      return <String, Object?>{
        'available': false,
        'reason': 'browserOwnsViewport',
        'alternatives': const <String>['managedBrowserViewport'],
      };
    case 'resizeViewport':
      throw PlatformException(
        code: 'browserOwnsViewport',
        message:
            'A web app cannot resize its own viewport. Use the Cockpit managed browser viewport.',
        details: const <String, Object?>{
          'alternatives': <String>['managedBrowserViewport'],
        },
      );
  }

  throw PlatformException(
    code: 'unimplemented',
    message: 'Method ${call.method} is not implemented on web.',
  );
}
