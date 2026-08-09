import 'package:flutter/material.dart';

/// Responsive geometry shared by the complete application shell.
abstract final class ConsoleShellLayoutStyle {
  static const double drawerBreakpoint = 720;
  static const double compactSidebarBreakpoint = 1000;
  static const double sidebarWidth = 200;
  static const double sidebarRailWidth = 56;
  static const double drawerWidth = 240;
  static const double navigationItemHeight = 34;
  static const double navigationRailItemHeight = 30;
  static const double drawerNavigationItemHeight = 40;
  static const double navigationIconSize = 18;
  static const double navigationRailIconSize = 16;
}

/// Shared geometry for the primary app-shell header on both sides of the
/// navigation divider.
abstract final class ConsoleShellHeaderStyle {
  static const double height = 64;
  static const double desktopHorizontalPadding = 24;
  static const double compactHorizontalPadding = 16;
  static const double compactBreakpoint = 720;

  static double horizontalPadding(double width) => width < compactBreakpoint
      ? compactHorizontalPadding
      : desktopHorizontalPadding;
}

/// The shared app-shell header surface.
final class ConsoleShellHeader extends StatelessWidget {
  const ConsoleShellHeader({
    required this.child,
    this.horizontalPadding = ConsoleShellHeaderStyle.desktopHorizontalPadding,
    super.key,
  });

  final Widget child;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ConsoleShellHeaderStyle.height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

/// A single-pixel shell divider shared by the sidebar and screen headers.
final class ConsoleShellDivider extends StatelessWidget {
  const ConsoleShellDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: ColoredBox(color: Theme.of(context).dividerColor),
    );
  }
}
