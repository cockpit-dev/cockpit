import 'package:cockpit/cockpit.dart' show CockpitTestDocumentCompiler;
import 'package:cockpit_demo/src/app/todo_app_service.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_demo/src/data/todo_repository.dart';
import 'package:cockpit_demo/src/model/todo_filter.dart';
import 'package:cockpit_demo/src/ui/widgets/task_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/cockpit_demo_test_support.dart';

void main() {
  late CockpitDemoDatabase database;
  late TodoAppService service;

  cockpitTestWidgets(
    'records a rich task flow into a compilable, replayable case',
    app: () {
      database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(
        database: database,
        onServiceReady: (ready) => service = ready,
      );
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      expect(recorder, isNotNull);
      expect(recorder.phase, CockpitRecorderPhase.idle);

      final repository = TodoRepository(database);

      await repository.createTask(title: 'Seed alpha');
      await repository.createTask(title: 'Seed bravo');
      for (var index = 3; index <= 12; index += 1) {
        await repository.createTask(title: 'Filler item $index');
      }
      await service.loadTasks();
      await tester.pumpAndSettle();
      await cockpit.expectVisible('New task');
      expect(recorder.steps, isEmpty);

      recorder.start(
        const CockpitInteractionRecordingRequest(name: 'Rich task flow'),
      );
      recorder.beginSegment('setup');
      expect(recorder.activeSession!.sessionId, 'r1');

      // 1. Raw tap on the entry point; the route push becomes a routeChange.
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await cockpit.expectVisible('Task title');

      final entryTap = recorder.steps.firstWhere(
        (step) => step.kind == CockpitInteractionStepKind.tap,
      );
      expect(entryTap.unresolved, isFalse);
      expect(entryTap.locatorCandidates, isNotEmpty);
      expect(entryTap.locatorCandidates.first.kind, 'key');
      expect(entryTap.locatorCandidates.first.selector, contains('open-task'));
      expect(entryTap.routeName, '/inbox');

      final editorPush = recorder.steps.firstWhere(
        (step) => step.kind == CockpitInteractionStepKind.routeChange,
      );
      expect(editorPush.fromRouteName, '/inbox');
      expect(editorPush.routeName, '/editor');

      // 2. Text entry commits one step with the final value when focus leaves.
      await tester.enterText(textFieldByLabel('Task title'), 'Recorded task');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final textSteps = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.text)
          .toList(growable: false);
      expect(textSteps, hasLength(1));
      expect(textSteps.single.resolvedValue, 'Recorded task');
      expect(textSteps.single.locatorCandidates, isNotEmpty);
      expect(textSteps.single.routeName, '/editor');

      // 3. Saving completes the setup segment and pops back to the inbox.
      await tester.tap(find.text('Save task'));
      await settleAfterTaskSave(tester);
      await cockpit.expectVisible('Recorded task');

      recorder.endSegment();
      expect(recorder.openSegments, isEmpty);
      expect(
        recorder.steps
            .where((step) => step.segments.contains('setup'))
            .isNotEmpty,
        isTrue,
      );

      // 4. Open a seeded task; complete it on the detail screen; go back.
      final seedRow = find
          .descendant(
            of: find.byType(TaskListItem),
            matching: find.text('Seed alpha'),
          )
          .first;
      await tester.ensureVisible(seedRow);
      await tester.pumpAndSettle();
      await tester.tap(seedRow);
      // The row also handles double-tap, so the single tap fires after the
      // double-tap window closes.
      await settleSingleTapGesture(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The route change caused by the back tap is discovered when the tap's
      // settle watch completes, so advance real time past the quiet window.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final routeChanges = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.routeChange)
          .toList(growable: false);
      expect(
        routeChanges.map((step) => '${step.fromRouteName}->${step.routeName}'),
        containsAll(<String>[
          '/inbox->/editor',
          '/editor->/inbox',
          '/inbox->/detail',
          '/detail->/inbox',
        ]),
      );

      // 5. Scroll the task list in both directions with raw drags.
      final scrollAnchor = find.byType(ListView).first;
      await tester.drag(scrollAnchor, const Offset(0, -140));
      await tester.pumpAndSettle();
      await tester.drag(scrollAnchor, const Offset(0, 140));
      await tester.pumpAndSettle();

      final scrollSteps = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.scroll)
          .toList(growable: false);
      expect(scrollSteps, hasLength(2));
      expect(
        scrollSteps.first.scrollDirection,
        CockpitInteractionScrollDirection.up,
      );
      expect(
        scrollSteps.last.scrollDirection,
        CockpitInteractionScrollDirection.down,
      );

      // 6. Annotate a recorded step.
      recorder.annotate(entryTap.stepId, 'entry point');
      expect(
        recorder.steps
            .firstWhere((step) => step.stepId == entryTap.stepId)
            .annotation,
        'entry point',
      );

      // 7. Discard the newest step; the engine's id counter stays monotonic.
      final lastId = recorder.steps.last.stepId;
      final lastNumber = int.parse(lastId.substring(1));
      recorder.discardLastStep();
      expect(recorder.steps.last.stepId, isNot(lastId));
      final countAfterDiscard = recorder.steps.length;
      // A tap on bare AppBar background (no registered target) produces one
      // more engine-stamped step without touching app state.
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();
      expect(recorder.steps.length, countAfterDiscard + 1);
      expect(recorder.steps.last.stepId, 's${lastNumber + 1}');
      expect(recorder.steps.last.unresolved, isTrue);

      // 8. Stop and verify the result counts.
      final unresolvedCount = recorder.steps
          .where((step) => step.unresolved)
          .length;
      final result = recorder.stop();
      expect(result.session.phase, CockpitRecorderPhase.stopped);
      expect(result.session.sessionId, 'r1');
      expect(result.session.stepCount, recorder.steps.length);
      expect(result.session.unresolvedCount, unresolvedCount);
      expect(result.steps, recorder.steps);

      // 9. Export and compile the recorded flow.
      final bundle = recorder.export();
      expect(bundle.caseYaml, isNotEmpty);
      expect(bundle.caseDocument['id'], 'recorded-r1');
      final compilation = const CockpitTestDocumentCompiler().compile(
        bundle.caseYaml,
        format: CockpitDocumentFormat.yaml,
      );
      expect(
        compilation.isSuccess,
        isTrue,
        reason: compilation.diagnostics
            .map((d) => '${d.path}: ${d.message}')
            .join('\n'),
      );
      final compiledCase = compilation.requireCase().testCase;
      expect(compiledCase.id, 'recorded-r1');
      expect(compiledCase.name, 'Rich task flow');
      expect(compiledCase.extensions['x-cockpit-origin'], 'recorded');
      expect(compiledCase.extensions['x-cockpit-recorder-session'], 'r1');

      List<CockpitTestActionTemplate> actionsOf(
        List<CockpitTestStepTemplate> steps,
      ) => <CockpitTestActionTemplate>[
        for (final step in steps)
          if (step.operation case CockpitTestActionOperationTemplate(
            :final action,
          ))
            action,
      ];

      final setupActions = actionsOf(compiledCase.setup);
      final mainActions = actionsOf(compiledCase.steps);
      expect(setupActions, isNotEmpty);
      expect(mainActions, isNotEmpty);
      // The unresolved noise tap never reaches the exported case.
      expect(
        mainActions
            .where((action) => action.kind == CockpitTestActionKind.tap)
            .length,
        lessThan(
          recorder.steps
              .where((step) => step.kind == CockpitInteractionStepKind.tap)
              .length,
        ),
      );
      // Setup carries the editor entry: tap, route wait, and the typed value.
      expect(setupActions.first.kind, CockpitTestActionKind.tap);
      expect(
        setupActions.any(
          (action) =>
              action.kind == CockpitTestActionKind.waitFor &&
              action.condition?.kind == CockpitTestConditionKind.route &&
              action.condition?.route?.value == '/editor',
        ),
        isTrue,
      );
      final enterText = setupActions.firstWhere(
        (action) => action.kind == CockpitTestActionKind.enterText,
      );
      expect(
        enterText.values[CockpitTestActionField.text]?.value,
        'Recorded task',
      );
      // Weak visibility assertions are emitted between actions.
      expect(
        mainActions.any(
          (action) =>
              action.kind == CockpitTestActionKind.waitFor &&
              action.condition?.kind == CockpitTestConditionKind.visible,
        ),
        isTrue,
      );
      // The entry tap's locator carries the remaining candidates as
      // fallbacks when discovery registered more than one signal.
      final entryAction = setupActions
          .where((action) => action.kind == CockpitTestActionKind.tap)
          .first;
      expect(entryAction.locator, isNotNull);
      if (entryTap.locatorCandidates.length > 1) {
        expect(entryAction.locator!.fallbacks, isNotEmpty);
      }

      // 10. Verify replay: actionable steps re-execute; capture stays silent.
      // Replay re-runs the recorded gestures from the state the flow was
      // captured in, so restore that precondition first: the recording has
      // completed 'Seed alpha' — the detail screen's helper text depends on
      // that completion state — and its setup segment already created the
      // 'Recorded task' row the replay is about to create again.
      final tasksAfterRecording = await repository.fetchTasks(
        const TodoFilter(completionFilter: TodoCompletionFilter.all),
      );
      await repository.setTaskCompleted(
        taskId: tasksAfterRecording
            .firstWhere((task) => task.title == 'Seed alpha')
            .id,
        isCompleted: false,
      );
      await repository.deleteTask(
        tasksAfterRecording
            .firstWhere((task) => task.title == 'Recorded task')
            .id,
      );
      await service.loadTasks();
      await tester.pumpAndSettle();

      final stepsBeforeReplay = recorder.steps.length;
      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();
      expect(recorder.steps.length, stepsBeforeReplay);
      expect(recorder.isReplaying, isFalse);
      expect(reports, hasLength(recorder.steps.length));
      for (var index = 0; index < reports.length; index += 1) {
        final report = reports[index];
        final step = recorder.steps[index];
        if (CockpitInteractionRecorder.isActionable(step)) {
          expect(
            report.status,
            CockpitReplayStatus.passed,
            reason:
                '${step.stepId} (${step.kind.name}) '
                '${report.reason ?? ''} '
                'candidates=${step.locatorCandidates.map((c) => c.selector).toList()}',
          );
        } else {
          expect(report.status, CockpitReplayStatus.skipped);
        }
      }

      // 11. A second session resets the timeline and increments the id.
      recorder.start();
      expect(recorder.steps, isEmpty);
      expect(recorder.activeSession!.sessionId, 'r2');
      await tester.tap(find.text('SUPER COCKPIT'));
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(1));
      expect(recorder.steps.single.stepId, 's1');
      recorder.stop();
      final second = recorder.export();
      expect(second.caseDocument['id'], 'recorded-r2');
      final secondCompilation = const CockpitTestDocumentCompiler().compile(
        second.caseYaml,
        format: CockpitDocumentFormat.yaml,
      );
      expect(
        secondCompilation.isSuccess,
        isTrue,
        reason: secondCompilation.diagnostics
            .map((d) => '${d.path}: ${d.message}')
            .join('\n'),
      );
    },
  );
}
