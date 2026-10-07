import 'dart:io';

import 'package:cockpit_console/i18n/console_localization.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/app_shell.dart';
import 'package:cockpit_console/src/ui/widgets/interaction_recorder_views.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:file_picker/file_picker.dart';
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

  group('InteractionRecorderControls status line', () {
    testWidgets('connection errors render inline next to command errors', (
      tester,
    ) async {
      await _pumpControls(
        tester,
        _state(
          phase: CockpitRecorderPhase.idle,
          endpoint: null,
          connectionError: 'Bad state: bridge unavailable',
        ),
      );

      expect(find.text('Bad state: bridge unavailable'), findsOneWidget);
      expect(find.text('Idle · 0 steps · 0 unresolved'), findsOneWidget);
    });

    testWidgets('the status line uses singular forms for one step', (
      tester,
    ) async {
      await _pumpControls(
        tester,
        _state(
          phase: CockpitRecorderPhase.recording,
          stepCount: 1,
          unresolvedCount: 1,
          endpoint: _endpoint,
        ),
      );

      expect(find.text('Recording · 1 step · 1 unresolved'), findsOneWidget);
    });
  });

  group('InteractionRecorderTimeline kinds', () {
    testWidgets('every step kind gets its badge', (tester) async {
      final kinds = <CockpitInteractionStepKind, String>{
        CockpitInteractionStepKind.tap: 'Tap',
        CockpitInteractionStepKind.longPress: 'Long press',
        CockpitInteractionStepKind.text: 'Text',
        CockpitInteractionStepKind.scroll: 'Scroll',
        CockpitInteractionStepKind.routeChange: 'Route change',
        CockpitInteractionStepKind.back: 'Back',
        CockpitInteractionStepKind.marker: 'Marker',
        CockpitInteractionStepKind.note: 'Note',
      };
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 600,
            child: InteractionRecorderTimeline(
              steps: <CockpitInteractionStep>[
                for (final entry in kinds.entries)
                  CockpitInteractionStep(
                    stepId: 's${entry.key.name}',
                    kind: entry.key,
                    locatorCandidates: <CockpitLocatorCandidate>[
                      CockpitLocatorCandidate(
                        kind: 'key',
                        selector: 'key:${entry.key.name}',
                        score: 4,
                      ),
                    ],
                    phase: CockpitRecorderPhase.recording,
                    segments: const <String>['checkout'],
                    recordedAt: DateTime.utc(2026, 10, 7, 9),
                  ),
              ],
            ),
          ),
        ),
      );

      for (final label in kinds.values) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('InteractionRecorderTimeline auto-follow', () {
    testWidgets(
      'appending steps keeps the newest visible, even after scrolling up',
      (tester) async {
        await _pumpTimeline(tester, 20);
        final controller = _timelineController(tester);
        expect(controller.position.pixels, 0); // First paint stays at top.
        expect(controller.position.maxScrollExtent, greaterThan(0));

        // Growth auto-scrolls to the newest step; the lazily built list
        // settles its extent over two frames.
        await _pumpTimeline(tester, 30);
        await tester.pump();
        await tester.pump();
        expect(controller.position.pixels, controller.position.maxScrollExtent);

        // The user scrolls back up to inspect history…
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pump();
        expect(
          controller.position.pixels,
          lessThan(controller.position.maxScrollExtent),
        );

        // …a new step still force-follows to the bottom.
        await _pumpTimeline(tester, 40);
        await tester.pump();
        await tester.pump();
        expect(controller.position.pixels, controller.position.maxScrollExtent);
      },
    );

    testWidgets('a timeline restart (shrink) does not jump', (tester) async {
      await _pumpTimeline(tester, 30);
      await _pumpTimeline(tester, 40);
      await tester.pump();
      await tester.pump();
      final controller = _timelineController(tester);
      expect(controller.position.pixels, controller.position.maxScrollExtent);

      // A new recording session restarts the list with fewer steps; the
      // viewport stays where the user is instead of jumping.
      await _pumpTimeline(tester, 5);
      await tester.pump();
      await tester.pump();
      expect(controller.position.pixels, controller.position.maxScrollExtent);
      expect(find.text('key:s4'), findsOneWidget);
      expect(find.text('key:s39'), findsNothing);
    });
  });

  group('InteractionRecorderExportPane save', () {
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

    setUp(FilePickerMacOS.registerWith);

    testWidgets('saving writes the document and confirms', (tester) async {
      final destination = Directory.systemTemp.createTempSync('recorder_save');
      addTearDown(() => destination.deleteSync(recursive: true));
      final path = '${destination.path}/recorded-r1.yaml';
      final calls = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        _saveDialogHandler(calls, destination: path),
      );

      await _pumpExport(
        tester,
        document: 'kind: case\nid: recorded-r1\n',
        canExport: true,
      );
      // Real file I/O: settle the write in a real async zone, then show the
      // snackbar in the fake zone.
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      expect(File(path).readAsStringSync(), 'kind: case\nid: recorded-r1\n\n');
      expect(calls.single['fileName'], 'recorded-r1.yaml');
      expect(find.text('Saved $path'), findsOneWidget);
    });

    testWidgets('cancelling the dialog writes nothing and stays quiet', (
      tester,
    ) async {
      final calls = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        _saveDialogHandler(calls, destination: null),
      );

      await _pumpExport(tester, document: 'kind: case\n', canExport: true);
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();

      expect(calls, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed write surfaces the error', (tester) async {
      const path = '/nonexistent-recorder-dir/recorded-r1.yaml';
      final calls = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        _saveDialogHandler(calls, destination: path),
      );

      await _pumpExport(tester, document: 'kind: case\n', canExport: true);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Could not save:'), findsOneWidget);
    });

    testWidgets('copy failure flips the button to a failure label', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard-unavailable');
          }
          return null;
        },
      );

      await _pumpExport(tester, document: 'kind: case\n', canExport: true);
      await tester.tap(find.text('Copy YAML'));
      await tester.pump();

      expect(find.text('Could not copy'), findsOneWidget);
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
      expect(t.recorder.settledAfter(ms: 320), '已稳定 · 320 毫秒');
      expect(t.recorder.saveDocument, '保存用例文档');
      expect(t.recorder.documentSaved(path: '/tmp/a.yaml'), '已保存到 /tmp/a.yaml');
      expect(t.recorder.saveFailed(error: 'boom'), '保存失败：boom');
      expect(t.recorder.kind.routeChange, '路由切换');
      expect(t.recorder.phase.stopped, '已停止');
      expect(t.recorder.noSessionsTitle, '没有实时会话');
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
  String? connectionError,
}) => InteractionRecorderState(
  endpoint: endpoint,
  phase: phase,
  stepCount: stepCount,
  unresolvedCount: unresolvedCount,
  commandBusy: commandBusy,
  commandError: commandError,
  connectionError: connectionError,
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

ScrollController _timelineController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

List<CockpitInteractionStep> _timelineSteps(int count) =>
    <CockpitInteractionStep>[
      for (var i = 0; i < count; i++)
        CockpitInteractionStep(
          stepId: 's$i',
          kind: CockpitInteractionStepKind.tap,
          locatorCandidates: <CockpitLocatorCandidate>[
            CockpitLocatorCandidate(kind: 'key', selector: 'key:s$i', score: 4),
          ],
          phase: CockpitRecorderPhase.recording,
          recordedAt: DateTime.utc(2026, 10, 7, 9),
        ),
    ];

Future<void> _pumpTimeline(WidgetTester tester, int count) => tester.pumpWidget(
  _wrap(
    SizedBox(
      height: 300,
      child: InteractionRecorderTimeline(steps: _timelineSteps(count)),
    ),
  ),
);

Future<Object?> Function(MethodCall) _saveDialogHandler(
  List<Map<Object?, Object?>> calls, {
  required Object? destination,
}) => (call) async {
  if (call.method == 'saveFile') {
    calls.add(Map<Object?, Object?>.from(call.arguments as Map));
    return destination;
  }
  return null;
};

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
