import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_ids.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_run_admission_store.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late CockpitSupervisorRunAdmissionStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-admissions-');
    final paths = await CockpitHome(
      paths: CockpitHomePaths(p.join(temporary.path, 'home')),
      permissionHardener: const _NoopPermissionHardener(),
    ).initialize();
    store = CockpitSupervisorRunAdmissionStore(
      paths: paths,
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
      tokenGenerator: _SequenceTokenGenerator(),
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('lists one workspace newest first with bounded paging', () async {
    await _admit(store, workspaceId: 'workspaceA', token: 'first', minute: 1);
    await _admit(store, workspaceId: 'workspaceB', token: 'other', minute: 2);
    await _admit(store, workspaceId: 'workspaceA', token: 'latest', minute: 3);

    final first = await store.listWorkspace(
      workspaceId: 'workspaceA',
      offset: 0,
      limit: 1,
    );
    final second = await store.listWorkspace(
      workspaceId: 'workspaceA',
      offset: 1,
      limit: 1,
    );

    expect(first.totalCount, 2);
    expect(first.items.single.idempotencyKey, 'latest');
    expect(second.totalCount, 2);
    expect(second.items.single.idempotencyKey, 'first');
  });

  test('accepts the terminal offset and rejects a stale offset', () async {
    await _admit(store, workspaceId: 'workspaceA', token: 'only', minute: 1);

    final terminal = await store.listWorkspace(
      workspaceId: 'workspaceA',
      offset: 1,
      limit: 12,
    );

    expect(terminal.items, isEmpty);
    expect(terminal.totalCount, 1);
    await expectLater(
      store.listWorkspace(workspaceId: 'workspaceA', offset: 2, limit: 12),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<void> _admit(
  CockpitSupervisorRunAdmissionStore store, {
  required String workspaceId,
  required String token,
  required int minute,
}) => store.admit(
  workspaceId: workspaceId,
  idempotencyKey: token,
  fingerprint: _digest,
  projectId: 'projectA',
  documentKind: CockpitRunDocumentKind.testCase,
  documentId: 'caseA',
  sourceSha256: _digest,
  submittedAt: DateTime.utc(2026, 8, 14, 0, minute),
);

const _digest =
    '0000000000000000000000000000000000000000000000000000000000000000';

final class _SequenceTokenGenerator
    implements CockpitTokenGenerator, CockpitResourceIdTokenGenerator {
  var _next = 0;

  @override
  String nextIdToken() => String.fromCharCode('a'.codeUnitAt(0) + _next++);

  @override
  String nextToken({int byteLength = 32}) => nextIdToken();
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
