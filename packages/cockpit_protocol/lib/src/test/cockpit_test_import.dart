import 'cockpit_test_case.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestImportRequest {
  /// Creates a CockpitTestImportRequest.
  CockpitTestImportRequest({
    required this.sourceVersion,
    required this.sourceText,
    required this.projectId,
    required this.workspaceId,
    required this.caseId,
    required this.engineVersion,
  }) {
    if (sourceVersion != 1) {
      throw const FormatException(
        'Only Cockpit control schema version 1 imports.',
      );
    }
    if (sourceText.trim().isEmpty) {
      throw const FormatException('Import source cannot be empty.');
    }
    for (final entry in <String, String>{
      'projectId': projectId,
      'workspaceId': workspaceId,
      'caseId': caseId,
    }.entries) {
      CockpitTestValueReader.string(entry.value, entry.key, id: true);
    }
    CockpitTestValueReader.string(engineVersion, 'engineVersion');
  }

  final int sourceVersion;
  final String sourceText;
  final String projectId;
  final String workspaceId;
  final String caseId;
  final String engineVersion;

  /// Encodes this CockpitTestImportRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sourceVersion': sourceVersion,
    'sourceText': sourceText,
    'projectId': projectId,
    'workspaceId': workspaceId,
    'caseId': caseId,
    'engineVersion': engineVersion,
  };

  /// Decodes a CockpitTestImportRequest from a JSON object.
  factory CockpitTestImportRequest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    const fields = <String>{
      'sourceVersion',
      'sourceText',
      'projectId',
      'workspaceId',
      'caseId',
      'engineVersion',
    };
    CockpitTestValueReader.keys(json, fields, path, required: fields);
    return CockpitTestImportRequest(
      sourceVersion: CockpitTestValueReader.integer(
        json['sourceVersion'],
        '$path.sourceVersion',
      ),
      sourceText: CockpitTestValueReader.string(
        json['sourceText'],
        '$path.sourceText',
      ),
      projectId: CockpitTestValueReader.string(
        json['projectId'],
        '$path.projectId',
        id: true,
      ),
      workspaceId: CockpitTestValueReader.string(
        json['workspaceId'],
        '$path.workspaceId',
        id: true,
      ),
      caseId: CockpitTestValueReader.string(
        json['caseId'],
        '$path.caseId',
        id: true,
      ),
      engineVersion: CockpitTestValueReader.string(
        json['engineVersion'],
        '$path.engineVersion',
      ),
    );
  }
}

final class CockpitTestImportMapping {
  /// Creates a CockpitTestImportMapping.
  CockpitTestImportMapping({
    required this.sourcePath,
    required this.destinationPath,
  }) {
    CockpitTestValueReader.string(sourcePath, r'$.sourcePath');
    CockpitTestValueReader.string(destinationPath, r'$.destinationPath');
  }

  final String sourcePath;
  final String destinationPath;

  /// Encodes this CockpitTestImportMapping as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sourcePath': sourcePath,
    'destinationPath': destinationPath,
  };

  /// Decodes a CockpitTestImportMapping from a JSON object.
  factory CockpitTestImportMapping.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'sourcePath', 'destinationPath'},
      path,
      required: const <String>{'sourcePath', 'destinationPath'},
    );
    return CockpitTestImportMapping(
      sourcePath: CockpitTestValueReader.string(
        json['sourcePath'],
        '$path.sourcePath',
      ),
      destinationPath: CockpitTestValueReader.string(
        json['destinationPath'],
        '$path.destinationPath',
      ),
    );
  }
}

