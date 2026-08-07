import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The bottom status bar showing daemon health, API version, and clock.
final class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemon = ref.watch(daemonProvider);
    final supervisor = ref.watch(supervisorProvider);
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _Dot(running: daemon.running, healthy: daemon.healthy),
          const SizedBox(width: 6),
          Text(
            daemon.running
                ? daemon.healthy
                      ? 'Daemon healthy'
                      : 'Daemon degraded'
                : 'Daemon offline',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1,
            ),
          ),
          const SizedBox(width: 16),
          if (supervisor is SupervisorConnected) ...[
            Icon(
              Icons.check_circle,
              size: 12,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 4),
            Text(
              'API v${supervisor.server.apiVersion.major}.'
              '${supervisor.server.apiVersion.minor}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1,
              ),
            ),
          ] else if (supervisor is SupervisorDisconnected) ...[
            Icon(Icons.error_outline, size: 12, color: theme.colorScheme.error),
            const SizedBox(width: 4),
            Expanded(
              child: Tooltip(
                message: supervisor.message,
                child: SelectableText(
                  supervisor.message,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.error,
                    height: 1,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            'Cockpit Console',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

final class _Dot extends StatelessWidget {
  const _Dot({required this.running, required this.healthy});

  final bool running;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final color = !running
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : healthy
        ? context.consoleColors.success
        : context.consoleColors.warning;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: running && healthy
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4)]
            : null,
      ),
    );
  }
}
