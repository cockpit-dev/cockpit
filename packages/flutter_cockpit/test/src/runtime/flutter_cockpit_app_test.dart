import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_runtime_tree_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(FlutterCockpit.dispose);

  test('FlutterCockpit.isInitialized reflects runtime lifecycle', () {
    expect(FlutterCockpit.isInitialized, isFalse);

    FlutterCockpit.ensureInitialized(
      const FlutterCockpitConfig(initialRouteName: '/ready'),
    );

    expect(FlutterCockpit.isInitialized, isTrue);

    FlutterCockpit.dispose();

    expect(FlutterCockpit.isInitialized, isFalse);
  });

  testWidgets(
    'FlutterCockpitApp provisions the runtime and renders through the cockpit root',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/inbox'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FlutterCockpitRoot), findsOneWidget);

      FlutterCockpit.recordStep(
        actionType: 'bootstrap',
        actionArgs: const <String, Object?>{'route': '/inbox'},
      );

      final bundle = FlutterCockpit.binding.sessionController.finish(
        environment: const CockpitEnvironment(
          platform: 'android',
          flutterVersion: '3.38.9',
          dartVersion: '3.10.8',
        ),
      );

      expect(bundle.steps, hasLength(1));
      expect(bundle.steps.single.actionType, 'bootstrap');
      expect(bundle.manifest.status, CockpitTaskStatus.completed);
    },
  );

  testWidgets(
    'FlutterCockpitApp does not recreate the binding on equivalent config rebuilds',
    (tester) async {
      const firstConfig = FlutterCockpitConfig(initialRouteName: '/inbox');

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: firstConfig,
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      final originalBinding = FlutterCockpit.binding;

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/inbox'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(identical(FlutterCockpit.binding, originalBinding), isTrue);
      expect(FlutterCockpit.binding.registry.routeName, '/inbox');
    },
  );

  testWidgets(
    'FlutterCockpit.setCurrentRouteName synchronizes the runtime route',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      FlutterCockpit.setCurrentRouteName(' /settings ');

      expect(FlutterCockpit.binding.currentRouteName.value, '/settings');
      expect(FlutterCockpit.binding.registry.routeName, '/settings');

      FlutterCockpit.setCurrentRouteName('   ');

      expect(FlutterCockpit.binding.currentRouteName.value, '/');
      expect(FlutterCockpit.binding.registry.routeName, '/');
    },
  );

  testWidgets(
    'FlutterCockpit.setCurrentRouteName preserves an explicit root route',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/inbox'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      FlutterCockpit.setCurrentRouteName('/');

      expect(FlutterCockpit.binding.currentRouteName.value, '/');
      expect(FlutterCockpit.binding.registry.routeName, '/');
    },
  );

  testWidgets(
    'bindRouteInformationProvider synchronizes Router-compatible locations',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/bootstrap'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      final provider = _TestRouteInformationProvider(
        RouteInformation(
          uri: Uri(scheme: '', path: '/home', query: 'tab=all'),
        ),
      );
      final unbind = FlutterCockpit.bindRouteInformationProvider(provider);
      final unbindSecond = FlutterCockpit.bindRouteInformationProvider(
        provider,
      );

      expect(FlutterCockpit.binding.currentRouteName.value, '/home?tab=all');
      provider.value = RouteInformation(uri: Uri(path: '/settings'));
      expect(FlutterCockpit.binding.currentRouteName.value, '/settings');

      unbindSecond();
      provider.value = RouteInformation(uri: Uri(path: '/profile'));
      expect(FlutterCockpit.binding.currentRouteName.value, '/profile');

      unbind();
      provider.value = RouteInformation(uri: Uri(path: '/ignored'));
      expect(FlutterCockpit.binding.currentRouteName.value, '/profile');
      provider.dispose();
    },
  );

  testWidgets(
    'FlutterCockpitRoot discovers a public Router provider without app changes',
    (tester) async {
      final provider = _TestRouteInformationProvider(
        RouteInformation(uri: Uri(path: '/router-home')),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        FlutterCockpitApp(
          config: const FlutterCockpitConfig(initialRouteName: '/bootstrap'),
          child: Router<Object?>(
            routeInformationProvider: provider,
            routeInformationParser: _TestRouteInformationParser(),
            routerDelegate: _TestRouterDelegate(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(FlutterCockpit.binding.currentRouteName.value, '/router-home');
      provider.value = RouteInformation(uri: Uri(path: '/router-settings'));
      await tester.pump();
      expect(FlutterCockpit.binding.currentRouteName.value, '/router-settings');
    },
  );

  testWidgets(
    'FlutterCockpitRoot discovers a Router mounted by a descendant rebuild',
    (tester) async {
      final provider = _TestRouteInformationProvider(
        RouteInformation(uri: Uri(path: '/delayed-router')),
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        FlutterCockpitApp(
          config: const FlutterCockpitConfig(initialRouteName: '/bootstrap'),
          child: _DelayedRouterHost(provider: provider),
        ),
      );

      expect(FlutterCockpit.binding.currentRouteName.value, '/bootstrap');

      // Exhaust the startup-frame retries so this also covers the backed-off
      // discovery path used by hosts that reveal their router later.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final host = tester.state<_DelayedRouterHostState>(
        find.byType(_DelayedRouterHost),
      );
      host.mountRouter();
      await tester.pump(const Duration(seconds: 1));

      expect(FlutterCockpit.binding.currentRouteName.value, '/delayed-router');
    },
  );

  testWidgets('FlutterCockpit.navigatorObserver normalizes route names', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterCockpitApp(
          config: const FlutterCockpitConfig(initialRouteName: '/'),
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            routes: <String, WidgetBuilder>{
              '/': (_) => _RoutePushButton(routeName: ' /details '),
              ' /details ': (_) => const Text('Details'),
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();

    expect(FlutterCockpit.binding.currentRouteName.value, '/details');
    expect(FlutterCockpit.binding.registry.routeName, '/details');
  });

  testWidgets(
    'discovers plain Navigator routes without requiring a production hook',
    (tester) async {
      await tester.pumpWidget(
        FlutterCockpitApp(
          config: const FlutterCockpitConfig(initialRouteName: '/inbox'),
          child: MaterialApp(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => switch (settings.name) {
                '/editor' => const Scaffold(body: Text('Editor screen')),
                _ => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/editor'),
                    child: const Text('Open editor'),
                  ),
                ),
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      rootState.snapshot();

      expect(FlutterCockpit.binding.currentRouteName.value, '/editor');
      expect(FlutterCockpit.binding.registry.routeName, '/editor');
    },
  );

  testWidgets('pops a visible plain Navigator without an observer', (
    tester,
  ) async {
    await tester.pumpWidget(
      FlutterCockpitApp(
        config: const FlutterCockpitConfig(initialRouteName: '/inbox'),
        child: MaterialApp(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => switch (settings.name) {
              '/editor' => const Scaffold(body: Text('Editor screen')),
              _ => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/editor'),
                  child: const Text('Open editor'),
                ),
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    final rootElement = tester.element(find.byType(FlutterCockpitRoot));
    final handled = await cockpitMaybePopCurrentNavigator(rootElement);
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets(
    'creates independent observers for nested navigators and restores parent route',
    (tester) async {
      await tester.pumpWidget(
        FlutterCockpitApp(
          config: const FlutterCockpitConfig(initialRouteName: '/shell'),
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: Navigator(
                observers: <NavigatorObserver>[
                  FlutterCockpit.createNavigatorObserver(),
                ],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/shell/home'),
                  builder: (context) => ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/shell/detail'),
                        builder: (context) => ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Pop detail'),
                        ),
                      ),
                    ),
                    child: const Text('Push detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(FlutterCockpit.binding.currentRouteName.value, '/shell/home');

      await tester.tap(find.text('Push detail'));
      await tester.pumpAndSettle();
      expect(FlutterCockpit.binding.currentRouteName.value, '/shell/detail');

      await tester.tap(find.text('Pop detail'));
      await tester.pumpAndSettle();
      expect(FlutterCockpit.binding.currentRouteName.value, '/shell/home');
    },
  );

  testWidgets(
    'tracks nested navigator routes when the shell installs an observer',
    (tester) async {
      await tester.pumpWidget(
        FlutterCockpitApp(
          config: const FlutterCockpitConfig(initialRouteName: '/shell'),
          child: MaterialApp(
            home: Scaffold(
              body: Navigator(
                observers: <NavigatorObserver>[
                  FlutterCockpit.createNavigatorObserver(),
                ],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/shell/home'),
                  builder: (context) => ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/shell/detail'),
                        builder: (context) => ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Pop detail'),
                        ),
                      ),
                    ),
                    child: const Text('Push detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(FlutterCockpit.binding.currentRouteName.value, '/shell/home');

      await tester.tap(find.text('Push detail'));
      await tester.pumpAndSettle();
      expect(FlutterCockpit.binding.currentRouteName.value, '/shell/detail');

      await tester.tap(find.text('Pop detail'));
      await tester.pumpAndSettle();
      expect(FlutterCockpit.binding.currentRouteName.value, '/shell/home');
    },
  );

  testWidgets(
    'FlutterCockpitApp ignores deferred route updates after the runtime is disposed',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: const FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/inbox'),
            child: _NavigatorProbeApp(),
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FlutterCockpitApp does not dispose the shared runtime by default on unmount',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(initialRouteName: '/inbox'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      final originalBinding = FlutterCockpit.binding;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(identical(FlutterCockpit.binding, originalBinding), isTrue);

      FlutterCockpit.dispose();
    },
  );

  testWidgets('FlutterCockpitApp can explicitly own and dispose the runtime', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterCockpitApp(
          ownsRuntime: true,
          config: FlutterCockpitConfig(initialRouteName: '/owned'),
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    final originalBinding = FlutterCockpit.binding;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(identical(FlutterCockpit.binding, originalBinding), isFalse);
  });

  testWidgets(
    'FlutterCockpitApp preserves the binding while applying updated runtime config',
    (tester) async {
      final firstController = CockpitSessionController(
        sessionId: 'first-session',
        taskId: 'first-task',
        platform: 'android',
      );
      final secondController = CockpitSessionController(
        sessionId: 'second-session',
        taskId: 'second-task',
        platform: 'ios',
      );
      final firstRegistry = CockpitTargetRegistry(routeName: '/inbox');
      final secondRegistry = CockpitTargetRegistry(routeName: '/settings');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig.fromRuntimeConfiguration(
              FlutterCockpitConfiguration(
                initialRouteName: '/inbox',
                registry: firstRegistry,
                sessionController: firstController,
                interactionPolicy: CockpitInteractionPolicy(
                  actionVisualDelay: Duration(milliseconds: 120),
                ),
              ),
            ),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      final originalBinding = FlutterCockpit.binding;
      expect(
        originalBinding.configuration.interactionPolicy.actionVisualDelay,
        const Duration(milliseconds: 120),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig.fromRuntimeConfiguration(
              FlutterCockpitConfiguration(
                initialRouteName: '/settings',
                registry: secondRegistry,
                sessionController: secondController,
                interactionPolicy: CockpitInteractionPolicy(
                  actionVisualDelay: Duration(milliseconds: 480),
                ),
              ),
            ),
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      expect(identical(FlutterCockpit.binding, originalBinding), isTrue);
      expect(
        FlutterCockpit
            .binding
            .configuration
            .interactionPolicy
            .actionVisualDelay,
        const Duration(milliseconds: 480),
      );
      expect(
        identical(FlutterCockpit.binding.registry, secondRegistry),
        isTrue,
      );
      expect(
        identical(FlutterCockpit.binding.sessionController, secondController),
        isTrue,
      );
      expect(FlutterCockpit.binding.registry.routeName, '/settings');
    },
  );

  test('FlutterCockpit.ensureInitialized bootstraps from app config', () {
    final binding = FlutterCockpit.ensureInitialized(
      const FlutterCockpitConfig(initialRouteName: '/settings'),
    );

    expect(binding.registry.routeName, '/settings');

    FlutterCockpit.dispose();
  });

  testWidgets(
    'FlutterCockpit.runApp bootstraps and mounts the cockpit root automatically',
    (tester) async {
      FlutterCockpit.runApp(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.shrink(),
        ),
        config: const FlutterCockpitConfig(initialRouteName: '/run-app'),
      );
      await tester.pump();

      expect(find.byType(FlutterCockpitRoot), findsOneWidget);
      expect(FlutterCockpit.binding.registry.routeName, '/run-app');

      FlutterCockpit.dispose();
    },
  );
}

final class _NavigatorProbeApp extends StatelessWidget {
  const _NavigatorProbeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: <NavigatorObserver>[FlutterCockpit.navigatorObserver],
      home: const SizedBox.shrink(),
    );
  }
}

final class _RoutePushButton extends StatelessWidget {
  const _RoutePushButton({required this.routeName});

  final String routeName;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(context).pushNamed(routeName),
      child: const Text('Open details'),
    );
  }
}

final class _TestRouteInformationParser
    extends RouteInformationParser<Object?> {
  @override
  Future<Object?> parseRouteInformation(RouteInformation routeInformation) {
    return Future<Object?>.value(routeInformation.uri.toString());
  }
}

final class _TestRouterDelegate extends RouterDelegate<Object?>
    with ChangeNotifier {
  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: Text('Router content'),
  );

  @override
  Object? get currentConfiguration => null;

  @override
  Future<void> setNewRoutePath(Object? configuration) async {}

  @override
  Future<bool> popRoute() => Future<bool>.value(false);
}

final class _DelayedRouterHost extends StatefulWidget {
  const _DelayedRouterHost({required this.provider});

  final RouteInformationProvider provider;

  @override
  State<_DelayedRouterHost> createState() => _DelayedRouterHostState();
}

final class _DelayedRouterHostState extends State<_DelayedRouterHost> {
  bool _showRouter = false;

  void mountRouter() {
    setState(() {
      _showRouter = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showRouter) {
      return const SizedBox.shrink();
    }
    return Router<Object?>(
      routeInformationProvider: widget.provider,
      routeInformationParser: _TestRouteInformationParser(),
      routerDelegate: _TestRouterDelegate(),
    );
  }
}

final class _TestRouteInformationProvider extends RouteInformationProvider
    with ChangeNotifier {
  _TestRouteInformationProvider(this._value);

  RouteInformation _value;

  @override
  RouteInformation get value => _value;

  set value(RouteInformation next) {
    _value = next;
    notifyListeners();
  }
}
