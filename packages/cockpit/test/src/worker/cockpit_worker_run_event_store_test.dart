import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_ids.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/worker/cockpit_worker_case_completion.dart';
import 'package:cockpit/src/worker/cockpit_worker_case_run_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_request.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_run_event_store.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String stateRoot;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-events-');
    stateRoot = await temporary.resolveSymbolicLinks();
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'repairs a partial trailing line without changing durable events',
    () async {
      final file = await _writeLog(stateRoot, <String>[
        jsonEncode(_event(runId: 'runA', eventId: 'eventA').toJson()),
        '{"partial":',
      ], trailingNewline: false);

      await _store(stateRoot).initialize();

      final lines = const LineSplitter()
          .convert(await file.readAsString())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(lines, hasLength(1));
      expect(
        CockpitRunEvent.fromJson(jsonDecode(lines.single)).eventId,
        'eventA',
      );
    },
  );

  test('fails closed for complete corruption and ownership mismatch', () async {
    await _writeLog(stateRoot, <String>[
      jsonEncode(_event(runId: 'runA', eventId: 'eventA').toJson()),
      '{not-json}',
    ]);
    await expectLater(
      _store(stateRoot).initialize(),
      throwsA(isA<FormatException>()),
    );

    await temporary.delete(recursive: true);
    temporary = await Directory.systemTemp.createTemp('cockpit-events-owner-');
    stateRoot = await temporary.resolveSymbolicLinks();
    await _writeLog(stateRoot, <String>[
      jsonEncode(
        _event(
          runId: 'runA',
          eventId: 'eventA',
          workspaceId: 'workspaceB',
        ).toJson(),
      ),
    ]);
    await expectLater(
      _store(stateRoot).initialize(),
      throwsA(isA<FormatException>()),
    );
  });

  test('redactor failure persists neither event nor relay metadata', () async {
    final publisher = _RecordingPublisher();
    final store = _store(
      stateRoot,
      publisher: publisher,
      redactor: (_) => throw StateError('redaction failed'),
    );

    await expectLater(
      store.append('runA', _terminalDraft()),
      throwsA(isA<StateError>()),
    );

    expect(
      await File(p.join(stateRoot, 'runs', 'runA', 'events.ndjson')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(stateRoot, 'runs', 'runA', 'relay.json')).exists(),
      isFalse,
    );
    expect(publisher.calls, isEmpty);
  });

  test(
    'rejects a globally duplicated event id before the second append',
    () async {
      final store = _store(
        stateRoot,
        tokenGenerator: const _FixedTokenGenerator('same-token'),
      );
      await store.append('runA', _terminalDraft());

      await expectLater(
        store.append('runB', _terminalDraft()),
        throwsA(isA<FormatException>()),
      );

      expect(
        await File(p.join(stateRoot, 'runs', 'runB', 'events.ndjson')).exists(),
        isFalse,
      );
    },
  );

  test(
    'replays a durable append when acknowledgement response is lost',
    () async {
      final publisher = _RecordingPublisher(loseFirstResponse: true);
      final first = _store(stateRoot, publisher: publisher);
      await expectLater(
        first.append('runA', _terminalDraft()),
        throwsA(isA<StateError>()),
      );
      expect(publisher.events['runA'], hasLength(1));

      final restarted = _store(stateRoot, publisher: publisher);
      await restarted.initialize();
      await restarted.resume();

      expect(publisher.calls, hasLength(2));
      expect(publisher.events['runA'], hasLength(1));
      final relay =
          jsonDecode(
                await File(
                  p.join(stateRoot, 'runs', 'runA', 'relay.json'),
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(relay['sequence'], 1);
    },
  );

  test('stops replay after the Supervisor terminalizes a run', () async {
    await _store(
      stateRoot,
    ).append('runA', _terminalDraft(), publishImmediately: false);
    final publisher = _TerminalPublisher();
    final recovered = _store(stateRoot, publisher: publisher);

    await recovered.resume();
    await recovered.publishRun('runA');

    expect(publisher.calls, hasLength(1));
    final relay =
        jsonDecode(
              await File(
                p.join(stateRoot, 'runs', 'runA', 'relay.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    expect(relay['sequence'], 1);
  });

  test('does not advance acknowledgement for an unresolved gap', () async {
    final store = _store(stateRoot, publisher: const _GapPublisher());

    await expectLater(
      store.append('runA', _terminalDraft()),
      throwsA(isA<FormatException>()),
    );

    final relay = File(p.join(stateRoot, 'runs', 'runA', 'relay.json'));
    expect(await relay.exists(), isFalse);
    final replay = await store.replay(
      CockpitWorkerReplayEventsRequest(
        protocolVersion: cockpitWorkerProtocolVersion,
        workspaceId: 'workspaceA',
        requestId: 'replay-unresolved-gap',
        deadline: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        idempotencyKey: 'replay-unresolved-gap',
        runId: 'runA',
        afterSequence: 0,
      ),
    );
    expect(replay.events, hasLength(1));
  });

  test('initialization leaves recovery decisions to case state', () async {
    await _store(stateRoot).append(
      'runA',
      const CockpitWorkerEventDraft(
        kind: 'attempt.running',
        entityKind: CockpitRunEventEntityKind.attempt,
        caseId: 'caseA',
        attemptId: 'attemptA',
      ),
    );

    await _store(stateRoot).initialize();
    await _store(stateRoot).initialize();

    final events = const LineSplitter()
        .convert(
          await File(
            p.join(stateRoot, 'runs', 'runA', 'events.ndjson'),
          ).readAsString(),
        )
        .where((line) => line.isNotEmpty)
        .map((line) => CockpitRunEvent.fromJson(jsonDecode(line)))
        .toList();
    expect(events.map((event) => event.kind), <String>['attempt.running']);
  });

  test(
    'persists and reconciles an exact completion batch idempotently',
    () async {
      final phases = <CockpitWorkerCaseCompletionPhase>[];
      void observer(CockpitWorkerCaseCompletionObservation observation) {
        phases.add(observation.phase);
        throw StateError('telemetry failed');
      }

      final cases = CockpitWorkerCaseRunStore.memory(
        workspaceId: 'workspaceA',
        completionObserver: observer,
      );
      final events = _store(stateRoot, completionObserver: observer);
      final now = DateTime.utc(2026, 7, 22, 3);
      final reservation = await cases.reserve(
        idempotencyKey: 'case-completion',
        requestFingerprint: List<String>.filled(64, 'a').join(),
        caseId: 'caseA',
        proposedRunId: 'runA',
        proposedAttemptId: 'attemptA',
        now: now,
      );
      await cases.markRunning(
        idempotencyKey: 'case-completion',
        runId: reservation.runId,
        attemptId: reservation.attemptId,
        now: now,
      );
      await events.append(
        reservation.runId,
        CockpitWorkerEventDraft(
          kind: 'attempt.running',
          entityKind: CockpitRunEventEntityKind.attempt,
          caseId: 'caseA',
          attemptId: reservation.attemptId,
        ),
      );
      final output = <String, Object?>{
        'runId': reservation.runId,
        'attemptId': reservation.attemptId,
        'result': const <String, Object?>{'outcome': 'passed'},
      };
      final intent = await events.appendCompletionBatch(
        runId: reservation.runId,
        drafts: _completionDrafts(reservation.attemptId),
        persistIntent: (exact) => cases.prepareCompletionIntent(
          idempotencyKey: 'case-completion',
          runId: reservation.runId,
          attemptId: reservation.attemptId,
          intentId: 'completion_exact',
          output: output,
          events: exact,
          now: now.add(const Duration(seconds: 1)),
        ),
      );
      await cases.commitCompletionIntent(
        intent: intent,
        now: now.add(const Duration(seconds: 2)),
      );

      final reopened = _store(stateRoot, completionObserver: observer);
      await reopened.initialize();
      await reopened.reconcileCompletionIntent(intent);
      final replay = await reopened.replay(
        CockpitWorkerReplayEventsRequest(
          protocolVersion: cockpitWorkerProtocolVersion,
          workspaceId: 'workspaceA',
          requestId: 'replay-completion',
          deadline: now.add(const Duration(minutes: 1)),
          idempotencyKey: 'replay-completion',
          runId: reservation.runId,
          afterSequence: 0,
        ),
      );
      expect(replay.events, hasLength(4));
      expect(
        replay.events.skip(1).map((event) => event.toJson()),
        intent.events.map((event) => event.toJson()),
      );
      expect(phases, <CockpitWorkerCaseCompletionPhase>[
        CockpitWorkerCaseCompletionPhase.intentPersisted,
        CockpitWorkerCaseCompletionPhase.eventsReconciled,
        CockpitWorkerCaseCompletionPhase.completionCommitted,
        CockpitWorkerCaseCompletionPhase.eventsReconciled,
      ]);
    },
  );

  test('persists and publishes a result event batch in one exchange', () async {
    final publisher = _RecordingPublisher();
    final store = _store(stateRoot, publisher: publisher);
    final drafts = <CockpitWorkerEventDraft>[
      for (var index = 0; index < 64; index += 1)
        CockpitWorkerEventDraft(
          kind: 'step.passed',
          entityKind: CockpitRunEventEntityKind.step,
          caseId: 'caseA',
          attemptId: 'attemptA',
          stepExecutionId: 'main/step$index',
          stepStatus: CockpitTestStepStatus.passed,
        ),
    ];

    final appended = await store.appendBatch('runA', drafts);

    expect(appended, hasLength(64));
    expect(
      appended.map((event) => event.sequence),
      orderedEquals(<int>[
        for (var sequence = 1; sequence <= 64; sequence += 1) sequence,
      ]),
    );
    expect(publisher.calls, hasLength(1));
    expect(publisher.calls.single.events, hasLength(64));
    expect(publisher.events['runA'], hasLength(64));
  });

  test('chunks a durable result batch at the publication limit', () async {
    final publisher = _RecordingPublisher();
    final store = _store(stateRoot, publisher: publisher);
    final drafts = <CockpitWorkerEventDraft>[
      for (var index = 0; index < 300; index += 1)
        CockpitWorkerEventDraft(
          kind: 'step.passed',
          entityKind: CockpitRunEventEntityKind.step,
          caseId: 'caseA',
          attemptId: 'attemptA',
          stepExecutionId: 'main/step$index',
          stepStatus: CockpitTestStepStatus.passed,
        ),
    ];

    await store.appendBatch('runA', drafts);

    expect(publisher.calls, hasLength(2));
    expect(
      publisher.calls.map((request) => request.events.length),
      orderedEquals(<int>[256, 44]),
    );
    expect(publisher.events['runA'], hasLength(300));
    expect(await _store(stateRoot).eventsForRun('runA'), hasLength(300));
  });
}

CockpitWorkerRunEventStore _store(
  String stateRoot, {
  CockpitWorkerEventPublisher? publisher,
  CockpitWorkerEventRedactor? redactor,
  CockpitTokenGenerator? tokenGenerator,
  CockpitWorkerCaseCompletionObserver? completionObserver,
}) => CockpitWorkerRunEventStore(
  projectId: 'projectA',
  workspaceId: 'workspaceA',
  stateRoot: stateRoot,
  permissionHardener: const _NoopPermissionHardener(),
  directorySyncer: const _NoopDirectorySyncer(),
  redactor: redactor ?? ((value) => value),
  publisher: publisher,
  tokenGenerator: tokenGenerator,
  completionObserver: completionObserver,
);

List<CockpitWorkerEventDraft> _completionDrafts(String attemptId) =>
    <CockpitWorkerEventDraft>[
      CockpitWorkerEventDraft(
        kind: 'attempt.completed',
        entityKind: CockpitRunEventEntityKind.attempt,
        caseId: 'caseA',
        attemptId: attemptId,
        outcome: CockpitRunOutcome.passed,
      ),
      CockpitWorkerEventDraft(
        kind: 'case.completed',
        entityKind: CockpitRunEventEntityKind.testCase,
        caseId: 'caseA',
        attemptId: attemptId,
        outcome: CockpitRunOutcome.passed,
        stability: CockpitRunStability.stable,
      ),
      CockpitWorkerEventDraft(
        kind: 'run.completed',
        entityKind: CockpitRunEventEntityKind.run,
        lifecycle: CockpitRunLifecycle.completed,
        outcome: CockpitRunOutcome.passed,
        stability: CockpitRunStability.stable,
      ),
    ];

CockpitWorkerEventDraft _terminalDraft() => const CockpitWorkerEventDraft(
  kind: 'run.completed',
  entityKind: CockpitRunEventEntityKind.run,
  lifecycle: CockpitRunLifecycle.completed,
  outcome: CockpitRunOutcome.passed,
  stability: CockpitRunStability.stable,
);

CockpitRunEvent _event({
  required String runId,
  required String eventId,
  String workspaceId = 'workspaceA',
}) => CockpitRunEvent(
  eventId: eventId,
  sequence: 1,
  timestamp: DateTime.utc(2026, 7, 22),
  kind: 'run.completed',
  entityKind: CockpitRunEventEntityKind.run,
  projectId: 'projectA',
  workspaceId: workspaceId,
  runId: runId,
  lifecycle: CockpitRunLifecycle.completed,
  outcome: CockpitRunOutcome.passed,
  stability: CockpitRunStability.stable,
);

Future<File> _writeLog(
  String stateRoot,
  List<String> lines, {
  bool trailingNewline = true,
}) async {
  final directory = await Directory(
    p.join(stateRoot, 'runs', 'runA'),
  ).create(recursive: true);
  final file = File(p.join(directory.path, 'events.ndjson'));
  await file.writeAsString(
    '${lines.join('\n')}${trailingNewline ? '\n' : ''}',
    flush: true,
  );
  return file;
}

final class _RecordingPublisher implements CockpitWorkerEventPublisher {
  _RecordingPublisher({this.loseFirstResponse = false});

  final bool loseFirstResponse;
  final List<CockpitWorkerPublishEventBatchRequest> calls = [];
  final Map<String, List<CockpitRunEvent>> events = {};

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    calls.add(request);
    final persisted = events.putIfAbsent(request.runId, () => []);
    for (final event in request.events) {
      if (event.sequence > persisted.length) persisted.add(event);
    }
    if (loseFirstResponse && calls.length == 1) {
      throw StateError('acknowledgement response lost');
    }
    return CockpitWorkerPublishEventBatchResult(
      runId: request.runId,
      highestContiguousSequence: persisted.length,
      terminal: false,
    );
  }
}

final class _GapPublisher implements CockpitWorkerEventPublisher {
  const _GapPublisher();

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async => CockpitWorkerPublishEventBatchResult(
    runId: request.runId,
    highestContiguousSequence: request.afterSequence,
    terminal: false,
    replayAfterSequence: request.afterSequence,
  );
}

final class _TerminalPublisher implements CockpitWorkerEventPublisher {
  final List<CockpitWorkerPublishEventBatchRequest> calls = [];

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    calls.add(request);
    return CockpitWorkerPublishEventBatchResult(
      runId: request.runId,
      highestContiguousSequence: request.events.last.sequence,
      terminal: true,
    );
  }
}

final class _FixedTokenGenerator implements CockpitTokenGenerator {
  const _FixedTokenGenerator(this.value);

  final String value;

  @override
  String nextToken({int byteLength = 32}) => value;
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
