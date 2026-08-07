import '../test/cockpit_test_case.dart';
import '../test/cockpit_test_diagnostic.dart';
import '../test/cockpit_test_document.dart';
import '../test/cockpit_test_project.dart';
import '../test/cockpit_test_suite.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitDocumentFormat { lon, json, yaml }

final class CockpitDocumentValidationRequest {
  /// Creates a CockpitDocumentValidationRequest.
  CockpitDocumentValidationRequest({
    required this.format,
    required this.sourceText,
    this.relativePath,
  }) {
    CockpitFoundationValueReader.boundedString(
      sourceText,
      r'$.sourceText',
      maximum: 1048576,
    );
    if (relativePath != null) {
      CockpitFoundationValueReader.relativePath(
        relativePath,
        r'$.relativePath',
      );
    }
  }

  final CockpitDocumentFormat format;
  final String sourceText;
  final String? relativePath;

  /// Encodes this CockpitDocumentValidationRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'format': format.name,
    'sourceText': sourceText,
    if (relativePath != null) 'relativePath': relativePath,
  };

  /// Decodes a CockpitDocumentValidationRequest from a JSON object.
  factory CockpitDocumentValidationRequest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'format', 'sourceText', 'relativePath'},
      path,
      required: const <String>{'format', 'sourceText'},
    );
    return CockpitDocumentValidationRequest(
      format: CockpitEnumValue<CockpitDocumentFormat>.parse(
        json['format'],
        CockpitDocumentFormat.values,
        '$path.format',
        policy: CockpitDecodePolicy.requests,
      ).requireKnown(),
      sourceText: CockpitFoundationValueReader.boundedString(
        json['sourceText'],
        '$path.sourceText',
        maximum: 1048576,
      ),
      relativePath: json['relativePath'] == null
          ? null
          : CockpitFoundationValueReader.relativePath(
              json['relativePath'],
              '$path.relativePath',
            ),
    );
  }
}

final class CockpitDocumentValidationResult {
  /// Creates a CockpitDocumentValidationResult.
  CockpitDocumentValidationResult({
    required this.valid,
    required this.sourceSha256,
    this.document,
    Iterable<CockpitTestDiagnostic> diagnostics =
        const <CockpitTestDiagnostic>[],
    Iterable<CockpitTestSourceMapEntry> sourceMap =
        const <CockpitTestSourceMapEntry>[],
  }) : diagnostics = List<CockpitTestDiagnostic>.unmodifiable(diagnostics),
       sourceMap = List<CockpitTestSourceMapEntry>.unmodifiable(sourceMap) {
    CockpitFoundationValueReader.sha256(sourceSha256, r'$.sourceSha256');
    final hasErrors = this.diagnostics.any(
      (diagnostic) =>
          diagnostic.severity == CockpitTestDiagnosticSeverity.error,
    );
    if (valid != (document != null && !hasErrors) ||
        (!valid && this.diagnostics.isEmpty)) {
      throw const FormatException('Validation result is inconsistent.');
    }
  }

  final bool valid;
  final String sourceSha256;
  final CockpitTestDocument? document;
  final List<CockpitTestDiagnostic> diagnostics;
  final List<CockpitTestSourceMapEntry> sourceMap;

  /// Encodes this CockpitDocumentValidationResult as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'valid': valid,
    'sourceSha256': sourceSha256,
    if (document != null) 'document': document!.toJson(),
    'diagnostics': diagnostics
        .map((diagnostic) => diagnostic.toJson())
        .toList(),
    'sourceMap': sourceMap.map((entry) => entry.toJson()).toList(),
  };

  /// Decodes a CockpitDocumentValidationResult from a JSON object.
  factory CockpitDocumentValidationResult.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'valid',
        'sourceSha256',
        'document',
        'diagnostics',
        'sourceMap',
      },
      path,
      required: const <String>{
        'valid',
        'sourceSha256',
        'diagnostics',
        'sourceMap',
      },
      policy: decodePolicy,
    );
    final rawDiagnostics = CockpitFoundationValueReader.list(
      json['diagnostics'],
      '$path.diagnostics',
    );
    final rawSourceMap = CockpitFoundationValueReader.list(
      json['sourceMap'],
      '$path.sourceMap',
    );
    return CockpitDocumentValidationResult(
      valid: CockpitFoundationValueReader.boolean(json['valid'], '$path.valid'),
      sourceSha256: CockpitFoundationValueReader.sha256(
        json['sourceSha256'],
        '$path.sourceSha256',
      ),
      document: json['document'] == null
          ? null
          : _document(json['document'], '$path.document'),
      diagnostics: <CockpitTestDiagnostic>[
        for (var index = 0; index < rawDiagnostics.length; index += 1)
          CockpitTestDiagnostic.fromJson(
            rawDiagnostics[index],
            path: '$path.diagnostics[$index]',
          ),
      ],
      sourceMap: <CockpitTestSourceMapEntry>[
        for (var index = 0; index < rawSourceMap.length; index += 1)
          CockpitTestSourceMapEntry.fromJson(
            rawSourceMap[index],
            path: '$path.sourceMap[$index]',
          ),
      ],
    );
  }
}

CockpitTestDocument _document(Object? value, String path) {
  final json = CockpitFoundationValueReader.object(value, path);
  final kind = CockpitFoundationValueReader.string(json['kind'], '$path.kind');
  return switch (kind) {
    'case' => CockpitTestCase.fromJson(value, path: path),
    'suite' => CockpitTestSuite.fromJson(value, path: path),
    'project' => CockpitTestProject.fromJson(value, path: path),
    _ => throw FormatException('Unsupported document kind at $path.kind.'),
  };
}
