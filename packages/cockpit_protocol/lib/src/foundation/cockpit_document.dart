import '../test/cockpit_test_diagnostic.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitIndexedDocumentKind { source, testCase, suite, project }

final class CockpitCaseIndexEntry {
  /// Creates a CockpitCaseIndexEntry.
  CockpitCaseIndexEntry({
    required this.caseId,
    this.documentId,
    this.relativePath,
    this.title,
    this.location,
  }) {
    CockpitFoundationValueReader.id(caseId, r'$.caseId');
    if ((documentId == null) != (relativePath == null)) {
      throw const FormatException(
        'Indexed case document identity must include both documentId and relativePath.',
      );
    }
    if (documentId != null) {
      CockpitFoundationValueReader.id(documentId!, r'$.documentId');
      CockpitFoundationValueReader.relativePath(
        relativePath!,
        r'$.relativePath',
      );
    }
    if (title != null) {
      CockpitFoundationValueReader.string(title, r'$.title', maximum: 256);
    }
  }

  final String caseId;
  final String? documentId;
  final String? relativePath;
  final String? title;
  final CockpitTestSourceLocation? location;

  /// Encodes this CockpitCaseIndexEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'caseId': caseId,
    if (documentId != null) 'documentId': documentId,
    if (relativePath != null) 'relativePath': relativePath,
    if (title != null) 'title': title,
    if (location != null) 'location': location!.toJson(),
  };

  /// Decodes a CockpitCaseIndexEntry from a JSON object.
  factory CockpitCaseIndexEntry.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'caseId',
        'documentId',
        'relativePath',
        'title',
        'location',
      },
      path,
      required: const <String>{'caseId'},
      policy: decodePolicy,
    );
    return CockpitCaseIndexEntry(
      caseId: CockpitFoundationValueReader.id(json['caseId'], '$path.caseId'),
      documentId: json['documentId'] == null
          ? null
          : CockpitFoundationValueReader.id(
              json['documentId'],
              '$path.documentId',
            ),
      relativePath: json['relativePath'] == null
          ? null
          : CockpitFoundationValueReader.relativePath(
              json['relativePath'],
              '$path.relativePath',
            ),
      title: CockpitFoundationValueReader.optionalString(
        json['title'],
        '$path.title',
        maximum: 256,
      ),
      location: json['location'] == null
          ? null
          : CockpitTestSourceLocation.fromJson(
              json['location'],
              path: '$path.location',
            ),
    );
  }
}

final class CockpitDocumentResource {
  /// Creates a CockpitDocumentResource.
  CockpitDocumentResource({
    required this.documentId,
    required this.workspaceId,
    required this.relativePath,
    required this.sha256,
    required this.modifiedAt,
    required this.kind,
    this.authoredId,
    this.title,
    Iterable<CockpitCaseIndexEntry> cases = const <CockpitCaseIndexEntry>[],
  }) : cases = List<CockpitCaseIndexEntry>.unmodifiable(cases) {
    CockpitFoundationValueReader.id(documentId, r'$.documentId');
    CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    CockpitFoundationValueReader.relativePath(relativePath, r'$.relativePath');
    CockpitFoundationValueReader.sha256(sha256, r'$.sha256');
    CockpitFoundationValueReader.utcDateTime(modifiedAt, r'$.modifiedAt');
    if (authoredId != null) {
      CockpitFoundationValueReader.id(authoredId!, r'$.authoredId');
    }
    if (title != null) {
      CockpitFoundationValueReader.string(title!, r'$.title', maximum: 256);
    }
    if ((kind == CockpitIndexedDocumentKind.source) != (authoredId == null)) {
      throw const FormatException(
        'Indexed document kind and authored identity disagree.',
      );
    }
    final caseIds = <String>{};
    for (final testCase in this.cases) {
      if (!caseIds.add(testCase.caseId)) {
        throw FormatException('Duplicate case ${testCase.caseId}.');
      }
    }
  }

  final String documentId;
  final String workspaceId;
  final String relativePath;
  final String sha256;
  final DateTime modifiedAt;
  final CockpitIndexedDocumentKind kind;
  final String? authoredId;
  final String? title;
  final List<CockpitCaseIndexEntry> cases;

