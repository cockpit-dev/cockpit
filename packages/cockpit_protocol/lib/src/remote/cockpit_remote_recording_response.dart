import '../recording/cockpit_recording_result.dart';
import 'cockpit_remote_artifact_download.dart';

final class CockpitRemoteRecordingResponse {
  /// Creates a CockpitRemoteRecordingResponse.
  CockpitRemoteRecordingResponse({
    required this.result,
    List<CockpitRemoteArtifactDownload> artifactDownloads =
        const <CockpitRemoteArtifactDownload>[],
  }) : artifactDownloads = List.unmodifiable(artifactDownloads);

  final CockpitRecordingResult result;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;

  /// Encodes this CockpitRemoteRecordingResponse as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'result': result.toJson(),
    'artifactDownloads': artifactDownloads
        .map((download) => download.toJson())
        .toList(growable: false),
  };

  /// Decodes a CockpitRemoteRecordingResponse from a JSON object.
  factory CockpitRemoteRecordingResponse.fromJson(Map<String, Object?> json) {
    final resultJson = json['result'] as Map<Object?, Object?>;
    final downloadsJson =
        json['artifactDownloads'] as List<Object?>? ?? const <Object?>[];
    return CockpitRemoteRecordingResponse(
      result: CockpitRecordingResult.fromJson(
        Map<String, Object?>.from(resultJson),
      ),
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
        other is CockpitRemoteRecordingResponse &&
            other.result == result &&
            _listEquals(other.artifactDownloads, artifactDownloads);
  }

  @override
  int get hashCode => Object.hash(result, Object.hashAll(artifactDownloads));

  static bool _listEquals(
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
