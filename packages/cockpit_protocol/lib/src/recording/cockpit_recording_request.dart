import 'cockpit_recording_layer.dart';
import 'cockpit_recording_mode.dart';
import 'cockpit_recording_purpose.dart';

final class CockpitRecordingRequest {
  /// Creates a CockpitRecordingRequest.
  const CockpitRecordingRequest({
    required this.purpose,
    required this.name,
    this.mode = CockpitRecordingMode.auto,
    this.layer,
    this.allowFallback,
    this.attachToStep = false,
    this.tailStabilizationDelay = const Duration(milliseconds: 1400),
  });

  final CockpitRecordingPurpose purpose;
  final String name;
  final CockpitRecordingMode mode;
  final CockpitRecordingLayer? layer;
  final bool? allowFallback;
  final bool attachToStep;
  final Duration tailStabilizationDelay;

  bool get allowsFallback => allowFallback ?? _defaultAllowsFallback();

  /// Encodes this CockpitRecordingRequest as a JSON object.
  Map<String, Object?> toJson() => {
    'purpose': purpose.name,
    'name': name,
    if (mode != CockpitRecordingMode.auto) 'mode': mode.jsonValue,
    if (layer != null) 'layer': layer!.jsonValue,
    if (allowFallback != null) 'allowFallback': allowFallback,
    'attachToStep': attachToStep,
    'tailStabilizationMs': tailStabilizationDelay.inMilliseconds,
  };

  /// Decodes a CockpitRecordingRequest from a JSON object.
  factory CockpitRecordingRequest.fromJson(Map<String, Object?> json) {
    final purpose = CockpitRecordingPurpose.fromJson(json['purpose']);
    return CockpitRecordingRequest(
      purpose: purpose,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name']! as String
          : purpose.name,
      mode: json['mode'] == null
          ? CockpitRecordingMode.auto
          : CockpitRecordingMode.fromJson(json['mode']),
      layer: json['layer'] == null
          ? null
          : CockpitRecordingLayer.fromJson(json['layer']),
      allowFallback: json['allowFallback'] as bool?,
      attachToStep: json['attachToStep'] as bool? ?? false,
      tailStabilizationDelay: Duration(
        milliseconds: (json['tailStabilizationMs'] as int?) ?? 1400,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRecordingRequest &&
            other.purpose == purpose &&
            other.name == name &&
            other.mode == mode &&
            other.layer == layer &&
            other.allowFallback == allowFallback &&
            other.attachToStep == attachToStep &&
            other.tailStabilizationDelay == tailStabilizationDelay;
  }

  @override
  int get hashCode => Object.hash(
    purpose,
    name,
    mode,
    layer,
    allowFallback,
    attachToStep,
    tailStabilizationDelay,
  );

  /// Returns a copy of this CockpitRecordingRequest with supplied fields replaced.
  CockpitRecordingRequest copyWith({
    CockpitRecordingPurpose? purpose,
    String? name,
    CockpitRecordingMode? mode,
    CockpitRecordingLayer? layer,
    Object? allowFallback = _unsetField,
    bool? attachToStep,
    Duration? tailStabilizationDelay,
  }) {
    return CockpitRecordingRequest(
      purpose: purpose ?? this.purpose,
      name: name ?? this.name,
      mode: mode ?? this.mode,
      layer: layer ?? this.layer,
      allowFallback: identical(allowFallback, _unsetField)
          ? this.allowFallback
          : allowFallback as bool?,
      attachToStep: attachToStep ?? this.attachToStep,
      tailStabilizationDelay:
          tailStabilizationDelay ?? this.tailStabilizationDelay,
    );
  }

  bool _defaultAllowsFallback() {
    if (layer != null) {
      return false;
    }
    return mode.defaultAllowsFallback;
  }
}

const Object _unsetField = Object();
