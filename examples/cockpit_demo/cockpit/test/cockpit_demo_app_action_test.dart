import 'package:cockpit_demo/src/app/todo_app_service.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cockpit_bootstrap.dart'
    show cockpitDemoAppActions, cockpitDemoAppState;
import 'support/cockpit_demo_test_support.dart'
    show addCockpitDemoDatabaseTearDown;

void main() {
  testWidgets('appAction applies quick settings and describeApp reports them', (
    tester,
  ) async {
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);
    addTearDown(FlutterCockpit.dispose);

    TodoAppService? service;
    await tester.pumpWidget(
      FlutterCockpitApp(
        appStateProvider: (context) => cockpitDemoAppState(
          service: service,
          acceptance: false,
          acceptancePlatform: 'macos',
          defineFile: '',
          httpNetworkObserverEnabled: true,
          runtimeObserverEnabled: true,
        ),
        appActions: cockpitDemoAppActions(() => service),
        child: CockpitDemoApp(
          database: database,
          navigatorObservers: <NavigatorObserver>[
            FlutterCockpit.createNavigatorObserver(),
          ],
          onServiceReady: (ready) => service = ready,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final root = tester.state<FlutterCockpitRootState>(
      find.byType(FlutterCockpitRoot),
    );
    final executor = root.createCommandExecutor();

    Future<Map<String, Object?>> describe() async {
      final result = await executor.execute(
        CockpitCommand(
          commandId: 'describe-demo',
          commandType: CockpitCommandType.describeApp,
        ),
      );
      expect(result.success, isTrue, reason: result.error?.message);
      return result.appState!;
    }

    expect((await describe())['actions'], <String>[
      'setCompactMode',
      'setSortMode',
      'setThemeMode',
    ]);

    final theme = await executor.execute(
      CockpitCommand(
        commandId: 'action-theme',
        commandType: CockpitCommandType.appAction,
        parameters: const <String, Object?>{
          'action': 'setThemeMode',
          'arguments': <String, Object?>{'mode': 'dark'},
        },
      ),
    );
    expect(theme.success, isTrue, reason: theme.error?.message);
    expect(theme.actionResult, <String, Object?>{'themeMode': 'dark'});
    expect((await describe())['themeMode'], 'dark');

    final sort = await executor.execute(
      CockpitCommand(
        commandId: 'action-sort',
        commandType: CockpitCommandType.appAction,
        parameters: const <String, Object?>{
          'action': 'setSortMode',
          'arguments': <String, Object?>{'mode': 'priority'},
        },
      ),
    );
    expect(sort.success, isTrue, reason: sort.error?.message);
    expect((await describe())['sortMode'], 'priority');

    final compact = await executor.execute(
      CockpitCommand(
        commandId: 'action-compact',
        commandType: CockpitCommandType.appAction,
        parameters: const <String, Object?>{
          'action': 'setCompactMode',
          'arguments': <String, Object?>{'enabled': true},
        },
      ),
    );
    expect(compact.success, isTrue, reason: compact.error?.message);
    expect((await describe())['compactMode'], isTrue);

    final invalid = await executor.execute(
      CockpitCommand(
        commandId: 'action-invalid-theme',
        commandType: CockpitCommandType.appAction,
        parameters: const <String, Object?>{
          'action': 'setThemeMode',
          'arguments': <String, Object?>{'mode': 'solarized'},
        },
      ),
    );
    expect(invalid.success, isFalse);
    expect(invalid.error?.code, 'appActionFailed');
    expect(invalid.error?.message, contains('system, light, dark'));

    final unknown = await executor.execute(
      CockpitCommand(
        commandId: 'action-unknown',
        commandType: CockpitCommandType.appAction,
        parameters: const <String, Object?>{'action': 'setLocale'},
      ),
    );
    expect(unknown.success, isFalse);
    expect(unknown.error?.code, 'appActionNotFound');
    expect(
      unknown.error?.message,
      contains('setCompactMode, setSortMode, setThemeMode'),
    );
  });
}
