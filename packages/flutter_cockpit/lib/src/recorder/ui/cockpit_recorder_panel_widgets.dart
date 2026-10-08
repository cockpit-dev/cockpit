import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Shared visual vocabulary of the recorder panel: the Cockpit Console
// dark-theme values rebuilt from basic widgets only. The package's lib/ code
// uses no Material composite widgets — `package:flutter/material.dart`
// imports there exist only for primitives and type checks — so the panel
// stays consistent with that and depends on nothing beyond flutter/widgets.

/// Surface stack: the overlay scrim, the card body, raised bars, inputs.
const Color cockpitRecorderScrim = Color(0xE608090A);
const Color cockpitRecorderSurface0 = Color(0xFF0D0E11);
const Color cockpitRecorderSurface1 = Color(0xFF121317);
const Color cockpitRecorderSurface2 = Color(0xFF181A1F);
const Color cockpitRecorderSurfaceHover = Color(0xFF25272D);

const Color cockpitRecorderBorder = Color(0xFF26272B);
const Color cockpitRecorderBorderHover = Color(0xFF34363B);
const Color cockpitRecorderBorderFocus = Color(0xFF3D3F45);

const Color cockpitRecorderInkPrimary = Color(0xFFEDEDEF);
const Color cockpitRecorderInkSecondary = Color(0xFF9B9DA3);
const Color cockpitRecorderInkTertiary = Color(0xFF7F8187);
const Color cockpitRecorderInkDisabled = Color(0xFF797B82);

const Color cockpitRecorderAccent = Color(0xFF5B8DEF);
const Color cockpitRecorderAccentHover = Color(0xFF7BA1F2);
const Color cockpitRecorderAccentFg = Color(0xFF08090A);

const Color cockpitRecorderSuccess = Color(0xFF4CB782);
const Color cockpitRecorderWarning = Color(0xFFF0A93C);
const Color cockpitRecorderError = Color(0xFFE5534B);
const Color cockpitRecorderErrorSubtle = Color(0xFF321815);

// UI text uses the platform's default font family; only data — selectors,
// step ids, counts, times, paths — is monospaced.

/// Panel titles: 15/w600.
const TextStyle cockpitRecorderTitleStyle = TextStyle(
  color: cockpitRecorderInkPrimary,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

/// Body copy and control labels: 13/w500.
const TextStyle cockpitRecorderBodyStyle = TextStyle(
  color: cockpitRecorderInkPrimary,
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

/// Secondary one-line copy: 11.
const TextStyle cockpitRecorderCaptionStyle = TextStyle(
  color: cockpitRecorderInkSecondary,
  fontSize: 11,
);

/// Data text: monospaced 11.
const TextStyle cockpitRecorderMonoStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 11,
  color: cockpitRecorderInkSecondary,
);

/// Visual variants of [CockpitRecorderPanelButton].
enum CockpitRecorderButtonVariant {
  /// Accent-filled for the one primary action of a zone.
  primary,

  /// Raised surface with a border for regular commands.
  secondary,

  /// Borderless, for low-emphasis inline actions (dismiss, delete).
  text,
}

/// Labeled button in the recorder's control vocabulary: 32 high, radius 8,
/// horizontal padding 12, 13/w500 label. A `null` [onPressed] renders the
/// disabled state; the label stays visible so the affordance remains
/// discoverable. Hover and pressed states darken through [MouseRegion].
final class CockpitRecorderPanelButton extends StatefulWidget {
  /// Creates a panel button showing [label] in [variant].
  const CockpitRecorderPanelButton({
    required this.label,
    required this.onPressed,
    this.variant = CockpitRecorderButtonVariant.secondary,
    this.compact = false,
    this.foreground,
    this.hoverForeground,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final CockpitRecorderButtonVariant variant;

  /// Shrinks to height 28 with a 12/w500 label for in-row editors.
  final bool compact;

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
    final foreground = interactive
        ? (widget.hoverForeground ?? _hoverForeground)
        : (widget.foreground ?? _restForeground);
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
              height: widget.compact ? 28 : 32,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 12,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _background,
                border: _border,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: widget.compact ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get _restForeground => switch (widget.variant) {
    CockpitRecorderButtonVariant.primary => cockpitRecorderAccentFg,
    CockpitRecorderButtonVariant.secondary => cockpitRecorderInkPrimary,
    CockpitRecorderButtonVariant.text => cockpitRecorderInkSecondary,
  };

  Color get _hoverForeground => switch (widget.variant) {
    CockpitRecorderButtonVariant.primary => cockpitRecorderAccentFg,
    CockpitRecorderButtonVariant.secondary => cockpitRecorderInkPrimary,
    CockpitRecorderButtonVariant.text => cockpitRecorderInkPrimary,
  };

  Color get _background {
    final disabled = widget.onPressed == null;
    if (disabled) {
      return switch (widget.variant) {
        CockpitRecorderButtonVariant.text => const Color(0x00000000),
        _ => cockpitRecorderSurface2,
      };
    }
    if (!_hovered && !_pressed) {
      return switch (widget.variant) {
        CockpitRecorderButtonVariant.primary => cockpitRecorderAccent,
        CockpitRecorderButtonVariant.secondary => cockpitRecorderSurface2,
        CockpitRecorderButtonVariant.text => const Color(0x00000000),
      };
    }
    return switch (widget.variant) {
      CockpitRecorderButtonVariant.primary =>
        _pressed ? cockpitRecorderAccent : cockpitRecorderAccentHover,
      CockpitRecorderButtonVariant.secondary => cockpitRecorderSurfaceHover,
      CockpitRecorderButtonVariant.text => cockpitRecorderSurfaceHover,
    };
  }

  Border get _border {
    if (widget.variant == CockpitRecorderButtonVariant.text) {
      return Border.all(color: const Color(0x00000000));
    }
    if (widget.onPressed == null) {
      return Border.all(color: cockpitRecorderBorder.withAlpha(0x66));
    }
    if (_pressed || _hovered) {
      return Border.all(color: cockpitRecorderBorderHover);
    }
    return Border.all(color: cockpitRecorderBorder);
  }
}

/// Small squared tag for segment labels: surface2 background, radius 4,
/// 10px tertiary ink.
final class CockpitRecorderPanelChip extends StatelessWidget {
  /// Creates a chip showing [label].
  const CockpitRecorderPanelChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cockpitRecorderSurface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: cockpitRecorderInkTertiary, fontSize: 10),
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? cockpitRecorderSurfaceHover : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '✕',
              style: TextStyle(
                color: _hovered
                    ? cockpitRecorderInkPrimary
                    : cockpitRecorderInkSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single-line text field built on [EditableText] — the widgets-layer input
/// widget, since the panel avoids Material composite widgets. 32 high,
/// surface2 fill, focus ring in [cockpitRecorderBorderFocus].
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
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: cockpitRecorderSurface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focusNode.hasFocus
              ? cockpitRecorderBorderFocus
              : cockpitRecorderBorder,
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
                style: const TextStyle(
                  color: cockpitRecorderInkTertiary,
                  fontSize: 12,
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
