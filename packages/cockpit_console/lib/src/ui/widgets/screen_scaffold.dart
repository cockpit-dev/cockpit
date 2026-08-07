import 'package:flutter/material.dart';

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
          Container(height: 1, color: theme.dividerColor),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    if (header != null) return header!;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          ),
        ],
      ],
    );
    final screenActions = actions;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < stackActionsBelowWidth &&
            screenActions?.isNotEmpty == true) {
          final horizontalPadding = constraints.maxWidth < 720 ? 16.0 : 24.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 8),
                Wrap(
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: screenActions!,
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth < 720 ? 16 : 24,
            16,
            constraints.maxWidth < 720 ? 16 : 24,
            12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleBlock),
              ...?screenActions,
            ],
          ),
        );
      },
    );
  }
}
