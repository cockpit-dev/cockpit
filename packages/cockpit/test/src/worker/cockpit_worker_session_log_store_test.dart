import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/worker/cockpit_worker_logger.dart';
import 'package:cockpit/src/worker/cockpit_worker_session_log_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'session logs are redacted, serialized, and retain newest lines',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cockpit-session-logs-',
      );
      addTearDown(() => root.delete(recursive: true));
      final redactor = CockpitWorkerLogRedactor(
        sensitiveValues: const <String>['top-secret'],
      );
      final store = CockpitWorkerSessionLogStore(
        root: p.join(root.path, 'logs'),
        redactor: redactor,
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
        utcNow: () => DateTime.utc(2026, 8, 23, 12),
        maximumFileBytes: 64 * 1024,
        maximumLineBytes: 1024,
      );

      final path = await store.create('s42');
      final padding = List<String>.filled(850, 'x').join();
      await Future.wait<void>([
        for (var index = 0; index < 100; index += 1)
          store.append('s42', 'line-$index top-secret $padding'),
      ]);
      await store.flush('s42');

      final file = File(path);
      final contents = await file.readAsString();
      expect(await file.length(), lessThanOrEqualTo(64 * 1024));
      expect(contents, isNot(contains('top-secret')));
      expect(contents, contains('[REDACTED]'));
      expect(contents, contains('line-99'));
      expect(contents, isNot(contains('line-0 ')));
      expect(contents, contains('[2026-08-23T12:00:00.000Z]'));
    },
  );

  test(
    'creating an existing session log starts a clean launch record',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cockpit-session-log-reset-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = CockpitWorkerSessionLogStore(
        root: root.path,
        redactor: CockpitWorkerLogRedactor(),
        permissionHardener: const _NoopPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      );

      final path = await store.create('s1');
      await store.append('s1', 'old launch');
      await store.create('s1');
      await store.append('s1', 'new launch');
      await store.flush('s1');

      final contents = await File(path).readAsString();
      expect(contents, contains('new launch'));
      expect(contents, isNot(contains('old launch')));
    },
  );
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

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
