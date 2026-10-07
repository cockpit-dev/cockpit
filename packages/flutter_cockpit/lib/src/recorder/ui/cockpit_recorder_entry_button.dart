import 'package:flutter/widgets.dart';

import 'cockpit_recorder_panel_widgets.dart';

/// Presentational entry button for recorder hosts: a compact dark circle
/// with a record dot.
///
/// Purely visual — [onTap] does nothing but invoke the callback, so hosts
/// decide what opening means (the default floating-ball host expands its
/// panel sheet). The live phase color belongs to
/// [CockpitRecorderIndicator], which hosts compose next to this button.
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
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: cockpitRecorderPanelBackground,
            shape: BoxShape.circle,
            border: Border.all(color: cockpitRecorderPanelBorder, width: 1.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cockpitRecorderPanelDanger,
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
