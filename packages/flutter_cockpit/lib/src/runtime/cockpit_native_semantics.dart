import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class CockpitNativeSemantics {
  const CockpitNativeSemantics({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName =
      'dev.cockpit.flutter_cockpit/accessibility';

  final MethodChannel _channel;

  Future<void> enable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'enableSemantics',
    );
    if (result?['enabled'] != true) {
      throw PlatformException(
        code: 'semanticsUnavailable',
        message: 'macOS native semantics did not become enabled.',
      );
    }
  }
}
