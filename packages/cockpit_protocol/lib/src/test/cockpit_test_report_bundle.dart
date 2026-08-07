import 'cockpit_test_report.dart';
import 'cockpit_test_run.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestReportExecutionRole { testCase, supporting, fixture }

final class CockpitTestReportArtifact {
  /// Creates a CockpitTestReportArtifact.
  CockpitTestReportArtifact({
    required this.evidenceId,
    required this.resourceId,
    required this.attemptId,
    this.stepExecutionId,
    required this.kind,
    required this.relativePath,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
  }) {
    CockpitTestValueReader.string(evidenceId, r'$.evidenceId', id: true);
    CockpitTestValueReader.string(resourceId, r'$.resourceId', id: true);
    CockpitTestValueReader.string(attemptId, r'$.attemptId', id: true);
    if (stepExecutionId != null) {
      CockpitTestValueReader.string(
        stepExecutionId,
        r'$.stepExecutionId',
        maximum: 512,
      );
    }
    CockpitTestValueReader.string(kind, r'$.kind');
    CockpitTestValueReader.string(mediaType, r'$.mediaType');
    _validateRelativePath(relativePath, r'$.relativePath');
    if (sizeBytes < 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException(
        'Report artifact size or SHA-256 is invalid.',
      );
    }
    if (!createdAt.isUtc) {
      throw const FormatException('Report artifact timestamp must be UTC.');
    }
  }

  final String evidenceId;
  final String resourceId;
  final String attemptId;
  final String? stepExecutionId;
  final String kind;
  final String relativePath;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;

  /// Encodes this CockpitTestReportArtifact as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'evidenceId': evidenceId,
    'resourceId': resourceId,
    'attemptId': attemptId,
    if (stepExecutionId != null) 'stepExecutionId': stepExecutionId,
    'kind': kind,
    'relativePath': relativePath,
    'mediaType': mediaType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Decodes a CockpitTestReportArtifact from a JSON object.
  factory CockpitTestReportArtifact.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'evidenceId',
        'resourceId',
        'attemptId',
        'stepExecutionId',
        'kind',
        'relativePath',
        'mediaType',
        'sizeBytes',
        'sha256',
        'createdAt',
      },
      path,
      required: const <String>{
        'evidenceId',
        'resourceId',
        'attemptId',
        'kind',
        'relativePath',
        'mediaType',
        'sizeBytes',
        'sha256',
        'createdAt',
      },
    );
    return CockpitTestReportArtifact(
      evidenceId: CockpitTestValueReader.string(
        json['evidenceId'],
        '$path.evidenceId',
        id: true,
      ),
      resourceId: CockpitTestValueReader.string(
        json['resourceId'],
        '$path.resourceId',
        id: true,
      ),
      attemptId: CockpitTestValueReader.string(
        json['attemptId'],
        '$path.attemptId',
        id: true,
      ),
      stepExecutionId: CockpitTestValueReader.optionalString(
        json['stepExecutionId'],
        '$path.stepExecutionId',
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
      createdAt: CockpitTestValueReader.dateTime(
        json['createdAt'],
        '$path.createdAt',
      ).toUtc(),
    );
  }
}

final class CockpitTestReportExecution {
  /// Creates a CockpitTestReportExecution.
  CockpitTestReportExecution({
    required this.role,
    this.entryId,
    this.attemptNumber,
    required this.result,
    Iterable<CockpitTestReportArtifact> artifacts =
        const <CockpitTestReportArtifact>[],
  }) : artifacts = List<CockpitTestReportArtifact>.unmodifiable(artifacts) {
    if ((entryId == null) != (attemptNumber == null) ||
        attemptNumber != null && attemptNumber! < 1) {
      throw const FormatException(
        'Linked report execution identity is incomplete.',
      );
    }
    if (entryId != null) {
      CockpitTestValueReader.string(entryId, r'$.entryId', id: true);
    }
    final evidenceIds = <String>{};
    final resourceIds = <String>{};
    final paths = <String>{};
    for (final artifact in this.artifacts) {
      if (artifact.attemptId != result.context.attemptId ||
          !evidenceIds.add(artifact.evidenceId) ||
          !resourceIds.add(artifact.resourceId) ||
          !paths.add(artifact.relativePath)) {
        throw const FormatException(
          'Report execution artifact identity is invalid or duplicated.',
        );
      }
    }
    for (final step in result.steps) {
      if (!step.evidence.every(evidenceIds.contains)) {
        throw FormatException(
          'Step ${step.executionId} references missing report evidence.',
        );
      }
    }
  }

  final CockpitTestReportExecutionRole role;
  final String? entryId;
  final int? attemptNumber;
  final CockpitTestAttemptResult result;
  final List<CockpitTestReportArtifact> artifacts;

  /// Encodes this CockpitTestReportExecution as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'role': role.name,
    if (entryId != null) 'entryId': entryId,
    if (attemptNumber != null) 'attemptNumber': attemptNumber,
    'result': result.toJson(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };

