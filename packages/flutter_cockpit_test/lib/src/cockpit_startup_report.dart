/// Startup milestones captured by [cockpitTestWidgets].
///
/// The harness starts its clock immediately before the app builder runs. This
/// gives reliable app-build, first-frame, and initial-ready timings without
/// claiming visibility into native process launch time.
final class CockpitStartupReport {
  CockpitStartupReport({
    required this.appMs,
    required this.firstFrameMs,
    required this.readyMs,
    this.source = 'harness',
  }) {
    if (appMs < 0 || firstFrameMs < appMs || readyMs < firstFrameMs) {
      throw ArgumentError('Startup milestones must be ordered and positive.');
    }
    if (source.trim().isEmpty) {
      throw ArgumentError.value(source, 'source', 'Must not be blank.');
    }
  }

  /// Time spent building and mounting the application, in milliseconds.
  final int appMs;

  /// Time from the harness clock start until the first pumped frame, in
  /// milliseconds. This is the closest in-app cold-start signal available to
  /// a Dart integration test.
  final int firstFrameMs;

  /// Time until the configured initial bootstrap pump completes, in
  /// milliseconds.
  final int readyMs;

  /// Origin of the timing clock. `harness` is intentionally explicit because
  /// native process launch time is outside the Dart test isolate.
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'cold',
    'source': source,
    'appMs': appMs,
    'firstMs': firstFrameMs,
    'readyMs': readyMs,
  };

  factory CockpitStartupReport.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Startup report must be an object.');
    }
    final json = Map<String, Object?>.from(value);
    return CockpitStartupReport(
      appMs: _int(json['appMs'], 'appMs'),
      firstFrameMs: _int(json['firstMs'], 'firstMs'),
      readyMs: _int(json['readyMs'], 'readyMs'),
      source: _string(json['source'], 'source'),
    );
  }
}

int _int(Object? value, String name) {
  if (value is int && value >= 0) return value;
  throw FormatException('Startup report $name must be a non-negative integer.');
}

String _string(Object? value, String name) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Startup report $name must be a non-empty string.');
}
