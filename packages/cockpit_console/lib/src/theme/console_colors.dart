import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'console_palette.dart';

/// Semantic color resolution for [Brightness].
extension type const ConsoleColors(Brightness brightness) {
  bool get isDark => brightness == Brightness.dark;

  // ── Surfaces ─────────────────────────────────────────────────────────
  Color get bg => isDark ? ConsolePalette.darkBg : ConsolePalette.lightBg;
  Color get surface =>
      isDark ? ConsolePalette.darkSurface : ConsolePalette.lightSurface;
  Color get surface1 =>
      isDark ? ConsolePalette.darkSurface1 : ConsolePalette.lightSurface1;
  Color get surface2 =>
      isDark ? ConsolePalette.darkSurface2 : ConsolePalette.lightSurface2;
  Color get surface3 =>
      isDark ? ConsolePalette.darkSurface3 : ConsolePalette.lightSurface3;
  Color get surfaceHover => isDark
      ? ConsolePalette.darkSurfaceHover
      : ConsolePalette.lightSurfaceHover;

  // ── Ink ──────────────────────────────────────────────────────────────
  Color get inkPrimary =>
      isDark ? ConsolePalette.darkInkPrimary : ConsolePalette.lightInkPrimary;
  Color get inkSecondary => isDark
      ? ConsolePalette.darkInkSecondary
      : ConsolePalette.lightInkSecondary;
  Color get inkTertiary =>
      isDark ? ConsolePalette.darkInkTertiary : ConsolePalette.lightInkTertiary;
  Color get inkDisabled =>
      isDark ? ConsolePalette.darkInkDisabled : ConsolePalette.lightInkDisabled;

  // ── Borders ──────────────────────────────────────────────────────────
  Color get border =>
      isDark ? ConsolePalette.darkBorder : ConsolePalette.lightBorder;
  Color get borderHover =>
      isDark ? ConsolePalette.darkBorderHover : ConsolePalette.lightBorderHover;
  Color get borderFocus =>
      isDark ? ConsolePalette.darkBorderFocus : ConsolePalette.lightBorderFocus;

  // ── Accent ───────────────────────────────────────────────────────────
  Color get accent => isDark ? ConsolePalette.accent : const Color(0xFF3867BD);
  Color get accentHover =>
      isDark ? ConsolePalette.accentHover : const Color(0xFF4775C8);
  Color get accentActive =>
      isDark ? ConsolePalette.accentActive : const Color(0xFF315EAF);
  Color get accentFg => isDark ? const Color(0xFF08090A) : Colors.white;
  Color get accentSubtle =>
      isDark ? ConsolePalette.accentSubtle : const Color(0xFFEAF1FE);
  Color get accentSubtleFg =>
      isDark ? ConsolePalette.accentSubtleFg : const Color(0xFF3867BD);

  Color get action => ConsolePalette.action;
  Color get actionHover => ConsolePalette.actionHover;
  Color get actionActive => ConsolePalette.actionActive;
  Color get actionFg => ConsolePalette.actionFg;

  // ── Status ───────────────────────────────────────────────────────────
  Color get success =>
      isDark ? ConsolePalette.success : const Color(0xFF287D56);
  Color get successSubtle =>
      isDark ? ConsolePalette.successSubtle : const Color(0xFFE8F6EF);
  Color get successFg => success;

  Color get warning =>
      isDark ? ConsolePalette.warning : const Color(0xFF946000);
  Color get warningSubtle =>
      isDark ? ConsolePalette.warningSubtle : const Color(0xFFFCF2E3);
  Color get warningFg => warning;

  Color get errorColor =>
      isDark ? ConsolePalette.error : const Color(0xFFC03833);
  Color get onError => isDark ? const Color(0xFF08090A) : Colors.white;
  Color get errorSubtle =>
      isDark ? ConsolePalette.errorSubtle : const Color(0xFFFCEAEA);
  Color get errorFg => errorColor;

  Color get info => isDark ? ConsolePalette.info : const Color(0xFF3867BD);
  Color get onInfo => isDark ? const Color(0xFF08090A) : Colors.white;
  Color get infoSubtle =>
      isDark ? ConsolePalette.infoSubtle : const Color(0xFFEAF1FE);
  Color get infoFg => info;

  // ── Shadows ──────────────────────────────────────────────────────────
  Color get shadow =>
      isDark ? Colors.black : Colors.black.withValues(alpha: 0.06);
  Color get scrim => Colors.black.withValues(alpha: isDark ? 0.6 : 0.4);
  Color get overlay => isDark
      ? Colors.black.withValues(alpha: 0.5)
      : Colors.black.withValues(alpha: 0.3);
}

/// Resolves [ConsoleColors] from a [ThemeContext].
extension ConsoleColorsX on BuildContext {
  ConsoleColors get consoleColors => ConsoleColors(Theme.brightnessOf(this));
  Color get consoleBg => consoleColors.bg;
  Color get consoleSurface => consoleColors.surface;
  Color get consoleInkPrimary => consoleColors.inkPrimary;
  Color get consoleInkSecondary => consoleColors.inkSecondary;
  Color get consoleInkTertiary => consoleColors.inkTertiary;
  Color get consoleBorder => consoleColors.border;
}

/// System-level overlay style for the console.
SystemUiOverlayStyle consoleOverlayStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
  );
}
