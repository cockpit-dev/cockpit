import 'dart:async';

import 'package:cockpit_console/i18n/console_localization.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/providers/session_monitor_provider.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/screens/recorder_screen.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  setUpAll(initializeConsoleLocalization);
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('without live sessions the page explains itself and still runs', (
    tester,
  ) async {
    final harness = _RecorderHarness(sessions: const <MonitoredSession>[]);
    await harness.pump(tester);
    await tester.pump();

    expect(find.text('No live sessions'), findsOneWidget);
    expect(
      find.text(
        'Start an app with Cockpit, then record its interactions here.',
      ),
      findsOneWidget,
    );
    expect(find.text('Interaction recorder'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget); // Phase badge.
    expect(harness.monitor.startCalls, 1); // Lifecycle still started.

    await harness.disposeScreen(tester);
  });

  testWidgets('adopts the monitor selection and resolves its endpoint', (
    tester,
  ) async {
    final harness = _RecorderHarness()
      ..clients[_keyA]!.setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'rA',
        stepCount: 1,
        unresolvedCount: 1,
      );
    await harness.pump(tester);
    await tester.pump();
    await tester.pump();

    final state = harness.container.read(interactionRecorderProvider);
    expect(state.selected, _keyA);
    expect(state.endpoint, harness.clients[_keyA]!.baseUri);
    expect(find.text('Recheck'), findsOneWidget); // Connected affordance.
    expect(find.text('Recording'), findsOneWidget); // Phase badge.
    expect(find.text('Recording · 1 step · 1 unresolved'), findsOneWidget);

    await harness.disposeScreen(tester);
  });

  testWidgets('the phase badge follows the recorder phase', (tester) async {
    final harness = _RecorderHarness()
      ..clients[_keyA]!.setSession(
        phase: CockpitRecorderPhase.paused,
        sessionId: 'rA',
        stepCount: 0,
      );
    await harness.pump(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);

    // The periodic poll notices the phase change on its own.
    harness.clients[_keyA]!.setSession(
      phase: CockpitRecorderPhase.stopped,
      sessionId: 'rA',
      stepCount: 0,
    );
    await tester.pump(interactionRecorderPollInterval);
    expect(find.text('Stopped'), findsOneWidget);

    await harness.disposeScreen(tester);
  });

  testWidgets(
    'a monitor selection change is adopted only until something is bound',
    (tester) async {
      // Nothing selected yet: the page has nothing to adopt.
      final harness = _RecorderHarness(selected: null);
      await harness.pump(tester);
      await tester.pump();
      await tester.pump();
      expect(
        harness.container.read(interactionRecorderProvider).selected,
        isNull,
      );

      // The monitor picks: the page follows.
      harness.monitor.selectSession(_keyB);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        harness.container.read(interactionRecorderProvider).selected,
        _keyB,
      );

      // The monitor moves on: the page keeps its bound session.
      harness.monitor.selectSession(_keyA);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        harness.container.read(interactionRecorderProvider).selected,
        _keyB,
      );

      await harness.disposeScreen(tester);
    },
  );

  testWidgets('picking a session in the picker rebinds the recorder', (
    tester,
  ) async {
    final harness = _RecorderHarness();
    await harness.pump(tester);
    await tester.pump();
    await tester.pump();
    expect(harness.connectorCalls(_keyA), 1);
    expect(harness.connectorCalls(_keyB), 0);

    await tester.tap(find.text('beta'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final state = harness.container.read(interactionRecorderProvider);
    expect(state.selected, _keyB);
    expect(state.endpoint, harness.clients[_keyB]!.baseUri);
    expect(harness.connectorCalls(_keyB), 1);
    expect(find.text('Recheck'), findsOneWidget);

    await harness.disposeScreen(tester);
  });

  testWidgets(
    'the connect affordance re-resolves and blocks while connecting',
    (tester) async {
      final harness = _RecorderHarness();
      await harness.pump(tester);
      await tester.pump();
      await tester.pump();
      expect(harness.connectorCalls(_keyA), 1);

      // A slow re-resolve disables the affordance until it settles.
      harness.gate = Completer<void>();
      await tester.tap(find.text('Recheck'));
      await tester.pump();
      expect(_isEnabled(tester, 'Recheck'), isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      harness.gate!.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(harness.connectorCalls(_keyA), 2);
      expect(_isEnabled(tester, 'Recheck'), isTrue);

      await harness.disposeScreen(tester);
    },
  );

  testWidgets(
    'polling starts with the page and stops when it leaves the tree',
    (tester) async {
      final harness = _RecorderHarness();
      await harness.pump(tester);
      await tester.pump();
      await tester.pump();
      final client = harness.clients[_keyA]!;
      expect(client.stepCursors, <int>[0]); // Connect polled once.

      // Leave the page: the poll timer dies with it.
      final drainsBeforeClose = client.stepCursors.length;
      await harness.disposeScreen(tester);
      client.recordedSteps = [_step('s1')];
      await tester.pump(const Duration(seconds: 30));
      expect(client.stepCursors, hasLength(drainsBeforeClose));
      expect(harness.monitor.stopCalls, 1);
    },
  );

  testWidgets('wide layout renders the timeline beside the export pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = _RecorderHarness();
    await harness.pump(tester);
    await tester.pump();
    await tester.pump();

    harness.clients[_keyA]!
      ..setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'rA',
        stepCount: 1,
      )
      ..recordedSteps = [_step('s1')];
    await tester.pump(interactionRecorderPollInterval);

    expect(find.byType(VerticalDivider), findsOneWidget); // Side by side.
    expect(find.text('key:s1'), findsOneWidget); // Timeline row.
    expect(find.text('Export preview'), findsOneWidget);
    expect(
      find.text('Start a recording, then export its case YAML.'),
      findsOneWidget,
    );

    await harness.disposeScreen(tester);
  });

  testWidgets('commands and export run against the bound session', (
    tester,
  ) async {
    // A tall surface keeps the stacked export pane on screen while tapping.
    await tester.binding.setSurfaceSize(const Size(700, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = _RecorderHarness()
      ..clients[_keyA]!.setSession(
        phase: CockpitRecorderPhase.idle,
        sessionId: 'rA',
        stepCount: 0,
      );
    await harness.pump(tester);
    await tester.pump();
    await tester.pump();
    final client = harness.clients[_keyA]!;

    // Start passes the typed name along.
    await tester.enterText(find.byType(TextField), 'checkout');
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.commands, <(String, String?)>[('start', 'checkout')]);

    // Each phase enables exactly its follow-up command.
    client
      ..setSession(
        phase: CockpitRecorderPhase.recording,
        sessionId: 'rA',
        stepCount: 1,
      )
      ..recordedSteps = [_step('s1')];
    await tester.pump(interactionRecorderPollInterval);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(client.commands.last, ('pause', null));

    client.setSession(
      phase: CockpitRecorderPhase.paused,
      sessionId: 'rA',
      stepCount: 1,
    );
    await tester.pump(interactionRecorderPollInterval);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(client.commands.last, ('resume', null));

    client.setSession(
      phase: CockpitRecorderPhase.recording,
      sessionId: 'rA',
      stepCount: 1,
    );
    await tester.pump(interactionRecorderPollInterval);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(client.commands.last, ('stop', null));
    expect(find.text('key:s1'), findsOneWidget); // Timeline followed along.

    // Export previews the bound session's case YAML.
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('kind: case'), findsOneWidget);

    await harness.disposeScreen(tester);
  });

  testWidgets('narrow layout stacks the timeline above the export pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = _RecorderHarness();
    await harness.pump(tester);
    await tester.pump();
    await tester.pump();

    expect(find.byType(VerticalDivider), findsNothing); // Stacked.
    expect(
      find.text('Recorded interactions appear here while the app is used.'),
      findsOneWidget,
    );
    expect(find.text('Export preview'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);

    await harness.disposeScreen(tester);
  });
}

