import 'dart:convert';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/test/cockpit_test_variable_binder.dart';
import 'package:test/test.dart';

void main() {
  const compiler = CockpitTestDocumentCompiler();

  test('YAML and canonical JSON compile to equivalent cases', () {
    final yaml = compiler.compile(_caseSource());
    expect(yaml.isSuccess, isTrue, reason: _diagnostics(yaml));

    final canonical = jsonEncode(yaml.requireCase().testCase.toJson());
    final json = compiler.compile(canonical);
    expect(json.isSuccess, isTrue, reason: _diagnostics(json));
    expect(
      json.requireCase().testCase.toJson(),
      yaml.requireCase().testCase.toJson(),
    );
    expect(
      yaml.requireCase().locationFor(r'$.steps[0].action.type'),
      isNotNull,
    );
  });

  test('dotted fragment ids retain exact source provenance', () {
    final result = compiler.compile(_caseSource(includeDottedFragment: true));
    expect(result.isSuccess, isTrue, reason: _diagnostics(result));

    final plan = CockpitTestVariableBinder().bind(result.requireCase());
    expect(plan.steps, hasLength(2));
    expect(plan.steps.map((node) => node.executionId), <String>[
      'main/firstCall@auth.login/fragmentTap',
      'main/secondCall@auth.login/fragmentTap',
    ]);
    for (final node in plan.steps) {
      expect(node.sourcePath, r'$.fragments["auth.login"][0]');
      expect(node.sourceLocation, isNotNull);
      expect(node.callPath, isNotEmpty);
    }
  });

  test('semantic diagnostics aggregate in deterministic source order', () {
    final result = compiler.compile('''
schemaVersion: cockpit.test/v2
kind: case
id: invalidCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
variables:
  password: {source: secret, type: string, reference: env:PASSWORD}
steps:
  - stepId: duplicate
    action:
      type: tap
      locator: {testId: {\$var: password}}
  - stepId: duplicate
    call: {fragment: absent}
''');

    expect(result.isSuccess, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll(<String>[
        'secretUsageInvalid',
        'duplicateStepId',
        'fragmentMissing',
      ]),
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.location?.line),
      orderedEquals(
        result.diagnostics
            .map((diagnostic) => diagnostic.location?.line)
            .toList()
          ..sort((left, right) => (left ?? 0).compareTo(right ?? 0)),
      ),
    );
  });

  test('missing and recursive fragments are rejected', () {
    final recursive = compiler.compile('''
schemaVersion: cockpit.test/v2
kind: case
id: recursiveCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
fragments:
  first:
    - {stepId: callSecond, call: {fragment: second}}
  second:
    - {stepId: callFirst, call: {fragment: first}}
steps:
  - {stepId: enterCycle, call: {fragment: first}}
''');

    expect(recursive.isSuccess, isFalse);
    expect(
      recursive.diagnostics.map((diagnostic) => diagnostic.code),
      contains('fragmentRecursion'),
    );
  });

  test('expanded step bounds and legacy envelopes fail before execution', () {
    final bounded = compiler.compile(
      _caseSource(includeDottedFragment: true, maxExpandedSteps: 3),
    );
    expect(
      bounded.diagnostics.map((diagnostic) => diagnostic.code),
      contains('expandedStepLimitExceeded'),
    );

    final legacy = compiler.compile('''
schemaVersion: 1
sessionId: old
taskId: old-task
platform: android
commands: []
failFast: true
    ''');
    expect(legacy.isSuccess, isFalse);
    expect(
      legacy.diagnostics.map((diagnostic) => diagnostic.code),
      everyElement('validationFailed'),
    );
  });

  test('enforces the authored document byte bound', () {
    final result = compiler.compile('''
schemaVersion: cockpit.test/v2
kind: case
id: boundedCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
defaults:
  limits: {maxDocumentBytes: 128}
steps:
  - {stepId: goBack, action: {type: back}}
''');

    expect(result.isSuccess, isFalse);
    expect(result.diagnostics.single.code, 'documentTooLarge');
  });

  test(
    'accepts documents above the standard bound when explicitly allowed',
    () {
      final source = jsonEncode(<String, Object?>{
        'schemaVersion': 'cockpit.test/v2',
        'kind': 'case',
        'id': 'largeCase',
        'target': <String, Object?>{
          'platform': 'android',
          'targetKind': 'flutterApp',
          'plane': 'semantic',
        },
        'defaults': <String, Object?>{
          'limits': <String, Object?>{'maxDocumentBytes': 2000000},
        },
        'steps': <Object?>[
          <String, Object?>{
            'stepId': 'goBack',
            'action': <String, Object?>{'type': 'back'},
          },
        ],
        'x-padding': List<String>.filled(1050000, 'a').join(),
      });

      expect(utf8.encode(source).length, greaterThan(1048576));
      final result = compiler.compile(source);
      expect(result.isSuccess, isTrue, reason: _diagnostics(result));
    },
  );

  test('structural diagnostics retain the exact source path and location', () {
    final result = compiler.compile('''
schemaVersion: cockpit.test/v2
kind: case
id: locatedCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
defaults:
  evidence:
    unknownEvidenceField: true
steps:
  - {stepId: goBack, action: {type: back}}
''');

    expect(result.isSuccess, isFalse);
    expect(
      result.diagnostics.single.path,
      r'$.defaults.evidence.unknownEvidenceField',
    );
    expect(result.diagnostics.single.location?.line, 7);
  });

  test('independent structural diagnostics are aggregated in source order', () {
    final result = compiler.compile('''
schemaVersion: cockpit.test/v2
kind: case
id: aggregateCase
target:
  platform: android
  targetKind: flutterApp
  plane: unsupportedPlane
defaults:
  cleanupTimeoutMs: 0
steps:
  - stepId: invalidAction
    action: {type: unknownAction}
''');

    expect(result.isSuccess, isFalse);
    expect(result.diagnostics, hasLength(greaterThanOrEqualTo(3)));
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.path),
      containsAll(<String>[
        r'$.target.plane',
        r'$.defaults.cleanupTimeoutMs',
        r'$.steps[0].action.type',
      ]),
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.location?.line),
      orderedEquals(
        result.diagnostics
            .map((diagnostic) => diagnostic.location?.line)
            .toList()
          ..sort((left, right) => (left ?? 0).compareTo(right ?? 0)),
      ),
    );
  });
}

String _caseSource({
  bool includeDottedFragment = false,
  int? maxExpandedSteps,
}) =>
    '''
schemaVersion: cockpit.test/v2
kind: case
id: compilerCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
${maxExpandedSteps == null ? '' : 'defaults:\n  limits: {maxExpandedSteps: $maxExpandedSteps}\n'}${includeDottedFragment ? '''fragments:
  auth.login:
    - stepId: fragmentTap
      action:
        type: tap
        locator: {testId: loginButton}
steps:
  - {stepId: firstCall, call: {fragment: auth.login}}
  - {stepId: secondCall, call: {fragment: auth.login}}
''' : '''steps:
  - stepId: tapContinue
    action:
      type: tap
      locator: {testId: continueButton}
'''}''';

String _diagnostics(CockpitTestCompilationResult result) => result.diagnostics
    .map((diagnostic) => '${diagnostic.code}: ${diagnostic.message}')
    .join('\n');
