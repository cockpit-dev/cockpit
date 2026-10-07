import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import 'cockpit_recorder_controller.dart';
import 'cockpit_recorder_panel_widgets.dart';

/// Passive recorder status indicator: a phase-colored dot with an optional
/// phase label.
///
/// The dot encodes the phase by color alone — grey when idle, red while
/// recording, amber while paused, blue once stopped — with no looping
/// animation: a debug overlay that animates forever would keep frames
/// scheduled and break `pumpAndSettle` in any host app test that starts a
/// recording. Wrapped in [IgnorePointer] unconditionally — it displays
/// state and never competes for hits, so it can sit over interactive app
/// content.
final class CockpitRecorderIndicator extends StatelessWidget {
  /// Creates an indicator bound to [controller].
  const CockpitRecorderIndicator({
    required this.controller,
    this.showLabel = true,
    super.key,
  });

  final CockpitRecorderController controller;

  /// Whether to render the phase name next to the dot.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final phase = controller.phase;
          final dot = Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: cockpitRecorderIndicatorColor(phase),
              shape: BoxShape.circle,
            ),
          );
          if (!showLabel) {
            return dot;
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              dot,
              const SizedBox(width: 6),
              Text(
                phase.name.toUpperCase(),
                style: cockpitRecorderPanelCaptionStyle.copyWith(
                  color: cockpitRecorderIndicatorColor(phase),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The phase-to-color mapping every recorder surface shares.
Color cockpitRecorderIndicatorColor(CockpitRecorderPhase phase) {
  return switch (phase) {
    CockpitRecorderPhase.idle => const Color(0xFF768390),
    CockpitRecorderPhase.recording => cockpitRecorderPanelDanger,
    CockpitRecorderPhase.paused => const Color(0xFFFFC857),
    CockpitRecorderPhase.stopped => cockpitRecorderPanelAccent,
  };
}
