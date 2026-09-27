import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

/// Project roots whose shipped `cockpit.test/v2` documents must always
/// compile against the current schema, including the Cockpit Console smoke
/// suite that release validation replays.
const List<String> _documentProjectRoots = <String>[
  'examples/cockpit_demo/cockpit',
  'packages/cockpit_console',
];

void main() {
  final repositoryRoot = Directory.current;
  const compiler = CockpitTestDocumentCompiler();

  test('every shipped e2e document compiles against the current schema', () {
    final documents = _shippedDocuments(repositoryRoot);
    expect(documents, isNotEmpty);

    for (final document in documents) {
      final result = compiler.compile(document.readAsStringSync());
      expect(
        result.isSuccess,
        isTrue,
        reason:
            '$document must compile: '
            '${result.diagnostics.map((d) => '${d.path}: ${d.message}').join('; ')}',
      );
      final compiled = result.compiled!;
      if (document.path.endsWith('.case.yaml')) {
        expect(
          compiled,
          isA<CockpitCompiledTestCase>(),
          reason: '$document must compile as a case document.',
        );
      } else if (document.path.endsWith('.suite.yaml')) {
        expect(
          compiled,
          isA<CockpitCompiledTestSuite>(),
          reason: '$document must compile as a suite document.',
        );
      }
    }
  });

  test('suite case and fixture references resolve to shipped documents', () {
    var referencedDocuments = 0;
    for (final root in _documentProjectRoots) {
      final projectRoot = Directory.fromUri(repositoryRoot.uri.resolve(root));
      for (final document in _shippedDocuments(projectRoot)) {
        if (!document.path.endsWith('.suite.yaml')) {
          continue;
        }
        final suite =
            compiler
                    .compile(document.readAsStringSync())
                    .requireCompiled()
                    .document
                as CockpitTestSuite;

        final references = <String, CockpitTestSuiteFileCaseSource>{};
        for (final entry in suite.cases) {
          if (entry.source case final CockpitTestSuiteFileCaseSource file) {
            references[entry.id] = file;
          }
        }
        for (final fixture in suite.fixtures) {
          if (fixture.setup case final CockpitTestSuiteFileCaseSource setup) {
            references[fixture.id] = setup;
          }
          if (fixture.teardown
              case final CockpitTestSuiteFileCaseSource teardown) {
            references['${fixture.id}-teardown'] = teardown;
          }
        }
        expect(
          references,
          isNotEmpty,
          reason: '$document declares no file-backed cases or fixtures.',
        );

        for (final MapEntry(key: entryId, value: reference)
            in references.entries) {
          final referenced = File.fromUri(
            projectRoot.uri.resolve(reference.relativePath),
          );
          expect(
            referenced.existsSync(),
            isTrue,
            reason:
                '$document references missing document '
                '${reference.relativePath} (entry $entryId).',
          );
          final result = compiler.compile(referenced.readAsStringSync());
          expect(
            result.isSuccess,
            isTrue,
            reason:
                '${reference.relativePath} referenced by $document must compile.',
          );
          final testCase = result.requireCase().testCase;
          expect(
            testCase.id,
            reference.caseId,
            reason:
                '${reference.relativePath} declares id ${testCase.id} but '
                '$document expects ${reference.caseId}.',
          );
          referencedDocuments += 1;
        }
      }
    }
    expect(referencedDocuments, greaterThan(0));
  });

  test('the Console smoke suite keeps both smoke cases', () {
    final suiteFile = File.fromUri(
      repositoryRoot.uri.resolve(
        'packages/cockpit_console/cockpit/e2e/suites/console_regression.suite.yaml',
      ),
    );
    final suite =
        compiler
                .compile(suiteFile.readAsStringSync())
                .requireCompiled()
                .document
            as CockpitTestSuite;

    expect(
      suite.cases.map((entry) => entry.id).toSet(),
      containsAll(<String>['flutterSmoke', 'nativeSmoke']),
    );
  });
}

List<File> _shippedDocuments(Directory root) {
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.uri.pathSegments.contains('e2e') &&
            (file.path.endsWith('.case.yaml') ||
                file.path.endsWith('.suite.yaml')),
      )
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}
