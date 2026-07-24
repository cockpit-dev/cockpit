import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:json_schema/json_schema.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

sealed class CockpitCompiledTestDocument {
  CockpitCompiledTestDocument({
    required this.document,
    required this.sourceSha256,
    required Map<String, CockpitTestSourceLocation> sourceMap,
  }) : sourceMap = Map<String, CockpitTestSourceLocation>.unmodifiable(
         sourceMap,
       );

  final CockpitTestDocument document;
  final String sourceSha256;
  final Map<String, CockpitTestSourceLocation> sourceMap;

  CockpitTestSourceLocation? locationFor(String path) {
    var candidate = path;
    while (candidate.isNotEmpty) {
      final exact = sourceMap[candidate];
      if (exact != null) {
        return exact;
      }
      final parent = _parentPath(candidate);
      if (parent == null) {
        break;
      }
      candidate = parent;
    }
    return sourceMap[r'$'];
  }
}

final class CockpitCompiledTestCase extends CockpitCompiledTestDocument {
  CockpitCompiledTestCase({
    required this.testCase,
    required super.sourceSha256,
    required super.sourceMap,
  }) : super(document: testCase);

  final CockpitTestCase testCase;
}

final class CockpitCompiledTestSuite extends CockpitCompiledTestDocument {
  CockpitCompiledTestSuite({
    required this.suite,
    required super.sourceSha256,
    required super.sourceMap,
  }) : super(document: suite);

  final CockpitTestSuite suite;
}

final class CockpitCompiledTestProject extends CockpitCompiledTestDocument {
  CockpitCompiledTestProject({
    required this.project,
    required super.sourceSha256,
    required super.sourceMap,
  }) : super(document: project);

  final CockpitTestProject project;
}

final class CockpitTestCompilationResult {
  CockpitTestCompilationResult({
    this.compiled,
    Iterable<CockpitTestDiagnostic> diagnostics =
        const <CockpitTestDiagnostic>[],
  }) : diagnostics = List<CockpitTestDiagnostic>.unmodifiable(diagnostics) {
    if ((compiled == null) == this.diagnostics.isEmpty) {
      throw ArgumentError(
        'A compilation result must contain either output or diagnostics.',
      );
    }
  }

  final CockpitCompiledTestDocument? compiled;
  final List<CockpitTestDiagnostic> diagnostics;

  bool get isSuccess => compiled != null;

  CockpitCompiledTestDocument requireCompiled() {
    final value = compiled;
    if (value == null) {
      throw FormatException(
        diagnostics.map((diagnostic) => diagnostic.message).join('\n'),
      );
    }
    return value;
  }

  CockpitCompiledTestCase requireCase() {
    final value = requireCompiled();
    if (value is! CockpitCompiledTestCase) {
      throw const FormatException('Expected a case document.');
    }
    return value;
  }

  CockpitCompiledTestSuite requireSuite() {
    final value = requireCompiled();
    if (value is! CockpitCompiledTestSuite) {
      throw const FormatException('Expected a suite document.');
    }
    return value;
  }

  CockpitCompiledTestProject requireProject() {
    final value = requireCompiled();
    if (value is! CockpitCompiledTestProject) {
      throw const FormatException('Expected a project document.');
    }
    return value;
  }
}

final class CockpitTestDocumentCompiler {
  const CockpitTestDocumentCompiler();

  static const int _maximumDocumentBytes = 16777216;
  static final Map<String, Object?> _schemaDocument = Map<String, Object?>.from(
    jsonDecode(cockpitTestV2SchemaJson) as Map<Object?, Object?>,
  );
  static final JsonSchema _schema = JsonSchema.create(_schemaDocument);
  static final Map<String, JsonSchema> _schemasByKind =
      Map<String, JsonSchema>.unmodifiable(<String, JsonSchema>{
        for (final kind in const <String>['case', 'suite', 'project'])
          kind: JsonSchema.create(<String, Object?>{
            r'$schema': _schemaDocument[r'$schema'],
            r'$defs': _schemaDocument[r'$defs'],
            r'$ref': '#/\$defs/$kind',
          }),
      });

