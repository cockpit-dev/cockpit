import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('route-only snapshots skip native target discovery', (
    tester,
  ) async {
    var discoveryVisits = 0;
    FlutterCockpit.initialize(
      FlutterCockpitConfiguration(
        initialRouteName: '/inbox',
        discoveryPolicy: CockpitDiscoveryPolicy(
          isIgnoredSubtree: (element) {
            discoveryVisits += 1;
            return false;
          },
        ),
      ),
    );

    final rootKey = GlobalKey<FlutterCockpitRootState>();
    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        child: const MaterialApp(home: Scaffold(body: Text('Inbox'))),
      ),
    );
    await tester.pump();

    discoveryVisits = 0;
    final snapshot = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(maxTargets: 0),
    );

    expect(snapshot.routeName, '/inbox');
    expect(snapshot.visibleTargets, isEmpty);
    expect(discoveryVisits, 0);
  });

  testWidgets(
    'FlutterCockpitRoot discovers native widget signals without explicit target wrappers',
    (tester) async {
      FlutterCockpit.initialize(
        const FlutterCockpitConfiguration(initialRouteName: '/'),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();
      final controller = TextEditingController();
      var tapCount = 0;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  const Text('Inbox'),
                  Semantics(
                    label: 'Create task',
                    hint: 'Opens the task editor',
                    child: Tooltip(
                      message: 'Create a task',
                      child: TextButton(
                        key: const ValueKey<String>('create-task-button'),
                        onPressed: () => tapCount += 1,
                        child: const Text('Add task'),
                      ),
                    ),
                  ),
                  TextField(
                    key: const ValueKey<String>('task-input'),
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Task title'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final live = rootKey.currentState!.snapshot();
      final createButton = live.visibleTargets.firstWhere(
        (target) => target.keyValue == 'create-task-button',
      );
      final textField = live.visibleTargets.firstWhere(
        (target) => target.keyValue == 'task-input',
      );

      expect(
        live.visibleTargets.map((target) => target.text),
        contains('Inbox'),
      );
      expect(createButton.text, 'Add task');
      expect(createButton.tooltip, 'Create a task');
      expect(createButton.semanticId, 'Create task');
      expect(createButton.ancestors, isEmpty);
      expect(createButton.supportedCommands, contains(CockpitCommandType.tap));
      expect(
        textField.supportedCommands,
        contains(CockpitCommandType.enterText),
      );

      final executor = InAppCockpitCommandExecutor(
        registry: FlutterCockpit.binding.registry,
        snapshotProvider: rootKey.currentState!.snapshot,
      );

      final tapResult = await executor.execute(
        CockpitCommand(
          commandId: 'tap-create-task',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(key: 'create-task-button'),
        ),
      );
      await tester.pump();
      expect(tapResult.success, isTrue);
      expect(tapCount, 1);

      final enterTextResult = await executor.execute(
        CockpitCommand(
          commandId: 'enter-task-title',
          commandType: CockpitCommandType.enterText,
          locator: const CockpitLocator(key: 'task-input'),
          parameters: const <String, Object?>{'text': 'Review pull request'},
        ),
      );
      await tester.pump();
      expect(enterTextResult.success, isTrue);
      expect(controller.text, 'Review pull request');
    },
  );

  testWidgets(
    'semanticId locator matches Semantics.identifier before label text',
    (tester) async {
      FlutterCockpit.initialize(
        const FlutterCockpitConfiguration(initialRouteName: '/'),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();
      var tapCount = 0;

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: Semantics(
                identifier: 'activity.open.latest',
                label: 'Latest recording',
                button: true,
                child: TextButton(
                  onPressed: () => tapCount += 1,
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final live = rootKey.currentState!.snapshot();
      expect(
        live.visibleTargets.map((target) => target.semanticId),
        contains('activity.open.latest'),
      );

      final executor = InAppCockpitCommandExecutor(
        registry: FlutterCockpit.binding.registry,
        snapshotProvider: rootKey.currentState!.snapshot,
      );

      final result = await executor.execute(
        CockpitCommand(
          commandId: 'tap-latest-activity',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(semanticId: 'activity.open.latest'),
        ),
      );
      await tester.pump();

      expect(result.success, isTrue);
      expect(tapCount, 1);
      expect(
        result.locatorResolution,
        const CockpitLocatorResolution(
          matchedKind: CockpitLocatorKind.semanticId,
          matchedValue: 'activity.open.latest',
        ),
      );
    },
  );

  testWidgets('FlutterCockpitRoot can escalate snapshot detail on demand', (
    tester,
  ) async {
    FlutterCockpit.initialize(
      const FlutterCockpitConfiguration(initialRouteName: '/'),
    );

    final rootKey = GlobalKey<FlutterCockpitRootState>();

    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        child: MaterialApp(
          navigatorObservers: <NavigatorObserver>[
            FlutterCockpit.navigatorObserver,
          ],
          home: Scaffold(
            body: Center(
              child: CockpitTargetNode(
                registrationId: 'home.open_form_button',
                cockpitId: 'open_form_button',
                text: 'Open form',
                typeName: 'ElevatedButton',
                supportedCommands: const <CockpitCommandType>{
                  CockpitCommandType.tap,
                },
                onTap: () {},
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Open form'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final live = rootKey.currentState!.snapshot();
    final investigate = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions.investigate(),
    );

    final liveTarget = live.visibleTargets.firstWhere(
      (target) => target.cockpitId == 'open_form_button',
    );
    final investigateTarget = investigate.visibleTargets.firstWhere(
      (target) => target.cockpitId == 'open_form_button',
    );

    expect(liveTarget.layout, isNull);
    expect(investigateTarget.layout, isNotNull);
    expect(investigateTarget.ancestors, isNotEmpty);
    expect(investigate.summary?.ancestorSummariesIncluded, isTrue);
  });

  testWidgets(
    'FlutterCockpitRoot exposes passive text inside actionable containers for text assertions',
    (tester) async {
      FlutterCockpit.initialize(
        const FlutterCockpitConfiguration(initialRouteName: '/'),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: InkWell(
                key: const ValueKey<String>('task-row'),
                onTap: () {},
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Review diagnostics'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final live = rootKey.currentState!.snapshot();
      expect(
        live.visibleTargets.any((target) => target.keyValue == 'task-row'),
        isTrue,
      );
      expect(
        live.visibleTargets.any(
          (target) => target.text == 'Review diagnostics',
        ),
        isTrue,
      );

      final executor = InAppCockpitCommandExecutor(
        registry: FlutterCockpit.binding.registry,
        snapshotProvider: rootKey.currentState!.snapshot,
      );
      final result = await executor.execute(
        CockpitCommand(
          commandId: 'assert-inline-text',
          commandType: CockpitCommandType.assertText,
          parameters: const <String, Object?>{'text': 'Review diagnostics'},
        ),
      );

      expect(result.success, isTrue);
    },
  );

  testWidgets('targeted snapshots find mounted targets outside the viewport', (
    tester,
  ) async {
    final rootKey = GlobalKey<CockpitSurfaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: CockpitSurface(
              key: rootKey,
              routeName: '/logs',
              child: const SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    Text('Visible target'),
                    SizedBox(height: 600),
                    Text(
                      'gesture:longPress',
                      key: ValueKey<String>('gesture-status'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final live = rootKey.currentState!.snapshot();
    final byText = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        query: 'gesture:longPress',
        maxTargets: 10,
      ),
    );
    final byKey = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        query: '@gesture-status',
        maxTargets: 10,
      ),
    );
    final missing = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        query: '@missing-target',
        maxTargets: 10,
      ),
    );

    expect(
      live.visibleTargets.any((target) => target.keyValue == 'gesture-status'),
      isFalse,
    );
    expect(byText.visibleTargets.single.text, 'gesture:longPress');
    expect(byKey.visibleTargets.single.keyValue, 'gesture-status');
    expect(missing.visibleTargets, isNotEmpty);
    expect(missing.visibleTargets.every((target) => target.visible), isTrue);
  });

  testWidgets(
    'FlutterCockpitRoot can attach network snapshots from an injected observer',
    (tester) async {
      final observer = _FakeNetworkObserver();
      FlutterCockpit.initialize(
        FlutterCockpitConfiguration(
          initialRouteName: '/',
          networkObserver: observer,
        ),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Workspace'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final liveSnapshot = rootKey.currentState!.snapshot();
      final investigateSnapshot = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.investigate(),
      );

      expect(liveSnapshot.network, isNull);
      expect(investigateSnapshot.network, isNotNull);
      expect(investigateSnapshot.network!.entries, hasLength(1));
      expect(investigateSnapshot.network!.entries.single.method, 'POST');
      expect(investigateSnapshot.network!.entries.single.statusCode, 200);
      expect(
        investigateSnapshot.network!.entries.single.requestBodyPreview,
        contains('sync'),
      );
      expect(
        investigateSnapshot.network!.entries.single.responseBodyPreview,
        contains('status'),
      );
    },
  );

  testWidgets(
    'FlutterCockpitRoot provisions an auto-configured http network observer',
    (tester) async {
      FlutterCockpit.initialize(
        const FlutterCockpitConfiguration(
          initialRouteName: '/',
          httpNetworkObserver: CockpitHttpNetworkObserverConfiguration(
            maxRetainedEntries: 8,
            maxBodyBytes: 256,
          ),
        ),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: const Scaffold(body: Center(child: Text('Workspace'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final observer =
          FlutterCockpit.binding.networkObserver as CockpitHttpNetworkObserver?;

      expect(observer, isNotNull);
      expect(observer, isA<CockpitHttpNetworkObserver>());
      expect(observer!.maxRetainedEntries, 8);
      expect(observer.maxBodyBytes, 256);
    },
  );

  testWidgets(
    'FlutterCockpitRoot can execute a long press against a discovered native target',
    (tester) async {
      FlutterCockpit.initialize(
        const FlutterCockpitConfiguration(initialRouteName: '/'),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();
      var longPressCount = 0;

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: GestureDetector(
                key: const ValueKey<String>('gesture-card'),
                onLongPress: () => longPressCount += 1,
                child: const SizedBox(
                  width: 180,
                  height: 180,
                  child: Center(child: Text('Focus board')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final executor = InAppCockpitCommandExecutor(
        registry: FlutterCockpit.binding.registry,
        snapshotProvider: rootKey.currentState!.snapshot,
        gestureHandler: rootKey.currentState!.performGesture,
      );

      final result = await executor.execute(
        CockpitCommand(
          commandId: 'long-press-board',
          commandType: CockpitCommandType.longPress,
          locator: const CockpitLocator(key: 'gesture-card'),
        ),
      );
      await tester.pumpAndSettle();

      expect(result.success, isTrue);
      expect(longPressCount, 1);
    },
  );

  testWidgets(
    'FlutterCockpitRoot excludes inactive route targets after navigator push',
    (tester) async {
      FlutterCockpit.initialize(
        const FlutterCockpitConfiguration(initialRouteName: '/inbox'),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            routes: <String, WidgetBuilder>{
              '/settings': (context) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Settings')),
                  body: Center(
                    child: FilledButton(
                      key: const ValueKey<String>('settings-save-button'),
                      onPressed: () {},
                      child: const Text('Save changes'),
                    ),
                  ),
                );
              },
            },
            home: Builder(
              builder: (context) {
                return Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    key: const ValueKey<String>('fab-add-task'),
                    onPressed: () {},
                    label: const Text('Create task'),
                  ),
                  body: Center(
                    child: TextButton(
                      key: const ValueKey<String>('open-settings-button'),
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/settings'),
                      child: const Text('Open settings'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        rootKey.currentState!.snapshot().visibleTargets.any(
          (target) => target.keyValue == 'fab-add-task',
        ),
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open-settings-button')),
      );
      await tester.pumpAndSettle();

      final snapshot = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.investigate(),
      );
      expect(snapshot.routeName, '/settings');
      expect(
        snapshot.visibleTargets.any(
          (target) => target.keyValue == 'settings-save-button',
        ),
        isTrue,
      );
      expect(
        snapshot.visibleTargets.any(
          (target) => target.keyValue == 'fab-add-task',
        ),
        isFalse,
      );
    },
  );
}

final class _FakeNetworkObserver implements CockpitNetworkObserver {
  @override
  void clear() {}

  @override
  Future<bool> waitForIdle({
    Duration quietWindow = const Duration(milliseconds: 150),
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return true;
  }

  @override
  CockpitNetworkSnapshot snapshot({
    int maxEntries = 10,
    CockpitNetworkQuery query = const CockpitNetworkQuery(),
  }) {
    return CockpitNetworkSnapshot(
      totalEntryCount: 1,
      failureCount: 0,
      entries: <CockpitNetworkEntry>[
        CockpitNetworkEntry(
          requestId: 'net-1',
          method: 'POST',
          uri: 'https://api.example.dev/sync',
          startedAt: DateTime.utc(2026, 3, 21, 0, 0),
          durationMs: 118,
          statusCode: 200,
          requestBodyPreview: '{"probe":"sync"}',
          responseBodyPreview: '{"status":"ok"}',
        ),
      ],
      capturedEntryCount: 1,
      query: query,
    );
  }
}
