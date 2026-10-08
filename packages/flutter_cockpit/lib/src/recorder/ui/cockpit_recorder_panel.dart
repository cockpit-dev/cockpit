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
/// [CockpitRecorderScope] controller — a REC timer header, the live step
/// flow, an action row (verify replay, copy, save), and the current phase's
/// session controls at the bottom.
///
/// The panel paints only its solid surface fill and sizes itself to the
/// container a host provides: the default floating-ball host clips it into
/// an adaptive sheet or card, and a host's own floating window can embed it
/// directly. [onClose] is optional: hosts that can collapse the panel pass a
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _HeaderBar(controller: controller, onClose: onClose),
            Expanded(child: CockpitRecorderTimeline(controller: controller)),
            _ActionBar(controller: controller),
            _ControlBar(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Fixed-height title strip: the live phase dot with the phase's status
/// title — the recording clock while a session runs — the step count, and,
/// for hosts that can collapse, the close button. The elapsed time is
/// recomputed on every controller notification; no timer drives it, so host
/// app tests keep settling.
final class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.controller, this.onClose});

  final CockpitRecorderController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            CockpitRecorderIndicator(controller: controller, showLabel: false),
            const SizedBox(width: 8),
            Flexible(
              child: Text(statusTitle, style: cockpitRecorderTitleStyle),
            ),
            if (session != null) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                ' · ${session.stepCount} steps',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cockpitRecorderSecondaryStyle,
              ),
            ],
            const Spacer(),
            if (onClose != null)
              CockpitRecorderPanelCloseButton(onPressed: onClose!),
          ],
        ),
      ),
    );
  }

  String get statusTitle {
    final session = controller.session;
    if (session == null) {
      return 'Recorder';
    }
    return switch (controller.phase) {
      CockpitRecorderPhase.recording =>
        'REC ${_formatClock(DateTime.now().difference(session.startedAt))}',
      CockpitRecorderPhase.paused =>
        'Paused · ${_formatClock((session.pausedAt ?? DateTime.now()).difference(session.startedAt))}',
      CockpitRecorderPhase.stopped => 'Stopped',
      CockpitRecorderPhase.idle => 'Recorder',
    };
  }

  static String _formatClock(Duration elapsed) {
    if (elapsed.isNegative) {
      elapsed = Duration.zero;
    }
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Action row: verify-replay, copy, and save — each one click, the bundle
/// export folded into copy and save — with an inline error banner above and
/// a status line below for the last case, copy confirmation, save path, and
/// replay tally. The status line hides entirely when nothing is reportable.
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cockpitRecorderErrorBanner,
                  borderRadius: BorderRadius.circular(
                    cockpitRecorderButtonRadius,
                  ),
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
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CockpitRecorderPanelButton(
                      label: 'Dismiss',
                      onPressed: controller.clearError,
                      variant: CockpitRecorderButtonVariant.text,
                      height: 28,
                      fontSize: 13,
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
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CockpitRecorderPanelButton(
                  label: _copied ? 'Copied' : 'Copy YAML',
                  onPressed: controller.session != null ? _copyYaml : null,
                  foreground: _copied
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
                ),
              ),
            ],
          ),
          if (_statusLine case final statusLine?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                statusLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

/// Bottom control zone: the current phase's session commands. Idle takes a
/// name and starts; recording pairs Pause with the record-red Stop over the
/// segment tools; stopped offers recording again beside the export hint.
/// The zone clears the screen's bottom inset so controls stay thumb-safe.
final class _ControlBar extends StatefulWidget {
  const _ControlBar({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_ControlBar> createState() => _ControlBarState();
}

final class _ControlBarState extends State<_ControlBar> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _segmentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _segmentController.addListener(_handleSegmentTextChange);
  }

  @override
  void dispose() {
    _segmentController.removeListener(_handleSegmentTextChange);
    _nameController.dispose();
    _segmentController.dispose();
    super.dispose();
  }

  void _handleSegmentTextChange() => setState(() {});

  void _start() {
    widget.controller.start(_nameController.text);
    _nameController.clear();
  }

  void _beginSegment() {
    final label = _segmentController.text.trim();
    if (label.isEmpty) {
      return;
    }
    widget.controller.beginSegment(label);
    _segmentController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
      child: switch (controller.phase) {
        CockpitRecorderPhase.idle => _idleControls(),
        CockpitRecorderPhase.recording => _recordingControls(),
        CockpitRecorderPhase.paused => _pausedControls(),
        CockpitRecorderPhase.stopped => _stoppedControls(),
      },
    );
  }

  Widget _idleControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Widget _recordingControls() {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _pauseStopRow(paused: false),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: CockpitRecorderPanelTextField(
                controller: _segmentController,
                hint: 'New segment label',
                onSubmitted: (_) => _beginSegment(),
              ),
            ),
            const SizedBox(width: 8),
            CockpitRecorderPanelButton(
              label: 'Add segment',
              onPressed: _segmentController.text.trim().isEmpty
                  ? null
                  : _beginSegment,
              variant: CockpitRecorderButtonVariant.text,
            ),
          ],
        ),
        const SizedBox(height: 8),
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
            const SizedBox(width: 8),
            CockpitRecorderPanelButton(
              label: 'End segment',
              onPressed: controller.openSegments.isNotEmpty
                  ? controller.endSegment
                  : null,
              variant: CockpitRecorderButtonVariant.text,
            ),
          ],
        ),
      ],
    );
  }

  Widget _pausedControls() => _pauseStopRow(paused: true);

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
      children: <Widget>[
        CockpitRecorderPanelButton(
          label: 'Record again',
          onPressed: () => widget.controller.start(),
          variant: CockpitRecorderButtonVariant.accent,
          height: 44,
        ),
        const SizedBox(height: 6),
        Text(
          'Session stopped — export below or record again.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: cockpitRecorderSecondaryStyle.copyWith(
            color: cockpitRecorderInkTertiary,
          ),
        ),
      ],
    );
  }
}