  CockpitTestCompilationResult compile(String source) {
    final bytes = utf8.encode(source);
    if (bytes.length > _maximumDocumentBytes) {
      return _failure(
        'documentTooLarge',
        'Document exceeds the absolute $_maximumDocumentBytes byte limit.',
        r'$',
      );
    }
    final sourceMap = <String, CockpitTestSourceLocation>{};
    Object? normalized;
    try {
      final root = loadYamlNode(source);
      normalized = _normalizeNode(root, r'$', sourceMap);
    } on YamlException catch (error) {
      final span = error.span;
      return CockpitTestCompilationResult(
        diagnostics: <CockpitTestDiagnostic>[
          CockpitTestDiagnostic(
            code: 'parseFailed',
            message: error.message,
            path: r'$',
            location: span == null ? null : _location(span),
          ),
        ],
      );
    } on FormatException catch (error) {
      return _failure('parseFailed', error.message, r'$');
    }

    final schemaDiagnostics = _validateSchema(
      normalized,
      sourceMap,
      schema: _schemaFor(normalized),
    );
    if (schemaDiagnostics.isNotEmpty) {
      final diagnostics = <CockpitTestDiagnostic>[...schemaDiagnostics];
      try {
        _decodeDocument(normalized);
      } on FormatException catch (error) {
        final path = _pathFromMessage(error.message);
        diagnostics.removeWhere(
          (diagnostic) =>
              path == diagnostic.path ||
              path.startsWith('${diagnostic.path}.') ||
              path.startsWith('${diagnostic.path}['),
        );
        diagnostics.add(
          CockpitTestDiagnostic(
            code: 'validationFailed',
            message: error.message,
            path: path,
            location: _nearestLocation(sourceMap, path),
          ),
        );
      }
      diagnostics.sort(_compareDiagnostics);
      return CockpitTestCompilationResult(
        diagnostics: List<CockpitTestDiagnostic>.unmodifiable(diagnostics),
      );
    }

    CockpitTestDocument document;
    try {
      document = _decodeDocument(normalized);
    } on FormatException catch (error) {
      final path = _pathFromMessage(error.message);
      return CockpitTestCompilationResult(
        diagnostics: <CockpitTestDiagnostic>[
          CockpitTestDiagnostic(
            code: 'validationFailed',
            message: error.message,
            path: path,
            location: _nearestLocation(sourceMap, path),
          ),
        ],
      );
    }

    final documentLimit = document is CockpitTestCase
        ? document.defaults.limits.maxDocumentBytes
        : _maximumDocumentBytes;
    if (bytes.length > documentLimit) {
      const path = r'$.defaults.limits.maxDocumentBytes';
      return CockpitTestCompilationResult(
        diagnostics: <CockpitTestDiagnostic>[
          CockpitTestDiagnostic(
            code: 'documentTooLarge',
            message: 'Document exceeds its declared $documentLimit byte limit.',
            path: path,
            location: _nearestLocation(sourceMap, path),
          ),
        ],
      );
    }

    final diagnostics = document is CockpitTestCase
        ? _validate(document, sourceMap)
        : const <CockpitTestDiagnostic>[];
    if (diagnostics.isNotEmpty) {
      return CockpitTestCompilationResult(diagnostics: diagnostics);
    }
    return CockpitTestCompilationResult(
      compiled: _compiledDocument(
        document,
        sha256.convert(bytes).toString(),
        sourceMap,
      ),
    );
  }

  CockpitTestCompilationResult _failure(
    String code,
    String message,
    String path,
  ) => CockpitTestCompilationResult(
    diagnostics: <CockpitTestDiagnostic>[
      CockpitTestDiagnostic(code: code, message: message, path: path),
    ],
  );

  static JsonSchema _schemaFor(Object? document) {
    if (document is Map<Object?, Object?> && document['kind'] is String) {
      return _schemasByKind[document['kind']] ?? _schema;
    }
    return _schema;
  }
}

CockpitTestDocument _decodeDocument(Object? value) {
  if (value is! Map<Object?, Object?> || value['kind'] is! String) {
    throw const FormatException(r'Expected a document object at $.');
  }
  final kind = value['kind']! as String;
  return switch (kind) {
    'case' => CockpitTestCase.fromJson(value),
    'suite' => CockpitTestSuite.fromJson(value),
    'project' => CockpitTestProject.fromJson(value),
    _ => throw const FormatException(r'Unsupported document kind at $.kind.'),
  };
}

CockpitCompiledTestDocument _compiledDocument(
  CockpitTestDocument document,
  String sourceSha256,
  Map<String, CockpitTestSourceLocation> sourceMap,
) => switch (document) {
  CockpitTestCase testCase => CockpitCompiledTestCase(
    testCase: testCase,
    sourceSha256: sourceSha256,
    sourceMap: sourceMap,
  ),
  CockpitTestSuite suite => CockpitCompiledTestSuite(
    suite: suite,
    sourceSha256: sourceSha256,
    sourceMap: sourceMap,
  ),
  CockpitTestProject project => CockpitCompiledTestProject(
    project: project,
    sourceSha256: sourceSha256,
    sourceMap: sourceMap,
  ),
  _ => throw StateError('Unsupported compiled document ${document.kind}.'),
};

