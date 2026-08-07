import 'cockpit_test_value_reader.dart';

enum CockpitTestDiagnosticSeverity { error, warning }

final class CockpitTestSourceLocation {
  /// Creates a CockpitTestSourceLocation.
  CockpitTestSourceLocation({
    required this.line,
    required this.column,
    this.endLine,
    this.endColumn,
  }) {
    if (line < 1 || column < 1) {
      throw const FormatException('Source line and column must be positive.');
    }
    if ((endLine == null) != (endColumn == null)) {
      throw const FormatException(
        'Source endLine and endColumn must be provided together.',
      );
    }
    if (endLine != null &&
        (endLine! < line || (endLine == line && endColumn! < column))) {
      throw const FormatException('Source range ends before it starts.');
    }
  }

  final int line;
  final int column;
  final int? endLine;
  final int? endColumn;

  /// Encodes this CockpitTestSourceLocation as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'line': line,
    'column': column,
    if (endLine != null) 'endLine': endLine,
    if (endColumn != null) 'endColumn': endColumn,
  };

  /// Decodes a CockpitTestSourceLocation from a JSON object.
  factory CockpitTestSourceLocation.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'line', 'column', 'endLine', 'endColumn'},
      path,
      required: const <String>{'line', 'column'},
    );
    return CockpitTestSourceLocation(
      line: CockpitTestValueReader.integer(
        json['line'],
        '$path.line',
        minimum: 1,
      ),
      column: CockpitTestValueReader.integer(
        json['column'],
        '$path.column',
        minimum: 1,
      ),
      endLine: json['endLine'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['endLine'],
              '$path.endLine',
              minimum: 1,
            ),
      endColumn: json['endColumn'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['endColumn'],
              '$path.endColumn',
              minimum: 1,
            ),
    );
  }
}

final class CockpitTestSourceMapEntry {
  /// Creates a CockpitTestSourceMapEntry.
  CockpitTestSourceMapEntry({required this.path, required this.location}) {
    CockpitTestValueReader.string(path, r'$.path');
  }

  final String path;
  final CockpitTestSourceLocation location;

  /// Encodes this CockpitTestSourceMapEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'location': location.toJson(),
  };

  /// Decodes a CockpitTestSourceMapEntry from a JSON object.
  factory CockpitTestSourceMapEntry.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'path', 'location'},
      path,
      required: const <String>{'path', 'location'},
    );
    return CockpitTestSourceMapEntry(
      path: CockpitTestValueReader.string(json['path'], '$path.path'),
      location: CockpitTestSourceLocation.fromJson(
        json['location'],
        path: '$path.location',
      ),
    );
  }
}

final class CockpitTestDiagnostic {
  /// Creates a CockpitTestDiagnostic.
  CockpitTestDiagnostic({
    required this.code,
    required this.message,
    required this.path,
    this.severity = CockpitTestDiagnosticSeverity.error,
    this.location,
    Map<String, Object?> details = const <String, Object?>{},
  }) : details = Map<String, Object?>.unmodifiable(
         CockpitTestValueReader.object(
           CockpitTestValueReader.jsonValue(details, r'$.details'),
           r'$.details',
         ),
       ) {
    CockpitTestValueReader.string(code, r'$.code', id: true);
    CockpitTestValueReader.string(message, r'$.message');
    CockpitTestValueReader.string(path, r'$.path');
  }

  final String code;
  final String message;
  final String path;
  final CockpitTestDiagnosticSeverity severity;
  final CockpitTestSourceLocation? location;
  final Map<String, Object?> details;

  /// Encodes this CockpitTestDiagnostic as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'path': path,
    'severity': severity.name,
    if (location != null) 'location': location!.toJson(),
    if (details.isNotEmpty) 'details': details,
  };

  /// Decodes a CockpitTestDiagnostic from a JSON object.
  factory CockpitTestDiagnostic.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'code',
        'message',
        'path',
        'severity',
        'location',
        'details',
      },
      path,
      required: const <String>{'code', 'message', 'path', 'severity'},
    );
    return CockpitTestDiagnostic(
      code: CockpitTestValueReader.string(json['code'], '$path.code', id: true),
      message: CockpitTestValueReader.string(json['message'], '$path.message'),
      path: CockpitTestValueReader.string(json['path'], '$path.path'),
      severity: CockpitTestValueReader.enumeration(
        json['severity'],
        CockpitTestDiagnosticSeverity.values,
        '$path.severity',
      ),
      location: json['location'] == null
          ? null
          : CockpitTestSourceLocation.fromJson(
              json['location'],
              path: '$path.location',
            ),
      details: json['details'] == null
          ? const <String, Object?>{}
          : CockpitTestValueReader.object(json['details'], '$path.details'),
    );
  }
}
