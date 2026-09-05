import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:cockpit_protocol/cockpit_protocol.dart';

export 'package:cockpit_protocol/cockpit_protocol.dart'
    show
        CockpitPerformanceEvent,
        CockpitPerformanceFrame,
        CockpitPerformanceMode,
        CockpitPerformancePhaseSummary,
        CockpitPerformanceReport,
        CockpitPerformanceSummary,
        CockpitPerformanceMemoryReport,
        CockpitPerformanceMemorySample,
        CockpitPerformanceMemorySummary;
export 'package:cockpit_protocol/cockpit_protocol.dart'
    show CockpitPerformancePluginStats, CockpitPerformanceArchiveInfo;

typedef CockpitPerformanceFrameListener =
    void Function(CockpitPerformanceFrame frame);

/// Collects engine-reported frame timings for an explicit, bounded capture.
///
/// The collector is dormant until [start] is called. It never samples the
/// widget tree and does not enable VM timeline streams by itself. This keeps
/// the normal application path cheap; callers that need VM events should use
/// [flutter_cockpit_test]'s profiling API, which owns the official integration
/// test VM-service trace lifecycle.
final class CockpitPerformanceCollector {
  CockpitPerformanceCollector({
    this.mode = CockpitPerformanceMode.light,
    this.maxFrames = 100000,
    int? frameBudgetUs,
    DateTime Function()? now,
    String? platform,
    String? buildMode,
  }) : _frameBudgetUs = frameBudgetUs ?? _defaultFrameBudgetUs(),
       _now = now ?? (() => DateTime.now().toUtc()),
       platform = platform ?? (kIsWeb ? 'web' : defaultTargetPlatform.name),
       buildMode = buildMode ?? _defaultBuildMode() {
    if (maxFrames < 1 || maxFrames > 1000000) {
      throw ArgumentError.value(
        maxFrames,
        'maxFrames',
        'Must be between 1 and 1000000.',
      );
    }
    if (_frameBudgetUs <= 0) {
      throw ArgumentError.value(
        _frameBudgetUs,
        'frameBudgetUs',
        'Must be positive.',
      );
    }
    if (this.platform.trim().isEmpty) {
      throw ArgumentError.value(
        this.platform,
        'platform',
        'Must not be blank.',
      );
    }
    if (!_performanceBuildModes.contains(this.buildMode)) {
      throw ArgumentError.value(
        this.buildMode,
        'buildMode',
        'Must be debug, profile, or release.',
      );
    }
  }

  final CockpitPerformanceMode mode;
  final int maxFrames;
  final int _frameBudgetUs;
  final DateTime Function() _now;
  final String platform;
  final String buildMode;
  final List<CockpitPerformanceFrame> _frames = <CockpitPerformanceFrame>[];
  final Set<CockpitPerformanceFrameListener> _frameListeners =
      <CockpitPerformanceFrameListener>{};
  TimingsCallback? _timingsCallback;
  Stopwatch? _clock;
  DateTime? _startedAt;
  int _seenFrames = 0;
  int _invalidFrames = 0;
  bool _running = false;
  bool _windowEnded = false;
  CockpitPerformanceMode? _activeMode;
  Duration? _elapsed;
  DateTime? _finishedAt;

  bool get isRunning => _running;
  DateTime? get startedAt => _startedAt;
  int get frameBudgetUs => _frameBudgetUs;
  int get frameCount => _seenFrames;
  int get invalidFrameCount => _invalidFrames;

  /// Registers a low-overhead observer for every valid frame, including
  /// frames that are outside the bounded in-memory retention window. The
  /// listener is intended for append-only archives and must not throw or do
  /// expensive synchronous work; failures are isolated from frame capture.
  void addFrameListener(CockpitPerformanceFrameListener listener) {
    _frameListeners.add(listener);
  }

  /// Removes a previously registered frame observer.
  void removeFrameListener(CockpitPerformanceFrameListener listener) {
    _frameListeners.remove(listener);
  }

  /// Starts one capture. A collector owns one capture at a time so that
  /// reports cannot accidentally combine unrelated actions.
  void start({CockpitPerformanceMode? mode}) {
    if (_running) {
      throw StateError('A performance capture is already running.');
    }
    _frames.clear();
    _seenFrames = 0;
    _invalidFrames = 0;
    _activeMode = mode ?? this.mode;
    _startedAt = _now().toUtc();
    _clock = Stopwatch()..start();
    _elapsed = null;
    _finishedAt = null;
    _windowEnded = false;
    _timingsCallback = _recordTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
    _running = true;
  }

