import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import '../cockpit_replay_report.dart';
import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_export_gateway.dart';
import 'cockpit_recorder_panel_widgets.dart';
import 'cockpit_recorder_scope.dart';
import 'cockpit_recorder_timeline.dart';

/// Embeddable recorder panel: control, timeline, export, and replay areas
/// over the [CockpitRecorderScope] controller.
///
/// Designed for a sized container — the default floating-ball host's sheet,
/// or a host's own floating window. All status and error reporting is inline
/// text within the panel; nothing depends on Scaffold snackbars or
/// OverlayEntry windows.
final class CockpitRecorderPanel extends StatelessWidget {
  /// Creates a recorder panel.
  const CockpitRecorderPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = CockpitRecorderScope.of(context);
    return Container(
      color: cockpitRecorderPanelBackground,
      padding: const EdgeInsets.all(12),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ControlArea(controller: controller),
            const _PanelDivider(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const CockpitRecorderPanelSectionHeader(
                    'Timeline',
                    caption: 'delete applies to the newest step only',
                  ),
                  Expanded(
                    child: CockpitRecorderTimeline(controller: controller),
                  ),
                ],
              ),
            ),
            const _PanelDivider(),
            _ExportArea(controller: controller),
            const _PanelDivider(),
            _ReplayArea(controller: controller),
            _ErrorArea(controller: controller),
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

/// Area a — phase, counters, session commands, and the segment stack.
final class _ControlArea extends StatefulWidget {
  const _ControlArea({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_ControlArea> createState() => _ControlAreaState();
}

final class _ControlAreaState extends State<_ControlArea> {
  final TextEditingController _segmentController = TextEditingController();

  @override
  void dispose() {
    _segmentController.dispose();
    super.dispose();
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
    final session = controller.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          session == null
              ? 'no session'
              : '${controller.phase.name} · ${session.stepCount} steps · '
                    '${session.unresolvedCount} unresolved',
          style: cockpitRecorderPanelTextStyle,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            CockpitRecorderPanelButton(
              label: 'Start',
              onPressed: controller.canStart ? controller.start : null,
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: 'Pause',
              onPressed: controller.canPause ? controller.pause : null,
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: 'Resume',
              onPressed: controller.canResume ? controller.resume : null,
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: 'Stop',
              onPressed: controller.canStop ? controller.stop : null,
            ),
          ],
        ),
        if (controller.phase == CockpitRecorderPhase.recording) ...<Widget>[
          const SizedBox(height: 8),
          CockpitRecorderPanelTextField(
            controller: _segmentController,
            hint: 'segment label',
            onSubmitted: (_) => _beginSegment(),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              CockpitRecorderPanelButton(
                label: 'Begin segment',
                onPressed: _beginSegment,
              ),
              const SizedBox(width: 6),
              CockpitRecorderPanelButton(
                label: 'End segment',
                onPressed: controller.openSegments.isNotEmpty
                    ? controller.endSegment
                    : null,
              ),
            ],
          ),
          if (controller.openSegments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: <Widget>[
                for (final segment in controller.openSegments)
                  CockpitRecorderPanelChip(
                    label: segment,
                    color: cockpitRecorderPanelAccent,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// Area c — bundle export, clipboard copy, and gateway save.
final class _ExportArea extends StatefulWidget {
  const _ExportArea({required this.controller});

  final CockpitRecorderController controller;

  @override
  State<_ExportArea> createState() => _ExportAreaState();
}

final class _ExportAreaState extends State<_ExportArea> {
  static const Duration _copyConfirmationDuration = Duration(seconds: 2);

  Timer? _copyReset;
  bool _copied = false;

  @override
  void dispose() {
    _copyReset?.cancel();
    super.dispose();
  }

  Future<void> _copyYaml(String caseYaml) async {
    await cockpitRecorderClipboardCopy(caseYaml);
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final bundle = controller.lastBundle;
    final caseId = bundle?.caseDocument['id'];
    final savedPath = controller.savedPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const CockpitRecorderPanelSectionHeader('Export'),
        Text(
          bundle == null || caseId is! String
              ? 'no bundle yet'
              : 'case $caseId${savedPath == null ? '' : '\nsaved to $savedPath'}',
          style: cockpitRecorderPanelCaptionStyle,
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            CockpitRecorderPanelButton(
              label: 'Export',
              onPressed: controller.session != null
                  ? controller.exportBundle
                  : null,
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: _copied ? 'Copied!' : 'Copy YAML',
              onPressed: bundle == null
                  ? null
                  : () => _copyYaml(bundle.caseYaml),
            ),
            const SizedBox(width: 6),
            CockpitRecorderPanelButton(
              label: controller.isSaving ? 'Saving…' : 'Save',
              onPressed: bundle == null || controller.isSaving
                  ? null
                  : controller.saveBundle,
            ),
          ],
        ),
      ],
    );
  }
}

/// Area d — verify-replay trigger and the per-step outcome list.
final class _ReplayArea extends StatelessWidget {
  const _ReplayArea({required this.controller});

  final CockpitRecorderController controller;

  @override
  Widget build(BuildContext context) {
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
            if (reports != null) ...<Widget>[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'passed $passed · deviated $deviated · skipped $skipped',
                  overflow: TextOverflow.ellipsis,
                  style: cockpitRecorderPanelCaptionStyle,
                ),
              ),
            ],
          ],
        ),
        if (reports != null && reports.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 84),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reports.length,
                itemBuilder: (context, index) {
                  final report = reports[index];
                  final color = switch (report.status) {
                    CockpitReplayStatus.passed => cockpitRecorderPanelAccent,
                    CockpitReplayStatus.deviated => cockpitRecorderPanelDanger,
                    CockpitReplayStatus.skipped => cockpitRecorderPanelDimText,
                  };
                  final reason = report.reason;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        CockpitRecorderPanelChip(
                          label: '${report.stepId}:${report.status.name}',
                          color: color,
                        ),
                        if (reason != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: cockpitRecorderPanelCaptionStyle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Inline error surface for failed commands — the panel's only error
/// channel; nothing escalates to snackbars or overlays.
final class _ErrorArea extends StatelessWidget {
  const _ErrorArea({required this.controller});

  final CockpitRecorderController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.lastError;
    if (error == null) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: cockpitRecorderPanelDanger),
          borderRadius: BorderRadius.circular(6),
        ),
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
    );
  }
}
