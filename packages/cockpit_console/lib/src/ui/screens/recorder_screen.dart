import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/providers/session_monitor_models.dart';
import 'package:cockpit_console/src/providers/session_monitor_provider.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/interaction_recorder_views.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_console/src/ui/widgets/session_monitor_session_list.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Records live app interactions of one monitored session into a replayable
/// case: connection to the session's recorder endpoint, live timeline,
/// controls, and export preview.
final class RecorderScreen extends ConsumerStatefulWidget {
  const RecorderScreen({super.key});

  static const double _splitBreakpoint = 860;

  @override
  ConsumerState<RecorderScreen> createState() => _RecorderScreenState();
}

final class _RecorderScreenState extends ConsumerState<RecorderScreen> {
  late final SessionMonitorNotifier _monitor;
  late final InteractionRecorderNotifier _recorder;

  @override
  void initState() {
    super.initState();
    _monitor = ref.read(sessionMonitorProvider.notifier);
    _recorder = ref.read(interactionRecorderProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _monitor.start();
      _recorder.startPolling();
      _adoptMonitorSelection();
    });
  }

  @override
  void dispose() {
    _recorder.stopPolling();
    _monitor.stop();
    super.dispose();
  }

  /// Until the user picks a session explicitly, the recorder follows the
  /// console-wide session selection the monitor maintains.
  void _adoptMonitorSelection() {
    if (ref.read(interactionRecorderProvider).selected != null) return;
    final key = ref.read(sessionMonitorProvider).selected;
    if (key != null) _recorder.select(key);
  }

  @override
  Widget build(BuildContext context) {
    final monitorState = ref.watch(sessionMonitorProvider);
    final state = ref.watch(interactionRecorderProvider);
    ref.listen(sessionMonitorProvider, (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _adoptMonitorSelection();
      });
    });

    return ScreenScaffold(
      title: context.t.recorder.title,
      subtitle: context.t.recorder.subtitle,
      stackActionsBelowWidth: 500,
      actions: [
        _PhaseBadge(phase: state.phase),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: state.connecting || state.selected == null
              ? null
              : () => _recorder.connect(),
          icon: state.connecting
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.refreshCw, size: 14),
          label: Text(
            state.endpoint == null
                ? context.t.recorder.connect
                : context.t.recorder.recheck,
          ),
        ),
      ],
      body: monitorState.sessions.isEmpty
          ? EmptyStateView(
              icon: LucideIcons.monitorOff,
              title: context.t.recorder.noSessionsTitle,
              description: context.t.recorder.noSessionsDescription,
            )
          : _buildBody(context, monitorState, state),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SessionMonitorState monitorState,
    InteractionRecorderState state,
  ) {
    final timeline = InteractionRecorderTimeline(steps: state.steps);
    final exportPane = InteractionRecorderExportPane(
      document: state.document,
      canExport: state.canExport,
      exporting: state.exporting,
      fileName: state.sessionId == null
          ? null
          : 'recorded-${state.sessionId}.yaml',
      onExport: () => _recorder.export(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SessionMonitorCompactPicker(
          sessions: monitorState.sessions,
          selected: state.selected ?? monitorState.selected,
          onSelect: _recorder.select,
        ),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        InteractionRecorderControls(
          state: state,
          onStart: (name) => _recorder.start(name: name),
          onPause: () => _recorder.pause(),
          onResume: () => _recorder.resume(),
          onStop: () => _recorder.stop(),
        ),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= RecorderScreen._splitBreakpoint;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: timeline),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                    SizedBox(width: 380, child: exportPane),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: timeline),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  SizedBox(height: 260, child: exportPane),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase});

  final CockpitRecorderPhase phase;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    final (background, foreground) = switch (phase) {
      CockpitRecorderPhase.recording => (
        colors.successSubtle,
        colors.successFg,
      ),
      CockpitRecorderPhase.paused => (colors.warningSubtle, colors.warningFg),
      CockpitRecorderPhase.idle ||
      CockpitRecorderPhase.stopped => (colors.surface2, colors.inkSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: ConsoleShapes.decoration(
        color: background,
        radius: ConsoleShapes.smallRadius,
      ),
      child: Text(
        switch (phase) {
          CockpitRecorderPhase.idle => context.t.recorder.phase.idle,
          CockpitRecorderPhase.recording => context.t.recorder.phase.recording,
          CockpitRecorderPhase.paused => context.t.recorder.phase.paused,
          CockpitRecorderPhase.stopped => context.t.recorder.phase.stopped,
        },
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