  /// Decodes a CockpitTestReportExecution from a JSON object.
  factory CockpitTestReportExecution.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'role', 'entryId', 'attemptNumber', 'result', 'artifacts'},
      path,
      required: const <String>{'role', 'result', 'artifacts'},
    );
    final rawArtifacts = CockpitTestValueReader.list(
      json['artifacts'],
      '$path.artifacts',
    );
    return CockpitTestReportExecution(
      role: CockpitTestValueReader.enumeration(
        json['role'],
        CockpitTestReportExecutionRole.values,
        '$path.role',
      ),
      entryId: CockpitTestValueReader.optionalString(
        json['entryId'],
        '$path.entryId',
      ),
      attemptNumber: json['attemptNumber'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['attemptNumber'],
              '$path.attemptNumber',
              minimum: 1,
            ),
      result: CockpitTestAttemptResult.fromJson(
        json['result'],
        path: '$path.result',
      ),
      artifacts: <CockpitTestReportArtifact>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          CockpitTestReportArtifact.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
          ),
      ],
    );
  }
}

final class CockpitTestReportBundle {
  /// Creates a CockpitTestReportBundle.
  CockpitTestReportBundle({
    this.schemaVersion = 'cockpit.report.bundle/v2',
    required this.generatedAt,
    required this.report,
    required Iterable<CockpitTestReportExecution> executions,
    this.complete = true,
  }) : executions = List<CockpitTestReportExecution>.unmodifiable(executions) {
    if (schemaVersion != 'cockpit.report.bundle/v2' ||
        !generatedAt.isUtc ||
        !complete) {
      throw const FormatException('Offline report bundle is incomplete.');
    }
    final attemptIds = <String>{};
    final resourceIds = <String>{};
    final paths = <String>{};
    for (final execution in this.executions) {
      if (execution.result.context.runId != report.runId ||
          execution.result.context.workspaceId != report.workspaceId ||
          !attemptIds.add(execution.result.context.attemptId)) {
        throw const FormatException(
          'Report execution crosses bundle authority or is duplicated.',
        );
      }
      for (final artifact in execution.artifacts) {
        if (!resourceIds.add(artifact.resourceId) ||
            !paths.add(artifact.relativePath)) {
          throw const FormatException(
            'Offline report contains duplicate artifact identity.',
          );
        }
      }
    }
  }

  final String schemaVersion;
  final DateTime generatedAt;
  final CockpitTestSuiteReport report;
  final List<CockpitTestReportExecution> executions;
  final bool complete;

  /// Encodes this CockpitTestReportBundle as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'report': report.toJson(),
    'executions': executions.map((execution) => execution.toJson()).toList(),
    'complete': complete,
  };

  /// Decodes a CockpitTestReportBundle from a JSON object.
  factory CockpitTestReportBundle.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'schemaVersion',
        'generatedAt',
        'report',
        'executions',
        'complete',
      },
      path,
      required: const <String>{
        'schemaVersion',
        'generatedAt',
        'report',
        'executions',
        'complete',
      },
    );
    final rawExecutions = CockpitTestValueReader.list(
      json['executions'],
      '$path.executions',
    );
    return CockpitTestReportBundle(
      schemaVersion: CockpitTestValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      generatedAt: CockpitTestValueReader.dateTime(
        json['generatedAt'],
        '$path.generatedAt',
      ).toUtc(),
      report: CockpitTestSuiteReport.fromJson(
        json['report'],
        path: '$path.report',
      ),
      executions: <CockpitTestReportExecution>[
        for (var index = 0; index < rawExecutions.length; index += 1)
          CockpitTestReportExecution.fromJson(
            rawExecutions[index],
            path: '$path.executions[$index]',
          ),
      ],
      complete: CockpitTestValueReader.boolean(
        json['complete'],
        '$path.complete',
      ),
    );
  }
}

final class CockpitTestReportBundleFile {
  /// Creates a CockpitTestReportBundleFile.
  CockpitTestReportBundleFile({
    required this.relativePath,
    required this.kind,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
    required this.runId,
    this.caseId,
    this.attemptId,
    this.stepExecutionId,
    this.resourceId,
    this.evidenceId,
  }) {
    _validateRelativePath(relativePath, r'$.relativePath');
    CockpitTestValueReader.string(kind, r'$.kind');
    CockpitTestValueReader.string(mediaType, r'$.mediaType');
    CockpitTestValueReader.string(runId, r'$.runId', id: true);
    for (final value in <String?>[caseId, attemptId, resourceId, evidenceId]) {
      if (value != null) {
        CockpitTestValueReader.string(value, r'$.owner', id: true);
      }
    }
    if (stepExecutionId != null) {
      CockpitTestValueReader.string(
        stepExecutionId,
        r'$.stepExecutionId',
        maximum: 512,
      );
    }
    if (sizeBytes < 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Report bundle file integrity is invalid.');
    }
  }