final class CockpitTestImportManifest {
  /// Creates a CockpitTestImportManifest.
  CockpitTestImportManifest({
    this.schemaVersion = 'cockpit.import/v2',
    required this.sourceVersion,
    required this.sourceSha256,
    required this.projectId,
    required this.workspaceId,
    required this.caseId,
    required this.engineVersion,
    Iterable<CockpitTestImportMapping> mappings =
        const <CockpitTestImportMapping>[],
    Iterable<String> warnings = const <String>[],
  }) : mappings = List<CockpitTestImportMapping>.unmodifiable(mappings),
       warnings = List<String>.unmodifiable(warnings) {
    if (schemaVersion != 'cockpit.import/v2' || sourceVersion != 1) {
      throw const FormatException('Invalid import manifest version.');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256)) {
      throw const FormatException('Invalid import source SHA-256.');
    }
    for (final entry in <String, String>{
      'projectId': projectId,
      'workspaceId': workspaceId,
      'caseId': caseId,
    }.entries) {
      CockpitTestValueReader.string(entry.value, entry.key, id: true);
    }
    CockpitTestValueReader.string(engineVersion, 'engineVersion');
    final sourcePaths = <String>{};
    final destinationPaths = <String>{};
    for (final mapping in this.mappings) {
      if (!sourcePaths.add(mapping.sourcePath) ||
          !destinationPaths.add(mapping.destinationPath)) {
        throw const FormatException('Import mappings must be one-to-one.');
      }
    }
    final uniqueWarnings = <String>{};
    for (var index = 0; index < this.warnings.length; index += 1) {
      final warning = CockpitTestValueReader.string(
        this.warnings[index],
        '\$.warnings[$index]',
      );
      if (!uniqueWarnings.add(warning)) {
        throw const FormatException('Import warnings must be unique.');
      }
    }
  }

  final String schemaVersion;
  final int sourceVersion;
  final String sourceSha256;
  final String projectId;
  final String workspaceId;
  final String caseId;
  final String engineVersion;
  final List<CockpitTestImportMapping> mappings;
  final List<String> warnings;

  /// Encodes this CockpitTestImportManifest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'sourceVersion': sourceVersion,
    'sourceSha256': sourceSha256,
    'projectId': projectId,
    'workspaceId': workspaceId,
    'caseId': caseId,
    'engineVersion': engineVersion,
    'mappings': mappings.map((mapping) => mapping.toJson()).toList(),
    'warnings': warnings,
  };

  /// Decodes a CockpitTestImportManifest from a JSON object.
  factory CockpitTestImportManifest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    const fields = <String>{
      'schemaVersion',
      'sourceVersion',
      'sourceSha256',
      'projectId',
      'workspaceId',
      'caseId',
      'engineVersion',
      'mappings',
      'warnings',
    };
    CockpitTestValueReader.keys(json, fields, path, required: fields);
    final rawMappings = CockpitTestValueReader.list(
      json['mappings'],
      '$path.mappings',
    );
    return CockpitTestImportManifest(
      schemaVersion: CockpitTestValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      sourceVersion: CockpitTestValueReader.integer(
        json['sourceVersion'],
        '$path.sourceVersion',
      ),
      sourceSha256: CockpitTestValueReader.string(
        json['sourceSha256'],
        '$path.sourceSha256',
      ),
      projectId: CockpitTestValueReader.string(
        json['projectId'],
        '$path.projectId',
        id: true,
      ),
      workspaceId: CockpitTestValueReader.string(
        json['workspaceId'],
        '$path.workspaceId',
        id: true,
      ),
      caseId: CockpitTestValueReader.string(
        json['caseId'],
        '$path.caseId',
        id: true,
      ),
      engineVersion: CockpitTestValueReader.string(
        json['engineVersion'],
        '$path.engineVersion',
      ),
      mappings: <CockpitTestImportMapping>[
        for (var index = 0; index < rawMappings.length; index += 1)
          CockpitTestImportMapping.fromJson(
            rawMappings[index],
            path: '$path.mappings[$index]',
          ),
      ],
      warnings: CockpitTestValueReader.strings(
        json['warnings'],
        '$path.warnings',
        unique: true,
      ),
    );
  }
}

final class CockpitTestImportResult {
  /// Creates a CockpitTestImportResult.
  CockpitTestImportResult({required this.testCase, required this.manifest}) {
    if (testCase.id != manifest.caseId) {
      throw const FormatException(
        'Imported case and manifest identities differ.',
      );
    }
  }

  final CockpitTestCase testCase;
  final CockpitTestImportManifest manifest;

  /// Encodes this CockpitTestImportResult as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'case': testCase.toJson(),
    'manifest': manifest.toJson(),
  };

  /// Decodes a CockpitTestImportResult from a JSON object.
  factory CockpitTestImportResult.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'case', 'manifest'},
      path,
      required: const <String>{'case', 'manifest'},
    );
    return CockpitTestImportResult(
      testCase: CockpitTestCase.fromJson(json['case'], path: '$path.case'),
      manifest: CockpitTestImportManifest.fromJson(
        json['manifest'],
        path: '$path.manifest',
      ),
    );
  }
}
