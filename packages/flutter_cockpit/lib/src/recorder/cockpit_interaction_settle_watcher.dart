import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Non-blocking scheduler-quiet watch that back-fills `settledAfterMs` for a
/// recorded step.
///
/// The watch never parks the UI thread: it samples the [SchedulerBinding] on
/// a periodic [Timer] and reports the elapsed time once the scheduler has
/// stayed idle for [quietWindow], bounded by [timeout] — a step whose watch
/// times out simply keeps `settledAfterMs == null`. Elapsed time is measured
/// in ticks so tests drive the watch entirely through the fake clock pumped
/// into periodic timers; production precision is [tickPeriod].
final class CockpitInteractionSettleWatcher {
  /// Creates a watch. Pass [isSchedulerIdle] to substitute the idle probe in
  /// tests.
  CockpitInteractionSettleWatcher({
    required this.quietWindow,
    required this.timeout,
    required this.onSettled,
    required this.onFinished,
    this.tickPeriod = const Duration(milliseconds: 50),
    bool Function()? isSchedulerIdle,
  }) : _isSchedulerIdle = isSchedulerIdle ?? _defaultSchedulerIdle;

  /// Idle duration required before the watch reports a settle.
  final Duration quietWindow;

  /// Wall-clock bound on the whole watch, measured from [start].
  final Duration timeout;

  /// Sampling cadence; also the precision of the reported settle time.
  final Duration tickPeriod;

  /// Invoked with the elapsed time (ms) from [start] to detected quiet.
  final void Function(int settledAfterMs) onSettled;

  /// Invoked exactly once when the watch ends, after [onSettled] on success
  /// and without it on timeout. Never invoked by an external [cancel].
  final VoidCallback onFinished;

  final bool Function() _isSchedulerIdle;

  Timer? _timer;
  int _ticks = 0;
  int? _quietSinceTick;

  /// Whether the watch is still running.
  bool get isRunning => _timer != null;

  /// Starts sampling. Starting an already-running watch is a no-op.
  void start() {
    _timer ??= Timer.periodic(tickPeriod, (_) => _tick());
  }

  /// Stops the watch without reporting. Safe to call repeatedly.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    _ticks += 1;
    final elapsed = tickPeriod * _ticks;
    if (elapsed >= timeout) {
      cancel();
      onFinished();
      return;
    }
    if (!_isSchedulerIdle()) {
      _quietSinceTick = null;
      return;
    }
    final quietSince = _quietSinceTick ?? _ticks;
    _quietSinceTick = quietSince;
    final quietDuration = tickPeriod * (_ticks - quietSince);
    if (quietDuration < quietWindow) {
      return;
    }
    cancel();
    onSettled(elapsed.inMilliseconds);
    onFinished();
  }

  static bool _defaultSchedulerIdle() {
    final binding = SchedulerBinding.instance;
    return binding.schedulerPhase == SchedulerPhase.idle &&
        !binding.hasScheduledFrame;
  }
}