  final String relativePath;
  final String kind;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
  final String runId;
  final String? caseId;
  final String? attemptId;
  final String? stepExecutionId;
  final String? resourceId;
  final String? evidenceId;

  /// Encodes this CockpitTestReportBundleFile as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'relativePath': relativePath,
    'kind': kind,
    'mediaType': mediaType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'owner': <String, Object?>{
      'runId': runId,
      if (caseId != null) 'caseId': caseId,
      if (attemptId != null) 'attemptId': attemptId,
      if (stepExecutionId != null) 'stepExecutionId': stepExecutionId,
      if (resourceId != null) 'resourceId': resourceId,
      if (evidenceId != null) 'evidenceId': evidenceId,
    },
  };

  /// Decodes a CockpitTestReportBundleFile from a JSON object.
  factory CockpitTestReportBundleFile.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'relativePath',
        'kind',
        'mediaType',
        'sizeBytes',
        'sha256',
        'owner',
      },
      path,
      required: const <String>{
        'relativePath',
        'kind',
        'mediaType',
        'sizeBytes',
        'sha256',
        'owner',
      },
    );
    final owner = CockpitTestValueReader.object(json['owner'], '$path.owner');
    CockpitTestValueReader.keys(
      owner,
      const <String>{
        'runId',
        'caseId',
        'attemptId',
        'stepExecutionId',
        'resourceId',
        'evidenceId',
      },
      '$path.owner',
      required: const <String>{'runId'},
    );
    return CockpitTestReportBundleFile(
      relativePath: CockpitTestValueReader.string(
        json['relativePath'],
        '$path.relativePath',
      ),
      kind: CockpitTestValueReader.string(json['kind'], '$path.kind'),
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
      runId: CockpitTestValueReader.string(
        owner['runId'],
        '$path.owner.runId',
        id: true,
      ),
      caseId: CockpitTestValueReader.optionalString(
        owner['caseId'],
        '$path.owner.caseId',
      ),
      attemptId: CockpitTestValueReader.optionalString(
        owner['attemptId'],
        '$path.owner.attemptId',
      ),
      stepExecutionId: CockpitTestValueReader.optionalString(
        owner['stepExecutionId'],
        '$path.owner.stepExecutionId',
      ),
      resourceId: CockpitTestValueReader.optionalString(
        owner['resourceId'],
        '$path.owner.resourceId',
      ),
      evidenceId: CockpitTestValueReader.optionalString(
        owner['evidenceId'],
        '$path.owner.evidenceId',
      ),
    );
  }
}

final class CockpitTestReportBundleManifest {
  /// Creates a CockpitTestReportBundleManifest.
  CockpitTestReportBundleManifest({
    this.schemaVersion = 'cockpit.report.manifest/v2',
    required this.runId,
    required this.createdAt,
    required Iterable<CockpitTestReportBundleFile> files,
  }) : files = List<CockpitTestReportBundleFile>.unmodifiable(files) {
    if (schemaVersion != 'cockpit.report.manifest/v2' || !createdAt.isUtc) {
      throw const FormatException('Report bundle manifest is invalid.');
    }
    CockpitTestValueReader.string(runId, r'$.runId', id: true);
    final paths = <String>{};
    for (final file in this.files) {
      if (file.runId != runId || !paths.add(file.relativePath)) {
        throw const FormatException(
          'Report bundle manifest ownership or paths are invalid.',
        );
      }
    }
  }

  final String schemaVersion;
  final String runId;
  final DateTime createdAt;
  final List<CockpitTestReportBundleFile> files;

  /// Encodes this CockpitTestReportBundleManifest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'runId': runId,
    'createdAt': createdAt.toIso8601String(),
    'files': files.map((file) => file.toJson()).toList(),
  };

  /// Decodes a CockpitTestReportBundleManifest from a JSON object.
  factory CockpitTestReportBundleManifest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'schemaVersion', 'runId', 'createdAt', 'files'},
      path,
      required: const <String>{'schemaVersion', 'runId', 'createdAt', 'files'},
    );
    final rawFiles = CockpitTestValueReader.list(json['files'], '$path.files');
    return CockpitTestReportBundleManifest(
      schemaVersion: CockpitTestValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      runId: CockpitTestValueReader.string(
        json['runId'],
        '$path.runId',
        id: true,
      ),
      createdAt: CockpitTestValueReader.dateTime(
        json['createdAt'],
        '$path.createdAt',
      ).toUtc(),
      files: <CockpitTestReportBundleFile>[
        for (var index = 0; index < rawFiles.length; index += 1)
          CockpitTestReportBundleFile.fromJson(
            rawFiles[index],
            path: '$path.files[$index]',
          ),
      ],
    );
  }
}

void _validateRelativePath(String value, String path) {
  CockpitTestValueReader.string(value, path);
  final parts = value.split('/');
  if (value.startsWith('/') ||
      value.contains(r'\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value) ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw FormatException('Expected a safe relative path at $path.');
  }
}
