enum CockpitRecordingPurpose {
  acceptance,
  repro;

  static CockpitRecordingPurpose fromJson(Object? json) {
    return values.firstWhere(
      (purpose) => purpose.name == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported recording purpose.',
      ),
    );
  }
}
