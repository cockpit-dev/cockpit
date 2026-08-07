import 'package:flutter/material.dart';

/// Shared superellipse geometry for the complete Cockpit Console surface.
abstract final class ConsoleShapes {
  static const double smallRadius = 8;
  static const double controlRadius = 10;
  static const double surfaceRadius = 12;
  static const double dialogRadius = 16;

  static RoundedSuperellipseBorder border({
    double radius = surfaceRadius,
    BorderSide side = BorderSide.none,
  }) {
    return RoundedSuperellipseBorder(
      side: side,
      borderRadius: BorderRadius.circular(radius),
    );
  }

  static ShapedInputBorder input(BorderSide side) {
    return ShapedInputBorder(
      borderSide: side,
      shape: border(radius: controlRadius),
    );
  }

  static ShapeDecoration decoration({
    Color? color,
    Color? borderColor,
    double borderWidth = 1,
    double radius = surfaceRadius,
    List<BoxShadow> shadows = const <BoxShadow>[],
  }) {
    return ShapeDecoration(
      color: color,
      shape: border(
        radius: radius,
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor, width: borderWidth),
      ),
      shadows: shadows,
    );
  }
}
