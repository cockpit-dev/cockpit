import 'package:collection/collection.dart';

/// The amount of performance data retained while a collector is active.
enum CockpitPerformanceMode {
  light('light'),
  profile('profile');

  const CockpitPerformanceMode(this.jsonValue);

  final String jsonValue;

  static CockpitPerformanceMode fromJson(Object? value) {
    return values.firstWhere(
      (mode) => mode.jsonValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unsupported performance mode.',
      ),
    );
  }
}

/// One frame reported by Flutter's frame timing pipeline.
///
/// Durations and timestamps are expressed in microseconds. Compact JSON keys
/// keep large reports inexpensive to transport while the Dart properties stay
/// descriptive for callers.
final class CockpitPerformanceFrame {
  const CockpitPerformanceFrame({
    required this.index,
    required this.timestampUs,
    required this.buildUs,
    required this.rasterUs,
    required this.vsyncUs,
    required this.totalUs,
    required this.layerCount,
    required this.layerBytes,
    required this.pictureCount,
    required this.pictureBytes,
    this.frameNumber,
  });

  final int index;
  final int timestampUs;
  final int buildUs;
  final int rasterUs;
  final int vsyncUs;
  final int totalUs;
  final int layerCount;
  final int layerBytes;
  final int pictureCount;
  final int pictureBytes;
  final int? frameNumber;

  bool get isValid =>
      index >= 0 &&
      buildUs >= 0 &&
      rasterUs >= 0 &&
      vsyncUs >= 0 &&
      totalUs >= 0 &&
      layerCount >= 0 &&
      layerBytes >= 0 &&
      pictureCount >= 0 &&
      pictureBytes >= 0 &&
      (frameNumber == null || frameNumber! >= 0);

  Map<String, Object?> toJson() => <String, Object?>{
    'i': index,
    't': timestampUs,
    'b': buildUs,
    'r': rasterUs,
    'v': vsyncUs,
    's': totalUs,
    'l': layerCount,
    'lb': layerBytes,
    'p': pictureCount,
    'pb': pictureBytes,
    if (frameNumber != null) 'n': frameNumber,
  };

  factory CockpitPerformanceFrame.fromJson(Object? value) {
    final json = _object(value, r'$.frame');
    return CockpitPerformanceFrame(
      index: _nonNegativeInt(json['i'], r'$.frame.i'),
      // FrameTiming timestamps use an engine-defined epoch. They are not
      // DateTime values and may be negative in synthetic/test data, so never
      // apply a non-negative constraint here.
      timestampUs: _anyInt(json['t'], r'$.frame.t'),
      buildUs: _nonNegativeInt(json['b'], r'$.frame.b'),
      rasterUs: _nonNegativeInt(json['r'], r'$.frame.r'),
      vsyncUs: _nonNegativeInt(json['v'], r'$.frame.v'),
      totalUs: _nonNegativeInt(json['s'], r'$.frame.s'),
      layerCount: _nonNegativeInt(json['l'], r'$.frame.l'),
      layerBytes: _nonNegativeInt(json['lb'], r'$.frame.lb'),
      pictureCount: _nonNegativeInt(json['p'], r'$.frame.p'),
      pictureBytes: _nonNegativeInt(json['pb'], r'$.frame.pb'),
      frameNumber: json['n'] == null
          ? null
          : _nonNegativeInt(json['n'], r'$.frame.n'),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitPerformanceFrame &&
            other.index == index &&
            other.timestampUs == timestampUs &&
            other.buildUs == buildUs &&
            other.rasterUs == rasterUs &&
            other.vsyncUs == vsyncUs &&
            other.totalUs == totalUs &&
            other.layerCount == layerCount &&
            other.layerBytes == layerBytes &&
            other.pictureCount == pictureCount &&
            other.pictureBytes == pictureBytes &&
            other.frameNumber == frameNumber;
  }

  @override
  int get hashCode => Object.hash(
    index,
    timestampUs,
    buildUs,
    rasterUs,
    vsyncUs,
    totalUs,
    layerCount,
    layerBytes,
    pictureCount,
    pictureBytes,
    frameNumber,
  );
}

/// A bounded VM timeline event retained for the exported performance report.
final class CockpitPerformanceEvent {
  const CockpitPerformanceEvent({
    required this.name,
    required this.category,
    required this.timestampUs,
    required this.durationUs,
    this.args = const <String, Object?>{},
    this.phase,
  });

