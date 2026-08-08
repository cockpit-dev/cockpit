import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/src/cockpit_demo_acceptance_runner.dart';

void main() {
  test('Web acceptance uses the supported development launch mode', () {
    expect(cockpitDemoLaunchModeForPlatform('web'), 'development');
    expect(cockpitDemoLaunchModeForPlatform('linux'), 'automation');
    expect(cockpitDemoLaunchModeForPlatform('android'), 'automation');
  });

  test('Acceptance CLI allows three minutes for target discovery', () async {
    final root = _cockpitRoot();
    final result = await Process.run('dart', const <String>[
      'run',
      'tool/verify.dart',
      '--help',
    ], workingDirectory: root);

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains('--discovery-timeout-seconds    (defaults to "180")'),
    );
    expect(result.stdout, contains('--require-recording'));
    expect(result.stdout, contains('--require-native-locator'));
    expect(result.stdout, contains('--wda-url'));
  });

  test(
    'release acceptance compiles the complete Flutter command surface',
    () async {
      final root = _cockpitRoot();
      final suiteFile = File(
        p.join(root, 'e2e', 'suites', 'regression.suite.yaml'),
      );
      final compiler = const CockpitTestDocumentCompiler();
      final compiledSuite = compiler
          .compile(await suiteFile.readAsString())
          .requireSuite();
      final suite = compiledSuite.suite;

      expect(suite.fixtures, hasLength(2));
      expect(suite.matrix.axes['variant'], <Object?>['primary', 'alternate']);
      expect(
        suite.cases.map((entry) => entry.id),
        containsAll(const <String>{
          'taskEditorValidation',
          'settingsNavigation',
          'visualRegression',
          'commandGestureCoverage',
          'commandSemanticCoverage',
          'mixedPlaneBlackBox',
          'locationTravel',
          'matrixEvidence',
          'nativeBlackBox',
          'recordingLifecycle',
        }),
      );

      final referencedSources = <CockpitTestSuiteFileCaseSource>[
        for (final entry in suite.cases)
          if (entry.source case final CockpitTestSuiteFileCaseSource source)
            source,
        for (final fixture
            in suite.fixtures) ...<CockpitTestSuiteFileCaseSource>[
          if (fixture.setup case final CockpitTestSuiteFileCaseSource source)
            source,
          if (fixture.teardown case final CockpitTestSuiteFileCaseSource source)
            source,
        ],
      ];
      for (final source in referencedSources) {
        final file = File(p.normalize(p.join(root, source.relativePath)));
        expect(p.isWithin(root, file.path), isTrue);
        final compiled = compiler
            .compile(await file.readAsString())
            .requireCase();
        expect(compiled.testCase.id, source.caseId);
      }

      final actionTypes = <String>{};
      await for (final entity in Directory(
        p.join(root, 'e2e'),
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File ||
            !const <String>{
              '.yaml',
              '.yml',
            }.contains(p.extension(entity.path))) {
          continue;
        }
        final compiled = compiler.compile(await entity.readAsString());
        expect(
          compiled.isSuccess,
          isTrue,
          reason:
              '${p.relative(entity.path, from: root)}: '
              '${compiled.diagnostics.map((item) => item.message).join('; ')}',
        );
        _collectActionTypes(
          compiled.requireCompiled().document.toJson(),
          actionTypes,
        );
      }
      expect(
        actionTypes,
        containsAll(CockpitTestActionKind.values.map((action) => action.name)),
      );
    },
  );
}

String _cockpitRoot() {
  final current = Directory.current.absolute.path;
  final nested = p.join(current, 'cockpit');
  return File(p.join(nested, 'tool', 'verify.dart')).existsSync()
      ? nested
      : current;
}

void _collectActionTypes(Object? value, Set<String> actionTypes) {
  if (value is Map<Object?, Object?>) {
    final action = value['action'];
    if (action is Map<Object?, Object?> && action['type'] is String) {
      actionTypes.add(action['type']! as String);
    }
    for (final child in value.values) {
      _collectActionTypes(child, actionTypes);
    }
  } else if (value is List<Object?>) {
    for (final child in value) {
      _collectActionTypes(child, actionTypes);
    }
  }
}
