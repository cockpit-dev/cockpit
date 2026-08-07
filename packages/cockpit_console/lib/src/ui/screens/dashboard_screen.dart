import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Dashboard: server overview, daemon health, quick stats, quick actions.
final class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemon = ref.watch(daemonProvider);
    final supervisor = ref.watch(supervisorProvider);

    return ScreenScaffold(
      title: 'Dashboard',
      subtitle: 'Supervisor status and system overview',
      stackActionsBelowWidth: 420,
      actions: [
        OutlinedButton.icon(
          onPressed: daemon.busy
              ? null
              : () => ref.read(daemonProvider.notifier).refresh(),
          icon: SizedBox(
            width: 14,
            height: 14,
            child: daemon.busy
                ? const CircularProgressIndicator(strokeWidth: 2)
                : const Icon(LucideIcons.refreshCw, size: 14),
          ),
          label: const Text('Refresh'),
        ),
        const SizedBox(width: 8),
        if (!daemon.running)
          FilledButton.icon(
            onPressed: daemon.busy
                ? null
                : () => ref.read(daemonProvider.notifier).start(),
            icon: const Icon(LucideIcons.play, size: 14),
            label: const Text('Start daemon'),
          )
        else
          FilledButton.icon(
            onPressed: daemon.busy
                ? null
                : () => ref.read(daemonProvider.notifier).restart(),
            icon: const Icon(LucideIcons.rotateCw, size: 14),
            label: const Text('Restart'),
          ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConnectionBanner(
                  daemonRunning: daemon.running,
                  daemonHealthy: daemon.healthy,
                  supervisorConnected: supervisor is SupervisorConnected,
                  errorMessage: supervisor is SupervisorDisconnected
                      ? supervisor.message
                      : daemon.error,
                ),
                const SizedBox(height: 20),
                if (supervisor is SupervisorConnected) ...[
                  _StatsGrid(
                    server: supervisor.server,
                    capabilities: supervisor.capabilities,
                  ),
                  const SizedBox(height: 24),
                  _ServerInfoSection(server: supervisor.server),
                ] else if (supervisor is SupervisorConnecting ||
                    supervisor is SupervisorInitial)
                  const _LoadingState()
                else
                  _DisconnectedState(
                    message: (supervisor as SupervisorDisconnected).message,
                    onRetry: () =>
                        ref.read(supervisorProvider.notifier).connect(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.daemonRunning,
    required this.daemonHealthy,
    required this.supervisorConnected,
    this.errorMessage,
  });

  final bool daemonRunning;
  final bool daemonHealthy;
  final bool supervisorConnected;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = daemonRunning && daemonHealthy && supervisorConnected;
    final color = connected
        ? context.consoleColors.success
        : daemonRunning
        ? context.consoleColors.warning
        : theme.colorScheme.error;
    final label = connected
        ? 'System operational'
        : daemonRunning
        ? 'Daemon running, API disconnected'
        : 'Daemon offline';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.2),
        radius: ConsoleShapes.controlRadius,
      ),
      child: Row(
        children: [
          Icon(
            connected ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.server, required this.capabilities});

  final CockpitServerInfo server;
  final CockpitCapabilityDocument capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = <Widget>[
      _MetricItem(
        label: 'API Version',
        value: 'v${server.apiVersion.major}.${server.apiVersion.minor}',
        icon: LucideIcons.code,
      ),
      _MetricItem(
        label: 'Engine',
        value: _truncateVersion(server.engineVersion),
        icon: LucideIcons.cpu,
      ),
      _MetricItem(
        label: 'Started',
        value: _formatStarted(server.startedAt),
        icon: LucideIcons.clock,
      ),
      _MetricItem(
        label: 'Operations',
        value: '${capabilities.operations.length}',
        icon: LucideIcons.workflow,
      ),
    ];
    return Container(
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            return Row(
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  Expanded(child: metrics[index]),
                  if (index != metrics.length - 1)
                    SizedBox(
                      height: 48,
                      child: VerticalDivider(
                        width: 1,
                        color: theme.dividerColor,
                      ),
                    ),
                ],
              ],
            );
          }
          return Column(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                metrics[index],
                if (index != metrics.length - 1)
                  Divider(height: 1, color: theme.dividerColor),
              ],
            ],
          );
        },
      ),
    );
  }

  String _truncateVersion(String version) {
    if (version.length > 20) return '${version.substring(0, 20)}…';
    return version;
  }

  String _formatStarted(DateTime startedAt) {
    final now = DateTime.now();
    final diff = now.difference(startedAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

final class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
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

final class _ServerInfoSection extends StatelessWidget {
  const _ServerInfoSection({required this.server});

  final CockpitServerInfo server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Server Information',
          style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: ConsoleShapes.decoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderColor: theme.dividerColor,
          ),
          child: Column(
            children: [
              _InfoRow(
                label: 'Instance ID',
                value: server.instanceId,
                mono: true,
              ),
              Divider(height: 1, color: theme.dividerColor),
              _InfoRow(
                label: 'API Version',
                value: 'v${server.apiVersion.major}.${server.apiVersion.minor}',
              ),
              Divider(height: 1, color: theme.dividerColor),
              _InfoRow(label: 'Engine Version', value: server.engineVersion),
              Divider(height: 1, color: theme.dividerColor),
              _InfoRow(
                label: 'Started At',
                value: server.startedAt.toUtc().toIso8601String(),
                mono: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: LucideIcons.loaderCircle,
      title: 'Connecting to Supervisor',
      description: 'Establishing daemon connection and reading capabilities.',
      iconSpin: true,
    );
  }
}

final class _DisconnectedState extends StatelessWidget {
  const _DisconnectedState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: LucideIcons.wifiOff,
      title: 'Cannot connect to Supervisor',
      description: message,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(LucideIcons.rotateCw, size: 14),
        label: const Text('Retry connection'),
      ),
    );
  }
}
