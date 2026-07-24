import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/suite/cockpit_suite_execution_plan.dart';
import 'package:cockpit/src/suite/cockpit_suite_scheduler.dart';
import 'package:cockpit/src/worker/cockpit_worker_suite_run_store.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'suite checkpoints and session affinity survive store reconstruction',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-suite-store-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final path = p.join(temporary.path, 'runs.json');
      final first = _store(path);
      final startedAt = DateTime.utc(2026, 7, 24, 9);
      final reservation = await first.reserve(
        runId: 'run_resume',
        idempotencyKey: 'suite-resume-key',
        requestFingerprint: _digest('a'),
        suiteId: 'suiteResume',
        sourceSha256: _digest('b'),
        startedAt: startedAt,
      );
      expect(reservation.progress, isEmpty);

      await first.recordNodeStarted(
        runId: 'run_resume',
        nodeId: 'nodeCase',
        entryId: 'entryCase',
        kind: CockpitSuitePlanNodeKind.testCase,
        startedAt: startedAt,
      );
      await first.recordAttemptStarted(
        runId: 'run_resume',
        nodeId: 'nodeCase',
        attemptId: 'attempt_nodeCase_1',
        attemptNumber: 1,
        startedAt: startedAt,
        targetId: 'targetA',
      );
      await first.bindSession(
        runId: 'run_resume',
        bindingKey: 'row:nodeCase:targetA',
        sessionResourceId: 'session_resume',
      );

      final recovered = await _store(path).reserve(
        runId: 'run_resume',
        idempotencyKey: 'suite-resume-key',
        requestFingerprint: _digest('a'),
        suiteId: 'suiteResume',
        sourceSha256: _digest('b'),
        startedAt: startedAt.add(const Duration(days: 1)),
      );
      expect(recovered.startedAt, startedAt);
      expect(recovered.progress, hasLength(1));
      expect(recovered.progress.single.activeAttempt?.number, 1);
      expect(recovered.sessionBindings, const <String, String>{
        'row:nodeCase:targetA': 'session_resume',
      });

      final interrupted = CockpitTestAttemptReport(
        attemptId: 'attempt_nodeCase_1',
        number: 1,
        outcome: CockpitRunOutcome.interrupted,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 2)),
        durationMs: 2000,
        targetId: 'targetA',
        failure: CockpitFailure(
          primary: CockpitApiError(
            code: CockpitErrorCode.interrupted,
            category: CockpitErrorCategory.interrupted,
            message: 'Worker terminated.',
            retryable: true,
            responsibleLayer: CockpitResponsibleLayer.worker,
          ),
        ),
      );
      await first.recordAttemptCompleted(
        runId: 'run_resume',
        nodeId: 'nodeCase',
        attempt: interrupted,
      );
      await first.recordExecution(
        runId: 'run_resume',
        execution: CockpitSuiteNodeExecution(
          nodeId: 'nodeCase',
          entryId: 'entryCase',
          kind: CockpitSuitePlanNodeKind.testCase,
          outcome: CockpitRunOutcome.interrupted,
          stability: CockpitRunStability.stable,
          attempts: <CockpitTestAttemptReport>[interrupted],
          startedAt: startedAt,
          finishedAt: interrupted.finishedAt,
        ),
        releasedSessionBindingKeys: const <String>{'row:nodeCase:targetA'},
      );
      await first.complete(
        runId: 'run_resume',
        output: const <String, Object?>{
          'runId': 'run_resume',
          'outcome': 'interrupted',
        },
      );

      final completed = await _store(path).reserve(
        runId: 'run_resume',
        idempotencyKey: 'suite-resume-key',
        requestFingerprint: _digest('a'),
        suiteId: 'suiteResume',
        sourceSha256: _digest('b'),
        startedAt: startedAt,
      );
      expect(completed.completed, isTrue);
      expect(completed.progress, isEmpty);
      expect(completed.sessionBindings, isEmpty);
    },
  );
}

CockpitWorkerSuiteRunStore _store(String path) => CockpitWorkerSuiteRunStore(
  workspaceId: 'workspaceOne',
  path: path,
  permissionHardener: const _NoopPermissionHardener(),
  directorySyncer: const _NoopDirectorySyncer(),
);

String _digest(String character) => List<String>.filled(64, character).join();

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
