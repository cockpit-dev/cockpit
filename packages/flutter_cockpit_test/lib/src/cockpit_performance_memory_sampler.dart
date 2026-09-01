import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_performance_memory_sampler_contract.dart';
import 'cockpit_performance_memory_sampler_stub.dart'
    if (dart.library.io) 'cockpit_performance_memory_sampler_io.dart'
    as platform;

CockpitPerformanceMemorySampler createCockpitPerformanceMemorySampler({
  Duration interval = const Duration(milliseconds: 100),
  void Function(CockpitPerformanceMemorySample sample)? onSample,
}) {
  if (interval <= Duration.zero || interval.inMilliseconds < 1) {
    throw ArgumentError.value(interval, 'interval', 'Must be positive.');
  }
  return platform.createCockpitPerformanceMemorySampler(
    interval: interval,
    onSample: onSample,
  );
}
