import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_demo/src/data/todo_repository.dart';
import 'package:cockpit_demo/src/model/todo_filter.dart';

import 'support/cockpit_demo_test_support.dart';

void main() {
  testWidgets('discovers command lab status text by stable test id', (
    tester,
  ) async {
    final registry = CockpitTargetRegistry(routeName: '/command-lab');
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);

    await tester.pumpWidget(
      buildCockpitDemoApp(
        configuration: FlutterCockpitConfiguration(
          initialRouteName: '/command-lab',
          registry: registry,
        ),
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    final resolution = registry.resolve(
      const CockpitLocator(key: 'lab-gesture-status'),
    );
    expect(
      resolution.isSuccess,
      isTrue,
      reason: registry.routeDiagnostics().toString(),
    );
    expect(resolution.target?.text, 'gesture:idle');

    final result =
        await InAppCockpitCommandExecutor(
          registry: registry,
          waitTickHandler: tester.pump,
        ).execute(
          CockpitCommand(
            commandId: 'assert-command-lab-idle',
            commandType: CockpitCommandType.assertText,
            locator: const CockpitLocator(key: 'lab-gesture-status'),
            parameters: const <String, Object?>{'text': 'gesture:idle'},
            timeoutMs: 1000,
          ),
        );
    expect(result.success, isTrue, reason: result.error?.toJson().toString());
  });

  testWidgets(
    'reveals long settings ledger content through the in-app executor',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'settings-scroll-session',
        taskId: 'settings-scroll-task',
        platform: 'ios',
      );
      final registry = CockpitTargetRegistry(routeName: '/settings');
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            initialRouteName: '/settings',
            sessionController: controller,
            registry: registry,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final executor = InAppCockpitCommandExecutor(
        registry: registry,
        snapshotProvider: surfaceState.snapshot,
        waitTickHandler: tester.pump,
        scrollStepHandler:
            ({
              required reverse,
              required viewportFraction,
              scrollableKey,
              targetLocator,
              scrollableLocator,
              required duration,
              required gestureProfile,
              required continuous,
              required postScrollEnsureVisible,
            }) {
              return surfaceState.scrollByViewport(
                reverse: reverse,
                viewportFraction: viewportFraction,
                scrollableKey: scrollableKey,
                targetLocator: targetLocator,
                scrollableLocator: scrollableLocator,
                duration: duration,
                gestureProfile: gestureProfile,
                continuous: continuous,
                postScrollEnsureVisible: postScrollEnsureVisible,
              );
            },
        ensureVisibleHandler:
            ({
              required locator,
              required duration,
              required alignment,
              required padding,
              required offset,
            }) {
              return surfaceState.ensureLocatorVisible(
                locator,
                duration: duration,
                alignment: alignment,
                padding: padding,
                offset: offset,
              );
            },
      );

      final result = await executor.execute(
        CockpitCommand(
          commandId: 'cmd-scroll-settings-ledger',
          commandType: CockpitCommandType.scrollUntilVisible,
          locator: const CockpitLocator(text: 'Acceptance bundles'),
          parameters: const <String, Object?>{
            'maxScrolls': 8,
            'viewportFraction': 0.8,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(result.success, isTrue, reason: result.error?.message);
      expect(find.text('Acceptance bundles'), findsOneWidget);
    },
  );

  testWidgets('reveals diagnostics controls through the in-app executor', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 844) * 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = CockpitSessionController(
      sessionId: 'settings-diagnostics-scroll-session',
      taskId: 'settings-diagnostics-scroll-task',
      platform: 'ios',
    );
    final registry = CockpitTargetRegistry(routeName: '/settings');
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);

    await tester.pumpWidget(
      buildCockpitDemoApp(
        configuration: FlutterCockpitConfiguration(
          initialRouteName: '/settings',
          sessionController: controller,
          registry: registry,
        ),
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final executor = InAppCockpitCommandExecutor(
      registry: registry,
      snapshotProvider: surfaceState.snapshot,
      waitTickHandler: tester.pump,
      scrollStepHandler:
          ({
            required reverse,
            required viewportFraction,
            scrollableKey,
            targetLocator,
            scrollableLocator,
            required duration,
            required gestureProfile,
            required continuous,
            required postScrollEnsureVisible,
          }) {
            return surfaceState.scrollByViewport(
              reverse: reverse,
              viewportFraction: viewportFraction,
              scrollableKey: scrollableKey,
              targetLocator: targetLocator,
              scrollableLocator: scrollableLocator,
              duration: duration,
              gestureProfile: gestureProfile,
              continuous: continuous,
              postScrollEnsureVisible: postScrollEnsureVisible,
            );
          },
      ensureVisibleHandler:
          ({
            required locator,
            required duration,
            required alignment,
            required padding,
            required offset,
          }) {
            return surfaceState.ensureLocatorVisible(
              locator,
              duration: duration,
              alignment: alignment,
              padding: padding,
              offset: offset,
            );
          },
    );

    final revealSyncCheck = await executor.execute(
      CockpitCommand(
        commandId: 'cmd-scroll-settings-sync-check',
        commandType: CockpitCommandType.scrollUntilVisible,
        locator: const CockpitLocator(text: 'Run check'),
        parameters: const <String, Object?>{
          'maxScrolls': 8,
          'viewportFraction': 0.82,
          'continuous': true,
          'durationPerStepMs': 220,
        },
      ),
    );
    await tester.pumpAndSettle();

    final runSyncCheck = await executor.execute(
      CockpitCommand(
        commandId: 'cmd-run-sync-check',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Run check'),
      ),
    );
    await tester.pumpAndSettle();

    final result = await executor.execute(
      CockpitCommand(
        commandId: 'cmd-scroll-settings-diagnostics',
        commandType: CockpitCommandType.scrollUntilVisible,
        locator: const CockpitLocator(text: 'Emit debug log'),
        parameters: const <String, Object?>{
          'maxScrolls': 8,
          'viewportFraction': 0.82,
          'continuous': true,
          'durationPerStepMs': 220,
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      revealSyncCheck.success,
      isTrue,
      reason:
          '${revealSyncCheck.error?.message}\n${revealSyncCheck.error?.details}',
    );
    expect(runSyncCheck.success, isTrue, reason: runSyncCheck.error?.message);
    expect(result.success, isTrue, reason: result.error?.message);
    expect(find.text('Emit debug log'), findsOneWidget);
  });

  testWidgets(
    'discovers native Todo targets and executes the creation flow through the in-app executor',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'capture-session',
        taskId: 'capture-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/inbox');
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            sessionController: controller,
            registry: registry,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      InAppCockpitCommandExecutor executorForCurrentRoute() {
        final surfaceState = tester.state<CockpitSurfaceState>(
          find.byType(CockpitSurface),
        );
        return InAppCockpitCommandExecutor(
          registry: registry,
          snapshotProvider: surfaceState.snapshot,
          waitTickHandler: tester.pump,
          scrollStepHandler:
              ({
                required reverse,
                required viewportFraction,
                scrollableKey,
                targetLocator,
                scrollableLocator,
                required duration,
                required gestureProfile,
                required continuous,
                required postScrollEnsureVisible,
              }) {
                return surfaceState.scrollByViewport(
                  reverse: reverse,
                  viewportFraction: viewportFraction,
                  scrollableKey: scrollableKey,
                  targetLocator: targetLocator,
                  scrollableLocator: scrollableLocator,
                  duration: duration,
                  gestureProfile: gestureProfile,
                  continuous: continuous,
                  postScrollEnsureVisible: postScrollEnsureVisible,
                );
              },
        );
      }

      expect(
        registry.resolve(const CockpitLocator(text: 'New task')).isSuccess,
        isTrue,
      );

      final openEditorCommand = CockpitCommand(
        commandId: 'cmd-open-editor',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'New task'),
      );
      final openEditorResult = await executorForCurrentRoute().execute(
        openEditorCommand,
      );
      expect(
        openEditorResult.success,
        isTrue,
        reason: openEditorResult.error?.message,
      );
      controller.recordCommandResult(openEditorCommand, openEditorResult);
      await tester.pumpAndSettle();

      final enterTitleCommand = CockpitCommand(
        commandId: 'cmd-enter-title',
        commandType: CockpitCommandType.enterText,
        locator: const CockpitLocator(type: 'TextField'),
        parameters: const <String, Object?>{'text': 'Review diagnostics'},
      );
      final enterTitleResult = await executorForCurrentRoute().execute(
        enterTitleCommand,
      );
      expect(
        enterTitleResult.success,
        isTrue,
        reason: enterTitleResult.error?.message,
      );
      controller.recordCommandResult(enterTitleCommand, enterTitleResult);
      await tester.pumpAndSettle();

      final saveTaskCommand = CockpitCommand(
        commandId: 'cmd-save-task',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Save task'),
      );
      final saveTaskResult = await executorForCurrentRoute().execute(
        saveTaskCommand,
      );
      expect(
        saveTaskResult.success,
        isTrue,
        reason: saveTaskResult.error?.message,
      );
      controller.recordCommandResult(saveTaskCommand, saveTaskResult);
      await tester.pumpAndSettle();
      await settleAfterTaskSave(tester);

      final createdTasks = await database.select(database.tasks).get();
      final createdTask = createdTasks.single;

      final revealTaskCommand = CockpitCommand(
        commandId: 'cmd-scroll-to-task',
        commandType: CockpitCommandType.scrollUntilVisible,
        locator: CockpitLocator(
          text: createdTask.title,
          type: 'InkWell',
          matchMode: CockpitTextMatchMode.contains,
        ),
        parameters: const <String, Object?>{
          'maxScrolls': 8,
          'viewportFraction': 0.72,
        },
      );
      controller.recordCommandResult(
        revealTaskCommand,
        await executorForCurrentRoute().execute(revealTaskCommand),
      );
      await tester.pumpAndSettle();

      final assertTaskVisibleCommand = CockpitCommand(
        commandId: 'cmd-assert-task-visible',
        commandType: CockpitCommandType.assertVisible,
        locator: CockpitLocator(
          text: createdTask.title,
          type: 'InkWell',
          matchMode: CockpitTextMatchMode.contains,
        ),
      );
      controller.recordCommandResult(
        assertTaskVisibleCommand,
        await executorForCurrentRoute().execute(assertTaskVisibleCommand),
      );

      expect(taskRowByTitle(createdTask.title), findsOneWidget);

      final bundle = controller.finish(
        environment: const CockpitEnvironment(
          platform: 'android',
          flutterVersion: '3.38.9',
          dartVersion: '3.10.8',
        ),
        capabilitiesUsed: const <String>['inAppControl'],
      );

      expect(bundle.manifest.commandCount, 5);
      expect(
        bundle.steps
            .where((step) => step.commandType != null)
            .map((step) => step.status),
        everyElement(CockpitCommandStatus.succeeded),
      );
      expect(
        bundle.steps
            .where((step) => step.commandType != null)
            .map((step) => step.commandType),
        <CockpitCommandType>[
          CockpitCommandType.tap,
          CockpitCommandType.enterText,
          CockpitCommandType.tap,
          CockpitCommandType.scrollUntilVisible,
          CockpitCommandType.assertVisible,
        ],
      );
    },
  );

  testWidgets(
    'executes rapid due-date selection through the real editor layout',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = CockpitSessionController(
        sessionId: 'rapid-editor-session',
        taskId: 'rapid-editor-task',
        platform: 'web',
      );
      final registry = CockpitTargetRegistry(routeName: '/inbox');
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            sessionController: controller,
            registry: registry,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      InAppCockpitCommandExecutor executorForCurrentRoute() {
        final surfaceState = tester.state<CockpitSurfaceState>(
          find.byType(CockpitSurface),
        );
        return InAppCockpitCommandExecutor(
          registry: registry,
          snapshotProvider: surfaceState.snapshot,
          waitTickHandler: tester.pump,
          scrollStepHandler:
              ({
                required reverse,
                required viewportFraction,
                scrollableKey,
                targetLocator,
                scrollableLocator,
                required duration,
                required gestureProfile,
                required continuous,
                required postScrollEnsureVisible,
              }) {
                return surfaceState.scrollByViewport(
                  reverse: reverse,
                  viewportFraction: viewportFraction,
                  scrollableKey: scrollableKey,
                  targetLocator: targetLocator,
                  scrollableLocator: scrollableLocator,
                  duration: duration,
                  gestureProfile: gestureProfile,
                  continuous: continuous,
                  postScrollEnsureVisible: postScrollEnsureVisible,
                );
              },
          ensureVisibleHandler:
              ({
                required locator,
                required duration,
                required alignment,
                required padding,
                required offset,
              }) {
                return surfaceState.ensureLocatorVisible(
                  locator,
                  duration: duration,
                  alignment: alignment,
                  padding: padding,
                  offset: offset,
                );
              },
        );
      }

      Future<void> execute(CockpitCommand command) async {
        final result = await executorForCurrentRoute().execute(command);
        await tester.pumpAndSettle();
        expect(
          result.success,
          isTrue,
          reason: result.error?.toJson().toString(),
        );
      }

      await execute(
        CockpitCommand(
          commandId: 'rapid-open-editor',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(text: 'New task', route: '/inbox'),
          parameters: const <String, Object?>{'expectedRouteName': '/editor'},
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-enter-title',
          commandType: CockpitCommandType.enterText,
          locator: const CockpitLocator(
            text: 'Task title',
            type: 'TextField',
            ancestor: CockpitLocator(route: '/editor'),
          ),
          parameters: const <String, Object?>{'text': 'Rapid due date proof'},
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-reveal-notes',
          commandType: CockpitCommandType.scrollUntilVisible,
          locator: const CockpitLocator(
            text: 'Notes',
            route: '/editor',
            ancestor: CockpitLocator(route: '/editor'),
          ),
          parameters: const <String, Object?>{
            'maxScrolls': 6,
            'viewportFraction': 0.62,
            'continuous': true,
            'durationPerStepMs': 180,
            'revealAlignment': 'center',
          },
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-enter-notes',
          commandType: CockpitCommandType.enterText,
          locator: const CockpitLocator(
            text: 'Notes',
            type: 'TextField',
            ancestor: CockpitLocator(route: '/editor'),
          ),
          parameters: const <String, Object?>{
            'text': 'Created during the rapid AI development verifier.',
          },
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-dismiss-keyboard',
          commandType: CockpitCommandType.dismissKeyboard,
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-reveal-high-priority',
          commandType: CockpitCommandType.scrollUntilVisible,
          locator: const CockpitLocator(
            semanticId: 'task-editor-priority-high',
            text: 'HIGH',
            route: '/editor',
            ancestor: CockpitLocator(route: '/editor'),
          ),
          parameters: const <String, Object?>{
            'maxScrolls': 6,
            'viewportFraction': 0.62,
            'continuous': true,
            'durationPerStepMs': 180,
            'revealAlignment': 'center',
          },
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-select-high-priority',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(
            semanticId: 'task-editor-priority-high',
            text: 'HIGH',
            route: '/editor',
            ancestor: CockpitLocator(route: '/editor'),
          ),
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-reveal-due-date-section',
          commandType: CockpitCommandType.scrollUntilVisible,
          locator: const CockpitLocator(
            semanticId: 'task-editor-due-section',
            route: '/editor',
            ancestor: CockpitLocator(route: '/editor'),
          ),
          parameters: const <String, Object?>{
            'maxScrolls': 6,
            'viewportFraction': 0.38,
            'continuous': true,
            'durationPerStepMs': 180,
            'revealAlignment': 'center',
          },
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-reveal-today',
          commandType: CockpitCommandType.scrollUntilVisible,
          locator: const CockpitLocator(
            semanticId: 'task-editor-due-today',
            text: 'Today',
            route: '/editor',
            ancestor: CockpitLocator(route: '/editor'),
          ),
          parameters: const <String, Object?>{
            'maxScrolls': 8,
            'viewportFraction': 0.52,
            'continuous': true,
            'durationPerStepMs': 180,
            'revealAlignment': 'center',
            'revealPaddingPx': 24,
          },
        ),
      );
      await execute(
        CockpitCommand(
          commandId: 'rapid-select-today',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(
            semanticId: 'task-editor-due-today',
            text: 'Today',
            route: '/editor',
            ancestor: CockpitLocator(route: '/editor'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'creates a follow-up task through the in-app executor with label-based input targeting',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'follow-up-capture-session',
        taskId: 'follow-up-capture-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/inbox');
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final sourceTask = await repository.createTask(
        title: 'Verify relay tracing',
        notes: 'Carry the backend context forward.',
      );

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            sessionController: controller,
            registry: registry,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      InAppCockpitCommandExecutor executorForCurrentRoute() {
        final surfaceState = tester.state<CockpitSurfaceState>(
          find.byType(CockpitSurface),
        );
        return InAppCockpitCommandExecutor(
          registry: registry,
          snapshotProvider: surfaceState.snapshot,
          waitTickHandler: tester.pump,
          scrollStepHandler:
              ({
                required reverse,
                required viewportFraction,
                scrollableKey,
                targetLocator,
                scrollableLocator,
                required duration,
                required gestureProfile,
                required continuous,
                required postScrollEnsureVisible,
              }) {
                return surfaceState.scrollByViewport(
                  reverse: reverse,
                  viewportFraction: viewportFraction,
                  scrollableKey: scrollableKey,
                  targetLocator: targetLocator,
                  scrollableLocator: scrollableLocator,
                  duration: duration,
                  gestureProfile: gestureProfile,
                  continuous: continuous,
                  postScrollEnsureVisible: postScrollEnsureVisible,
                );
              },
        );
      }

      final openTaskCommand = CockpitCommand(
        commandId: 'cmd-open-source-task',
        commandType: CockpitCommandType.tap,
        locator: CockpitLocator(
          text: sourceTask.title,
          type: 'InkWell',
          matchMode: CockpitTextMatchMode.contains,
        ),
      );
      final openTaskResult = await executorForCurrentRoute().execute(
        openTaskCommand,
      );
      expect(
        openTaskResult.success,
        isTrue,
        reason: openTaskResult.error?.message,
      );
      controller.recordCommandResult(openTaskCommand, openTaskResult);
      await tester.pumpAndSettle();

      final openFollowUpSheetCommand = CockpitCommand(
        commandId: 'cmd-open-follow-up-sheet',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(tooltip: 'Create follow-up'),
      );
      final openFollowUpSheetResult = await executorForCurrentRoute().execute(
        openFollowUpSheetCommand,
      );
      expect(
        openFollowUpSheetResult.success,
        isTrue,
        reason: openFollowUpSheetResult.error?.message,
      );
      controller.recordCommandResult(
        openFollowUpSheetCommand,
        openFollowUpSheetResult,
      );
      await tester.pumpAndSettle();

      final enterTitleCommand = CockpitCommand(
        commandId: 'cmd-enter-follow-up-title',
        commandType: CockpitCommandType.enterText,
        locator: const CockpitLocator(
          text: 'Follow-up title',
          type: 'TextField',
        ),
        parameters: const <String, Object?>{
          'text': 'Verify relay tracing follow-up',
        },
      );
      final enterTitleResult = await executorForCurrentRoute().execute(
        enterTitleCommand,
      );
      expect(
        enterTitleResult.success,
        isTrue,
        reason: enterTitleResult.error?.message,
      );
      controller.recordCommandResult(enterTitleCommand, enterTitleResult);
      await tester.pumpAndSettle();

      final createFollowUpCommand = CockpitCommand(
        commandId: 'cmd-create-follow-up',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Create follow-up'),
      );
      final createFollowUpResult = await executorForCurrentRoute().execute(
        createFollowUpCommand,
      );
      expect(
        createFollowUpResult.success,
        isTrue,
        reason: createFollowUpResult.error?.message,
      );
      controller.recordCommandResult(
        createFollowUpCommand,
        createFollowUpResult,
      );
      await tester.pumpAndSettle();
      await settleAfterTaskSave(tester);

      expect(find.text('Verify relay tracing follow-up'), findsWidgets);
      final tasks = await repository.fetchTasks(const TodoFilter.inbox());
      expect(
        tasks.any((task) => task.title == 'Verify relay tracing follow-up'),
        isTrue,
      );
    },
  );

  testWidgets(
    'creates and applies a shared batch tag through the in-app executor',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'batch-tag-capture-session',
        taskId: 'batch-tag-capture-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/inbox');
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final first = await repository.createTask(title: 'Tag first');
      final second = await repository.createTask(title: 'Tag second');

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            sessionController: controller,
            registry: registry,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      InAppCockpitCommandExecutor executorForCurrentRoute() {
        final surfaceState = tester.state<CockpitSurfaceState>(
          find.byType(CockpitSurface),
        );
        return InAppCockpitCommandExecutor(
          registry: registry,
          snapshotProvider: surfaceState.snapshot,
          waitTickHandler: tester.pump,
          scrollStepHandler:
              ({
                required reverse,
                required viewportFraction,
                scrollableKey,
                targetLocator,
                scrollableLocator,
                required duration,
                required gestureProfile,
                required continuous,
                required postScrollEnsureVisible,
              }) {
                return surfaceState.scrollByViewport(
                  reverse: reverse,
                  viewportFraction: viewportFraction,
                  scrollableKey: scrollableKey,
                  targetLocator: targetLocator,
                  scrollableLocator: scrollableLocator,
                  duration: duration,
                  gestureProfile: gestureProfile,
                  continuous: continuous,
                  postScrollEnsureVisible: postScrollEnsureVisible,
                );
              },
        );
      }

      final selectFirstCommand = CockpitCommand(
        commandId: 'cmd-select-first-task',
        commandType: CockpitCommandType.longPress,
        locator: CockpitLocator(
          text: first.title,
          type: 'InkWell',
          matchMode: CockpitTextMatchMode.contains,
        ),
      );
      final selectFirstResult = await executorForCurrentRoute().execute(
        selectFirstCommand,
      );
      expect(
        selectFirstResult.success,
        isTrue,
        reason: selectFirstResult.error?.message,
      );
      controller.recordCommandResult(selectFirstCommand, selectFirstResult);
      await tester.pumpAndSettle();

      final selectAllCommand = CockpitCommand(
        commandId: 'cmd-select-all-results',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'All results'),
      );
      final selectAllResult = await executorForCurrentRoute().execute(
        selectAllCommand,
      );
      expect(
        selectAllResult.success,
        isTrue,
        reason: selectAllResult.error?.message,
      );
      controller.recordCommandResult(selectAllCommand, selectAllResult);
      await tester.pumpAndSettle();

      final openTagsCommand = CockpitCommand(
        commandId: 'cmd-open-batch-tags',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Tags', type: 'OutlinedButton'),
      );
      final openTagsResult = await executorForCurrentRoute().execute(
        openTagsCommand,
      );
      expect(
        openTagsResult.success,
        isTrue,
        reason: openTagsResult.error?.message,
      );
      controller.recordCommandResult(openTagsCommand, openTagsResult);
      await tester.pumpAndSettle();

      final enterTagNameCommand = CockpitCommand(
        commandId: 'cmd-enter-tag-name',
        commandType: CockpitCommandType.enterText,
        locator: const CockpitLocator(text: 'New tag', type: 'TextField'),
        parameters: const <String, Object?>{'text': 'Ops'},
      );
      final enterTagNameResult = await executorForCurrentRoute().execute(
        enterTagNameCommand,
      );
      expect(
        enterTagNameResult.success,
        isTrue,
        reason: enterTagNameResult.error?.message,
      );
      controller.recordCommandResult(enterTagNameCommand, enterTagNameResult);
      await tester.pumpAndSettle();

      final createTagCommand = CockpitCommand(
        commandId: 'cmd-create-batch-tag',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Create tag'),
      );
      final createTagResult = await executorForCurrentRoute().execute(
        createTagCommand,
      );
      expect(
        createTagResult.success,
        isTrue,
        reason: createTagResult.error?.message,
      );
      controller.recordCommandResult(createTagCommand, createTagResult);
      await tester.pumpAndSettle();

      final applyTagsCommand = CockpitCommand(
        commandId: 'cmd-apply-batch-tags',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Apply tags'),
      );
      final applyTagsResult = await executorForCurrentRoute().execute(
        applyTagsCommand,
      );
      expect(
        applyTagsResult.success,
        isTrue,
        reason: applyTagsResult.error?.message,
      );
      controller.recordCommandResult(applyTagsCommand, applyTagsResult);
      await tester.pumpAndSettle();

      final tasks = await repository.fetchTasks(const TodoFilter.inbox());
      expect(
        tasks
            .where((task) => task.id == first.id || task.id == second.id)
            .every((task) => task.tags.map((tag) => tag.name).contains('Ops')),
        isTrue,
      );
    },
  );

  testWidgets(
    'duplicates selected tasks through the in-app executor with label-based input targeting',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'batch-duplicate-capture-session',
        taskId: 'batch-duplicate-capture-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/inbox');
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);
      final repository = TodoRepository(database);
      final first = await repository.createTask(title: 'Duplicate first');
      await repository.createTask(title: 'Duplicate second');

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            sessionController: controller,
            registry: registry,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      InAppCockpitCommandExecutor executorForCurrentRoute() {
        final surfaceState = tester.state<CockpitSurfaceState>(
          find.byType(CockpitSurface),
        );
        return InAppCockpitCommandExecutor(
          registry: registry,
          snapshotProvider: surfaceState.snapshot,
          waitTickHandler: tester.pump,
          scrollStepHandler:
              ({
                required reverse,
                required viewportFraction,
                scrollableKey,
                targetLocator,
                scrollableLocator,
                required duration,
                required gestureProfile,
                required continuous,
                required postScrollEnsureVisible,
              }) {
                return surfaceState.scrollByViewport(
                  reverse: reverse,
                  viewportFraction: viewportFraction,
                  scrollableKey: scrollableKey,
                  targetLocator: targetLocator,
                  scrollableLocator: scrollableLocator,
                  duration: duration,
                  gestureProfile: gestureProfile,
                  continuous: continuous,
                  postScrollEnsureVisible: postScrollEnsureVisible,
                );
              },
        );
      }

      final selectFirstCommand = CockpitCommand(
        commandId: 'cmd-select-duplicate-first-task',
        commandType: CockpitCommandType.longPress,
        locator: CockpitLocator(
          text: first.title,
          type: 'InkWell',
          matchMode: CockpitTextMatchMode.contains,
        ),
      );
      final selectFirstResult = await executorForCurrentRoute().execute(
        selectFirstCommand,
      );
      expect(
        selectFirstResult.success,
        isTrue,
        reason: selectFirstResult.error?.message,
      );
      controller.recordCommandResult(selectFirstCommand, selectFirstResult);
      await tester.pumpAndSettle();

      final selectAllCommand = CockpitCommand(
        commandId: 'cmd-select-duplicate-all-results',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'All results'),
      );
      final selectAllResult = await executorForCurrentRoute().execute(
        selectAllCommand,
      );
      expect(
        selectAllResult.success,
        isTrue,
        reason: selectAllResult.error?.message,
      );
      controller.recordCommandResult(selectAllCommand, selectAllResult);
      await tester.pumpAndSettle();

      final openDuplicateCommand = CockpitCommand(
        commandId: 'cmd-open-duplicate-sheet',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(
          text: 'Duplicate',
          type: 'OutlinedButton',
        ),
      );
      final openDuplicateResult = await executorForCurrentRoute().execute(
        openDuplicateCommand,
      );
      expect(
        openDuplicateResult.success,
        isTrue,
        reason: openDuplicateResult.error?.message,
      );
      controller.recordCommandResult(openDuplicateCommand, openDuplicateResult);
      await tester.pumpAndSettle();

      final enterPrefixCommand = CockpitCommand(
        commandId: 'cmd-enter-duplicate-prefix',
        commandType: CockpitCommandType.enterText,
        locator: const CockpitLocator(text: 'Title prefix', type: 'TextField'),
        parameters: const <String, Object?>{'text': 'Copy'},
      );
      final enterPrefixResult = await executorForCurrentRoute().execute(
        enterPrefixCommand,
      );
      expect(
        enterPrefixResult.success,
        isTrue,
        reason: enterPrefixResult.error?.message,
      );
      controller.recordCommandResult(enterPrefixCommand, enterPrefixResult);
      await tester.pumpAndSettle();

      final createDuplicatesCommand = CockpitCommand(
        commandId: 'cmd-create-duplicates',
        commandType: CockpitCommandType.tap,
        locator: const CockpitLocator(text: 'Create duplicates'),
      );
      final createDuplicatesResult = await executorForCurrentRoute().execute(
        createDuplicatesCommand,
      );
      expect(
        createDuplicatesResult.success,
        isTrue,
        reason: createDuplicatesResult.error?.message,
      );
      controller.recordCommandResult(
        createDuplicatesCommand,
        createDuplicatesResult,
      );
      await tester.pumpAndSettle();

      final tasks = await repository.fetchTasks(const TodoFilter.inbox());
      expect(
        tasks.any((task) => task.title == 'Copy: Duplicate first'),
        isTrue,
      );
      expect(
        tasks.any((task) => task.title == 'Copy: Duplicate second'),
        isTrue,
      );
    },
  );
}
