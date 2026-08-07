import 'cockpit_test_run.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestArtifactEntry {
  /// Creates a CockpitTestArtifactEntry.
  CockpitTestArtifactEntry({
    required this.artifactId,
    required this.kind,
    required this.relativePath,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
    this.stepExecutionId,
  }) {
    CockpitTestValueReader.string(artifactId, r'$.artifactId', id: true);
    CockpitTestValueReader.string(kind, r'$.kind');
    CockpitTestValueReader.string(mediaType, r'$.mediaType');
    final segments = relativePath.split('/');
    if (relativePath.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relativePath) ||
        relativePath.contains(r'\') ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw const FormatException('Artifact path must be safe and relative.');
    }
    if (sizeBytes < 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Artifact size or SHA-256 is invalid.');
    }
    if (stepExecutionId != null) {
      CockpitTestValueReader.string(stepExecutionId, r'$.stepExecutionId');
    }
  }

  final String artifactId;
  final String kind;
  final String relativePath;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
  final String? stepExecutionId;

  /// Encodes this CockpitTestArtifactEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'artifactId': artifactId,
    'kind': kind,
    'relativePath': relativePath,
    'mediaType': mediaType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    if (stepExecutionId != null) 'stepExecutionId': stepExecutionId,
  };

  /// Decodes a CockpitTestArtifactEntry from a JSON object.
  factory CockpitTestArtifactEntry.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'artifactId',
        'kind',
        'relativePath',
        'mediaType',
        'sizeBytes',
        'sha256',
        'stepExecutionId',
      },
      path,
      required: const <String>{
        'artifactId',
        'kind',
        'relativePath',
        'mediaType',
        'sizeBytes',
        'sha256',
      },
    );
    return CockpitTestArtifactEntry(
      artifactId: CockpitTestValueReader.string(
        json['artifactId'],
        '$path.artifactId',
        id: true,
      ),
      kind: CockpitTestValueReader.string(json['kind'], '$path.kind'),
      relativePath: CockpitTestValueReader.string(
        json['relativePath'],
        '$path.relativePath',
      ),
      mediaType: CockpitTestValueReader.string(
        json['mediaType'],
        '$path.mediaType',
      ),
      sizeBytes: CockpitTestValueReader.integer(
        json['sizeBytes'],
        '$path.sizeBytes',
        minimum: 0,
      ),
      sha256: CockpitTestValueReader.string(json['sha256'], '$path.sha256'),
      stepExecutionId: CockpitTestValueReader.optionalString(
        json['stepExecutionId'],
        '$path.stepExecutionId',
      ),
    );
  }
}

final class CockpitTestEvidenceIndexEntry {
  /// Creates a CockpitTestEvidenceIndexEntry.
  CockpitTestEvidenceIndexEntry({
    required this.stepResultIndex,
    required this.stepExecutionId,
    required Iterable<String> artifactIds,
  }) : artifactIds = List<String>.unmodifiable(artifactIds) {
    if (stepResultIndex < 0) {
      throw const FormatException(
        'Evidence index step result index must be non-negative.',
      );
    }
    CockpitTestValueReader.string(stepExecutionId, r'$.stepExecutionId');
    if (this.artifactIds.isEmpty) {
      throw const FormatException('Evidence index entry cannot be empty.');
    }
    final uniqueIds = <String>{};
    for (var index = 0; index < this.artifactIds.length; index += 1) {
      final artifactId = CockpitTestValueReader.string(
        this.artifactIds[index],
        '\$.artifactIds[$index]',
        id: true,
      );
      if (!uniqueIds.add(artifactId)) {
        throw const FormatException(
          'Evidence index contains a duplicate artifact id.',
        );
      }
    }
  }

  final int stepResultIndex;
  final String stepExecutionId;
  final List<String> artifactIds;

  /// Encodes this CockpitTestEvidenceIndexEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'stepResultIndex': stepResultIndex,
    'stepExecutionId': stepExecutionId,
    'artifactIds': artifactIds,
  };

  /// Decodes a CockpitTestEvidenceIndexEntry from a JSON object.
  factory CockpitTestEvidenceIndexEntry.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'stepResultIndex', 'stepExecutionId', 'artifactIds'},
      path,
      required: const <String>{
        'stepResultIndex',
        'stepExecutionId',
        'artifactIds',
      },
    );
    return CockpitTestEvidenceIndexEntry(
      stepResultIndex: CockpitTestValueReader.integer(
        json['stepResultIndex'],
        '$path.stepResultIndex',
        minimum: 0,
      ),
      stepExecutionId: CockpitTestValueReader.string(
        json['stepExecutionId'],
        '$path.stepExecutionId',
      ),
      artifactIds: CockpitTestValueReader.strings(
        json['artifactIds'],
        '$path.artifactIds',
        id: true,
        unique: true,
      ),
    );
  }
}

final class CockpitTestAttemptBundleManifest {
  /// Creates a CockpitTestAttemptBundleManifest.
  CockpitTestAttemptBundleManifest({
    this.schemaVersion = 'cockpit.report/v2',
    required this.context,
    required this.sourceSha256,
    required this.createdAt,
    required this.result,
    Iterable<CockpitTestArtifactEntry> artifacts =
        const <CockpitTestArtifactEntry>[],
    Iterable<CockpitTestEvidenceIndexEntry> evidenceIndex =
        const <CockpitTestEvidenceIndexEntry>[],
  }) : artifacts = List<CockpitTestArtifactEntry>.unmodifiable(artifacts),
       evidenceIndex = List<CockpitTestEvidenceIndexEntry>.unmodifiable(
         evidenceIndex,
       ) {
    if (schemaVersion != 'cockpit.report/v2') {
      throw const FormatException(
        'Bundle schemaVersion must be cockpit.report/v2.',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256)) {
      throw const FormatException('Bundle source SHA-256 is invalid.');
    }
    if (!_sameContext(context, result.context)) {
      throw const FormatException('Bundle and result identities differ.');
    }
    final artifactIds = <String>{};
    final stepExecutionIds = result.steps
        .map((step) => step.executionId)
        .toSet();
    for (final artifact in this.artifacts) {
      if (!artifactIds.add(artifact.artifactId)) {
        throw FormatException('Duplicate artifact id ${artifact.artifactId}.');
      }
      if (artifact.stepExecutionId case final executionId?
          when !stepExecutionIds.contains(executionId)) {
        throw FormatException(
          'Artifact ${artifact.artifactId} references an unknown step.',
        );
      }
    }
    final indexedStepResults = <int>{};
    final expectedEvidence = <int, Set<String>>{};
    for (
      var stepResultIndex = 0;
      stepResultIndex < result.steps.length;
      stepResultIndex += 1
    ) {
      final step = result.steps[stepResultIndex];
      if (!step.evidence.every(artifactIds.contains)) {
        throw FormatException(
          'Step ${step.executionId} references an unknown artifact.',
        );
      }
      if (step.evidence.isNotEmpty) {
        expectedEvidence[stepResultIndex] = step.evidence.toSet();
      }
    }
    for (final index in this.evidenceIndex) {
      if (index.stepResultIndex >= result.steps.length ||
          result.steps[index.stepResultIndex].executionId !=
              index.stepExecutionId) {
        throw const FormatException(
          'Evidence index references an unknown step result.',
        );
      }
      if (!indexedStepResults.add(index.stepResultIndex)) {
        throw const FormatException(
          'Evidence index contains a duplicate step result.',
        );
      }
      if (!index.artifactIds.every(artifactIds.contains)) {
        throw const FormatException(
          'Evidence index references an unknown artifact.',
        );
      }
      final expected = expectedEvidence[index.stepResultIndex];
      if (expected == null ||
          expected.length != index.artifactIds.length ||
          !index.artifactIds.every(expected.contains)) {
        throw const FormatException(
          'Evidence index does not match the step evidence.',
        );
      }
    }
    if (indexedStepResults.length != expectedEvidence.length ||
        !indexedStepResults.containsAll(expectedEvidence.keys)) {
      throw const FormatException(
        'Evidence index must cover every step with evidence.',
      );
    }
  }

