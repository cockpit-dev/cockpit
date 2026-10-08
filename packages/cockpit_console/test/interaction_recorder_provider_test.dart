import 'dart:async';

import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connect resolves the client and reports the idle status', () async {
    final (container, client) = _container();

    container.read(interactionRecorderProvider.notifier).select(_key);
    await pumpEventQueue();

    final state = container.read(interactionRecorderProvider);
    expect(state.selected, _key);
    expect(state.connected, isTrue);
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
    'connection failures surface inline and leave the session unconnected',
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
      expect(state.connected, isFalse);
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
    expect(client.stepCursors, isEmpty); // No session connected yet.

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

  testWidgets('provider disposal stops the poll timer', (tester) async {
    final (container, client) = _container();
    final notifier = container.read(interactionRecorderProvider.notifier);

    notifier.startPolling();
    notifier.select(_key);
    await tester.pump();
    await tester.pump(interactionRecorderPollInterval);
    expect(client.stepCursors, hasLength(2));

    container.dispose();
    client.recordedSteps = [_step('s1')];
    await tester.pump(const Duration(seconds: 30));
    expect(client.stepCursors, hasLength(2)); // Timer cancelled on dispose.
  });

  group('connection lifecycle', () {
    test(
      'a failed connect can be re-resolved into a working connection',
      () async {
        var attempts = 0;
        final client = _FakeRecorderClient();
        final container = ProviderContainer(
          overrides: [
            interactionRecorderConnectorProvider.overrideWithValue((key) async {
              attempts++;
              if (attempts == 1) throw StateError('bridge unavailable');
              return client;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(interactionRecorderProvider.notifier);

        notifier.select(_key);
        await pumpEventQueue();
        var state = container.read(interactionRecorderProvider);
        expect(state.connected, isFalse);
        expect(state.connectionError, contains('bridge unavailable'));

        await notifier.connect();
        state = container.read(interactionRecorderProvider);
        expect(state.connected, isTrue);
        expect(state.connectionError, isNull);
        expect(attempts, 2);
      },
    );

    test('connect attempts while connecting are ignored', () async {
      final gate = Completer<void>();
      var connectorCalls = 0;
      final container = ProviderContainer(
        overrides: [
          interactionRecorderConnectorProvider.overrideWithValue((key) async {
            connectorCalls++;
            await gate.future;
            return _FakeRecorderClient();
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(interactionRecorderProvider.notifier);

      notifier.select(_key);
      await notifier.connect(); // In flight already; this is a no-op.
      await pumpEventQueue();
      expect(connectorCalls, 1);
      expect(container.read(interactionRecorderProvider).connecting, isTrue);

      gate.complete();
      await pumpEventQueue();
      expect(connectorCalls, 1);
      expect(container.read(interactionRecorderProvider).connecting, isFalse);
    });

    test(
      'reselecting the connected session is a no-op, another session rebinds',
      () async {
        final clients = <SessionMonitorKey, _FakeRecorderClient>{
          _keyA: _FakeRecorderClient(),
          _keyB: _FakeRecorderClient(),
        };
        var connectorCalls = 0;
        final container = ProviderContainer(
          overrides: [
            interactionRecorderConnectorProvider.overrideWithValue((key) async {
              connectorCalls++;
              return clients[key]!;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(interactionRecorderProvider.notifier);

        notifier.select(_keyA);
        await pumpEventQueue();
        final clientA = clients[_keyA]!;
        clientA
          ..setSession(
            phase: CockpitRecorderPhase.recording,
            sessionId: 'rA',
            stepCount: 1,
          )
          ..recordedSteps = [_step('a1')];
        await notifier.poll();

        notifier.select(_keyA); // Already bound: ignored.
        await pumpEventQueue();
        var state = container.read(interactionRecorderProvider);
        expect(connectorCalls, 1);
        expect(state.steps, hasLength(1));

        notifier.select(_keyB); // Different session: view resets and rebinds.
        await pumpEventQueue();
        state = container.read(interactionRecorderProvider);
        expect(state.selected, _keyB);
        expect(state.connected, isTrue);
        expect(state.steps, isEmpty);
        expect(state.sessionId, isNull);
        expect(state.document, isNull);
        expect(connectorCalls, 2);
      },
    );
  });

  group('stale async results never leak into a newer selection', () {
    test(
      'a superseded connect cannot adopt another session connection',
      () async {
        final releaseA = Completer<void>();
        var aResolved = false;
        final clientB = _FakeRecorderClient();
        final container = ProviderContainer(
          overrides: [
            interactionRecorderConnectorProvider.overrideWithValue((key) async {
              if (key == _keyA) {
                await releaseA.future;
                aResolved = true;
                return _FakeRecorderClient();
              }
              return clientB;
            }),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(interactionRecorderProvider.notifier);

        notifier.select(_keyA); // Slow connect for A stays in flight…
        notifier.select(_keyB); // …while B resolves and binds.
        await pumpEventQueue();
        expect(container.read(interactionRecorderProvider).connected, isTrue);

        releaseA.complete(); // A finishes last; it must be discarded.
        await pumpEventQueue();
        final state = container.read(interactionRecorderProvider);
        expect(aResolved, isTrue);
        expect(state.selected, _keyB);
        expect(state.connected, isTrue);
      },
    );

    test('a superseded poll cannot apply the old session timeline', () async {
      final clientA = _FakeRecorderClient();
      final clientB = _FakeRecorderClient();
      final clients = <SessionMonitorKey, _FakeRecorderClient>{
        _keyA: clientA,
        _keyB: clientB,
      };
      final container = ProviderContainer(
        overrides: [
          interactionRecorderConnectorProvider.overrideWithValue(
            (key) async => clients[key]!,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(interactionRecorderProvider.notifier);

      notifier.select(_keyA);
      await pumpEventQueue();
      // One poll for A completed during connect; hold the next one open.
      expect(clientA.stepCursors, <int>[0]);
      clientA.statusGate = Completer<void>();
      final slowPoll = notifier.poll();
      clientA.setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'rA',
        stepCount: 1,
      );
      clientA.recordedSteps = [_step('a1')];

      notifier.select(_keyB);
      await pumpEventQueue();
      expect(container.read(interactionRecorderProvider).connected, isTrue);

      clientA.statusGate!.complete(); // A's read finishes after the switch.
      await slowPoll;
      await pumpEventQueue();
      final state = container.read(interactionRecorderProvider);
      expect(state.steps, isEmpty); // A's timeline never landed on B.
      expect(state.sessionId, isNull);
      expect(clientA.stepCursors, <int>[0]); // A was never drained again.
    });

    test(
      'a superseded export cannot preview the old session document',
      () async {
        final clientA = _FakeRecorderClient();
        final clientB = _FakeRecorderClient();
        final clients = <SessionMonitorKey, _FakeRecorderClient>{
          _keyA: clientA,
          _keyB: clientB,
        };
        final container = ProviderContainer(
          overrides: [
            interactionRecorderConnectorProvider.overrideWithValue(
              (key) async => clients[key]!,
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(interactionRecorderProvider.notifier);

        notifier.select(_keyA);
        await pumpEventQueue();
        clientA.exportGate = Completer<void>();
        final slowExport = notifier.export();

        notifier.select(_keyB);
        await pumpEventQueue();

        clientA.exportGate!.complete();
        await slowExport;
        await pumpEventQueue();
        expect(container.read(interactionRecorderProvider).document, isNull);
      },
    );

    test('a superseded command failure stays on its own session', () async {
      final clientA = _FakeRecorderClient();
      final clientB = _FakeRecorderClient();
      final clients = <SessionMonitorKey, _FakeRecorderClient>{
        _keyA: clientA,
        _keyB: clientB,
      };
      final container = ProviderContainer(
        overrides: [
          interactionRecorderConnectorProvider.overrideWithValue(
            (key) async => clients[key]!,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(interactionRecorderProvider.notifier);

      notifier.select(_keyA);
      await pumpEventQueue();
      clientA.commandGate = Completer<void>();
      clientA.commandFailure = StateError('A exploded');
      final slowStop = notifier.stop();

      notifier.select(_keyB);
      await pumpEventQueue();

      clientA.commandGate!.complete();
      await slowStop;
      await pumpEventQueue();
      final state = container.read(interactionRecorderProvider);
      expect(state.selected, _keyB);
      expect(state.commandError, isNull); // A's error did not follow the user.
      expect(state.commandBusy, isFalse);
    });
  });

  group('polling invariants', () {
    test('a poll completing after disposal settles silently', () async {
      final client = _FakeRecorderClient();
      final container = ProviderContainer(
        overrides: [
          interactionRecorderConnectorProvider.overrideWithValue(
            (key) async => client,
          ),
        ],
      );
      final notifier = container.read(interactionRecorderProvider.notifier);
      notifier.select(_key);
      await pumpEventQueue();

      // The page closes while a status read is still open: the late read
      // must not write to the disposed provider (no unhandled exception).
      client.statusGate = Completer<void>();
      final inFlight = notifier.poll();
      container.dispose();
      client.setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'r1',
        stepCount: 1,
      );
      client.recordedSteps = [_step('s1')];
      client.statusGate!.complete();
      await inFlight;
      await pumpEventQueue();
      expect(client.stepCursors, <int>[0]); // The drain never ran.
    });

    test(
      'polls never overlap: concurrent polls perform one status read',
      () async {
        final (container, client) = _container();
        final notifier = container.read(interactionRecorderProvider.notifier);
        notifier.select(_key);
        await pumpEventQueue();
        expect(client.statusCalls, 1); // The connect poll.

        client.statusGate = Completer<void>();
        final first = notifier.poll();
        final second = notifier.poll();
        await pumpEventQueue();
        expect(client.statusCalls, 2); // The gated read, nothing more.

        client.statusGate!.complete();
        await first;
        await second;
        expect(client.statusCalls, 2); // The second call was skipped, not run.
        expect(client.stepCursors, hasLength(2)); // Idle + one drained.
      },
    );

    test(
      'a shrinking total under the same session id does not restart the timeline',
      () async {
        final (container, client) = _container();
        final notifier = container.read(interactionRecorderProvider.notifier);
        notifier.select(_key);
        await pumpEventQueue();

        client
          ..setSession(
            phase: CockpitRecorderPhase.recording,
            sessionId: 'r1',
            stepCount: 2,
          )
          ..recordedSteps = [_step('s1'), _step('s2')];
        await notifier.poll();
        expect(container.read(interactionRecorderProvider).steps, hasLength(2));

        // Same session id, server total shrinks below the cursor: the page
        // keeps the consumed timeline; only the cursor follows the total.
        client.recordedSteps = [_step('s1')];
        await notifier.poll();
        var state = container.read(interactionRecorderProvider);
        expect(state.sessionId, 'r1');
        expect(state.steps.map((step) => step.stepId), <String>['s1', 's2']);
        // The next drain resumes from the shrunken total (cursor 1).
        await notifier.poll();
        state = container.read(interactionRecorderProvider);
        expect(client.stepCursors.last, 1);
        expect(state.steps.map((step) => step.stepId), <String>['s1', 's2']);

        // A new session id still restarts even when its total is smaller.
        client
          ..setSession(
            phase: CockpitRecorderPhase.recording,
            sessionId: 'r2',
            stepCount: 1,
          )
          ..recordedSteps = [_step('n1')];
        await notifier.poll();
        expect(
          container
              .read(interactionRecorderProvider)
              .steps
              .map((step) => step.stepId),
          <String>['n1'],
        );
      },
    );

    test(
      'an idle status after a session clears counts, keeps the timeline',
      () async {
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
        var state = container.read(interactionRecorderProvider);
        expect(state.canExport, isTrue);

        client.statusPayload = <String, Object?>{'phase': 'idle'};
        await notifier.poll();
        state = container.read(interactionRecorderProvider);
        expect(state.phase, CockpitRecorderPhase.idle);
        expect(state.sessionId, isNull);
        expect(state.stepCount, 0);
        expect(state.unresolvedCount, 0);
        expect(state.steps, hasLength(2)); // History stays reviewable.
        expect(state.canExport, isFalse);
      },
    );
  });

  group('malformed payloads surface as errors, not crashes', () {
    test(
      'a step that fails to decode reports an error and keeps the timeline',
      () async {
        final (container, client) = _container();
        final notifier = container.read(interactionRecorderProvider.notifier);
        notifier.select(_key);
        await pumpEventQueue();

        client
          ..setSession(
            phase: CockpitRecorderPhase.recording,
            sessionId: 'r1',
            stepCount: 1,
          )
          ..recordedSteps = [_step('s1')];
        await notifier.poll();
        expect(container.read(interactionRecorderProvider).steps, hasLength(1));

        client.rawStepsOverride = <Object?>[
          <String, Object?>{
            'stepId': 's2',
            'kind': 'teleport', // Unknown step kind.
            'phase': 'recording',
            'recordedAt': DateTime.utc(2026, 10, 7, 9).toIso8601String(),
          },
        ];
        await notifier.poll();
        var state = container.read(interactionRecorderProvider);
        expect(state.connectionError, contains('kind'));
        expect(state.steps.map((step) => step.stepId), <String>['s1']);

        // The cursor never advanced past the malformed step; once the payload
        // is well-formed again the error clears and the drain resumes.
        client.rawStepsOverride = null;
        client.recordedSteps = [_step('s1'), _step('s2')];
        await notifier.poll();
        state = container.read(interactionRecorderProvider);
        expect(state.connectionError, isNull);
        expect(state.steps.map((step) => step.stepId), <String>['s1', 's2']);
      },
    );

    test('an unknown phase in the status reports an error', () async {
      final (container, client) = _container();
      final notifier = container.read(interactionRecorderProvider.notifier);
      notifier.select(_key);
      await pumpEventQueue();

      client.statusPayload = <String, Object?>{
        'sessionId': 'r1',
        'phase': 'warping',
        'stepCount': 3,
      };
      await notifier.poll();
      final state = container.read(interactionRecorderProvider);
      expect(state.connectionError, contains('phase'));
      expect(state.phase, CockpitRecorderPhase.idle); // Last known phase kept.
      expect(state.stepCount, 0);
    });
  });

  group('commands and export while busy', () {
    test('a second command while one is in flight is ignored', () async {
      final (container, client) = _container();
      final notifier = container.read(interactionRecorderProvider.notifier);
      notifier.select(_key);
      await pumpEventQueue();

      client.commandGate = Completer<void>();
      client.setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'r1',
        stepCount: 0,
      );
      final slowStart = notifier.start(name: 'flow');
      await notifier.pause(); // Must be dropped: a command is in flight.
      await pumpEventQueue();
      expect(client.commandLog, <String>['start:flow']);
      expect(container.read(interactionRecorderProvider).commandBusy, isTrue);

      client.commandGate!.complete();
      await slowStart;
      await pumpEventQueue();
      expect(client.commandLog, <String>['start:flow']);
      expect(container.read(interactionRecorderProvider).commandBusy, isFalse);

      // Once idle again the pause goes through.
      await notifier.pause();
      expect(client.commandLog, <String>['start:flow', 'pause']);
    });

    test('commands without a connection are dropped', () async {
      final container = ProviderContainer(
        overrides: [
          interactionRecorderConnectorProvider.overrideWithValue(
            (key) async => throw StateError('bridge unavailable'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(interactionRecorderProvider.notifier);

      notifier.select(_key);
      await pumpEventQueue();
      await notifier.start();
      final state = container.read(interactionRecorderProvider);
      expect(state.commandBusy, isFalse);
      expect(state.commandError, isNull);
    });

    test(
      're-export replaces the preview; concurrent exports collapse',
      () async {
        final (container, client) = _container();
        final notifier = container.read(interactionRecorderProvider.notifier);
        notifier.select(_key);
        await pumpEventQueue();

        client.exportYaml = 'kind: case\nid: recorded-r1\n';
        await notifier.export();
        expect(
          container.read(interactionRecorderProvider).document,
          'kind: case\nid: recorded-r1\n',
        );

        client.exportGate = Completer<void>();
        client.exportYaml = 'kind: case\nid: recorded-r1\nsteps: 2\n';
        final slowExport = notifier.export();
        await notifier.export(); // Must be dropped: an export is in flight.
        await pumpEventQueue();
        expect(client.exportCalls, 2); // First export + the gated re-export.

        client.exportGate!.complete();
        await slowExport;
        await pumpEventQueue();
        expect(
          container.read(interactionRecorderProvider).document,
          'kind: case\nid: recorded-r1\nsteps: 2\n',
        );
      },
    );

    test(
      'export failures surface inline and clear on the next success',
      () async {
        final (container, client) = _container();
        final notifier = container.read(interactionRecorderProvider.notifier);
        notifier.select(_key);
        await pumpEventQueue();

        client.exportFailure = StateError('no recording session');
        await notifier.export();
        var state = container.read(interactionRecorderProvider);
        expect(state.document, isNull);
        expect(state.commandError, contains('no recording session'));
        expect(state.exporting, isFalse);

        client.exportFailure = null;
        await notifier.export();
        state = container.read(interactionRecorderProvider);
        expect(state.commandError, isNull);
        expect(state.document, _caseYaml);
      },
    );

    test('a successful command refreshes the view through one poll', () async {
      final (container, client) = _container();
      final notifier = container.read(interactionRecorderProvider.notifier);
      notifier.select(_key);
      await pumpEventQueue();
      expect(client.statusCalls, 1);

      client.setSession(
        phase: CockpitRecorderPhase.stopped,
        sessionId: 'r1',
        stepCount: 1,
      );
      client.recordedSteps = [_step('s1')];
      await notifier.stop();

      final state = container.read(interactionRecorderProvider);
      expect(state.phase, CockpitRecorderPhase.stopped);
      expect(state.steps, hasLength(1));
      expect(client.statusCalls, 2); // Command poll, no double read.
    });
  });
}

const _key = SessionMonitorKey(workspaceId: 'ws-1', sessionId: 'session-1');
const _keyA = SessionMonitorKey(workspaceId: 'ws-1', sessionId: 'session-a');
const _keyB = SessionMonitorKey(workspaceId: 'ws-1', sessionId: 'session-b');

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

/// In-memory recorder client: scriptable status, drained steps, and
/// optional per-command failures and gates.
final class _FakeRecorderClient implements InteractionRecorderClient {
  Map<String, Object?> _status = <String, Object?>{'phase': 'idle'};

  /// When set, replaces the scripted status payload entirely.
  Map<String, Object?>? statusPayload;

  List<CockpitInteractionStep> recordedSteps = <CockpitInteractionStep>[];

  /// When set, replaces the drained step payloads (already JSON encoded).
  List<Object?>? rawStepsOverride;

  Object? commandFailure;
  Object? exportFailure;

  String exportYaml = _caseYaml;

  /// Held futures that gate each interaction kind for concurrency tests.
  Completer<void>? statusGate;
  Completer<void>? commandGate;
  Completer<void>? exportGate;

  final List<String> commandLog = <String>[];
  final List<int> stepCursors = <int>[];
  int statusCalls = 0;
  int exportCalls = 0;

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
    final gate = commandGate;
    if (gate != null) await gate.future;
    final failure = commandFailure;
    if (failure != null) throw failure;
    return _status;
  }

  @override
  Future<Map<String, Object?>> status() async {
    statusCalls++;
    final gate = statusGate;
    if (gate != null) await gate.future;
    return statusPayload ?? _status;
  }

  @override
  Future<Map<String, Object?>> steps({int after = 0}) async {
    stepCursors.add(after);
    return <String, Object?>{
      'steps':
          rawStepsOverride ??
          <Object?>[
            for (final step in recordedSteps.skip(after)) step.toJson(),
          ],
      'total': recordedSteps.length,
    };
  }

  @override
  Future<String> exportCaseYaml() async {
    exportCalls++;
    final gate = exportGate;
    if (gate != null) await gate.future;
    final failure = exportFailure;
    if (failure != null) throw failure;
    return exportYaml;
  }
}
