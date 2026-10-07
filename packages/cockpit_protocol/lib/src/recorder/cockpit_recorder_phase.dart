import '../foundation/cockpit_enum.dart';

enum CockpitRecorderPhase {
  idle,
  recording,
  paused,
  stopped;

  static CockpitRecorderPhase fromJson(
    Object? json, {
    String path = r'$.phase',
  }) => cockpitEnumFromJson(json, values, path);

  bool get isTerminal => this == CockpitRecorderPhase.stopped;
}