List<CockpitTestDiagnostic> _validateSchema(
  Object? document,
  Map<String, CockpitTestSourceLocation> sourceMap, {
  required JsonSchema schema,
}) {
  final errors = schema.validate(document).errors;
  final diagnostics = <CockpitTestDiagnostic>[];
  final seen = <String>{};
  for (final error in errors) {
    final path = _schemaErrorPath(document, error.instancePath, error.message);
    final key = '$path\u0000${error.message}';
    if (!seen.add(key)) continue;
    diagnostics.add(
      CockpitTestDiagnostic(
        code: 'validationFailed',
        message: error.message,
        path: path,
        location: _nearestLocation(sourceMap, path),
      ),
    );
  }
  diagnostics.sort(_compareDiagnostics);
  return List<CockpitTestDiagnostic>.unmodifiable(diagnostics);
}

String _schemaErrorPath(Object? document, String pointer, String message) {
  final base = _jsonPointerPath(pointer);
  final additionalProperty = RegExp(
    r'^unallowed additional property (.+)$',
  ).firstMatch(message);
  if (additionalProperty != null) {
    return _childPath(base, additionalProperty.group(1)!);
  }
  final value = _valueAtPointer(document, pointer);
  if (message.contains('/oneOf:') && value is Map) {
    final type = value['type'];
    if (type is String &&
        !CockpitTestActionKind.values.any((kind) => kind.name == type)) {
      return _childPath(base, 'type');
    }
  }
  return base;
}

Object? _valueAtPointer(Object? document, String pointer) {
  var value = document;
  if (pointer.isEmpty) return value;
  for (final encoded in pointer.split('/').skip(1)) {
    final segment = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
    if (value is Map) {
      value = value[segment];
      continue;
    }
    if (value is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= value.length) return null;
      value = value[index];
      continue;
    }
    return null;
  }
  return value;
}

String _jsonPointerPath(String pointer) {
  if (pointer.isEmpty) return r'$';
  final segments = pointer
      .split('/')
      .skip(1)
      .map((segment) => segment.replaceAll('~1', '/').replaceAll('~0', '~'));
  var path = r'$';
  for (final segment in segments) {
    final index = int.tryParse(segment);
    if (index != null && index.toString() == segment) {
      path = '$path[$index]';
    } else {
      path = _childPath(path, segment);
    }
  }
  return path;
}

int _compareDiagnostics(
  CockpitTestDiagnostic left,
  CockpitTestDiagnostic right,
) {
  final leftLocation = left.location;
  final rightLocation = right.location;
  final line = (leftLocation?.line ?? 0x7fffffff).compareTo(
    rightLocation?.line ?? 0x7fffffff,
  );
  if (line != 0) return line;
  final column = (leftLocation?.column ?? 0x7fffffff).compareTo(
    rightLocation?.column ?? 0x7fffffff,
  );
  if (column != 0) return column;
  final path = left.path.compareTo(right.path);
  if (path != 0) return path;
  return left.message.compareTo(right.message);
}