  final String name;
  final String category;
  final int timestampUs;
  final int durationUs;
  final Map<String, Object?> args;
  final String? phase;

  bool get isValid =>
      name.isNotEmpty &&
      category.isNotEmpty &&
      durationUs >= 0 &&
      (phase == null || phase!.isNotEmpty) &&
      _isJsonObject(args);

  Map<String, Object?> toJson() => <String, Object?>{
    'n': name,
    'c': category,
    't': timestampUs,
    if (durationUs > 0) 'd': durationUs,
    if (phase != null) 'p': phase,
    if (args.isNotEmpty) 'a': args,
  };

  factory CockpitPerformanceEvent.fromJson(Object? value) {
    final json = _object(value, r'$.event');
    final args = json['a'];
    return CockpitPerformanceEvent(
      name: _string(json['n'], r'$.event.n'),
      category: _string(json['c'], r'$.event.c'),
      timestampUs: _anyInt(json['t'], r'$.event.t'),
      durationUs: json['d'] == null
          ? 0
          : _nonNegativeInt(json['d'], r'$.event.d'),
      phase: json['p'] == null ? null : _string(json['p'], r'$.event.p'),
      args: args == null
          ? const <String, Object?>{}
          : Map<String, Object?>.unmodifiable(_object(args, r'$.event.a')),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitPerformanceEvent &&
            other.name == name &&
            other.category == category &&
            other.timestampUs == timestampUs &&
            other.durationUs == durationUs &&
            other.phase == phase &&
            const DeepCollectionEquality().equals(other.args, args);
  }

  @override
  int get hashCode => Object.hash(
    name,
    category,
    timestampUs,
    durationUs,
    phase,
    const DeepCollectionEquality().hash(args),
  );
}

/// Percentile and budget information for one frame phase.
final class CockpitPerformancePhaseSummary {
  const CockpitPerformancePhaseSummary({
    required this.averageUs,
    required this.p50Us,
    required this.p90Us,
    required this.p99Us,
    required this.worstUs,
    required this.budgetUs,
    required this.missedBudget,
  });

  final int averageUs;
  final int p50Us;
  final int p90Us;
  final int p99Us;
  final int worstUs;
  final int budgetUs;
  final int missedBudget;

  bool get isValid =>
      averageUs >= 0 &&
      p50Us >= 0 &&
      p90Us >= 0 &&
      p99Us >= 0 &&
      worstUs >= 0 &&
      budgetUs > 0 &&
      missedBudget >= 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'avg': averageUs,
    'p50': p50Us,
    'p90': p90Us,
    'p99': p99Us,
    'max': worstUs,
    'bud': budgetUs,
    'miss': missedBudget,
  };

  factory CockpitPerformancePhaseSummary.fromJson(Object? value) {
    final json = _object(value, r'$.phase');
    return CockpitPerformancePhaseSummary(
      averageUs: _nonNegativeInt(json['avg'], r'$.phase.avg'),
      p50Us: _nonNegativeInt(json['p50'], r'$.phase.p50'),
      p90Us: _nonNegativeInt(json['p90'], r'$.phase.p90'),
      p99Us: _nonNegativeInt(json['p99'], r'$.phase.p99'),
      worstUs: _nonNegativeInt(json['max'], r'$.phase.max'),
      budgetUs: _positiveInt(json['bud'], r'$.phase.bud'),
      missedBudget: _nonNegativeInt(json['miss'], r'$.phase.miss'),
    );
  }
}

/// Compact aggregate performance metrics suitable for normal AI output.
final class CockpitPerformanceSummary {
  const CockpitPerformanceSummary({
    required this.frameCount,
    required this.jankCount,
    this.fps,
    required this.build,
    required this.raster,
    required this.vsync,
    required this.layerCacheMax,
    required this.pictureCacheMax,
    this.newGenGcCount,
    this.oldGenGcCount,
  });

