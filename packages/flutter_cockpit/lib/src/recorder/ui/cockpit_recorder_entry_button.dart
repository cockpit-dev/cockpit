import 'package:flutter/widgets.dart';

import 'cockpit_recorder_panel_widgets.dart';

/// Presentational entry button for recorder hosts: a 40×40 solid dark
/// circle with a hairline stroke and a record-red dot.
///
/// Purely visual — [onTap] does nothing but invoke the callback, so hosts
/// decide what opening means (the default floating-ball host expands its
/// panel sheet). The dot is the entry's resting REC affordance, not live
/// state: the phase color belongs to [CockpitRecorderIndicator], which
/// hosts compose next to this button.
final class CockpitRecorderEntryButton extends StatelessWidget {
  /// Creates an entry button invoking [onTap] when tapped.
  const CockpitRecorderEntryButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cockpit recorder',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cockpitRecorderBallSurface,
            shape: BoxShape.circle,
            border: Border.all(color: cockpitRecorderStroke, width: 1.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: SizedBox(
              width: 10,
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cockpitRecorderRecord,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
