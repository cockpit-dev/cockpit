import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_cockpit_web_handlers.dart';

final class FlutterCockpitWeb {
  static void registerWith(Registrar registrar) {
    final captureChannel = MethodChannel(
      cockpitWebCaptureChannelName,
      const StandardMethodCodec(),
      registrar,
    );
    final recordingChannel = MethodChannel(
      cockpitWebRecordingChannelName,
      const StandardMethodCodec(),
      registrar,
    );
    final viewportChannel = MethodChannel(
      cockpitWebViewportChannelName,
      const StandardMethodCodec(),
      registrar,
    );
    captureChannel.setMethodCallHandler(cockpitWebHandleCaptureMethodCall);
    recordingChannel.setMethodCallHandler(cockpitWebHandleRecordingMethodCall);
    viewportChannel.setMethodCallHandler(cockpitWebHandleViewportMethodCall);
  }
}
