import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

/// Shared visual vocabulary of the recorder HUD: an iOS floating-overlay
/// palette — solid dark surfaces, restrained semantic colors, thumb-sized
/// controls — rebuilt from basic widgets only, so the panel depends on
/// nothing beyond flutter/widgets.

// --- Colors ---

/// The scrim behind an expanded panel sheet.
const Color cockpitRecorderScrim = Color(0x59000000);

/// Solid base fill of sheets, cards, and inputs.
const Color cockpitRecorderSurface = Color(0xFF1C1C1E);
const Color cockpitRecorderSurfaceElevated = Color(0xFF2C2C2E);

/// Hairline strokes and list separators over the solid surfaces.
const Color cockpitRecorderStroke = Color(0x33FFFFFF);
const Color cockpitRecorderStrokeHover = Color(0x4DFFFFFF);
const Color cockpitRecorderSeparator = Color(0x1FFFFFFF);

const Color cockpitRecorderInkPrimary = Color(0xFFF2F2F7);
const Color cockpitRecorderInkSecondary = Color(0x99EBEBF5);
const Color cockpitRecorderInkTertiary = Color(0x61EBEBF5);

/// Primary actions and selection.
const Color cockpitRecorderAccent = Color(0xFF0A84FF);

/// Recording, stop, and deviated outcomes.
const Color cockpitRecorderRecord = Color(0xFFFF453A);

/// Passed replay outcomes.
const Color cockpitRecorderSuccess = Color(0xFF30D158);

/// Paused phase and unresolved targets.
const Color cockpitRecorderWarning = Color(0xFFFF9F0A);

/// Inline error text and its banner fill.
const Color cockpitRecorderError = Color(0xFFFF6961);
const Color cockpitRecorderErrorBanner = Color(0x2EFF453A);

/// The floating ball's surface.
const Color cockpitRecorderBallSurface = Color(0xFF1C1C1E);

/// Chip and candidate fill over the solid surfaces.
const Color cockpitRecorderChipFill = Color(0x22FFFFFF);

// --- Radii ---

const double cockpitRecorderSheetRadius = 20;
const double cockpitRecorderButtonRadius = 12;
const double cockpitRecorderChipRadius = 8;

// --- Text styles (all platform-default fonts; nothing is monospaced) ---

/// Panel titles and status: 15/w600.
const TextStyle cockpitRecorderTitleStyle = TextStyle(
  color: cockpitRecorderInkPrimary,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

/// Step titles and input text: 14/w500.
const TextStyle cockpitRecorderBodyStyle = TextStyle(
  color: cockpitRecorderInkPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w500,
);

/// Secondary copy — selectors, notes, captions: 12.
const TextStyle cockpitRecorderSecondaryStyle = TextStyle(
  color: cockpitRecorderInkSecondary,
  fontSize: 12,
);

/// Micro copy — times, scores, status lines: 11.
const TextStyle cockpitRecorderMicroStyle = TextStyle(
  color: cockpitRecorderInkTertiary,
  fontSize: 11,
);

/// Visual tones of [CockpitRecorderPanelButton].
enum CockpitRecorderButtonVariant {
  /// Elevated fill with a hairline stroke for regular commands.
  secondary,

  /// Accent-filled for the one primary action of a zone.
  accent,

  /// Record-red-filled for the session's stop command.
  record,

  /// Borderless, for low-emphasis inline actions (dismiss, delete).
  text,
}

/// Labeled button in the recorder's control vocabulary. [height] picks the
/// touch target — 36 inside dense rows, 44 for primary controls — and the
/// label scale follows it (12/w500 at 36, 15 at 44). Filled tones label in
/// white w600. A `null` [onPressed] renders the disabled state; the label
/// stays visible so the affordance remains discoverable.
final class CockpitRecorderPanelButton extends StatefulWidget {
  /// Creates a panel button showing [label] in [variant].
  const CockpitRecorderPanelButton({
    required this.label,
    required this.onPressed,
    this.variant = CockpitRecorderButtonVariant.secondary,
    this.height = 36.0,
    this.fontSize,
    this.foreground,
    this.hoverForeground,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final CockpitRecorderButtonVariant variant;

  /// Touch-target height: 36 for in-row commands, 44 for primary controls.
  final double height;

  /// Overrides the derived label size (the error banner's 13, micro 11).
  final double? fontSize;

  /// Overrides the label color of the resting state.
  final Color? foreground;

  /// Overrides the label color of the hovered and pressed states.
  final Color? hoverForeground;

  @override
  State<CockpitRecorderPanelButton> createState() =>
      _CockpitRecorderPanelButtonState();
}

final class _CockpitRecorderPanelButtonState
    extends State<CockpitRecorderPanelButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final interactive = enabled && (_hovered || _pressed);
    final filled =
        widget.variant == CockpitRecorderButtonVariant.accent ||
        widget.variant == CockpitRecorderButtonVariant.record;
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _background(interactive),
                border: _border(interactive),
                borderRadius: BorderRadius.circular(
                  cockpitRecorderButtonRadius,
                ),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _foreground(interactive),
                  fontSize: widget.fontSize ?? (widget.height >= 44 ? 15 : 12),
                  fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _fillTone() => widget.variant == CockpitRecorderButtonVariant.accent
      ? cockpitRecorderAccent
      : cockpitRecorderRecord;

  Color _background(bool interactive) {
    final variant = widget.variant;
    if (widget.onPressed == null) {
      return variant == CockpitRecorderButtonVariant.secondary
          ? cockpitRecorderSurfaceElevated.withValues(alpha: 0.4)
          : variant == CockpitRecorderButtonVariant.text
          ? const Color(0x00000000)
          : _fillTone().withValues(alpha: 0.4);
    }
    return switch (variant) {
      CockpitRecorderButtonVariant.accent ||
      CockpitRecorderButtonVariant.record =>
        interactive ? _fillTone().withValues(alpha: 0.85) : _fillTone(),
      CockpitRecorderButtonVariant.secondary => cockpitRecorderSurfaceElevated,
      CockpitRecorderButtonVariant.text => const Color(0x00000000),
    };
  }

  Border? _border(bool interactive) {
    if (widget.variant != CockpitRecorderButtonVariant.secondary) {
      return null;
    }
    if (widget.onPressed == null) {
      return Border.all(color: cockpitRecorderStroke.withValues(alpha: 0.4));
    }
    return Border.all(
      color: interactive ? cockpitRecorderStrokeHover : cockpitRecorderStroke,
    );
  }

  Color _foreground(bool interactive) {
    if (widget.onPressed == null) {
      return widget.foreground ?? cockpitRecorderInkTertiary;
    }
    final rest =
        widget.foreground ??
        switch (widget.variant) {
          CockpitRecorderButtonVariant.accent ||
          CockpitRecorderButtonVariant.record => const Color(0xFFFFFFFF),
          CockpitRecorderButtonVariant.secondary => cockpitRecorderInkPrimary,
          CockpitRecorderButtonVariant.text => cockpitRecorderInkSecondary,
        };
    return interactive ? (widget.hoverForeground ?? rest) : rest;
  }
}

/// Small rounded tag for segment labels and inline chip groups: radius 8,
/// translucent fill, 11 tertiary ink.
final class CockpitRecorderPanelChip extends StatelessWidget {
  /// Creates a chip showing [label].
  const CockpitRecorderPanelChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cockpitRecorderChipFill,
        borderRadius: BorderRadius.circular(cockpitRecorderChipRadius),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: cockpitRecorderMicroStyle,
      ),
    );
  }
}

