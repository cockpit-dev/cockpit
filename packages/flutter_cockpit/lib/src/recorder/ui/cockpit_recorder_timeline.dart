import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import '../cockpit_replay_report.dart';
import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_panel_widgets.dart';

/// Timeline hero of the recorder panel: the live step list, newest last and
/// auto-scrolled to the newest step, with per-row annotate, replay outcome
/// badges joined from the controller's last verify-replay pass, and delete.
///
/// Delete is an engine constraint, not a UI preference: only the most
/// recently recorded step can be discarded, so the button appears on the
/// last row alone while recording.
final class CockpitRecorderTimeline extends StatefulWidget {
  /// Creates a timeline over the controller's current steps.
  const CockpitRecorderTimeline({required this.controller, super.key});

  final CockpitRecorderController controller;

  @override
  State<CockpitRecorderTimeline> createState() =>
      _CockpitRecorderTimelineState();
}

final class _CockpitRecorderTimelineState
    extends State<CockpitRecorderTimeline> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _noteController = TextEditingController();

  /// Step id whose inline annotate field is open; `null` when none is.
  String? _annotatingStepId;
  int _observedStepCount = 0;

  @override
  void initState() {
    super.initState();
    _observedStepCount = widget.controller.steps.length;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant CockpitRecorderTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      _observedStepCount = widget.controller.steps.length;
      widget.controller.addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _scrollController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Appended steps arrive as controller notifications, so the scroll hook
  /// lives on the controller listener rather than on widget updates.
  void _handleControllerChange() {
    final count = widget.controller.steps.length;
    final grew = count > _observedStepCount;
    _observedStepCount = count;
    if (!grew) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.position.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    });
  }

  void _openAnnotation(CockpitInteractionStep step) {
    setState(() {
      _annotatingStepId = step.stepId;
      _noteController.text = step.annotation ?? '';
    });
  }

  void _closeAnnotation() {
    setState(() => _annotatingStepId = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final steps = widget.controller.steps;
        if (steps.isEmpty) {
          return const Center(
            child: Text(
              'No steps recorded yet.',
              style: cockpitRecorderPanelCaptionStyle,
            ),
          );
        }
        final replayById = <String, CockpitReplayReport>{
          for (final report
              in widget.controller.replayReports ??
                  const <CockpitReplayReport>[])
            report.stepId: report,
        };
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          itemCount: steps.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final step = steps[index];
            return _CockpitRecorderTimelineRow(
              key: ValueKey<String>(step.stepId),
              step: step,
              isLast: index == steps.length - 1,
              canMutate:
                  widget.controller.phase == CockpitRecorderPhase.recording,
              canDelete: widget.controller.canDiscardLast,
              annotating: _annotatingStepId == step.stepId,
              noteController: _noteController,
              replay: replayById[step.stepId],
              onAnnotate: () => _annotatingStepId == step.stepId
                  ? _closeAnnotation()
                  : _openAnnotation(step),
              onSaveAnnotation: (note) {
                widget.controller.annotate(step.stepId, note);
                _closeAnnotation();
              },
              onDelete: widget.controller.discardLastStep,
            );
          },
        );
      },
    );
  }
}

class _CockpitRecorderTimelineRow extends StatelessWidget {
  const _CockpitRecorderTimelineRow({
    required this.step,
    required this.isLast,
    required this.canMutate,
    required this.canDelete,
    required this.annotating,
    required this.noteController,
    required this.replay,
    required this.onAnnotate,
    required this.onSaveAnnotation,
    required this.onDelete,
    super.key,
  });

  final CockpitInteractionStep step;
  final bool isLast;
  final bool canMutate;
  final bool canDelete;
  final bool annotating;
  final TextEditingController noteController;
  final CockpitReplayReport? replay;
  final VoidCallback onAnnotate;
  final ValueChanged<String> onSaveAnnotation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final annotation = step.annotation;
    final replay = this.replay;
    final reason = replay?.reason;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cockpitRecorderPanelSurface.withAlpha(0x66),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cockpitRecorderPanelBorder.withAlpha(0x80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CockpitRecorderPanelChip(label: step.stepId),
              const SizedBox(width: 6),
              CockpitRecorderPanelChip(
                label: step.kind.name,
                color: cockpitRecorderStepKindColor(step.kind),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.unresolved
                      ? '(unresolved)'
                      : step.locatorCandidates.isEmpty
                      ? step.resolvedValue ?? step.routeName ?? step.kind.name
                      : step.locatorCandidates.first.selector,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: cockpitRecorderPanelTextStyle,
                ),
              ),
              if (step.settledAfterMs != null) ...<Widget>[
                const SizedBox(width: 6),
                CockpitRecorderPanelChip(
                  label: 'settled ${step.settledAfterMs}ms',
                  color: cockpitRecorderPanelAccent,
                ),
              ],
              if (replay != null) ...<Widget>[
                const SizedBox(width: 6),
                _replayBadge(replay),
              ],
            ],
          ),
          if (step.segments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: <Widget>[
                  for (final segment in step.segments)
                    CockpitRecorderPanelChip(label: segment),
                ],
              ),
            ),
          if (annotation != null && !annotating)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'note: $annotation',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: cockpitRecorderPanelCaptionStyle,
              ),
            ),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: cockpitRecorderPanelCaptionStyle.copyWith(
                  color: _replayColor(replay!.status),
                ),
              ),
            ),
          if (annotating)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: CockpitRecorderPanelTextField(
                      controller: noteController,
                      hint: 'note',
                      onSubmitted: onSaveAnnotation,
                    ),
                  ),
                  const SizedBox(width: 6),
                  CockpitRecorderPanelButton(
                    label: 'Save',
                    onPressed: canMutate
                        ? () => onSaveAnnotation(noteController.text)
                        : null,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                CockpitRecorderPanelButton(
                  label: 'Annotate',
                  onPressed: canMutate ? onAnnotate : null,
                ),
                if (isLast) ...<Widget>[
                  const SizedBox(width: 6),
                  CockpitRecorderPanelButton(
                    label: 'Delete',
                    onPressed: canDelete ? onDelete : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replayBadge(CockpitReplayReport report) {
    return CockpitRecorderPanelChip(
      label: switch (report.status) {
        CockpitReplayStatus.passed => '✓ passed',
        CockpitReplayStatus.deviated => '✗ deviated',
        CockpitReplayStatus.skipped => '– skipped',
      },
      color: _replayColor(report.status),
    );
  }
}

Color _replayColor(CockpitReplayStatus status) => switch (status) {
  CockpitReplayStatus.passed => cockpitRecorderPanelSuccess,
  CockpitReplayStatus.deviated => cockpitRecorderPanelDanger,
  CockpitReplayStatus.skipped => cockpitRecorderPanelDimText,
};
