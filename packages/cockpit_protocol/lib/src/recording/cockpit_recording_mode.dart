enum CockpitRecordingMode {
  auto('auto'),
  cheap('cheap'),
  native('native'),
  full('full');

  /// Creates a CockpitRecordingMode.
  const CockpitRecordingMode(this.jsonValue);

  final String jsonValue;

  bool get defaultAllowsFallback {
    return switch (this) {
      CockpitRecordingMode.auto || CockpitRecordingMode.cheap => true,
      CockpitRecordingMode.native || CockpitRecordingMode.full => false,
    };
  }

  static CockpitRecordingMode fromJson(Object? json) {
    return values.firstWhere(
      (candidate) => candidate.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported recording mode.',
      ),
    );
  }
}
