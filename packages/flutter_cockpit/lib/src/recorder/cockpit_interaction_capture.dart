import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'cockpit_interaction_recorder.dart';
import 'cockpit_interaction_settle_watcher.dart';
import 'cockpit_interaction_target_matcher.dart';
import 'cockpit_interaction_text_capture.dart';

/// Classification and settle thresholds for [CockpitInteractionCapture].
///
/// All values are injectable for tests. With the defaults, any displacement
/// at or above [tapSlopPx] scrolls ([scrollMinPx] equals the slop), and a
/// stationary press held [longPressMs] or longer is a long press.
final class CockpitInteractionCaptureDefaults {
  /// Creates capture thresholds.
  const CockpitInteractionCaptureDefaults({
    this.tapSlopPx = 8.0,
    this.longPressMs = 500,
    this.scrollMinPx = 8.0,
    this.settleQuietWindowMs = 300,
    this.settleTimeoutMs = 5000,
  });

  /// Maximum pointer displacement (logical px) that still classifies as a
  /// tap or long-press.
  final double tapSlopPx;

  /// Minimum press duration (ms) for a stationary gesture to classify as a
  /// long press.
  final int longPressMs;

  /// Minimum pointer displacement (logical px) that classifies the gesture
  /// as a scroll.
  final double scrollMinPx;

  /// Scheduler quiet duration (ms) required before an action step is marked
  /// settled.
  final int settleQuietWindowMs;

  /// Upper bound (ms) on the settle watch of one action step.
  final int settleTimeoutMs;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitInteractionCaptureDefaults &&
            other.tapSlopPx == tapSlopPx &&
            other.longPressMs == longPressMs &&
            other.scrollMinPx == scrollMinPx &&
            other.settleQuietWindowMs == settleQuietWindowMs &&
            other.settleTimeoutMs == settleTimeoutMs;
  }

  @override
  int get hashCode => Object.hash(
    tapSlopPx,
    longPressMs,
    scrollMinPx,
    settleQuietWindowMs,
    settleTimeoutMs,
  );
}

/// The gesture under observation between pointer-down and up/cancel.
final class _ActiveGesture {
  _ActiveGesture({
    required this.downPosition,
    required this.downStopwatch,
    required this.candidates,
  });

  final Offset downPosition;
  final Stopwatch downStopwatch;
  final List<CockpitLocatorCandidate> candidates;

  bool get unresolved => candidates.isEmpty;
}

/// Captures organic user interaction inside [child] and feeds it to a
/// [CockpitInteractionRecorder].
///
/// The widget wraps the app surface as a translucent `Listener` ancestor, so
/// every app hit appears in its path. Pointer events are classified
/// (tap / long-press / scroll), text fields commit one `text` step when
/// focus leaves, and [routeName] diffs between rebuilds emit `routeChange`
/// steps. Steps record only while the recorder is `recording`; pause
/// suppression lives in the engine. Mounting and wiring are owned by
/// `FlutterCockpitRoot` — hosts never mount this widget directly.
final class CockpitInteractionCapture extends StatefulWidget {
  /// Creates a capture layer. [registry] resolves hits to registered
  /// targets; [routeName] participates in `routeChange` detection and stamps
  /// recorded steps.
  const CockpitInteractionCapture({
    required this.recorder,
    required this.registry,
    required this.child,
    this.routeName,
    this.defaults = const CockpitInteractionCaptureDefaults(),
    super.key,
  });

  final CockpitInteractionRecorder recorder;
  final CockpitTargetRegistry registry;
  final String? routeName;
  final CockpitInteractionCaptureDefaults defaults;
  final Widget child;

  @override
  State<CockpitInteractionCapture> createState() =>
      _CockpitInteractionCaptureState();
}