const _keyA = SessionMonitorKey(workspaceId: 'ws-1', sessionId: 'session-a');
const _keyB = SessionMonitorKey(workspaceId: 'ws-1', sessionId: 'session-b');

bool _isEnabled(WidgetTester tester, String label) =>
    tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          ),
        )
        .onPressed !=
    null;

CockpitInteractionStep _step(String id) => CockpitInteractionStep(
  stepId: id,
  kind: CockpitInteractionStepKind.tap,
  locatorCandidates: <CockpitLocatorCandidate>[
    CockpitLocatorCandidate(kind: 'key', selector: 'key:$id', score: 4),
  ],
  phase: CockpitRecorderPhase.recording,
  recordedAt: DateTime.utc(2026, 10, 7, 9),
);

MonitoredSession _session({
  required SessionMonitorKey key,
  required String project,
  String platform = 'macos',
}) => MonitoredSession(
  key: key,
  projectPath: '/workspace/$project',
  projectName: project,
  targetId: 'target-${key.sessionId}',
  platform: platform,
  deviceId: 'device-$platform',
  targetKind: CockpitTargetKind.flutterApp,
  entrypoint: 'cockpit/main.dart',
  flavor: null,
  appId: 'app-${key.sessionId}',
  state: 'ready',
  lastSeenAt: DateTime.utc(2026, 10, 7, 9),
  route: '/',
  appReachable: true,
  bridgeReachable: true,
);

