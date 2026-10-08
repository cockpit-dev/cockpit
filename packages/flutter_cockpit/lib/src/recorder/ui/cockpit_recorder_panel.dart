import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import '../cockpit_replay_report.dart';
import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_export_gateway.dart';
import 'cockpit_recorder_indicator.dart';
import 'cockpit_recorder_panel_widgets.dart';
import 'cockpit_recorder_scope.dart';
import 'cockpit_recorder_timeline.dart';

/// Embeddable recorder panel: a floating-HUD column over the
/// [CockpitRecorderScope] controller — a step-count hero header, the live
/// step receipt, a quiet export row, and the current phase's thumb
/// controls at the bottom.
///
/// The column sizes to its content (hosts cap its height), so a short
/// recording reads as a compact sheet instead of floating in a fixed
/// frame. [onClose] is optional: hosts that can collapse the panel pass a
/// callback and get the header's close button. All status and error
/// reporting is inline text within the panel; nothing depends on Scaffold
/// snackbars or OverlayEntry windows.
final class CockpitRecorderPanel extends StatelessWidget {
  /// Creates a recorder panel with an optional header close button.
  const CockpitRecorderPanel({this.onClose, super.key});

  /// Invoked by the header's close button; `null` hides the button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final controller = CockpitRecorderScope.of(context);
    return ColoredBox(
      color: cockpitRecorderSurface,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _HeroHeader(controller: controller, onClose: onClose),
            const _Hairline(),
            Flexible(child: CockpitRecorderTimeline(controller: controller)),
            if (controller.phase == CockpitRecorderPhase.recording)
              _SegmentTail(controller: controller),
            _ActionBar(controller: controller),
            _ControlBar(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// A full-bleed hairline with side insets matching the panel gutters.
final class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 0.5,
      color: cockpitRecorderSeparator,
    );
  }
}

/// Hero header: the live phase dot beside the session's step count — what
/// the recorder is here to produce, so it is the largest type on the panel —
/// with the phase and elapsed clock as a quiet caption, and the close button
/// for hosts that can collapse. The clock is recomputed on every controller
/// notification; no timer drives it, so host app tests keep settling, and
/// the paused/stopped clock freezes at the session's boundary.
final class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.controller, this.onClose});

  final CockpitRecorderController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: <Widget>[
          CockpitRecorderIndicator(controller: controller, showLabel: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (session == null)
                  Text(
                    'Recorder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: cockpitRecorderHeroStyle,
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '${session.stepCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cockpitRecorderTimerStyle,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        session.stepCount == 1 ? 'step' : 'steps',
                        style: cockpitRecorderSecondaryStyle.copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 2),
                Text(
                  _caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cockpitRecorderSecondaryStyle,
                ),
              ],
            ),
          ),
          if (onClose != null) ...<Widget>[
            const SizedBox(width: 8),
            CockpitRecorderPanelCloseButton(onPressed: onClose!),
          ],
        ],
      ),
    );
  }

  String get _clock {
    final session = controller.session!;
    final now = DateTime.now();
    final end = switch (controller.phase) {
      CockpitRecorderPhase.paused => session.pausedAt ?? now,
      CockpitRecorderPhase.stopped => session.endedAt ?? now,
      _ => now,
    };
    var elapsed = end.difference(session.startedAt);
    if (elapsed.isNegative) {
      elapsed = Duration.zero;
    }
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _caption {
    if (controller.session == null) {
      return 'Record a flow as a cockpit.test case';
    }
    return switch (controller.phase) {
      CockpitRecorderPhase.recording => 'Recording · $_clock',
      CockpitRecorderPhase.paused => 'Paused · $_clock',
      CockpitRecorderPhase.stopped => 'Stopped · $_clock',
      CockpitRecorderPhase.idle => 'Record a flow as a cockpit.test case',
    };
  }
}

