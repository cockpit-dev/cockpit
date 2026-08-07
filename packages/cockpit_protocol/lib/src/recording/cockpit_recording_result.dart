import 'package:collection/collection.dart';

import '../model/cockpit_artifact_ref.dart';
import 'cockpit_recording_kind.dart';
import 'cockpit_recording_layer.dart';
import 'cockpit_recording_mode.dart';
import 'cockpit_recording_purpose.dart';
import 'cockpit_recording_state.dart';

final class CockpitRecordingResult {
  /// Creates a CockpitRecordingResult.
  CockpitRecordingResult({
    required this.state,
    this.purpose,
    this.recordingKind,
    this.requestedMode,
    this.requestedLayer,
    this.effectiveLayer,
    this.fallbackUsed = false,
    this.fallbackReason,
    this.artifact,
    this.durationMs,
    List<int>? bytes,
    this.sourceFilePath,
    this.failureReason,
  }) : bytes = bytes == null ? null : List.unmodifiable(bytes);

  final CockpitRecordingState state;
  final CockpitRecordingPurpose? purpose;
  final CockpitRecordingKind? recordingKind;
  final CockpitRecordingMode? requestedMode;
  final CockpitRecordingLayer? requestedLayer;
  final CockpitRecordingLayer? effectiveLayer;
  final bool fallbackUsed;
  final String? fallbackReason;
  final CockpitArtifactRef? artifact;
  final int? durationMs;
  final List<int>? bytes;
  final String? sourceFilePath;
  final String? failureReason;

  static const ListEquality<int> _byteEquality = ListEquality<int>();

  /// Encodes this CockpitRecordingResult as a JSON object.
  Map<String, Object?> toJson() => {
    'state': state.name,
    if (purpose != null) 'purpose': purpose!.name,
    if (recordingKind != null) 'recordingKind': recordingKind!.name,
    if (requestedMode != null) 'requestedMode': requestedMode!.jsonValue,
    if (requestedLayer != null) 'requestedLayer': requestedLayer!.jsonValue,
    if (effectiveLayer != null) 'effectiveLayer': effectiveLayer!.jsonValue,
    if (fallbackUsed) 'fallbackUsed': fallbackUsed,
    if (fallbackReason != null) 'fallbackReason': fallbackReason,
    if (artifact != null) 'artifact': artifact!.toJson(),
    if (durationMs != null) 'durationMs': durationMs,
    if (bytes != null) 'bytes': bytes,
    if (sourceFilePath != null) 'sourceFilePath': sourceFilePath,
    if (failureReason != null) 'failureReason': failureReason,
  };

  /// Decodes a CockpitRecordingResult from a JSON object.
  factory CockpitRecordingResult.fromJson(Map<String, Object?> json) {
    final artifactJson = json['artifact'] as Map<Object?, Object?>?;
    return CockpitRecordingResult(
      state: CockpitRecordingState.fromJson(json['state']),
      purpose: json['purpose'] == null
          ? null
          : CockpitRecordingPurpose.fromJson(json['purpose']),
      recordingKind: json['recordingKind'] == null
          ? null
          : CockpitRecordingKind.fromJson(json['recordingKind']),
      requestedMode: json['requestedMode'] == null
          ? null
          : CockpitRecordingMode.fromJson(json['requestedMode']),
      requestedLayer: json['requestedLayer'] == null
          ? null
          : CockpitRecordingLayer.fromJson(json['requestedLayer']),
      effectiveLayer: json['effectiveLayer'] == null
          ? null
          : CockpitRecordingLayer.fromJson(json['effectiveLayer']),
      fallbackUsed: json['fallbackUsed'] as bool? ?? false,
      fallbackReason: json['fallbackReason'] as String?,
      artifact: artifactJson == null
          ? null
          : CockpitArtifactRef.fromJson(
              Map<String, Object?>.from(artifactJson),
            ),
      durationMs: json['durationMs'] as int?,
      bytes: (json['bytes'] as List<Object?>?)?.cast<int>(),
      sourceFilePath: json['sourceFilePath'] as String?,
      failureReason: json['failureReason'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRecordingResult &&
            other.state == state &&
            other.purpose == purpose &&
            other.recordingKind == recordingKind &&
            other.requestedMode == requestedMode &&
            other.requestedLayer == requestedLayer &&
            other.effectiveLayer == effectiveLayer &&
            other.fallbackUsed == fallbackUsed &&
            other.fallbackReason == fallbackReason &&
            other.artifact == artifact &&
            other.durationMs == durationMs &&
            _byteEquality.equals(other.bytes, bytes) &&
            other.sourceFilePath == sourceFilePath &&
            other.failureReason == failureReason;
  }

  @override
  int get hashCode => Object.hash(
    state,
    purpose,
    recordingKind,
    requestedMode,
    requestedLayer,
    effectiveLayer,
    fallbackUsed,
    fallbackReason,
    artifact,
    durationMs,
    bytes == null ? null : _byteEquality.hash(bytes!),
    sourceFilePath,
    failureReason,
  );

  /// Returns a copy of this CockpitRecordingResult with supplied fields replaced.
  CockpitRecordingResult copyWith({
    CockpitRecordingState? state,
    CockpitRecordingPurpose? purpose,
    CockpitRecordingKind? recordingKind,
    Object? requestedMode = _unsetField,
    Object? requestedLayer = _unsetField,
    Object? effectiveLayer = _unsetField,
    bool? fallbackUsed,
    Object? fallbackReason = _unsetField,
    Object? artifact = _unsetField,
    Object? durationMs = _unsetField,
    Object? bytes = _unsetField,
    Object? sourceFilePath = _unsetField,
    Object? failureReason = _unsetField,
  }) {
    return CockpitRecordingResult(
      state: state ?? this.state,
      purpose: purpose ?? this.purpose,
      recordingKind: recordingKind ?? this.recordingKind,
      requestedMode: identical(requestedMode, _unsetField)
          ? this.requestedMode
          : requestedMode as CockpitRecordingMode?,
      requestedLayer: identical(requestedLayer, _unsetField)
          ? this.requestedLayer
          : requestedLayer as CockpitRecordingLayer?,
      effectiveLayer: identical(effectiveLayer, _unsetField)
          ? this.effectiveLayer
          : effectiveLayer as CockpitRecordingLayer?,
      fallbackUsed: fallbackUsed ?? this.fallbackUsed,
      fallbackReason: identical(fallbackReason, _unsetField)
          ? this.fallbackReason
          : fallbackReason as String?,
      artifact: identical(artifact, _unsetField)
          ? this.artifact
          : artifact as CockpitArtifactRef?,
      durationMs: identical(durationMs, _unsetField)
          ? this.durationMs
          : durationMs as int?,
      bytes: identical(bytes, _unsetField) ? this.bytes : bytes as List<int>?,
      sourceFilePath: identical(sourceFilePath, _unsetField)
          ? this.sourceFilePath
          : sourceFilePath as String?,
      failureReason: identical(failureReason, _unsetField)
          ? this.failureReason
          : failureReason as String?,
    );
  }
}

const Object _unsetField = Object();
