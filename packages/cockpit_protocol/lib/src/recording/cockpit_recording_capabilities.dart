import 'package:collection/collection.dart';

import 'cockpit_recording_kind.dart';
import 'cockpit_recording_layer.dart';

final class CockpitRecordingCapabilities {
  /// Creates a CockpitRecordingCapabilities.
  CockpitRecordingCapabilities({
    required this.supportsNativeRecording,
    this.preferredAcceptanceRecordingKind,
    List<CockpitRecordingLayer> supportedLayers =
        const <CockpitRecordingLayer>[],
    this.preferredLayer,
    List<String> recordingLimitations = const <String>[],
  }) : supportedLayers = List.unmodifiable(supportedLayers),
       recordingLimitations = List.unmodifiable(recordingLimitations);

  final bool supportsNativeRecording;
  final CockpitRecordingKind? preferredAcceptanceRecordingKind;
  final List<CockpitRecordingLayer> supportedLayers;
  final CockpitRecordingLayer? preferredLayer;
  final List<String> recordingLimitations;

  static const ListEquality<String> _stringListEquality =
      ListEquality<String>();
  static const ListEquality<CockpitRecordingLayer> _layerListEquality =
      ListEquality<CockpitRecordingLayer>();

  /// Encodes this CockpitRecordingCapabilities as a JSON object.
  Map<String, Object?> toJson() => {
    'supportsNativeRecording': supportsNativeRecording,
    'preferredAcceptanceRecordingKind': preferredAcceptanceRecordingKind?.name,
    if (supportedLayers.isNotEmpty)
      'supportedLayers': supportedLayers
          .map((layer) => layer.jsonValue)
          .toList(growable: false),
    if (preferredLayer != null) 'preferredLayer': preferredLayer!.jsonValue,
    'recordingLimitations': recordingLimitations,
  };

  /// Decodes a CockpitRecordingCapabilities from a JSON object.
  factory CockpitRecordingCapabilities.fromJson(Map<String, Object?> json) {
    final preferredKind = json['preferredAcceptanceRecordingKind'];

    return CockpitRecordingCapabilities(
      supportsNativeRecording:
          json['supportsNativeRecording'] as bool? ?? false,
      preferredAcceptanceRecordingKind: preferredKind == null
          ? null
          : CockpitRecordingKind.fromJson(preferredKind),
      supportedLayers:
          (json['supportedLayers'] as List<Object?>? ?? const <Object?>[])
              .map(CockpitRecordingLayer.fromJson)
              .toList(growable: false),
      preferredLayer: json['preferredLayer'] == null
          ? null
          : CockpitRecordingLayer.fromJson(json['preferredLayer']),
      recordingLimitations:
          (json['recordingLimitations'] as List<Object?>? ?? const <Object?>[])
              .cast<String>(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRecordingCapabilities &&
            other.supportsNativeRecording == supportsNativeRecording &&
            other.preferredAcceptanceRecordingKind ==
                preferredAcceptanceRecordingKind &&
            _layerListEquality.equals(other.supportedLayers, supportedLayers) &&
            other.preferredLayer == preferredLayer &&
            _stringListEquality.equals(
              other.recordingLimitations,
              recordingLimitations,
            );
  }

  @override
  int get hashCode => Object.hash(
    supportsNativeRecording,
    preferredAcceptanceRecordingKind,
    _layerListEquality.hash(supportedLayers),
    preferredLayer,
    _stringListEquality.hash(recordingLimitations),
  );
}