final class _CockpitInteractionCaptureState
    extends State<CockpitInteractionCapture> {
  final List<CockpitInteractionSettleWatcher> _settleWatches =
      <CockpitInteractionSettleWatcher>[];
  late final CockpitInteractionTextCapture _textCapture;
  int? _activePointer;
  _ActiveGesture? _gesture;
  int _viewId = 0;

  @override
  void initState() {
    super.initState();
    _textCapture = CockpitInteractionTextCapture(
      recorder: () => widget.recorder,
      registry: () => widget.registry,
      routeName: () => widget.routeName,
    );
    _textCapture.attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewId = View.of(context).viewId;
  }

  @override
  void didUpdateWidget(covariant CockpitInteractionCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeName != widget.routeName) {
      _recordRouteChange(from: oldWidget.routeName, to: widget.routeName);
    }
  }

  @override
  void dispose() {
    for (final watch in _settleWatches) {
      watch.cancel();
    }
    _settleWatches.clear();
    _textCapture.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) {
      // Multi-touch v1: only the first active pointer is recorded;
      // concurrent pointers are ignored until it completes.
      return;
    }
    _activePointer = event.pointer;
    if (widget.recorder.phase != CockpitRecorderPhase.recording ||
        widget.recorder.isReplaying) {
      return;
    }
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, event.position, _viewId);
    final path = result.path
        .map((entry) => entry.target)
        .whereType<RenderObject>()
        .toList(growable: false);
    if (widget.recorder.exclusions.coversPath(path)) {
      // The tombstone above keeps the excluded pointer occupying the gesture
      // slot until up/cancel; no step records from it.
      return;
    }
    final match = CockpitInteractionTargetMatcher.matchHitPath(
      widget.registry,
      path,
    );
    final candidates = match == null
        ? const <CockpitLocatorCandidate>[]
        : CockpitInteractionTargetMatcher.locatorCandidates(match);
    _gesture = _ActiveGesture(
      downPosition: event.position,
      downStopwatch: Stopwatch()..start(),
      candidates: candidates,
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    final gesture = _takeActiveGesture(event.pointer);
    if (gesture != null) {
      _recordGestureStep(gesture, event);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    // Cancelled gestures record nothing.
    _takeActiveGesture(event.pointer);
  }

  /// Releases the gesture slot when [pointer] is the tracked one, returning
  /// its gesture — `null` for an excluded or non-tracked pointer.
  _ActiveGesture? _takeActiveGesture(int pointer) {
    if (_activePointer != pointer) {
      return null;
    }
    _activePointer = null;
    final gesture = _gesture;
    _gesture = null;
    return gesture;
  }

  void _recordGestureStep(_ActiveGesture gesture, PointerUpEvent event) {
    final defaults = widget.defaults;
    final displacement = (event.position - gesture.downPosition).distance;
    final durationMs = gesture.downStopwatch.elapsed.inMilliseconds;
    final CockpitInteractionStepKind kind;
    final CockpitInteractionScrollDirection? direction;
    if (displacement >= defaults.scrollMinPx) {
      kind = CockpitInteractionStepKind.scroll;
      direction = _scrollDirection(event.position - gesture.downPosition);
    } else if (durationMs >= defaults.longPressMs &&
        displacement < defaults.tapSlopPx) {
      kind = CockpitInteractionStepKind.longPress;
      direction = null;
    } else {
      kind = CockpitInteractionStepKind.tap;
      direction = null;
    }
    final recorder = widget.recorder;
    final before = recorder.steps.length;
    recorder.recordInteractionStep(
      CockpitInteractionStep(
        stepId: 'pending',
        kind: kind,
        locatorCandidates: gesture.candidates,
        scrollDirection: direction,
        routeName: widget.routeName,
        positionDx: gesture.downPosition.dx,
        positionDy: gesture.downPosition.dy,
        unresolved: gesture.unresolved,
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.now(),
      ),
    );
    if (recorder.steps.length == before) {
      // The engine dropped the step (not recording); nothing to settle.
      return;
    }
    _startSettleWatch(recorder.steps.last.stepId);
  }

  /// Scroll direction follows the pointer's dominant-axis movement — the
  /// same motion a replay of the step must reproduce. Ties favor the
  /// horizontal axis.
  CockpitInteractionScrollDirection _scrollDirection(Offset delta) {
    if (delta.dx.abs() >= delta.dy.abs()) {
      return delta.dx >= 0
          ? CockpitInteractionScrollDirection.right
          : CockpitInteractionScrollDirection.left;
    }
    return delta.dy >= 0
        ? CockpitInteractionScrollDirection.down
        : CockpitInteractionScrollDirection.up;
  }

  void _recordRouteChange({String? from, String? to}) {
    if (widget.recorder.phase != CockpitRecorderPhase.recording ||
        widget.recorder.isReplaying) {
      return;
    }
    widget.recorder.recordInteractionStep(
      CockpitInteractionStep(
        stepId: 'pending',
        kind: CockpitInteractionStepKind.routeChange,
        routeName: to,
        fromRouteName: from,
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.now(),
      ),
    );
  }

  void _startSettleWatch(String stepId) {
    final defaults = widget.defaults;
    late final CockpitInteractionSettleWatcher watch;
    watch = CockpitInteractionSettleWatcher(
      quietWindow: Duration(milliseconds: defaults.settleQuietWindowMs),
      timeout: Duration(milliseconds: defaults.settleTimeoutMs),
      onSettled: (settledAfterMs) {
        _markStepSettled(stepId, settledAfterMs);
        _refreshRouteDiscovery();
      },
      onFinished: () => _settleWatches.remove(watch),
    );
    _settleWatches.add(watch);
    watch.start();
  }

  /// Refreshes route discovery once a recorded action settles.
  ///
  /// Route-name discovery is read-driven: this registry read re-runs tree
  /// discovery, which syncs the binding's route name and rebuilds this widget
  /// with the new route, emitting a `routeChange` step in [didUpdateWidget].
  /// A gesture can navigate on pointer-up (a back button pops a route), and
  /// the pointer-down read only saw the pre-action route, so without this
  /// refresh the change stays undiscovered until the next unrelated read.
  void _refreshRouteDiscovery() {
    if (widget.recorder.phase != CockpitRecorderPhase.recording ||
        widget.recorder.isReplaying) {
      return;
    }
    widget.registry.visibleTargets;
  }

  void _markStepSettled(String stepId, int settledAfterMs) {
    final recorder = widget.recorder;
    // Settling is legal while paused, but a stopped session or a discarded
    // step no longer accepts the back-fill.
    if (recorder.phase == CockpitRecorderPhase.stopped) {
      return;
    }
    final stillRecorded = recorder.steps.any((step) => step.stepId == stepId);
    if (!stillRecorded) {
      return;
    }
    recorder.markStepSettled(stepId, settledAfterMs);
  }
}
