import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/providers/session_monitor_provider.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_detail.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_session_list.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Read-only workspace for observing every Cockpit development session.
final class SessionMonitorScreen extends ConsumerStatefulWidget {
  const SessionMonitorScreen({super.key});

  static const double _splitBreakpoint = 720;

  @override
  ConsumerState<SessionMonitorScreen> createState() =>
      _SessionMonitorScreenState();
}

final class _SessionMonitorScreenState
    extends ConsumerState<SessionMonitorScreen> {
  SessionMonitorSection _section = SessionMonitorSection.overview;
  late final SessionMonitorNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(sessionMonitorProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifier.start();
    });
  }

  @override
  void dispose() {
    _notifier.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionMonitorProvider);
    final notifier = ref.read(sessionMonitorProvider.notifier);
    final liveCount = state.sessions.where((session) => session.live).length;

    return ScreenScaffold(
      title: context.t.sessions.title,
      subtitle: context.t.sessions.subtitle,
      stackActionsBelowWidth: 500,
      actions: [
        _LiveCount(count: liveCount, total: state.sessions.length),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: state.loading
              ? null
              : () => notifier.refresh(forceProbe: true),
          icon: state.loading
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 14),
          label: Text(context.t.common.refresh),
        ),
      ],
      body: _buildBody(context, state, notifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SessionMonitorState state,
    SessionMonitorNotifier notifier,
  ) {
    if (state.loading && state.sessions.isEmpty) {
      return EmptyStateView(
        icon: LucideIcons.radio,
        title: context.t.sessions.findingTitle,
        description: context.t.sessions.findingDescription,
        iconSpin: true,
      );
    }
    if (state.sessions.isEmpty) {
      return EmptyStateView(
        icon: LucideIcons.monitorOff,
        title: context.t.sessions.emptyTitle,
        description: context.t.sessions.emptyDescription,
        action: OutlinedButton.icon(
          onPressed: () => notifier.refresh(forceProbe: true),
          icon: const Icon(LucideIcons.refreshCw, size: 14),
          label: Text(context.t.sessions.checkAgain),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= SessionMonitorScreen._splitBreakpoint;
        final detail = SessionMonitorDetailPane(
          session: state.selectedSession,
          detail: state.selected == null ? null : state.detail(state.selected!),
          section: _section,
          onSectionSelected: (section) => setState(() => _section = section),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 300,
                child: SessionMonitorSessionList(
                  sessions: state.sessions,
                  selected: state.selected,
                  error: state.error,
                  onSelect: notifier.select,
                ),
              ),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              Expanded(child: detail),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SessionMonitorCompactPicker(
              sessions: state.sessions,
              selected: state.selected,
              error: state.error,
              onSelect: notifier.select,
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

final class _LiveCount extends StatelessWidget {
  const _LiveCount({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Semantics(
      label: context.t.sessions.liveCountSemantics(live: count, total: total),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: ConsoleShapes.decoration(
          color: colors.successSubtle,
          radius: ConsoleShapes.smallRadius,
        ),
        child: Text(
          context.t.sessions.liveCount(live: count, total: total),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.successFg),
        ),
      ),
    );
  }
}
