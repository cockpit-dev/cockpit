/// Retention policy used by a live performance archive.
enum CockpitPerformanceArchiveMode {
  /// Stop accepting new records when the writer backlog reaches its bound.
  /// The archive records the number of dropped records and never blocks the
  /// measured application action.
  low('low'),

  /// Keep accepting records and let the file sink apply back-pressure during
  /// flushes. This preserves the event stream at the cost of I/O overhead.
  lossless('lossless');

  const CockpitPerformanceArchiveMode(this.value);

  final String value;
}

/// Limits for a long-running append-only performance archive.
final class CockpitPerformanceArchiveOptions {
  const CockpitPerformanceArchiveOptions({
    // An archive is explicitly selected by the caller, so preserving every
    // record is the least surprising default. The in-memory `profile()` path
    // remains the lightweight choice for short captures. Callers that must
    // protect a slow disk or a constrained runner can opt into `low` and set
    // `maxPendingBytes`.
    this.mode = CockpitPerformanceArchiveMode.lossless,
    this.chunkBytes = 64 * 1024 * 1024,
    this.maxPendingBytes,
    this.flushEvery = const Duration(milliseconds: 250),
    this.pollEvery = const Duration(seconds: 1),
  });

  final CockpitPerformanceArchiveMode mode;
  final int chunkBytes;

  /// Maximum bytes retained in memory while a flush/rotation is in progress.
  ///
  /// In [CockpitPerformanceArchiveMode.low], records beyond this bound are
  /// dropped and counted. In [CockpitPerformanceArchiveMode.lossless], the
  /// bound only controls the in-memory window; excess records spill to a
  /// recoverable JSONL file and are drained before close. `null` uses the
  /// built-in lossless window.
  final int? maxPendingBytes;
  final Duration flushEvery;
  final Duration pollEvery;

  void validate() {
    if (chunkBytes < 1024 * 1024 || chunkBytes > 1024 * 1024 * 1024) {
      throw ArgumentError.value(
        chunkBytes,
        'chunkBytes',
        'Must be between 1 MiB and 1 GiB.',
      );
    }
    if (mode == CockpitPerformanceArchiveMode.low && maxPendingBytes == null) {
      throw ArgumentError.value(
        maxPendingBytes,
        'maxPendingBytes',
        'Must be set when mode is low.',
      );
    }
    if (maxPendingBytes != null &&
        (maxPendingBytes! < 64 * 1024 ||
            maxPendingBytes! > 256 * 1024 * 1024)) {
      throw ArgumentError.value(
        maxPendingBytes,
        'maxPendingBytes',
        'Must be between 64 KiB and 256 MiB.',
      );
    }
    if (flushEvery <= Duration.zero ||
        flushEvery > const Duration(minutes: 1)) {
      throw ArgumentError.value(
        flushEvery,
        'flushEvery',
        'Must be between 1ms and 1min.',
      );
    }
    if (pollEvery < const Duration(milliseconds: 100) ||
        pollEvery > const Duration(minutes: 1)) {
      throw ArgumentError.value(
        pollEvery,
        'pollEvery',
        'Must be between 100ms and 1min.',
      );
    }
  }
}
