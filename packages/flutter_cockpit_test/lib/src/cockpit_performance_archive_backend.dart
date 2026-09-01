import 'package:cockpit_protocol/cockpit_protocol.dart';

abstract interface class CockpitPerformanceArchiveBackend {
  Future<void> open();

  void add(String kind, Map<String, Object?> value);

  Future<void> flush();

  Future<CockpitPerformanceArchiveInfo> close();

  CockpitPerformanceArchiveInfo snapshot();
}
