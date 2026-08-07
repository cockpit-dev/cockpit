import 'cockpit_recording_request.dart';
import 'cockpit_recording_state.dart';

final class CockpitRecordingSession {
  /// Creates a CockpitRecordingSession.
  const CockpitRecordingSession({required this.request, required this.state});

  final CockpitRecordingRequest request;
  final CockpitRecordingState state;

  /// Returns a copy of this CockpitRecordingSession with supplied fields replaced.
  CockpitRecordingSession copyWith({
    CockpitRecordingRequest? request,
    CockpitRecordingState? state,
  }) {
    return CockpitRecordingSession(
      request: request ?? this.request,
      state: state ?? this.state,
    );
  }

  /// Encodes this CockpitRecordingSession as a JSON object.
  Map<String, Object?> toJson() => {
    'request': request.toJson(),
    'state': state.name,
  };

  /// Decodes a CockpitRecordingSession from a JSON object.
  factory CockpitRecordingSession.fromJson(Map<String, Object?> json) {
    return CockpitRecordingSession(
      request: CockpitRecordingRequest.fromJson(
        Map<String, Object?>.from(json['request']! as Map<Object?, Object?>),
      ),
      state: CockpitRecordingState.fromJson(json['state']),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRecordingSession &&
            other.request == request &&
            other.state == state;
  }

  @override
  int get hashCode => Object.hash(request, state);
}
