import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/app_shell.dart';
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
      ConsoleNavigationMode.railDrawer,
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

  testWidgets('rail exposes a bottom control that expands navigation', (
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
                  onToggleNavigation: () {
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
    expect(find.byTooltip('Projects'), findsOneWidget);
    expect(find.text('Projects'), findsNothing);
    final collapsedProjectsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('Projects')),
        matching: find.byType(Icon),
      ),
    );
    expect(
      collapsedProjectsIcon.size,
      ConsoleShellLayoutStyle.navigationRailIconSize,
    );
    expect(
      tester.getCenter(find.byType(Image).first).dx,
      closeTo(ConsoleShellLayoutStyle.sidebarRailWidth / 2, 0.01),
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey(ConsoleNavigationIds.toggle)))
          .dy,
      greaterThan(
        tester
            .getCenter(find.byKey(const ValueKey(ConsoleNavigationIds.theme)))
            .dy,
      ),
    );

    await tester.tap(find.byTooltip('Expand navigation'));
    await tester.pump();

    expect(find.byTooltip('Collapse navigation'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    final expandedProjectsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('Projects')),
        matching: find.byType(Icon),
      ),
    );
    expect(
      expandedProjectsIcon.size,
      ConsoleShellLayoutStyle.navigationIconSize,
    );
    expect(tester.widget<Image>(find.byType(Image).first).width, 40);
    expect(
      tester
          .getCenter(find.byKey(const ValueKey(ConsoleNavigationIds.toggle)))
          .dy,
      greaterThan(tester.getCenter(find.byKey(const ValueKey('Projects'))).dy),
    );
  });

  testWidgets('direct drawer activation replaces the body and closes', (
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
    final projects = tester.widget<InkWell>(
      find.byKey(const ValueKey('Projects')),
    );
    projects.onTap!.call();
    await tester.pump(const Duration(milliseconds: 300));

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

  testWidgets('narrow app shell opens its navigation drawer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ConsoleTheme.build(Brightness.light),
          home: const AppShell(),
        ),
      ),
    );

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.byKey(const ValueKey('nav-menu')), findsNothing);
    expect(find.byTooltip('Open navigation'), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(tester.widget<Sidebar>(find.byType(Sidebar)).collapsed, isTrue);

    final open = tester.widget<IconButton>(
      find.byKey(const ValueKey(ConsoleNavigationIds.toggle)),
    );
    open.onPressed!.call();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scaffold.isDrawerOpen, isTrue);
    expect(find.byType(Sidebar), findsNWidgets(2));
    expect(find.byTooltip('Close navigation'), findsOneWidget);
    expect(find.bySemanticsLabel('Projects'), findsOneWidget);
    expect(
      tester.widget<Drawer>(find.byType(Drawer)).width,
      ConsoleShellLayoutStyle.drawerWidth,
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey(ConsoleNavigationIds.close)))
          .dy,
      greaterThan(
        tester
            .getCenter(
              find.descendant(
                of: find.byType(Drawer),
                matching: find.byKey(const ValueKey('Projects')),
              ),
            )
            .dy,
      ),
    );

    final close = tester.widget<IconButton>(
      find.byKey(const ValueKey(ConsoleNavigationIds.close)),
    );
    close.onPressed!.call();
    await tester.pump(const Duration(milliseconds: 300));
    expect(scaffold.isDrawerOpen, isFalse);
  });
}
