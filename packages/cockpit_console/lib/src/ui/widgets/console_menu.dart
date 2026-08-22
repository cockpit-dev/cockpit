import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_menu_style.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Compact section heading shared by anchored Console menus.
final class ConsoleMenuHeader extends StatelessWidget {
  const ConsoleMenuHeader({required this.label, this.icon, super.key});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return SizedBox(
      height: ConsoleMenuStyle.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (icon case final icon?) ...[
              Icon(icon, size: 14, color: colors.inkTertiary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.inkTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A consistently aligned single-selection row for anchored Console menus.
final class ConsoleSelectionMenuItem extends StatelessWidget {
  const ConsoleSelectionMenuItem({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.minWidth = ConsoleMenuStyle.selectionWidth,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: selected
          ? Icon(LucideIcons.check, size: 15, color: colors.accent)
          : const SizedBox.square(dimension: 15),
      style: ConsoleMenuStyle.selectableItem(
        colors,
        selected: selected,
        minWidth: minWidth,
      ),
      child: Text(label),
    );
  }
}
