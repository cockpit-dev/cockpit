import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/recorder/ui/cockpit_recorder_panel_widgets.dart';
import 'package:flutter_cockpit/src/recorder/ui/cockpit_recorder_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('header', () {
    testWidgets('idle shows the Recorder title without counters', (
      tester,
    ) async {
      await pumpPanel(tester);

      expect(find.text('Recorder'), findsOneWidget);
      expect(find.textContaining('REC '), findsNothing);
      // No session, no step-count suffix beside the title.
      expect(find.textContaining(' · '), findsNothing);
      // The phase is the header dot's color, not an uppercase word.
      expect(find.text('RECORDING'), findsNothing);
    });

    testWidgets('switches the hero clock and caption through the phases', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);

      controller.start();
      await tester.pump();

      // The clock is recomputed per controller notification: a fresh
      // session reads 00:00, with the phase and count in the caption.
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Recording · 0 steps'), findsOneWidget);

      controller.recorder.recordInteractionStep(
        unresolvedStep(CockpitInteractionStepKind.tap),
      );
      await tester.pump();
      expect(find.text('Recording · 1 step'), findsOneWidget);

      controller.pause();
      await tester.pump();
      expect(find.text('Paused · 1 step'), findsOneWidget);

      controller.stop();
      await tester.pump();
      expect(find.text('Stopped · 1 step'), findsOneWidget);
      // The stopped clock freezes at the session's end instead of tracking
      // whatever notification arrives next.
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('embedded panels render no close button', (tester) async {
      await pumpPanel(tester);
      expect(find.text('✕'), findsNothing);
    });
  });

  group('control zone', () {
    testWidgets('shows only the current phase primary buttons', (tester) async {
      final controller = await pumpPanel(tester);

      // idle: the name field above a full-width Record.
      expect(isButtonEnabled(tester, 'Record'), isTrue);
      expect(find.text('Session name (optional)'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Stop'), findsNothing);

      controller.start();
      await tester.pump();

      // recording: pause + stop + the collapsed segment affordance.
      expect(find.text('Record'), findsNothing);
      expect(isButtonEnabled(tester, 'Pause'), isTrue);
      expect(find.text('Resume'), findsNothing);
      expect(isButtonEnabled(tester, 'Stop'), isTrue);
      expect(isButtonEnabled(tester, '+ Add segment'), isTrue);

      controller.pause();
      await tester.pump();

      // paused: resume + stop; segments annotate a live capture only.
      expect(find.text('Pause'), findsNothing);
      expect(isButtonEnabled(tester, 'Resume'), isTrue);
      expect(isButtonEnabled(tester, 'Stop'), isTrue);
      expect(find.text('+ Add segment'), findsNothing);

      controller.resume();
      controller.stop();
      await tester.pump();

      // stopped: record again, with a hint instead of the name field.
      expect(isButtonEnabled(tester, 'Record again'), isTrue);
      expect(find.text('Record'), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Session name (optional)'), findsNothing);
      expect(
        find.text('Session stopped — export above or record again.'),
        findsOneWidget,
      );
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
      // Starting switched the zone to recording controls; the name field is
      // gone and took its text with it.
      expect(find.text('login flow'), findsNothing);
    });

    testWidgets('tapping Record reads the name field', (tester) async {
      final controller = await pumpPanel(tester);

      await tester.enterText(find.byType(EditableText), 'checkout flow');
      await tester.tap(find.text('Record'));
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
      await tester.tap(find.text('Record'));
      await tester.pump();

      expect(controller.phase, CockpitRecorderPhase.recording);
    });

    testWidgets('segment begin and end update open chips', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      // Resting shows one quiet affordance; the composer is collapsed and
      // the end control only exists while a segment is open.
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('End segment'), findsNothing);

      await tester.tap(find.text('+ Add segment'));
      await tester.pump();
      expect(find.text('Segment label'), findsOneWidget);

      // The empty-label guard: Add stays disabled until text lands.
      expect(isButtonEnabled(tester, 'Add'), isFalse);

      await tester.enterText(find.byType(EditableText), 'setup');
      await tester.pump();
      expect(isButtonEnabled(tester, 'Add'), isTrue);

      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(controller.openSegments, <String>['setup']);
      expect(find.text('setup'), findsOneWidget);
      expect(isButtonEnabled(tester, 'End segment'), isTrue);
      // Adding collapsed the composer back to the quiet affordance.
      expect(find.byType(EditableText), findsNothing);
      expect(isButtonEnabled(tester, '+ Add segment'), isTrue);

      await tester.tap(find.text('End segment'));
      await tester.pump();

      expect(controller.openSegments, isEmpty);
      expect(find.text('End segment'), findsNothing);
    });

    testWidgets('submitting the segment field begins the segment', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      await tester.tap(find.text('+ Add segment'));
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'via-keyboard');
      // Drive the field's submit wiring (what a keyboard done action fires).
      tester.widget<EditableText>(find.byType(EditableText)).onSubmitted!(
        'via-keyboard',
      );
      await tester.pump();

      expect(controller.openSegments, <String>['via-keyboard']);
      // Submitting collapsed the composer; the label moved into a chip.
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('via-keyboard'), findsOneWidget);
    });

    testWidgets('illegal commands surface inline errors', (tester) async {
      final controller = await pumpPanel(tester);

      // No session yet: tapping disabled buttons is impossible, but the
      // controller-level failure path is visible when a command races a
      // phase change — drive one directly.
      controller.pause();
      await tester.pump();

      expect(find.textContaining('Cannot pause'), findsOneWidget);
      expect(isButtonEnabled(tester, 'Dismiss'), isTrue);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(find.textContaining('Cannot pause'), findsNothing);
    });
  });

  group('steps flow', () {
    testWidgets('renders action titles and the unresolved marker', (
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
      expect(find.text('Tap · save'), findsOneWidget);
      expect(find.text('@save'), findsOneWidget);
      expect(find.text('(unresolved target)'), findsOneWidget);
      // The glyphs carry the row state: neutral for a resolved step, amber
      // for an unresolved one.
      final firstRow = find.byKey(const ValueKey<String>('s1'));
      final secondRow = find.byKey(const ValueKey<String>('s2'));
      expect(stepGlyphColor(tester, firstRow), cockpitRecorderInkTertiary);
      expect(stepGlyphColor(tester, secondRow), cockpitRecorderWarning);
    });

    testWidgets('renders relative times from the first step', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      // The last row swaps its time for the Delete affordance while
      // recording, so the timed offset lands on a middle row.
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          const <CockpitLocatorCandidate>[],
          sessionClock(const Duration(milliseconds: 1200)),
        ),
      );
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      final firstRow = find.byKey(const ValueKey<String>('s1'));
      final secondRow = find.byKey(const ValueKey<String>('s2'));
      expect(
        find.descendant(of: firstRow, matching: find.text('+0.0s')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: secondRow, matching: find.text('+1.2s')),
        findsOneWidget,
      );
    });

    testWidgets('delete appears on the last row only, while recording', (
      tester,
    ) async {
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

      // Pausing hides the affordance: no step can be discarded.
      controller.pause();
      await tester.pump();
      expect(find.text('Delete'), findsNothing);

      controller.resume();
      await tester.pump();
      await tester.tap(
        find.descendant(of: lastRow, matching: find.text('Delete')),
      );
      await tester.pump();

      expect(controller.steps.map((step) => step.stepId), <String>['s1']);
    });

    testWidgets('tapping a row expands the detail area', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap, <
          CockpitLocatorCandidate
        >[
          keyCandidate('save'),
          CockpitLocatorCandidate(kind: 'text', selector: 'New task', score: 2),
        ]),
      );
      await tester.pump();

      final row = find.byKey(const ValueKey<String>('s1'));
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: row, matching: find.text('key · @save')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('text · New task')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('4')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('2')),
        findsOneWidget,
      );

      // Tapping the row again collapses it without saving.
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text('key · @save')),
        findsNothing,
      );
      expect(controller.steps.single.annotation, isNull);
    });

    testWidgets('annotate flow updates the row', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      final row = find.byKey(const ValueKey<String>('s1'));
      await tester.tap(row);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: row, matching: find.byType(EditableText)),
        'first tap',
      );
      await tester.tap(find.descendant(of: row, matching: find.text('Save')));
      await tester.pumpAndSettle();

      expect(controller.steps.single.annotation, 'first tap');
      expect(find.text('Note: first tap'), findsOneWidget);
    });

    testWidgets('annotation Save stays disabled once not recording', (
      tester,
    ) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        stepWithCandidates(CockpitInteractionStepKind.tap),
      );
      controller.stop();
      await tester.pump();

      final row = find.byKey(const ValueKey<String>('s1'));
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: row, matching: find.byType(EditableText)),
        findsOneWidget,
      );
      expect(isRowButtonEnabled(tester, row, 'Save'), isFalse);
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
      final newest = find.byKey(const ValueKey<String>('s12'));
      expect(newest, findsOneWidget);
      expect(newest.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('s1')), findsNothing);
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
      expect(find.byKey(const ValueKey<String>('s1')), findsOneWidget);

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
          recordedAt: sessionClock(),
        ),
      );
      controller.recorder.recordInteractionStep(
        CockpitInteractionStep(
          stepId: 'pending',
          kind: CockpitInteractionStepKind.routeChange,
          routeName: '/checkout',
          phase: CockpitRecorderPhase.recording,
          recordedAt: sessionClock(),
        ),
      );
      await tester.pump();

      expect(find.text('Type “typed draft”'), findsOneWidget);
      expect(find.text('Open /checkout'), findsOneWidget);
    });

    testWidgets('shows the empty state before any step', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      expect(find.text('No steps yet'), findsOneWidget);
      expect(
        find.textContaining('appear here as they are captured'),
        findsOneWidget,
      );
    });
  });

  group('action row', () {
    testWidgets('stays disabled until a session exists', (tester) async {
      final controller = await pumpPanel(tester);

      // Nothing to report: the status line is hidden entirely.
      expect(find.text('no bundle yet'), findsNothing);
      expect(find.textContaining('case '), findsNothing);
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
      // The button itself flips to a success-colored confirmation.
      expect(find.text('Copied'), findsOneWidget);

      // The confirmation resets after two seconds.
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('copied ✓'), findsOneWidget);
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('copied ✓'), findsNothing);
      expect(find.text('Copy YAML'), findsOneWidget);
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

    testWidgets('rows carry per-step outcomes with reasons', (tester) async {
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
      // Stop first: the last row swaps its time for the Delete affordance
      // while recording, and every outcome must be visible at once.
      controller.stop();
      await tester.pump();

      expect(isButtonEnabled(tester, 'Verify replay'), isTrue);
      await tester.tap(find.text('Verify replay'));
      await tester.pump();
      await tester.pump();

      // The outcomes tint the rows' glyphs, joined by step id.
      final s1Row = find.byKey(const ValueKey<String>('s1'));
      final s2Row = find.byKey(const ValueKey<String>('s2'));
      final s3Row = find.byKey(const ValueKey<String>('s3'));
      expect(stepGlyphColor(tester, s1Row), cockpitRecorderSuccess);
      expect(stepGlyphColor(tester, s2Row), cockpitRecorderRecord);
      expect(
        find.descendant(
          of: s2Row,
          matching: find.textContaining('No locator candidate'),
        ),
        findsOneWidget,
      );
      expect(stepGlyphColor(tester, s3Row), cockpitRecorderInkTertiary);
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
  final labelInRow = find.descendant(of: row, matching: find.text(label));
  expect(
    labelInRow,
    findsOneWidget,
    reason: 'Button "$label" must live inside the row.',
  );
  final gesture = find
      .ancestor(of: labelInRow, matching: find.byType(GestureDetector))
      .first;
  return tester.widget<GestureDetector>(gesture).onTap != null;
}
