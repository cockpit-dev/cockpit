import 'package:cockpit_protocol/cockpit_protocol.dart';

/// Captures low-overhead process RSS samples for one performance interval.
abstract interface class CockpitPerformanceMemorySampler {
  void start();

  CockpitPerformanceMemoryReport? stop();
}
