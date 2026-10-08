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

/// Embeddable recorder panel: a fixed header strip, a control row, the
/// timeline hero, and a bottom action bar over the [CockpitRecorderScope]
/// controller.
///
/// Designed for a sized container — the default floating-ball host's
/// full-screen overlay, or a host's own floating window. [onClose] is
/// optional: hosts that can collapse the panel pass a callback and get the
/// header's close button. All status and error reporting is inline text
/// within the panel; nothing depends on Scaffold snackbars or
/// OverlayEntry windows.
final class CockpitRecorderPanel extends StatelessWidget {
  /// Creates a recorder panel with an optional header close button.
  const CockpitRecorderPanel({this.onClose, super.key});

  /// Invoked by the header's close button; `null` hides the button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final controller = CockpitRecorderScope.of(context);
    return Container(
      color: cockpitRecorderPanelBackground,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _HeaderArea(controller: controller, onClose: onClose),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ControlArea(controller: controller),
                    const _PanelDivider(),
                    Expanded(
                      child: CockpitRecorderTimeline(controller: controller),
                    ),
                    const _PanelDivider(),
                    _BottomBar(controller: controller),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: cockpitRecorderPanelBorder),
      ),
    );
  }
}

/// Fixed-height title strip: recorder identity, phase badge, live step
/// counters, and — for hosts that can collapse — the close button.
final class _HeaderArea extends StatelessWidget {
  const _HeaderArea({required this.controller, this.onClose});

  final CockpitRecorderController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: cockpitRecorderPanelSurface,
        border: Border(bottom: BorderSide(color: cockpitRecorderPanelBorder)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            'COCKPIT RECORDER',
            style: cockpitRecorderPanelCaptionStyle.copyWith(
              color: cockpitRecorderPanelText,
            ),
          ),
          const SizedBox(width: 12),
          CockpitRecorderIndicator(controller: controller),
          const Spacer(),
          Flexible(
            child: Text(
              session == null
                  ? 'no session'
                  : '${session.stepCount} steps · '
                        '${session.unresolvedCount} unresolved',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cockpitRecorderPanelCaptionStyle,
            ),
          ),
          if (onClose != null) ...<Widget>[
            const SizedBox(width: 8),
            CockpitRecorderPanelButton(label: '✕', onPressed: onClose),
          ],
        ],
      ),
    );
  }
}

/// Control area: the current phase's primary session commands on one row
/// (the recording-name field beside Start while idle, the segment field
/// while recording), and — while recording — the compact segment controls
/// on a secondary row below, showing the open segments.
///
/// The segment buttons sit below the main row, not beside it: on embedded
/// panel widths the fixed-width buttons would overflow a single row.
final class _ControlArea extends StatefulWidget {
  const _ControlArea({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_ControlArea> createState() => _ControlAreaState();
}

final class _ControlAreaState extends State<_ControlArea> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _segmentController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _segmentController.dispose();
    super.dispose();
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (controller.canStart) ...<Widget>[
              CockpitRecorderPanelButton(label: 'Start', onPressed: _start),
              const SizedBox(width: 8),
              Expanded(
                child: CockpitRecorderPanelTextField(
                  controller: _nameController,
                  hint: 'recording name',
                  onSubmitted: (_) => _start(),
                ),
              ),
            ] else ...<Widget>[
              if (controller.canPause) ...<Widget>[
                CockpitRecorderPanelButton(
                  label: 'Pause',
                  onPressed: controller.pause,
                ),
                const SizedBox(width: 6),
              ],
              if (controller.canResume) ...<Widget>[
                CockpitRecorderPanelButton(
                  label: 'Resume',
                  onPressed: controller.resume,
                ),
                const SizedBox(width: 6),
              ],
              if (controller.canStop)
                CockpitRecorderPanelButton(
                  label: 'Stop',
                  onPressed: controller.stop,
                ),
              if (controller.phase ==
                  CockpitRecorderPhase.recording) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: CockpitRecorderPanelTextField(
                    controller: _segmentController,
                    hint: 'segment label',
                    onSubmitted: (_) => _beginSegment(),
                  ),
                ),
              ],
            ],
          ],
        ),
        if (controller.phase == CockpitRecorderPhase.recording)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                CockpitRecorderPanelButton(
                  label: 'Begin segment',
                  onPressed: _beginSegment,
                ),
                CockpitRecorderPanelButton(
                  label: 'End segment',
                  onPressed: controller.openSegments.isNotEmpty
                      ? controller.endSegment
                      : null,
                ),
                for (final segment in controller.openSegments)
                  CockpitRecorderPanelChip(
                    label: segment,
                    color: cockpitRecorderPanelAccent,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bottom action bar: verify-replay, copy, and save — each one click, the
/// bundle export folded into copy and save — plus an inline status line
/// for the last case, copy confirmation, save path, replay tally, and
/// command errors.
final class _BottomBar extends StatefulWidget {
  const _BottomBar({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

final class _BottomBarState extends State<_BottomBar> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            CockpitRecorderPanelButton(
              label: controller.isReplaying ? 'Replaying…' : 'Verify replay',
              onPressed: controller.canVerifyReplay
                  ? controller.verifyReplay
                  : null,
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: 'Copy YAML',
              onPressed: controller.session != null ? _copyYaml : null,
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: controller.isSaving ? 'Saving…' : 'Save',
              onPressed: controller.session != null && !controller.isSaving
                  ? _save
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusLine(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: cockpitRecorderPanelCaptionStyle,
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    error,
                    style: cockpitRecorderPanelCaptionStyle.copyWith(
                      color: cockpitRecorderPanelDanger,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CockpitRecorderPanelButton(
                  label: 'Dismiss',
                  onPressed: controller.clearError,
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _statusLine() {
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
    return parts.isEmpty ? 'no bundle yet' : parts.join(' · ');
  }
}
