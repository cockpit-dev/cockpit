import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Shared visual vocabulary of the recorder panel: a dark, compact dev-tool
// surface built from basic widgets only. The package's lib/ code uses no
// Material composite widgets — `package:flutter/material.dart` imports there
// exist only for primitives and type checks — so the panel stays consistent
// with that and depends on nothing beyond flutter/widgets and services.

const Color cockpitRecorderPanelBackground = Color(0xF20F141A);
const Color cockpitRecorderPanelSurface = Color(0xFF1A2129);
const Color cockpitRecorderPanelBorder = Color(0xFF2C3644);
const Color cockpitRecorderPanelText = Color(0xFFE6EDF3);
const Color cockpitRecorderPanelDimText = Color(0xFF93A1B3);
const Color cockpitRecorderPanelAccent = Color(0xFF38BDF8);
const Color cockpitRecorderPanelSuccess = Color(0xFF4ADE80);
const Color cockpitRecorderPanelDanger = Color(0xFFF43F5E);

/// The kind-to-color mapping timeline rows badge their steps with: gesture
/// kinds get the cooler hues, navigation and passive kinds stay dim.
Color cockpitRecorderStepKindColor(CockpitInteractionStepKind kind) {
  return switch (kind) {
    CockpitInteractionStepKind.tap => cockpitRecorderPanelAccent,
    CockpitInteractionStepKind.longPress => const Color(0xFF818CF8),
    CockpitInteractionStepKind.text => const Color(0xFF2DD4BF),
    CockpitInteractionStepKind.scroll => const Color(0xFFFFC857),
    CockpitInteractionStepKind.routeChange => const Color(0xFFA78BFA),
    CockpitInteractionStepKind.back => cockpitRecorderPanelDimText,
    CockpitInteractionStepKind.marker => const Color(0xFFFB923C),
    CockpitInteractionStepKind.note => cockpitRecorderPanelDimText,
  };
}

const TextStyle cockpitRecorderPanelTextStyle = TextStyle(
  color: cockpitRecorderPanelText,
  fontSize: 13,
  fontFamily: 'monospace',
);

const TextStyle cockpitRecorderPanelCaptionStyle = TextStyle(
  color: cockpitRecorderPanelDimText,
  fontSize: 11,
  fontFamily: 'monospace',
);

/// Compact labeled button for recorder panel actions. A `null` [onPressed]
/// renders the disabled state; the label stays visible so the affordance
/// remains discoverable.
final class CockpitRecorderPanelButton extends StatelessWidget {
  /// Creates a panel button showing [label].
  const CockpitRecorderPanelButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: enabled ? cockpitRecorderPanelSurface : null,
            border: Border.all(
              color: enabled
                  ? cockpitRecorderPanelBorder
                  : cockpitRecorderPanelBorder.withAlpha(0x55),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: cockpitRecorderPanelCaptionStyle.copyWith(
              color: enabled
                  ? cockpitRecorderPanelText
                  : cockpitRecorderPanelDimText.withAlpha(0x77),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded tag for segment labels, settle markers, and replay states.
final class CockpitRecorderPanelChip extends StatelessWidget {
  /// Creates a chip showing [label], tinted with [color].
  const CockpitRecorderPanelChip({
    required this.label,
    this.color = cockpitRecorderPanelDimText,
    super.key,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withAlpha(0x88)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: cockpitRecorderPanelCaptionStyle.copyWith(color: color),
      ),
    );
  }
}

/// Section title row with an optional trailing explanation for rules the
/// panel enforces (for example: only the newest step can be deleted).
final class CockpitRecorderPanelSectionHeader extends StatelessWidget {
  /// Creates a header showing [title].
  const CockpitRecorderPanelSectionHeader(this.title, {this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final caption = this.caption;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: cockpitRecorderPanelCaptionStyle.copyWith(
              color: cockpitRecorderPanelDimText,
            ),
          ),
          if (caption != null) ...<Widget>[
            const Spacer(),
            Flexible(
              child: Text(
                caption,
                overflow: TextOverflow.ellipsis,
                style: cockpitRecorderPanelCaptionStyle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single-line text field built on [EditableText] — the widgets-layer input
/// widget, since the panel avoids Material composite widgets.
///
/// The caller owns the [controller] (it reads the value when a button fires);
/// the field owns its [FocusNode] and exposes [onSubmitted] for enter-driven
/// flows.
final class CockpitRecorderPanelTextField extends StatefulWidget {
  /// Creates a panel text field.
  const CockpitRecorderPanelTextField({
    required this.controller,
    required this.hint,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CockpitRecorderPanelTextField> createState() =>
      _CockpitRecorderPanelTextFieldState();
}

final class _CockpitRecorderPanelTextFieldState
    extends State<CockpitRecorderPanelTextField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: cockpitRecorderPanelBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: EditableText(
        controller: widget.controller,
        focusNode: _focusNode,
        style: cockpitRecorderPanelCaptionStyle,
        cursorColor: cockpitRecorderPanelAccent,
        backgroundCursorColor: cockpitRecorderPanelDimText,
        textInputAction: TextInputAction.done,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
