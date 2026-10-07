import 'package:cockpit_console/i18n/console_localization.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/app_shell.dart';
import 'package:cockpit_console/src/ui/widgets/interaction_recorder_views.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  setUpAll(initializeConsoleLocalization);
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('InteractionRecorderControls', () {
    testWidgets('buttons follow the phase matrix', (tester) async {
      await _pumpControls(
        tester,
        _state(phase: CockpitRecorderPhase.idle, endpoint: _endpoint),
      );
      // idle: start only.
      expect(_isEnabled(tester, 'Start'), isTrue);
      expect(_isEnabled(tester, 'Pause'), isFalse);
      expect(_isEnabled(tester, 'Resume'), isFalse);
      expect(_isEnabled(tester, 'Stop'), isFalse);
      expect(find.text('Idle · 0 steps · 0 unresolved'), findsOneWidget);
      expect(find.text('Name (optional)'), findsOneWidget);

      await _pumpControls(
        tester,
        _state(
          phase: CockpitRecorderPhase.recording,
          stepCount: 3,
          endpoint: _endpoint,
        ),
      );
      // recording: pause + stop.
      expect(_isEnabled(tester, 'Start'), isFalse);
      expect(_isEnabled(tester, 'Pause'), isTrue);
      expect(_isEnabled(tester, 'Resume'), isFalse);
      expect(_isEnabled(tester, 'Stop'), isTrue);
      expect(find.text('Recording · 3 steps · 0 unresolved'), findsOneWidget);
      expect(find.text('Name (optional)'), findsNothing);

      await _pumpControls(
        tester,
        _state(
          phase: CockpitRecorderPhase.paused,
          unresolvedCount: 2,
          endpoint: _endpoint,
        ),
      );
      // paused: resume + stop.
      expect(_isEnabled(tester, 'Start'), isFalse);
      expect(_isEnabled(tester, 'Pause'), isFalse);
      expect(_isEnabled(tester, 'Resume'), isTrue);
      expect(_isEnabled(tester, 'Stop'), isTrue);

      await _pumpControls(
        tester,
        _state(phase: CockpitRecorderPhase.stopped, endpoint: _endpoint),
      );
      // stopped: start again.
      expect(_isEnabled(tester, 'Start'), isTrue);
      expect(_isEnabled(tester, 'Stop'), isFalse);
    });

    testWidgets('commands stay disabled without an endpoint or mid-command', (
      tester,
    ) async {
      await _pumpControls(
        tester,
        _state(phase: CockpitRecorderPhase.recording, endpoint: null),
      );
      expect(_isEnabled(tester, 'Pause'), isFalse);
      expect(_isEnabled(tester, 'Stop'), isFalse);

      await _pumpControls(
        tester,
        _state(
          phase: CockpitRecorderPhase.recording,
          commandBusy: true,
          endpoint: _endpoint,
        ),
      );
      expect(_isEnabled(tester, 'Pause'), isFalse);
      expect(_isEnabled(tester, 'Stop'), isFalse);
    });

    testWidgets('start relays the trimmed name and errors render inline', (
      tester,
    ) async {
      String? startedName;
      await _pumpControls(
        tester,
        _state(
          phase: CockpitRecorderPhase.idle,
          endpoint: _endpoint,
          commandError: 'Cannot start while stopped.',
        ),
        onStart: (name) => startedName = name,
      );

      expect(find.text('Cannot start while stopped.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  login flow  ');
      await tester.tap(find.text('Start'));
      expect(startedName, 'login flow');
    });
  });

  group('InteractionRecorderTimeline', () {
    testWidgets('rows show kind, locator, annotation, and settle badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 300,
            child: InteractionRecorderTimeline(
              steps: <CockpitInteractionStep>[
                CockpitInteractionStep(
                  stepId: 's1',
                  kind: CockpitInteractionStepKind.tap,
                  locatorCandidates: <CockpitLocatorCandidate>[
                    CockpitLocatorCandidate(
                      kind: 'key',
                      selector: 'key:submit',
                      score: 4,
                    ),
                  ],
                  phase: CockpitRecorderPhase.recording,
                  annotation: 'primary submit button',
                  settledAfterMs: 320,
                  recordedAt: DateTime.utc(2026, 10, 7, 9),
                ),
                CockpitInteractionStep(
                  stepId: 's2',
                  kind: CockpitInteractionStepKind.tap,
                  unresolved: true,
                  phase: CockpitRecorderPhase.recording,
                  recordedAt: DateTime.utc(2026, 10, 7, 9, 0, 1),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tap'), findsNWidgets(2));
      expect(find.text('key:submit'), findsOneWidget);
      expect(find.text('(unresolved)'), findsOneWidget);
      expect(find.text('primary submit button'), findsOneWidget);
      expect(find.text('settled · 320 ms'), findsOneWidget);
      expect(find.text('s1'), findsOneWidget);
    });

    testWidgets('an empty timeline explains itself', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            height: 300,
            child: InteractionRecorderTimeline(
              steps: <CockpitInteractionStep>[],
            ),
          ),
        ),
      );

      expect(
        find.text('Recorded interactions appear here while the app is used.'),
        findsOneWidget,
      );
    });
  });

  group('InteractionRecorderExportPane', () {
    testWidgets('export needs a session; the preview shows the case YAML', (
      tester,
    ) async {
      var exportTaps = 0;
      await _pumpExport(tester, document: null, canExport: false);
      expect(_isEnabled(tester, 'Export'), isFalse);
      expect(
        find.text('Start a recording, then export its case YAML.'),
        findsOneWidget,
      );

      await _pumpExport(
        tester,
        document: 'kind: case\nid: recorded-r1\n',
        canExport: true,
        onExport: () => exportTaps++,
      );
      expect(_isEnabled(tester, 'Export'), isTrue);
      expect(find.textContaining('kind: case'), findsOneWidget);
      expect(_isEnabled(tester, 'Save'), isTrue);

      await tester.tap(find.text('Export'));
      expect(exportTaps, 1);
    });

    testWidgets('copy writes the case YAML to the clipboard', (tester) async {
      // flutter_test ships no clipboard; without a mock the platform message
      // never replies and the test hangs.
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
            case 'Clipboard.getData':
              return <String, Object?>{'text': clipboardText};
          }
          return null;
        },
      );

      const yaml = 'kind: case\nid: recorded-r1\n';
      await _pumpExport(tester, document: yaml, canExport: true);

      await tester.tap(find.text('Copy YAML'));
      await tester.pump();

      expect(clipboardText, yaml);
      expect(find.text('YAML copied'), findsOneWidget);
    });
  });

  group('registration and localization', () {
    testWidgets('the recorder page is reachable from the shell navigation', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            child: MaterialApp(
              theme: ConsoleTheme.build(Brightness.dark),
              home: const AppShell(),
            ),
          ),
        ),
      );

      expect(find.text('Recorder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('Simplified Chinese covers the recorder strings', () async {
      await LocaleSettings.setLocale(AppLocale.zhCn);
      addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

      expect(t.nav.recorder, '录制');
      expect(t.recorder.title, '交互录制');
      expect(
        t.recorder.statusLine(phase: '录制中', steps: '2 步', unresolved: '1 个未解析'),
        '录制中 · 2 步 · 1 个未解析',
      );
      expect(t.recorder.unresolvedStep, '（未解析）');
    });
  });
}