/// 28×28 borderless close button for panel headers.
final class CockpitRecorderPanelCloseButton extends StatefulWidget {
  /// Creates a close button invoking [onPressed].
  const CockpitRecorderPanelCloseButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  State<CockpitRecorderPanelCloseButton> createState() =>
      _CockpitRecorderPanelCloseButtonState();
}

final class _CockpitRecorderPanelCloseButtonState
    extends State<CockpitRecorderPanelCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Text(
                '✕',
                style: TextStyle(
                  color: _hovered
                      ? cockpitRecorderInkPrimary
                      : cockpitRecorderInkTertiary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single-line text field built on [EditableText] — the widgets-layer input
/// widget, since the panel avoids Material composite widgets. 36 high,
/// elevated fill with a hairline stroke that brightens on focus.
///
/// The caller owns the [controller] (it reads the value when a button fires);
/// the field owns its [FocusNode] and exposes [onSubmitted] for enter-driven
/// flows. The hint renders only while the field is empty.
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
  bool _empty = true;

  @override
  void initState() {
    super.initState();
    _empty = widget.controller.text.isEmpty;
    _focusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant CockpitRecorderPanelTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      _empty = widget.controller.text.isEmpty;
      widget.controller.addListener(_handleTextChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() => setState(() {});

  void _handleTextChange() {
    final empty = widget.controller.text.isEmpty;
    if (empty != _empty) {
      setState(() => _empty = empty);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: cockpitRecorderSurfaceElevated,
        borderRadius: BorderRadius.circular(cockpitRecorderButtonRadius),
        border: Border.all(
          color: _focusNode.hasFocus
              ? cockpitRecorderStrokeHover
              : cockpitRecorderStroke,
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (_empty)
            IgnorePointer(
              child: Text(
                widget.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cockpitRecorderSecondaryStyle.copyWith(
                  color: cockpitRecorderInkTertiary,
                ),
              ),
            ),
          EditableText(
            controller: widget.controller,
            focusNode: _focusNode,
            style: cockpitRecorderBodyStyle,
            cursorColor: cockpitRecorderAccent,
            backgroundCursorColor: cockpitRecorderInkTertiary,
            textInputAction: TextInputAction.done,
            onSubmitted: widget.onSubmitted,
          ),
        ],
      ),
    );
  }
}
