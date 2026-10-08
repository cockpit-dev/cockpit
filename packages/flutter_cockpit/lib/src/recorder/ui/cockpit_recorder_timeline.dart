import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import '../cockpit_replay_report.dart';
import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_panel_widgets.dart';
import 'cockpit_recorder_step_glyph.dart';

/// Step flow of the recorder panel: an iOS-style receipt list — a leading
/// glyph tile whose stroke carries the row's state, an action title, a
/// selector line — newest last and auto-scrolled to the newest step,
/// hairline separators indented to the text. Rows expand in place: tap
/// anywhere on a row to inspect its locator candidates and edit its note.
/// Replay outcomes join from the controller's last verify-replay pass and
/// tint the row's glyph.
///
/// Delete is an engine constraint, not a UI preference: only the most
/// recently recorded step can be discarded, so the affordance appears on the
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

  /// Step id whose detail area is expanded; `null` when none is.
  String? _expandedStepId;
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

  void _toggleExpanded(CockpitInteractionStep step) {
    setState(() {
      if (_expandedStepId == step.stepId) {
        _expandedStepId = null;
      } else {
        _expandedStepId = step.stepId;
        _noteController.text = step.annotation ?? '';
      }
    });
  }

  void _saveAnnotation(CockpitInteractionStep step, String note) {
    widget.controller.annotate(step.stepId, note);
    setState(() => _expandedStepId = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final steps = widget.controller.steps;
        if (steps.isEmpty) {
          return const _TimelineEmptyState();
        }
        final replayById = <String, CockpitReplayReport>{
          for (final report
              in widget.controller.replayReports ??
                  const <CockpitReplayReport>[])
            report.stepId: report,
        };
        return ListView.separated(
          controller: _scrollController,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: steps.length,
          separatorBuilder: (_, _) => Container(
            margin: const EdgeInsets.fromLTRB(64, 0, 20, 0),
            height: 0.5,
            color: cockpitRecorderSeparator,
          ),
          itemBuilder: (context, index) {
            final step = steps[index];
            return _TimelineRow(
              key: ValueKey<String>(step.stepId),
              step: step,
              isLast: index == steps.length - 1,
              isRecording:
                  widget.controller.phase == CockpitRecorderPhase.recording,
              canMutate:
                  widget.controller.phase == CockpitRecorderPhase.recording,
              canDelete: widget.controller.canDiscardLast,
              expanded: _expandedStepId == step.stepId,
              noteController: _noteController,
              replay: replayById[step.stepId],
              offset: step.recordedAt.difference(steps.first.recordedAt),
              onToggle: () => _toggleExpanded(step),
              onSaveAnnotation: (note) => _saveAnnotation(step, note),
              onDelete: widget.controller.discardLastStep,
            );
          },
        );
      },
    );
  }
}

final class _TimelineEmptyState extends StatelessWidget {
  const _TimelineEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            'No steps yet',
            style: cockpitRecorderTitleStyle.copyWith(
              color: cockpitRecorderInkSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start a recording and use your app. Taps, text, scrolls, and '
            'route changes appear here as they are captured.',
            textAlign: TextAlign.center,
            style: cockpitRecorderSecondaryStyle.copyWith(
              color: cockpitRecorderInkTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

final class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.isLast,
    required this.isRecording,
    required this.canMutate,
    required this.canDelete,
    required this.expanded,
    required this.noteController,
    required this.replay,
    required this.offset,
    required this.onToggle,
    required this.onSaveAnnotation,
    required this.onDelete,
    super.key,
  });