/// Wires the recorder screen against a scriptable monitor and recorder
/// clients, mirroring the production provider graph.
final class _RecorderHarness {
  _RecorderHarness({
    List<MonitoredSession>? sessions,
    SessionMonitorKey? selected = _keyA,
  }) : monitor = _FakeMonitorNotifier(
         SessionMonitorState(
           sessions:
               sessions ??
               <MonitoredSession>[
                 _session(key: _keyA, project: 'alpha'),
                 _session(key: _keyB, project: 'beta'),
               ],
           selected: selected,
         ),
       ) {
    container = ProviderContainer(
      overrides: [
        sessionMonitorProvider.overrideWith(() => monitor),
        interactionRecorderConnectorProvider.overrideWithValue((key) async {
          _connectorCalls[key] = (_connectorCalls[key] ?? 0) + 1;
          final gate = this.gate;
          if (gate != null) await gate.future;
          return clients[key]!;
        }),
      ],
    );
    addTearDown(container.dispose);
  }

  final _FakeMonitorNotifier monitor;
  late final ProviderContainer container;

  final Map<SessionMonitorKey, _ScreenRecorderClient> clients = {
    _keyA: _ScreenRecorderClient(Uri.parse('http://127.0.0.1:18441')),
    _keyB: _ScreenRecorderClient(Uri.parse('http://127.0.0.1:18442')),
  };

  final Map<SessionMonitorKey, int> _connectorCalls = {};

  /// When set, the next connector invocation waits for it.
  Completer<void>? gate;

  int connectorCalls(SessionMonitorKey key) => _connectorCalls[key] ?? 0;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ConsoleTheme.build(Brightness.dark),
            home: const Scaffold(body: RecorderScreen()),
          ),
        ),
      ),
    );
  }

  Future<void> disposeScreen(WidgetTester tester) => tester.pumpWidget(
    TranslationProvider(
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.dark),
          home: const Scaffold(),
        ),
      ),
    ),
  );
}

final class _FakeMonitorNotifier extends SessionMonitorNotifier {
  _FakeMonitorNotifier(this._initial);

  final SessionMonitorState _initial;

  int startCalls = 0;
  int stopCalls = 0;

  @override
  SessionMonitorState build() => _initial;

  @override
  void start() => startCalls++;

  @override
  void stop() => stopCalls++;

  void selectSession(SessionMonitorKey key) {
    state = state.copyWith(selected: key);
  }
}

final class _ScreenRecorderClient implements InteractionRecorderClient {
  _ScreenRecorderClient(this.baseUri);

  @override
  final Uri baseUri;

  Map<String, Object?> _status = <String, Object?>{'phase': 'idle'};

  List<CockpitInteractionStep> recordedSteps = <CockpitInteractionStep>[];

  final List<(String, String?)> commands = <(String, String?)>[];

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
  Future<Map<String, Object?>> start({String? name}) async {
    commands.add(('start', name));
    return _status;
  }

  @override
  Future<Map<String, Object?>> pause() async {
    commands.add(('pause', null));
    return _status;
  }

  @override
  Future<Map<String, Object?>> resume() async {
    commands.add(('resume', null));
    return _status;
  }

  @override
  Future<Map<String, Object?>> stop() async {
    commands.add(('stop', null));
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
  Future<String> exportCaseYaml() async => 'kind: case\nid: recorded-r1\n';
}
