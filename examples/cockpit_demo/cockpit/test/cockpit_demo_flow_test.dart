import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';

import 'support/cockpit_demo_test_support.dart';

void main() {
  test('ships a dedicated cockpit development entrypoint', () {
    expect(resolveCockpitDemoFile('main.dart').existsSync(), isTrue);
    expect(
      resolveCockpitDemoFile('cockpit_bootstrap.dart').existsSync(),
      isTrue,
    );
  });

  testWidgets(
    'captures validation failure while preserving an explicit Cockpit step',
    (tester) async {
      var tick = 0;
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      final controller = CockpitSessionController(
        sessionId: 'todo-flow-failure-session',
        taskId: 'todo-flow-failure-task',
        platform: 'ios',
        now: () => DateTime.utc(2026, 3, 20, 8, 0, tick++),
      );

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: FlutterCockpitConfiguration(
            sessionController: controller,
          ),
          database: database,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save task'));
      await tester.pump();
      FlutterCockpit.recordStep(
        actionType: 'validation_attempt',
        actionArgs: const <String, Object?>{'route': '/editor'},
      );

      final bundle = controller.finishWithFailure(
        environment: const CockpitEnvironment(
          platform: 'ios',
          flutterVersion: '3.38.9',
          dartVersion: '3.10.8',
        ),
        failureSummary: 'Task title validation failed.',
      );

      expect(find.text('Task title is required.'), findsOneWidget);
      expect(bundle.manifest.status, CockpitTaskStatus.failed);
      expect(bundle.steps, isNotEmpty);
    },
  );

  testWidgets(
    'keeps programmatic navigation stable across service-driven rebuilds',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: const FlutterCockpitConfiguration(
            initialRouteName: '/inbox',
          ),
          database: database,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      await tester.tap(find.text('New task'));
      await tester.pumpAndSettle();

      expect(FlutterCockpit.binding.currentRouteName.value, '/editor');
      expect(textFieldByLabel('Task title'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(FlutterCockpit.binding.currentRouteName.value, '/settings');
      expect(find.text('Settings'), findsWidgets);
    },
  );

  testWidgets(
    'executes AI-style Cockpit commands through discovered controls',
    (tester) async {
      final database = CockpitDemoDatabase.inMemory();
      addCockpitDemoDatabaseTearDown(tester, database);

      await tester.pumpWidget(
        buildCockpitDemoApp(
          configuration: const FlutterCockpitConfiguration(
            initialRouteName: '/inbox',
          ),
          database: database,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final executor = InAppCockpitCommandExecutor(
        registry: FlutterCockpit.binding.registry,
        waitTickHandler: tester.pump,
        interactionPolicy: const CockpitInteractionPolicy(
          preActionVisualDelay: Duration.zero,
          actionVisualDelay: Duration.zero,
          routeTransitionVisualDelay: Duration.zero,
          recordingActionVisualDelay: Duration.zero,
        ),
      );

      final openEditor = await executor.execute(
        CockpitCommand(
          commandId: 'test-open-editor',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(text: 'New task', route: '/inbox'),
        ),
      );

      expect(openEditor.success, isTrue);
      expect(openEditor.snapshot?['routeName'], '/editor');
      expect(textFieldByLabel('Task title'), findsOneWidget);

      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();

      final openSettings = await executor.execute(
        CockpitCommand(
          commandId: 'test-open-settings',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(tooltip: 'Settings', route: '/inbox'),
        ),
      );

      expect(openSettings.success, isTrue);
      expect(openSettings.snapshot?['routeName'], '/settings');
      expect(find.text('Settings'), findsWidgets);
    },
  );
}
