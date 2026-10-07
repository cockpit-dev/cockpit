import 'dart:io';

import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/interaction_recorder_provider.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/console_copy_button.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Command area of the recorder page: start/pause/resume/stop with the
/// optional recording name, the live status line, and inline errors.
///
/// Enablement follows the recorder phase matrix; every command additionally
/// requires a resolved endpoint and no command in flight.
final class InteractionRecorderControls extends StatefulWidget {
  const InteractionRecorderControls({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    super.key,
  });

  final InteractionRecorderState state;
  final ValueChanged<String?> onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  State<InteractionRecorderControls> createState() =>
      _InteractionRecorderControlsState();
}

final class _InteractionRecorderControlsState
    extends State<InteractionRecorderControls> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final colors = context.consoleColors;
    final connected = state.endpoint != null;
    final interactive = connected && !state.commandBusy;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: state.canStart && interactive
                    ? () => widget.onStart(
                        _nameController.text.trim().isEmpty
                            ? null
                            : _nameController.text.trim(),
                      )
                    : null,
                icon: const Icon(LucideIcons.play, size: 14),
                label: Text(context.t.recorder.start),
              ),
              OutlinedButton.icon(
                onPressed: state.canPause && interactive
                    ? widget.onPause
                    : null,
                icon: const Icon(LucideIcons.pause, size: 14),
                label: Text(context.t.recorder.pause),
              ),
              OutlinedButton.icon(
                onPressed: state.canResume && interactive
                    ? widget.onResume
                    : null,
                icon: const Icon(LucideIcons.play, size: 14),
                label: Text(context.t.recorder.resume),
              ),
              OutlinedButton.icon(
                onPressed: state.canStop && interactive ? widget.onStop : null,
                icon: const Icon(LucideIcons.square, size: 14),
                label: Text(context.t.recorder.stop),
              ),
              if (state.canStart)
                SizedBox(
                  width: 220,
                  child: ConsoleTextField(
                    controller: _nameController,
                    label: context.t.recorder.nameLabel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.t.recorder.statusLine(
              phase: _phaseLabel(context, state.phase),
              steps: context.t.recorder.stepCount(n: state.stepCount),
              unresolved: context.t.recorder.unresolvedCount(
                n: state.unresolvedCount,
              ),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
          if (state.connectionError != null) ...[
            const SizedBox(height: 6),
            Text(
              state.connectionError!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.errorFg),
            ),
          ],
          if (state.commandError != null) ...[
            const SizedBox(height: 6),
            Text(
              state.commandError!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.errorFg),
            ),
          ],
        ],
      ),
    );
  }
}

/// Live step list, newest last and auto-scrolled to the newest step.
final class InteractionRecorderTimeline extends StatefulWidget {
  const InteractionRecorderTimeline({required this.steps, super.key});

  final List<CockpitInteractionStep> steps;

  @override
  State<InteractionRecorderTimeline> createState() =>
      _InteractionRecorderTimelineState();
}

final class _InteractionRecorderTimelineState
    extends State<InteractionRecorderTimeline> {
  final ScrollController _scrollController = ScrollController();
  int _observedStepCount = 0;

  @override
  void didUpdateWidget(covariant InteractionRecorderTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.steps.length > _observedStepCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.position.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      });
    }
    _observedStepCount = widget.steps.length;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.consoleColors;
    if (widget.steps.isEmpty) {
      return Center(
        child: Text(
          context.t.recorder.timelineEmpty,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.inkTertiary),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: widget.steps.length,
      itemBuilder: (context, index) {
        final step = widget.steps[index];
        final settledAfterMs = step.settledAfterMs;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _KindBadge(kind: step.kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.locatorCandidates.isEmpty
                          ? context.t.recorder.unresolvedStep
                          : step.locatorCandidates.first.selector,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: step.locatorCandidates.isEmpty
                            ? colors.inkTertiary
                            : colors.inkPrimary,
                      ),
                    ),
                    if (step.annotation != null)
                      Text(
                        step.annotation!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.inkSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (settledAfterMs != null) ...[
                const SizedBox(width: 8),
                Text(
                  context.t.recorder.settledAfter(ms: settledAfterMs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.successFg,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                step.stepId,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkTertiary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Export area: preview of the case YAML with copy and save actions.
final class InteractionRecorderExportPane extends StatelessWidget {
  const InteractionRecorderExportPane({
    required this.document,
    required this.canExport,
    required this.exporting,
    required this.fileName,
    required this.onExport,
    super.key,
  });

  final String? document;
  final bool canExport;
  final bool exporting;
  final String? fileName;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.consoleColors;
    final document = this.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                context.t.recorder.exportTitle,
                style: theme.textTheme.labelLarge,
              ),
              OutlinedButton.icon(
                onPressed: canExport && !exporting ? onExport : null,
                icon: exporting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.fileDown, size: 14),
                label: Text(context.t.recorder.export),
              ),
              if (document != null) ...[
                ConsoleCopyButton(
                  text: document,
                  copyLabel: context.t.recorder.copyYaml,
                  copiedLabel: context.t.recorder.yamlCopied,
                  variant: ConsoleCopyButtonVariant.labeled,
                ),
                OutlinedButton.icon(
                  onPressed: () => _save(context),
                  icon: const Icon(LucideIcons.save, size: 14),
                  label: Text(context.t.recorder.save),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: document == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.t.recorder.exportHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.inkTertiary,
                      ),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    document,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Mirrors the runs screen artifact save: native save panel, then an
  /// inline-adjacent confirmation through the shell's snackbar.
  Future<void> _save(BuildContext context) async {
    final document = this.document;
    if (document == null) return;
    final destination = await FilePicker.saveFile(
      dialogTitle: context.t.recorder.saveDocument,
      fileName: fileName ?? 'recorded-flow.yaml',
    );
    if (destination == null) return;
    try {
      await File(destination).writeAsString('$document\n', flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.recorder.documentSaved(path: destination)),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t.recorder.saveFailed(error: error.toString()),
            ),
          ),
        );
      }
    }
  }
}

final class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final CockpitInteractionStepKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.consoleColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ConsoleShapes.decoration(
        color: colors.surface2,
        radius: ConsoleShapes.smallRadius,
      ),
      child: Text(
        _kindLabel(context, kind),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.inkSecondary),
      ),
    );
  }
}

String _kindLabel(BuildContext context, CockpitInteractionStepKind kind) =>
    switch (kind) {
      CockpitInteractionStepKind.tap => context.t.recorder.kind.tap,
      CockpitInteractionStepKind.longPress => context.t.recorder.kind.longPress,
      CockpitInteractionStepKind.text => context.t.recorder.kind.text,
      CockpitInteractionStepKind.scroll => context.t.recorder.kind.scroll,
      CockpitInteractionStepKind.routeChange =>
        context.t.recorder.kind.routeChange,
      CockpitInteractionStepKind.back => context.t.recorder.kind.back,
      CockpitInteractionStepKind.marker => context.t.recorder.kind.marker,
      CockpitInteractionStepKind.note => context.t.recorder.kind.note,
    };

String _phaseLabel(BuildContext context, CockpitRecorderPhase phase) =>
    switch (phase) {
      CockpitRecorderPhase.idle => context.t.recorder.phase.idle,
      CockpitRecorderPhase.recording => context.t.recorder.phase.recording,
      CockpitRecorderPhase.paused => context.t.recorder.phase.paused,
      CockpitRecorderPhase.stopped => context.t.recorder.phase.stopped,
    };