/// The step feed's tail while recording: segment tools under progressive
/// disclosure. Resting shows one quiet affordance; opening it swaps in the
/// label composer, and open segments surface as chips with their end
/// control. Hidden in every other phase — segments annotate a live
/// capture, not a finished one.
final class _SegmentTail extends StatefulWidget {
  const _SegmentTail({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_SegmentTail> createState() => _SegmentTailState();
}

final class _SegmentTailState extends State<_SegmentTail> {
  final TextEditingController _segmentController = TextEditingController();
  bool _composerOpen = false;

  @override
  void initState() {
    super.initState();
    _segmentController.addListener(_handleSegmentTextChange);
  }

  @override
  void dispose() {
    _segmentController.removeListener(_handleSegmentTextChange);
    _segmentController.dispose();
    super.dispose();
  }

  void _handleSegmentTextChange() => setState(() {});

  void _beginSegment() {
    final label = _segmentController.text.trim();
    if (label.isEmpty) {
      return;
    }
    widget.controller.beginSegment(label);
    _segmentController.clear();
    setState(() => _composerOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_composerOpen)
            Row(
              children: <Widget>[
                Expanded(
                  child: CockpitRecorderPanelTextField(
                    controller: _segmentController,
                    hint: 'Segment label',
                    autofocus: true,
                    onSubmitted: (_) => _beginSegment(),
                  ),
                ),
                const SizedBox(width: 8),
                CockpitRecorderPanelButton(
                  label: 'Add',
                  onPressed: _segmentController.text.trim().isEmpty
                      ? null
                      : _beginSegment,
                ),
              ],
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: CockpitRecorderPanelButton(
                label: '+ Add segment',
                onPressed: () => setState(() => _composerOpen = true),
                variant: CockpitRecorderButtonVariant.text,
                foreground: cockpitRecorderInkTertiary,
                hoverForeground: cockpitRecorderInkSecondary,
              ),
            ),
          if (controller.openSegments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final segment in controller.openSegments)
                        CockpitRecorderPanelChip(label: segment),
                    ],
                  ),
                ),
                CockpitRecorderPanelButton(
                  label: 'End segment',
                  onPressed: controller.endSegment,
                  variant: CockpitRecorderButtonVariant.text,
                  foreground: cockpitRecorderInkTertiary,
                  hoverForeground: cockpitRecorderInkSecondary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Quiet export row: verify-replay, copy, and save as text actions — the
/// thumb controls below stay the panel's one dominant control zone, so the
/// utilities read light and stay light — with an inline error banner above
/// and a status line below for the last case, copy confirmation, save
/// path, and replay tally. The status line hides entirely when nothing is
/// reportable.
final class _ActionBar extends StatefulWidget {
  const _ActionBar({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

final class _ActionBarState extends State<_ActionBar> {
  static const Duration _copyConfirmationDuration = Duration(seconds: 2);

  Timer? _copyReset;
  bool _copied = false;

  @override
  void dispose() {
    _copyReset?.cancel();
    super.dispose();
  }

  /// Copy needs a bundle, so a fresh one is exported first; a failed export
  /// leaves the controller's inline error to speak for itself and nothing
  /// stale reaches the clipboard.
  Future<void> _copyYaml() async {
    widget.controller.exportBundle();
    final bundle = widget.controller.lastBundle;
    if (widget.controller.lastError != null || bundle == null) {
      return;
    }
    await cockpitRecorderClipboardCopy(bundle.caseYaml);
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _copyReset?.cancel();
    _copyReset = Timer(_copyConfirmationDuration, () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _save() {
    widget.controller.exportBundle();
    if (widget.controller.lastError != null) {
      return;
    }
    widget.controller.saveBundle();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final error = controller.lastError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: const ShapeDecoration(
                  color: cockpitRecorderErrorBanner,
                  shape: cockpitRecorderControlShape,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        error,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: cockpitRecorderSecondaryStyle.copyWith(
                          color: cockpitRecorderError,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CockpitRecorderPanelButton(
                      label: 'Dismiss',
                      onPressed: controller.clearError,
                      variant: CockpitRecorderButtonVariant.text,
                      height: 30,
                      fontSize: 12.5,
                      foreground: cockpitRecorderError,
                      hoverForeground: cockpitRecorderError,
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: CockpitRecorderPanelButton(
                  label: controller.isReplaying
                      ? 'Replaying…'
                      : 'Verify replay',
                  onPressed: controller.canVerifyReplay
                      ? controller.verifyReplay
                      : null,
                  variant: CockpitRecorderButtonVariant.text,
                  height: 38,
                  fontSize: 12.5,
                  hoverForeground: cockpitRecorderInkPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CockpitRecorderPanelButton(
                  label: _copied ? 'Copied' : 'Copy YAML',
                  onPressed: controller.session != null ? _copyYaml : null,
                  variant: CockpitRecorderButtonVariant.text,
                  height: 38,
                  fontSize: 12.5,
                  foreground: _copied
                      ? cockpitRecorderSuccess
                      : cockpitRecorderInkSecondary,
                  hoverForeground: _copied
                      ? cockpitRecorderSuccess
                      : cockpitRecorderInkPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CockpitRecorderPanelButton(
                  label: controller.isSaving ? 'Saving…' : 'Save',
                  onPressed: controller.session != null && !controller.isSaving
                      ? _save
                      : null,
                  variant: CockpitRecorderButtonVariant.text,
                  height: 38,
                  fontSize: 12.5,
                  foreground: cockpitRecorderInkSecondary,
                  hoverForeground: cockpitRecorderInkPrimary,
                ),
              ),
            ],
          ),
          if (_statusLine case final statusLine?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                statusLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: cockpitRecorderMicroStyle,
              ),
            ),
        ],
      ),
    );
  }

  String? get _statusLine {
    final controller = widget.controller;
    final caseId = controller.lastBundle?.caseDocument['id'];
    final reports = controller.replayReports;
    final passed =
        reports
            ?.where((report) => report.status == CockpitReplayStatus.passed)
            .length ??
        0;
    final deviated =
        reports
            ?.where((report) => report.status == CockpitReplayStatus.deviated)
            .length ??
        0;
    final skipped =
        reports
            ?.where((report) => report.status == CockpitReplayStatus.skipped)
            .length ??
        0;
    final savedPath = controller.savedPath;
    final parts = <String>[
      if (caseId is String) 'case $caseId',
      if (_copied) 'copied ✓',
      if (savedPath != null) 'saved to $savedPath',
      if (reports != null)
        'replay: $passed passed · $deviated deviated · $skipped skipped',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Bottom control zone: the current phase's session commands — the one
/// dominant control zone of the panel. Idle takes a name and starts;
/// recording and paused pair a secondary Resume/Pause with the record-red
/// Stop at thumb scale; stopped offers recording again beside the export
/// hint. The zone clears the screen's bottom inset so controls stay
/// thumb-safe.
final class _ControlBar extends StatefulWidget {
  const _ControlBar({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_ControlBar> createState() => _ControlBarState();
}

final class _ControlBarState extends State<_ControlBar> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _start() {
    widget.controller.start(_nameController.text);
    _nameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: 8),
        const _Hairline(),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 16),
          child: switch (controller.phase) {
            CockpitRecorderPhase.idle => _idleControls(),
            CockpitRecorderPhase.recording => _pauseStopRow(paused: false),
            CockpitRecorderPhase.paused => _pauseStopRow(paused: true),
            CockpitRecorderPhase.stopped => _stoppedControls(),
          },
        ),
      ],
    );
  }

  Widget _idleControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CockpitRecorderPanelTextField(
          controller: _nameController,
          hint: 'Session name (optional)',
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 8),
        CockpitRecorderPanelButton(
          label: 'Record',
          onPressed: _start,
          variant: CockpitRecorderButtonVariant.accent,
          height: 44,
        ),
      ],
    );
  }

  Widget _pauseStopRow({required bool paused}) {
    final controller = widget.controller;
    return Row(
      children: <Widget>[
        Expanded(
          flex: 2,
          child: paused
              ? CockpitRecorderPanelButton(
                  label: 'Resume',
                  onPressed: controller.resume,
                  variant: CockpitRecorderButtonVariant.accent,
                  height: 44,
                )
              : CockpitRecorderPanelButton(
                  label: 'Pause',
                  onPressed: controller.pause,
                  height: 44,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: CockpitRecorderPanelButton(
            label: 'Stop',
            onPressed: controller.stop,
            variant: CockpitRecorderButtonVariant.record,
            height: 44,
          ),
        ),
      ],
    );
  }

  Widget _stoppedControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CockpitRecorderPanelButton(
          label: 'Record again',
          onPressed: () => widget.controller.start(),
          variant: CockpitRecorderButtonVariant.accent,
          height: 44,
        ),
        const SizedBox(height: 8),
        Text(
          'Session stopped — export above or record again.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: cockpitRecorderMicroStyle,
        ),
      ],
    );
  }
}
