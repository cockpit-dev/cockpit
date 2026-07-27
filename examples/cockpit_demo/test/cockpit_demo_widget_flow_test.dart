import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_demo/src/data/todo_repository.dart';
import 'package:cockpit_demo/src/model/todo_filter.dart';
import 'package:cockpit_demo/src/model/todo_priority.dart';
import 'package:cockpit_demo/src/model/todo_task.dart';
import 'package:cockpit_demo/src/ui/widgets/collection_overview_card.dart';

import 'support/cockpit_demo_test_support.dart';

void main() {
  testWidgets('overview card keeps its content inset from the card edge', (
    tester,
  ) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);

    await pumpTodoApp(tester, database: database);

    final overviewCard = find.byType(CollectionOverviewCard).first;
    final cardRect = tester.getRect(overviewCard);
    final headlineRect = tester.getRect(find.text('Work queue').first);
    final metricRect = tester.getRect(find.text('OPEN').first);

    expect(headlineRect.left - cardRect.left, greaterThanOrEqualTo(16));
    expect(metricRect.left - cardRect.left, greaterThanOrEqualTo(16));
  });

  testWidgets(
    'todo app supports create, edit, complete, search, and settings flows',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await pumpTodoApp(tester, database: database);

      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Work queue'), findsOneWidget);
      expect(textFieldByLabel('Search title or notes'), findsNothing);

      await createTaskThroughUi(
        tester,
        title: 'Review remote validation',
        notes: 'Check screenshots and recordings',
        priorityLabel: 'HIGH',
      );
      await tester.pumpAndSettle();

      final createdTasks = await database.select(database.tasks).get();
      expect(createdTasks.length, 1);
      expect(find.text('New task'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('latest-task-open-action')),
        findsOneWidget,
      );
      final task = createdTasks.single;
      final taskOpenFinder = taskRowByTitle(task.title);
      await scrollTodoCollectionUntilVisible(tester, taskOpenFinder);
      await tester.tap(taskOpenFinder);
      await settleSingleTapGesture(tester);
      expect(find.text('Task detail'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        textFieldByLabel('Task title'),
        'Review final validation',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Review final validation'), findsWidgets);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Completed'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(navigationButton('Inbox'));
      await tester.pumpAndSettle();
      await scrollTodoCollectionUntilVisible(
        tester,
        textFieldByLabel('Search title or notes'),
        delta: -220,
      );
      await tester.enterText(
        textFieldByLabel('Search title or notes'),
        'final',
      );
      await tester.pumpAndSettle();
      expect(find.text('Review final validation'), findsWidgets);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      await tester.ensureVisible(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use compact task rows'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use compact task rows'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();

      final storedSettings = await (database.select(
        database.appSettings,
      )..limit(1)).getSingle();
      expect(storedSettings.compactMode, isTrue);
      expect(storedSettings.themePreference, 'dark');
    },
  );

  testWidgets('task editor can clear notes before saving', (tester) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);

    await pumpTodoApp(tester, database: database);

    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      textFieldByLabel('Task title'),
      'Draft delivery summary',
    );
    await tester.enterText(
      textFieldByLabel('Notes'),
      'Temporary handoff notes',
    );
    await tester.pumpAndSettle();

    final clearNotesFinder = find.text('Clear notes');
    expect(clearNotesFinder, findsOneWidget);

    await tester.ensureVisible(clearNotesFinder);
    await tester.pumpAndSettle();
    await tester.tap(clearNotesFinder);
    await tester.pumpAndSettle();

    expect(find.text('Temporary handoff notes'), findsNothing);

    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    final createdTasks = await database.select(database.tasks).get();
    expect(createdTasks, hasLength(1));
    expect(createdTasks.single.notes, isEmpty);
  });

  testWidgets(
    'task editor can create tags, assign them, filter the list, and show them in detail',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await pumpTodoApp(tester, database: database);

      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        textFieldByLabel('Task title'),
        'Verify relay tracing',
      );
      await tester.enterText(
        textFieldByLabel('Notes'),
        'Use a backend tag to isolate the validation path.',
      );

      await scrollTodoCollectionUntilVisible(tester, find.text('Create tag'));
      await tester.tap(find.text('Create tag'));
      await tester.pumpAndSettle();
      await tester.enterText(textFieldByLabel('Tag name'), 'Backend');
      await tester.tap(find.text('Create tag').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'Backend'), findsOneWidget);

      await tester.ensureVisible(find.text('Save task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();

      await createTaskThroughUi(
        tester,
        title: 'Polish release notes',
        notes: 'Keep this untagged to verify the filter.',
      );

      await scrollTodoCollectionUntilVisible(
        tester,
        find.widgetWithText(FilterChip, 'Backend').last,
        delta: -180,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Backend').last);
      await tester.pumpAndSettle();

      expect(find.text('Verify relay tracing'), findsWidgets);
      expect(find.text('Polish release notes'), findsNothing);

      final createdTasks = await database.select(database.tasks).get();
      final backendTask = createdTasks.singleWhere(
        (task) => task.title == 'Verify relay tracing',
      );
      await scrollTodoCollectionUntilVisible(
        tester,
        taskRowByTitle(backendTask.title),
      );
      await tester.tap(taskRowByTitle(backendTask.title));
      await tester.pumpAndSettle();

      expect(find.text('Backend'), findsWidgets);
    },
  );

  testWidgets(
    'selection mode can select all filtered tasks and apply a batch priority',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final first = await repository.createTask(
        title: 'Prepare production release',
        priority: TodoPriority.low,
      );
      final second = await repository.createTask(
        title: 'Verify modal overlays',
        priority: TodoPriority.medium,
      );
      final third = await repository.createTask(
        title: 'Guard runtime regressions',
        priority: TodoPriority.high,
      );

      await pumpTodoApp(tester, database: database);

      await tester.longPress(taskRowByTitle(first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All results'));
      await tester.pumpAndSettle();

      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.text('Priority'));
      await tester.pumpAndSettle();
      expect(find.text('Update priority'), findsOneWidget);

      await tester.ensureVisible(find.text('Urgent priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Urgent priority'));
      await tester.pumpAndSettle();

      final refreshed = <String, TodoTask>{
        for (final task in await repository.fetchTasks(
          const TodoFilter.inbox(),
        ))
          task.id: task,
      };
      expect(refreshed[first.id]?.priority, TodoPriority.urgent);
      expect(refreshed[second.id]?.priority, TodoPriority.urgent);
      expect(refreshed[third.id]?.priority, TodoPriority.urgent);
      expect(find.textContaining('selected'), findsNothing);
      expect(find.text('URGENT'), findsWidgets);
    },
  );

  testWidgets('inbox exposes a compact queue brief for rapid validation', (
    tester,
  ) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);
    final repository = TodoRepository(database);
    await repository.createTask(
      title: 'Ship cockpit rapid loop',
      notes: 'Keep the summary cheap for AI validation.',
      priority: TodoPriority.high,
      dueAt: DateTime.now(),
    );
    await repository.createTask(
      title: 'Archive finished notes',
      priority: TodoPriority.low,
      dueAt: DateTime.now(),
    );
    final completed = await repository.createTask(
      title: 'Closed acceptance pass',
      priority: TodoPriority.urgent,
      dueAt: DateTime.now(),
    );
    await repository.setTaskCompleted(taskId: completed.id, isCompleted: true);

    await pumpTodoApp(tester, database: database);

    expect(find.textContaining('Queue brief:'), findsOneWidget);
  });

  testWidgets('selection mode can apply a batch due date update', (
    tester,
  ) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);
    final repository = TodoRepository(database);
    final first = await repository.createTask(title: 'Schedule first');
    await repository.createTask(title: 'Schedule second');

    await pumpTodoApp(tester, database: database);

    await tester.longPress(taskRowByTitle(first.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All results'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Update due date'), findsOneWidget);

    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();

    final refreshed = await repository.fetchTasks(const TodoFilter.inbox());
    final dueTasks = refreshed.where((task) => task.dueAt != null).toList();
    expect(dueTasks, hasLength(2));
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('selection mode can create and apply a shared batch tag set', (
    tester,
  ) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);
    final repository = TodoRepository(database);
    final first = await repository.createTask(title: 'Tag first');
    await repository.createTask(title: 'Tag second');

    await pumpTodoApp(tester, database: database);

    await tester.longPress(taskRowByTitle(first.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All results'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Update tags'), findsOneWidget);

    await tester.enterText(textFieldByLabel('New tag'), 'Ops');
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Ops'), findsWidgets);

    await tester.ensureVisible(find.text('Apply tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply tags'));
    await tester.pumpAndSettle();

    final refreshed = await repository.fetchTasks(const TodoFilter.inbox());
    final taggedTasks = refreshed
        .where((task) => task.tags.isNotEmpty)
        .toList();
    expect(taggedTasks, hasLength(2));
    expect(
      taggedTasks.every(
        (task) => task.tags.map((tag) => tag.name).contains('Ops'),
      ),
      isTrue,
    );
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets(
    'selection mode can duplicate selected tasks with a shared prefix',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final backendTag = await repository.createTag(name: 'Backend');
      final first = await repository.createTask(
        title: 'Duplicate first',
        notes: 'Carry the backend context.',
        tagIds: <String>[backendTag.id],
      );
      await repository.createTask(title: 'Duplicate second');

      await pumpTodoApp(tester, database: database);

      await tester.longPress(taskRowByTitle(first.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All results'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Duplicate'));
      await tester.pumpAndSettle();
      expect(find.text('Duplicate tasks'), findsOneWidget);

      await tester.enterText(textFieldByLabel('Title prefix'), 'Copy');
      await tester.ensureVisible(find.text('Create duplicates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create duplicates'));
      await tester.pumpAndSettle();

      final refreshed = await repository.fetchTasks(const TodoFilter.inbox());
      expect(
        refreshed.any((task) => task.title == 'Copy: Duplicate first'),
        isTrue,
      );
      expect(
        refreshed.any((task) => task.title == 'Copy: Duplicate second'),
        isTrue,
      );
      final copiedFirst = refreshed.singleWhere(
        (task) => task.title == 'Copy: Duplicate first',
      );
      expect(copiedFirst.notes, 'Carry the backend context.');
      expect(
        copiedFirst.tags.map((tag) => tag.name).toList(growable: false),
        <String>['Backend'],
      );
      expect(find.textContaining('selected'), findsNothing);
    },
  );

  testWidgets(
    'task detail can create a follow-up task and open it immediately',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final backendTag = await repository.createTag(name: 'Backend');
      final source = await repository.createTask(
        title: 'Verify relay tracing',
        notes: 'Carry the backend context forward.',
        tagIds: <String>[backendTag.id],
      );

      await pumpTodoApp(tester, database: database);

      await scrollTodoCollectionUntilVisible(
        tester,
        taskRowByTitle(source.title),
      );
      await tester.tap(taskRowByTitle(source.title));
      await settleSingleTapGesture(tester);

      await tester.tap(find.byTooltip('Create follow-up'));
      await tester.pumpAndSettle();
      expect(find.text('Follow-up task'), findsOneWidget);

      await tester.enterText(
        textFieldByLabel('Follow-up title'),
        'Verify relay tracing follow-up',
      );
      final tomorrowChip = find.widgetWithText(ChoiceChip, 'Tomorrow');
      await tester.ensureVisible(tomorrowChip);
      await tester.pumpAndSettle();
      await tester.tap(tomorrowChip);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create follow-up').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create follow-up').last);
      await tester.pumpAndSettle();

      expect(find.text('Verify relay tracing follow-up'), findsWidgets);
      expect(find.text('Backend'), findsWidgets);
      final createdTasks = await repository.fetchTasks(
        const TodoFilter.inbox(),
      );
      expect(
        createdTasks.any(
          (task) => task.title == 'Verify relay tracing follow-up',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'selection delete asks for confirmation and undo restores the full batch',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final first = await repository.createTask(title: 'Delete first');
      final second = await repository.createTask(title: 'Delete second');
      await repository.createTask(title: 'Keep me');

      await pumpTodoApp(tester, database: database);

      await tester.longPress(taskRowByTitle(first.title));
      await tester.pumpAndSettle();
      await scrollTodoCollectionUntilVisible(
        tester,
        taskRowByTitle(second.title, selectionMode: true),
      );
      await tester.tap(taskRowByTitle(second.title, selectionMode: true));
      await settleSingleTapGesture(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 tasks?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 tasks?'), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete tasks'));
      await tester.pumpAndSettle();

      final remaining = await repository.fetchTasks(const TodoFilter.inbox());
      expect(
        remaining.map((task) => task.title).toList(growable: false),
        <String>['Keep me'],
      );
      expect(find.text('Removed 2 tasks from the board.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(
        await repository.fetchTasks(const TodoFilter.inbox()),
        hasLength(3),
      );
      expect(find.textContaining('selected'), findsNothing);
    },
  );

  testWidgets('todo inbox shows a production empty state before tasks exist', (
    tester,
  ) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);

    await pumpTodoApp(tester, database: database);

    expect(find.text('New task'), findsOneWidget);
    expect(find.text('Work queue'), findsOneWidget);
    expect(textFieldByLabel('Search title or notes'), findsNothing);
  });

  testWidgets(
    'todo inbox does not overflow on a narrow Android-sized viewport with long task content',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(427, 952);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      await repository.createTask(
        title:
            'Review runtime diagnostics for the launch bundle before delivery',
        notes:
            'Capture the final screenshot, confirm the recording, and keep the handoff summary readable on Android.',
        priority: TodoPriority.high,
        dueAt: DateTime.utc(2026, 3, 22, 17),
      );

      await pumpTodoApp(tester, database: database);

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Review runtime diagnostics'), findsOneWidget);
    },
  );
}
