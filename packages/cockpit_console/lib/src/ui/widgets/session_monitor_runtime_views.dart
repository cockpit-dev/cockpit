import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/widgets/console_copy_button.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_data_view.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:lucide_icons_flutter/lucide_icons.dart';

final class SessionOverviewView extends StatelessWidget {
  const SessionOverviewView({
    required this.session,
    required this.detail,
    super.key,
  });

  final MonitoredSession session;
  final SessionMonitorDetail detail;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions;
    final overview = strings.overview;
    final identity = detail.identity;
    final status = mapValue(identity?['status']);
    final runtime = mapValue(identity?['runtime']);
    return _SectionScroll(
      children: [
        if (session.message case final message?)
          _MessageBanner(
            message: sessionMonitorMessageText(context, message),
            session: session,
          ),
        _MetricStrip(
          metrics: [
            _Metric(
              label: overview.appProcess,
              value: switch (session.appReachable) {
                true => overview.reachable,
                false => overview.unavailable,
                null => overview.checking,
              },
              tone: switch (session.appReachable) {
                true => _MetricTone.success,
                false => _MetricTone.warning,
                null => _MetricTone.neutral,
              },
            ),
            _Metric(
              label: overview.bridge,
              value: session.bridgeReachable
                  ? overview.connected
                  : overview.disconnected,
              tone: session.bridgeReachable
                  ? _MetricTone.success
                  : _MetricTone.warning,
            ),
            _Metric(
              label: overview.runtimeErrors,
              value: '${session.errorCount}',
              tone: session.errorCount > 0
                  ? _MetricTone.error
                  : _MetricTone.neutral,
            ),
            _Metric(
              label: overview.networkFailures,
              value: '${session.networkFailureCount}',
              tone: session.networkFailureCount > 0
                  ? _MetricTone.warning
                  : _MetricTone.neutral,
            ),
          ],
        ),
        SessionSectionCard(
          title: overview.currentState,
          subtitle: overview.currentStateDescription,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                SessionInfoRow(label: overview.route, value: session.route),
                SessionInfoRow(label: overview.lifecycle, value: session.state),
                SessionInfoRow(
                  label: overview.reloadGeneration,
                  value: '${session.reloadGeneration}',
                ),
                SessionInfoRow(
                  label: overview.lastRuntimeStatus,
                  value: session.runtimeStatusAt == null
                      ? null
                      : formatSessionTime(session.runtimeStatusAt!),
                ),
                SessionInfoRow(
                  label: overview.nextStep,
                  value: _nextStepLabel(
                    context,
                    stringValue(identity?['recommendedNextStep']),
                  ),
                ),
                SessionInfoRow(
                  label: overview.lastError,
                  value: stringValue(status?['lastError']),
                ),
              ],
            ),
          ),
        ),
        SessionSectionCard(
          title: overview.launchIdentity,
          subtitle: overview.launchIdentityDescription,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                SessionInfoRow(
                  label: overview.project,
                  value: session.projectPath,
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(
                  label: overview.workspace,
                  value: session.key.workspaceId,
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(
                  label: overview.session,
                  value: session.key.sessionId,
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(
                  label: overview.target,
                  value: session.targetId,
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(label: overview.device, value: session.deviceId),
                SessionInfoRow(
                  label: overview.entrypoint,
                  value: session.entrypoint,
                  monospace: true,
                ),
                SessionInfoRow(label: overview.flavor, value: session.flavor),
                SessionInfoRow(
                  label: overview.appId,
                  value: session.appId,
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(
                  label: overview.vmService,
                  value: stringValue(runtime?['vmServiceUri']),
                  monospace: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class SessionUiView extends StatelessWidget {
  const SessionUiView({required this.detail, super.key});

  final SessionMonitorDetail detail;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.ui;
    final ui = detail.ui;
    if (ui == null) {
      return SessionInlineEmpty(
        icon: LucideIcons.component,
        message: strings.open,
      );
    }
    final snapshot = mapValue(ui['snapshot']);
    final summary = mapValue(snapshot?['summary']) ?? mapValue(ui['uiSummary']);
    final tree = mapValue(ui['fullTree']);
    final completeness = mapValue(ui['completeness']);
    return _SectionScroll(
      children: [
        SessionSectionCard(
          title: strings.current,
          subtitle: strings.description,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                SessionInfoRow(
                  label: context.t.sessions.overview.route,
                  value: stringValue(ui['routeName']),
                ),
                SessionInfoRow(
                  label: strings.snapshotFile,
                  value: stringValue(completeness?['snapshotPath']),
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(
                  label: strings.treeFile,
                  value: stringValue(completeness?['widgetTreePath']),
                  monospace: true,
                  copyable: true,
                ),
                SessionInfoRow(
                  label: strings.targets,
                  value: scalarText(summary?['visibleTargetCount']),
                ),
                SessionInfoRow(
                  label: strings.elements,
                  value: scalarText(tree?['emitted'] ?? tree?['total']),
                ),
                SessionInfoRow(
                  label: strings.snapshotTruncated,
                  value: scalarText(snapshot?['truncated'] ?? ui['truncated']),
                ),
                SessionInfoRow(
                  label: strings.treeTruncated,
                  value: scalarText(tree?['truncated']),
                ),
              ],
            ),
          ),
        ),
        if (stringValue(completeness?['snapshotError']) case final error?)
          _DataWarning(message: error),
        if (stringValue(completeness?['widgetTreeError']) case final error?)
          _DataWarning(message: error),
        SessionDataView(
          title: strings.completeSnapshot,
          value: snapshot,
          emptyMessage: strings.snapshotUnavailable,
          copyLabel: strings.copySnapshot,
        ),
        SessionDataView(
          title: strings.fullTree,
          value: tree,
          emptyMessage: strings.treeUnavailable,
          copyLabel: strings.copyTree,
        ),
        SessionDataView(
          title: strings.metadata,
          value: _withoutLargeUiPayloads(ui),
          emptyMessage: strings.metadataEmpty,
          copyLabel: strings.copyMetadata,
        ),
      ],
    );
  }
}

final class SessionLogsView extends StatelessWidget {
  const SessionLogsView({required this.detail, super.key});

  final SessionMonitorDetail detail;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.logs;
    final appLogs = detail.logs;
    final sessionLogs = detail.sessionLogs;
    if (appLogs == null && sessionLogs == null) {
      return SessionInlineEmpty(icon: LucideIcons.logs, message: strings.open);
    }
    final appLines = stringList(appLogs?['lines']);
    final sessionLines = stringList(sessionLogs?['lines']);
    final appPath = stringValue(appLogs?['logPath']);
    final sessionPath = stringValue(sessionLogs?['logPath']);
    final duplicateSupervisorLog =
        appLogs?['source'] == 'supervisor' &&
        appPath != null &&
        appPath == sessionPath;
    final appMissing = stringValue(appLogs?['missingReason']);
    final sessionMissing = stringValue(sessionLogs?['missingReason']);
    return _SectionScroll(
      children: [
        SessionSectionCard(
          key: const ValueKey('session-startup-logs'),
          title: strings.startupTitle,
          subtitle: _liveLogSubtitle(
            live: strings.live,
            latestBelow: strings.latestBelow,
            empty: sessionMissing ?? strings.startupNone,
            recent: strings.startupRecent(n: sessionLines.length),
            hasLines: sessionLines.isNotEmpty,
            truncated: sessionLogs?['truncated'] == true,
            olderHidden: strings.olderHidden,
          ),
          trailing: _LogCopyActions(lines: sessionLines, path: sessionPath),
          collapsible: true,
          initiallyExpanded: sessionLines.isNotEmpty || appLines.isEmpty,
          expandLabel: strings.expand,
          collapseLabel: strings.collapse,
          child: sessionLines.isEmpty
              ? SessionInlineEmpty(
                  icon: LucideIcons.logs,
                  message: sessionMissing ?? strings.startupRunningEmpty,
                )
              : _LogLines(lines: sessionLines),
        ),
        if (!duplicateSupervisorLog)
          SessionSectionCard(
            key: const ValueKey('session-app-logs'),
            title: strings.title,
            subtitle: _liveLogSubtitle(
              live: strings.live,
              latestBelow: strings.latestBelow,
              empty: appMissing ?? strings.none,
              recent: strings.recent(n: appLines.length),
              hasLines: appLines.isNotEmpty,
              truncated: appLogs?['truncated'] == true,
              olderHidden: strings.olderHidden,
            ),
            trailing: _LogCopyActions(lines: appLines, path: appPath),
            collapsible: true,
            initiallyExpanded: sessionLines.isEmpty && appLines.isNotEmpty,
            expandLabel: strings.expand,
            collapseLabel: strings.collapse,
            child: appLines.isEmpty
                ? SessionInlineEmpty(
                    icon: LucideIcons.logs,
                    message: appMissing ?? strings.runningEmpty,
                  )
                : _LogLines(lines: appLines),
          ),
      ],
    );
  }
}

final class _LogCopyActions extends StatelessWidget {
  const _LogCopyActions({required this.lines, required this.path});

  final List<String> lines;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.logs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lines.isNotEmpty)
          ConsoleCopyButton(
            text: lines.join('\n'),
            copyLabel: strings.copyLines,
            copiedLabel: strings.linesCopied,
          ),
        if (path case final logPath?)
          ConsoleCopyButton(
            text: logPath,
            copyLabel: strings.copyPath,
            copiedLabel: strings.pathCopied,
            icon: LucideIcons.fileText,
          ),
      ],
    );
  }
}