InteractionRecorderState _state({
  required CockpitRecorderPhase phase,
  Uri? endpoint,
  int stepCount = 0,
  int unresolvedCount = 0,
  bool commandBusy = false,
  String? commandError,
}) => InteractionRecorderState(
  endpoint: endpoint,
  phase: phase,
  stepCount: stepCount,
  unresolvedCount: unresolvedCount,
  commandBusy: commandBusy,
  commandError: commandError,
  sessionId: phase == CockpitRecorderPhase.idle ? null : 'r1',
);

final _endpoint = Uri.parse('http://127.0.0.1:18434');

Future<void> _pumpControls(
  WidgetTester tester,
  InteractionRecorderState state, {
  ValueChanged<String?>? onStart,
}) async {
  await tester.pumpWidget(
    _wrap(
      InteractionRecorderControls(
        state: state,
        onStart: onStart ?? (_) {},
        onPause: () {},
        onResume: () {},
        onStop: () {},
      ),
    ),
  );
}

Future<void> _pumpExport(
  WidgetTester tester, {
  required String? document,
  required bool canExport,
  VoidCallback? onExport,
}) async {
  await tester.pumpWidget(
    _wrap(
      SizedBox(
        width: 380,
        height: 400,
        child: InteractionRecorderExportPane(
          document: document,
          canExport: canExport,
          exporting: false,
          fileName: 'recorded-r1.yaml',
          onExport: onExport ?? () {},
        ),
      ),
    ),
  );
}

Widget _wrap(Widget child) => TranslationProvider(
  child: MaterialApp(
    theme: ConsoleTheme.build(Brightness.light),
    home: Scaffold(body: child),
  ),
);

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
