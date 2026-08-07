import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Navigation destinations for the console sidebar.
///
/// Each destination carries a [LucideIcons] data point for rendering.
enum ConsoleNavDestination {
  dashboard(label: 'Dashboard', icon: LucideIcons.layoutDashboard),
  workspaces(label: 'Projects', icon: LucideIcons.folderOpen),
  targets(label: 'Apps & devices', icon: LucideIcons.smartphone),
  documents(label: 'Tests', icon: LucideIcons.fileText),
  runs(label: 'Test runs', icon: LucideIcons.playCircle),
  operations(label: 'Actions', icon: LucideIcons.command),
  aiChat(label: 'AI Assistant', icon: LucideIcons.sparkles);

  const ConsoleNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