String _liveLogSubtitle({
  required String live,
  required String latestBelow,
  required String empty,
  required String recent,
  required bool hasLines,
  required bool truncated,
  required String olderHidden,
}) {
  final summary = hasLines ? '$recent${truncated ? olderHidden : ''}' : empty;
  return '$live · $summary · $latestBelow';
}

enum _ActivityFilter { all, lifecycle, routes, runtime, network }

final class SessionActivityView extends StatefulWidget {
  const SessionActivityView({required this.detail, super.key});

  final SessionMonitorDetail detail;

  @override
  State<SessionActivityView> createState() => _SessionActivityViewState();
}

final class _SessionActivityViewState extends State<SessionActivityView> {
  _ActivityFilter _filter = _ActivityFilter.all;
  SessionMonitorActivity? _expanded;

  @override
  Widget build(BuildContext context) {
    final activity = widget.detail.activity;
    if (activity.isEmpty) {
      return SessionInlineEmpty(
        icon: LucideIcons.history,
        message: context.t.sessions.activityEmpty,
      );
    }

    final visible = <int>[];
    for (var index = activity.length - 1; index >= 0; index--) {
      if (_matchesActivityFilter(activity[index], _filter)) {
        visible.add(index);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActivityToolbar(
          selected: _filter,
          visible: visible.length,
          total: activity.length,
          onSelected: (filter) {
            setState(() {
              _filter = filter;
              _expanded = null;
            });
          },
        ),
        Divider(height: 1, color: context.consoleColors.border),
        if (widget.detail.activityDropped > 0)
          _ActivityRetentionNotice(count: widget.detail.activityDropped),
        Expanded(
          child: visible.isEmpty
              ? SessionInlineEmpty(
                  icon: LucideIcons.listFilter,
                  message: context.t.sessions.timeline.noMatch,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(480),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final sourceIndex = visible[index];
                    final item = activity[sourceIndex];
                    return _ActivityTimelineItem(
                      key: ValueKey(
                        '${item.at.microsecondsSinceEpoch}:${item.kind.name}:$sourceIndex',
                      ),
                      item: item,
                      first: index == 0,
                      last: index == visible.length - 1,
                      expanded: identical(_expanded, item),
                      onToggle: () {
                        setState(() {
                          _expanded = identical(_expanded, item) ? null : item;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

final class _ActivityToolbar extends StatelessWidget {
  const _ActivityToolbar({
    required this.selected,
    required this.visible,
    required this.total,
    required this.onSelected,
  });

  final _ActivityFilter selected;
  final int visible;
  final int total;
  final ValueChanged<_ActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.timeline;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              itemCount: _ActivityFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final filter = _ActivityFilter.values[index];
                return ChoiceChip(
                  selected: selected == filter,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text(_activityFilterLabel(context, filter)),
                  onSelected: (_) => onSelected(filter),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: strings.newestFirst,
              child: Text(
                '${strings.newestFirst} · ${strings.showing(visible: visible, total: total)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.consoleColors.inkTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ActivityRetentionNotice extends StatelessWidget {
  const _ActivityRetentionNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return ColoredBox(
      color: colors.surface1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            Icon(LucideIcons.archive, size: 13, color: colors.inkTertiary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                context.t.sessions.timeline.discarded(n: count),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class SessionDiagnosticsView extends StatelessWidget {
  const SessionDiagnosticsView({required this.detail, super.key});

  final SessionMonitorDetail detail;

  @override
  Widget build(BuildContext context) {
    final strings = context.t.sessions.diagnostics;
    if (detail.errors == null && detail.sessionLogs == null) {
      return SessionInlineEmpty(
        icon: LucideIcons.stethoscope,
        message: strings.open,
      );
    }
    final errors = objectList(detail.errors?['errors']);
    final sessionLines = stringList(detail.sessionLogs?['lines']);
    final sessionLogsMissing = stringValue(
      detail.sessionLogs?['missingReason'],
    );
    return _SectionScroll(
      children: [
        SessionSectionCard(
          title: strings.runtimeErrors,
          subtitle: errors.isEmpty
              ? strings.noRuntimeErrors
              : strings.capturedErrors(n: errors.length),
          child: errors.isEmpty
              ? SessionInlineEmpty(
                  icon: LucideIcons.circleCheck,
                  message: strings.noRuntimeErrors,
                )
              : _RuntimeErrorsList(errors: errors),
        ),
        SessionSectionCard(
          title: strings.sessionLogs,
          subtitle:
              sessionLogsMissing ??
              (sessionLines.isEmpty
                  ? strings.noSessionLines
                  : strings.recentSessionLines(n: sessionLines.length)),
          child: sessionLines.isEmpty
              ? SessionInlineEmpty(
                  icon: LucideIcons.logs,
                  message: sessionLogsMissing ?? strings.sessionLogsUnavailable,
                )
              : _LogLines(lines: sessionLines),
        ),
      ],
    );
  }
}

final class _SectionScroll extends StatelessWidget {
  const _SectionScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) => children[index],
    );
  }
}

final class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.session});

  final String message;
  final MonitoredSession session;

  @override
  Widget build(BuildContext context) {
    final error = session.state == 'failed';
    final colors = context.consoleColors;
    final color = error ? colors.errorFg : colors.warningFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ConsoleShapes.decoration(
        color: error ? colors.errorSubtle : colors.warningSubtle,
        borderColor: color.withValues(alpha: 0.25),
      ),
      child: Row(
        children: [
          Icon(
            error ? LucideIcons.circleAlert : LucideIcons.triangleAlert,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DataWarning extends StatelessWidget {
  const _DataWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ConsoleShapes.decoration(
        color: colors.warningSubtle,
        borderColor: colors.warning.withValues(alpha: 0.25),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 15, color: colors.warningFg),
          const SizedBox(width: 9),
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

final class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ConsoleShapes.decoration(
        color: context.consoleColors.surface1,
        borderColor: context.consoleColors.border,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 560
              ? constraints.maxWidth / 2
              : constraints.maxWidth / metrics.length;
          return Wrap(
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: _MetricCell(metric: metric),
                ),
            ],
          );
        },
      ),
    );
  }
}

final class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final color = metric.tone.color(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric.label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

final class _Metric {
  const _Metric({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final _MetricTone tone;
}

enum _MetricTone {
  neutral,
  success,
  warning,
  error;

  Color color(BuildContext context) => switch (this) {
    _MetricTone.neutral => context.consoleColors.inkPrimary,
    _MetricTone.success => context.consoleColors.successFg,
    _MetricTone.warning => context.consoleColors.warningFg,
    _MetricTone.error => context.consoleColors.errorFg,
  };
}

final class _LogLines extends StatelessWidget {
  const _LogLines({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final visibleRows = lines.length.clamp(1, 16);
    final height = (20 + visibleRows * 18).clamp(80, 320).toDouble();
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: context.consoleColors.bg,
        child: SelectionArea(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[lines.length - index - 1];
              return Text(
                line,
                style: consoleMono(
                  size: 11,
                  color: context.consoleColors.inkSecondary,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _ActivityTimelineItem extends StatelessWidget {
  const _ActivityTimelineItem({
    required this.item,
    required this.first,
    required this.last,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final SessionMonitorActivity item;
  final bool first;
  final bool last;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = sessionMonitorActivityText(context, item);
    final colors = context.consoleColors;
    final color = switch (item.severity) {
      SessionMonitorSeverity.info => context.consoleColors.info,
      SessionMonitorSeverity.success => context.consoleColors.success,
      SessionMonitorSeverity.warning => context.consoleColors.warning,
      SessionMonitorSeverity.error => context.consoleColors.errorColor,
    };
    final timeline = context.t.sessions.timeline;
    return Material(
      color: expanded ? colors.surface1 : Colors.transparent,
      shape: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        customBorder: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
        child: Semantics(
          button: true,
          label: '${text.label}, ${text.detail}',
          hint: expanded ? timeline.collapse : timeline.expand,
          excludeSemantics: true,
          child: Stack(
            children: [
              if (!first)
                Positioned(
                  left: 18.5,
                  top: 0,
                  height: 13,
                  child: ColoredBox(
                    color: colors.border,
                    child: const SizedBox(width: 1),
                  ),
                ),
              if (!last)
                Positioned(
                  left: 18.5,
                  top: 13,
                  bottom: 0,
                  child: ColoredBox(
                    color: colors.border,
                    child: const SizedBox(width: 1),
                  ),
                ),
              Positioned(
                left: 15,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 1.5),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 7, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            text.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatSessionTime(item.at),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.inkTertiary),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: expanded
                              ? timeline.collapse
                              : timeline.expand,
                          child: Icon(
                            expanded
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            size: 13,
                            color: colors.inkTertiary,
                          ),
                        ),
                      ],
                    ),
                    if (text.detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        text.detail,
                        maxLines: expanded ? null : 1,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.inkSecondary,
                        ),
                      ),
                    ],
                    if (expanded) ...[
                      const SizedBox(height: 7),
                      Text(
                        '${_activityFilterLabel(context, _filterForActivity(item))} · '
                        '${_activitySeverityLabel(context, item.severity)} · '
                        '${formatSessionDateTime(context, item.at)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.inkTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _RuntimeErrorRow extends StatelessWidget {
  const _RuntimeErrorRow({required this.error});

  final Map<String, Object?> error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 15,
            color: context.consoleColors.errorFg,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  stringValue(error['message']) ??
                      context.t.sessions.diagnostics.runtimeError,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.consoleColors.inkPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    stringValue(error['source']),
                    stringValue(error['routeName']),
                    stringValue(error['recordedAt']),
                  ].whereType<String>().join(' · '),
                  style: consoleMono(
                    size: 10,
                    color: context.consoleColors.inkTertiary,
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

final class _RuntimeErrorsList extends StatelessWidget {
  const _RuntimeErrorsList({required this.errors});

  final List<Map<String, Object?>> errors;

  @override
  Widget build(BuildContext context) {
    final height = (errors.length * 92).clamp(120, 520).toDouble();
    return SizedBox(
      height: height,
      child: ListView.separated(
        itemCount: errors.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.consoleColors.border),
        itemBuilder: (context, index) => _RuntimeErrorRow(error: errors[index]),
      ),
    );
  }
}

Map<String, Object?>? mapValue(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

String? stringValue(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String? scalarText(Object? value) => value == null ? null : '$value';

String? _nextStepLabel(BuildContext context, String? value) {
  if (value == null) return null;
  if (value == 'ready_for_incremental_probe') {
    return context.t.sessions.overview.noActionNeeded;
  }
  if (!value.contains('_')) return value;
  final words = value.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return null;
  final first = words.first;
  words[0] = '${first[0].toUpperCase()}${first.substring(1)}';
  return words.join(' ');
}

List<String> stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

List<Map<String, Object?>> objectList(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) Map<String, Object?>.from(item),
      ]
    : const <Map<String, Object?>>[];

Map<String, Object?> _withoutLargeUiPayloads(Map<String, Object?> value) =>
    Map<String, Object?>.of(value)
      ..remove('snapshot')
      ..remove('fullTree');

bool _matchesActivityFilter(
  SessionMonitorActivity activity,
  _ActivityFilter filter,
) => switch (filter) {
  _ActivityFilter.all => true,
  _ActivityFilter.lifecycle => switch (activity.kind) {
    SessionMonitorActivityKind.discovered ||
    SessionMonitorActivityKind.connected ||
    SessionMonitorActivityKind.changed ||
    SessionMonitorActivityKind.appUnavailable ||
    SessionMonitorActivityKind.appReachable ||
    SessionMonitorActivityKind.bridgeConnected ||
    SessionMonitorActivityKind.bridgeDisconnected => true,
    _ => false,
  },
  _ActivityFilter.routes =>
    activity.kind == SessionMonitorActivityKind.routeChanged,
  _ActivityFilter.runtime =>
    activity.kind == SessionMonitorActivityKind.runtimeError,
  _ActivityFilter.network =>
    activity.kind == SessionMonitorActivityKind.networkFailure,
};

_ActivityFilter _filterForActivity(SessionMonitorActivity activity) =>
    switch (activity.kind) {
      SessionMonitorActivityKind.routeChanged => _ActivityFilter.routes,
      SessionMonitorActivityKind.runtimeError => _ActivityFilter.runtime,
      SessionMonitorActivityKind.networkFailure => _ActivityFilter.network,
      _ => _ActivityFilter.lifecycle,
    };

String _activityFilterLabel(BuildContext context, _ActivityFilter filter) {
  final strings = context.t.sessions.timeline;
  return switch (filter) {
    _ActivityFilter.all => strings.all,
    _ActivityFilter.lifecycle => strings.lifecycle,
    _ActivityFilter.routes => strings.routes,
    _ActivityFilter.runtime => strings.runtime,
    _ActivityFilter.network => strings.network,
  };
}

String _activitySeverityLabel(
  BuildContext context,
  SessionMonitorSeverity severity,
) {
  final strings = context.t.sessions.timeline.severity;
  return switch (severity) {
    SessionMonitorSeverity.info => strings.info,
    SessionMonitorSeverity.success => strings.success,
    SessionMonitorSeverity.warning => strings.warning,
    SessionMonitorSeverity.error => strings.error,
  };
}

String formatSessionTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String formatSessionDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatShortDate(local);
  return '$date ${formatSessionTime(value)}';
}
