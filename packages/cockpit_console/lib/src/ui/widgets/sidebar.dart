import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/console_shell_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The left navigation sidebar — Linear-style compact rail with labels.
///
/// Shows the daemon status indicator at the top and nav items below. The shell
/// decides whether this instance is expanded, collapsed, or hosted in a
/// narrow-window drawer.
final class Sidebar extends HookConsumerWidget {
  const Sidebar({
    required this.collapsed,
    this.drawer = false,
    this.onToggleCollapsed,
    this.onClose,
    this.onDestinationSelected,
    super.key,
  });

  final bool collapsed;
  final bool drawer;
  final VoidCallback? onToggleCollapsed;
  final VoidCallback? onClose;
  final VoidCallback? onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemonState = ref.watch(daemonProvider);
    final themeMode = ref.watch(themeProvider);

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

    final statusIndicator = Tooltip(
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
                      color: statusColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
    final themeToggle = IconButton(
      icon: Icon(
        themeMode == ThemeMode.dark ? LucideIcons.sun : LucideIcons.moon,
        size: 15,
      ),
      onPressed: () =>
          ref.read(themeProvider.notifier).toggle(theme.brightness),
      tooltip: 'Toggle theme',
      style: IconButton.styleFrom(minimumSize: const Size.square(28)),
    );
    final toggleCollapsed = onToggleCollapsed == null
        ? null
        : IconButton(
            icon: Icon(
              collapsed
                  ? LucideIcons.panelLeftOpen
                  : LucideIcons.panelLeftClose,
              size: 15,
            ),
            onPressed: onToggleCollapsed,
            tooltip: collapsed ? 'Expand navigation' : 'Collapse navigation',
            style: IconButton.styleFrom(minimumSize: const Size.square(28)),
          );
    return Container(
      width: drawer
          ? null
          : collapsed
          ? ConsoleShellLayoutStyle.sidebarRailWidth
          : ConsoleShellLayoutStyle.sidebarWidth,
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(collapsed: collapsed, drawer: drawer, onClose: onClose),
          const ConsoleShellDivider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final dest in ConsoleNavDestination.values)
                  _NavItem(
                    destination: dest,
                    collapsed: collapsed,
                    onSelected: onDestinationSelected,
                  ),
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
                      statusIndicator,
                      const SizedBox(height: 8),
                      themeToggle,
                      if (toggleCollapsed != null) ...[
                        const SizedBox(height: 4),
                        toggleCollapsed,
                      ],
                    ],
                  )
                : Row(
                    children: [
                      statusIndicator,
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
                      themeToggle,
                      ?toggleCollapsed,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({
    required this.collapsed,
    required this.drawer,
    required this.onClose,
  });

  final bool collapsed;
  final bool drawer;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (collapsed) {
      return const ConsoleShellHeader(
        horizontalPadding: 0,
        child: Center(
          child: Tooltip(
            message: 'Cockpit Console',
            waitDuration: Duration(milliseconds: 300),
            showDuration: Duration(seconds: 2),
            child: _BrandMark(includeSemantics: true),
          ),
        ),
      );
    }
    return ConsoleShellHeader(
      horizontalPadding: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _BrandMark(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cockpit',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                Text(
                  'Console',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (drawer)
            IconButton(
              onPressed: onClose,
              icon: const Icon(LucideIcons.x, size: 16),
              tooltip: 'Close navigation',
            ),
        ],
      ),
    );
  }
}

final class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 24, this.includeSemantics = false});

  final double size;
  final bool includeSemantics;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/cockpit_console_app_icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: includeSemantics ? 'Cockpit Console' : null,
      excludeFromSemantics: !includeSemantics,
    );
  }
}

final class _NavItem extends HookConsumerWidget {
  const _NavItem({
    required this.destination,
    required this.collapsed,
    this.onSelected,
  });

  final ConsoleNavDestination destination;
  final bool collapsed;
  final VoidCallback? onSelected;

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
      onSelected?.call();
    }

    final item = Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      onTap: navigate,
      child: InkWell(
        key: ValueKey(destination.label),
        onTap: navigate,
        customBorder: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
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
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hovered.value = true,
      onExit: (_) => hovered.value = false,
      child: collapsed
          ? Tooltip(
              message: destination.label,
              waitDuration: const Duration(milliseconds: 300),
              showDuration: const Duration(seconds: 2),
              child: item,
            )
          : item,
    );
  }
}
