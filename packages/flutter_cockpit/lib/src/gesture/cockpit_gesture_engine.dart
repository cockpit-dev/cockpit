import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../runtime/cockpit_target_geometry.dart';
import '../runtime/cockpit_target_geometry_resolver.dart';
import 'cockpit_gesture_action.dart';
import 'cockpit_gesture_anchor.dart';
import 'cockpit_gesture_profile.dart';
import 'cockpit_multi_touch_sequence.dart';

typedef CockpitGestureDelay = Future<void> Function([Duration? duration]);
typedef CockpitViewportGeometryProvider = CockpitTargetGeometry? Function();

final class CockpitGestureEngine {
  CockpitGestureEngine({
    CockpitGestureDelay? delay,
    CockpitViewportGeometryProvider? viewportGeometryProvider,
  }) : _delay = delay ?? _defaultDelay,
       _viewportGeometryProvider = viewportGeometryProvider;

  final CockpitGestureDelay _delay;
  final CockpitViewportGeometryProvider? _viewportGeometryProvider;

  Future<void> perform(CockpitGestureAction action) async {
    final geometry = _resolveGeometry(action);
    final origin = _resolvePrimaryOrigin(action, geometry);
    switch (action.type) {
      case CockpitGestureActionType.tap:
        await _performTap(
          geometry,
          origin: origin,
          pointerDeviceKind: action.pointerDeviceKind,
          buttons: action.buttons,
        );
      case CockpitGestureActionType.longPress:
        await _performLongPress(
          geometry,
          action.duration,
          origin: origin,
          pointerDeviceKind: action.pointerDeviceKind,
          buttons: action.buttons,
        );
      case CockpitGestureActionType.doubleTap:
        await _performDoubleTap(
          geometry,
          action.interval,
          origin: origin,
          pointerDeviceKind: action.pointerDeviceKind,
          buttons: action.buttons,
        );
      case CockpitGestureActionType.drag:
        await _performDrag(
          geometry: geometry,
          origin: origin,
          delta: action.delta,
          duration: action.duration,
          holdDuration: action.holdDuration,
          touchSlopX: action.touchSlopX,
          touchSlopY: action.touchSlopY,
          moveEventCount: action.moveEventCount,
          profile: action.profile,
          sampleHz: action.sampleHz,
          frameInterval: action.frameInterval,
          initialHoldDuration: action.initialHoldDuration,
          pointerDeviceKind: action.pointerDeviceKind,
          buttons: action.buttons,
        );
      case CockpitGestureActionType.fling:
        await _performFling(
          geometry: geometry,
          origin: origin,
          delta: action.delta,
          duration: action.duration,
          moveEventCount: action.moveEventCount,
          profile: action.profile,
          sampleHz: action.sampleHz,
          frameInterval: action.frameInterval,
          initialHoldDuration: action.initialHoldDuration,
          pointerDeviceKind: action.pointerDeviceKind,
          buttons: action.buttons,
        );
      case CockpitGestureActionType.swipe:
        await _performSwipe(
          geometry: geometry,
          origin: origin,
          useExplicitOrigin:
              action.origin != null ||
              action.anchor != CockpitGestureAnchor.center,
          direction: action.direction,
          distanceFactor: action.distanceFactor,
          duration: action.duration,
          moveEventCount: action.moveEventCount,
          profile: action.profile,
          sampleHz: action.sampleHz,
          frameInterval: action.frameInterval,
          initialHoldDuration: action.initialHoldDuration,
          pointerDeviceKind: action.pointerDeviceKind,
          buttons: action.buttons,
        );
      case CockpitGestureActionType.pinchZoom:
        await _performPinchZoom(
          geometry: geometry,
          origin: origin,
          scale: action.scale,
          startSpan: action.startSpan,
          duration: action.duration,
          moveEventCount: action.moveEventCount,
          profile: action.profile,
          sampleHz: action.sampleHz,
          frameInterval: action.frameInterval,
          initialHoldDuration: action.initialHoldDuration,
        );
      case CockpitGestureActionType.rotate:
        await _performRotate(
          geometry: geometry,
          origin: origin,
          rotation: action.rotation,
          startSpan: action.startSpan,
          duration: action.duration,
          moveEventCount: action.moveEventCount,
          profile: action.profile,
          sampleHz: action.sampleHz,
          frameInterval: action.frameInterval,
          initialHoldDuration: action.initialHoldDuration,
        );
      case CockpitGestureActionType.panZoom:
        await _performPanZoom(
          geometry: geometry,
          origin: origin,
          delta: action.delta,
          scale: action.scale,
          rotation: action.rotation,
          duration: action.duration,
          moveEventCount: action.moveEventCount,
          profile: action.profile,
          sampleHz: action.sampleHz,
          frameInterval: action.frameInterval,
          initialHoldDuration: action.initialHoldDuration,
        );
      case CockpitGestureActionType.multiTouch:
        final sequence = action.sequence;
        if (sequence == null) {
          throw ArgumentError.value(
            action.sequence,
            'action.sequence',
            'Multi-touch actions require a sequence.',
          );
        }
        await _performMultiTouch(
          geometry: geometry,
          origin: origin,
          sequence: sequence,
        );
    }
  }

