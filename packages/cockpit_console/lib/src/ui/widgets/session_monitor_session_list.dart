import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final class SessionMonitorSessionList extends StatelessWidget {
  const SessionMonitorSessionList({
    required this.sessions,
    required this.selected,
    required this.onSelect,
    this.error,
    super.key,
  });

  final List<MonitoredSession> sessions;
  final SessionMonitorKey? selected;
  final ValueChanged<SessionMonitorKey> onSelect;
  final SessionMonitorMessage? error;

  @override
  Widget build(BuildContext context) {
    final rows = _sessionRows(sessions);
    return ColoredBox(
      color: context.consoleColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t.sessions.listTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${sessions.length}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (error != null)
            _DiscoveryWarning(
              message: sessionMonitorMessageText(context, error!),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final session = row.session;
                if (session != null) {
                  return _SessionTile(
                    session: session,
                    selected: selected == session.key,
                    onTap: () => onSelect(session.key),
                  );
                }
                return _ProjectHeader(
                  projectPath: row.projectPath!,
                  projectName: row.projectName!,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class SessionMonitorCompactPicker extends StatelessWidget {
  const SessionMonitorCompactPicker({
    required this.sessions,
    required this.selected,
    required this.onSelect,
    this.error,
    super.key,
  });

  final List<MonitoredSession> sessions;
  final SessionMonitorKey? selected;
  final ValueChanged<SessionMonitorKey> onSelect;
  final SessionMonitorMessage? error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.consoleColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return _CompactSessionItem(
                    session: session,
                    selected: selected == session.key,
                    onTap: () => onSelect(session.key),
                  );
                },
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              _DiscoveryWarning(
                message: sessionMonitorMessageText(context, error!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _CompactSessionItem extends StatelessWidget {
  const _CompactSessionItem({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final MonitoredSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    final label =
        '${session.projectName}, ${session.platform}, ${session.key.sessionId}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? colors.accentSubtle : colors.surface1,
        shape: ConsoleShapes.border(
          radius: ConsoleShapes.smallRadius,
          side: BorderSide(color: selected ? colors.accent : colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  _StatusDot(session: session),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.projectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: selected
                                    ? colors.accentSubtleFg
                                    : colors.inkPrimary,
                              ),
                        ),
                        Text(
                          '${session.platform} · ${shortSessionId(session.key.sessionId)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.inkTertiary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.projectPath, required this.projectName});

  final String projectPath;
  final String projectName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
      child: Tooltip(
        message: projectPath,
        child: Text(
          projectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.consoleColors.inkTertiary,
          ),
        ),
      ),
    );
  }
}

final class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final MonitoredSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    final background = selected ? colors.accentSubtle : Colors.transparent;
    return Semantics(
      button: true,
      selected: selected,
      label: context.t.sessions.selectSemantics(
        project: session.projectName,
        platform: session.platform,
        session: session.key.sessionId,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: ConsoleShapes.border(
              radius: ConsoleShapes.smallRadius,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: ConsoleShapes.decoration(
                color: background,
                radius: ConsoleShapes.smallRadius,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _StatusDot(session: session),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${session.platform} · ${shortSessionId(session.key.sessionId)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: selected
                                          ? colors.accentSubtleFg
                                          : colors.inkPrimary,
                                    ),
                              ),
                            ),
                            if (session.errorCount > 0 ||
                                session.networkFailureCount > 0)
                              Icon(
                                LucideIcons.triangleAlert,
                                size: 13,
                                color: session.errorCount > 0
                                    ? colors.errorFg
                                    : colors.warningFg,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.route ?? session.deviceId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.session});

  final MonitoredSession session;

  @override
  Widget build(BuildContext context) {
    final color = sessionStatusColor(context, session);
    return Tooltip(
      message: sessionStatusLabel(context, session),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

final class _DiscoveryWarning extends StatelessWidget {
  const _DiscoveryWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: ConsoleShapes.decoration(
        color: colors.warningSubtle,
        borderColor: colors.warning.withValues(alpha: 0.25),
        radius: ConsoleShapes.smallRadius,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 13, color: colors.warningFg),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.warningFg),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SessionListRow {
  const _SessionListRow.header({
    required this.projectPath,
    required this.projectName,
  }) : session = null;

  const _SessionListRow.session(this.session)
    : projectPath = null,
      projectName = null;

  final String? projectPath;
  final String? projectName;
  final MonitoredSession? session;
}

List<_SessionListRow> _sessionRows(List<MonitoredSession> sessions) {
  final grouped = <String, List<MonitoredSession>>{};
  for (final session in sessions) {
    grouped.putIfAbsent(session.projectPath, () => []).add(session);
  }
  return [
    for (final entry in grouped.entries) ...[
      _SessionListRow.header(
        projectPath: entry.key,
        projectName: entry.value.first.projectName,
      ),
      for (final session in entry.value) _SessionListRow.session(session),
    ],
  ];
}

String shortSessionId(String id) {
  if (id.length <= 10) return id;
  return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
}

String sessionStatusLabel(BuildContext context, MonitoredSession session) {
  final status = context.t.sessions.status;
  if (session.state == 'ready' && !session.bridgeReachable) {
    return status.reconnecting;
  }
  return sessionMonitorStateText(context, session.state);
}

Color sessionStatusColor(BuildContext context, MonitoredSession session) {
  final colors = context.consoleColors;
  if (session.healthy) return colors.success;
  return switch (session.state) {
    'failed' => colors.errorColor,
    'starting' || 'reloading' || 'restarting' || 'checking' => colors.info,
    'stopped' => colors.inkTertiary,
    _ => colors.warning,
  };
}
