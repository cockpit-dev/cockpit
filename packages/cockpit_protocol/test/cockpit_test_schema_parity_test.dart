import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('embedded schema is byte-identical to the published schema', () {
    expect(
      File(
        p.join(_packageRoot().path, 'schema', 'cockpit.test.v2.schema.json'),
      ).readAsStringSync(),
      cockpitTestV2SchemaJson,
    );
  });

  final packageRoot = _packageRoot();
  final schemaPath = p.join(
    packageRoot.path,
    'schema',
    'cockpit.test.v2.schema.json',
  );
  final schemaJson =
      jsonDecode(File(schemaPath).readAsStringSync()) as Map<String, Object?>;
  final schema = JsonSchema.create(schemaJson);

  test('published schema is valid JSON Schema 2020-12 with a stable id', () {
    expect(
      schemaJson[r'$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );
    expect(
      schemaJson[r'$id'],
      'https://github.com/cockpit-dev/cockpit/packages/cockpit_protocol/schema/cockpit.test.v2.schema.json',
    );
    expect(schema.schemaVersion, SchemaVersion.draft2020_12);
    expect(
      p.relative(schemaPath, from: packageRoot.path),
      p.join('schema', 'cockpit.test.v2.schema.json'),
    );
  });

  test('Dart model and JSON Schema agree on the shared fixture corpus', () {
    final fixtureRoot = Directory(
      p.join(packageRoot.path, 'test', 'fixtures', 'cockpit_test_v2'),
    );
    final validFiles = _jsonFiles(Directory(p.join(fixtureRoot.path, 'valid')));
    final invalidFiles = _jsonFiles(
      Directory(p.join(fixtureRoot.path, 'invalid')),
    );
    expect(validFiles, isNotEmpty);
    expect(invalidFiles, isNotEmpty);

    for (final entry in <(File, bool)>[
      ...validFiles.map((file) => (file, true)),
      ...invalidFiles.map((file) => (file, false)),
    ]) {
      final file = entry.$1;
      final expected = entry.$2;
      final document = jsonDecode(file.readAsStringSync());
      final schemaResult = schema.validate(document);
      CockpitTestCase? model;
      Object? modelError;
      try {
        model = CockpitTestCase.fromJson(document);
      } on Object catch (error) {
        modelError = error;
      }
      final modelAccepted = model != null;
      expect(
        schemaResult.isValid,
        expected,
        reason: '${file.path}: ${schemaResult.errors}',
      );
      expect(modelAccepted, expected, reason: '${file.path}: $modelError');
      expect(modelAccepted, schemaResult.isValid, reason: file.path);
      if (model != null) {
        final canonical = model.toJson();
        expect(schema.validate(canonical).isValid, isTrue, reason: file.path);
        expect(
          CockpitTestCase.fromJson(canonical).toJson(),
          canonical,
          reason: file.path,
        );
      }
    }
  });
}

Directory _packageRoot() {
  final current = Directory.current;
  final directSchema = File(
    p.join(current.path, 'schema', 'cockpit.test.v2.schema.json'),
  );
  if (directSchema.existsSync()) {
    return current;
  }
  final workspacePackage = Directory(
    p.join(current.path, 'packages', 'cockpit_protocol'),
  );
  if (File(
    p.join(workspacePackage.path, 'schema', 'cockpit.test.v2.schema.json'),
  ).existsSync()) {
    return workspacePackage;
  }
  throw StateError('Cannot locate the cockpit_protocol package root.');
}

List<File> _jsonFiles(Directory directory) {
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  return files;
}
