import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/recorder/ui/cockpit_recorder_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('header', () {
    testWidgets('shows the phase badge and live counters', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      expect(find.text('COCKPIT RECORDER'), findsOneWidget);
      expect(find.text('RECORDING'), findsOneWidget);
      expect(find.text('0 steps · 0 unresolved'), findsOneWidget);

      controller.recorder.recordInteractionStep(
        unresolvedStep(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      expect(find.text('1 steps · 1 unresolved'), findsOneWidget);
    });

    testWidgets('embedded panels render no close button', (tester) async {
      await pumpPanel(tester);
      expect(find.text('✕'), findsNothing);
    });
  });

  group('control area', () {
    testWidgets('shows only the current phase primary buttons', (tester) async {
      final controller = await pumpPanel(tester);

      // idle: start with the name field beside it.
      expect(isButtonEnabled(tester, 'Start'), isTrue);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('no session'), findsOneWidget);

      controller.start();
      await tester.pump();

      // recording: pause + stop.
      expect(find.text('Start'), findsNothing);
      expect(isButtonEnabled(tester, 'Pause'), isTrue);
      expect(find.text('Resume'), findsNothing);
      expect(isButtonEnabled(tester, 'Stop'), isTrue);

      controller.pause();
      await tester.pump();

      // paused: resume + stop.
      expect(find.text('Pause'), findsNothing);
      expect(isButtonEnabled(tester, 'Resume'), isTrue);
      expect(isButtonEnabled(tester, 'Stop'), isTrue);

      controller.resume();
      controller.stop();
      await tester.pump();

      // stopped: start again.
      expect(isButtonEnabled(tester, 'Start'), isTrue);
      expect(find.text('Stop'), findsNothing);
    });

    testWidgets('the name field feeds the session name', (tester) async {
      final controller = await pumpPanel(tester);

      await tester.enterText(find.byType(EditableText), 'login flow');
      tester.widget<EditableText>(find.byType(EditableText)).onSubmitted!(
        'login flow',
      );
      await tester.pump();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      controller.exportBundle();

      expect(controller.lastBundle!.caseDocument['name'], 'login flow');
      // Starting switched the row to recording controls; the name field is
      // gone and took its text with it.
      expect(find.text('login flow'), findsNothing);
    });

    testWidgets('tapping Start reads the name field', (tester) async {
      final controller = await pumpPanel(tester);

      await tester.enterText(find.byType(EditableText), 'checkout flow');
      await tester.tap(find.text('Start'));
      await tester.pump();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      controller.exportBundle();

      expect(controller.lastBundle!.caseDocument['name'], 'checkout flow');
    });

    testWidgets('an empty name starts an unnamed session', (tester) async {
      final controller = await pumpPanel(tester);

      await tester.enterText(find.byType(EditableText), '   ');
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(controller.phase, CockpitRecorderPhase.recording);
    });

    testWidgets('segment begin and end update open chips', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'setup');
      await tester.tap(find.text('Begin segment'));
      await tester.pump();

      expect(controller.openSegments, <String>['setup']);
      expect(find.text('setup'), findsOneWidget);
      expect(isButtonEnabled(tester, 'End segment'), isTrue);

      await tester.tap(find.text('End segment'));
      await tester.pump();

      expect(controller.openSegments, isEmpty);
      expect(isButtonEnabled(tester, 'End segment'), isFalse);
    });

    testWidgets('submitting the segment field begins the segment', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'via-keyboard');
      // Drive the field's submit wiring (what a keyboard done action fires).
      tester.widget<EditableText>(find.byType(EditableText)).onSubmitted!(
        'via-keyboard',
      );
      await tester.pump();

      expect(controller.openSegments, <String>['via-keyboard']);
      // The field cleared itself after submitting.
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, isEmpty);
    });

    testWidgets('illegal commands surface inline errors', (tester) async {
      final controller = await pumpPanel(tester);

      // No session yet: tapping disabled buttons is impossible, but the
      // controller-level failure path is visible when a command races a
      // phase change — drive one directly.
      controller.pause();
      await tester.pump();

      expect(find.textContaining('Cannot pause'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(find.textContaining('Cannot pause'), findsNothing);
    });
  });

  group('timeline area', () {
    testWidgets('renders locator summary and unresolved marker', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      controller.recorder.recordInteractionStep(
        unresolvedStep(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('s1')), findsOneWidget);
      expect(find.text('@save'), findsOneWidget);
      expect(find.text('(unresolved)'), findsOneWidget);
      expect(find.text('No steps recorded yet.'), findsNothing);
    });

    testWidgets('delete appears on the last row only', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      final lastRow = find.byKey(const ValueKey<String>('s2'));
      final earlierRow = find.byKey(const ValueKey<String>('s1'));
      expect(isRowButtonEnabled(tester, lastRow, 'Delete'), isTrue);
      expect(
        find.descendant(of: earlierRow, matching: find.text('Delete')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(of: lastRow, matching: find.text('Delete')),
      );
      await tester.pump();

      expect(controller.steps.map((step) => step.stepId), <String>['s1']);
    });

    testWidgets('annotate flow updates the row', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      final row = find.byKey(const ValueKey<String>('s1'));
      await tester.tap(
        find.descendant(of: row, matching: find.text('Annotate')),
      );
      await tester.pump();

      await tester.enterText(
        find.descendant(of: row, matching: find.byType(EditableText)),
        'first tap',
      );
      await tester.tap(find.descendant(of: row, matching: find.text('Save')));
      await tester.pump();

      expect(controller.steps.single.annotation, 'first tap');
      expect(find.text('note: first tap'), findsOneWidget);
    });

    testWidgets('toggling annotate closed drops the inline editor', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      final row = find.byKey(const ValueKey<String>('s1'));
      final annotateButton = find.descendant(
        of: row,
        matching: find.text('Annotate'),
      );
      await tester.tap(annotateButton);
      await tester.pump();
      expect(
        find.descendant(of: row, matching: find.byType(EditableText)),
        findsOneWidget,
      );

      // Tapping Annotate while open closes the editor without saving.
      await tester.tap(annotateButton);
      await tester.pump();

      expect(
        find.descendant(of: row, matching: find.byType(EditableText)),
        findsNothing,
      );
      expect(controller.steps.single.annotation, isNull);
    });

    testWidgets('rows show settle markers and open segments', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.beginSegment('checkout');
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      controller.recorder.markStepSettled('s1', 320);
      await tester.pump();

      final row = find.byKey(const ValueKey<String>('s1'));
      expect(
        find.descendant(of: row, matching: find.text('settled 320ms')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('checkout')),
        findsOneWidget,
      );
      controller.endSegment();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();
      final secondRow = find.byKey(const ValueKey<String>('s2'));
      expect(
        find.descendant(of: secondRow, matching: find.text('checkout')),
        findsNothing,
      );
    });

    testWidgets('auto-scrolls to the newest step', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      for (var index = 0; index < 12; index += 1) {
        controller.recorder.recordInteractionStep(
          stepWithCandidates(CockpitInteractionStepKind.tap),
        );
      }
      await tester.pump();
      await tester.pump();

      // The lazy list only builds the newest row once scrolled to it.
      expect(find.text('s12'), findsOneWidget);
      expect(find.text('s12').hitTestable(), findsOneWidget);
      expect(find.text('s1'), findsNothing);
    });

    testWidgets('follows a controller swap', (tester) async {
      final first = newController();
      first.start();
      first.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      final second = newController();
      second.start();
      second.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      second.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 480,
              height: 320,
              child: CockpitRecorderTimeline(controller: first),
            ),
          ),
        ),
      );
      expect(find.text('s1'), findsOneWidget);

      // Swapping controllers re-targets the timeline and its listener.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 480,
              height: 320,
              child: CockpitRecorderTimeline(controller: second),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey<String>('s1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('s2')), findsOneWidget);

      // The first controller no longer drives the timeline: appending there
      // leaves it untouched, while appending to the second appends a row.
      first.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      second.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('s3')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('s2')), findsOneWidget);
    });

    testWidgets('renders value and route fallbacks for candidate-less rows', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        CockpitInteractionStep(
          stepId: 'pending',
          kind: CockpitInteractionStepKind.text,
          resolvedValue: 'typed draft',
          phase: CockpitRecorderPhase.recording,
          recordedAt: DateTime.utc(2026, 10, 7, 9),
        ),
      );
      controller.recorder.recordInteractionStep(
        CockpitInteractionStep(
          stepId: 'pending',
          kind: CockpitInteractionStepKind.routeChange,
          routeName: '/checkout',
          phase: CockpitRecorderPhase.recording,
          recordedAt: DateTime.utc(2026, 10, 7, 9),
        ),
      );
      await tester.pump();

      expect(find.text('typed draft'), findsOneWidget);
      expect(find.text('/checkout'), findsOneWidget);
    });
  });

  group('bottom bar', () {
    testWidgets('stays disabled until a session exists', (tester) async {
      final controller = await pumpPanel(tester);

      expect(find.text('no bundle yet'), findsOneWidget);
      expect(isButtonEnabled(tester, 'Copy YAML'), isFalse);
      expect(isButtonEnabled(tester, 'Save'), isFalse);
      expect(isButtonEnabled(tester, 'Verify replay'), isFalse);
      // The export step is folded into copy and save — no Export button.
      expect(find.text('Export'), findsNothing);

      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      await tester.pump();

      expect(isButtonEnabled(tester, 'Copy YAML'), isTrue);
      expect(isButtonEnabled(tester, 'Save'), isTrue);
    });

    testWidgets('copy exports and copies in one click', (tester) async {
      // flutter_test ships no clipboard mock; without one the platform
      // message never replies and the test hangs.
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
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Copy YAML'));
      await tester.pump();

      expect(clipboardText, controller.lastBundle!.caseYaml);
      expect(find.textContaining('case recorded-r1'), findsOneWidget);
      expect(find.textContaining('copied ✓'), findsOneWidget);

      // The confirmation in the status line resets after two seconds.
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('copied ✓'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('copied ✓'), findsNothing);
    });

    testWidgets('save exports and persists in one click', (tester) async {
      final gateway = RecordingGateway()..result = '/tmp/recorded-r1.yaml';
      final controller = await pumpPanel(tester, gateway: gateway);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();

      expect(gateway.bundles, hasLength(1));
      expect(controller.savedPath, '/tmp/recorded-r1.yaml');
      expect(
        find.textContaining('saved to /tmp/recorded-r1.yaml'),
        findsOneWidget,
      );
    });

    testWidgets('gateway errors surface inline', (tester) async {
      final gateway = RecordingGateway()..error = StateError('disk on fire');
      final controller = await pumpPanel(tester, gateway: gateway);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();

      expect(controller.savedPath, isNull);
      expect(find.textContaining('disk on fire'), findsOneWidget);
    });
  });

  group('replay', () {
    testWidgets('stays disabled without actionable steps', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        unresolvedStep(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      expect(isButtonEnabled(tester, 'Verify replay'), isFalse);
    });

    testWidgets('rows carry per-step badges with reasons', (tester) async {
      final controller = await pumpPanel(
        tester,
        recorder: replayableRecorder(),
      );
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('replay-zone')],
        ),
      );
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('vanished')],
        ),
      );
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.routeChange),
      );
      await tester.pump();

      expect(isButtonEnabled(tester, 'Verify replay'), isTrue);
      await tester.tap(find.text('Verify replay'));
      await tester.pump();
      await tester.pump();

      // The badges live inside the timeline rows, joined by step id.
      final s1Row = find.byKey(const ValueKey<String>('s1'));
      final s2Row = find.byKey(const ValueKey<String>('s2'));
      final s3Row = find.byKey(const ValueKey<String>('s3'));
      expect(
        find.descendant(of: s1Row, matching: find.text('✓ passed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: s2Row, matching: find.text('✗ deviated')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: s2Row,
          matching: find.textContaining('No locator candidate'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: s3Row, matching: find.text('– skipped')),
        findsOneWidget,
      );
      expect(
        find.text('replay: 1 passed · 1 deviated · 1 skipped'),
        findsOneWidget,
      );
    });

    testWidgets('replay failures surface inline', (tester) async {
      // Actionable step, but no registry wired to the engine.
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('gone')],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Verify replay'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('no target registry'), findsOneWidget);
    });
  });
}

/// Whether the button showing [label] inside [row] is enabled.
bool isRowButtonEnabled(WidgetTester tester, Finder row, String label) {
  final gesture = find
      .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
      .first;
  expect(
    find.descendant(of: row, matching: gesture),
    findsOneWidget,
    reason: 'Button "$label" must live inside the row.',
  );
  return tester.widget<GestureDetector>(gesture).onTap != null;
}
