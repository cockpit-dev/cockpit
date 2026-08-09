import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/console_shell_header.dart';
import 'package:cockpit_console/src/ui/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('navigation mode follows the shell breakpoints', () {
    expect(
      ConsoleShellLayoutStyle.navigationMode(719),
      ConsoleNavigationMode.drawer,
    );
    expect(
      ConsoleShellLayoutStyle.navigationMode(720),
      ConsoleNavigationMode.rail,
    );
    expect(
      ConsoleShellLayoutStyle.navigationMode(999),
      ConsoleNavigationMode.rail,
    );
    expect(
      ConsoleShellLayoutStyle.navigationMode(1000),
      ConsoleNavigationMode.sidebar,
    );
  });

  testWidgets('rail exposes a header control that expands navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var collapsed = true;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topLeft,
                child: Sidebar(
                  collapsed: collapsed,
                  onToggleCollapsed: () {
                    setState(() => collapsed = !collapsed);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Expand navigation'), findsOneWidget);
    expect(find.text('Projects'), findsNothing);

    await tester.tap(find.byTooltip('Expand navigation'));
    await tester.pump();

    expect(find.byTooltip('Collapse navigation'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('drawer closes before its destination replaces the body', (
    tester,
  ) async {
    const menuKey = ValueKey('menu');
    const currentDestinationKey = ValueKey('current-destination');

    await tester.binding.setSurfaceSize(const Size(640, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.light),
          home: Consumer(
            builder: (context, ref, child) {
              final current = ref.watch(navProvider);
              return Scaffold(
                drawer: Drawer(
                  child: Builder(
                    builder: (drawerContext) => Sidebar(
                      collapsed: false,
                      drawer: true,
                      onDestinationSelected: () =>
                          Navigator.of(drawerContext).pop(),
                    ),
                  ),
                ),
                body: Builder(
                  builder: (scaffoldContext) => Column(
                    children: [
                      IconButton(
                        key: menuKey,
                        onPressed: Scaffold.of(scaffoldContext).openDrawer,
                        icon: const Icon(Icons.menu),
                      ),
                      Text(current.label, key: currentDestinationKey),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(menuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Projects')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.byKey(currentDestinationKey)).data,
      ConsoleNavDestination.workspaces.label,
    );
    expect(
      tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
      isFalse,
    );
  });
}
