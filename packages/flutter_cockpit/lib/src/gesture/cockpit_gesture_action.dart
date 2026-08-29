import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';

import '../runtime/cockpit_target.dart';
import '../runtime/cockpit_target_geometry.dart';
import 'cockpit_gesture_anchor.dart';
import 'cockpit_gesture_profile.dart';
import 'cockpit_multi_touch_sequence.dart';

enum CockpitGestureActionType {
  tap,
  hover,
  wheel,
  longPress,
  doubleTap,
  drag,
  fling,
  swipe,
  pinchZoom,
  rotate,
  panZoom,
  multiTouch,
}

const double cockpitDefaultDragTouchSlop = 20.0;

final class CockpitGestureAction {
  const CockpitGestureAction._({
    required this.type,
    this.target,
    this.geometry,
    this.origin,
    this.anchor = CockpitGestureAnchor.center,
    this.pointerDeviceKind = PointerDeviceKind.touch,
    this.buttons = kPrimaryButton,
    this.duration = const Duration(milliseconds: 220),
    this.holdDuration = Duration.zero,
    this.interval = const Duration(milliseconds: 80),
    this.steps = 1,
    this.delta = Offset.zero,
    this.direction = AxisDirection.right,
    this.distanceFactor = 0.82,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.startSpan = 56,
    this.touchSlopX = cockpitDefaultDragTouchSlop,
    this.touchSlopY = cockpitDefaultDragTouchSlop,
    this.moveEventCount = 0,
    this.profile = CockpitGestureProfile.userLike,
    this.sampleHz,
    this.frameInterval,
    this.initialHoldDuration = Duration.zero,
    this.sequence,
  });

  const CockpitGestureAction.tap({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
  }) : this._(
         type: CockpitGestureActionType.tap,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: buttons,
         duration: Duration.zero,
         profile: CockpitGestureProfile.fast,
       );

  /// Moves a mouse pointer into the target without pressing a button.
  ///
  /// Keeping hover as a real pointer action is important for desktop and web
  /// Flutter widgets such as [MouseRegion], hover menus, and tooltip states.
  const CockpitGestureAction.hover({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.mouse,
  }) : this._(
         type: CockpitGestureActionType.hover,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: 0,
         duration: Duration.zero,
         profile: CockpitGestureProfile.fast,
       );

  /// Dispatches real [PointerScrollEvent] signals at the target position.
  ///
  /// Unlike a drag-based scroll, wheel input exercises Flutter's pointer
  /// signal path used by desktop scrollables, custom [Listener] handlers, and
  /// trackpad-aware widgets. [delta] is the per-event scroll delta and
  /// [steps] repeats it without retaining any event history.
  const CockpitGestureAction.wheel({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required Offset delta,
    int steps = 1,
    Duration interval = Duration.zero,
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.mouse,
  }) : this._(
         type: CockpitGestureActionType.wheel,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: 0,
         delta: delta,
         interval: interval,
         steps: steps,
         duration: Duration.zero,
         profile: CockpitGestureProfile.fast,
       );

  const CockpitGestureAction.longPress({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    Duration duration = const Duration(milliseconds: 600),
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
  }) : this._(
         type: CockpitGestureActionType.longPress,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: buttons,
         duration: duration,
         profile: CockpitGestureProfile.userLike,
       );

  const CockpitGestureAction.doubleTap({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    Duration interval = const Duration(milliseconds: 90),
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
  }) : this._(
         type: CockpitGestureActionType.doubleTap,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: buttons,
         interval: interval,
         profile: CockpitGestureProfile.fast,
       );

  const CockpitGestureAction.drag({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required Offset delta,
    Duration duration = const Duration(milliseconds: 220),
    Duration holdDuration = Duration.zero,
    double touchSlopX = cockpitDefaultDragTouchSlop,
    double touchSlopY = cockpitDefaultDragTouchSlop,
    int moveEventCount = 0,
    CockpitGestureProfile profile = CockpitGestureProfile.userLike,
    double? sampleHz,
    Duration? frameInterval,
    Duration initialHoldDuration = Duration.zero,
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
  }) : this._(
         type: CockpitGestureActionType.drag,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: buttons,
         delta: delta,
         duration: duration,
         holdDuration: holdDuration,
         touchSlopX: touchSlopX,
         touchSlopY: touchSlopY,
         moveEventCount: moveEventCount,
         profile: profile,
         sampleHz: sampleHz,
         frameInterval: frameInterval,
         initialHoldDuration: initialHoldDuration,
       );

