import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_performance_memory_sampler_contract.dart';

final class _ProcessMemorySampler implements CockpitPerformanceMemorySampler {
  _ProcessMemorySampler(this.interval, this.onSample);

  static const _maxSamples = 10000;

  final Duration interval;
  final void Function(CockpitPerformanceMemorySample sample)? onSample;
  final List<CockpitPerformanceMemorySample> _samples =
      <CockpitPerformanceMemorySample>[];
  Stopwatch? _clock;
  Timer? _timer;
  var _dropped = 0;
  var _disabled = false;

  @override
  void start() {
    _samples.clear();
    _dropped = 0;
    _disabled = false;
    _clock = Stopwatch()..start();
    _sample();
    if (!_disabled) {
      _timer = Timer.periodic(interval, (_) => _sample());
    }
  }

  @override
  CockpitPerformanceMemoryReport? stop() {
    _timer?.cancel();
    _timer = null;
    if (!_disabled) _sample();
    _clock?.stop();
    _clock = null;
    if (_samples.isEmpty) return null;
    return CockpitPerformanceMemoryReport(
      source: 'processInfo',
      intervalMs: interval.inMilliseconds,
      samples: _samples,
      droppedSamples: _dropped,
    );
  }

  void _sample() {
    final clock = _clock;
    if (_disabled || clock == null) return;
    try {
      final rss = ProcessInfo.currentRss;
      final peak = ProcessInfo.maxRss;
      if (rss < 0 || peak < rss) {
        _disabled = true;
        _timer?.cancel();
        _timer = null;
        return;
      }
      final sample = CockpitPerformanceMemorySample(
        timestampUs: clock.elapsed.inMicroseconds,
        rssBytes: rss,
        processPeakBytes: peak,
      );
      if (_samples.length >= _maxSamples) {
        _dropped += 1;
      } else {
        _samples.add(sample);
      }
      try {
        onSample?.call(sample);
      } on Object {
        // Archive failures must never affect the measured action.
      }
    } on Object {
      _disabled = true;
      _timer?.cancel();
      _timer = null;
    }
  }
}

CockpitPerformanceMemorySampler createCockpitPerformanceMemorySampler({
  required Duration interval,
  void Function(CockpitPerformanceMemorySample sample)? onSample,
}) => _ProcessMemorySampler(interval, onSample);
