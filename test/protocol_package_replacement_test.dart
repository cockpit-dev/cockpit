import 'dart:io';

import 'package:test/test.dart';

void main() {
  const oldPackage =
      'flutter_cockpit'
      '_protocol';

  test('active Dart sources use only cockpit_protocol imports', () {
    const oldImportPrefix = 'package:$oldPackage/';

    expect(Directory('packages/cockpit_protocol').existsSync(), isTrue);
    expect(Directory('packages/$oldPackage').existsSync(), isFalse);

    final staleImports = <String>[];
    for (final root in const <String>['packages', 'examples', 'test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final separator = Platform.pathSeparator;
        if (entity.path.contains('$separator.dart_tool$separator') ||
            entity.path.contains('${separator}build$separator')) {
          continue;
        }
        if (entity.readAsStringSync().contains(oldImportPrefix)) {
          staleImports.add(entity.path);
        }
      }
    }

    expect(
      staleImports,
      isEmpty,
      reason: 'stale protocol package imports: $staleImports',
    );
  });

  test('active workspace configuration uses only cockpit_protocol', () {
    const paths = <String>[
      'pubspec.yaml',
      'melos.yaml',
      'packages/cockpit_protocol/pubspec.yaml',
      'packages/flutter_cockpit/pubspec.yaml',
      'packages/cockpit/pubspec.yaml',
      'examples/cockpit_demo/cockpit/pubspec.yaml',
      '.github/workflows/example-e2e.yml',
    ];
    final oldDependency = RegExp('^\\s*$oldPackage:', multiLine: true);
    final staleConfiguration = <String>[];

    for (final path in paths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'missing active file: $path');
      if (!file.existsSync()) {
        continue;
      }
      final content = file.readAsStringSync();
      if (content.contains('packages/$oldPackage') ||
          oldDependency.hasMatch(content)) {
        staleConfiguration.add(path);
      }
    }

    expect(
      staleConfiguration,
      isEmpty,
      reason: 'stale protocol package configuration: $staleConfiguration',
    );
  });
}
