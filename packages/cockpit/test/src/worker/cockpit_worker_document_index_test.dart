import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/worker/cockpit_worker_document_index.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('rejects replaced and stale document capabilities', () async {
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    final source = await File(
      p.join(fixture.workspace.path, 'main.dart'),
    ).writeAsString('void main() {}\n');
    final index = fixture.index();
    final summaries = await index.refresh();
    final documentId = summaries.single['documentId']! as String;

    final replaced = File('${source.path}.replaced');
    await source.rename(replaced.path);
    await File(source.path).writeAsString('void main() => print(1);\n');
    await expectLater(
      fixture.index().resolveDocuments(<String>[documentId]),
      throwsA(isA<FormatException>()),
    );

    await File(source.path).delete();
    await replaced.rename(source.path);
    await source.writeAsString('void main() => print(2);\n');
    await expectLater(
      fixture.index().resolveDocuments(<String>[documentId]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects file and parent symlink substitutions', () async {
    if (Platform.isWindows) return;
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    final direct = await File(
      p.join(fixture.workspace.path, 'direct.dart'),
    ).writeAsString('const direct = true;\n');
    final nested = await File(
      p.join(fixture.workspace.path, 'nested', 'main.dart'),
    ).create(recursive: true);
    await nested.writeAsString('void main() {}\n');
    final outside = await Directory(
      p.join(fixture.directory.path, 'outside'),
    ).create();
    final outsideDirect = await File(
      p.join(outside.path, 'direct.dart'),
    ).writeAsString('const outside = true;\n');
    final outsideNested = await Directory(
      p.join(outside.path, 'nested'),
    ).create();
    await File(
      p.join(outsideNested.path, 'main.dart'),
    ).writeAsString('void main() => print("outside");\n');

    final index = fixture.index();
    final summaries = await index.refresh();
    final idsByPath = <String, String>{};
    for (final summary in summaries) {
      final id = summary['documentId']! as String;
      final resolved = (await index.resolveDocuments(<String>[id])).single;
      idsByPath[p.relative(
            resolved.absolutePath,
            from: fixture.workspace.path,
          )] =
          id;
    }

    await direct.delete();
    await Link(direct.path).create(outsideDirect.path);
    await expectLater(
      fixture.index().resolveDocuments(<String>[idsByPath['direct.dart']!]),
      throwsA(isA<FormatException>()),
    );
    await Link(direct.path).delete();
    await File(direct.path).writeAsString('const direct = true;\n');

    final nestedDirectory = Directory(p.dirname(nested.path));
    await nestedDirectory.rename('${nestedDirectory.path}.replaced');
    await Link(nestedDirectory.path).create(outsideNested.path);
    await expectLater(
      fixture.index().resolveDocuments(<String>[
        idsByPath[p.join('nested', 'main.dart')]!,
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'restart resolves persisted capabilities without discovering or writing',
    () async {
      final fixture = await _DocumentFixture.create();
      addTearDown(fixture.dispose);
      await File(
        p.join(fixture.workspace.path, 'main.dart'),
      ).writeAsString('void main() {}\n');
      await File(p.join(fixture.workspace.path, 'case.yaml')).writeAsString('''
schemaVersion: cockpit.test/v2
kind: case
id: restartCase
target: {platform: flutter, targetKind: flutterApp, plane: semantic}
steps:
  - stepId: goBack
    action: {type: back}
''');
      final indexed = await fixture.index().refresh();
      final source = indexed.singleWhere(
        (document) => document['kind'] == 'source',
      );
      final testCase = indexed.singleWhere(
        (document) => document['kind'] == 'case',
      );
      final indexFile = File(
        p.join(fixture.state.path, 'documents', 'index.json'),
      );
      final beforeBytes = await indexFile.readAsBytes();
      final beforeModified = (await indexFile.stat()).modified;
      await File(
        p.join(fixture.workspace.path, 'new.dart'),
      ).writeAsString('const newlyDiscovered = true;\n');

      final reopened = fixture.index();
      final resolved = await reopened.resolveDocuments(<String>[
        source['documentId']! as String,
      ]);
      expect(resolved.single.sourceSha256, source['sourceSha256']);
      final compiled = await reopened.resolve(
        CockpitIndexedCaseReference(
          documentId: testCase['documentId']! as String,
          caseId: testCase['authoredId']! as String,
          documentSha256: testCase['sourceSha256']! as String,
        ),
      );
      expect(compiled.testCase.id, 'restartCase');
      expect(await indexFile.readAsBytes(), beforeBytes);
      expect((await indexFile.stat()).modified, beforeModified);

      final refreshed = await reopened.refresh();
      expect(refreshed, hasLength(3));
      expect(await indexFile.readAsBytes(), isNot(beforeBytes));
    },
  );

  test(
    'recovers exact atomic temps and rejects unknown storage entries',
    () async {
      final fixture = await _DocumentFixture.create();
      addTearDown(fixture.dispose);
      await File(
        p.join(fixture.workspace.path, 'main.dart'),
      ).writeAsString('void main() {}\n');
      final summary = (await fixture.index().refresh()).single;
      final storage = Directory(p.join(fixture.state.path, 'documents'));
      final exact = await File(
        p.join(
          storage.path,
          '.index.json.$pid.${List<String>.filled(24, 'a').join()}.tmp',
        ),
      ).writeAsString('{}');

      await fixture.index().resolveDocuments(<String>[
        summary['documentId']! as String,
      ]);
      expect(await exact.exists(), isFalse);

      final unknown = await File(
        p.join(storage.path, '.index.json.invalid.tmp'),
      ).writeAsString('{}');
      await expectLater(
        fixture.index().resolveDocuments(<String>[
          summary['documentId']! as String,
        ]),
        throwsA(isA<FileSystemException>()),
      );
      await unknown.delete();

      if (!Platform.isWindows) {
        final index = File(p.join(storage.path, 'index.json'));
        final outside = await File(
          p.join(fixture.directory.path, 'outside-index.json'),
        ).writeAsBytes(await index.readAsBytes());
        await index.delete();
        await Link(index.path).create(outside.path);
        await expectLater(
          fixture.index().resolveDocuments(<String>[
            summary['documentId']! as String,
          ]),
          throwsA(isA<FileSystemException>()),
        );
      }
    },
  );

  test('treats an unpublished first-write temp as empty state', () async {
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    final storage = await Directory(
      p.join(fixture.state.path, 'documents'),
    ).create();
    final temporary = await File(
      p.join(
        storage.path,
        '.index.json.$pid.${List<String>.filled(24, 'b').join()}.tmp',
      ),
    ).writeAsString('{"partial":true}');

    await expectLater(
      fixture.index().resolveDocuments(const <String>['document_missing']),
      throwsA(isA<FormatException>()),
    );
    expect(await temporary.exists(), isFalse);
    expect(await File(p.join(storage.path, 'index.json')).exists(), isFalse);
  });

  test('bounds index reads before decoding', () async {
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    await File(
      p.join(fixture.workspace.path, 'main.dart'),
    ).writeAsString('void main() {}\n');
    final summary = (await fixture.index().refresh()).single;
    final index = File(p.join(fixture.state.path, 'documents', 'index.json'));
    await index.writeAsBytes(
      List<int>.filled(CockpitWorkerDocumentIndex.maximumIndexBytes + 1, 32),
    );

    await expectLater(
      fixture.index().resolveDocuments(<String>[
        summary['documentId']! as String,
      ]),
      throwsA(isA<CockpitStorageException>()),
    );
  });

  test('does not index generated or dependency directories', () async {
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    await File(
      p.join(fixture.workspace.path, 'lib', 'app.dart'),
    ).create(recursive: true);
    await File(
      p.join(fixture.workspace.path, 'lib', 'app.dart'),
    ).writeAsString('void main() {}\n');
    for (final directory in <String>[
      '.dart_tool',
      'build',
      'ios/Pods',
      'node_modules',
    ]) {
      final generated = await File(
        p.join(fixture.workspace.path, directory, 'generated.json'),
      ).create(recursive: true);
      await generated.writeAsString('{"generated":true}\n');
    }

    final summaries = await fixture.index().refresh();

    expect(summaries, hasLength(1));
    expect(summaries.single['relativePath'], 'lib/app.dart');
  });

  test('restores the in-memory index when atomic publication fails', () async {
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    final hardener = _FailingPermissionHardener();
    final source = await File(
      p.join(fixture.workspace.path, 'main.dart'),
    ).writeAsString('void main() {}\n');
    final index = fixture.index(permissionHardener: hardener);
    final summary = (await index.refresh()).single;
    final indexFile = File(
      p.join(fixture.state.path, 'documents', 'index.json'),
    );
    final durableBytes = await indexFile.readAsBytes();
    await File(
      p.join(fixture.workspace.path, 'second.dart'),
    ).writeAsString('const second = true;\n');
    hardener.failNextFile = true;

    await expectLater(index.refresh(), throwsA(isA<FileSystemException>()));

    expect(await indexFile.readAsBytes(), durableBytes);
    final resolved = await index.resolveDocuments(<String>[
      summary['documentId']! as String,
    ]);
    expect(resolved.single.absolutePath, source.path);
  });

  test('rejects a storage-directory symlink before hardening it', () async {
    if (Platform.isWindows) return;
    final fixture = await _DocumentFixture.create();
    addTearDown(fixture.dispose);
    final outside = await Directory(
      p.join(fixture.directory.path, 'outside-documents'),
    ).create();
    final storagePath = p.join(fixture.state.path, 'documents');
    await Link(storagePath).create(outside.path);
    final hardener = _RecordingPermissionHardener();

    await expectLater(
      fixture.index(permissionHardener: hardener).resolveDocuments(
        const <String>['document_missing'],
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(hardener.resolvedDirectories, isEmpty);
  });
}

final class _DocumentFixture {
  const _DocumentFixture(this.directory, this.workspace, this.state);

  final Directory directory;
  final Directory workspace;
  final Directory state;

  static Future<_DocumentFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-worker-document-index-',
    );
    final workspace = await Directory(
      p.join(directory.path, 'workspace'),
    ).create();
    final state = await Directory(p.join(directory.path, 'state')).create();
    return _DocumentFixture(
      directory,
      Directory(await workspace.resolveSymbolicLinks()),
      Directory(await state.resolveSymbolicLinks()),
    );
  }

  CockpitWorkerDocumentIndex index({
    CockpitPermissionHardener permissionHardener =
        const _NoopPermissionHardener(),
  }) => CockpitWorkerDocumentIndex(
    workspaceRoot: workspace.path,
    stateRoot: state.path,
    permissionHardener: permissionHardener,
    directorySyncer: const _NoopDirectorySyncer(),
  );

  Future<void> dispose() => directory.delete(recursive: true);
}

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class _FailingPermissionHardener implements CockpitPermissionHardener {
  var failNextFile = false;

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {
    if (failNextFile) {
      failNextFile = false;
      throw FileSystemException(
        'injected index publication failure',
        file.path,
      );
    }
  }
}

final class _RecordingPermissionHardener implements CockpitPermissionHardener {
  final List<String> resolvedDirectories = <String>[];

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {
    resolvedDirectories.add(await directory.resolveSymbolicLinks());
  }

  @override
  Future<void> hardenFile(File file) async {}
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
