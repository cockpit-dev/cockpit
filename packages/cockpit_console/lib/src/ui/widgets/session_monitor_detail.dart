import 'dart:async';

import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/providers/session_monitor_provider.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_data_view.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_network_view.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_runtime_views.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_session_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _liveLogRefreshInterval = Duration(seconds: 2);

final class SessionMonitorDetailPane extends HookConsumerWidget {
  const SessionMonitorDetailPane({
    required this.session,
    required this.detail,
    required this.section,
    required this.onSectionSelected,
    super.key,
  });

  final MonitoredSession? session;
  final SessionMonitorDetail? detail;
  final SessionMonitorSection section;
  final ValueChanged<SessionMonitorSection> onSectionSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSession = session;
    final currentDetail = detail;
    useEffect(() {
      if (currentSession != null &&
          currentDetail != null &&
          !_sectionLoaded(currentDetail, section)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(sessionMonitorProvider.notifier)
              .loadSection(currentSession.key, section);
        });
      }
      return null;
    }, [currentSession?.key, section]);
    useEffect(() {
      if (currentSession == null || section != SessionMonitorSection.logs) {
        return null;
      }
      final timer = Timer.periodic(_liveLogRefreshInterval, (_) {
        unawaited(
          ref
              .read(sessionMonitorProvider.notifier)
              .loadSection(
                currentSession.key,
                SessionMonitorSection.logs,
                silent: true,
              ),
        );
      });
      return timer.cancel;
    }, [currentSession?.key, section]);

    if (currentSession == null || currentDetail == null) {
      return Center(
        child: SessionInlineEmpty(
          icon: LucideIcons.mousePointerClick,
          message: context.t.sessions.selectPrompt,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionHeader(session: currentSession),
        Divider(height: 1, color: context.consoleColors.border),
        _SectionTabs(
          selected: section,
          loading: currentDetail.loading(section),
          onSelected: onSectionSelected,
          onRefresh: () => ref
              .read(sessionMonitorProvider.notifier)
              .loadSection(currentSession.key, section),
        ),
        Divider(height: 1, color: context.consoleColors.border),
        if (currentDetail.loading(section))
          const LinearProgressIndicator(minHeight: 2),
        if (currentDetail.sectionErrors[section] case final error?)
          _SectionError(
            message: error,
            onRetry: () => ref
                .read(sessionMonitorProvider.notifier)
                .loadSection(currentSession.key, section),
          ),
        Expanded(
          child: _SectionBody(
            section: section,
            session: currentSession,
            detail: currentDetail,
          ),
        ),
      ],
    );
  }
}

final class _SessionHeader extends ConsumerWidget {
  const _SessionHeader({required this.session});

  final MonitoredSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.consoleColors;
    void go(ConsoleNavDestination destination) {
      ref
          .read(selectedWorkspaceIdProvider.notifier)
          .select(session.key.workspaceId);
      ref.read(navProvider.notifier).go(destination);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: sessionStatusColor(context, session),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${session.projectName} · ${session.platform}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: ConsoleShapes.decoration(
                      color: sessionStatusColor(
                        context,
                        session,
                      ).withValues(alpha: 0.1),
                      radius: 6,
                    ),
                    child: Text(
                      sessionStatusLabel(context, session),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: sessionStatusColor(context, session),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Tooltip(
                message: session.key.sessionId,
                child: SelectableText(
                  context.t.sessions.sessionId(session: session.key.sessionId),
                  maxLines: 1,
                  style: consoleMono(size: 11, color: colors.inkSecondary),
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _ContextAction(
                icon: LucideIcons.smartphone,
                label: context.t.sessions.contextApp,
                tooltip: context.t.sessions.contextAppTip,
                onPressed: () => go(ConsoleNavDestination.targets),
              ),
              _ContextAction(
                icon: LucideIcons.command,
                label: context.t.sessions.contextActions,
                tooltip: context.t.sessions.contextActionsTip,
                onPressed: () => go(ConsoleNavDestination.operations),
              ),
              _ContextAction(
                icon: LucideIcons.fileCheck2,
                label: context.t.sessions.contextTests,
                tooltip: context.t.sessions.contextTestsTip,
                onPressed: () => go(ConsoleNavDestination.documents),
              ),
              _ContextAction(
                icon: LucideIcons.playCircle,
                label: context.t.sessions.contextRuns,
                tooltip: context.t.sessions.contextRunsTip,
                onPressed: () => go(ConsoleNavDestination.runs),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 10), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

final class _ContextAction extends StatelessWidget {
  const _ContextAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 13),
        label: Text(label),
      ),
    );
  }
}

final class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.selected,
    required this.loading,
    required this.onSelected,
    required this.onRefresh,
  });

  final SessionMonitorSection selected;
  final bool loading;
  final ValueChanged<SessionMonitorSection> onSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final section in SessionMonitorSection.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: _SectionTab(
                        section: section,
                        selected: section == selected,
                        onTap: () => onSelected(section),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              tooltip: context.t.sessions.refreshSection(
                section: sectionLabel(context, selected),
              ),
              onPressed: loading ? null : onRefresh,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SessionMonitorSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: ConsoleShapes.border(radius: ConsoleShapes.smallRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: ConsoleShapes.decoration(
            color: selected ? colors.accentSubtle : Colors.transparent,
            radius: ConsoleShapes.smallRadius,
          ),
          child: Text(
            sectionLabel(context, section),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? colors.accentSubtleFg : colors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

final class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.session,
    required this.detail,
  });

  final SessionMonitorSection section;
  final MonitoredSession session;
  final SessionMonitorDetail detail;

  @override
  Widget build(BuildContext context) => switch (section) {
    SessionMonitorSection.overview => SessionOverviewView(
      session: session,
      detail: detail,
    ),
    SessionMonitorSection.ui => SessionUiView(detail: detail),
    SessionMonitorSection.logs => SessionLogsView(detail: detail),
    SessionMonitorSection.network => SessionNetworkView(
      session: session,
      detail: detail,
    ),
    SessionMonitorSection.activity => SessionActivityView(detail: detail),
    SessionMonitorSection.diagnostics => SessionDiagnosticsView(detail: detail),
  };
}

final class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Container(
      color: colors.errorSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 14, color: colors.errorFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.errorFg),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.t.common.retry)),
        ],
      ),
    );
  }
}

String sectionLabel(BuildContext context, SessionMonitorSection section) =>
    switch (section) {
      SessionMonitorSection.overview => context.t.sessions.sections.overview,
      SessionMonitorSection.ui => context.t.sessions.sections.ui,
      SessionMonitorSection.logs => context.t.sessions.sections.logs,
      SessionMonitorSection.network => context.t.sessions.sections.network,
      SessionMonitorSection.activity => context.t.sessions.sections.activity,
      SessionMonitorSection.diagnostics =>
        context.t.sessions.sections.diagnostics,
    };

bool _sectionLoaded(
  SessionMonitorDetail detail,
  SessionMonitorSection section,
) {
  if (detail.sectionErrors.containsKey(section)) return true;
  return switch (section) {
    SessionMonitorSection.overview => detail.identity != null,
    SessionMonitorSection.ui => detail.ui != null,
    SessionMonitorSection.logs =>
      detail.logs != null || detail.sessionLogs != null,
    SessionMonitorSection.network => detail.network != null,
    SessionMonitorSection.activity => true,
    SessionMonitorSection.diagnostics =>
      detail.errors != null || detail.sessionLogs != null,
  };
}
