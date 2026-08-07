import '../runtime/cockpit_snapshot.dart';
import 'cockpit_remote_artifact_download.dart';

final class CockpitRemoteSnapshotResponse {
  /// Creates a CockpitRemoteSnapshotResponse.
  CockpitRemoteSnapshotResponse({
    required this.snapshot,
    List<CockpitRemoteArtifactDownload> artifactDownloads =
        const <CockpitRemoteArtifactDownload>[],
  }) : artifactDownloads = List.unmodifiable(artifactDownloads);

  final CockpitSnapshot snapshot;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;

  /// Returns a copy of this CockpitRemoteSnapshotResponse with supplied fields replaced.
  CockpitRemoteSnapshotResponse copyWith({
    CockpitSnapshot? snapshot,
    List<CockpitRemoteArtifactDownload>? artifactDownloads,
  }) {
    return CockpitRemoteSnapshotResponse(
      snapshot: snapshot ?? this.snapshot,
      artifactDownloads: artifactDownloads ?? this.artifactDownloads,
    );
  }

  /// Encodes this CockpitRemoteSnapshotResponse as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'snapshot': snapshot.toJson(),
    'artifactDownloads': artifactDownloads
        .map((download) => download.toJson())
        .toList(growable: false),
  };

  /// Decodes a CockpitRemoteSnapshotResponse from a JSON object.
  factory CockpitRemoteSnapshotResponse.fromJson(Map<String, Object?> json) {
    final snapshotJson = json['snapshot'] as Map<Object?, Object?>;
    final downloadsJson =
        json['artifactDownloads'] as List<Object?>? ?? const <Object?>[];
    return CockpitRemoteSnapshotResponse(
      snapshot: CockpitSnapshot.fromJson(
        Map<String, Object?>.from(snapshotJson),
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
        other is CockpitRemoteSnapshotResponse &&
            other.snapshot == snapshot &&
            _listEquals(other.artifactDownloads, artifactDownloads);
  }

  @override
  int get hashCode => Object.hash(snapshot, Object.hashAll(artifactDownloads));

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
