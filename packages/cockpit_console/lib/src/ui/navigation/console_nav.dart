import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Navigation destinations for the console sidebar.
///
/// Each destination carries a [LucideIcons] data point for rendering.
enum ConsoleNavDestination {
  dashboard(icon: LucideIcons.layoutDashboard),
  workspaces(icon: LucideIcons.folderOpen),
  targets(icon: LucideIcons.smartphone),
  sessions(icon: LucideIcons.radio),
  documents(icon: LucideIcons.fileText),
  runs(icon: LucideIcons.playCircle),
  operations(icon: LucideIcons.command),
  aiChat(icon: LucideIcons.sparkles);

  const ConsoleNavDestination({required this.icon});

  final IconData icon;

  String label(Translations translations) => switch (this) {
    ConsoleNavDestination.dashboard => translations.nav.dashboard,
    ConsoleNavDestination.workspaces => translations.nav.projects,
    ConsoleNavDestination.targets => translations.nav.appsDevices,
    ConsoleNavDestination.sessions => translations.nav.liveSessions,
    ConsoleNavDestination.documents => translations.nav.tests,
    ConsoleNavDestination.runs => translations.nav.testRuns,
    ConsoleNavDestination.operations => translations.nav.actions,
    ConsoleNavDestination.aiChat => translations.nav.aiAssistant,
  };
}
