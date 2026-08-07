import 'dart:math' as math;

import '../gesture/cockpit_gesture_anchor.dart';

final class CockpitTargetGeometry {
  /// Creates a CockpitTargetGeometry.
  const CockpitTargetGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.viewportLeft,
    required this.viewportTop,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.viewId,
  });

  /// Creates a CockpitTargetGeometry using the named constructor `atPoint`.
  factory CockpitTargetGeometry.atPoint({
    required double x,
    required double y,
    required CockpitTargetGeometry viewportGeometry,
  }) {
    return CockpitTargetGeometry(
      left: x,
      top: y,
      width: 0,
      height: 0,
      viewportLeft: viewportGeometry.viewportLeft,
      viewportTop: viewportGeometry.viewportTop,
      viewportWidth: viewportGeometry.viewportWidth,
      viewportHeight: viewportGeometry.viewportHeight,
      viewId: viewportGeometry.viewId,
    );
  }

  final double left;
  final double top;
  final double width;
  final double height;
  final double viewportLeft;
  final double viewportTop;
  final double viewportWidth;
  final double viewportHeight;
  final int viewId;

  double get right => left + width;
  double get bottom => top + height;
  double get viewportRight => viewportLeft + viewportWidth;
  double get viewportBottom => viewportTop + viewportHeight;
  double get centerX => left + (width / 2);
  double get centerY => top + (height / 2);
  double get shortestSide => math.min(width, height);

  bool containsPoint({
    required double dx,
    required double dy,
    double tolerance = 0,
  }) {
    return dx >= left - tolerance &&
        dx <= right + tolerance &&
        dy >= top - tolerance &&
        dy <= bottom + tolerance;
  }

  double clampXToViewport(double value, {double edgeInset = 1.0}) {
    final safeInsetX = math.min(edgeInset, viewportWidth / 2);
    final minX = viewportLeft + safeInsetX;
    final maxX = viewportRight - safeInsetX;
    return value.clamp(minX, maxX).toDouble();
  }

  double clampYToViewport(double value, {double edgeInset = 1.0}) {
    final safeInsetY = math.min(edgeInset, viewportHeight / 2);
    final minY = viewportTop + safeInsetY;
    final maxY = viewportBottom - safeInsetY;
    return value.clamp(minY, maxY).toDouble();
  }

  ({double dx, double dy}) resolveAnchorPosition(
    CockpitGestureAnchor anchor, {
    double edgeInset = 12.0,
  }) {
    final insetX = _axisInset(width, edgeInset);
    final insetY = _axisInset(height, edgeInset);
    final resolved = switch (anchor) {
      CockpitGestureAnchor.center ||
      CockpitGestureAnchor.textHitTestable => (dx: centerX, dy: centerY),
      CockpitGestureAnchor.topLeft => (dx: left + insetX, dy: top + insetY),
      CockpitGestureAnchor.topRight => (dx: right - insetX, dy: top + insetY),
      CockpitGestureAnchor.bottomLeft => (
        dx: left + insetX,
        dy: bottom - insetY,
      ),
      CockpitGestureAnchor.bottomRight => (
        dx: right - insetX,
        dy: bottom - insetY,
      ),
    };
    return (
      dx: clampXToViewport(resolved.dx),
      dy: clampYToViewport(resolved.dy),
    );
  }

  double _axisInset(double extent, double edgeInset) {
    final preferredInset = math.max(edgeInset, extent * 0.12);
    return math.min(preferredInset, math.max(extent / 2, 1.0));
  }

  /// Encodes this CockpitTargetGeometry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'viewportLeft': viewportLeft,
    'viewportTop': viewportTop,
    'viewportWidth': viewportWidth,
    'viewportHeight': viewportHeight,
    'viewId': viewId,
  };

  /// Decodes a CockpitTargetGeometry from a JSON object.
  factory CockpitTargetGeometry.fromJson(Map<String, Object?> json) {
    return CockpitTargetGeometry(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      viewportLeft: (json['viewportLeft'] as num).toDouble(),
      viewportTop: (json['viewportTop'] as num).toDouble(),
      viewportWidth: (json['viewportWidth'] as num).toDouble(),
      viewportHeight: (json['viewportHeight'] as num).toDouble(),
      viewId: json['viewId']! as int,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitTargetGeometry &&
            other.left == left &&
            other.top == top &&
            other.width == width &&
            other.height == height &&
            other.viewportLeft == viewportLeft &&
            other.viewportTop == viewportTop &&
            other.viewportWidth == viewportWidth &&
            other.viewportHeight == viewportHeight &&
            other.viewId == viewId;
  }

  @override
  int get hashCode => Object.hash(
    left,
    top,
    width,
    height,
    viewportLeft,
    viewportTop,
    viewportWidth,
    viewportHeight,
    viewId,
  );
}
