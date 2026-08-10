import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/screens/ai_chat_screen.dart';
import 'package:cockpit_console/src/ui/screens/dashboard_screen.dart';
import 'package:cockpit_console/src/ui/screens/documents_screen.dart';
import 'package:cockpit_console/src/ui/screens/operations_screen.dart';
import 'package:cockpit_console/src/ui/screens/runs_screen.dart';
import 'package:cockpit_console/src/ui/screens/targets_screen.dart';
import 'package:cockpit_console/src/ui/screens/workspaces_screen.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/console_shell_header.dart';
import 'package:cockpit_console/src/ui/widgets/sidebar.dart';
import 'package:cockpit_console/src/ui/widgets/status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The main application shell: sidebar + routed content area + status bar.
///
/// Uses a Riverpod-backed indexed navigation model (no Router) since the
/// console is a single-window desktop app. Each nav destination maps to a
/// screen builder. Every width keeps persistent navigation: wide and medium
/// windows toggle between a sidebar and icon rail, while narrow windows keep
/// the rail and open the expanded sidebar as a drawer from its bottom action.
final class AppShell extends HookConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navProvider);
    final theme = Theme.of(context);
    final collapsedOverride = useState<bool?>(null);
    final drawerOpen = useState(false);
    final scaffoldKey = useMemoized(GlobalKey<ScaffoldState>.new);

    return LayoutBuilder(
      builder: (context, constraints) {
        final navigationMode = ConsoleShellLayoutStyle.navigationMode(
          constraints.maxWidth,
        );
        final useDrawer = navigationMode == ConsoleNavigationMode.railDrawer;
        final defaultCollapsed = navigationMode == ConsoleNavigationMode.rail;
        final collapsed = collapsedOverride.value ?? defaultCollapsed;

        return Scaffold(
          key: scaffoldKey,
          onDrawerChanged: useDrawer ? (open) => drawerOpen.value = open : null,
          drawer: useDrawer
              ? Drawer(
                  width: ConsoleShellLayoutStyle.drawerWidth,
                  elevation: 0,
                  backgroundColor: theme.scaffoldBackgroundColor,
                  clipBehavior: Clip.antiAlias,
                  shape: ConsoleShapes.drawer(
                    side: BorderSide(color: theme.dividerColor),
                  ),
                  child: Builder(
                    builder: (drawerContext) => Sidebar(
                      collapsed: false,
                      drawer: true,
                      onToggleNavigation: () =>
                          Navigator.of(drawerContext).pop(),
                      onDestinationSelected: () =>
                          Navigator.of(drawerContext).pop(),
                    ),
                  ),
                )
              : null,
          body: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      excluding: useDrawer && drawerOpen.value,
                      child: Sidebar(
                        collapsed: useDrawer || collapsed,
                        opensDrawer: useDrawer,
                        onToggleNavigation: useDrawer
                            ? () => scaffoldKey.currentState?.openDrawer()
                            : () => collapsedOverride.value = !collapsed,
                      ),
                    ),
                    Container(width: 1, color: theme.dividerColor),
                    Expanded(child: _buildContent(current)),
                  ],
                ),
              ),
              const StatusBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(ConsoleNavDestination dest) {
    return switch (dest) {
      ConsoleNavDestination.dashboard => const DashboardScreen(),
      ConsoleNavDestination.workspaces => const WorkspacesScreen(),
      ConsoleNavDestination.targets => const TargetsScreen(),
      ConsoleNavDestination.documents => const DocumentsScreen(),
      ConsoleNavDestination.runs => const RunsScreen(),
      ConsoleNavDestination.operations => const OperationsScreen(),
      ConsoleNavDestination.aiChat => const AiChatScreen(),
    };
  }
}