  final int frameCount;
  final int jankCount;

  /// The observed frame cadence. It is null when fewer than two valid,
  /// monotonic engine timestamps are available; no wall-clock estimate is
  /// substituted in that case.
  final double? fps;
  final CockpitPerformancePhaseSummary build;
  final CockpitPerformancePhaseSummary raster;
  final CockpitPerformancePhaseSummary vsync;
  final Map<String, int> layerCacheMax;
  final Map<String, int> pictureCacheMax;
  final int? newGenGcCount;
  final int? oldGenGcCount;

  bool get isValid =>
      frameCount >= 0 &&
      jankCount >= 0 &&
      (fps == null || (fps!.isFinite && fps! > 0)) &&
      build.isValid &&
      raster.isValid &&
      vsync.isValid &&
      _validCache(layerCacheMax) &&
      _validCache(pictureCacheMax) &&
      (newGenGcCount == null || newGenGcCount! >= 0) &&
      (oldGenGcCount == null || oldGenGcCount! >= 0);

  CockpitPerformanceSummary copyWith({
    int? frameCount,
    int? jankCount,
    double? fps,
    bool clearFps = false,
    CockpitPerformancePhaseSummary? build,
    CockpitPerformancePhaseSummary? raster,
    CockpitPerformancePhaseSummary? vsync,
    Map<String, int>? layerCacheMax,
    Map<String, int>? pictureCacheMax,
    int? newGenGcCount,
    int? oldGenGcCount,
  }) {
    return CockpitPerformanceSummary(
      frameCount: frameCount ?? this.frameCount,
      jankCount: jankCount ?? this.jankCount,
      fps: clearFps ? null : (fps ?? this.fps),
      build: build ?? this.build,
      raster: raster ?? this.raster,
      vsync: vsync ?? this.vsync,
      layerCacheMax: layerCacheMax ?? this.layerCacheMax,
      pictureCacheMax: pictureCacheMax ?? this.pictureCacheMax,
      newGenGcCount: newGenGcCount ?? this.newGenGcCount,
      oldGenGcCount: oldGenGcCount ?? this.oldGenGcCount,
    );
  }

