import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/worker/cockpit_worker_operation_journal.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'replays a completed mutation and rejects fingerprint conflicts',
    () async {
      final fixture = await _JournalFixture.create();
      addTearDown(fixture.dispose);
      final invocation = _invocation('mutation-A');
      final submittedAt = DateTime.utc(2026, 7, 22);
      final journal = fixture.open();
      final admission = await journal.admit(
        invocation: invocation,
        submittedAt: submittedAt,
      );
      await journal.markRunning(
        idempotencyKey: 'mutation-A',
        startedAt: submittedAt.add(const Duration(seconds: 1)),
      );
      final result = _success(admission.operationId, submittedAt: submittedAt);
      await journal.complete(idempotencyKey: 'mutation-A', result: result);

      final reopened = fixture.open();
      await reopened.recover(now: submittedAt.add(const Duration(seconds: 3)));
      final replay = await reopened.admit(
        invocation: invocation,
        submittedAt: submittedAt.add(const Duration(seconds: 4)),
      );
      expect(replay.execute, isFalse);
      expect(replay.operationId, admission.operationId);
      expect(replay.replay?.toJson(), result.toJson());
      await expectLater(
        reopened.admit(
          invocation: _invocation(
            'mutation-A',
            input: const <String, Object?>{'value': 'different'},
          ),
          submittedAt: submittedAt.add(const Duration(seconds: 5)),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('fingerprints required feature sets independent of order', () async {
    final journal = CockpitInMemoryWorkerOperationJournal();
    final submittedAt = DateTime.utc(2026, 7, 22, 0, 30);
    final first = await journal.admit(
      invocation: _invocation(
        'feature-order',
        input: const <String, Object?>{
          'requiredFeatures': <String>['inputB', 'inputA'],
        },
        requiredFeatures: const <String>['envelopeB', 'envelopeA'],
      ),
      submittedAt: submittedAt,
    );

    final replay = await journal.admit(
      invocation: _invocation(
        'feature-order',
        input: const <String, Object?>{
          'requiredFeatures': <String>['inputA', 'inputB'],
        },
        requiredFeatures: const <String>['envelopeA', 'envelopeB'],
      ),
      submittedAt: submittedAt.add(const Duration(seconds: 1)),
    );

    expect(replay.operationId, first.operationId);
    expect(replay.execute, isTrue);
  });

  test('resumes a prepared mutation with its original operation id', () async {
    final fixture = await _JournalFixture.create();
    addTearDown(fixture.dispose);
    final invocation = _invocation('mutation-prepared');
    final preparedAt = DateTime.utc(2026, 7, 22, 1);
    final first = await fixture.open().admit(
      invocation: invocation,
      submittedAt: preparedAt,
    );

    final reopened = fixture.open();
    await reopened.recover(now: preparedAt.add(const Duration(seconds: 1)));
    final resumed = await reopened.admit(
      invocation: invocation,
      submittedAt: preparedAt.add(const Duration(seconds: 2)),
    );
    expect(resumed.execute, isTrue);
    expect(resumed.replay, isNull);
    expect(resumed.operationId, first.operationId);
  });

  test(
    'recovers a running mutation as interrupted without redispatch',
    () async {
      final fixture = await _JournalFixture.create();
      addTearDown(fixture.dispose);
      final invocation = _invocation('mutation-running');
      final submittedAt = DateTime.utc(2026, 7, 22, 2);
      final journal = fixture.open();
      final first = await journal.admit(
        invocation: invocation,
        submittedAt: submittedAt,
      );
      await journal.markRunning(
        idempotencyKey: 'mutation-running',
        startedAt: submittedAt.add(const Duration(seconds: 1)),
      );

      final reopened = fixture.open();
      await reopened.recover(now: submittedAt.add(const Duration(seconds: 2)));
      final recovered = await reopened.admit(
        invocation: invocation,
        submittedAt: submittedAt.add(const Duration(seconds: 3)),
      );
      expect(recovered.execute, isFalse);
      expect(recovered.operationId, first.operationId);
      expect(recovered.replay?.outcome, CockpitOperationOutcome.failed);
      expect(recovered.replay?.failure?.primary.code, 'operationInterrupted');
      expect(
        recovered.replay?.failure?.primary.category,
        CockpitErrorCategory.interrupted,
      );
    },
  );

  test(
    'shards completed results beyond the former global capacity',
    () async {
      final fixture = await _JournalFixture.create();
      addTearDown(fixture.dispose);
      final journal = fixture.open();
      final submittedAt = DateTime.utc(2026, 7, 22, 3);
      final payload = List<String>.filled(900 * 1024, 'x').join();
      for (var index = 0; index < 40; index += 1) {
        final key = 'capacity-$index';
        final invocation = _invocation(key);
        final admission = await journal.admit(
          invocation: invocation,
          submittedAt: submittedAt,
        );
        await journal.markRunning(idempotencyKey: key, startedAt: submittedAt);
        await journal.complete(
          idempotencyKey: key,
          result: _success(
            admission.operationId,
            submittedAt: submittedAt,
            output: <String, Object?>{'payload': payload},
          ),
        );
      }

      final records = await Directory(fixture.path)
          .list(recursive: true, followLinks: false)
          .where(
            (entity) =>
                entity is File && p.basename(entity.path) == 'record.json',
          )
          .cast<File>()
          .toList();
      expect(records, hasLength(40));
      final totalBytes = (await Future.wait(
        records.map((file) => file.length()),
      )).fold<int>(0, (total, length) => total + length);
      expect(totalBytes, greaterThan(32 * 1024 * 1024));

      final replay = await fixture.open().admit(
        invocation: _invocation('capacity-39'),
        submittedAt: submittedAt.add(const Duration(seconds: 1)),
      );
      expect(replay.execute, isFalse);
      expect(replay.replay?.output?['payload'], payload);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('case.run recovery retries with the original operation id', () async {
    final fixture = await _JournalFixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime.utc(2026, 7, 22, 4);
    final first = fixture.open(
      recoveryPolicies: const <String, CockpitWorkerOperationRecoveryPolicy>{
        'case.run': CockpitWorkerOperationRecoveryPolicy.retryPrepared,
      },
    );
    final invocation = _invocation('case-retry', kind: 'case.run');
    final admission = await first.admit(
      invocation: invocation,
      submittedAt: now,
    );
    await first.markRunning(idempotencyKey: 'case-retry', startedAt: now);

    final reopened = fixture.open(
      recoveryPolicies: const <String, CockpitWorkerOperationRecoveryPolicy>{
        'case.run': CockpitWorkerOperationRecoveryPolicy.retryPrepared,
      },
    );
    await reopened.recover(now: now.add(const Duration(seconds: 1)));
    final retry = await reopened.admit(
      invocation: invocation,
      submittedAt: now.add(const Duration(seconds: 2)),
    );

    expect(retry.execute, isTrue);
    expect(retry.replay, isNull);
    expect(retry.operationId, admission.operationId);
  });

  test(
    'recovers exact active temp remnants and rejects unknown files',
    () async {
      final fixture = await _JournalFixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 7, 22, 5);
      final journal = fixture.open();
      await journal.admit(
        invocation: _invocation('temp-remnant'),
        submittedAt: now,
      );
      await journal.markRunning(idempotencyKey: 'temp-remnant', startedAt: now);
      final record = (await _recordFiles(fixture.path)).single;
      final temp = File(
        p.join(
          record.parent.path,
          '.record.json.123.${List<String>.filled(24, 'a').join()}.tmp',
        ),
      );
      await temp.writeAsString('{"partial":true}');

      await fixture.open().recover(now: now.add(const Duration(seconds: 1)));
      expect(await temp.exists(), isFalse);

      final unknown = await File(
        p.join(record.parent.path, '.record.json.bad.tmp'),
      ).writeAsString('bad');
      await expectLater(
        fixture.open().admit(
          invocation: _invocation('temp-remnant'),
          submittedAt: now.add(const Duration(seconds: 2)),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await unknown.exists(), isTrue);
      await unknown.delete();
      final wrongTarget = await File(
        p.join(
          record.parent.path,
          '.other.json.123.${List<String>.filled(24, 'c').join()}.tmp',
        ),
      ).writeAsString('wrong');
      await expectLater(
        fixture.open().admit(
          invocation: _invocation('temp-remnant'),
          submittedAt: now.add(const Duration(seconds: 3)),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await wrongTarget.exists(), isTrue);
    },
  );

  test('active record symlinks fail closed', () async {
    if (Platform.isWindows) return;
    final fixture = await _JournalFixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime.utc(2026, 7, 22, 6);
    final journal = fixture.open();
    await journal.admit(
      invocation: _invocation('symlink-record'),
      submittedAt: now,
    );
    final record = (await _recordFiles(fixture.path)).single;
    final link = Link(p.join(record.parent.path, 'unknown.json'));
    await link.create(record.path);

    await expectLater(
      fixture.open().recover(now: now.add(const Duration(seconds: 1))),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('active manifest corruption and hash tampering fail closed', () async {
    final corruptFixture = await _JournalFixture.create();
    addTearDown(corruptFixture.dispose);
    await corruptFixture.open().recover(now: DateTime.utc(2026, 7, 22, 7));
    await _manifestFile(corruptFixture.path).writeAsString('{');
    await expectLater(
      corruptFixture.open().recover(now: DateTime.utc(2026, 7, 22, 7, 0, 1)),
      throwsA(isA<CockpitStorageException>()),
    );

    final tamperedFixture = await _JournalFixture.create();
    addTearDown(tamperedFixture.dispose);
    final journal = tamperedFixture.open();
    await journal.admit(
      invocation: _invocation('manifest-tamper'),
      submittedAt: DateTime.utc(2026, 7, 22, 8),
    );
    final manifest =
        jsonDecode(await _manifestFile(tamperedFixture.path).readAsString())
            as Map<String, Object?>;
    final records = manifest['records']! as Map<String, Object?>;
    final value = records.values.single;
    records
      ..clear()
      ..[List<String>.filled(64, '0').join()] = value;
    await _manifestFile(
      tamperedFixture.path,
    ).writeAsString(jsonEncode(manifest));
    await expectLater(
      tamperedFixture.open().recover(now: DateTime.utc(2026, 7, 22, 8, 0, 1)),
      throwsA(isA<FormatException>()),
    );
  });

  test('both active-manifest crash windows recover conservatively', () async {
    final missingFixture = await _JournalFixture.create();
    addTearDown(missingFixture.dispose);
    final missingJournal = missingFixture.open();
    await missingJournal.recover(now: DateTime.utc(2026, 7, 22, 9));
    await _writeManifest(missingFixture.path, <String>['missing-record']);
    await missingFixture.open().recover(
      now: DateTime.utc(2026, 7, 22, 9, 0, 1),
    );
    expect(await _manifestRecords(missingFixture.path), isEmpty);

    final completedFixture = await _JournalFixture.create();
    addTearDown(completedFixture.dispose);
    final now = DateTime.utc(2026, 7, 22, 10);
    final completedJournal = completedFixture.open();
    final admission = await completedJournal.admit(
      invocation: _invocation('completed-window'),
      submittedAt: now,
    );
    await completedJournal.markRunning(
      idempotencyKey: 'completed-window',
      startedAt: now,
    );
    final activeBeforeCompletion = await _manifestFile(
      completedFixture.path,
    ).readAsString();
    await completedJournal.complete(
      idempotencyKey: 'completed-window',
      result: _success(admission.operationId, submittedAt: now),
    );
    await _manifestFile(
      completedFixture.path,
    ).writeAsString(activeBeforeCompletion);
    await completedFixture.open().recover(
      now: now.add(const Duration(seconds: 3)),
    );
    expect(await _manifestRecords(completedFixture.path), isEmpty);
    final replay = await completedFixture.open().admit(
      invocation: _invocation('completed-window'),
      submittedAt: now.add(const Duration(seconds: 4)),
    );
    expect(replay.execute, isFalse);
    expect(replay.operationId, admission.operationId);
  });

  test('startup does not parse inactive completed records', () async {
    final fixture = await _JournalFixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime.utc(2026, 7, 22, 11);
    final journal = fixture.open();
    for (var index = 0; index < 8; index += 1) {
      final key = 'inactive-$index';
      final admission = await journal.admit(
        invocation: _invocation(key),
        submittedAt: now,
      );
      await journal.markRunning(idempotencyKey: key, startedAt: now);
      await journal.complete(
        idempotencyKey: key,
        result: _success(admission.operationId, submittedAt: now),
      );
    }
    final corruptedHash = sha256.convert(utf8.encode('inactive-0')).toString();
    final corruptedRecord = (await _recordFiles(
      fixture.path,
    )).singleWhere((record) => p.basename(record.parent.path) == corruptedHash);
    await corruptedRecord.writeAsString('{');

    await fixture.open().recover(now: now.add(const Duration(seconds: 3)));
    final replay = await fixture.open().admit(
      invocation: _invocation('inactive-7'),
      submittedAt: now.add(const Duration(seconds: 4)),
    );
    expect(replay.execute, isFalse);
  });

  test(
    'initial manifest crash is recoverable only without record evidence',
    () async {
      final fresh = await _JournalFixture.create();
      addTearDown(fresh.dispose);
      final active = await Directory(
        p.join(fresh.path, 'active'),
      ).create(recursive: true);
      final temp = await File(
        p.join(
          active.path,
          '.manifest.json.111.${List<String>.filled(24, 'c').join()}.tmp',
        ),
      ).writeAsString('partial');

      await fresh.open().recover(now: DateTime.utc(2026, 7, 22, 12));
      expect(await temp.exists(), isFalse);
      expect(await _manifestFile(fresh.path).exists(), isTrue);

      final existing = await _JournalFixture.create();
      addTearDown(existing.dispose);
      await existing.open().admit(
        invocation: _invocation('manifest-deleted'),
        submittedAt: DateTime.utc(2026, 7, 22, 13),
      );
      await _manifestFile(existing.path).delete();
      await expectLater(
        existing.open().recover(now: DateTime.utc(2026, 7, 22, 13, 0, 1)),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'active record temp evidence is recovered under its record lock',
    () async {
      final fixture = await _JournalFixture.create();
      addTearDown(fixture.dispose);
      const key = 'record-temp-evidence';
      final hash = sha256.convert(utf8.encode(key)).toString();
      await Directory(p.join(fixture.path, 'active')).create(recursive: true);
      await _writeManifest(fixture.path, const <String>[key]);
      final recordDirectory = await Directory(
        p.join(fixture.path, 'records', hash.substring(0, 2), hash),
      ).create(recursive: true);
      final temp = await File(
        p.join(
          recordDirectory.path,
          '.record.json.333.${List<String>.filled(24, 'e').join()}.tmp',
        ),
      ).writeAsString('partial');

      await expectLater(
        fixture.open().recover(now: DateTime.utc(2026, 7, 22, 14)),
        throwsA(isA<FormatException>()),
      );

      expect(await temp.exists(), isFalse);
      expect((await _manifestRecords(fixture.path)).values, contains(key));
    },
  );
}

CockpitOperationInvocation _invocation(
  String idempotencyKey, {
  String kind = 'mutation.test',
  Map<String, Object?> input = const <String, Object?>{'value': 'original'},
  Iterable<String> requiredFeatures = const <String>[],
}) => CockpitOperationInvocation(
  kind: kind,
  workspaceId: 'workspaceA',
  idempotencyKey: CockpitIdempotencyKey(idempotencyKey),
  deadline: DateTime.utc(2026, 7, 23),
  input: input,
  requiredFeatures: requiredFeatures,
);

CockpitOperationResult _success(
  String operationId, {
  required DateTime submittedAt,
  Map<String, Object?> output = const <String, Object?>{'completed': true},
}) => CockpitOperationResult(
  operationId: operationId,
  kind: 'mutation.test',
  workspaceId: 'workspaceA',
  lifecycle: CockpitOperationLifecycle.completed,
  outcome: CockpitOperationOutcome.succeeded,
  submittedAt: submittedAt,
  startedAt: submittedAt.add(const Duration(seconds: 1)),
  finishedAt: submittedAt.add(const Duration(seconds: 2)),
  output: output,
);

final class _JournalFixture {
  const _JournalFixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_JournalFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-worker-operation-journal-',
    );
    final canonical = await directory.resolveSymbolicLinks();
    return _JournalFixture(directory, p.join(canonical, 'operations'));
  }

  CockpitFileWorkerOperationJournal open({
    Map<String, CockpitWorkerOperationRecoveryPolicy> recoveryPolicies =
        const <String, CockpitWorkerOperationRecoveryPolicy>{},
  }) => CockpitFileWorkerOperationJournal(
    path: path,
    permissionHardener: Platform.isWindows
        ? const CockpitWindowsInheritedAclPermissionHardener()
        : const CockpitPosixPermissionHardener(),
    directorySyncer: const _NoopDirectorySyncer(),
    recoveryPolicies: recoveryPolicies,
  );

  Future<void> dispose() => directory.delete(recursive: true);
}

Future<List<File>> _recordFiles(String root) async => Directory(root)
    .list(recursive: true, followLinks: false)
    .where(
      (entity) => entity is File && p.basename(entity.path) == 'record.json',
    )
    .cast<File>()
    .toList();

File _manifestFile(String root) =>
    File(p.join(root, 'active', 'manifest.json'));

Future<Map<String, Object?>> _manifestRecords(String root) async {
  final manifest =
      jsonDecode(await _manifestFile(root).readAsString())
          as Map<String, Object?>;
  return manifest['records']! as Map<String, Object?>;
}

Future<void> _writeManifest(String root, List<String> keys) async {
  await _manifestFile(root).writeAsString(
    jsonEncode(<String, Object?>{
      'schemaVersion': 'cockpit.worker.operation-active/v1',
      'records': <String, Object?>{
        for (final key in keys)
          sha256.convert(utf8.encode(key)).toString(): key,
      },
    }),
  );
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
