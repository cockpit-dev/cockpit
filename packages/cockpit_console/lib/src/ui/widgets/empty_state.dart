import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:flutter/material.dart';

/// Empty / loading / error state view with icon, title, description, action.
final class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.iconSpin = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  final bool iconSpin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalPadding = constraints.maxHeight.isFinite
            ? (constraints.maxHeight * 0.08).clamp(12.0, 32.0)
            : 32.0;
        final minimumHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - verticalPadding * 2).clamp(
                0.0,
                double.infinity,
              )
            : 0.0;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 32,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconSpin && !MediaQuery.disableAnimationsOf(context))
                    SizedBox.square(
                      dimension: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 36,
                      color: context.consoleColors.inkTertiary,
                    ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 16), action!],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
