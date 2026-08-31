import 'dart:async';
import 'dart:developer' as developer;

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:vm_service/vm_service.dart';

import 'cockpit_vm_service_connect.dart';

/// Collects the bounded VM data that powers Flutter DevTools' CPU and Memory
/// views. It is deliberately best-effort: a missing profiler must not make a
/// user interaction fail, but the report records the exact unavailable reason.
final class CockpitDevToolsProfiler {
  CockpitDevToolsProfiler({
    this.timeout = const Duration(seconds: 3),
    this.maxCpuSamples = 50000,
    this.maxHeapClasses = 200,
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    if (maxCpuSamples < 1 || maxCpuSamples > 50000) {
      throw ArgumentError.value(
        maxCpuSamples,
        'maxCpuSamples',
        'Must be between 1 and 50000.',
      );
    }
    if (maxHeapClasses < 1 || maxHeapClasses > 1000) {
      throw ArgumentError.value(
        maxHeapClasses,
        'maxHeapClasses',
        'Must be between 1 and 1000.',
      );
    }
  }

  final Duration timeout;
  final int maxCpuSamples;
  final int maxHeapClasses;

  VmService? _service;
  String? _isolateId;
  int? _originUs;
  CockpitHeapPoint? _beforeHeap;
  bool _profilerWasEnabled = false;
  bool _profilerChanged = false;
  bool _requested = false;
  final List<String> _failures = <String>[];

  /// Starts a capture without blocking the action when the VM service is not
  /// available (for example, a web test or a release build).
  Future<void> start({required bool cpu, required bool heap}) async {
    _failures.clear();
    _requested = cpu || heap;
    if (!_requested) return;
    try {
      final info = await developer.Service.getInfo().timeout(timeout);
      final uri = info.serverUri;
      if (uri == null) {
        _recordFailure('vm', StateError('VM service URI is unavailable.'));
        return;
      }
      final service = await connectCockpitVmService(uri).timeout(timeout);
      final vm = await service.getVM().timeout(timeout);
      final isolateId = _mainIsolateId(vm);
      if (isolateId == null) {
        await service.dispose();
        _recordFailure('vm', StateError('No runnable isolate is available.'));
        return;
      }
      _service = service;
      _isolateId = isolateId;
      final now = await service.getVMTimelineMicros().timeout(timeout);
      _originUs = now.timestamp ?? 0;
      if (cpu) {
        try {
          await _prepareCpuProfiler(service, isolateId);
        } on Object catch (error) {
          _recordFailure('cpu', error);
        }
      }
      if (heap) {
        try {
          _beforeHeap = await _readHeapPoint(service, isolateId, reset: true);
        } on Object catch (error) {
          _recordFailure('heap', error);
        }
      }
    } on Object catch (error) {
      await _close();
      _recordFailure('vm', error);
    }
  }

  /// Finishes the capture and returns a truthful, bounded projection.
  Future<CockpitDevToolsProfile?> finish({
    required bool cpu,
    required bool heap,
    Iterable<CockpitPerformanceEvent> events =
        const <CockpitPerformanceEvent>[],
  }) async {
    if (!_requested) {
      final gpu = _gpu(events);
      return gpu == null
          ? null
          : CockpitDevToolsProfile(
              source: 'vmTimeline',
              state: 'available',
              gpu: gpu,
            );
    }
    final service = _service;
    final isolateId = _isolateId;
    if (service == null || isolateId == null || _originUs == null) {
      return CockpitDevToolsProfile(
        source: 'vm',
        state: _hasUnsupportedFailure ? 'unsupported' : 'unavailable',
        reason: _failureReason ?? 'VM service connection was not established.',
        gpu: _gpu(events),
      );
    }

    CockpitCpuProfile? cpuProfile;
    CockpitHeapProfile? heapProfile;
    try {
      int? endUs;
      try {
        final end = await service.getVMTimelineMicros().timeout(timeout);
        endUs = end.timestamp ?? _originUs!;
      } on Object catch (error) {
        _recordFailure('timeline', error);
      }

      if (cpu && (_profilerWasEnabled || _profilerChanged)) {
        if (endUs == null) {
          _recordFailure(
            'cpu',
            StateError('VM timeline end timestamp is unavailable.'),
          );
        } else {
          try {
            final extentUs = (endUs - _originUs!).clamp(
              1,
              24 * 60 * 60 * 1000000,
            );
            final raw = await service
                .getCpuSamples(isolateId, _originUs!, extentUs)
                .timeout(timeout);
            cpuProfile = _cpuProfile(raw);
          } on Object catch (error) {
            _recordFailure('cpu', error);
          }
        }
      } else if (cpu) {
        _recordFailure('cpu', StateError('VM CPU profiler is unavailable.'));
      }

      if (heap && _beforeHeap != null) {
        try {
          final after = await _readHeapPoint(service, isolateId);
          if (after != null) {
            final allocation = await service
                .getAllocationProfile(isolateId)
                .timeout(timeout);
            heapProfile = _heapProfile(_beforeHeap!, after, allocation);
          } else {
            _recordFailure(
              'heap',
              StateError('Heap end sample is unavailable.'),
            );
          }
        } on Object catch (error) {
          _recordFailure('heap', error);
        }
      } else if (heap) {
        _recordFailure('heap', StateError('Heap baseline is unavailable.'));
      }
    } finally {
      await _restoreCpuProfiler();
      await _close();
    }

    final gpu = _gpu(events);
    if (cpuProfile == null && heapProfile == null && _failures.isNotEmpty) {
      return CockpitDevToolsProfile(
        source: 'vm',
        state: 'unavailable',
        reason: _failureReason,
        gpu: gpu,
      );
    }
    return CockpitDevToolsProfile(
      source: 'vm',
      state: cpuProfile != null || heapProfile != null
          ? 'available'
          : 'unavailable',
      reason: _failureReason,
      cpu: cpuProfile,
      heap: heapProfile,
      gpu: gpu,
    );
  }

  bool get _hasUnsupportedFailure => _failures.any(
    (failure) => failure.contains('web') || failure.contains('unsupported'),
  );

  String? get _failureReason => _failures.isEmpty ? null : _failures.join('; ');

  void _recordFailure(String scope, Object error) {
    final reason = _shortReason(error);
    final entry = '$scope: $reason';
    if (!_failures.contains(entry)) {
      _failures.add(entry);
    }
  }

  Future<void> _prepareCpuProfiler(VmService service, String isolateId) async {
    final flags = await service.getFlagList().timeout(timeout);
    final profiler = flags.flags
        ?.where((flag) => flag.name == 'profiler')
        .firstOrNull;
    if (profiler == null) {
      throw UnsupportedError('VM CPU profiler flag is unavailable.');
    }
    _profilerWasEnabled = profiler.valueAsString == 'true';
    _profilerChanged = !_profilerWasEnabled;
    await service.clearCpuSamples(isolateId).timeout(timeout);
    if (_profilerChanged) {
      await service.setFlag('profiler', 'true').timeout(timeout);
    }
  }

  Future<void> _restoreCpuProfiler() async {
    final service = _service;
    if (service == null || !_profilerChanged) return;
    try {
      await service.setFlag('profiler', 'false').timeout(timeout);
    } catch (_) {
      // A disconnected VM is already unavailable; never mask the test action.
    }
    _profilerChanged = false;
  }

  Future<CockpitHeapPoint?> _readHeapPoint(
    VmService service,
    String isolateId, {
    bool reset = false,
  }) async {
    final profile = await service
        .getAllocationProfile(isolateId, reset: reset)
        .timeout(timeout);
    final usage = profile.memoryUsage;
    final heapUsage = usage?.heapUsage;
    final heapCapacity = usage?.heapCapacity;
    final external = usage?.externalUsage;
    if (heapUsage == null || heapCapacity == null || external == null) {
      return null;
    }
    if (heapUsage < 0 || heapCapacity < heapUsage || external < 0) return null;
    return CockpitHeapPoint(
      usageBytes: heapUsage,
      capacityBytes: heapCapacity,
      externalBytes: external,
    );
  }

  CockpitCpuProfile _cpuProfile(CpuSamples raw) {
    final functions = <CockpitCpuFunction>[];
    for (final function in raw.functions ?? const <ProfileFunction>[]) {
      final reference = function.function;
      final name =
          _dynamicString(reference, 'name') ??
          function.resolvedUrl ??
          '<anonymous>';
      functions.add(
        CockpitCpuFunction(
          name: name,
          kind: function.kind,
          uri: function.resolvedUrl,
          inclusiveTicks: _nonNegative(function.inclusiveTicks),
          exclusiveTicks: _nonNegative(function.exclusiveTicks),
        ),
      );
    }
    final rawSamples = raw.samples ?? const <CpuSample>[];
    final samples = <CockpitCpuSample>[];
    var dropped = 0;
    for (final sample in rawSamples) {
      if (samples.length >= maxCpuSamples) {
        dropped += 1;
        continue;
      }
      final timestamp = sample.timestamp;
      if (timestamp == null || timestamp < 0) {
        dropped += 1;
        continue;
      }
      samples.add(
        CockpitCpuSample(
          timestampUs: timestamp,
          threadId: sample.tid,
          stack: List<int>.unmodifiable(sample.stack ?? const <int>[]),
          vmTag: sample.vmTag,
          userTag: sample.userTag,
          truncated: sample.truncated ?? false,
        ),
      );
    }
    return CockpitCpuProfile(
      samplePeriodUs: _nonNegative(raw.samplePeriod),
      maxStackDepth: _nonNegative(raw.maxStackDepth),
      sampleCount: _nonNegative(raw.sampleCount),
      timeOriginUs: _nonNegative(raw.timeOriginMicros),
      timeExtentUs: _nonNegative(raw.timeExtentMicros),
      pid: raw.pid,
      functions: List.unmodifiable(functions),
      samples: List.unmodifiable(samples),
      droppedSamples: dropped,
    );
  }

  CockpitHeapProfile _heapProfile(
    CockpitHeapPoint before,
    CockpitHeapPoint after,
    AllocationProfile raw,
  ) {
    final members =
        List<ClassHeapStats>.of(raw.members ?? const <ClassHeapStats>[])..sort(
          (left, right) => _nonNegative(
            right.bytesCurrent,
          ).compareTo(_nonNegative(left.bytesCurrent)),
        );
    final classes = <CockpitHeapClass>[];
    for (final member in members.take(maxHeapClasses)) {
      final classRef = member.classRef;
      final name = classRef?.name;
      if (name == null || name.trim().isEmpty) continue;
      final library = classRef?.library;
      classes.add(
        CockpitHeapClass(
          name: name,
          id: classRef?.id,
          library: library?.name,
          currentBytes: _nonNegative(member.bytesCurrent),
          currentInstances: _nonNegative(member.instancesCurrent),
          accumulatedBytes: _nonNegative(member.accumulatedSize),
          accumulatedInstances: _nonNegative(member.instancesAccumulated),
        ),
      );
    }
    return CockpitHeapProfile(
      before: before,
      after: after,
      classes: classes,
      droppedClasses: (raw.members?.length ?? 0) - classes.length,
    );
  }

  CockpitGpuProfile? _gpu(Iterable<CockpitPerformanceEvent> source) {
    var count = 0;
    var shaders = 0;
    var duration = 0;
    for (final event in source) {
      final text = '${event.category} ${event.name}'.toLowerCase();
      final gpu =
          text.contains('gpu') ||
          text.contains('raster') ||
          text.contains('shader') ||
          text.contains('skia');
      if (!gpu) continue;
      count += 1;
      duration += event.durationUs;
      if (text.contains('shader') || text.contains('skia')) shaders += 1;
    }
    if (count == 0) return null;
    return CockpitGpuProfile(
      source: 'vmTimeline',
      events: count,
      shaderEvents: shaders,
      durationUs: duration,
    );
  }

  Future<void> _close() async {
    final service = _service;
    _service = null;
    _isolateId = null;
    _originUs = null;
    _beforeHeap = null;
    if (service != null) await service.dispose();
  }

  static String? _dynamicString(Object? value, String field) {
    try {
      final result = (value as dynamic)?.toJson();
      if (result is Map && result[field] is String) {
        return result[field] as String;
      }
    } catch (_) {
      try {
        final result = (value as dynamic)?.name;
        if (result is String && result.isNotEmpty) return result;
      } catch (_) {}
    }
    return null;
  }

  static String? _mainIsolateId(VM vm) {
    for (final isolate in vm.isolates ?? const <IsolateRef>[]) {
      final id = isolate.id;
      if (id != null && isolate.isSystemIsolate != true) return id;
    }
    for (final isolate in vm.isolates ?? const <IsolateRef>[]) {
      final id = isolate.id;
      if (id != null) return id;
    }
    return null;
  }

  static int _nonNegative(int? value) => value == null || value < 0 ? 0 : value;

  static String _shortReason(Object error) {
    final value = '$error'.trim();
    if (value.isEmpty) return 'VM profiler request failed.';
    return value.length <= 240 ? value : '${value.substring(0, 237)}...';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
