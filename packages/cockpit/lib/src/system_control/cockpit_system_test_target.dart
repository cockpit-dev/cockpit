import 'package:cockpit_protocol/cockpit_protocol.dart';

final class CockpitSystemTestTarget {
  CockpitSystemTestTarget({
    required this.platform,
    required this.deviceId,
    required this.appId,
    this.targetKind = CockpitTargetKind.nativeApp,
    this.processId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : metadata = Map<String, Object?>.unmodifiable(metadata);

  final String platform;
  final String deviceId;
  final String? appId;
  final CockpitTargetKind targetKind;
  final int? processId;
  final Map<String, Object?> metadata;
}