  final CockpitInteractionStep step;
  final bool isLast;
  final bool isRecording;
  final bool canMutate;
  final bool canDelete;
  final bool expanded;
  final TextEditingController noteController;
  final CockpitReplayReport? replay;
  final Duration offset;
  final VoidCallback onToggle;
  final ValueChanged<String> onSaveAnnotation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    final annotation = step.annotation;
    final reason = replay?.reason;
    final selector = _selectorLine(step);
    final settledAfterMs = step.settledAfterMs;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CockpitRecorderStepGlyph(kind: step.kind, color: _nodeColor()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _titleLine(),
                  if (selector != null || settledAfterMs != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: <Widget>[
                          if (selector != null)
                            Expanded(
                              child: Text(
                                selector,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: cockpitRecorderSecondaryStyle,
                              ),
                            )
                          else
                            const Spacer(),
                          if (settledAfterMs != null)
                            Text(
                              'settled ${settledAfterMs}ms',
                              style: cockpitRecorderMicroStyle,
                            ),
                        ],
                      ),
                    ),
                  if (step.segments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: <Widget>[
                          for (final segment in step.segments)
                            CockpitRecorderPanelChip(label: segment),
                        ],
                      ),
                    ),
                  if (annotation != null && !expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Note: $annotation',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: cockpitRecorderSecondaryStyle,
                      ),
                    ),
                  if (reason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: cockpitRecorderSecondaryStyle.copyWith(
                          color: cockpitRecorderError,
                        ),
                      ),
                    ),
                  if (expanded) _expandedDetail(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Line 1: the action verb with the short target, and the delete
  /// affordance (last row while recording) or the relative time.
  Widget _titleLine() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              text: _actionTitle(step),
              children: <InlineSpan>[
                if (_shortTarget(step) case final target?)
                  TextSpan(text: ' · $target'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cockpitRecorderBodyStyle,
          ),
        ),
        const SizedBox(width: 8),
        if (isRecording && isLast)
          CockpitRecorderPanelButton(
            label: 'Delete',
            onPressed: canDelete ? onDelete : null,
            variant: CockpitRecorderButtonVariant.text,
            fontSize: 11,
            foreground: cockpitRecorderInkTertiary,
            hoverForeground: cockpitRecorderRecord,
          )
        else
          Text(
            _formatOffset(offset),
            style: cockpitRecorderSecondaryStyle.copyWith(
              color: cockpitRecorderInkTertiary,
            ),
          ),
      ],
    );
  }

  /// Expanded detail: the full locator candidate list and the inline note
  /// editor.
  Widget _expandedDetail() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final candidate in step.locatorCandidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${candidate.kind} · ${candidate.selector}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cockpitRecorderSecondaryStyle,
                    ),
                  ),
                  Text('${candidate.score}', style: cockpitRecorderMicroStyle),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: CockpitRecorderPanelTextField(
                  controller: noteController,
                  hint: 'Add a note',
                  onSubmitted: canMutate ? onSaveAnnotation : null,
                ),
              ),
              const SizedBox(width: 8),
              CockpitRecorderPanelButton(
                label: 'Save',
                onPressed: canMutate
                    ? () => onSaveAnnotation(noteController.text)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _nodeColor() {
    final replay = this.replay;
    if (replay != null) {
      return _replayColor(replay.status);
    }
    return step.unresolved
        ? cockpitRecorderWarning
        : cockpitRecorderInkTertiary;
  }
}

/// Whether the kind locates a widget target on screen.
bool _locatorKind(CockpitInteractionStepKind kind) {
  return switch (kind) {
    CockpitInteractionStepKind.tap ||
    CockpitInteractionStepKind.longPress ||
    CockpitInteractionStepKind.scroll ||
    CockpitInteractionStepKind.text => true,
    CockpitInteractionStepKind.routeChange ||
    CockpitInteractionStepKind.back ||
    CockpitInteractionStepKind.marker ||
    CockpitInteractionStepKind.note => false,
  };
}

String _actionTitle(CockpitInteractionStep step) {
  return switch (step.kind) {
    CockpitInteractionStepKind.tap => 'Tap',
    CockpitInteractionStepKind.longPress => 'Long press',
    CockpitInteractionStepKind.text =>
      step.resolvedValue == null ? 'Type' : 'Type “${step.resolvedValue}”',
    CockpitInteractionStepKind.scroll => 'Scroll',
    CockpitInteractionStepKind.routeChange =>
      step.routeName == null ? 'Route change' : 'Open ${step.routeName}',
    CockpitInteractionStepKind.back => 'Back',
    CockpitInteractionStepKind.marker =>
      step.resolvedValue == null ? 'Marker' : 'Marker: ${step.resolvedValue}',
    CockpitInteractionStepKind.note => switch (step.resolvedValue ??
        step.annotation) {
      null => 'Note',
      final value => 'Note: $value',
    },
  };
}

/// The best candidate's human label appended to the action title.
String? _shortTarget(CockpitInteractionStep step) {
  if (!_locatorKind(step.kind) || step.locatorCandidates.isEmpty) {
    return null;
  }
  final candidate = step.locatorCandidates.first;
  if (candidate.kind == 'key' && candidate.selector.startsWith('@')) {
    return candidate.selector.substring(1);
  }
  return candidate.selector.replaceAll('cockpit:', '');
}

/// The line-2 selector text: the best candidate's selector, or the
/// unresolved marker when the step targeted nothing.
String? _selectorLine(CockpitInteractionStep step) {
  if (step.locatorCandidates.isNotEmpty) {
    return step.locatorCandidates.first.selector;
  }
  return step.unresolved || _locatorKind(step.kind)
      ? '(unresolved target)'
      : null;
}

String _formatOffset(Duration offset) {
  final seconds = offset.inMilliseconds.clamp(0, 1 << 40) / 1000;
  return '+${seconds.toStringAsFixed(1)}s';
}

Color _replayColor(CockpitReplayStatus status) => switch (status) {
  CockpitReplayStatus.passed => cockpitRecorderSuccess,
  CockpitReplayStatus.deviated => cockpitRecorderRecord,
  CockpitReplayStatus.skipped => cockpitRecorderInkTertiary,
};