  final String schemaVersion;
  final CockpitTestRunContext context;
  final String sourceSha256;
  final DateTime createdAt;
  final CockpitTestAttemptResult result;
  final List<CockpitTestArtifactEntry> artifacts;
  final List<CockpitTestEvidenceIndexEntry> evidenceIndex;

  /// Encodes this CockpitTestAttemptBundleManifest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'context': context.toJson(),
    'sourceSha256': sourceSha256,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'result': result.toJson(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'evidenceIndex': evidenceIndex.map((entry) => entry.toJson()).toList(),
  };

  /// Decodes a CockpitTestAttemptBundleManifest from a JSON object.
  factory CockpitTestAttemptBundleManifest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'schemaVersion',
        'context',
        'sourceSha256',
        'createdAt',
        'result',
        'artifacts',
        'evidenceIndex',
      },
      path,
      required: const <String>{
        'schemaVersion',
        'context',
        'sourceSha256',
        'createdAt',
        'result',
        'artifacts',
        'evidenceIndex',
      },
    );
    final rawArtifacts = CockpitTestValueReader.list(
      json['artifacts'],
      '$path.artifacts',
    );
    final rawEvidence = CockpitTestValueReader.list(
      json['evidenceIndex'],
      '$path.evidenceIndex',
    );
    return CockpitTestAttemptBundleManifest(
      schemaVersion: CockpitTestValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      context: CockpitTestRunContext.fromJson(
        json['context'],
        path: '$path.context',
      ),
      sourceSha256: CockpitTestValueReader.string(
        json['sourceSha256'],
        '$path.sourceSha256',
      ),
      createdAt: CockpitTestValueReader.dateTime(
        json['createdAt'],
        '$path.createdAt',
      ),
      result: CockpitTestAttemptResult.fromJson(
        json['result'],
        path: '$path.result',
      ),
      artifacts: <CockpitTestArtifactEntry>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          CockpitTestArtifactEntry.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
          ),
      ],
      evidenceIndex: <CockpitTestEvidenceIndexEntry>[
        for (var index = 0; index < rawEvidence.length; index += 1)
          CockpitTestEvidenceIndexEntry.fromJson(
            rawEvidence[index],
            path: '$path.evidenceIndex[$index]',
          ),
      ],
    );
  }
}

final class CockpitTestBundleSummary {
  /// Creates a CockpitTestBundleSummary.
  CockpitTestBundleSummary({
    required this.path,
    required this.manifestSha256,
    required this.artifactCount,
  }) {
    CockpitTestValueReader.string(path, r'$.path');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestSha256) ||
        artifactCount < 0) {
      throw const FormatException('Invalid bundle summary.');
    }
  }

  final String path;
  final String manifestSha256;
  final int artifactCount;

  /// Encodes this CockpitTestBundleSummary as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'manifestSha256': manifestSha256,
    'artifactCount': artifactCount,
  };

  /// Decodes a CockpitTestBundleSummary from a JSON object.
  factory CockpitTestBundleSummary.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'path', 'manifestSha256', 'artifactCount'},
      path,
      required: const <String>{'path', 'manifestSha256', 'artifactCount'},
    );
    return CockpitTestBundleSummary(
      path: CockpitTestValueReader.string(json['path'], '$path.path'),
      manifestSha256: CockpitTestValueReader.string(
        json['manifestSha256'],
        '$path.manifestSha256',
      ),
      artifactCount: CockpitTestValueReader.integer(
        json['artifactCount'],
        '$path.artifactCount',
        minimum: 0,
      ),
    );
  }
}

bool _sameContext(CockpitTestRunContext left, CockpitTestRunContext right) =>
    left.projectId == right.projectId &&
    left.workspaceId == right.workspaceId &&
    left.runId == right.runId &&
    left.caseId == right.caseId &&
    left.attemptId == right.attemptId &&
    left.engineVersion == right.engineVersion;
