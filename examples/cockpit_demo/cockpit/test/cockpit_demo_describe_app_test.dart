import 'package:cockpit_demo/src/app/todo_app_service.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cockpit_bootstrap.dart' show cockpitDemoAppState;
import 'support/cockpit_demo_test_support.dart'
    show addCockpitDemoDatabaseTearDown;

void main() {
  testWidgets('describeApp reports launch configuration and live todo state', (
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
    final result = await executor.execute(
      CockpitCommand(
        commandId: 'describe-demo',
        commandType: CockpitCommandType.describeApp,
      ),
    );

    expect(result.success, isTrue, reason: result.error?.message);
    final appState = result.appState!;
    expect(appState['acceptance'], isFalse);
    expect(appState['acceptancePlatform'], 'macos');
    expect(appState['httpNetworkObserverEnabled'], isTrue);
    expect(appState['runtimeObserverEnabled'], isTrue);
    expect(appState['syncStatus'], 'idle');
    expect(appState['taskCount'], 0);
    expect(appState['activeTaskCount'], 0);
  });
}