  factory CockpitPerformanceSummary.fromFrames(
    Iterable<CockpitPerformanceFrame> source, {
    required int frameBudgetUs,
    int? newGenGcCount,
    int? oldGenGcCount,
  }) {
    if (frameBudgetUs <= 0) {
      throw ArgumentError.value(
        frameBudgetUs,
        'frameBudgetUs',
        'Must be positive.',
      );
    }
    final frames = source.toList(growable: false);
    if (frames.any((frame) => !frame.isValid)) {
      throw ArgumentError.value(source, 'source', 'Contains an invalid frame.');
    }
    final build = _phaseSummary(
      frames.map((frame) => frame.buildUs),
      budgetUs: frameBudgetUs,
    );
    final raster = _phaseSummary(
      frames.map((frame) => frame.rasterUs),
      budgetUs: frameBudgetUs,
    );
    final vsync = _phaseSummary(
      frames.map((frame) => frame.vsyncUs),
      // Vsync overhead is part of the total latency, but it is not a frame
      // budget miss by itself. Keep the real budget in the report while
      // reporting no miss for this phase.
      budgetUs: frameBudgetUs,
      countMisses: false,
    );
    var jank = 0;
    for (final frame in frames) {
      if (frame.buildUs > frameBudgetUs || frame.rasterUs > frameBudgetUs) {
        jank += 1;
      }
    }
    final timestamps = <int>[];
    var monotonic = true;
    for (final frame in frames) {
      if (timestamps.isNotEmpty && frame.timestampUs < timestamps.last) {
        monotonic = false;
      }
      timestamps.add(frame.timestampUs);
    }
    double? fps;
    if (monotonic && timestamps.length >= 2) {
      final spanUs = timestamps.last - timestamps.first;
      if (spanUs > 0) {
        fps = (timestamps.length - 1) * 1000000 / spanUs;
      }
    }
    return CockpitPerformanceSummary(
      frameCount: frames.length,
      jankCount: jank,
      fps: fps,
      build: build,
      raster: raster,
      vsync: vsync,
      layerCacheMax: <String, int>{
        'count': _maxOrZero(frames.map((frame) => frame.layerCount)),
        'bytes': _maxOrZero(frames.map((frame) => frame.layerBytes)),
      },
      pictureCacheMax: <String, int>{
        'count': _maxOrZero(frames.map((frame) => frame.pictureCount)),
        'bytes': _maxOrZero(frames.map((frame) => frame.pictureBytes)),
      },
      newGenGcCount: newGenGcCount,
      oldGenGcCount: oldGenGcCount,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'frames': frameCount,
    'jank': jankCount,
    if (fps != null) 'fps': fps,
    'build': build.toJson(),
    'raster': raster.toJson(),
    'vsync': vsync.toJson(),
    'layerCache': layerCacheMax,
    'pictureCache': pictureCacheMax,
    if (newGenGcCount != null || oldGenGcCount != null)
      'gc': <String, Object?>{
        if (newGenGcCount != null) 'new': newGenGcCount,
        if (oldGenGcCount != null) 'old': oldGenGcCount,
      },
  };

  factory CockpitPerformanceSummary.fromJson(Object? value) {
    final json = _object(value, r'$.summary');
    final layer = _object(json['layerCache'], r'$.summary.layerCache');
    final picture = _object(json['pictureCache'], r'$.summary.pictureCache');
    final gc = json['gc'];
    final gcJson = gc == null ? null : _object(gc, r'$.summary.gc');
    return CockpitPerformanceSummary(
      frameCount: _nonNegativeInt(json['frames'], r'$.summary.frames'),
      jankCount: _nonNegativeInt(json['jank'], r'$.summary.jank'),
      fps: json['fps'] == null
          ? null
          : _positiveDouble(json['fps'], r'$.summary.fps'),
      build: CockpitPerformancePhaseSummary.fromJson(json['build']),
      raster: CockpitPerformancePhaseSummary.fromJson(json['raster']),
      vsync: CockpitPerformancePhaseSummary.fromJson(json['vsync']),
      layerCacheMax: <String, int>{
        'count': _nonNegativeInt(layer['count'], r'$.summary.layerCache.count'),
        'bytes': _nonNegativeInt(layer['bytes'], r'$.summary.layerCache.bytes'),
      },
      pictureCacheMax: <String, int>{
        'count': _nonNegativeInt(
          picture['count'],
          r'$.summary.pictureCache.count',
        ),
        'bytes': _nonNegativeInt(
          picture['bytes'],
          r'$.summary.pictureCache.bytes',
        ),
      },
      newGenGcCount: gcJson?['new'] == null
          ? null
          : _nonNegativeInt(gcJson!['new'], r'$.summary.gc.new'),
      oldGenGcCount: gcJson?['old'] == null
          ? null
          : _nonNegativeInt(gcJson!['old'], r'$.summary.gc.old'),
    );
  }
}

/// A complete bounded performance capture.
final class CockpitPerformanceReport {
  CockpitPerformanceReport({
    this.schemaVersion = 'cockpit.performance/v1',
    required this.startedAt,
    required this.finishedAt,
    required this.durationUs,
    required this.durationMs,
    required this.platform,
    required this.mode,
    required this.summary,
    Iterable<CockpitPerformanceFrame> frames =
        const <CockpitPerformanceFrame>[],
    Iterable<CockpitPerformanceEvent> events =
        const <CockpitPerformanceEvent>[],
    this.droppedFrames = 0,
    this.droppedEvents = 0,
    this.invalidFrames = 0,
    this.invalidEvents = 0,
    this.timelineSource,
    this.stepId,
  }) : frames = List<CockpitPerformanceFrame>.unmodifiable(frames),
       events = List<CockpitPerformanceEvent>.unmodifiable(events) {
    if (schemaVersion != 'cockpit.performance/v1') {
      throw const FormatException('Unsupported performance report schema.');
    }
    if (!startedAt.isUtc ||
        !finishedAt.isUtc ||
        finishedAt.isBefore(startedAt)) {
      throw const FormatException('Performance report timestamps are invalid.');
    }
    if (durationUs < 0 ||
        durationMs < 0 ||
        droppedFrames < 0 ||
        droppedEvents < 0 ||
        invalidFrames < 0 ||
        invalidEvents < 0) {
      throw const FormatException('Performance report bounds are invalid.');
    }
    final exactDurationUs = finishedAt.difference(startedAt).inMicroseconds;
    if (durationUs != exactDurationUs || durationMs != durationUs ~/ 1000) {
      throw const FormatException(
        'Performance report duration is inconsistent.',
      );
    }
    if (summary.frameCount != frames.length + droppedFrames) {
      throw const FormatException('Performance frame counts are inconsistent.');
    }
    if (frames.length > 100000 || events.length > 200000) {
      throw const FormatException('Performance report is too large.');
    }
    if (frames.any((frame) => !frame.isValid) ||
        events.any((event) => !event.isValid) ||
        !summary.isValid) {
      throw const FormatException('Performance report contains invalid data.');
    }
  }

