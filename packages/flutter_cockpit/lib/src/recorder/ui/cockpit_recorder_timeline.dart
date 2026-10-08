import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import '../cockpit_replay_report.dart';
import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_panel_widgets.dart';

/// Timeline hero of the recorder panel: the live step list on a connected
/// vertical spine, newest last and auto-scrolled to the newest step. Rows
/// expand in place — tap anywhere on a row to inspect its locator
/// candidates and edit its note. Replay outcomes join from the
/// controller's last verify-replay pass.
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
        final replayById = <String, CockpitReplayReport>{
          for (final report
              in widget.controller.replayReports ??
                  const <CockpitReplayReport>[])
            report.stepId: report,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Timeline',
                  style: TextStyle(
                    color: cockpitRecorderInkSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (steps.isEmpty)
                const Expanded(child: _TimelineEmptyState())
              else
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: steps.length,
                    itemBuilder: (context, index) {
                      final step = steps[index];
                      return _TimelineRow(
                        key: ValueKey<String>(step.stepId),
                        step: step,
                        isLast: index == steps.length - 1,
                        isRecording:
                            widget.controller.phase ==
                            CockpitRecorderPhase.recording,
                        canMutate:
                            widget.controller.phase ==
                            CockpitRecorderPhase.recording,
                        canDelete: widget.controller.canDiscardLast,
                        expanded: _expandedStepId == step.stepId,
                        noteController: _noteController,
                        replay: replayById[step.stepId],
                        offset: step.recordedAt.difference(
                          steps.first.recordedAt,
                        ),
                        onToggle: () => _toggleExpanded(step),
                        onSaveAnnotation: (note) => _saveAnnotation(step, note),
                        onDelete: widget.controller.discardLastStep,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

final class _TimelineEmptyState extends StatelessWidget {
  const _TimelineEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'No steps yet',
              style: cockpitRecorderBodyStyle.copyWith(
                color: cockpitRecorderInkSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Start a recording and use your app. Taps, text, scrolls, and '
              'route changes appear here as they are captured.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cockpitRecorderInkTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

final class _TimelineRow extends StatefulWidget {
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
  State<_TimelineRow> createState() => _TimelineRowState();
}

final class _TimelineRowState extends State<_TimelineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final annotation = step.annotation;
    final reason = widget.replay?.reason;
    final selector = _selectorLine(step);
    final settledAfterMs = step.settledAfterMs;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggle,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Spine(color: _nodeColor()),
            Expanded(
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _hovered
                        ? cockpitRecorderSurface1
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                                    style: cockpitRecorderMonoStyle.copyWith(
                                      color: step.locatorCandidates.isNotEmpty
                                          ? cockpitRecorderInkSecondary
                                          : cockpitRecorderWarning,
                                    ),
                                  ),
                                ),
                              if (settledAfterMs != null)
                                Text(
                                  'settled ${settledAfterMs}ms',
                                  style: cockpitRecorderMonoStyle.copyWith(
                                    color: cockpitRecorderInkTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (step.segments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: <Widget>[
                              for (final segment in step.segments)
                                CockpitRecorderPanelChip(label: segment),
                            ],
                          ),
                        ),
                      if (annotation != null && !widget.expanded)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Note: $annotation',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: cockpitRecorderCaptionStyle,
                          ),
                        ),
                      if (reason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: cockpitRecorderCaptionStyle.copyWith(
                              color: cockpitRecorderError,
                            ),
                          ),
                        ),
                      if (widget.expanded) _expandedDetail(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Line 1: the action verb with the short target, the delete affordance
  /// or replay outcome plus relative time, and the expansion chevron.
  Widget _titleLine() {
    final replay = widget.replay;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              text: _actionTitle(widget.step),
              style: cockpitRecorderBodyStyle,
              children: <InlineSpan>[
                if (_shortTarget(widget.step) case final target?)
                  TextSpan(
                    text: ' · $target',
                    style: const TextStyle(
                      color: cockpitRecorderInkSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.isRecording && widget.isLast)
          CockpitRecorderPanelButton(
            label: 'Delete step',
            onPressed: widget.canDelete ? widget.onDelete : null,
            variant: CockpitRecorderButtonVariant.text,
            foreground: cockpitRecorderInkTertiary,
            hoverForeground: cockpitRecorderError,
          )
        else ...<Widget>[
          if (replay != null)
            Text(
              replay.status.name,
              style: cockpitRecorderCaptionStyle.copyWith(
                color: _replayColor(replay.status),
              ),
            ),
          const SizedBox(width: 6),
          Text(
            _formatOffset(widget.offset),
            style: cockpitRecorderMonoStyle.copyWith(
              color: cockpitRecorderInkTertiary,
            ),
          ),
        ],
        const SizedBox(width: 6),
        AnimatedRotation(
          turns: widget.expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 150),
          child: const Text(
            '›',
            style: TextStyle(color: cockpitRecorderInkTertiary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// Expanded detail: the full locator candidate list and the inline note
  /// editor.
  Widget _expandedDetail() {
    final step = widget.step;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final candidate in step.locatorCandidates)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${candidate.kind} ${candidate.selector}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cockpitRecorderMonoStyle,
                    ),
                  ),
                  Text(
                    '${candidate.score}',
                    style: cockpitRecorderMonoStyle.copyWith(
                      color: cockpitRecorderInkTertiary,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CockpitRecorderPanelTextField(
                    controller: widget.noteController,
                    hint: 'Add a note',
                    onSubmitted: widget.canMutate
                        ? widget.onSaveAnnotation
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                CockpitRecorderPanelButton(
                  label: 'Save',
                  compact: true,
                  onPressed: widget.canMutate
                      ? () =>
                            widget.onSaveAnnotation(widget.noteController.text)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _nodeColor() {
    final replay = widget.replay;
    if (replay != null) {
      return _replayColor(replay.status);
    }
    return widget.step.unresolved
        ? cockpitRecorderWarning
        : cockpitRecorderBorderFocus;
  }
}

/// The left spine: a continuous line through the row with the step's node.
final class _Spine extends StatelessWidget {
  const _Spine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      child: Stack(
        children: <Widget>[
          const Positioned(
            left: 11,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: 2,
              child: ColoredBox(color: cockpitRecorderBorder),
            ),
          ),
          Positioned(
            left: 5,
            top: 10,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: cockpitRecorderSurface0, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
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
  CockpitReplayStatus.deviated => cockpitRecorderError,
  CockpitReplayStatus.skipped => cockpitRecorderInkTertiary,
};
