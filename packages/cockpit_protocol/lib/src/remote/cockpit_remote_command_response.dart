import '../control/cockpit_command_execution.dart';
import '../control/cockpit_command_result.dart';
import '../model/cockpit_step_record.dart';
import 'cockpit_remote_artifact_download.dart';
import 'cockpit_remote_artifact_payload.dart';

final class CockpitRemoteCommandResponse {
  /// Creates a CockpitRemoteCommandResponse.
  CockpitRemoteCommandResponse({
    required this.result,
    List<CockpitRemoteArtifactPayload> artifactPayloads =
        const <CockpitRemoteArtifactPayload>[],
    List<CockpitStepRecord> runtimeSteps = const <CockpitStepRecord>[],
    List<CockpitRemoteArtifactDownload> artifactDownloads =
        const <CockpitRemoteArtifactDownload>[],
  }) : artifactPayloads = List.unmodifiable(artifactPayloads),
       runtimeSteps = List.unmodifiable(runtimeSteps),
       artifactDownloads = List.unmodifiable(artifactDownloads);

  final CockpitCommandResult result;
  final List<CockpitRemoteArtifactPayload> artifactPayloads;
  final List<CockpitStepRecord> runtimeSteps;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;

  /// Creates a CockpitRemoteCommandResponse using the named constructor `fromExecution`.
  factory CockpitRemoteCommandResponse.fromExecution(
    CockpitCommandExecution execution,
  ) {
    final artifactsByPath = {
      for (final artifact in execution.result.artifacts)
        artifact.relativePath: artifact,
    };
    return CockpitRemoteCommandResponse(
      result: execution.result,
      artifactPayloads: execution.artifactPayloads.entries
          .where((entry) => artifactsByPath.containsKey(entry.key))
          .map(
            (entry) => CockpitRemoteArtifactPayload(
              artifact: artifactsByPath[entry.key]!,
              bytes: entry.value,
            ),
          )
          .toList(growable: false),
      runtimeSteps: execution.runtimeSteps,
    );
  }

  CockpitCommandExecution toExecution() {
    return CockpitCommandExecution(
      result: result,
      artifactPayloads: <String, List<int>>{
        for (final payload in artifactPayloads)
          payload.artifact.relativePath: payload.bytes,
      },
      runtimeSteps: runtimeSteps,
    );
  }

  /// Encodes this CockpitRemoteCommandResponse as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'result': result.toJson(),
    'artifactPayloads': artifactPayloads
        .map((payload) => payload.toJson())
        .toList(growable: false),
    'runtimeSteps': runtimeSteps
        .map((step) => step.toJson())
        .toList(growable: false),
    if (artifactDownloads.isNotEmpty)
      'artifactDownloads': artifactDownloads
          .map((download) => download.toJson())
          .toList(growable: false),
  };

  /// Decodes a CockpitRemoteCommandResponse from a JSON object.
  factory CockpitRemoteCommandResponse.fromJson(Map<String, Object?> json) {
    final resultJson = json['result'] as Map<Object?, Object?>;
    final payloadJson =
        json['artifactPayloads'] as List<Object?>? ?? const <Object?>[];
    final runtimeStepsJson =
        json['runtimeSteps'] as List<Object?>? ?? const <Object?>[];
    final downloadsJson =
        json['artifactDownloads'] as List<Object?>? ?? const <Object?>[];

    return CockpitRemoteCommandResponse(
      result: CockpitCommandResult.fromJson(
        Map<String, Object?>.from(resultJson),
      ),
      artifactPayloads: payloadJson
          .cast<Map<Object?, Object?>>()
          .map(
            (payload) => CockpitRemoteArtifactPayload.fromJson(
              Map<String, Object?>.from(payload),
            ),
          )
          .toList(growable: false),
      runtimeSteps: runtimeStepsJson
          .cast<Map<Object?, Object?>>()
          .map(
            (step) =>
                CockpitStepRecord.fromJson(Map<String, Object?>.from(step)),
          )
          .toList(growable: false),
      artifactDownloads: downloadsJson
          .cast<Map<Object?, Object?>>()
          .map(
            (download) => CockpitRemoteArtifactDownload.fromJson(
              Map<String, Object?>.from(download),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRemoteCommandResponse &&
            other.result == result &&
            _listEquals(other.artifactPayloads, artifactPayloads) &&
            _stepListEquals(other.runtimeSteps, runtimeSteps) &&
            _downloadListEquals(other.artifactDownloads, artifactDownloads);
  }

  @override
  int get hashCode => Object.hash(
    result,
    Object.hashAll(artifactPayloads),
    Object.hashAll(runtimeSteps),
    Object.hashAll(artifactDownloads),
  );

  static bool _listEquals(
    List<CockpitRemoteArtifactPayload> left,
    List<CockpitRemoteArtifactPayload> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static bool _stepListEquals(
    List<CockpitStepRecord> left,
    List<CockpitStepRecord> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static bool _downloadListEquals(
    List<CockpitRemoteArtifactDownload> left,
    List<CockpitRemoteArtifactDownload> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