  final String schemaVersion;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationUs;
  final int durationMs;
  final String platform;
  final CockpitPerformanceMode mode;
  final CockpitPerformanceSummary summary;
  final List<CockpitPerformanceFrame> frames;
  final List<CockpitPerformanceEvent> events;
  final int droppedFrames;
  final int droppedEvents;
  final int invalidFrames;
  final int invalidEvents;
  final String? timelineSource;
  final String? stepId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schemaVersion,
    'started': startedAt.toIso8601String(),
    'finished': finishedAt.toIso8601String(),
    'durationUs': durationUs,
    'durationMs': durationMs,
    'platform': platform,
    'mode': mode.jsonValue,
    'summary': summary.toJson(),
    if (frames.isNotEmpty)
      'frames': frames.map((frame) => frame.toJson()).toList(),
    if (events.isNotEmpty)
      'events': events.map((event) => event.toJson()).toList(),
    if (droppedFrames > 0 ||
        droppedEvents > 0 ||
        invalidFrames > 0 ||
        invalidEvents > 0)
      'dropped': <String, Object?>{
        if (droppedFrames > 0) 'frames': droppedFrames,
        if (droppedEvents > 0) 'events': droppedEvents,
        if (invalidFrames > 0) 'badFrames': invalidFrames,
        if (invalidEvents > 0) 'badEvents': invalidEvents,
      },
    if (timelineSource != null) 'source': timelineSource,
    if (stepId != null) 'step': stepId,
  };

