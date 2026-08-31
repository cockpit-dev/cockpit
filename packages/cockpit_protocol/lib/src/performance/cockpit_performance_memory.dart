import 'package:collection/collection.dart';

/// One process-memory sample captured during a performance interval.
///
/// [timestampUs] is relative to the beginning of the capture. RSS values come
/// directly from the platform process API and include Dart, engine, native,
/// and mapped process memory according to that platform's accounting rules.
final class CockpitPerformanceMemorySample {
  const CockpitPerformanceMemorySample({
    required this.timestampUs,
    required this.rssBytes,
    required this.processPeakBytes,
  });

  final int timestampUs;
  final int rssBytes;
  final int processPeakBytes;

  bool get isValid =>
      timestampUs >= 0 && rssBytes >= 0 && processPeakBytes >= rssBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    't': timestampUs,
    'rss': rssBytes,
    'peak': processPeakBytes,
  };

  factory CockpitPerformanceMemorySample.fromJson(Object? value) {
    final json = _object(value, r'$.memory.sample');
    return CockpitPerformanceMemorySample(
      timestampUs: _nonNegativeInt(json['t'], r'$.memory.sample.t'),
      rssBytes: _nonNegativeInt(json['rss'], r'$.memory.sample.rss'),
      processPeakBytes: _nonNegativeInt(json['peak'], r'$.memory.sample.peak'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CockpitPerformanceMemorySample &&
          other.timestampUs == timestampUs &&
          other.rssBytes == rssBytes &&
          other.processPeakBytes == processPeakBytes;

  @override
  int get hashCode => Object.hash(timestampUs, rssBytes, processPeakBytes);
}

/// Aggregate memory pressure for the retained samples in one capture.
final class CockpitPerformanceMemorySummary {
  const CockpitPerformanceMemorySummary({
    required this.sampleCount,
    required this.startRssBytes,
    required this.endRssBytes,
    required this.minRssBytes,
    required this.maxRssBytes,
    required this.averageRssBytes,
    required this.processPeakBytes,
    required this.deltaRssBytes,
  });

  final int sampleCount;
  final int startRssBytes;
  final int endRssBytes;
  final int minRssBytes;
  final int maxRssBytes;
  final int averageRssBytes;
  final int processPeakBytes;
  final int deltaRssBytes;

  bool get isValid =>
      sampleCount > 0 &&
      startRssBytes >= 0 &&
      endRssBytes >= 0 &&
      minRssBytes >= 0 &&
      minRssBytes <= startRssBytes &&
      minRssBytes <= endRssBytes &&
      maxRssBytes >= startRssBytes &&
      maxRssBytes >= endRssBytes &&
      averageRssBytes >= minRssBytes &&
      averageRssBytes <= maxRssBytes &&
      processPeakBytes >= maxRssBytes &&
      deltaRssBytes == endRssBytes - startRssBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'n': sampleCount,
    'start': startRssBytes,
    'end': endRssBytes,
    'min': minRssBytes,
    'max': maxRssBytes,
    'avg': averageRssBytes,
    'peak': processPeakBytes,
    'delta': deltaRssBytes,
  };

  factory CockpitPerformanceMemorySummary.fromJson(Object? value) {
    final json = _object(value, r'$.memory.summary');
    final summary = CockpitPerformanceMemorySummary(
      sampleCount: _positiveInt(json['n'], r'$.memory.summary.n'),
      startRssBytes: _nonNegativeInt(json['start'], r'$.memory.summary.start'),
      endRssBytes: _nonNegativeInt(json['end'], r'$.memory.summary.end'),
      minRssBytes: _nonNegativeInt(json['min'], r'$.memory.summary.min'),
      maxRssBytes: _nonNegativeInt(json['max'], r'$.memory.summary.max'),
      averageRssBytes: _nonNegativeInt(json['avg'], r'$.memory.summary.avg'),
      processPeakBytes: _nonNegativeInt(json['peak'], r'$.memory.summary.peak'),
      deltaRssBytes: _int(json['delta'], r'$.memory.summary.delta'),
    );
    if (!summary.isValid) {
      throw const FormatException('Memory summary is inconsistent.');
    }
    return summary;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CockpitPerformanceMemorySummary &&
          other.sampleCount == sampleCount &&
          other.startRssBytes == startRssBytes &&
          other.endRssBytes == endRssBytes &&
          other.minRssBytes == minRssBytes &&
          other.maxRssBytes == maxRssBytes &&
          other.averageRssBytes == averageRssBytes &&
          other.processPeakBytes == processPeakBytes &&
          other.deltaRssBytes == deltaRssBytes;

  @override
  int get hashCode => Object.hash(
    sampleCount,
    startRssBytes,
    endRssBytes,
    minRssBytes,
    maxRssBytes,
    averageRssBytes,
    processPeakBytes,
    deltaRssBytes,
  );
}

/// Bounded process-memory timeline captured alongside frame timings.
final class CockpitPerformanceMemoryReport {
  factory CockpitPerformanceMemoryReport({
    String source = 'process',
    required int intervalMs,
    required Iterable<CockpitPerformanceMemorySample> samples,
    int droppedSamples = 0,
  }) {
    final retained = List<CockpitPerformanceMemorySample>.unmodifiable(samples);
    return CockpitPerformanceMemoryReport._(
      source: source,
      intervalMs: intervalMs,
      samples: retained,
      droppedSamples: droppedSamples,
      summary: _summarize(retained),
    );
  }

  CockpitPerformanceMemoryReport._({
    required this.source,
    required this.intervalMs,
    required this.samples,
    required this.droppedSamples,
    required this.summary,
  }) {
    if (source.trim().isEmpty || intervalMs < 1 || droppedSamples < 0) {
      throw const FormatException('Memory report metadata is invalid.');
    }
    if (samples.isEmpty || samples.length > 10000) {
      throw const FormatException('Memory report sample count is invalid.');
    }
    if (samples.any((sample) => !sample.isValid)) {
      throw const FormatException('Memory report contains an invalid sample.');
    }
    for (var index = 1; index < samples.length; index += 1) {
      if (samples[index].timestampUs < samples[index - 1].timestampUs) {
        throw const FormatException('Memory samples are not ordered.');
      }
    }
  }

  final String source;
  final int intervalMs;
  final List<CockpitPerformanceMemorySample> samples;
  final int droppedSamples;
  final CockpitPerformanceMemorySummary summary;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'intervalMs': intervalMs,
    'summary': summary.toJson(),
    'samples': samples.map((sample) => sample.toJson()).toList(growable: false),
    if (droppedSamples > 0) 'dropped': droppedSamples,
  };

  factory CockpitPerformanceMemoryReport.fromJson(Object? value) {
    final json = _object(value, r'$.memory');
    final rawSamples = json['samples'];
    if (rawSamples is! List<Object?>) {
      throw const FormatException(r'$.memory.samples must be an array.');
    }
    final report = CockpitPerformanceMemoryReport(
      source: _string(json['source'], r'$.memory.source'),
      intervalMs: _positiveInt(json['intervalMs'], r'$.memory.intervalMs'),
      samples: rawSamples.map(CockpitPerformanceMemorySample.fromJson),
      droppedSamples: json['dropped'] == null
          ? 0
          : _nonNegativeInt(json['dropped'], r'$.memory.dropped'),
    );
    final encodedSummary = CockpitPerformanceMemorySummary.fromJson(
      json['summary'],
    );
    if (encodedSummary != report.summary) {
      throw const FormatException('Memory report summary is inconsistent.');
    }
    return report;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CockpitPerformanceMemoryReport &&
          other.source == source &&
          other.intervalMs == intervalMs &&
          other.droppedSamples == droppedSamples &&
          other.summary == summary &&
          const ListEquality<CockpitPerformanceMemorySample>().equals(
            other.samples,
            samples,
          );

  @override
  int get hashCode => Object.hash(
    source,
    intervalMs,
    droppedSamples,
    summary,
    const ListEquality<CockpitPerformanceMemorySample>().hash(samples),
  );
}

CockpitPerformanceMemorySummary _summarize(
  Iterable<CockpitPerformanceMemorySample> source,
) {
  final samples = source.toList(growable: false);
  if (samples.isEmpty) {
    throw const FormatException('Memory report requires at least one sample.');
  }
  var minRss = samples.first.rssBytes;
  var maxRss = samples.first.rssBytes;
  var processPeak = samples.first.processPeakBytes;
  var total = 0;
  for (final sample in samples) {
    minRss = sample.rssBytes < minRss ? sample.rssBytes : minRss;
    maxRss = sample.rssBytes > maxRss ? sample.rssBytes : maxRss;
    processPeak = sample.processPeakBytes > processPeak
        ? sample.processPeakBytes
        : processPeak;
    total += sample.rssBytes;
  }
  return CockpitPerformanceMemorySummary(
    sampleCount: samples.length,
    startRssBytes: samples.first.rssBytes,
    endRssBytes: samples.last.rssBytes,
    minRssBytes: minRss,
    maxRssBytes: maxRss,
    averageRssBytes: total ~/ samples.length,
    processPeakBytes: processPeak,
    deltaRssBytes: samples.last.rssBytes - samples.first.rssBytes,
  );
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is Map<Object?, Object?>) return Map<String, Object?>.from(value);
  throw FormatException('$path must be an object.');
}

String _string(Object? value, String path) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$path must be a non-empty string.');
}

int _int(Object? value, String path) {
  if (value is int) return value;
  throw FormatException('$path must be an integer.');
}

int _nonNegativeInt(Object? value, String path) {
  final result = _int(value, path);
  if (result >= 0) return result;
  throw FormatException('$path must be non-negative.');
}

int _positiveInt(Object? value, String path) {
  final result = _int(value, path);
  if (result > 0) return result;
  throw FormatException('$path must be positive.');
}
