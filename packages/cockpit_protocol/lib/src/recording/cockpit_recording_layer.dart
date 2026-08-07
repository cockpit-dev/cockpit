enum CockpitRecordingLayer {
  flutter('flutter'),
  appWindow('app-window'),
  hostScreen('host-screen'),
  system('system');

  /// Creates a CockpitRecordingLayer.
  const CockpitRecordingLayer(this.jsonValue);

  final String jsonValue;

  int get coverageRank {
    return switch (this) {
      CockpitRecordingLayer.flutter => 0,
      CockpitRecordingLayer.appWindow => 1,
      CockpitRecordingLayer.hostScreen => 2,
      CockpitRecordingLayer.system => 3,
    };
  }

  static CockpitRecordingLayer fromJson(Object? json) {
    return values.firstWhere(
      (candidate) => candidate.jsonValue == json || candidate.name == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported recording layer.',
      ),
    );
  }
}
