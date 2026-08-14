import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const Duration _frameInterval = Duration(milliseconds: 16);
const Duration _transitionDuration = Duration(milliseconds: 320);
const Duration _defaultBudget = Duration(milliseconds: 640);
const Duration _defaultStallTimeout = Duration(milliseconds: 50);

Future<bool>? _visualFrameFlight;
bool _visualFrameFlightMayAnimate = false;

bool cockpitSupportsSyntheticVisualFrames(String platform) {
  return switch (platform.trim().toLowerCase()) {
    'macos' || 'windows' || 'linux' || 'web' => true,
    _ => false,
  };
}

/// Commits pending Flutter work when a desktop or web engine has stopped
/// delivering vsync because its surface is hidden, occluded, or backgrounded.
///
/// A normally delivered frame always wins. Synthetic frames are considered
/// only after a pending frame misses [stallTimeout], or when Flutter has
/// explicitly disabled frames. Mobile platforms and test bindings are never
/// driven this way.
Future<bool> ensureCockpitVisualFrame({
  required String platform,
  bool mayAnimate = false,
  Duration budget = _defaultBudget,
  Duration stallTimeout = _defaultStallTimeout,
}) async {
  final active = _visualFrameFlight;
  if (active != null) {
    final activeMayAnimate = _visualFrameFlightMayAnimate;
    final result = await active;
    if (!mayAnimate || activeMayAnimate) return result;
    return ensureCockpitVisualFrame(
      platform: platform,
      mayAnimate: true,
      budget: budget,
      stallTimeout: stallTimeout,
    );
  }

  final future = Future<bool>.microtask(
    () => _ensureCockpitVisualFrame(
      platform: platform,
      mayAnimate: mayAnimate,
      budget: budget,
      stallTimeout: stallTimeout,
    ),
  );
  _visualFrameFlight = future;
  _visualFrameFlightMayAnimate = mayAnimate;
  try {
    return await future;
  } finally {
    if (identical(_visualFrameFlight, future)) {
      _visualFrameFlight = null;
      _visualFrameFlightMayAnimate = false;
    }
  }
}

Future<bool> _ensureCockpitVisualFrame({
  required String platform,
  required bool mayAnimate,
  required Duration budget,
  required Duration stallTimeout,
}) async {
  if (!cockpitSupportsSyntheticVisualFrames(platform)) return false;

  WidgetsBinding binding;
  try {
    binding = WidgetsBinding.instance;
  } on Object {
    return false;
  }
  if (_isTestBinding(binding)) return false;

  final pending =
      binding.hasScheduledFrame ||
      binding.schedulerPhase != SchedulerPhase.idle;
  if (binding.framesEnabled && pending) {
    try {
      await binding.endOfFrame.timeout(stallTimeout);
      return true;
    } on TimeoutException {
      // A hidden or occluded engine can retain a scheduled frame indefinitely.
    }
  } else if (binding.framesEnabled) {
    return false;
  }

  if (binding.schedulerPhase != SchedulerPhase.idle) return false;
  return _driveSyntheticFrames(binding, mayAnimate: mayAnimate, budget: budget);
}

Future<bool> _driveSyntheticFrames(
  WidgetsBinding binding, {
  required bool mayAnimate,
  required Duration budget,
}) async {
  final offsets = _frameOffsets(mayAnimate: mayAnimate, budget: budget);
  final timeOrigin = binding.currentSystemFrameTimeStamp;
  var driven = 0;

  try {
    for (final offset in offsets) {
      if (binding.schedulerPhase != SchedulerPhase.idle) break;
      binding.handleBeginFrame(timeOrigin + offset);
      await Future<void>.microtask(() {});
      binding.handleDrawFrame();
      await Future<void>.microtask(() {});
      driven += 1;
    }
  } finally {
    if (driven > 0) binding.resetEpoch();
  }
  return driven > 0;
}

List<Duration> _frameOffsets({
  required bool mayAnimate,
  required Duration budget,
}) {
  final offsets = <Duration>[];

  void add(Duration value) {
    final bounded = value <= budget ? value : budget;
    if (bounded <= Duration.zero ||
        (offsets.isNotEmpty && bounded <= offsets.last)) {
      return;
    }
    offsets.add(bounded);
  }

  add(_frameInterval);
  if (mayAnimate) {
    // The first draw can create an implicit animation and the next begin-frame
    // establishes its ticker origin. Only the third frame may jump beyond the
    // transition duration without leaving Theme/Data lerps at their old end.
    add(_frameInterval * 2);
    add(_transitionDuration + (_frameInterval * 2));
  }
  return offsets;
}

bool _isTestBinding(WidgetsBinding binding) {
  return binding.runtimeType.toString().contains('TestWidgetsFlutterBinding');
}
