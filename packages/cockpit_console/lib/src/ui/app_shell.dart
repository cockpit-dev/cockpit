import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/screens/ai_chat_screen.dart';
import 'package:cockpit_console/src/ui/screens/dashboard_screen.dart';
import 'package:cockpit_console/src/ui/screens/documents_screen.dart';
import 'package:cockpit_console/src/ui/screens/operations_screen.dart';
import 'package:cockpit_console/src/ui/screens/runs_screen.dart';
import 'package:cockpit_console/src/ui/screens/targets_screen.dart';
import 'package:cockpit_console/src/ui/screens/workspaces_screen.dart';
import 'package:cockpit_console/src/ui/widgets/sidebar.dart';
import 'package:cockpit_console/src/ui/widgets/status_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The main application shell: sidebar + routed content area + status bar.
///
/// Uses a Riverpod-backed indexed navigation model (no Router) since the
/// console is a single-window desktop app. Each nav destination maps to a
/// screen builder. The content area is responsive: the sidebar collapses to
/// an icon rail below 1000px.
final class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                const Sidebar(),
                Container(width: 1, color: theme.dividerColor),
                Expanded(child: _buildContent(current)),
              ],
            ),
          ),
          const StatusBar(),
        ],
      ),
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
