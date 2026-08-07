import '../recording/cockpit_recording_capabilities.dart';
import '../recording/cockpit_recording_session.dart';
import '../model/cockpit_environment.dart';
import '../runtime/cockpit_capabilities.dart';
import '../runtime/cockpit_snapshot.dart';

final class CockpitRemoteSessionStatus {
  /// Creates a CockpitRemoteSessionStatus.
  CockpitRemoteSessionStatus({
    required this.sessionId,
    required this.platform,
    required this.transportType,
    required this.currentRouteName,
    required this.capabilities,
    required this.recordingCapabilities,
    required this.snapshot,
    this.environment,
    this.processId,
    this.activeRecording,
  });

  final String sessionId;
  final String platform;
  final String transportType;
  final String? currentRouteName;
  final CockpitCapabilities capabilities;
  final CockpitRecordingCapabilities recordingCapabilities;
  final CockpitSnapshot snapshot;
  final CockpitEnvironment? environment;
  final int? processId;
  final CockpitRecordingSession? activeRecording;

  /// Encodes this CockpitRemoteSessionStatus as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'platform': platform,
    'transportType': transportType,
    if (currentRouteName != null) 'currentRouteName': currentRouteName,
    'capabilities': capabilities.toJson(),
    'recordingCapabilities': recordingCapabilities.toJson(),
    'snapshot': snapshot.toJson(),
    if (environment != null) 'environment': environment!.toJson(),
    if (processId != null) 'processId': processId,
    if (activeRecording != null) 'activeRecording': activeRecording!.toJson(),
  };

  /// Decodes a CockpitRemoteSessionStatus from a JSON object.
  factory CockpitRemoteSessionStatus.fromJson(Map<String, Object?> json) {
    final capabilitiesJson = json['capabilities'] as Map<Object?, Object?>;
    final recordingCapabilitiesJson =
        json['recordingCapabilities'] as Map<Object?, Object?>;
    final snapshotJson = json['snapshot'] as Map<Object?, Object?>;
    final environmentJson = json['environment'];
    final activeRecordingJson = json['activeRecording'];

    return CockpitRemoteSessionStatus(
      sessionId: json['sessionId']! as String,
      platform: json['platform']! as String,
      transportType: json['transportType']! as String,
      currentRouteName: json['currentRouteName'] as String?,
      capabilities: CockpitCapabilities.fromJson(
        Map<String, Object?>.from(capabilitiesJson),
      ),
      recordingCapabilities: CockpitRecordingCapabilities.fromJson(
        Map<String, Object?>.from(recordingCapabilitiesJson),
      ),
      snapshot: CockpitSnapshot.fromJson(
        Map<String, Object?>.from(snapshotJson),
      ),
      environment: environmentJson == null
          ? null
          : CockpitEnvironment.fromJson(
              Map<String, Object?>.from(
                environmentJson as Map<Object?, Object?>,
              ),
            ),
      processId: json['processId'] as int?,
      activeRecording: activeRecordingJson == null
          ? null
          : CockpitRecordingSession.fromJson(
              Map<String, Object?>.from(
                activeRecordingJson as Map<Object?, Object?>,
              ),
            ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRemoteSessionStatus &&
            other.sessionId == sessionId &&
            other.platform == platform &&
            other.transportType == transportType &&
            other.currentRouteName == currentRouteName &&
            other.capabilities == capabilities &&
            other.recordingCapabilities == recordingCapabilities &&
            other.snapshot == snapshot &&
            other.environment == environment &&
            other.processId == processId &&
            other.activeRecording == activeRecording;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    platform,
    transportType,
    currentRouteName,
    capabilities,
    recordingCapabilities,
    snapshot,
    environment,
    processId,
    activeRecording,
  );
}
