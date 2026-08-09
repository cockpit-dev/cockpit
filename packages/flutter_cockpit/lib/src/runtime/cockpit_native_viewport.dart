import 'package:flutter/services.dart';

final class CockpitViewportAvailability {
  CockpitViewportAvailability({
    required this.available,
    required this.platform,
    this.reason,
    List<String> alternatives = const <String>[],
  }) : alternatives = List<String>.unmodifiable(alternatives);

  final bool available;
  final String platform;
  final String? reason;
  final List<String> alternatives;
}

final class CockpitNativeViewportResizeResult {
  CockpitNativeViewportResizeResult({
    required this.accepted,
    this.reason,
    List<String> alternatives = const <String>[],
  }) : alternatives = List<String>.unmodifiable(alternatives);

  final bool accepted;
  final String? reason;
  final List<String> alternatives;
}

final class CockpitNativeViewport {
  const CockpitNativeViewport({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.cockpit.flutter_cockpit/viewport';

  final MethodChannel _channel;

  Future<CockpitViewportAvailability> queryAvailability({
    required String platform,
  }) async {
    try {
      final payload = await _channel.invokeMethod<Object?>(
        'queryViewportAvailability',
      );
      if (payload is! Map<Object?, Object?>) {
        throw StateError('Viewport availability returned an invalid payload.');
      }
      return CockpitViewportAvailability(
        available: payload['available'] == true,
        platform: platform,
        reason: payload['reason'] as String?,
        alternatives:
            (payload['alternatives'] as List<Object?>? ?? const <Object?>[])
                .whereType<String>()
                .toList(growable: false),
      );
    } on MissingPluginException {
      return CockpitViewportAvailability(
        available: false,
        platform: platform,
        reason: 'viewportPluginUnavailable',
        alternatives: const <String>['rebuildDesktopApp'],
      );
    } on PlatformException catch (error) {
      return CockpitViewportAvailability(
        available: false,
        platform: platform,
        reason: error.code,
        alternatives: const <String>['rebuildDesktopApp'],
      );
    }
  }

  Future<CockpitNativeViewportResizeResult> resize({
    required int width,
    required int height,
  }) async {
    final payload = await _channel.invokeMethod<Object?>(
      'resizeViewport',
      <String, Object?>{'width': width, 'height': height},
    );
    if (payload is! Map<Object?, Object?> || payload['accepted'] is! bool) {
      throw StateError('Native viewport resize returned an invalid payload.');
    }
    return CockpitNativeViewportResizeResult(
      accepted: payload['accepted'] as bool,
      reason: payload['reason'] as String?,
      alternatives:
          (payload['alternatives'] as List<Object?>? ?? const <Object?>[])
              .whereType<String>()
              .toList(growable: false),
    );
  }
}
