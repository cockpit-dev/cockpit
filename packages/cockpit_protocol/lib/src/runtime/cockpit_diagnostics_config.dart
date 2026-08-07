final class CockpitDiagnosticsConfig {
  /// Creates a CockpitDiagnosticsConfig.
  const CockpitDiagnosticsConfig({
    this.enableRebuildTracking = false,
    this.maxTrackedRebuildEntries = 120,
    this.enableTapFeedback = false,
  });

  final bool enableRebuildTracking;
  final int maxTrackedRebuildEntries;
  final bool enableTapFeedback;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitDiagnosticsConfig &&
            other.enableRebuildTracking == enableRebuildTracking &&
            other.maxTrackedRebuildEntries == maxTrackedRebuildEntries &&
            other.enableTapFeedback == enableTapFeedback;
  }

  @override
  int get hashCode => Object.hash(
    enableRebuildTracking,
    maxTrackedRebuildEntries,
    enableTapFeedback,
  );
}
