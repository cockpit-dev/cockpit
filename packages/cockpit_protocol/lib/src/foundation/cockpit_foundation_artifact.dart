import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

final class CockpitArtifactReference {
  /// Creates a CockpitArtifactReference.
  CockpitArtifactReference({
    required this.artifactId,
    required this.runId,
    this.sha256,
  }) {
    CockpitFoundationValueReader.id(artifactId, r'$.artifactId');
    CockpitFoundationValueReader.id(runId, r'$.runId');
    if (sha256 != null) {
      CockpitFoundationValueReader.sha256(sha256, r'$.sha256');
    }
  }

  final String artifactId;
  final String runId;
  final String? sha256;

  /// Encodes this CockpitArtifactReference as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'artifactId': artifactId,
    'runId': runId,
    if (sha256 != null) 'sha256': sha256,
  };

  /// Decodes a CockpitArtifactReference from a JSON object.
  factory CockpitArtifactReference.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'artifactId', 'runId', 'sha256'},
      path,
      required: const <String>{'artifactId', 'runId'},
      policy: decodePolicy,
    );
    return CockpitArtifactReference(
      artifactId: CockpitFoundationValueReader.id(
        json['artifactId'],
        '$path.artifactId',
      ),
      runId: CockpitFoundationValueReader.id(json['runId'], '$path.runId'),
      sha256: json['sha256'] == null
          ? null
          : CockpitFoundationValueReader.sha256(json['sha256'], '$path.sha256'),
    );
  }
}

final class CockpitArtifactResource {
  /// Creates a CockpitArtifactResource.
  CockpitArtifactResource({
    required this.artifactId,
    required this.workspaceId,
    required this.runId,
    required this.kind,
    required this.relativePath,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
    required this.downloadUrl,
    this.attemptId,
    this.stepExecutionId,
  }) {
    CockpitFoundationValueReader.id(artifactId, r'$.artifactId');
    CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    CockpitFoundationValueReader.id(runId, r'$.runId');
    CockpitFoundationValueReader.kind(kind, r'$.kind');
    CockpitFoundationValueReader.relativePath(relativePath, r'$.relativePath');
    CockpitFoundationValueReader.mediaType(mediaType, r'$.mediaType');
    CockpitFoundationValueReader.integer(sizeBytes, r'$.sizeBytes', min: 0);
    CockpitFoundationValueReader.sha256(sha256, r'$.sha256');
    CockpitFoundationValueReader.utcDateTime(createdAt, r'$.createdAt');
    CockpitFoundationValueReader.apiPath(downloadUrl, r'$.downloadUrl');
    if (attemptId != null) {
      CockpitFoundationValueReader.id(attemptId, r'$.attemptId');
    }
    if (stepExecutionId != null) {
      CockpitFoundationValueReader.string(
        stepExecutionId,
        r'$.stepExecutionId',
        maximum: 512,
      );
      if (attemptId == null) {
        throw const FormatException('Step artifact requires an attemptId.');
      }
    }
  }

  final String artifactId;
  final String workspaceId;
  final String runId;
  final String? attemptId;
  final String? stepExecutionId;
  final String kind;
  final String relativePath;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;
  final String downloadUrl;

  CockpitArtifactReference get reference => CockpitArtifactReference(
    artifactId: artifactId,
    runId: runId,
    sha256: sha256,
  );

  /// Encodes this CockpitArtifactResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'artifactId': artifactId,
    'workspaceId': workspaceId,
    'runId': runId,
    if (attemptId != null) 'attemptId': attemptId,
    if (stepExecutionId != null) 'stepExecutionId': stepExecutionId,
    'kind': kind,
    'relativePath': relativePath,
    'mediaType': mediaType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'downloadUrl': downloadUrl,
  };

  /// Decodes a CockpitArtifactResource from a JSON object.
  factory CockpitArtifactResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'artifactId',
      'workspaceId',
      'runId',
      'attemptId',
      'stepExecutionId',
      'kind',
      'relativePath',
      'mediaType',
      'sizeBytes',
      'sha256',
      'createdAt',
      'downloadUrl',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields.difference(const <String>{
        'attemptId',
        'stepExecutionId',
      }),
      policy: decodePolicy,
    );
    return CockpitArtifactResource(
      artifactId: CockpitFoundationValueReader.id(
        json['artifactId'],
        '$path.artifactId',
      ),
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      runId: CockpitFoundationValueReader.id(json['runId'], '$path.runId'),
      attemptId: json['attemptId'] == null
          ? null
          : CockpitFoundationValueReader.id(
              json['attemptId'],
              '$path.attemptId',
            ),
      stepExecutionId: CockpitFoundationValueReader.optionalString(
        json['stepExecutionId'],
        '$path.stepExecutionId',
        maximum: 512,
      ),
      kind: CockpitFoundationValueReader.kind(json['kind'], '$path.kind'),
      relativePath: CockpitFoundationValueReader.relativePath(
        json['relativePath'],
        '$path.relativePath',
      ),
      mediaType: CockpitFoundationValueReader.mediaType(
        json['mediaType'],
        '$path.mediaType',
      ),
      sizeBytes: CockpitFoundationValueReader.integer(
        json['sizeBytes'],
        '$path.sizeBytes',
        min: 0,
      ),
      sha256: CockpitFoundationValueReader.sha256(
        json['sha256'],
        '$path.sha256',
      ),
      createdAt: CockpitFoundationValueReader.dateTime(
        json['createdAt'],
        '$path.createdAt',
      ),
      downloadUrl: CockpitFoundationValueReader.apiPath(
        json['downloadUrl'],
        '$path.downloadUrl',
      ),
    );
  }
}
