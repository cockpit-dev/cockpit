import 'package:flutter/services.dart';

import '../model/cockpit_artifact_ref.dart';
import 'cockpit_recording_capabilities.dart';
import 'cockpit_recording_kind.dart';
import 'cockpit_recording_layer.dart';
import 'cockpit_recording_paths.dart';
import 'cockpit_recording_request.dart';
import 'cockpit_recording_result.dart';
import 'cockpit_recording_session.dart';
import 'cockpit_recording_state.dart';

class CockpitNativeRecording {
  const CockpitNativeRecording({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.cockpit.flutter_cockpit/recording';

  final MethodChannel _channel;

  Future<CockpitRecordingCapabilities> queryCapabilities() async {
    final payload = await _channel.invokeMethod<Object?>(
      'queryRecordingCapabilities',
    );
    if (payload is! Map<Object?, Object?>) {
      throw StateError('Recording capabilities returned an invalid payload.');
    }

    return CockpitRecordingCapabilities.fromJson(
      Map<String, Object?>.from(payload),
    );
  }

  Future<CockpitRecordingSession> startRecording({
    required CockpitRecordingRequest request,
  }) async {
    final payload = await _channel
        .invokeMethod<Object?>('startRecording', <String, Object?>{
          'purpose': request.purpose.name,
          'name': request.name,
          'mode': request.mode.jsonValue,
          'layer': request.layer?.jsonValue,
          'allowFallback': request.allowFallback,
          'attachToStep': request.attachToStep,
          'relativePath': cockpitRecordingRelativePathFor(request),
        });
    if (payload is! Map<Object?, Object?>) {
      throw StateError('Start recording returned an invalid payload.');
    }

    final state = payload['state'] == null
        ? CockpitRecordingState.recording
        : CockpitRecordingState.fromJson(payload['state']);
    return CockpitRecordingSession(request: request, state: state);
  }

  /// Cancels a pending native recording consent/start request.
  ///
  /// Platforms without an interruptible pending request return `false`.
  /// The method is intentionally separate from [stopRecording], because a
  /// recording session does not exist until startup has completed.
  Future<bool> cancelStart() async {
    final Object? payload;
    try {
      payload = await _channel.invokeMethod<Object?>('cancelRecordingStart');
    } on MissingPluginException {
      return false;
    }
    if (payload is bool) return payload;
    if (payload is Map<Object?, Object?>) {
      return payload['cancelled'] == true;
    }
    throw StateError('Cancel recording start returned an invalid payload.');
  }

  Future<CockpitRecordingResult> stopRecording({
    required CockpitRecordingSession session,
  }) async {
    final payload = await _channel
        .invokeMethod<Object?>('stopRecording', <String, Object?>{
          'purpose': session.request.purpose.name,
          'name': session.request.name,
          'relativePath': cockpitRecordingRelativePathFor(session.request),
        });
    if (payload is! Map<Object?, Object?>) {
      throw StateError('Stop recording returned an invalid payload.');
    }

    final state = CockpitRecordingState.fromJson(
      _requiredField<String>(payload, 'state'),
    );
    final rawBytes = _optionalField<Uint8List>(payload, 'bytes');
    final rawSourceFilePath = _optionalField<String>(payload, 'sourceFilePath');
    final completed = state == CockpitRecordingState.completed;
    final bytes = completed && rawBytes != null && rawBytes.isNotEmpty
        ? rawBytes
        : null;
    final sourceFilePath =
        completed &&
            rawSourceFilePath != null &&
            rawSourceFilePath.trim().isNotEmpty
        ? rawSourceFilePath
        : null;
    final hasUsableSource = bytes != null || sourceFilePath != null;
    final relativePath = cockpitRecordingRelativePathFor(session.request);

    return CockpitRecordingResult(
      state: state,
      purpose: session.request.purpose,
      recordingKind: _optionalField<String>(payload, 'recordingKind') == null
          ? CockpitRecordingKind.nativeScreen
          : CockpitRecordingKind.fromJson(payload['recordingKind']),
      requestedMode: session.request.mode,
      requestedLayer: session.request.layer,
      effectiveLayer: _optionalField<String>(payload, 'effectiveLayer') == null
          ? session.request.layer
          : CockpitRecordingLayer.fromJson(payload['effectiveLayer']),
      fallbackUsed: _optionalField<bool>(payload, 'fallbackUsed') ?? false,
      fallbackReason: _optionalField<String>(payload, 'fallbackReason'),
      artifact: completed && hasUsableSource
          ? CockpitArtifactRef(role: 'recording', relativePath: relativePath)
          : null,
      durationMs: _optionalField<int>(payload, 'durationMs'),
      bytes: bytes,
      sourceFilePath: sourceFilePath,
      failureReason: _optionalField<String>(payload, 'failureReason'),
    );
  }

  T _requiredField<T>(Map<Object?, Object?> payload, String name) {
    final value = payload[name];
    if (value is! T) {
      throw StateError('Stop recording returned an invalid $name field.');
    }
    return value;
  }

  T? _optionalField<T>(Map<Object?, Object?> payload, String name) {
    final value = payload[name];
    if (value == null) {
      return null;
    }
    if (value is! T) {
      throw StateError('Stop recording returned an invalid $name field.');
    }
    return value as T;
  }
}