  const CockpitGestureAction.swipe({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required AxisDirection direction,
    double distanceFactor = 0.82,
    Duration duration = const Duration(milliseconds: 200),
    int moveEventCount = 0,
    CockpitGestureProfile profile = CockpitGestureProfile.userLike,
    double? sampleHz,
    Duration? frameInterval,
    Duration initialHoldDuration = Duration.zero,
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
  }) : this._(
         type: CockpitGestureActionType.swipe,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: buttons,
         direction: direction,
         distanceFactor: distanceFactor,
         duration: duration,
         moveEventCount: moveEventCount,
         profile: profile,
         sampleHz: sampleHz,
         frameInterval: frameInterval,
         initialHoldDuration: initialHoldDuration,
       );

  const CockpitGestureAction.fling({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required Offset delta,
    Duration duration = const Duration(milliseconds: 96),
    int moveEventCount = 50,
    CockpitGestureProfile profile = CockpitGestureProfile.fast,
    double? sampleHz,
    Duration? frameInterval,
    Duration initialHoldDuration = Duration.zero,
    PointerDeviceKind pointerDeviceKind = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
  }) : this._(
         type: CockpitGestureActionType.fling,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         pointerDeviceKind: pointerDeviceKind,
         buttons: buttons,
         delta: delta,
         duration: duration,
         moveEventCount: moveEventCount,
         profile: profile,
         sampleHz: sampleHz,
         frameInterval: frameInterval,
         initialHoldDuration: initialHoldDuration,
       );

  const CockpitGestureAction.pinchZoom({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required double scale,
    double startSpan = 56,
    Duration duration = const Duration(milliseconds: 220),
    int moveEventCount = 0,
    CockpitGestureProfile profile = CockpitGestureProfile.precise,
    double? sampleHz,
    Duration? frameInterval,
    Duration initialHoldDuration = Duration.zero,
  }) : this._(
         type: CockpitGestureActionType.pinchZoom,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         scale: scale,
         startSpan: startSpan,
         duration: duration,
         moveEventCount: moveEventCount,
         profile: profile,
         sampleHz: sampleHz,
         frameInterval: frameInterval,
         initialHoldDuration: initialHoldDuration,
       );

  const CockpitGestureAction.rotate({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required double rotation,
    double startSpan = 56,
    Duration duration = const Duration(milliseconds: 220),
    int moveEventCount = 0,
    CockpitGestureProfile profile = CockpitGestureProfile.precise,
    double? sampleHz,
    Duration? frameInterval,
    Duration initialHoldDuration = Duration.zero,
  }) : this._(
         type: CockpitGestureActionType.rotate,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         rotation: rotation,
         startSpan: startSpan,
         duration: duration,
         moveEventCount: moveEventCount,
         profile: profile,
         sampleHz: sampleHz,
         frameInterval: frameInterval,
         initialHoldDuration: initialHoldDuration,
       );

  const CockpitGestureAction.panZoom({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    Offset delta = Offset.zero,
    double scale = 1.0,
    double rotation = 0.0,
    Duration duration = const Duration(milliseconds: 180),
    int moveEventCount = 0,
    CockpitGestureProfile profile = CockpitGestureProfile.userLike,
    double? sampleHz,
    Duration? frameInterval,
    Duration initialHoldDuration = Duration.zero,
  }) : this._(
         type: CockpitGestureActionType.panZoom,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         delta: delta,
         scale: scale,
         rotation: rotation,
         duration: duration,
         moveEventCount: moveEventCount,
         profile: profile,
         sampleHz: sampleHz,
         frameInterval: frameInterval,
         initialHoldDuration: initialHoldDuration,
       );

  const CockpitGestureAction.multiTouch({
    CockpitTarget? target,
    CockpitTargetGeometry? geometry,
    Offset? origin,
    CockpitGestureAnchor anchor = CockpitGestureAnchor.center,
    required CockpitMultiTouchSequence sequence,
  }) : this._(
         type: CockpitGestureActionType.multiTouch,
         target: target,
         geometry: geometry,
         origin: origin,
         anchor: anchor,
         sequence: sequence,
       );

  final CockpitGestureActionType type;
  final CockpitTarget? target;
  final CockpitTargetGeometry? geometry;
  final Offset? origin;
  final CockpitGestureAnchor anchor;
  final PointerDeviceKind pointerDeviceKind;
  final int buttons;
  final Duration duration;
  final Duration holdDuration;
  final Duration interval;
  final int steps;
  final Offset delta;
  final AxisDirection direction;
  final double distanceFactor;
  final double scale;
  final double rotation;
  final double startSpan;
  final double touchSlopX;
  final double touchSlopY;
  final int moveEventCount;
  final CockpitGestureProfile profile;
  final double? sampleHz;
  final Duration? frameInterval;
  final Duration initialHoldDuration;
  final CockpitMultiTouchSequence? sequence;
}