  factory CockpitPerformanceReport.fromJson(Object? value) {
    final json = _object(value, r'$.performance');
    final dropped = json['dropped'];
    final droppedJson = dropped == null
        ? const <String, Object?>{}
        : _object(dropped, r'$.performance.dropped');
    final rawFrames = json['frames'];
    final rawEvents = json['events'];
    return CockpitPerformanceReport(
      schemaVersion: _string(json['schema'], r'$.performance.schema'),
      startedAt: _date(json['started'], r'$.performance.started'),
      finishedAt: _date(json['finished'], r'$.performance.finished'),
      durationUs: _nonNegativeInt(
        json['durationUs'],
        r'$.performance.durationUs',
      ),
      durationMs: _nonNegativeInt(
        json['durationMs'],
        r'$.performance.durationMs',
      ),
      platform: _string(json['platform'], r'$.performance.platform'),
      mode: CockpitPerformanceMode.fromJson(json['mode']),
      summary: CockpitPerformanceSummary.fromJson(json['summary']),
      frames: rawFrames == null
          ? const <CockpitPerformanceFrame>[]
          : _list(
              rawFrames,
              r'$.performance.frames',
            ).map(CockpitPerformanceFrame.fromJson).toList(growable: false),
      events: rawEvents == null
          ? const <CockpitPerformanceEvent>[]
          : _list(
              rawEvents,
              r'$.performance.events',
            ).map(CockpitPerformanceEvent.fromJson).toList(growable: false),
      droppedFrames: droppedJson['frames'] == null
          ? 0
          : _nonNegativeInt(
              droppedJson['frames'],
              r'$.performance.dropped.frames',
            ),
      droppedEvents: droppedJson['events'] == null
          ? 0
          : _nonNegativeInt(
              droppedJson['events'],
              r'$.performance.dropped.events',
            ),
      invalidFrames: droppedJson['badFrames'] == null
          ? 0
          : _nonNegativeInt(
              droppedJson['badFrames'],
              r'$.performance.dropped.badFrames',
            ),
      invalidEvents: droppedJson['badEvents'] == null
          ? 0
          : _nonNegativeInt(
              droppedJson['badEvents'],
              r'$.performance.dropped.badEvents',
            ),
      timelineSource: json['source'] as String?,
      stepId: json['step'] as String?,
    );
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is Map<Object?, Object?>) return Map<String, Object?>.from(value);
  if (value is Map<String, Object?>) return value;
  throw FormatException('$path must be an object.');
}

List<Object?> _list(Object? value, String path) {
  if (value is List<Object?>) return value;
  throw FormatException('$path must be an array.');
}

String _string(Object? value, String path) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$path must be a non-empty string.');
}

int _anyInt(Object? value, String path) {
  if (value is int) return value;
  throw FormatException('$path must be an integer.');
}

int _nonNegativeInt(Object? value, String path) {
  if (value is int && value >= 0) return value;
  throw FormatException('$path must be a non-negative integer.');
}

int _positiveInt(Object? value, String path) {
  if (value is int && value > 0) return value;
  throw FormatException('$path must be a positive integer.');
}

double _positiveDouble(Object? value, String path) {
  if (value is num && value.isFinite && value > 0) return value.toDouble();
  throw FormatException('$path must be a positive number.');
}

DateTime _date(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be an ISO timestamp.');
  }
  final parsed = DateTime.tryParse(value)?.toUtc();
  if (parsed == null) throw FormatException('$path must be an ISO timestamp.');
  return parsed;
}

CockpitPerformancePhaseSummary _phaseSummary(
  Iterable<int> values, {
  required int budgetUs,
  bool countMisses = true,
}) {
  final data = values.toList(growable: false);
  if (data.isEmpty) {
    return CockpitPerformancePhaseSummary(
      averageUs: 0,
      p50Us: 0,
      p90Us: 0,
      p99Us: 0,
      worstUs: 0,
      budgetUs: budgetUs,
      missedBudget: 0,
    );
  }
  final sorted = List<int>.from(data)..sort();
  int percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  return CockpitPerformancePhaseSummary(
    averageUs: data.reduce((a, b) => a + b) ~/ data.length,
    p50Us: percentile(.50),
    p90Us: percentile(.90),
    p99Us: percentile(.99),
    worstUs: sorted.last,
    budgetUs: budgetUs,
    missedBudget: countMisses
        ? data.where((value) => value > budgetUs).length
        : 0,
  );
}

int _maxOrZero(Iterable<int> values) {
  var max = 0;
  for (final value in values) {
    if (value > max) {
      max = value;
    }
  }
  return max;
}

bool _isJsonObject(Map<String, Object?> value) {
  bool isJson(Object? item) {
    if (item == null || item is String || item is bool) {
      return true;
    }
    if (item is num) return item.isFinite;
    if (item is List) return item.every(isJson);
    if (item is Map) {
      return item.entries.every(
        (entry) => entry.key is String && isJson(entry.value),
      );
    }
    return false;
  }

  return value.entries.every((entry) => isJson(entry.value));
}

bool _validCache(Map<String, int> value) {
  final count = value['count'];
  final bytes = value['bytes'];
  return value.length == 2 &&
      count != null &&
      bytes != null &&
      count >= 0 &&
      bytes >= 0;
}
