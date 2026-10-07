import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('control area', () {
    testWidgets('buttons follow the phase matrix', (tester) async {
      final controller = await pumpPanel(tester);

      // idle: start only.
      expect(isButtonEnabled(tester, 'Start'), isTrue);
      expect(isButtonEnabled(tester, 'Pause'), isFalse);
      expect(isButtonEnabled(tester, 'Resume'), isFalse);
      expect(isButtonEnabled(tester, 'Stop'), isFalse);
      expect(find.text('no session'), findsOneWidget);

      controller.start();
      await tester.pump();

      // recording: pause + stop.
      expect(isButtonEnabled(tester, 'Start'), isFalse);
      expect(isButtonEnabled(tester, 'Pause'), isTrue);
      expect(isButtonEnabled(tester, 'Resume'), isFalse);
      expect(isButtonEnabled(tester, 'Stop'), isTrue);
      expect(find.text('recording · 0 steps · 0 unresolved'), findsOneWidget);

      controller.pause();
      await tester.pump();

      // paused: resume + stop.
      expect(isButtonEnabled(tester, 'Start'), isFalse);
      expect(isButtonEnabled(tester, 'Pause'), isFalse);
      expect(isButtonEnabled(tester, 'Resume'), isTrue);
      expect(isButtonEnabled(tester, 'Stop'), isTrue);

      controller.resume();
      controller.stop();
      await tester.pump();

      // stopped: start again.
      expect(isButtonEnabled(tester, 'Start'), isTrue);
      expect(isButtonEnabled(tester, 'Stop'), isFalse);
    });

    testWidgets('counters track steps and unresolved noise', (tester) async {
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

      expect(find.text('recording · 2 steps · 1 unresolved'), findsOneWidget);
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

    testWidgets('delete is enabled on the last row only', (tester) async {
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
        isRowButtonEnabled(tester, earlierRow, 'Delete (last only)'),
        isFalse,
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
  });

  group('export area', () {
    testWidgets('stays disabled until a bundle exists', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      await tester.pump();

      expect(find.text('no bundle yet'), findsOneWidget);
      expect(isButtonEnabled(tester, 'Copy YAML'), isFalse);
      expect(isButtonEnabled(tester, 'Save'), isFalse);
      expect(isButtonEnabled(tester, 'Export'), isTrue);

      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('save')],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Export'));
      await tester.pump();

      expect(find.text('case recorded-r1'), findsOneWidget);
      expect(isButtonEnabled(tester, 'Copy YAML'), isTrue);
      expect(isButtonEnabled(tester, 'Save'), isTrue);
    });

    testWidgets('copy writes the case YAML to the clipboard', (tester) async {
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
      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.tap(find.text('Copy YAML'));
      await tester.pump();

      expect(clipboardText, controller.lastBundle!.caseYaml);
      expect(find.text('Copied!'), findsOneWidget);
    });

    testWidgets('save shows the gateway path', (tester) async {
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
      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.tap(find.text('Save'));
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
      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(controller.savedPath, isNull);
      expect(find.textContaining('disk on fire'), findsOneWidget);
    });
  });

  group('replay area', () {
    testWidgets('stays disabled without actionable steps', (tester) async {
      final controller = await pumpPanel(tester);
      controller.start();
      controller.recorder.recordInteractionStep(
        unresolvedStep(CockpitInteractionStepKind.tap),
      );
      await tester.pump();

      expect(isButtonEnabled(tester, 'Verify replay'), isFalse);
    });

    testWidgets('lists per-step statuses with reasons', (tester) async {
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
      await tester.pump();
      await tester.tap(find.text('Verify replay'));
      await tester.pump();

      expect(find.text('s1:passed'), findsOneWidget);
      expect(find.text('s2:deviated'), findsOneWidget);
      expect(find.textContaining('No locator candidate'), findsOneWidget);
      expect(find.text('s3:skipped'), findsOneWidget);
      expect(find.text('passed 1 · deviated 1 · skipped 1'), findsOneWidget);
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
