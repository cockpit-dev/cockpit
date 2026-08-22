import 'package:cockpit_console/i18n/console_localization.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/app_shell.dart';
import 'package:cockpit_console/src/ui/widgets/console_shell_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  setUpAll(initializeConsoleLocalization);
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  test('uses locale-aware singular and plural forms', () async {
    expect(t.sessions.refreshFailed(n: 1), 'Could not refresh 1 project.');
    expect(t.sessions.refreshFailed(n: 2), 'Could not refresh 2 projects.');

    await LocaleSettings.setLocale(AppLocale.zhCn);
    expect(t.sessions.refreshFailed(n: 1), '1 个项目刷新失败。');
    expect(t.sessions.refreshFailed(n: 2), '2 个项目刷新失败。');
  });

  testWidgets('system locale resolves Simplified Chinese', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('zh', 'CN'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await tester.runAsync(LocaleSettings.useDeviceLocale);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(builder: (context) => Text(context.t.sessions.title)),
        ),
      ),
    );

    expect(LocaleSettings.currentLocale, AppLocale.zhCn);
    expect(find.text('实时会话'), findsOneWidget);
  });

  testWidgets('Simplified Chinese app shell fits a narrow window', (
    tester,
  ) async {
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.zhCn));
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          child: MaterialApp(
            theme: ConsoleTheme.build(Brightness.light),
            home: const AppShell(),
          ),
        ),
      ),
    );

    final open = tester.widget<IconButton>(
      find.byKey(const ValueKey(ConsoleNavigationIds.toggle)),
    );
    open.onPressed!.call();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('项目'), findsWidgets);
    expect(find.text('实时会话'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