  Future<void> _performTap(
    CockpitTargetGeometry geometry, {
    required Offset origin,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) async {
    _dispatchDown(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
      timeStamp: Duration.zero,
    );
    await _delay(Duration.zero);
    _dispatchUp(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      timeStamp: const Duration(milliseconds: 32),
    );
    await _delay(Duration.zero);
  }

  Future<void> _performLongPress(
    CockpitTargetGeometry geometry,
    Duration duration, {
    required Offset origin,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) async {
    _dispatchDown(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
      timeStamp: Duration.zero,
    );
    await _delay(Duration.zero);
    await _delay(duration);
    _dispatchUp(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      timeStamp: duration,
    );
    await _delay(Duration.zero);
  }

  Future<void> _performDoubleTap(
    CockpitTargetGeometry geometry,
    Duration interval, {
    required Offset origin,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) async {
    _dispatchDown(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
      timeStamp: Duration.zero,
    );
    await _delay(Duration.zero);
    _dispatchUp(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      timeStamp: const Duration(milliseconds: 32),
    );
    await _delay(interval);
    _dispatchDown(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
      timeStamp: interval + const Duration(milliseconds: 32),
    );
    await _delay(Duration.zero);
    _dispatchUp(
      pointer: 1,
      geometry: geometry,
      position: origin,
      pointerDeviceKind: pointerDeviceKind,
      timeStamp: interval + const Duration(milliseconds: 64),
    );
    await _delay(Duration.zero);
  }

  Future<void> _performDrag({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required Offset delta,
    required Duration duration,
    required Duration holdDuration,
    double touchSlopX = cockpitDefaultDragTouchSlop,
    double touchSlopY = cockpitDefaultDragTouchSlop,
    int moveEventCount = 0,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) async {
    final start = origin;
    final end = origin + delta;
    await _dispatchPolylineDrag(
      geometry: geometry,
      waypoints: _buildSlopAwareDragWaypoints(
        start,
        end,
        touchSlopX: touchSlopX,
        touchSlopY: touchSlopY,
      ),
      duration: duration,
      holdDuration: holdDuration + initialHoldDuration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
    );
  }

  Future<void> _performSwipe({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required bool useExplicitOrigin,
    required AxisDirection direction,
    required double distanceFactor,
    required Duration duration,
    required int moveEventCount,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) {
    final clampedFactor = distanceFactor.clamp(0.15, 0.95);
    final distance = switch (direction) {
      AxisDirection.left ||
      AxisDirection.right => math.max(geometry.width * clampedFactor, 96),
      AxisDirection.up ||
      AxisDirection.down => math.max(geometry.height * clampedFactor, 96),
    }.toDouble();
    final start = useExplicitOrigin
        ? origin
        : switch (direction) {
            AxisDirection.left => Offset(
              geometry.right - (geometry.width * 0.18),
              geometry.centerY,
            ),
            AxisDirection.right => Offset(
              geometry.left + (geometry.width * 0.18),
              geometry.centerY,
            ),
            AxisDirection.up => Offset(
              geometry.centerX,
              geometry.bottom - (geometry.height * 0.18),
            ),
            AxisDirection.down => Offset(
              geometry.centerX,
              geometry.top + (geometry.height * 0.18),
            ),
          };
    final end = switch (direction) {
      AxisDirection.left => Offset(start.dx - distance, start.dy),
      AxisDirection.right => Offset(start.dx + distance, start.dy),
      AxisDirection.up => Offset(start.dx, start.dy - distance),
      AxisDirection.down => Offset(start.dx, start.dy + distance),
    };
    return _dispatchPolylineDrag(
      geometry: geometry,
      waypoints: <Offset>[start, end],
      duration: duration,
      holdDuration: initialHoldDuration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
    );
  }

  Future<void> _performFling({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required Offset delta,
    required Duration duration,
    int moveEventCount = 50,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) {
    return _dispatchPolylineDrag(
      geometry: geometry,
      waypoints: <Offset>[origin, origin + delta],
      duration: duration,
      holdDuration: initialHoldDuration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
    );
  }

  Future<void> _performPinchZoom({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required double scale,
    required double startSpan,
    required Duration duration,
    int moveEventCount = 0,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
  }) async {
    final clampedScale = scale.clamp(0.25, 4.0);
    final baseSpan = _resolveGestureSpan(geometry, startSpan);
    final endSpan = baseSpan * clampedScale;
    await _performInterpolatedMultiPointerGesture(
      geometry: geometry,
      origin: origin,
      startOffsets: <int, Offset>{
        1: Offset(-baseSpan / 2, 0),
        2: Offset(baseSpan / 2, 0),
      },
      endOffsets: <int, Offset>{
        1: Offset(-endSpan / 2, 0),
        2: Offset(endSpan / 2, 0),
      },
      duration: duration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      initialHoldDuration: initialHoldDuration,
    );
  }

  Future<void> _performRotate({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required double rotation,
    required double startSpan,
    required Duration duration,
    int moveEventCount = 0,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
  }) async {
    final span = _resolveGestureSpan(geometry, startSpan);
    final radius = span / 2;
    // A mathematically pure rotation changes neither span nor focal point, so
    // Flutter's scale recognizer cannot win against an enclosing scrollable.
    // Cross scale slop first, then rotate from the recognizer's new baseline.
    final recognitionRadius = radius + kScaleSlop + 4;
    final endLeft = Offset(
      -recognitionRadius * math.cos(rotation),
      -recognitionRadius * math.sin(rotation),
    );
    final endRight = Offset(
      recognitionRadius * math.cos(rotation),
      recognitionRadius * math.sin(rotation),
    );
    await _performInterpolatedMultiPointerGesture(
      geometry: geometry,
      origin: origin,
      startOffsets: <int, Offset>{1: Offset(-radius, 0), 2: Offset(radius, 0)},
      recognitionOffsets: <int, Offset>{
        1: Offset(-recognitionRadius, 0),
        2: Offset(recognitionRadius, 0),
      },
      endOffsets: <int, Offset>{1: endLeft, 2: endRight},
      duration: duration,
      moveEventCount: moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
      initialHoldDuration: initialHoldDuration,
    );
  }

  double _resolveGestureSpan(
    CockpitTargetGeometry geometry,
    double requestedSpan,
  ) {
    final referenceShortestSide = geometry.shortestSide > 0
        ? geometry.shortestSide
        : math.min(geometry.viewportWidth, geometry.viewportHeight);
    final maxSpan = math.max(12.0, referenceShortestSide * 0.85);
    return requestedSpan.clamp(12.0, maxSpan).toDouble();
  }

  Future<void> _performPanZoom({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required Offset delta,
    required double scale,
    required double rotation,
    required Duration duration,
    int moveEventCount = 0,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
  }) async {
    const pointer = 1;
    final stepCount = _resolvedMoveEventCount(
      duration,
      moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
    );
    _dispatchPanZoomStart(
      pointer: pointer,
      geometry: geometry,
      position: origin,
      timeStamp: Duration.zero,
    );
    await _delay(Duration.zero);
    if (initialHoldDuration > Duration.zero) {
      await _delay(initialHoldDuration);
    }
    var previousPan = Offset.zero;
    var previousUs = 0;
    for (var step = 1; step <= stepCount; step += 1) {
      final t = step / stepCount;
      final nextUs = (duration.inMicroseconds * t).round();
      final pan = delta * t;
      _dispatchPanZoomUpdate(
        pointer: pointer,
        geometry: geometry,
        position: origin,
        pan: pan,
        panDelta: pan - previousPan,
        scale: 1 + ((scale - 1) * t),
        rotation: rotation * t,
        timeStamp: initialHoldDuration + Duration(microseconds: nextUs),
      );
      previousPan = pan;
      await _delay(Duration(microseconds: nextUs - previousUs));
      previousUs = nextUs;
    }
    _dispatchPanZoomEnd(
      pointer: pointer,
      geometry: geometry,
      position: origin,
      timeStamp:
          initialHoldDuration + duration + const Duration(milliseconds: 24),
    );
    await _delay(Duration.zero);
  }

  Future<void> _performMultiTouch({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required CockpitMultiTouchSequence sequence,
  }) async {
    if (sequence.steps.isEmpty) {
      throw ArgumentError.value(
        sequence.steps,
        'sequence.steps',
        'Multi-touch sequences must contain at least one step.',
      );
    }

    final orderedSteps = sequence.steps.toList(growable: false)
      ..sort((left, right) {
        final timeCompare = left.atMs.compareTo(right.atMs);
        if (timeCompare != 0) {
          return timeCompare;
        }
        return left.pointer.compareTo(right.pointer);
      });
    _validateMultiTouchSequence(orderedSteps);

    final activePointers = <int, Offset>{};
    var currentAtMs = 0;
    try {
      for (final step in orderedSteps) {
        final deltaMs = step.atMs - currentAtMs;
        if (deltaMs > 0) {
          await _delay(Duration(milliseconds: deltaMs));
        }
        currentAtMs = step.atMs;

        final position = Offset(origin.dx + step.dx, origin.dy + step.dy);
        switch (step.phase) {
          case CockpitMultiTouchPhase.down:
            _dispatchDown(
              pointer: step.pointer,
              geometry: geometry,
              position: position,
              pointerDeviceKind: PointerDeviceKind.touch,
              buttons: kPrimaryButton,
              timeStamp: Duration(milliseconds: step.atMs),
            );
            activePointers[step.pointer] = position;
          case CockpitMultiTouchPhase.move:
            _dispatchMove(
              pointer: step.pointer,
              geometry: geometry,
              previousPosition: activePointers[step.pointer]!,
              nextPosition: position,
              pointerDeviceKind: PointerDeviceKind.touch,
              buttons: kPrimaryButton,
              timeStamp: Duration(milliseconds: step.atMs),
            );
            activePointers[step.pointer] = position;
          case CockpitMultiTouchPhase.up:
            _dispatchUp(
              pointer: step.pointer,
              geometry: geometry,
              position: position,
              pointerDeviceKind: PointerDeviceKind.touch,
              timeStamp: Duration(milliseconds: step.atMs),
            );
            activePointers.remove(step.pointer);
        }

        await _delay(Duration.zero);
      }
    } on Object {
      // Release every still-active pointer so a failed sequence cannot leave
      // phantom pointers stuck in GestureBinding.
      _cancelActivePointers(
        activePointers,
        geometry: geometry,
        timeStamp: Duration(milliseconds: currentAtMs),
      );
      rethrow;
    }

    await _delay(Duration.zero);
  }

  void _validateMultiTouchSequence(List<CockpitMultiTouchStep> orderedSteps) {
    final activePointers = <int>{};
    for (final step in orderedSteps) {
      switch (step.phase) {
        case CockpitMultiTouchPhase.down:
          if (!activePointers.add(step.pointer)) {
            throw ArgumentError.value(
              step.pointer,
              'step.pointer',
              'Down events require a pointer that is not already active.',
            );
          }
        case CockpitMultiTouchPhase.move:
          if (!activePointers.contains(step.pointer)) {
            throw ArgumentError.value(
              step.pointer,
              'step.pointer',
              'Move events require an active pointer.',
            );
          }
        case CockpitMultiTouchPhase.up:
          if (!activePointers.remove(step.pointer)) {
            throw ArgumentError.value(
              step.pointer,
              'step.pointer',
              'Up events require an active pointer.',
            );
          }
      }
    }
    if (activePointers.isNotEmpty) {
      throw ArgumentError(
        'Multi-touch sequences must release all active pointers before completion.',
      );
    }
  }

  void _cancelActivePointers(
    Map<int, Offset> activePointers, {
    required CockpitTargetGeometry geometry,
    required Duration timeStamp,
  }) {
    for (final entry in activePointers.entries) {
      try {
        _dispatchCancel(
          pointer: entry.key,
          geometry: geometry,
          position: entry.value,
          pointerDeviceKind: PointerDeviceKind.touch,
          timeStamp: timeStamp,
        );
      } on Object {
        // Best effort: keep cancelling the remaining pointers.
      }
    }
    activePointers.clear();
  }

  Future<void> _performInterpolatedMultiPointerGesture({
    required CockpitTargetGeometry geometry,
    required Offset origin,
    required Map<int, Offset> startOffsets,
    Map<int, Offset>? recognitionOffsets,
    required Map<int, Offset> endOffsets,
    required Duration duration,
    required int moveEventCount,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required Duration initialHoldDuration,
  }) async {
    final pointerIds = startOffsets.keys.toList(growable: false)..sort();
    final stepCount = _resolvedMoveEventCount(
      duration,
      moveEventCount,
      profile: profile,
      sampleHz: sampleHz,
      frameInterval: frameInterval,
    );
    final previousPositions = <int, Offset>{};
    for (final pointer in pointerIds) {
      final start = startOffsets[pointer];
      final end = endOffsets[pointer];
      if (start == null || end == null) {
        throw ArgumentError(
          'Multi-pointer gestures require matching start and end offsets.',
        );
      }
      previousPositions[pointer] = start;
      _dispatchDown(
        pointer: pointer,
        geometry: geometry,
        position: Offset(origin.dx + start.dx, origin.dy + start.dy),
        pointerDeviceKind: PointerDeviceKind.touch,
        buttons: kPrimaryButton,
        timeStamp: Duration.zero,
      );
    }
    await _delay(Duration.zero);
    if (initialHoldDuration > Duration.zero) {
      await _delay(initialHoldDuration);
    }
    var previousUs = 0;
    Future<void> dispatchPhase({
      required Map<int, Offset> phaseStart,
      required Map<int, Offset> phaseEnd,
      required int eventCount,
      required int durationUs,
    }) async {
      final phaseStartUs = previousUs;
      for (var step = 1; step <= eventCount; step += 1) {
        final t = step / eventCount;
        final nextUs = phaseStartUs + (durationUs * t).round();
        for (final pointer in pointerIds) {
          final start = phaseStart[pointer];
          final end = phaseEnd[pointer];
          if (start == null || end == null) {
            throw ArgumentError(
              'Multi-pointer gesture phases require matching pointer offsets.',
            );
          }
          final previousOffset = previousPositions[pointer]!;
          final nextOffset = Offset.lerp(start, end, t)!;
          _dispatchMove(
            pointer: pointer,
            geometry: geometry,
            previousPosition: Offset(
              origin.dx + previousOffset.dx,
              origin.dy + previousOffset.dy,
            ),
            nextPosition: Offset(
              origin.dx + nextOffset.dx,
              origin.dy + nextOffset.dy,
            ),
            pointerDeviceKind: PointerDeviceKind.touch,
            buttons: kPrimaryButton,
            timeStamp: initialHoldDuration + Duration(microseconds: nextUs),
          );
          previousPositions[pointer] = nextOffset;
        }
        await _delay(Duration(microseconds: nextUs - previousUs));
        previousUs = nextUs;
      }
    }

    if (recognitionOffsets == null) {
      await dispatchPhase(
        phaseStart: startOffsets,
        phaseEnd: endOffsets,
        eventCount: stepCount,
        durationUs: duration.inMicroseconds,
      );
    } else {
      final recognitionStepCount = math.max(2, (stepCount * 0.35).round());
      final actionStepCount = math.max(2, stepCount - recognitionStepCount);
      final recognitionDurationUs = (duration.inMicroseconds * 0.35).round();
      await dispatchPhase(
        phaseStart: startOffsets,
        phaseEnd: recognitionOffsets,
        eventCount: recognitionStepCount,
        durationUs: recognitionDurationUs,
      );
      await _delay(Duration.zero);
      await dispatchPhase(
        phaseStart: recognitionOffsets,
        phaseEnd: endOffsets,
        eventCount: actionStepCount,
        durationUs: duration.inMicroseconds - recognitionDurationUs,
      );
    }

    for (final pointer in pointerIds.reversed) {
      final end = previousPositions[pointer]!;
      _dispatchUp(
        pointer: pointer,
        geometry: geometry,
        position: Offset(origin.dx + end.dx, origin.dy + end.dy),
        pointerDeviceKind: PointerDeviceKind.touch,
        timeStamp:
            initialHoldDuration + duration + const Duration(milliseconds: 24),
      );
    }
    await _delay(Duration.zero);
  }

  Future<void> _dispatchPolylineDrag({
    required CockpitTargetGeometry geometry,
    required List<Offset> waypoints,
    required Duration duration,
    required Duration holdDuration,
    int moveEventCount = 0,
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
  }) async {
    final normalizedWaypoints = _normalizeWaypoints(waypoints);
    if (normalizedWaypoints.length < 2) {
      throw ArgumentError.value(
        waypoints,
        'waypoints',
        'Gesture paths must contain at least two unique points.',
      );
    }
    final start = normalizedWaypoints.first;
    final end = normalizedWaypoints.last;
    final sampledPositions = _samplePolyline(
      normalizedWaypoints,
      _resolvedMoveEventCount(
        duration,
        moveEventCount,
        profile: profile,
        sampleHz: sampleHz,
        frameInterval: frameInterval,
      ),
    );

    _dispatchDown(
      pointer: 1,
      geometry: geometry,
      position: start,
      pointerDeviceKind: pointerDeviceKind,
      buttons: buttons,
      timeStamp: Duration.zero,
    );
    await _delay(Duration.zero);
    if (holdDuration > Duration.zero) {
      await _delay(holdDuration);
    }

    var previous = start;
    var previousUs = 0;
    for (var index = 0; index < sampledPositions.length; index += 1) {
      final t = (index + 1) / sampledPositions.length;
      final nextUs = (duration.inMicroseconds * t).round();
      final next = sampledPositions[index];
      _dispatchMove(
        pointer: 1,
        geometry: geometry,
        previousPosition: previous,
        nextPosition: next,
        pointerDeviceKind: pointerDeviceKind,
        buttons: buttons,
        timeStamp: holdDuration + Duration(microseconds: nextUs),
      );
      previous = next;
      await _delay(Duration(microseconds: nextUs - previousUs));
      previousUs = nextUs;
    }

    _dispatchUp(
      pointer: 1,
      geometry: geometry,
      position: end,
      pointerDeviceKind: pointerDeviceKind,
      timeStamp: holdDuration + duration,
    );
    await _delay(Duration.zero);
  }

  List<Offset> _buildSlopAwareDragWaypoints(
    Offset start,
    Offset end, {
    required double touchSlopX,
    required double touchSlopY,
  }) {
    final offset = end - start;
    final separateX = offset.dx.abs() > touchSlopX && touchSlopX > 0;
    final separateY = offset.dy.abs() > touchSlopY && touchSlopY > 0;
    if (!separateX && !separateY) {
      return <Offset>[start, end];
    }

    final xSign = offset.dx.sign;
    final ySign = offset.dy.sign;
    final offsetX = offset.dx;
    final offsetY = offset.dy;
    final waypoints = <Offset>[start];

    if (offsetX == 0) {
      waypoints.add(start + Offset(0, touchSlopY * ySign));
      waypoints.add(end);
      return _normalizeWaypoints(waypoints);
    }
    if (offsetY == 0) {
      waypoints.add(start + Offset(touchSlopX * xSign, 0));
      waypoints.add(end);
      return _normalizeWaypoints(waypoints);
    }

    final offsetSlope = offsetY / offsetX;
    final inverseOffsetSlope = offsetX / offsetY;
    final slopSlope = touchSlopY / touchSlopX;
    final absoluteOffsetSlope = offsetSlope.abs();
    final signedSlopX = touchSlopX * xSign;
    final signedSlopY = touchSlopY * ySign;

    if (absoluteOffsetSlope != slopSlope) {
      if (absoluteOffsetSlope < slopSlope) {
        final diffY = offsetSlope.abs() * touchSlopX * ySign;
        waypoints.add(start + Offset(signedSlopX, diffY));
        if (offsetY.abs() > touchSlopY) {
          final diffY2 = signedSlopY - diffY;
          final diffX2 = inverseOffsetSlope * diffY2;
          waypoints.add(start + Offset(signedSlopX + diffX2, signedSlopY));
        }
      } else {
        final diffX = inverseOffsetSlope.abs() * touchSlopY * xSign;
        waypoints.add(start + Offset(diffX, signedSlopY));
        if (offsetX.abs() > touchSlopX) {
          final diffX2 = signedSlopX - diffX;
          final diffY2 = offsetSlope * diffX2;
          waypoints.add(start + Offset(signedSlopX, signedSlopY + diffY2));
        }
      }
    } else {
      waypoints.add(start + Offset(signedSlopX, signedSlopY));
    }
    waypoints.add(end);
    return _normalizeWaypoints(waypoints);
  }

  List<Offset> _normalizeWaypoints(List<Offset> waypoints) {
    final normalized = <Offset>[];
    for (final waypoint in waypoints) {
      if (normalized.isEmpty ||
          (normalized.last - waypoint).distanceSquared > 0.01) {
        normalized.add(waypoint);
      }
    }
    return normalized;
  }

  List<Offset> _samplePolyline(List<Offset> waypoints, int moveEventCount) {
    if (moveEventCount <= 0) {
      return <Offset>[waypoints.last];
    }
    final segmentLengths = <double>[];
    var totalLength = 0.0;
    for (var index = 0; index < waypoints.length - 1; index += 1) {
      final length = (waypoints[index + 1] - waypoints[index]).distance;
      segmentLengths.add(length);
      totalLength += length;
    }
    if (totalLength <= 0) {
      return List<Offset>.filled(
        moveEventCount,
        waypoints.last,
        growable: false,
      );
    }

    final sampled = <Offset>[];
    for (var step = 1; step <= moveEventCount; step += 1) {
      final targetDistance = totalLength * (step / moveEventCount);
      var traversed = 0.0;
      for (
        var segmentIndex = 0;
        segmentIndex < segmentLengths.length;
        segmentIndex += 1
      ) {
        final segmentLength = segmentLengths[segmentIndex];
        final nextTraversed = traversed + segmentLength;
        if (segmentIndex == segmentLengths.length - 1 ||
            targetDistance <= nextTraversed) {
          final localT = segmentLength == 0
              ? 1.0
              : ((targetDistance - traversed) / segmentLength).clamp(0.0, 1.0);
          sampled.add(
            Offset.lerp(
              waypoints[segmentIndex],
              waypoints[segmentIndex + 1],
              localT,
            )!,
          );
          break;
        }
        traversed = nextTraversed;
      }
    }
    return sampled;
  }

  int _resolvedMoveEventCount(
    Duration duration,
    int requestedCount, {
    required CockpitGestureProfile profile,
    double? sampleHz,
    Duration? frameInterval,
  }) {
    if (requestedCount > 0) {
      return requestedCount;
    }
    final hasExplicitSampling =
        (sampleHz != null && sampleHz > 0) ||
        (frameInterval != null && frameInterval > Duration.zero);
    final rawEstimate = switch ((sampleHz, frameInterval)) {
      (final hz?, _) when hz > 0 => duration.inMicroseconds / (1000000 / hz),
      (_, final interval?) when interval > Duration.zero =>
        duration.inMicroseconds / interval.inMicroseconds,
      _ =>
        duration.inMicroseconds /
            _defaultFrameIntervalFor(profile).inMicroseconds,
    };
    final estimated = rawEstimate.ceil();
    final minimum = hasExplicitSampling
        ? 1
        : switch (profile) {
            CockpitGestureProfile.fast => 6,
            CockpitGestureProfile.userLike => 10,
            CockpitGestureProfile.precise => 14,
          };
    final maximum = switch (profile) {
      CockpitGestureProfile.fast => 72,
      CockpitGestureProfile.userLike => 120,
      CockpitGestureProfile.precise => 180,
    };
    return math.max(minimum, math.min(maximum, estimated));
  }

  Duration _defaultFrameIntervalFor(CockpitGestureProfile profile) {
    return switch (profile) {
      CockpitGestureProfile.fast => const Duration(milliseconds: 22),
      CockpitGestureProfile.userLike => const Duration(milliseconds: 16),
      CockpitGestureProfile.precise => const Duration(milliseconds: 10),
    };
  }

  Offset _resolvePrimaryOrigin(
    CockpitGestureAction action,
    CockpitTargetGeometry geometry,
  ) {
    final explicitOrigin = action.origin;
    if (explicitOrigin != null) {
      return Offset(
        geometry.clampXToViewport(explicitOrigin.dx),
        geometry.clampYToViewport(explicitOrigin.dy),
      );
    }
    if (action.anchor == CockpitGestureAnchor.textHitTestable) {
      final textOrigin = _resolveTextHitTestableOrigin(action, geometry);
      if (textOrigin != null) {
        return textOrigin;
      }
    }
    final anchor = geometry.resolveAnchorPosition(action.anchor);
    return Offset(anchor.dx, anchor.dy);
  }

  Offset? _resolveTextHitTestableOrigin(
    CockpitGestureAction action,
    CockpitTargetGeometry geometry,
  ) {
    final diagnosticNode = action.target?.diagnosticNodeProvider?.call();
    final element = diagnosticNode is Element ? diagnosticNode : null;
    if (element == null || !element.mounted) {
      return null;
    }
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderParagraph) {
      return null;
    }
    final plainText = renderObject.text.toPlainText();
    if (plainText.isEmpty) {
      return null;
    }
    final boxes = renderObject.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plainText.length),
    );
    if (boxes.isEmpty) {
      return null;
    }
    final paragraphOrigin = renderObject.localToGlobal(Offset.zero);
    for (final box in boxes) {
      final globalCenter = box.toRect().center + paragraphOrigin;
      final clamped = Offset(
        geometry.clampXToViewport(globalCenter.dx),
        geometry.clampYToViewport(globalCenter.dy),
      );
      final hitTestResult = HitTestResult();
      GestureBinding.instance.hitTestInView(
        hitTestResult,
        clamped,
        geometry.viewId,
      );
      if (hitTestResult.path.any(
        (entry) => identical(entry.target, renderObject),
      )) {
        return clamped;
      }
    }
    return null;
  }

  CockpitTargetGeometry _resolveGeometry(CockpitGestureAction action) {
    final explicitGeometry = action.geometry;
    if (explicitGeometry != null) {
      return explicitGeometry;
    }

    final target = action.target;
    if (target != null) {
      final targetGeometry = CockpitTargetGeometryResolver.maybeFromTarget(
        target,
      );
      if (targetGeometry != null) {
        return targetGeometry;
      }
    }

    final viewportGeometry = _viewportGeometryProvider?.call();
    final origin = action.origin;
    if (viewportGeometry != null && origin != null) {
      return CockpitTargetGeometry.atPoint(
        x: origin.dx,
        y: origin.dy,
        viewportGeometry: viewportGeometry,
      );
    }
    if (viewportGeometry != null &&
        (action.type == CockpitGestureActionType.drag ||
            action.type == CockpitGestureActionType.fling ||
            action.type == CockpitGestureActionType.swipe ||
            action.type == CockpitGestureActionType.pinchZoom ||
            action.type == CockpitGestureActionType.rotate ||
            action.type == CockpitGestureActionType.panZoom ||
            action.type == CockpitGestureActionType.multiTouch)) {
      return viewportGeometry;
    }

    throw StateError(
      'Unable to resolve gesture geometry for ${action.type.name}.',
    );
  }

  void _dispatchDown({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset position,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
    required Duration timeStamp,
  }) {
    final clampedPosition = _clampToViewport(geometry, position);
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: _deviceForKind(pointerDeviceKind),
        kind: pointerDeviceKind,
        buttons: buttons,
        position: clampedPosition,
        viewId: geometry.viewId,
      ),
    );
  }

  void _dispatchMove({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset previousPosition,
    required Offset nextPosition,
    required PointerDeviceKind pointerDeviceKind,
    required int buttons,
    required Duration timeStamp,
  }) {
    final clampedPrevious = _clampToViewport(geometry, previousPosition);
    final clampedNext = _clampToViewport(geometry, nextPosition);
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: _deviceForKind(pointerDeviceKind),
        kind: pointerDeviceKind,
        position: clampedNext,
        delta: clampedNext - clampedPrevious,
        buttons: buttons,
        viewId: geometry.viewId,
      ),
    );
  }

  void _dispatchUp({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset position,
    required PointerDeviceKind pointerDeviceKind,
    required Duration timeStamp,
  }) {
    final clampedPosition = _clampToViewport(geometry, position);
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: _deviceForKind(pointerDeviceKind),
        kind: pointerDeviceKind,
        position: clampedPosition,
        viewId: geometry.viewId,
      ),
    );
  }

  void _dispatchCancel({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset position,
    required PointerDeviceKind pointerDeviceKind,
    required Duration timeStamp,
  }) {
    final clampedPosition = _clampToViewport(geometry, position);
    GestureBinding.instance.handlePointerEvent(
      PointerCancelEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: _deviceForKind(pointerDeviceKind),
        kind: pointerDeviceKind,
        position: clampedPosition,
        viewId: geometry.viewId,
      ),
    );
  }

  int _deviceForKind(PointerDeviceKind kind) {
    return kind == PointerDeviceKind.mouse ? 1 : 0;
  }

  void _dispatchPanZoomStart({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset position,
    required Duration timeStamp,
  }) {
    GestureBinding.instance.handlePointerEvent(
      PointerPanZoomStartEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: 0,
        position: _clampToViewport(geometry, position),
        viewId: geometry.viewId,
      ),
    );
  }

  void _dispatchPanZoomUpdate({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset position,
    required Offset pan,
    required Offset panDelta,
    required double scale,
    required double rotation,
    required Duration timeStamp,
  }) {
    GestureBinding.instance.handlePointerEvent(
      PointerPanZoomUpdateEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: 0,
        position: _clampToViewport(geometry, position),
        pan: pan,
        panDelta: panDelta,
        scale: scale,
        rotation: rotation,
        viewId: geometry.viewId,
      ),
    );
  }

  void _dispatchPanZoomEnd({
    required int pointer,
    required CockpitTargetGeometry geometry,
    required Offset position,
    required Duration timeStamp,
  }) {
    GestureBinding.instance.handlePointerEvent(
      PointerPanZoomEndEvent(
        timeStamp: timeStamp,
        pointer: pointer,
        device: 0,
        position: _clampToViewport(geometry, position),
        viewId: geometry.viewId,
      ),
    );
  }

  static Offset _clampToViewport(
    CockpitTargetGeometry geometry,
    Offset position,
  ) {
    return Offset(
      geometry.clampXToViewport(position.dx),
      geometry.clampYToViewport(position.dy),
    );
  }

  static Future<void> _defaultDelay([Duration? duration]) {
    final resolvedDuration = duration ?? Duration.zero;
    WidgetsBinding widgetsBinding;
    try {
      widgetsBinding = WidgetsBinding.instance;
    } on Object {
      return Future<void>.delayed(resolvedDuration);
    }
    if (_isTestBinding(widgetsBinding)) {
      final dynamic dynamicBinding = widgetsBinding;
      return dynamicBinding.pump(resolvedDuration) as Future<void>;
    }
    return Future<void>.delayed(resolvedDuration);
  }

  static bool _isTestBinding(WidgetsBinding widgetsBinding) {
    return widgetsBinding.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }
}
