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
    this.maxHeapSamples = 10000,
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
    if (maxHeapSamples < 1 || maxHeapSamples > 10000) {
      throw ArgumentError.value(
        maxHeapSamples,
        'maxHeapSamples',
        'Must be between 1 and 10000.',
      );
    }
  }

  final Duration timeout;
  final int maxCpuSamples;
  final int maxHeapClasses;
  final int maxHeapSamples;

  VmService? _service;
  String? _isolateId;
  int? _originUs;
  CockpitHeapPoint? _beforeHeap;
  CockpitHeapPoint? _beforeGroupHeap;
  CockpitHeapPoint? _afterGroupHeap;
  CockpitIsolateStats? _isolateBefore;
  CockpitIsolateStats? _isolateAfter;
  final List<CockpitIsolateStats> _isolatesBefore = <CockpitIsolateStats>[];
  final List<CockpitIsolateStats> _isolatesAfter = <CockpitIsolateStats>[];
  final List<CockpitIsolateEvent> _isolateEvents = <CockpitIsolateEvent>[];
  StreamSubscription<Event>? _isolateSubscription;
  var _droppedIsolatesBefore = 0;
  var _droppedIsolatesAfter = 0;
  var _droppedIsolateEvents = 0;
  CockpitTimelineProfile? _timeline;
  CockpitVmRuntimeProfile? _vm;
  CockpitVmMemorySnapshot? _vmMemoryBefore;
  CockpitVmMemorySnapshot? _vmMemoryAfter;
  final List<CockpitAllocationTrace> _allocationTraces =
      <CockpitAllocationTrace>[];
  final List<String> _allocationClassIds = <String>[];
  final Map<String, String> _allocationClassNames = <String, String>{};
  final Set<String> _enabledAllocationClassIds = <String>{};
  CockpitPerfettoTrace? _perfettoCpu;
  CockpitPerfettoTrace? _perfettoTimeline;
  Duration _heapSampleEvery = const Duration(milliseconds: 100);
  Timer? _heapSampleTimer;
  Future<void>? _heapSamplePending;
  final List<CockpitHeapSample> _heapSamples = <CockpitHeapSample>[];
  var _droppedHeapSamples = 0;
  bool _profilerWasEnabled = false;
  bool _profilerChanged = false;
  bool _requested = false;
  final List<String> _failures = <String>[];

  /// Starts a capture without blocking the action when the VM service is not
  /// available (for example, a web test or a release build).
  Future<void> start({
    required bool cpu,
    required bool heap,
    required bool timeline,
    required bool vmMemory,
    required bool perfetto,
    Iterable<String> allocationClassIds = const <String>[],
    Duration heapSampleEvery = const Duration(milliseconds: 100),
  }) async {
    if (heapSampleEvery <= Duration.zero ||
        heapSampleEvery.inMilliseconds < 1) {
      throw ArgumentError.value(
        heapSampleEvery,
        'heapSampleEvery',
        'Must be positive.',
      );
    }
    _failures.clear();
    _heapSampleEvery = heapSampleEvery;
    _heapSamples.clear();
    _droppedHeapSamples = 0;
    _beforeHeap = null;
    _beforeGroupHeap = null;
    _afterGroupHeap = null;
    _isolateBefore = null;
    _isolateAfter = null;
    _isolatesBefore.clear();
    _isolatesAfter.clear();
    _isolateEvents.clear();
    _droppedIsolatesBefore = 0;
    _droppedIsolatesAfter = 0;
    _droppedIsolateEvents = 0;
    _timeline = null;
    _vm = null;
    _vmMemoryBefore = null;
    _vmMemoryAfter = null;
    _allocationTraces.clear();
    _allocationClassIds
      ..clear()
      ..addAll(
        allocationClassIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
      );
    _allocationClassNames.clear();
    _enabledAllocationClassIds.clear();
    _perfettoCpu = null;
    _perfettoTimeline = null;
    _profilerWasEnabled = false;
    _profilerChanged = false;
    _requested =
        cpu ||
        heap ||
        timeline ||
        vmMemory ||
        perfetto ||
        _allocationClassIds.isNotEmpty;
    if (!_requested) return;
    try {
      final info = await developer.Service.getInfo().timeout(timeout);
      final uri = info.serverUri;
      if (uri == null) {
        _recordFailure('vm', StateError('VM service URI is unavailable.'));
        return;
      }
      final service = await connectCockpitVmService(uri).timeout(timeout);
      _service = service;
      await _subscribeIsolateEvents(service);
      final vm = await service.getVM().timeout(timeout);
      _vm = _vmProfile(vm);
      final isolateId = _mainIsolateId(vm);
      if (isolateId == null) {
        await service.dispose();
        _recordFailure('vm', StateError('No runnable isolate is available.'));
        return;
      }
      _isolateId = isolateId;
      try {
        _isolatesBefore.addAll(
          await _readIsolates(service, vm, before: true),
        );
        _isolateBefore = _findIsolate(_isolatesBefore, isolateId);
        _isolateBefore ??= _isolateStats(
          await service.getIsolate(isolateId).timeout(timeout),
        );
      } on Object catch (error) {
        _recordFailure('isolate', error);
      }
      if (timeline) {
        try {
          final flags = await service.getVMTimelineFlags().timeout(timeout);
          _timeline = CockpitTimelineProfile(
            recorder: flags.recorderName ?? 'unknown',
            availableStreams: flags.availableStreams ?? const <String>[],
            recordedStreams: flags.recordedStreams ?? const <String>[],
          );
        } on Object catch (error) {
          _recordFailure('timeline-flags', error);
        }
      }
      final now = await service.getVMTimelineMicros().timeout(timeout);
      _originUs = now.timestamp ?? 0;
      if (vmMemory) {
        try {
          _vmMemoryBefore = await _readVmMemorySnapshot(service, _originUs!);
        } on Object catch (error) {
          _recordFailure('vm-memory', error);
        }
      }
      if (cpu || _allocationClassIds.isNotEmpty) {
        try {
          await _prepareCpuProfiler(service, isolateId);
        } on Object catch (error) {
          _recordFailure('cpu', error);
        }
      }
      if (heap) {
        try {
          _beforeHeap = await _readHeapPoint(service, isolateId, reset: true);
          final before = _beforeHeap;
          if (before != null) {
            _heapSamples.add(_heapSample(0, before));
            _startHeapSampling();
          }
          final groupId = _isolateBefore?.groupId;
          if (groupId != null && groupId.isNotEmpty) {
            try {
              _beforeGroupHeap = await _readGroupHeapPoint(service, groupId);
            } on Object catch (error) {
              _recordFailure('heap-group', error);
            }
          }
        } on Object catch (error) {
          _recordFailure('heap', error);
        }
      }
      if (_allocationClassIds.isNotEmpty) {
        try {
          final profile = await service
              .getAllocationProfile(isolateId)
              .timeout(timeout);
          for (final member in profile.members ?? const <ClassHeapStats>[]) {
            final id = member.classRef?.id;
            final name = member.classRef?.name;
            if (id != null && name != null && name.trim().isNotEmpty) {
              _allocationClassNames[id] = name;
            }
          }
          await _enableAllocationTracing(service, isolateId);
        } on Object catch (error) {
          _recordFailure('allocation', error);
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
    required bool timeline,
    required bool vmMemory,
    required bool perfetto,
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
        vm: _vm,
        vmMemory: _vmMemoryBefore == null
            ? null
            : CockpitVmMemoryProfile(before: _vmMemoryBefore),
        isolate: _isolateProfile,
        allocationTraces: _allocationTraces,
        perfetto: _perfettoProfile,
      );
    }

    CockpitCpuProfile? cpuProfile;
    CockpitHeapProfile? heapProfile;
    CockpitVmMemoryProfile? vmMemoryProfile;
    try {
      await _stopHeapSampling();
      int? endUs;
      try {
        final end = await service.getVMTimelineMicros().timeout(timeout);
        endUs = end.timestamp ?? _originUs!;
      } on Object catch (error) {
        _recordFailure('timeline', error);
      }

      if (timeline) {
        try {
          final flags = await service.getVMTimelineFlags().timeout(timeout);
          _timeline = CockpitTimelineProfile(
            recorder: flags.recorderName ?? _timeline?.recorder ?? 'unknown',
            availableStreams:
                flags.availableStreams ??
                _timeline?.availableStreams ??
                const <String>[],
            recordedStreams:
                flags.recordedStreams ??
                _timeline?.recordedStreams ??
                const <String>[],
          );
        } on Object catch (error) {
          _recordFailure('timeline-flags', error);
        }
      }

      final extentUs = endUs == null
          ? null
          : (endUs - _originUs!).clamp(1, 24 * 60 * 60 * 1000000);

      if (_allocationClassIds.isNotEmpty && extentUs != null) {
        await _readAllocationTraces(service, isolateId, extentUs: extentUs);
      }

      if (perfetto && extentUs != null) {
        await _readPerfettoTraces(
          service,
          isolateId,
          extentUs: extentUs,
          includeCpu: cpu,
          includeTimeline: timeline,
        );
      }

      if (vmMemory) {
        try {
          _vmMemoryAfter = await _readVmMemorySnapshot(service, _originUs!);
          if (_vmMemoryBefore != null || _vmMemoryAfter != null) {
            vmMemoryProfile = CockpitVmMemoryProfile(
              before: _vmMemoryBefore,
              after: _vmMemoryAfter,
            );
          }
        } on Object catch (error) {
          _recordFailure('vm-memory', error);
        }
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
            if (endUs != null) {
              _retainHeapSample(
                _heapSample(
                  (endUs - _originUs!).clamp(0, 24 * 60 * 60 * 1000000),
                  after,
                ),
              );
            }
            final allocation = await service
                .getAllocationProfile(isolateId)
                .timeout(timeout);
            final groupId = _isolateBefore?.groupId;
            if (groupId != null && groupId.isNotEmpty) {
              try {
                _afterGroupHeap = await _readGroupHeapPoint(service, groupId);
              } on Object catch (error) {
                _recordFailure('heap-group', error);
              }
            }
            heapProfile = _heapProfile(
              _beforeHeap!,
              after,
              allocation,
              samples: _heapSamples,
              droppedSamples: _droppedHeapSamples,
              groupBefore: _beforeGroupHeap,
              groupAfter: _afterGroupHeap,
            );
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
      try {
        final currentVm = await service.getVM().timeout(timeout);
        _isolatesAfter.addAll(
          await _readIsolates(service, currentVm, before: false),
        );
        _isolateAfter = _findIsolate(_isolatesAfter, isolateId);
        _isolateAfter ??= _isolateStats(
          await service.getIsolate(isolateId).timeout(timeout),
        );
      } on Object catch (error) {
        _recordFailure('isolate', error);
      }
    } finally {
      await _restoreCpuProfiler();
      await _close();
    }

    final gpu = _gpu(events);
    final hasData =
        cpuProfile != null ||
        heapProfile != null ||
        _isolateBefore != null ||
        _isolateAfter != null ||
        _isolatesBefore.isNotEmpty ||
        _isolatesAfter.isNotEmpty ||
        _timeline != null ||
        _vm != null ||
        vmMemoryProfile != null ||
        _allocationTraces.isNotEmpty ||
        _perfettoProfile != null ||
        gpu != null;
    if (!hasData && _failures.isNotEmpty) {
      return CockpitDevToolsProfile(
        source: 'vm',
        state: 'unavailable',
        reason: _failureReason,
        gpu: gpu,
        vm: _vm,
        vmMemory: vmMemoryProfile,
        isolate: _isolateProfile,
        allocationTraces: _allocationTraces,
        perfetto: _perfettoProfile,
      );
    }
    return CockpitDevToolsProfile(
      source: 'vm',
      state: hasData ? 'available' : 'unavailable',
      reason: _failureReason,
      cpu: cpuProfile,
      heap: heapProfile,
      gpu: gpu,
      isolate: _isolateProfile,
      timeline: _timeline,
      vm: _vm,
      vmMemory: vmMemoryProfile,
      allocationTraces: _allocationTraces,
      perfetto: _perfettoProfile,
    );
  }

  CockpitPerfettoProfile? get _perfettoProfile {
    if (_perfettoCpu == null && _perfettoTimeline == null) return null;
    return CockpitPerfettoProfile(
      cpu: _perfettoCpu,
      timeline: _perfettoTimeline,
    );
  }

  CockpitIsolateProfile? get _isolateProfile {
    if (_isolateBefore == null &&
        _isolateAfter == null &&
        _isolatesBefore.isEmpty &&
        _isolatesAfter.isEmpty) {
      return null;
    }
    return CockpitIsolateProfile(
      before: _isolateBefore,
      after: _isolateAfter,
      beforeAll: _isolatesBefore,
      afterAll: _isolatesAfter,
      droppedBefore: _droppedIsolatesBefore,
      droppedAfter: _droppedIsolatesAfter,
      events: _isolateEvents,
      droppedEvents: _droppedIsolateEvents,
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

  Future<void> _enableAllocationTracing(
    VmService service,
    String isolateId,
  ) async {
    for (final classId in _allocationClassIds.take(20)) {
      if (!_allocationClassNames.containsKey(classId)) {
        _recordFailure(
          'allocation',
          StateError('VM class $classId was not present in the baseline.'),
        );
        continue;
      }
      try {
        await service
            .setTraceClassAllocation(isolateId, classId, true)
            .timeout(timeout);
        _enabledAllocationClassIds.add(classId);
      } on Object catch (error) {
        _recordFailure('allocation:$classId', error);
      }
    }
  }

  Future<void> _readAllocationTraces(
    VmService service,
    String isolateId, {
    required int extentUs,
  }) async {
    for (final classId in _enabledAllocationClassIds) {
      try {
        final raw = await service
            .getAllocationTraces(
              isolateId,
              timeOriginMicros: _originUs,
              timeExtentMicros: extentUs,
              classId: classId,
            )
            .timeout(timeout);
        _allocationTraces.add(
          CockpitAllocationTrace(
            classId: classId,
            className: _allocationClassNames[classId],
            profile: _cpuProfile(raw),
          ),
        );
      } on Object catch (error) {
        _recordFailure('allocation:$classId', error);
      }
    }
  }

  Future<void> _readPerfettoTraces(
    VmService service,
    String isolateId, {
    required int extentUs,
    required bool includeCpu,
    required bool includeTimeline,
  }) async {
    if (includeCpu && (_profilerWasEnabled || _profilerChanged)) {
      try {
        final raw = await service
            .getPerfettoCpuSamples(
              isolateId,
              timeOriginMicros: _originUs,
              timeExtentMicros: extentUs,
            )
            .timeout(timeout);
        final data = raw.samples;
        if (data != null && data.isNotEmpty) {
          _perfettoCpu = CockpitPerfettoTrace(
            kind: 'cpu',
            data: data,
            originUs: _nonNegativeNullable(raw.timeOriginMicros) ?? _originUs!,
            extentUs: _nonNegativeNullable(raw.timeExtentMicros) ?? extentUs,
            samplePeriodUs: _nonNegativeNullable(raw.samplePeriod),
            maxStackDepth: _nonNegativeNullable(raw.maxStackDepth),
            sampleCount: _nonNegativeNullable(raw.sampleCount),
            pid: _nonNegativeNullable(raw.pid),
          );
        }
      } on Object catch (error) {
        _recordFailure('perfetto-cpu', error);
      }
    }
    if (includeTimeline) {
      try {
        final raw = await service
            .getPerfettoVMTimeline(
              timeOriginMicros: _originUs,
              timeExtentMicros: extentUs,
            )
            .timeout(timeout);
        final data = raw.trace;
        if (data != null && data.isNotEmpty) {
          _perfettoTimeline = CockpitPerfettoTrace(
            kind: 'timeline',
            data: data,
            originUs: _nonNegativeNullable(raw.timeOriginMicros) ?? _originUs!,
            extentUs: _nonNegativeNullable(raw.timeExtentMicros) ?? extentUs,
          );
        }
      } on Object catch (error) {
        _recordFailure('perfetto-timeline', error);
      }
    }
  }

  static int? _nonNegativeNullable(int? value) {
    return value == null || value < 0 ? null : value;
  }

  static String _nonEmpty(String? value, {required String fallback}) {
    final text = value?.trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static String? _nonEmptyNullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
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

  Future<CockpitHeapPoint?> _readGroupHeapPoint(
    VmService service,
    String groupId,
  ) async {
    final usage = await service
        .getIsolateGroupMemoryUsage(groupId)
        .timeout(timeout);
    return _heapPointFromMemory(usage);
  }

  static CockpitHeapPoint? _heapPointFromMemory(MemoryUsage usage) {
    final heapUsage = usage.heapUsage;
    final heapCapacity = usage.heapCapacity;
    final external = usage.externalUsage;
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

  static CockpitIsolateStats _isolateStats(Isolate isolate) {
    String? pauseKind;
    try {
      final kind = isolate.pauseEvent?.json?['kind'];
      if (kind is String && kind.isNotEmpty) pauseKind = kind;
    } catch (_) {}
    String? error;
    try {
      final message = isolate.error?.message;
      if (message is String && message.isNotEmpty) error = message;
    } catch (_) {}
    return CockpitIsolateStats(
      id: _nonEmpty(isolate.id, fallback: 'unknown'),
      name: _nonEmpty(isolate.name, fallback: 'isolate'),
      groupId: _nonEmptyNullable(isolate.isolateGroupId),
      runnable: isolate.runnable,
      livePorts: _nonNegativeNullable(isolate.livePorts),
      libraryCount: isolate.libraries?.length,
      extensionCount: isolate.extensionRPCs?.length,
      startTimeMs: _nonNegativeNullable(isolate.startTime),
      system: isolate.isSystemIsolate,
      pauseKind: pauseKind,
      error: error,
    );
  }

  static const _maxIsolateSnapshots = 64;
  static const _maxIsolateEvents = 1000;

  Future<void> _subscribeIsolateEvents(VmService service) async {
    final subscription = service.onIsolateEvent.listen(_recordIsolateEvent);
    _isolateSubscription = subscription;
    try {
      await service.streamListen(EventStreams.kIsolate).timeout(timeout);
    } on Object catch (error) {
      await subscription.cancel();
      _isolateSubscription = null;
      _recordFailure('isolate-stream', error);
    }
  }

  void _recordIsolateEvent(Event event) {
    final kind = event.kind?.trim();
    if (kind == null || kind.isEmpty) return;
    if (_isolateEvents.length >= _maxIsolateEvents) {
      _droppedIsolateEvents += 1;
      return;
    }
    _isolateEvents.add(
      CockpitIsolateEvent(
        kind: kind,
        timestampMs: _nonNegativeNullable(event.timestamp),
        isolateId: _nonEmptyNullable(event.isolate?.id),
        name: _nonEmptyNullable(event.isolate?.name),
        groupId: _nonEmptyNullable(event.isolateGroup?.id),
      ),
    );
  }

  Future<List<CockpitIsolateStats>> _readIsolates(
    VmService service,
    VM vm, {
    required bool before,
  }) async {
    final refs = vm.isolates ?? const <IsolateRef>[];
    final dropped = refs.length > _maxIsolateSnapshots
        ? refs.length - _maxIsolateSnapshots
        : 0;
    final values = await Future.wait(
      refs.take(_maxIsolateSnapshots).map((ref) async {
        final id = ref.id;
        if (id == null || id.isEmpty) return null;
        try {
          return _isolateStats(
            await service.getIsolate(id).timeout(timeout),
          );
        } on Object catch (error) {
          _recordFailure('isolate:$id', error);
          return null;
        }
      }),
    );
    if (before) {
      _droppedIsolatesBefore = dropped;
    } else {
      _droppedIsolatesAfter = dropped;
    }
    return values.whereType<CockpitIsolateStats>().toList(growable: false);
  }

  static CockpitIsolateStats? _findIsolate(
    Iterable<CockpitIsolateStats> isolates,
    String id,
  ) {
    for (final isolate in isolates) {
      if (isolate.id == id) return isolate;
    }
    return null;
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
          threadId: _nonNegativeNullable(sample.tid),
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
      timeOriginUs:
          _nonNegativeNullable(raw.timeOriginMicros) ?? _originUs ?? 0,
      timeExtentUs: _nonNegativeNullable(raw.timeExtentMicros) ?? 0,
      pid: _nonNegativeNullable(raw.pid),
      functions: List.unmodifiable(functions),
      samples: List.unmodifiable(samples),
      droppedSamples: dropped,
    );
  }

  CockpitHeapProfile _heapProfile(
    CockpitHeapPoint before,
    CockpitHeapPoint after,
    AllocationProfile raw, {
    Iterable<CockpitHeapSample> samples = const <CockpitHeapSample>[],
    int droppedSamples = 0,
    CockpitHeapPoint? groupBefore,
    CockpitHeapPoint? groupAfter,
  }) {
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
    final memberCount = raw.members?.length ?? 0;
    return CockpitHeapProfile(
      before: before,
      after: after,
      classes: classes,
      droppedClasses: memberCount > classes.length
          ? memberCount - classes.length
          : 0,
      intervalMs: _heapSampleEvery.inMilliseconds,
      samples: samples,
      droppedSamples: droppedSamples,
      groupBefore: groupBefore,
      groupAfter: groupAfter,
    );
  }

  void _startHeapSampling() {
    if (_heapSampleTimer != null || _service == null || _isolateId == null) {
      return;
    }
    _heapSampleTimer = Timer.periodic(
      _heapSampleEvery,
      (_) => unawaited(_sampleHeap()),
    );
  }

  Future<void> _sampleHeap() async {
    final service = _service;
    final isolateId = _isolateId;
    final originUs = _originUs;
    if (service == null || isolateId == null || originUs == null) return;
    if (_heapSamplePending != null) {
      _droppedHeapSamples += 1;
      return;
    }
    final pending = _readVmHeapSample(service, isolateId, originUs);
    _heapSamplePending = pending;
    try {
      final sample = await pending;
      if (sample == null) {
        _droppedHeapSamples += 1;
      } else {
        _retainHeapSample(sample);
      }
    } on Object catch (error) {
      _droppedHeapSamples += 1;
      _recordFailure('heap-sample', error);
    } finally {
      if (identical(_heapSamplePending, pending)) {
        _heapSamplePending = null;
      }
    }
  }

  void _retainHeapSample(CockpitHeapSample sample) {
    if (_heapSamples.length < maxHeapSamples) {
      _heapSamples.add(sample);
    } else {
      _droppedHeapSamples += 1;
    }
  }

  Future<CockpitHeapSample?> _readVmHeapSample(
    VmService service,
    String isolateId,
    int originUs,
  ) async {
    final values = await Future.wait<Object?>(<Future<Object?>>[
      service.getVMTimelineMicros().timeout(timeout),
      service.getMemoryUsage(isolateId).timeout(timeout),
    ]);
    final now = values[0] as Timestamp;
    final point = _heapPointFromMemory(values[1] as MemoryUsage);
    if (point == null) return null;
    final timestamp = ((now.timestamp ?? originUs) - originUs).clamp(
      0,
      24 * 60 * 60 * 1000000,
    );
    return _heapSample(timestamp, point);
  }

  Future<CockpitVmMemorySnapshot?> _readVmMemorySnapshot(
    VmService service,
    int originUs,
  ) async {
    final values = await Future.wait<Object?>(<Future<Object?>>[
      service.getVMTimelineMicros().timeout(timeout),
      service.getProcessMemoryUsage().timeout(timeout),
    ]);
    final now = values[0] as Timestamp;
    final usage = values[1] as ProcessMemoryUsage;
    final root = usage.root;
    if (root == null) return null;
    _vmMemoryNodes = 0;
    final node = _vmMemoryNode(root, depth: 1);
    if (node == null) return null;
    final timestamp = ((now.timestamp ?? originUs) - originUs).clamp(
      0,
      24 * 60 * 60 * 1000000,
    );
    return CockpitVmMemorySnapshot(timestampUs: timestamp, root: node);
  }

  static const _maxVmMemoryDepth = 8;
  static const _maxVmMemoryNodes = 512;
  static const _maxVmMemoryChildren = 64;
  var _vmMemoryNodes = 0;

  CockpitVmMemoryNode? _vmMemoryNode(
    ProcessMemoryItem item, {
    required int depth,
  }) {
    if (_vmMemoryNodes >= _maxVmMemoryNodes) return null;
    final name = item.name?.trim();
    final size = item.size;
    if (name == null || name.isEmpty || size == null || size < 0) return null;
    _vmMemoryNodes += 1;

    final rawChildren = List<ProcessMemoryItem>.of(
      item.children ?? const <ProcessMemoryItem>[],
    )..sort((left, right) => (right.size ?? -1).compareTo(left.size ?? -1));
    var dropped = depth >= _maxVmMemoryDepth
        ? rawChildren.length
        : rawChildren.length > _maxVmMemoryChildren
        ? rawChildren.length - _maxVmMemoryChildren
        : 0;
    final children = <CockpitVmMemoryNode>[];
    if (depth < _maxVmMemoryDepth) {
      for (final child in rawChildren.take(_maxVmMemoryChildren)) {
        final node = _vmMemoryNode(child, depth: depth + 1);
        if (node == null) {
          dropped += 1;
        } else {
          children.add(node);
        }
      }
    }
    return CockpitVmMemoryNode(
      name: name,
      sizeBytes: size,
      children: children,
      droppedChildren: dropped,
    );
  }

  CockpitHeapSample _heapSample(int timestampUs, CockpitHeapPoint point) =>
      CockpitHeapSample(
        timestampUs: timestampUs,
        usageBytes: point.usageBytes,
        capacityBytes: point.capacityBytes,
        externalBytes: point.externalBytes,
      );

  Future<void> _stopHeapSampling() async {
    _heapSampleTimer?.cancel();
    _heapSampleTimer = null;
    final pending = _heapSamplePending;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The failed sample is already represented by the bounded reason.
      }
    }
    _heapSamplePending = null;
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
    await _stopHeapSampling();
    final service = _service;
    final isolateId = _isolateId;
    final isolateSubscription = _isolateSubscription;
    _isolateSubscription = null;
    if (isolateSubscription != null) {
      await isolateSubscription.cancel();
    }
    if (service != null && isolateId != null) {
      for (final classId in _enabledAllocationClassIds) {
        try {
          await service
              .setTraceClassAllocation(isolateId, classId, false)
              .timeout(timeout);
        } catch (_) {
          // A disconnected VM already stopped tracing; never mask the action.
        }
      }
    }
    if (service != null) {
      try {
        await service.streamCancel(EventStreams.kIsolate).timeout(timeout);
      } catch (_) {
        // A disconnected VM already stopped the stream.
      }
    }
    _enabledAllocationClassIds.clear();
    _service = null;
    _isolateId = null;
    _originUs = null;
    _beforeHeap = null;
    _vmMemoryBefore = null;
    _vmMemoryAfter = null;
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

  static CockpitVmRuntimeProfile _vmProfile(VM vm) {
    int? nonNegative(int? value) => value == null || value < 0 ? null : value;
    String? nonEmpty(String? value) {
      final text = value?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return CockpitVmRuntimeProfile(
      name: nonEmpty(vm.name),
      version: nonEmpty(vm.version),
      operatingSystem: nonEmpty(vm.operatingSystem),
      hostCpu: nonEmpty(vm.hostCPU),
      targetCpu: nonEmpty(vm.targetCPU),
      architectureBits: vm.architectureBits == null || vm.architectureBits! <= 0
          ? null
          : vm.architectureBits,
      pid: nonNegative(vm.pid),
      startTimeMs: nonNegative(vm.startTime),
      isolateCount: vm.isolates?.length,
      isolateGroupCount: vm.isolateGroups?.length,
      systemIsolateCount: vm.systemIsolates?.length,
    );
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