  /// Records a single engine timing. This is public for deterministic host or
  /// test adapters that already receive [FrameTiming] from Flutter.
  void record(FrameTiming timing) {
    if (!_running || _windowEnded) return;
    final frame = _frame(timing, index: _seenFrames);
    if (frame == null) {
      _invalidFrames += 1;
      return;
    }
    _seenFrames += 1;
    if (_frames.length < maxFrames) {
      _frames.add(frame);
    }
    for (final listener in List<CockpitPerformanceFrameListener>.of(
      _frameListeners,
    )) {
      try {
        listener(frame);
      } on Object {
        // A diagnostic sink must never change frame timing collection.
      }
    }
  }

  /// Freezes the measured interval at the end of the user action.
  /// Subsequent teardown and report-export work cannot affect frame timing or
  /// elapsed duration. [stop] still owns report construction and cleanup.
  void endWindow() {
    if (!_running || _windowEnded) return;
    final clock = _clock;
    if (clock != null) {
      clock.stop();
      _elapsed = clock.elapsed;
    }
    final started = _startedAt;
    if (started != null && _elapsed != null) {
      _finishedAt = started.add(_elapsed!);
    }
    final callback = _timingsCallback;
    if (callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
      _timingsCallback = null;
    }
    _windowEnded = true;
  }

  /// Stops the capture and creates a self-consistent report.
  ///
  /// [events] must contain raw, bounded VM timeline events when supplied. The
  /// collector does not reinterpret timestamps or durations; preserving the
  /// source values is essential for accurate cross-tool comparison.
  CockpitPerformanceReport stop({
    Iterable<CockpitPerformanceEvent> events =
        const <CockpitPerformanceEvent>[],
    String? timelineSource,
    String? stepId,
    int? newGenGcCount,
    int? oldGenGcCount,
    CockpitPerformanceMemoryReport? memory,
    CockpitDevToolsProfile? devTools,
    Iterable<CockpitPerformancePluginStats> plugins =
        const <CockpitPerformancePluginStats>[],
    int droppedEvents = 0,
    int invalidEvents = 0,
  }) {
    if (!_running) {
      throw StateError('No performance capture is running.');
    }
    final started = _startedAt!;
    endWindow();
    final elapsed = _elapsed ?? Duration.zero;
    final finished = _finishedAt ?? started.add(elapsed);
    final activeMode = _activeMode ?? mode;
    try {
      final boundedEvents = events.toList(growable: false);
      if (droppedEvents < 0 || invalidEvents < 0) {
        throw ArgumentError('Event drop counts must not be negative.');
      }
      if (boundedEvents.length > 200000) {
        throw ArgumentError.value(
          boundedEvents.length,
          'events',
          'A performance report cannot contain more than 200000 events.',
        );
      }
      final summary = CockpitPerformanceSummary.fromFrames(
        _frames,
        frameBudgetUs: _frameBudgetUs,
        newGenGcCount: newGenGcCount,
        oldGenGcCount: oldGenGcCount,
      );
      return CockpitPerformanceReport(
        startedAt: started,
        finishedAt: finished,
        durationUs: elapsed.inMicroseconds,
        durationMs: elapsed.inMilliseconds,
        platform: platform,
        buildMode: buildMode,
        mode: activeMode,
        summary: summary,
        frames: _frames,
        events: boundedEvents,
        droppedFrames: _seenFrames - _frames.length,
        droppedEvents: droppedEvents,
        invalidFrames: _invalidFrames,
        invalidEvents: invalidEvents,
        memory: memory,
        devTools: devTools,
        plugins: plugins,
        timelineSource: timelineSource,
        stepId: stepId,
      );
    } finally {
      _detach();
    }
  }

  /// Captures an action and always detaches the timings callback.
  Future<CockpitPerformanceReport> capture(
    Future<void> Function() action, {
    Iterable<CockpitPerformanceEvent> events =
        const <CockpitPerformanceEvent>[],
    String? timelineSource,
    String? stepId,
    int? newGenGcCount,
    int? oldGenGcCount,
    CockpitPerformanceMemoryReport? memory,
    CockpitDevToolsProfile? devTools,
    Duration? timeout,
  }) async {
    start();
    CockpitPerformanceReport? report;
    try {
      final future = Future<void>.sync(action);
      if (timeout == null) {
        await future;
      } else {
        await _awaitCaptureAction(future, timeout);
      }
    } finally {
      if (_running) {
        report = stop(
          events: events,
          timelineSource: timelineSource,
          stepId: stepId,
          newGenGcCount: newGenGcCount,
          oldGenGcCount: oldGenGcCount,
          droppedEvents: 0,
          invalidEvents: 0,
          memory: memory,
          devTools: devTools,
        );
      }
    }
    return report!;
  }

