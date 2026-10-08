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

/// Embeddable recorder panel: a card with a header strip, a phase toolbar,
/// the timeline hero, and a footer action bar over the
/// [CockpitRecorderScope] controller.
///
/// Designed for a sized container — the default floating-ball host centers
/// it over a full-screen scrim, and a host's own floating window can embed
/// it directly. [onClose] is optional: hosts that can collapse the panel
/// pass a callback and get the header's close button. All status and error
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cockpitRecorderSurface0,
        border: Border.all(color: cockpitRecorderBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _HeaderBar(controller: controller, onClose: onClose),
            _Toolbar(controller: controller),
            Expanded(child: CockpitRecorderTimeline(controller: controller)),
            _FooterBar(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Fixed-height title strip: recorder identity with live phase dot, the
/// session name, live step counters, and — for hosts that can collapse —
/// the close button.
final class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.controller, this.onClose});

  final CockpitRecorderController controller;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final sessionName = controller.recorder.sessionName?.trim();
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: cockpitRecorderSurface1,
        border: Border(bottom: BorderSide(color: cockpitRecorderBorder)),
      ),
      child: Row(
        children: <Widget>[
          CockpitRecorderIndicator(controller: controller, showLabel: false),
          const SizedBox(width: 8),
          const Text('Recorder', style: cockpitRecorderTitleStyle),
          if (sessionName != null && sessionName.isNotEmpty) ...<Widget>[
            Flexible(
              child: Text(
                ' · $sessionName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: cockpitRecorderInkSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (session != null) ...<Widget>[
            Text(
              '${session.stepCount} steps · '
              '${session.unresolvedCount} unresolved',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cockpitRecorderMonoStyle.copyWith(
                color: cockpitRecorderInkTertiary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (onClose != null)
            CockpitRecorderPanelCloseButton(onPressed: onClose!),
        ],
      ),
    );
  }
}

/// Phase toolbar: the current phase's session commands on one row (the
/// session-name field beside Record while idle, the segment field while
/// recording), and — while recording — the open-segment chips with the
/// segment end command on a secondary row below.
final class _Toolbar extends StatefulWidget {
  const _Toolbar({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

final class _ToolbarState extends State<_Toolbar> {
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
    return Container(
      decoration: const BoxDecoration(
        color: cockpitRecorderSurface1,
        border: Border(bottom: BorderSide(color: cockpitRecorderBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (controller.canStart) ...<Widget>[
                CockpitRecorderPanelButton(
                  label: 'Record',
                  onPressed: _start,
                  variant: CockpitRecorderButtonVariant.primary,
                ),
                if (controller.phase == CockpitRecorderPhase.idle) ...<Widget>[
                  const SizedBox(width: 8),
                  Expanded(
                    child: CockpitRecorderPanelTextField(
                      controller: _nameController,
                      hint: 'Session name (optional)',
                      onSubmitted: (_) => _start(),
                    ),
                  ),
                ],
              ] else ...<Widget>[
                if (controller.canPause) ...<Widget>[
                  CockpitRecorderPanelButton(
                    label: 'Pause',
                    onPressed: controller.pause,
                  ),
                  const SizedBox(width: 8),
                ],
                if (controller.canResume) ...<Widget>[
                  CockpitRecorderPanelButton(
                    label: 'Resume',
                    onPressed: controller.resume,
                  ),
                  const SizedBox(width: 8),
                ],
                if (controller.canStop)
                  CockpitRecorderPanelButton(
                    label: 'Stop',
                    onPressed: controller.stop,
                  ),
                if (controller.phase ==
                    CockpitRecorderPhase.recording) ...<Widget>[
                  const SizedBox(width: 8),
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
              ],
            ],
          ),
          if (controller.phase == CockpitRecorderPhase.recording)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final segment in controller.openSegments)
                    CockpitRecorderPanelChip(label: segment),
                  CockpitRecorderPanelButton(
                    label: 'End segment',
                    onPressed: controller.openSegments.isNotEmpty
                        ? controller.endSegment
                        : null,
                    variant: CockpitRecorderButtonVariant.text,
                  ),
                ],
              ),
            ),
          if (controller.phase == CockpitRecorderPhase.stopped)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Session stopped — export below or record again.',
                style: cockpitRecorderCaptionStyle.copyWith(
                  color: cockpitRecorderInkTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Footer action bar: verify-replay, copy, and save — each one click, the
/// bundle export folded into copy and save — an inline error banner, and a
/// status line for the last case, copy confirmation, save path, and replay
/// tally.
final class _FooterBar extends StatefulWidget {
  const _FooterBar({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_FooterBar> createState() => _FooterBarState();
}

final class _FooterBarState extends State<_FooterBar> {
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
    return Container(
      decoration: const BoxDecoration(
        color: cockpitRecorderSurface1,
        border: Border(top: BorderSide(color: cockpitRecorderBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cockpitRecorderErrorSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        error,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: cockpitRecorderCaptionStyle.copyWith(
                          color: cockpitRecorderError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CockpitRecorderPanelButton(
                      label: 'Dismiss',
                      onPressed: controller.clearError,
                      variant: CockpitRecorderButtonVariant.text,
                      foreground: cockpitRecorderError,
                      hoverForeground: cockpitRecorderError,
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: <Widget>[
              CockpitRecorderPanelButton(
                label: controller.isReplaying ? 'Replaying…' : 'Verify replay',
                onPressed: controller.canVerifyReplay
                    ? controller.verifyReplay
                    : null,
              ),
              const SizedBox(width: 8),
              CockpitRecorderPanelButton(
                label: _copied ? 'Copied' : 'Copy YAML',
                onPressed: controller.session != null ? _copyYaml : null,
                foreground: _copied
                    ? cockpitRecorderSuccess
                    : cockpitRecorderInkPrimary,
              ),
              const SizedBox(width: 8),
              CockpitRecorderPanelButton(
                label: controller.isSaving ? 'Saving…' : 'Save',
                onPressed: controller.session != null && !controller.isSaving
                    ? _save
                    : null,
              ),
              if (_statusLine case final statusLine?) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: cockpitRecorderCaptionStyle.copyWith(
                      color: cockpitRecorderInkTertiary,
                    ),
                  ),
                ),
              ],
            ],
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