Object? _normalizeNode(
  YamlNode node,
  String path,
  Map<String, CockpitTestSourceLocation> sourceMap,
) {
  sourceMap[path] = _location(node.span);
  if (node is YamlMap) {
    final result = <String, Object?>{};
    for (final entry in node.nodes.entries) {
      final keyNode = entry.key;
      final key = keyNode.value;
      if (key is! String || key.trim().isEmpty) {
        throw FormatException('Expected a non-empty string key at $path.');
      }
      final childPath = _childPath(path, key);
      if (result.containsKey(key)) {
        throw FormatException('Duplicate key at $childPath.');
      }
      result[key] = _normalizeNode(entry.value, childPath, sourceMap);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  if (node is YamlList) {
    return List<Object?>.unmodifiable(<Object?>[
      for (var index = 0; index < node.nodes.length; index += 1)
        _normalizeNode(node.nodes[index], '$path[$index]', sourceMap),
    ]);
  }
  final value = node.value;
  if (value == null ||
      value is String ||
      value is bool ||
      value is int ||
      value is double && value.isFinite) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  throw FormatException('Unsupported scalar at $path.');
}

String _childPath(String parent, String key) {
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(key)) {
    return '$parent.$key';
  }
  return '$parent[${jsonEncode(key)}]';
}

CockpitTestSourceLocation _location(SourceSpan span) =>
    CockpitTestSourceLocation(
      line: span.start.line + 1,
      column: span.start.column + 1,
      endLine: span.end.line + 1,
      endColumn: span.end.column + 1,
    );

CockpitTestSourceLocation? _nearestLocation(
  Map<String, CockpitTestSourceLocation> sourceMap,
  String path,
) {
  var candidate = path;
  while (candidate.isNotEmpty) {
    final location = sourceMap[candidate];
    if (location != null) {
      return location;
    }
    final parent = _parentPath(candidate);
    if (parent == null) {
      break;
    }
    candidate = parent;
  }
  return sourceMap[r'$'];
}

String _pathFromMessage(String message) {
  final match = RegExp(
    r'''(\$(?:(?:\.[A-Za-z_][A-Za-z0-9_-]*)|(?:\[(?:\d+|"(?:\\.|[^"\\])*")\]))*)''',
  ).firstMatch(message);
  return match?.group(1) ?? r'$';
}

List<CockpitTestDiagnostic> _validate(
  CockpitTestCase testCase,
  Map<String, CockpitTestSourceLocation> sourceMap,
) {
  final diagnostics = <CockpitTestDiagnostic>[];
  final stepPaths = <String, String>{};
  final calls = <String, Set<String>>{};
  final limits = testCase.defaults.limits;

  void add(String code, String message, String path) {
    diagnostics.add(
      CockpitTestDiagnostic(
        code: code,
        message: message,
        path: path,
        location: _nearestLocation(sourceMap, path),
      ),
    );
  }

  void walk(
    List<CockpitTestStepTemplate> steps,
    String path, {
    required int depth,
    required String owner,
  }) {
    if (depth > limits.maxNesting) {
      add(
        'nestingLimitExceeded',
        'Control nesting exceeds ${limits.maxNesting}.',
        path,
      );
      return;
    }
    for (var index = 0; index < steps.length; index += 1) {
      final step = steps[index];
      final stepPath = '$path[$index]';
      final previous = stepPaths[step.stepId];
      if (previous != null) {
        add(
          'duplicateStepId',
          'stepId ${step.stepId} is already declared at $previous.',
          '$stepPath.stepId',
        );
      } else {
        stepPaths[step.stepId] = '$stepPath.stepId';
      }
      final operation = step.operation;
      switch (operation) {
        case CockpitTestActionOperationTemplate():
          _validateActionReferences(
            operation.action,
            '$stepPath.action',
            testCase.variables,
            add,
          );
        case CockpitTestIfOperationTemplate():
          _validateConditionReferences(
            operation.condition,
            '$stepPath.if.condition',
            testCase.variables,
            add,
          );
          walk(
            operation.thenSteps,
            '$stepPath.if.then',
            depth: depth + 1,
            owner: owner,
          );
          walk(
            operation.elseSteps,
            '$stepPath.if.else',
            depth: depth + 1,
            owner: owner,
          );
        case CockpitTestRetryOperationTemplate():
          if (operation.maxAttempts > limits.maxRetryAttempts) {
            add(
              'retryLimitExceeded',
              'Retry attempts exceed ${limits.maxRetryAttempts}.',
              '$stepPath.retry.maxAttempts',
            );
          }
          walk(
            operation.steps,
            '$stepPath.retry.steps',
            depth: depth + 1,
            owner: owner,
          );
        case CockpitTestLoopOperationTemplate():
          if (operation.maxIterations > limits.maxLoopIterations) {
            add(
              'loopLimitExceeded',
              'Loop iterations exceed ${limits.maxLoopIterations}.',
              '$stepPath.loop.maxIterations',
            );
          }
          _validateConditionReferences(
            operation.condition,
            '$stepPath.loop.condition',
            testCase.variables,
            add,
          );
          walk(
            operation.steps,
            '$stepPath.loop.steps',
            depth: depth + 1,
            owner: owner,
          );
        case CockpitTestCallOperationTemplate():
          calls.putIfAbsent(owner, () => <String>{}).add(operation.fragment);
          if (!testCase.fragments.containsKey(operation.fragment)) {
            add(
              'fragmentMissing',
              'Fragment ${operation.fragment} does not exist.',
              '$stepPath.call.fragment',
            );
          }
        case CockpitTestStartRecordingOperationTemplate() ||
            CockpitTestStopRecordingOperationTemplate():
          break;
      }
    }
  }

  walk(testCase.setup, r'$.setup', depth: 1, owner: '<root>');
  walk(testCase.steps, r'$.steps', depth: 1, owner: '<root>');
  walk(testCase.finallySteps, r'$.finally', depth: 1, owner: '<root>');
  for (final entry in testCase.fragments.entries) {
    walk(
      entry.value,
      _childPath(r'$.fragments', entry.key),
      depth: 1,
      owner: entry.key,
    );
  }

  _validateCallGraph(testCase, calls, add);
  final expanded = _expandedStepCount(testCase, '<root>', calls);
  if (expanded > limits.maxExpandedSteps) {
    add(
      'expandedStepLimitExceeded',
      'Expanded case has $expanded steps; limit is ${limits.maxExpandedSteps}.',
      r'$.steps',
    );
  }
  diagnostics.sort((left, right) {
    final leftLocation = left.location;
    final rightLocation = right.location;
    if (leftLocation == null || rightLocation == null) {
      return left.path.compareTo(right.path);
    }
    final line = leftLocation.line.compareTo(rightLocation.line);
    return line != 0
        ? line
        : leftLocation.column.compareTo(rightLocation.column);
  });
  return diagnostics;
}

typedef _AddDiagnostic =
    void Function(String code, String message, String path);

void _validateActionReferences(
  CockpitTestActionTemplate action,
  String path,
  Map<String, CockpitTestVariableDeclaration> variables,
  _AddDiagnostic add,
) {
  for (final entry in action.values.entries) {
    _validateTemplateValue(
      entry.value,
      '$path.${entry.key.wireName}',
      variables,
      add,
      allowSecret: action.spec.secretFields.contains(entry.key),
    );
  }
  if (action.locator != null) {
    _validateLocatorReferences(
      action.locator!,
      '$path.locator',
      variables,
      add,
    );
  }
  if (action.condition != null) {
    _validateConditionReferences(
      action.condition!,
      '$path.condition',
      variables,
      add,
    );
  }
}

void _validateConditionReferences(
  CockpitTestConditionTemplate condition,
  String path,
  Map<String, CockpitTestVariableDeclaration> variables,
  _AddDiagnostic add,
) {
  if (condition.locator != null) {
    _validateLocatorReferences(
      condition.locator!,
      '$path.locator',
      variables,
      add,
    );
  }
  for (final entry in <String, CockpitTestTemplateValue?>{
    'expected': condition.expected,
    'text': condition.text,
    'route': condition.route,
    'quietMs': condition.quietMs,
  }.entries) {
    final value = entry.value;
    if (value != null) {
      _validateTemplateValue(value, '$path.${entry.key}', variables, add);
    }
  }
}

void _validateLocatorReferences(
  CockpitTestLocatorTemplate locator,
  String path,
  Map<String, CockpitTestVariableDeclaration> variables,
  _AddDiagnostic add,
) {
  for (final entry in <String, CockpitTestTemplateValue?>{
    'value': locator.value,
    'x': locator.x,
    'y': locator.y,
    'threshold': locator.threshold,
    'index': locator.index,
  }.entries) {
    final value = entry.value;
    if (value != null) {
      _validateTemplateValue(value, '$path.${entry.key}', variables, add);
    }
  }
  if (locator.ancestor != null) {
    _validateLocatorReferences(
      locator.ancestor!,
      '$path.ancestor',
      variables,
      add,
    );
  }
  for (var index = 0; index < locator.fallbacks.length; index += 1) {
    _validateLocatorReferences(
      locator.fallbacks[index],
      '$path.fallbacks[$index]',
      variables,
      add,
    );
  }
}

void _validateTemplateValue(
  CockpitTestTemplateValue value,
  String path,
  Map<String, CockpitTestVariableDeclaration> variables,
  _AddDiagnostic add, {
  bool allowSecret = false,
}) {
  switch (value.kind) {
    case CockpitTestTemplateValueKind.literal:
      return;
    case CockpitTestTemplateValueKind.variable:
      final name = value.variable!;
      final declaration = variables[name];
      if (declaration == null) {
        add('variableMissing', 'Variable $name is not declared.', path);
        return;
      }
      final assignable =
          declaration.valueType == value.expectedType ||
          declaration.valueType == CockpitTestValueType.integer &&
              value.expectedType == CockpitTestValueType.number;
      if (!assignable) {
        add(
          'variableTypeMismatch',
          'Variable $name has type ${declaration.valueType.name}, but '
              '${value.expectedType.name} is required.',
          path,
        );
      } else if (declaration.source == CockpitTestVariableSource.secret &&
          !allowSecret) {
        add(
          'secretUsageInvalid',
          'Secret variable $name is allowed only in action string fields.',
          path,
        );
      }
    case CockpitTestTemplateValueKind.stringTemplate:
      final template = value.value! as String;
      final pattern = RegExp(r'\$\{([A-Za-z][A-Za-z0-9._-]{0,127})\}');
      final matches = pattern.allMatches(template).toList(growable: false);
      final unmatched = template.replaceAll(pattern, '');
      if (matches.isEmpty || unmatched.contains(r'${')) {
        add('invalidInterpolation', 'Invalid variable interpolation.', path);
        return;
      }
      for (final match in matches) {
        final name = match.group(1)!;
        final declaration = variables[name];
        if (declaration == null) {
          add('variableMissing', 'Variable $name is not declared.', path);
        } else if (declaration.valueType != CockpitTestValueType.string ||
            declaration.source == CockpitTestVariableSource.secret) {
          add(
            'interpolationTypeMismatch',
            'Interpolation requires a non-secret string variable; $name is '
                '${declaration.source.name}/${declaration.valueType.name}.',
            path,
          );
        }
      }
  }
}

void _validateCallGraph(
  CockpitTestCase testCase,
  Map<String, Set<String>> calls,
  _AddDiagnostic add,
) {
  final visiting = <String>{};
  final visited = <String>{};

  void visit(String fragment, List<String> stack) {
    if (visited.contains(fragment)) {
      return;
    }
    if (!visiting.add(fragment)) {
      final cycle = <String>[...stack, fragment].join(' -> ');
      add(
        'fragmentRecursion',
        'Recursive fragment call graph: $cycle.',
        fragment == '<root>'
            ? r'$.steps'
            : _childPath(r'$.fragments', fragment),
      );
      return;
    }
    for (final target in calls[fragment] ?? const <String>{}) {
      if (testCase.fragments.containsKey(target)) {
        visit(target, <String>[...stack, fragment]);
      }
    }
    visiting.remove(fragment);
    visited.add(fragment);
  }

  visit('<root>', const <String>[]);
  for (final fragment in testCase.fragments.keys) {
    visit(fragment, const <String>[]);
  }
}

String? _parentPath(String path) {
  if (path == r'$') {
    return null;
  }
  if (path.endsWith(']')) {
    final bracket = path.lastIndexOf('[');
    return bracket <= 0 ? null : path.substring(0, bracket);
  }
  var bracketDepth = 0;
  var quoted = false;
  var escaped = false;
  for (var index = path.length - 1; index > 0; index -= 1) {
    final character = path[index];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        quoted = false;
      }
      continue;
    }
    if (character == '"' && bracketDepth > 0) {
      quoted = true;
    } else if (character == ']') {
      bracketDepth += 1;
    } else if (character == '[') {
      bracketDepth -= 1;
    } else if (character == '.' && bracketDepth == 0) {
      return path.substring(0, index);
    }
  }
  return r'$';
}