  /// Encodes this CockpitDocumentResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    'workspaceId': workspaceId,
    'relativePath': relativePath,
    'sha256': sha256,
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'kind': kind == CockpitIndexedDocumentKind.testCase ? 'case' : kind.name,
    if (authoredId != null) 'authoredId': authoredId,
    if (title != null) 'title': title,
    'cases': cases.map((testCase) => testCase.toJson()).toList(),
  };

  /// Decodes a CockpitDocumentResource from a JSON object.
  factory CockpitDocumentResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'documentId',
      'workspaceId',
      'relativePath',
      'sha256',
      'modifiedAt',
      'kind',
      'authoredId',
      'title',
      'cases',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields.difference(const <String>{'authoredId', 'title'}),
      policy: decodePolicy,
    );
    final rawCases = CockpitFoundationValueReader.list(
      json['cases'],
      '$path.cases',
    );
    return CockpitDocumentResource(
      documentId: CockpitFoundationValueReader.id(
        json['documentId'],
        '$path.documentId',
      ),
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      relativePath: CockpitFoundationValueReader.relativePath(
        json['relativePath'],
        '$path.relativePath',
      ),
      sha256: CockpitFoundationValueReader.sha256(
        json['sha256'],
        '$path.sha256',
      ),
      modifiedAt: CockpitFoundationValueReader.dateTime(
        json['modifiedAt'],
        '$path.modifiedAt',
      ),
      kind: _documentKind(json['kind'], '$path.kind'),
      authoredId: json['authoredId'] == null
          ? null
          : CockpitFoundationValueReader.id(
              json['authoredId'],
              '$path.authoredId',
            ),
      title: CockpitFoundationValueReader.optionalString(
        json['title'],
        '$path.title',
        maximum: 256,
      ),
      cases: <CockpitCaseIndexEntry>[
        for (var index = 0; index < rawCases.length; index += 1)
          CockpitCaseIndexEntry.fromJson(
            rawCases[index],
            path: '$path.cases[$index]',
            decodePolicy: decodePolicy,
          ),
      ],
    );
  }
}

CockpitIndexedDocumentKind _documentKind(Object? value, String path) {
  final name = CockpitFoundationValueReader.string(value, path);
  if (name == 'case') return CockpitIndexedDocumentKind.testCase;
  return CockpitEnumValue<CockpitIndexedDocumentKind>.parse(
    name,
    CockpitIndexedDocumentKind.values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}

final class CockpitIndexedCaseReference {
  /// Creates a CockpitIndexedCaseReference.
  CockpitIndexedCaseReference({
    required this.documentId,
    required this.caseId,
    required this.documentSha256,
  }) {
    CockpitFoundationValueReader.id(documentId, r'$.documentId');
    CockpitFoundationValueReader.id(caseId, r'$.caseId');
    CockpitFoundationValueReader.sha256(documentSha256, r'$.documentSha256');
  }

  final String documentId;
  final String caseId;
  final String documentSha256;

  /// Encodes this CockpitIndexedCaseReference as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    'caseId': caseId,
    'documentSha256': documentSha256,
  };

  /// Decodes a CockpitIndexedCaseReference from a JSON object.
  factory CockpitIndexedCaseReference.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{'documentId', 'caseId', 'documentSha256'};
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields,
      policy: decodePolicy,
    );
    return CockpitIndexedCaseReference(
      documentId: CockpitFoundationValueReader.id(
        json['documentId'],
        '$path.documentId',
      ),
      caseId: CockpitFoundationValueReader.id(json['caseId'], '$path.caseId'),
      documentSha256: CockpitFoundationValueReader.sha256(
        json['documentSha256'],
        '$path.documentSha256',
      ),
    );
  }
}

final class CockpitIndexedSuiteReference {
  /// Creates a CockpitIndexedSuiteReference.
  CockpitIndexedSuiteReference({
    required this.documentId,
    required this.suiteId,
    required this.documentSha256,
  }) {
    CockpitFoundationValueReader.id(documentId, r'$.documentId');
    CockpitFoundationValueReader.id(suiteId, r'$.suiteId');
    CockpitFoundationValueReader.sha256(documentSha256, r'$.documentSha256');
  }

  final String documentId;
  final String suiteId;
  final String documentSha256;

  /// Encodes this CockpitIndexedSuiteReference as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'documentId': documentId,
    'suiteId': suiteId,
    'documentSha256': documentSha256,
  };

  /// Decodes a CockpitIndexedSuiteReference from a JSON object.
  factory CockpitIndexedSuiteReference.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{'documentId', 'suiteId', 'documentSha256'};
    CockpitFoundationValueReader.keys(json, fields, path, required: fields);
    return CockpitIndexedSuiteReference(
      documentId: CockpitFoundationValueReader.id(
        json['documentId'],
        '$path.documentId',
      ),
      suiteId: CockpitFoundationValueReader.id(
        json['suiteId'],
        '$path.suiteId',
      ),
      documentSha256: CockpitFoundationValueReader.sha256(
        json['documentSha256'],
        '$path.documentSha256',
      ),
    );
  }
}
