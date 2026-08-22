import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/preferences_store.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_menu_style.dart';
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
    this.opensDrawer = false,
    this.onToggleNavigation,
    this.onDestinationSelected,
    super.key,
  });

  final bool collapsed;
  final bool drawer;
  final bool opensDrawer;
  final VoidCallback? onToggleNavigation;
  final VoidCallback? onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemonState = ref.watch(daemonProvider);
    final themeMode = ref.watch(themeProvider);
    final localeMode = ref.watch(consoleLocaleProvider);

    final theme = Theme.of(context);
    final running = daemonState.running;
    final healthy = daemonState.healthy;
    final statusColor = !running
        ? theme.colorScheme.onSurfaceVariant
        : healthy
        ? context.consoleColors.success
        : context.consoleColors.warning;
    final statusLabel = !running
        ? context.t.shell.offline
        : healthy
        ? context.t.shell.connected
        : context.t.shell.degraded;

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
      key: ValueKey(
        drawer
            ? '${ConsoleNavigationIds.theme}-drawer'
            : ConsoleNavigationIds.theme,
      ),
      icon: Icon(
        themeMode == ThemeMode.dark ? LucideIcons.sun : LucideIcons.moon,
        size: 15,
      ),
      onPressed: () =>
          ref.read(themeProvider.notifier).toggle(theme.brightness),
      tooltip: context.t.shell.toggleTheme,
      style: IconButton.styleFrom(minimumSize: const Size.square(28)),
    );
    final languageMenu = _LanguageMenu(
      drawer: drawer,
      mode: localeMode,
      onSelected: ref.read(consoleLocaleProvider.notifier).set,
    );
    final navigationToggle = onToggleNavigation == null
        ? null
        : IconButton(
            key: ValueKey(
              drawer ? ConsoleNavigationIds.close : ConsoleNavigationIds.toggle,
            ),
            onPressed: onToggleNavigation,
            icon: Icon(
              drawer || !collapsed
                  ? LucideIcons.panelLeftClose
                  : LucideIcons.panelLeftOpen,
              size: collapsed ? 15 : 16,
            ),
            tooltip: drawer
                ? context.t.shell.closeNavigation
                : opensDrawer
                ? context.t.shell.openNavigation
                : collapsed
                ? context.t.shell.expandNavigation
                : context.t.shell.collapseNavigation,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(28),
              maximumSize: const Size.square(28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
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
          _Header(collapsed: collapsed),
          const ConsoleShellDivider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final dest in ConsoleNavDestination.values)
                  _NavItem(
                    destination: dest,
                    collapsed: collapsed,
                    drawer: drawer,
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
                      languageMenu,
                      const SizedBox(height: 4),
                      themeToggle,
                      if (navigationToggle != null) ...[
                        const SizedBox(height: 4),
                        navigationToggle,
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
                      languageMenu,
                      const SizedBox(width: 4),
                      themeToggle,
                      if (navigationToggle != null) ...[
                        const SizedBox(width: 4),
                        navigationToggle,
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

final class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.drawer,
    required this.mode,
    required this.onSelected,
  });

  final bool drawer;
  final ConsoleLocaleMode mode;
  final ValueChanged<ConsoleLocaleMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final translations = context.t;
    final colors = context.consoleColors;
    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        _LanguageMenuItem(
          label: translations.language.system,
          selected: mode == ConsoleLocaleMode.system,
          onPressed: () => onSelected(ConsoleLocaleMode.system),
        ),
        _LanguageMenuItem(
          label: translations.language.simplifiedChinese,
          selected: mode == ConsoleLocaleMode.simplifiedChinese,
          onPressed: () => onSelected(ConsoleLocaleMode.simplifiedChinese),
        ),
        _LanguageMenuItem(
          label: translations.language.english,
          selected: mode == ConsoleLocaleMode.english,
          onPressed: () => onSelected(ConsoleLocaleMode.english),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message:
            '${translations.language.title}: ${_languageLabel(translations, mode)}',
        child: IconButton(
          key: ValueKey(
            drawer
                ? '${ConsoleNavigationIds.language}-drawer'
                : ConsoleNavigationIds.language,
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(LucideIcons.languages, size: 15),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(28),
            maximumSize: const Size.square(28),
            backgroundColor: controller.isOpen ? colors.surface3 : null,
            foregroundColor: controller.isOpen
                ? colors.inkPrimary
                : colors.inkSecondary,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
          ),
        ),
      ),
    );
  }
}

final class _LanguageMenuItem extends StatelessWidget {
  const _LanguageMenuItem({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return MenuItemButton(
      onPressed: onPressed,
      trailingIcon: selected
          ? Icon(LucideIcons.check, size: 16, color: colors.accent)
          : const SizedBox.square(dimension: 16),
      style: ConsoleMenuStyle.selectableItem(colors, selected: selected),
      child: Text(label),
    );
  }
}

String _languageLabel(Translations translations, ConsoleLocaleMode mode) =>
    switch (mode) {
      ConsoleLocaleMode.system => translations.language.system,
      ConsoleLocaleMode.english => translations.language.english,
      ConsoleLocaleMode.simplifiedChinese =>
        translations.language.simplifiedChinese,
    };

final class _Header extends StatelessWidget {
  const _Header({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (collapsed) {
      return ConsoleShellHeader(
        horizontalPadding: 0,
        child: const Center(
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
    required this.drawer,
    this.onSelected,
  });

  final ConsoleNavDestination destination;
  final bool collapsed;
  final bool drawer;
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
    final itemHeight = drawer
        ? ConsoleShellLayoutStyle.drawerNavigationItemHeight
        : collapsed
        ? ConsoleShellLayoutStyle.navigationRailItemHeight
        : ConsoleShellLayoutStyle.navigationItemHeight;
    final iconSize = collapsed
        ? ConsoleShellLayoutStyle.navigationRailIconSize
        : ConsoleShellLayoutStyle.navigationIconSize;
    final label = destination.label(context.t);
    void navigate() {
      final navigation = ref.read(navProvider.notifier);
      navigation.go(destination);
      onSelected?.call();
    }

    final item = Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: navigate,
      child: InkWell(
        key: ValueKey(destination.name),
        onTap: navigate,
        customBorder: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
        child: Container(
          height: itemHeight,
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
              Icon(destination.icon, size: iconSize, color: fg),
              if (!collapsed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
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
              message: label,
              waitDuration: const Duration(milliseconds: 300),
              showDuration: const Duration(seconds: 2),
              child: item,
            )
          : item,
    );
  }
}