int _expandedStepCount(
  CockpitTestCase testCase,
  String owner,
  Map<String, Set<String>> calls,
) {
  int countSteps(
    List<CockpitTestStepTemplate> steps,
    Set<String> fragmentStack,
  ) {
    var count = 0;
    for (final step in steps) {
      count += 1;
      switch (step.operation) {
        case CockpitTestIfOperationTemplate(:final thenSteps, :final elseSteps):
          count += countSteps(thenSteps, fragmentStack);
          count += countSteps(elseSteps, fragmentStack);
        case CockpitTestRetryOperationTemplate(:final steps) ||
            CockpitTestLoopOperationTemplate(:final steps):
          count += countSteps(steps, fragmentStack);
        case CockpitTestCallOperationTemplate(:final fragment):
          final fragmentSteps = testCase.fragments[fragment];
          if (fragmentSteps != null && !fragmentStack.contains(fragment)) {
            count += countSteps(fragmentSteps, <String>{
              ...fragmentStack,
              fragment,
            });
          }
        case CockpitTestActionOperationTemplate() ||
            CockpitTestStartRecordingOperationTemplate() ||
            CockpitTestStopRecordingOperationTemplate():
          break;
      }
    }
    return count;
  }

  return countSteps(testCase.setup, const <String>{}) +
      countSteps(testCase.steps, const <String>{}) +
      countSteps(testCase.finallySteps, const <String>{});
}
