import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The left navigation sidebar — Linear-style compact rail with labels.
///
/// Shows the daemon status indicator at the top and nav items below. A theme
/// toggle sits at the bottom. Width is fixed at 200px for a dense, productive
/// layout. The sidebar collapses to a 56px icon rail below 1000px viewport.
final class Sidebar extends HookConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemonState = ref.watch(daemonProvider);
    final themeMode = ref.watch(themeProvider);
    final collapsed = MediaQuery.sizeOf(context).width < 1000;

    final theme = Theme.of(context);
    final running = daemonState.running;
    final healthy = daemonState.healthy;
    final statusColor = !running
        ? theme.colorScheme.onSurfaceVariant
        : healthy
        ? context.consoleColors.success
        : context.consoleColors.warning;
    final statusLabel = !running
        ? 'Offline'
        : healthy
        ? 'Connected'
        : 'Degraded';

    return Container(
      width: collapsed ? 56 : 200,
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(collapsed: collapsed),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final dest in ConsoleNavDestination.values)
                  _NavItem(destination: dest, collapsed: collapsed),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: collapsed
                ? const EdgeInsets.symmetric(vertical: 10)
                : const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: collapsed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: statusLabel,
                        child: Semantics(
                          label: statusLabel,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: running && healthy
                                  ? [
                                      BoxShadow(
                                        color: statusColor.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        icon: Icon(
                          themeMode == ThemeMode.dark
                              ? LucideIcons.sun
                              : LucideIcons.moon,
                          size: 15,
                        ),
                        onPressed: () => ref
                            .read(themeProvider.notifier)
                            .toggle(theme.brightness),
                        tooltip: 'Toggle theme',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(28, 28),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Tooltip(
                        message: statusLabel,
                        child: Semantics(
                          label: statusLabel,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: running && healthy
                                  ? [
                                      BoxShadow(
                                        color: statusColor.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          themeMode == ThemeMode.dark
                              ? LucideIcons.sun
                              : LucideIcons.moon,
                          size: 15,
                        ),
                        onPressed: () => ref
                            .read(themeProvider.notifier)
                            .toggle(theme.brightness),
                        tooltip: 'Toggle theme',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(28, 28),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: const Center(child: _BrandMark(includeSemantics: true)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          const _BrandMark(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cockpit',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Console',
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _BrandMark extends StatelessWidget {
  const _BrandMark({this.includeSemantics = false});

  final bool includeSemantics;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/cockpit_console_app_icon.png',
      width: 24,
      height: 24,
      filterQuality: FilterQuality.high,
      semanticLabel: includeSemantics ? 'Cockpit Console' : null,
      excludeFromSemantics: !includeSemantics,
    );
  }
}

final class _NavItem extends HookConsumerWidget {
  const _NavItem({required this.destination, required this.collapsed});

  final ConsoleNavDestination destination;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navProvider);
    final selected = current == destination;
    final hovered = useState(false);
    final theme = Theme.of(context);

    final bg = selected
        ? theme.colorScheme.surfaceContainerHigh
        : hovered.value
        ? theme.colorScheme.surfaceContainer
        : Colors.transparent;
    final fg = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    void navigate() {
      ref.read(navProvider.notifier).go(destination);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: Tooltip(
        message: destination.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 300),
        showDuration: const Duration(milliseconds: 0),
        child: Semantics(
          button: true,
          selected: selected,
          label: destination.label,
          excludeSemantics: true,
          onTap: navigate,
          child: InkWell(
            key: ValueKey(destination.label),
            onTap: navigate,
            customBorder: ConsoleShapes.border(
              radius: ConsoleShapes.smallRadius,
            ),
            child: Container(
              height: 30,
              margin: const EdgeInsets.only(bottom: 1),
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 8),
              decoration: ConsoleShapes.decoration(
                color: bg,
                radius: ConsoleShapes.smallRadius,
              ),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(destination.icon, size: 16, color: fg),
                  if (!collapsed) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        destination.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: fg,
                          height: 1.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
