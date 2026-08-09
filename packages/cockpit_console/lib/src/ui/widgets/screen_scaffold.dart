import 'package:cockpit_console/src/ui/widgets/console_shell_header.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Standard scaffold for console screens: title bar with actions + scrollable
/// content area with consistent padding.
///
/// The [title] is the page heading. [actions] appear right-aligned in the
/// header. [sidebar] is an optional right-side panel (e.g. detail view).
final class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.header,
    this.stackActionsBelowWidth = 640,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? header;
  final double stackActionsBelowWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, theme),
          const ConsoleShellDivider(),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    if (header != null) {
      return ConsoleShellHeader(child: _withNavigationMenu(context, header!));
    }
    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
    final screenActions = actions;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < stackActionsBelowWidth &&
            screenActions?.isNotEmpty == true) {
          final horizontalPadding = ConsoleShellHeaderStyle.horizontalPadding(
            constraints.maxWidth,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConsoleShellHeader(
                horizontalPadding: horizontalPadding,
                child: _withNavigationMenu(context, titleBlock),
              ),
              const ConsoleShellDivider(),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 8,
                ),
                child: Wrap(
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: screenActions!,
                ),
              ),
            ],
          );
        }
        return ConsoleShellHeader(
          horizontalPadding: ConsoleShellHeaderStyle.horizontalPadding(
            constraints.maxWidth,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ..._navigationMenuLeading(context),
              Expanded(child: titleBlock),
              ...?screenActions,
            ],
          ),
        );
      },
    );
  }

  Widget _withNavigationMenu(BuildContext context, Widget child) {
    final leading = _navigationMenuLeading(context);
    if (leading.isEmpty) return child;
    return Row(
      children: [
        ...leading,
        Expanded(child: child),
      ],
    );
  }

  List<Widget> _navigationMenuLeading(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.hasDrawer != true) return const <Widget>[];
    return <Widget>[
      IconButton(
        key: const ValueKey(ConsoleNavigationIds.menu),
        onPressed: scaffold!.openDrawer,
        icon: const Icon(LucideIcons.menu),
        tooltip: 'Open navigation',
      ),
      const SizedBox(width: 12),
    ];
  }
}
