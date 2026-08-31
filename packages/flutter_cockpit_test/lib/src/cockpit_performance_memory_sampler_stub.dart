import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_performance_memory_sampler_contract.dart';

final class _UnavailableMemorySampler
    implements CockpitPerformanceMemorySampler {
  @override
  void start() {}

  @override
  CockpitPerformanceMemoryReport? stop() => null;
}

CockpitPerformanceMemorySampler createCockpitPerformanceMemorySampler({
  required Duration interval,
}) => _UnavailableMemorySampler();
