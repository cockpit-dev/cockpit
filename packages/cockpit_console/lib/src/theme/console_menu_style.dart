import 'package:flutter/material.dart';

import 'console_colors.dart';
import 'console_control_style.dart';
import 'console_shapes.dart';

/// Shared geometry and interaction states for every anchored Console menu.
abstract final class ConsoleMenuStyle {
  static const double itemHeight = ConsoleControlStyle.height;
  static const double selectionWidth = 172;
  static const EdgeInsets menuPadding = EdgeInsets.all(4);
  static const EdgeInsets itemPadding = EdgeInsets.symmetric(horizontal: 10);

  static MenuThemeData menuTheme(ConsoleColors colors) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface1),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(menuPadding),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
        shape: WidgetStatePropertyAll(
          ConsoleShapes.border(radius: ConsoleShapes.surfaceRadius),
        ),
      ),
    );
  }

  static MenuButtonThemeData buttonTheme(ConsoleColors colors) {
    return MenuButtonThemeData(
      style: ButtonStyle(
        alignment: Alignment.centerLeft,
        minimumSize: const WidgetStatePropertyAll(Size(0, itemHeight)),
        padding: const WidgetStatePropertyAll(itemPadding),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        animationDuration: const Duration(milliseconds: 160),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.inkDisabled;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return colors.inkPrimary;
          }
          return colors.inkSecondary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return colors.surface3;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return colors.surfaceHover;
          }
          return Colors.transparent;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.inkDisabled;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return colors.inkPrimary;
          }
          return colors.inkSecondary;
        }),
        iconSize: const WidgetStatePropertyAll(16),
        shape: WidgetStatePropertyAll(
          ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
        ),
      ),
    );
  }

  static ButtonStyle selectableItem(
    ConsoleColors colors, {
    required bool selected,
    double minWidth = selectionWidth,
  }) {
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(minWidth, itemHeight)),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.inkDisabled;
        }
        if (selected ||
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return colors.inkPrimary;
        }
        return colors.inkSecondary;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return selected
              ? colors.accentSubtle.withValues(alpha: 0.5)
              : Colors.transparent;
        }
        if (selected) {
          if (states.contains(WidgetState.pressed)) {
            return Color.alphaBlend(
              colors.accent.withValues(alpha: 0.16),
              colors.accentSubtle,
            );
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return Color.alphaBlend(
              colors.accent.withValues(alpha: 0.08),
              colors.accentSubtle,
            );
          }
          return colors.accentSubtle;
        }
        if (states.contains(WidgetState.pressed)) {
          return colors.surface3;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return colors.surfaceHover;
        }
        return Colors.transparent;
      }),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }
}
