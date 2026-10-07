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

/// A stable, non-interactive AppBar text on every collection screen.
final Finder _appBarBrand = find.text('SUPER COCKPIT');

/// A point in the AppBar background whose hit path contains no registered
/// target: taps there classify as unresolved noise. (List-body gutters are
/// NOT noise on this app — merged-semantics section containers cover them.)
const Offset _appBarBackground = Offset(400, 40);

/// The task-row completion checkbox, resolved without a semantics handle.
Finder _taskCheckbox(String title) => find.descendant(
  of: find.widgetWithText(TaskListItem, title),
  matching: find.byType(Checkbox),
);

void main() {
  late CockpitDemoDatabase holdDatabase;
  late TodoAppService holdService;
  late CockpitDemoDatabase deviationDatabase;
  late TodoAppService deviationService;

  cockpitTestWidgets(
    'pause suppresses capture and ids stay monotonic after resume',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('New task');

      recorder.start();
      await tester.tap(_appBarBrand);
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(1));
      expect(recorder.steps.single.stepId, 's1');

      recorder.pause();
      await tester.tap(_appBarBrand);
      await tester.pumpAndSettle();
      expect(
        recorder.steps,
        hasLength(1),
        reason: 'Paused capture dropped it.',
      );

      recorder.resume();
      await tester.tap(_appBarBrand);
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(2));
      expect(recorder.steps.last.stepId, 's2');
      recorder.stop();
    },
  );

  cockpitTestWidgets(
    'keeps unresolved noise out of the exported case',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('New task');

      recorder.start();
      await tester.tap(_appBarBrand);
      await tester.pumpAndSettle();
      // A tap on bare AppBar background resolves to no registered target.
      await tester.tapAt(_appBarBackground);
      await tester.pumpAndSettle();

      final noise = recorder.steps.last;
      expect(noise.unresolved, isTrue);
      expect(noise.locatorCandidates, isEmpty);
      expect(recorder.steps, hasLength(2));
      recorder.stop();

      final bundle = recorder.export();
      final compilation = const CockpitTestDocumentCompiler().compile(
        bundle.caseYaml,
        format: CockpitDocumentFormat.yaml,
      );
      expect(
        compilation.isSuccess,
        isTrue,
        reason: compilation.diagnostics
            .map((diagnostic) => diagnostic.message)
            .join('\n'),
      );
      final compiledCase = compilation.requireCase().testCase;
      final tapActions = <CockpitTestActionTemplate>[
        for (final step in compiledCase.steps)
          if (step.operation case CockpitTestActionOperationTemplate(
            :final action,
          ))
            if (action.kind == CockpitTestActionKind.tap) action,
      ];
      // The resolved tap survives; the noise tap never becomes an action.
      expect(tapActions, hasLength(1));
    },
  );

  cockpitTestWidgets(
    'skips text capture for empty values',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('New task');

      recorder.start();
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await cockpit.expectVisible('Task title');
      await tester.enterText(textFieldByLabel('Task title'), '');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        recorder.steps.any(
          (step) => step.kind == CockpitInteractionStepKind.text,
        ),
        isFalse,
      );
      recorder.stop();
    },
  );

  cockpitTestWidgets(
    'flushes a still-focused field when stopping',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('New task');

      recorder.start();
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await cockpit.expectVisible('Task title');
      await tester.enterText(textFieldByLabel('Task title'), 'Unflushed value');
      await tester.pump();
      expect(
        recorder.steps.any(
          (step) => step.kind == CockpitInteractionStepKind.text,
        ),
        isFalse,
        reason: 'The step must wait for focus to leave or the session to stop.',
      );

      final result = recorder.stop();
      final flushed = result.steps
          .where((step) => step.kind == CockpitInteractionStepKind.text)
          .single;
      expect(flushed.resolvedValue, 'Unflushed value');
      expect(flushed.locatorCandidates, isNotEmpty);
    },
  );

  cockpitTestWidgets(
    'classifies a real-timing long press',
    app: () {
      holdDatabase = CockpitDemoDatabase.inMemory();
      addTearDown(holdDatabase.close);
      return CockpitDemoApp(
        database: holdDatabase,
        onServiceReady: (ready) => holdService = ready,
      );
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final repository = TodoRepository(holdDatabase);
      await repository.createTask(title: 'Hold target one');
      await repository.createTask(title: 'Hold target two');
      await holdService.loadTasks();
      await tester.pumpAndSettle();

      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('Hold target one');
      recorder.start();

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.descendant(
            of: find.byType(TaskListItem).first,
            matching: find.byType(InkWell),
          ),
        ),
      );
      // Real wall-clock hold past the 500 ms default threshold.
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      final longPress = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.longPress)
          .single;
      expect(longPress.unresolved, isFalse);
      expect(longPress.locatorCandidates, isNotEmpty);
      recorder.stop();
    },
  );

  cockpitTestWidgets(
    'records rapid taps before settle completes',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('New task');

      recorder.start();
      // Two taps with no settle wait between them.
      await tester.tap(_appBarBrand);
      await tester.tap(find.text('Inbox').first);
      await tester.pumpAndSettle();
      // Let the pending settle watches observe a full quiet window.
      await tester.pump(const Duration(milliseconds: 800));

      expect(recorder.steps, hasLength(2));
      expect(
        recorder.steps.map((step) => step.stepId).toList(growable: false),
        <String>['s1', 's2'],
      );
      for (final step in recorder.steps) {
        expect(step.settledAfterMs, isNotNull, reason: step.stepId);
      }
      recorder.stop();
    },
  );

  cockpitTestWidgets(
    'records route push and pop as routeChange steps',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final recorder = cockpit.root.interactionRecorder!;
      await cockpit.expectVisible('New task');

      recorder.start();
      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await cockpit.expectVisible('Task title');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await cockpit.expectVisible('New task');

      final transitions = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.routeChange)
          .map((step) => '${step.fromRouteName}->${step.routeName}')
          .toList(growable: false);
      expect(transitions, <String>['/inbox->/editor', '/editor->/inbox']);
      recorder.stop();
    },
  );

  cockpitTestWidgets(
    'reports a deviation when a recorded target disappears',
    app: () {
      deviationDatabase = CockpitDemoDatabase.inMemory();
      addTearDown(deviationDatabase.close);
      return CockpitDemoApp(
        database: deviationDatabase,
        onServiceReady: (ready) => deviationService = ready,
      );
    },
    options: cockpitDemoRecorderTestOptions(),
    body: (cockpit) async {
      final tester = cockpit.flutter;
      final repository = TodoRepository(deviationDatabase);
      await repository.createTask(title: 'Stable task');
      await repository.createTask(title: 'Doomed task');
      await deviationService.loadTasks();
      await tester.pumpAndSettle();

      final recorder = cockpit.root.interactionRecorder!;
      recorder.start();
      await tester.tap(_appBarBrand);
      await tester.pumpAndSettle();
      await tester.tap(_taskCheckbox('Doomed task'));
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(2));
      final doomedStepId = recorder.steps.last.stepId;
      recorder.stop();

      // Remove both tasks out-of-band and reload so the rows unmount: the
      // doomed step must have no surviving fallback (another row's checkbox
      // or task-item type would otherwise resolve and mask the deviation).
      final tasks = await repository.fetchTasks(
        const TodoFilter(completionFilter: TodoCompletionFilter.all),
      );
      await repository.deleteTasks(tasks.map((task) => task.id).toList());
      await deviationService.loadTasks();
      await tester.pumpAndSettle();

      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(reports.first.status, CockpitReplayStatus.passed);
      expect(reports.last.stepId, doomedStepId);
      expect(reports.last.status, CockpitReplayStatus.deviated);
      expect(reports.last.reason, contains('No locator candidate resolved'));
    },
  );
}
