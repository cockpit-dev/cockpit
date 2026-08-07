import 'package:flutter/material.dart';

/// The single geometry source for every Cockpit Console form control and
/// button.
///
/// Screens never define control height, density, padding, or icon constraints.
/// Changing this specification updates text fields, dropdowns, read-only
/// fields, and all themed buttons together.
abstract final class ConsoleControlStyle {
  static const double height = 40;
  static const double compactHeight = 30;
  static const double labelGap = 5;
  static const double supportGap = 4;

  static const bool fieldIsDense = false;
  static const VisualDensity fieldDensity = VisualDensity.standard;
  static const EdgeInsets fieldPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  );
  static const BoxConstraints fieldConstraints = BoxConstraints.tightFor(
    height: height,
  );
  static const BoxConstraints fieldMinConstraints = BoxConstraints(
    minHeight: height,
  );
  static const BoxConstraints fieldIconConstraints = BoxConstraints.tightFor(
    width: height,
    height: height,
  );

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
  static const EdgeInsets compactButtonPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  );
  static const double iconButtonMinSize = 30;
  static const double iconButtonMaxSize = 36;
  static const double iconSize = 17;

  static InputDecoration field({
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      isDense: fieldIsDense,
      visualDensity: fieldDensity,
      constraints: fieldConstraints,
      contentPadding: fieldPadding,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconConstraints: prefixIcon == null ? null : fieldIconConstraints,
      suffixIconConstraints: suffixIcon == null ? null : fieldIconConstraints,
    );
  }

  static InputDecoration textArea({
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      isDense: fieldIsDense,
      visualDensity: fieldDensity,
      contentPadding: fieldPadding,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconConstraints: prefixIcon == null ? null : fieldIconConstraints,
      suffixIconConstraints: suffixIcon == null ? null : fieldIconConstraints,
    );
  }

  static ButtonStyle fieldIconButtonStyle() => IconButton.styleFrom(
    minimumSize: const Size.square(height),
    maximumSize: const Size.square(height),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
