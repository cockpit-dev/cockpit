import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the framework-derived settings served by `describeApp`: locale,
/// effective brightness, theme color, text scale, and platform are read live
/// from the widget tree, layered under the app-authored provider values.
void main() {
  testWidgets('describeApp derives the standard app settings', (tester) async {
    FlutterCockpit.initialize(
      const FlutterCockpitConfiguration(initialRouteName: '/'),
    );
    addTearDown(FlutterCockpit.dispose);

    final rootKey = GlobalKey<FlutterCockpitRootState>();
    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        child: MaterialApp(
          locale: const Locale('en', 'GB'),
          supportedLocales: const <Locale>[Locale('en', 'GB')],
          themeMode: ThemeMode.dark,
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.dark(primary: Color(0xFF12AB34)),
          ),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final executor = rootKey.currentState!.createCommandExecutor();
    final result = await executor.execute(
      CockpitCommand(
        commandId: 'describe-derived',
        commandType: CockpitCommandType.describeApp,
      ),
    );
    expect(result.success, isTrue, reason: result.error?.message);
    final appState = result.appState!;
    expect(appState['locale'], 'en_GB');
    expect(appState['brightness'], 'dark');
    expect(appState['themeColor'], '#12AB34');
    expect(appState['platform'], isA<String>());
    expect(appState['textScale'], 1.0);
  });

  testWidgets('app-authored keys win over derived settings', (tester) async {
    FlutterCockpit.initialize(
      const FlutterCockpitConfiguration(initialRouteName: '/'),
    );
    addTearDown(FlutterCockpit.dispose);

    final rootKey = GlobalKey<FlutterCockpitRootState>();
    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        appStateProvider: (context) => const <String, Object?>{
          'locale': 'app-authored-locale',
        },
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(colorScheme: const ColorScheme.light()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final executor = rootKey.currentState!.createCommandExecutor();
    final result = await executor.execute(
      CockpitCommand(
        commandId: 'describe-override',
        commandType: CockpitCommandType.describeApp,
      ),
    );
    expect(result.success, isTrue, reason: result.error?.message);
    expect(result.appState!['locale'], 'app-authored-locale');
    expect(result.appState!['brightness'], 'light');
  });

  testWidgets('derived settings track live theme changes', (tester) async {
    FlutterCockpit.initialize(
      const FlutterCockpitConfiguration(initialRouteName: '/'),
    );
    addTearDown(FlutterCockpit.dispose);

    final rootKey = GlobalKey<FlutterCockpitRootState>();
    var themeMode = ThemeMode.light;
    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        child: MaterialApp(
          themeMode: themeMode,
          theme: ThemeData(colorScheme: const ColorScheme.light()),
          darkTheme: ThemeData(colorScheme: const ColorScheme.dark()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<String?> describeBrightness() async {
      final result = await rootKey.currentState!
          .createCommandExecutor()
          .execute(
            CockpitCommand(
              commandId: 'describe-brightness',
              commandType: CockpitCommandType.describeApp,
            ),
          );
      expect(result.success, isTrue, reason: result.error?.message);
      return result.appState!['brightness'] as String?;
    }

    expect(await describeBrightness(), 'light');

    themeMode = ThemeMode.dark;
    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        child: MaterialApp(
          themeMode: themeMode,
          theme: ThemeData(colorScheme: const ColorScheme.light()),
          darkTheme: ThemeData(colorScheme: const ColorScheme.dark()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await describeBrightness(), 'dark');
  });

  testWidgets('describeApp works without an app state provider', (
    tester,
  ) async {
    FlutterCockpit.initialize(
      const FlutterCockpitConfiguration(initialRouteName: '/'),
    );
    addTearDown(FlutterCockpit.dispose);

    final rootKey = GlobalKey<FlutterCockpitRootState>();
    await tester.pumpWidget(
      FlutterCockpitRoot(
        key: rootKey,
        child: MaterialApp(
          locale: const Locale('en', 'GB'),
          supportedLocales: const <Locale>[Locale('en', 'GB')],
          theme: ThemeData(colorScheme: const ColorScheme.light()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final executor = rootKey.currentState!.createCommandExecutor();
    final result = await executor.execute(
      CockpitCommand(
        commandId: 'describe-no-provider',
        commandType: CockpitCommandType.describeApp,
      ),
    );
    expect(result.success, isTrue, reason: result.error?.message);
    expect(result.appState!['locale'], 'en_GB');
    expect(result.appState!['brightness'], 'light');
  });
}