  /// Detaches the timing callback. A disposed collector can be reused.
  void dispose() {
    if (_running) _detach();
    _frames.clear();
    _frameListeners.clear();
  }

  void _recordTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      record(timing);
    }
  }

  CockpitPerformanceFrame? _frame(FrameTiming timing, {required int index}) {
    final buildUs = timing.buildDuration.inMicroseconds;
    final rasterUs = timing.rasterDuration.inMicroseconds;
    final vsyncUs = timing.vsyncOverhead.inMicroseconds;
    final totalUs = timing.totalSpan.inMicroseconds;
    final wallTimeUs = timing.timestampInMicroseconds(
      FramePhase.rasterFinishWallTime,
    );
    final values = <int>[
      buildUs,
      rasterUs,
      vsyncUs,
      totalUs,
      timing.layerCacheCount,
      timing.layerCacheBytes,
      timing.pictureCacheCount,
      timing.pictureCacheBytes,
    ];
    if (values.any((value) => value < 0)) return null;
    final frameNumber = timing.frameNumber;
    final timestampUs = timing.timestampInMicroseconds(FramePhase.vsyncStart);
    final buildStartUs = timing.timestampInMicroseconds(FramePhase.buildStart);
    final buildFinishUs = timing.timestampInMicroseconds(
      FramePhase.buildFinish,
    );
    final rasterStartUs = timing.timestampInMicroseconds(
      FramePhase.rasterStart,
    );
    final rasterFinishUs = timing.timestampInMicroseconds(
      FramePhase.rasterFinish,
    );
    final phaseTimestamps = <int>[
      timestampUs,
      buildStartUs,
      buildFinishUs,
      rasterStartUs,
      rasterFinishUs,
    ];
    if (phaseTimestamps[0] > phaseTimestamps[1] ||
        phaseTimestamps[1] > phaseTimestamps[2] ||
        phaseTimestamps[2] > phaseTimestamps[3] ||
        phaseTimestamps[3] > phaseTimestamps[4]) {
      return null;
    }
    return CockpitPerformanceFrame(
      index: index,
      timestampUs: timestampUs,
      wallTimeUs: wallTimeUs,
      buildUs: buildUs,
      rasterUs: rasterUs,
      vsyncUs: vsyncUs,
      totalUs: totalUs,
      layerCount: timing.layerCacheCount,
      layerBytes: timing.layerCacheBytes,
      pictureCount: timing.pictureCacheCount,
      pictureBytes: timing.pictureCacheBytes,
      frameNumber: frameNumber < 0 ? null : frameNumber,
      buildStartUs: buildStartUs,
      buildFinishUs: buildFinishUs,
      rasterStartUs: rasterStartUs,
      rasterFinishUs: rasterFinishUs,
    );
  }

  void _detach() {
    final callback = _timingsCallback;
    if (callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
    }
    _timingsCallback = null;
    _clock = null;
    _activeMode = null;
    _running = false;
    _windowEnded = false;
    _elapsed = null;
    _finishedAt = null;
  }
}

const Duration _captureTimeoutGrace = Duration(seconds: 2);

/// Applies a hard public timeout to an uncancellable Dart action. The action
/// gets a small cleanup grace period, but a hung future can never keep the
/// collector (and therefore the caller) blocked forever. A terminal listener
/// absorbs a late failure after the timeout has been reported.
Future<void> _awaitCaptureAction(Future<void> action, Duration timeout) async {
  try {
    await action.timeout(timeout);
  } on TimeoutException catch (error, stack) {
    try {
      await action.timeout(_captureTimeoutGrace);
    } on Object {
      unawaited(
        action.then<void>(
          (_) {},
          onError: (Object lateError, StackTrace lateStack) {},
        ),
      );
    }
    Error.throwWithStackTrace(error, stack);
  }
}

int _defaultFrameBudgetUs() {
  final view = PlatformDispatcher.instance.implicitView;
  final refreshRate = view?.display.refreshRate;
  if (refreshRate != null && refreshRate.isFinite && refreshRate > 0) {
    final budget = (1000000 / refreshRate).round();
    if (budget > 0) return budget;
  }
  // A 60Hz display has a 16.667ms frame interval. Keep the exact rounded
  // interval rather than truncating it to 16ms, which would over-report jank.
  return (1000000 / 60).round();
}

String _defaultBuildMode() {
  if (kDebugMode) return 'debug';
  if (kProfileMode) return 'profile';
  return 'release';
}

const Set<String> _performanceBuildModes = <String>{
  'debug',
  'profile',
  'release',
};
