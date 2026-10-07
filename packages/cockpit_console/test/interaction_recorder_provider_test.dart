import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connect resolves the endpoint and reports the idle status', () async {
    final (container, client) = _container();

    container.read(interactionRecorderProvider.notifier).select(_key);
    await pumpEventQueue();

    final state = container.read(interactionRecorderProvider);
    expect(state.selected, _key);
    expect(state.endpoint, client.baseUri);
    expect(state.phase, CockpitRecorderPhase.idle);
    expect(state.stepCount, 0);
    expect(state.unresolvedCount, 0);
    expect(state.steps, isEmpty);
    expect(state.connectionError, isNull);
  });

  test('poll appends drained steps and advances the cursor', () async {
    final (container, client) = _container();
    final notifier = container.read(interactionRecorderProvider.notifier);
    notifier.select(_key);
    await pumpEventQueue();
    // Connecting already performed one idle poll at cursor 0.
    expect(client.stepCursors, <int>[0]);

    client
      ..setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'r1',
        stepCount: 1,
        unresolvedCount: 0,
      )
      ..recordedSteps = [_step('s1')];
    await notifier.poll();
    expect(container.read(interactionRecorderProvider).steps, hasLength(1));

    client
      ..setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'r1',
        stepCount: 2,
        unresolvedCount: 1,
      )
      ..recordedSteps = [_step('s1'), _step('s2')];
    await notifier.poll();

    final state = container.read(interactionRecorderProvider);
    expect(client.stepCursors, <int>[0, 0, 1]);
    expect(state.steps.map((step) => step.stepId), <String>['s1', 's2']);
    expect(state.phase, CockpitRecorderPhase.recording);
    expect(state.stepCount, 2);
    expect(state.unresolvedCount, 1);
  });

  test('a new recording session on the app restarts the timeline', () async {
    final (container, client) = _container();
    final notifier = container.read(interactionRecorderProvider.notifier);
    notifier.select(_key);
    await pumpEventQueue();

    client
      ..setSession(
        phase: CockpitRecorderPhase.stopped,
        sessionId: 'r1',
        stepCount: 2,
      )
      ..recordedSteps = [_step('s1'), _step('s2')];
    await notifier.poll();
    expect(container.read(interactionRecorderProvider).steps, hasLength(2));

    client
      ..setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'r2',
        stepCount: 1,
      )
      ..recordedSteps = [_step('n1')];
    await notifier.poll();

    final state = container.read(interactionRecorderProvider);
    expect(state.steps.map((step) => step.stepId), <String>['n1']);
    expect(client.stepCursors.last, 0); // The timeline restarted at cursor 0.
    expect(state.phase, CockpitRecorderPhase.recording);
    expect(state.sessionId, 'r2');
  });

  test(
    'command failures surface inline without wedging the busy flag',
    () async {
      final (container, client) = _container();
      final notifier = container.read(interactionRecorderProvider.notifier);
      notifier.select(_key);
      await pumpEventQueue();

      client.commandFailure = StateError('Cannot pause while idle.');
      await notifier.pause();

      var state = container.read(interactionRecorderProvider);
      expect(state.commandError, contains('Cannot pause while idle.'));
      expect(state.commandBusy, isFalse);

      client.commandFailure = null;
      client.setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'r1',
        stepCount: 0,
      );
      await notifier.start(name: 'login flow');
      state = container.read(interactionRecorderProvider);
      expect(state.commandError, isNull);
      expect(state.phase, CockpitRecorderPhase.recording);
      expect(client.commandLog, <String>['pause', 'start:login flow']);
    },
  );

  test('export stores the case YAML for the preview pane', () async {
    final (container, client) = _container();
    final notifier = container.read(interactionRecorderProvider.notifier);
    notifier.select(_key);
    await pumpEventQueue();

    await notifier.export();
    expect(container.read(interactionRecorderProvider).document, _caseYaml);
  });

  test(
    'connection failures surface inline and leave the endpoint unset',
    () async {
      final container = ProviderContainer(
        overrides: [
          interactionRecorderConnectorProvider.overrideWithValue(
            (key) async => throw StateError('bridge unavailable'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(interactionRecorderProvider.notifier).select(_key);
      await pumpEventQueue();

      final state = container.read(interactionRecorderProvider);
      expect(state.endpoint, isNull);
      expect(state.connectionError, contains('bridge unavailable'));
    },
  );

  testWidgets('polling follows the page lifecycle and the poll interval', (
    tester,
  ) async {
    final (container, client) = _container();
    final notifier = container.read(interactionRecorderProvider.notifier);

    notifier.startPolling();
    await tester.pump();
    expect(client.stepCursors, isEmpty); // No endpoint resolved yet.

    notifier.select(_key);
    await tester.pump();
    expect(client.stepCursors, <int>[0]); // Connect resolves, then polls.

    client.recordedSteps = [_step('s1')];
    await tester.pump(interactionRecorderPollInterval);
    expect(client.stepCursors, <int>[0, 0]);
    expect(container.read(interactionRecorderProvider).steps, hasLength(1));

    client.recordedSteps = [_step('s1'), _step('s2')];
    await tester.pump(interactionRecorderPollInterval);
    expect(client.stepCursors.last, 1); // Cursor advanced to the drain total.

    notifier.stopPolling();
    client.recordedSteps = [_step('s1'), _step('s2'), _step('s3')];
    await tester.pump(const Duration(seconds: 30));
    expect(client.stepCursors, hasLength(3)); // Polling halted.
  });
}

const _key = SessionMonitorKey(workspaceId: 'ws-1', sessionId: 'session-1');

const _caseYaml = 'kind: case\nid: recorded-r1\n';

(ProviderContainer, _FakeRecorderClient) _container() {
  final client = _FakeRecorderClient();
  final container = ProviderContainer(
    overrides: [
      interactionRecorderConnectorProvider.overrideWithValue(
        (key) async => client,
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container, client);
}

CockpitInteractionStep _step(String id) => CockpitInteractionStep(
  stepId: id,
  kind: CockpitInteractionStepKind.tap,
  locatorCandidates: <CockpitLocatorCandidate>[
    CockpitLocatorCandidate(kind: 'key', selector: 'key:$id', score: 4),
  ],
  phase: CockpitRecorderPhase.recording,
  recordedAt: DateTime.utc(2026, 10, 7, 9),
);

/// In-memory recorder endpoint: scriptable status, drained steps, and
/// optional per-command failures.
final class _FakeRecorderClient implements InteractionRecorderClient {
  @override
  final Uri baseUri = Uri.parse('http://127.0.0.1:18434');

  Map<String, Object?> _status = <String, Object?>{'phase': 'idle'};

  List<CockpitInteractionStep> recordedSteps = <CockpitInteractionStep>[];

  Object? commandFailure;

  final List<String> commandLog = <String>[];

  final List<int> stepCursors = <int>[];

  void setSession({
    required CockpitRecorderPhase phase,
    required String sessionId,
    required int stepCount,
    int unresolvedCount = 0,
  }) {
    _status = <String, Object?>{
      'sessionId': sessionId,
      'phase': phase.name,
      'startedAt': DateTime.utc(2026, 10, 7, 9).toIso8601String(),
      'stepCount': stepCount,
      'unresolvedCount': unresolvedCount,
    };
  }

  @override
  Future<Map<String, Object?>> start({String? name}) async =>
      _run('start:${name ?? ''}');

  @override
  Future<Map<String, Object?>> pause() async => _run('pause');

  @override
  Future<Map<String, Object?>> resume() async => _run('resume');

  @override
  Future<Map<String, Object?>> stop() async => _run('stop');

  Future<Map<String, Object?>> _run(String entry) async {
    commandLog.add(entry);
    final failure = commandFailure;
    if (failure != null) throw failure;
    return _status;
  }

  @override
  Future<Map<String, Object?>> status() async => _status;

  @override
  Future<Map<String, Object?>> steps({int after = 0}) async {
    stepCursors.add(after);
    return <String, Object?>{
      'steps': <Object?>[
        for (final step in recordedSteps.skip(after)) step.toJson(),
      ],
      'total': recordedSteps.length,
    };
  }

  @override
  Future<String> exportCaseYaml() async => _caseYaml;
}
