import 'package:flutter/material.dart';

import 'console_colors.dart';
import 'console_control_style.dart';
import 'console_shapes.dart';

/// Builds the Cockpit Console [ThemeData] — a Linear / Vercel inspired
/// dark-first system with Inter-style typography, tight neutral surfaces,
/// and a single blue accent for primary actions and selection.
final class ConsoleTheme {
  const ConsoleTheme._();

  static ThemeData build(Brightness brightness) {
    final colors = ConsoleColors(brightness);
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.surface,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.accentFg,
        primaryContainer: colors.accentSubtle,
        onPrimaryContainer: colors.accentSubtleFg,
        secondary: colors.accent,
        onSecondary: colors.accentFg,
        secondaryContainer: colors.accentSubtle,
        onSecondaryContainer: colors.accentSubtleFg,
        tertiary: colors.info,
        onTertiary: colors.onInfo,
        error: colors.errorColor,
        onError: colors.onError,
        errorContainer: colors.errorSubtle,
        onErrorContainer: colors.errorFg,
        surface: colors.surface,
        onSurface: colors.inkPrimary,
        onSurfaceVariant: colors.inkSecondary,
        outline: colors.border,
        outlineVariant: colors.border.withValues(alpha: 0.5),
        shadow: colors.shadow,
        scrim: colors.scrim,
        inverseSurface: colors.inkPrimary,
        onInverseSurface: colors.bg,
        inversePrimary: colors.accent,
        surfaceDim: colors.bg,
        surfaceBright: colors.surface2,
        surfaceContainerLowest: colors.bg,
        surfaceContainerLow: colors.surface,
        surfaceContainer: colors.surface1,
        surfaceContainerHigh: colors.surface2,
        surfaceContainerHighest: colors.surface3,
      ),
      visualDensity: VisualDensity.standard,
      splashFactory: NoSplash.splashFactory,
    );

    return base.copyWith(
      textTheme: _buildTextTheme(base.textTheme, colors),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        foregroundColor: colors.inkPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: _inputDecoration(colors),
      chipTheme: _chipTheme(base.chipTheme, colors),
      filledButtonTheme: _filledButton(base, colors),
      outlinedButtonTheme: _outlinedButton(colors),
      textButtonTheme: _textButton(colors),
      iconButtonTheme: _iconButton(colors),
      switchTheme: _switchTheme(colors),
      checkboxTheme: _checkboxTheme(colors),
      radioTheme: _radioTheme(colors),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surface2,
        linearMinHeight: 2,
        circularTrackColor: colors.surface2,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return colors.borderHover;
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.borderHover;
          }
          return colors.border;
        }),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        trackVisibility: WidgetStateProperty.all(false),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ConsoleShapes.decoration(
          color: colors.surface3,
          borderColor: colors.borderHover,
          radius: ConsoleShapes.smallRadius,
        ),
        textStyle: TextStyle(
          color: colors.inkPrimary,
          fontSize: 12,
          height: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: _popupMenuTheme(colors),
      menuBarTheme: MenuBarThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(colors.surface2),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(
            ConsoleShapes.border(side: BorderSide(color: colors.border)),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: ConsoleShapes.border(
          radius: ConsoleShapes.dialogRadius,
          side: BorderSide(color: colors.border),
        ),
        titleTextStyle: TextStyle(
          color: colors.inkPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        contentTextStyle: TextStyle(
          color: colors.inkSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surface3,
        contentTextStyle: TextStyle(color: colors.inkPrimary, fontSize: 13),
        actionTextColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        shape: ConsoleShapes.border(
          side: BorderSide(color: colors.borderHover),
        ),
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.inkPrimary,
        unselectedLabelColor: colors.inkSecondary,
        indicatorColor: colors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: colors.border,
        overlayColor: WidgetStateProperty.all(colors.surfaceHover),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      ),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, ConsoleColors colors) {
    const family = null; // system font stack (Inter on macOS, Roboto on others)
    return base.copyWith(
      // Display — rarely used in product UI
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.5,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.4,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      // Headings
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.3,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.2,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      // Titles — section / panel headers
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.4,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      // Body
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        fontFamily: family,
        color: colors.inkSecondary,
      ),
      // Labels — buttons, chips, badges
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0,
        fontFamily: family,
        color: colors.inkPrimary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0,
        fontFamily: family,
        color: colors.inkSecondary,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0,
        fontFamily: family,
        color: colors.inkTertiary,
      ),
    );
  }

  static InputDecorationTheme _inputDecoration(ConsoleColors colors) {
    return InputDecorationTheme(
      isDense: ConsoleControlStyle.fieldIsDense,
      visualDensity: ConsoleControlStyle.fieldDensity,
      filled: true,
      fillColor: colors.surface1,
      prefixIconColor: colors.inkSecondary,
      suffixIconColor: colors.inkSecondary,
      hintStyle: TextStyle(color: colors.inkTertiary, fontSize: 13),
      labelStyle: TextStyle(color: colors.inkSecondary, fontSize: 13),
      floatingLabelStyle: TextStyle(
        color: colors.inkSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: ConsoleControlStyle.fieldPadding,
      constraints: ConsoleControlStyle.fieldMinConstraints,
      prefixIconConstraints: ConsoleControlStyle.fieldIconConstraints,
      suffixIconConstraints: ConsoleControlStyle.fieldIconConstraints,
      border: ConsoleShapes.input(BorderSide(color: colors.border)),
      enabledBorder: ConsoleShapes.input(BorderSide(color: colors.border)),
      focusedBorder: ConsoleShapes.input(
        BorderSide(color: colors.accent, width: 1.5),
      ),
      errorBorder: ConsoleShapes.input(BorderSide(color: colors.errorColor)),
      focusedErrorBorder: ConsoleShapes.input(
        BorderSide(color: colors.errorColor, width: 1.5),
      ),
      disabledBorder: ConsoleShapes.input(
        BorderSide(color: colors.border.withValues(alpha: 0.5)),
      ),
    );
  }

  static ChipThemeData _chipTheme(ChipThemeData base, ConsoleColors colors) {
    return base.copyWith(
      backgroundColor: colors.surface2,
      selectedColor: colors.accentSubtle,
      checkmarkColor: colors.accent,
      labelStyle: TextStyle(
        color: colors.inkSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        color: colors.accentSubtleFg,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: colors.border),
      shape: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  static FilledButtonThemeData _filledButton(
    ThemeData base,
    ConsoleColors colors,
  ) {
    return FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.accentFg,
            disabledBackgroundColor: colors.surface3,
            disabledForegroundColor: colors.inkDisabled,
            elevation: 0,
            padding: ConsoleControlStyle.buttonPadding,
            minimumSize: const Size(0, ConsoleControlStyle.height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: ConsoleShapes.border(radius: ConsoleShapes.controlRadius),
            textStyle: base.textTheme.labelLarge,
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colors.surface3;
              }
              if (states.contains(WidgetState.pressed)) {
                return colors.accentActive;
              }
              if (states.contains(WidgetState.hovered)) {
                return colors.accentHover;
              }
              return colors.accent;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: colors.borderFocus, width: 1.5);
              }
              return BorderSide.none;
            }),
          ),
    );
  }

  static OutlinedButtonThemeData _outlinedButton(ConsoleColors colors) {
    return OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: colors.inkPrimary,
            backgroundColor: colors.surface1,
            disabledForegroundColor: colors.inkDisabled,
            disabledBackgroundColor: colors.surface1,
            elevation: 0,
            padding: ConsoleControlStyle.buttonPadding,
            minimumSize: const Size(0, ConsoleControlStyle.height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: ConsoleShapes.border(radius: ConsoleShapes.controlRadius),
            side: BorderSide(color: colors.border),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return colors.surface3;
              }
              if (states.contains(WidgetState.focused)) {
                return colors.accentSubtle;
              }
              if (states.contains(WidgetState.hovered)) {
                return colors.surfaceHover;
              }
              return null;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: colors.borderFocus, width: 1.5);
              }
              if (states.contains(WidgetState.hovered)) {
                return BorderSide(color: colors.borderHover);
              }
              return BorderSide(color: colors.border);
            }),
          ),
    );
  }

  static TextButtonThemeData _textButton(ConsoleColors colors) {
    return TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: colors.inkSecondary,
            disabledForegroundColor: colors.inkDisabled,
            elevation: 0,
            padding: ConsoleControlStyle.compactButtonPadding,
            minimumSize: const Size(0, ConsoleControlStyle.compactHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return colors.surface3;
              }
              if (states.contains(WidgetState.focused)) {
                return colors.accentSubtle;
              }
              if (states.contains(WidgetState.hovered)) {
                return colors.surfaceHover;
              }
              return null;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colors.inkDisabled;
              }
              if (states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)) {
                return colors.inkPrimary;
              }
              return colors.inkSecondary;
            }),
          ),
    );
  }

  static IconButtonThemeData _iconButton(ConsoleColors colors) {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        disabledForegroundColor: colors.inkDisabled,
        elevation: 0,
        minimumSize: const Size.square(ConsoleControlStyle.iconButtonMinSize),
        maximumSize: const Size.square(ConsoleControlStyle.iconButtonMaxSize),
        iconSize: ConsoleControlStyle.iconSize,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
      ),
    );
  }

  static SwitchThemeData _switchTheme(ConsoleColors colors) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.inkDisabled;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accentFg;
        }
        return colors.inkSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.surface3;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accent;
        }
        return colors.surface3;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return colors.borderHover;
      }),
      padding: EdgeInsets.zero,
    );
  }

  static CheckboxThemeData _checkboxTheme(ConsoleColors colors) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          if (states.contains(WidgetState.selected)) {
            return colors.inkDisabled;
          }
          return Colors.transparent;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accent;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(colors.accentFg),
      side: BorderSide(color: colors.borderHover, width: 1.5),
      shape: ConsoleShapes.border(radius: 6),
      visualDensity: VisualDensity.compact,
    );
  }

  static RadioThemeData _radioTheme(ConsoleColors colors) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.inkDisabled;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accent;
        }
        return colors.borderHover;
      }),
      visualDensity: VisualDensity.compact,
    );
  }

  static PopupMenuThemeData _popupMenuTheme(ConsoleColors colors) {
    return PopupMenuThemeData(
      color: colors.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      textStyle: TextStyle(color: colors.inkPrimary, fontSize: 13),
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(color: colors.inkTertiary, fontSize: 11),
      ),
      shape: ConsoleShapes.border(side: BorderSide(color: colors.border)),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    );
  }
}

/// Monospace text style for code, IDs, paths, and technical values.
TextStyle consoleMono({
  double size = 12,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double height = 1.5,
}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'DejaVu Sans Mono', 'Roboto Mono'],
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
  );
}
