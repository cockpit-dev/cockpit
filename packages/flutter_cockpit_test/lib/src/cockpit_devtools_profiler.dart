import 'dart:async';
import 'dart:developer' as developer;

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:vm_service/vm_service.dart';

import 'cockpit_vm_service_connect.dart';
import 'cockpit_timeline_analysis.dart';

/// Collects the bounded VM data that powers Flutter DevTools' CPU and Memory
/// views. It is deliberately best-effort: a missing profiler must not make a
/// user interaction fail, but the report records the exact unavailable reason.
final class CockpitDevToolsProfiler {
  CockpitDevToolsProfiler({
    this.timeout = const Duration(seconds: 3),
    this.maxCpuSamples = 50000,
    this.maxHeapClasses = 200,
    this.maxHeapSamples = 10000,
    this.maxRebuildFrames = 10000,
    this.maxRebuildEntries = 100000,
    this.maxLogEvents = 2000,
    this.maxDebugEvents = 2000,
    this.onIsolateEvent,
    this.onLogEvent,
    this.onDebugEvent,
    this.onHeapSample,
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
    if (maxRebuildFrames < 1 || maxRebuildFrames > 10000) {
      throw ArgumentError.value(
        maxRebuildFrames,
        'maxRebuildFrames',
        'Must be between 1 and 10000.',
      );
    }
    if (maxRebuildEntries < 1 || maxRebuildEntries > 1000000) {
      throw ArgumentError.value(
        maxRebuildEntries,
        'maxRebuildEntries',
        'Must be between 1 and 1000000.',
      );
    }
    if (maxLogEvents < 1 || maxLogEvents > 100000) {
      throw ArgumentError.value(
        maxLogEvents,
        'maxLogEvents',
        'Must be between 1 and 100000.',
      );
    }
    if (maxDebugEvents < 1 || maxDebugEvents > 100000) {
      throw ArgumentError.value(
        maxDebugEvents,
        'maxDebugEvents',
        'Must be between 1 and 100000.',
      );
    }
  }

  final Duration timeout;
  final int maxCpuSamples;
  final int maxHeapClasses;
  final int maxHeapSamples;
  final int maxRebuildFrames;
  final int maxRebuildEntries;
  final int maxLogEvents;
  final int maxDebugEvents;
  final void Function(CockpitIsolateEvent event)? onIsolateEvent;
  final void Function(CockpitVmLogEvent event)? onLogEvent;
  final void Function(CockpitVmDebugEvent event)? onDebugEvent;
  final void Function(CockpitHeapSample sample)? onHeapSample;

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
  final List<CockpitVmLogEvent> _logEvents = <CockpitVmLogEvent>[];
  final List<CockpitVmDebugEvent> _debugEvents = <CockpitVmDebugEvent>[];
  StreamSubscription<Event>? _isolateSubscription;
  StreamSubscription<Event>? _extensionSubscription;
  StreamSubscription<Event>? _loggingSubscription;
  StreamSubscription<Event>? _debugSubscription;
  var _droppedIsolatesBefore = 0;
  var _droppedIsolatesAfter = 0;
  var _droppedIsolateEvents = 0;
  var _droppedLogEvents = 0;
  var _droppedDebugEvents = 0;
  CockpitTimelineProfile? _timeline;
  CockpitDisplayProfile? _display;
  final List<CockpitRebuildFrame> _rebuildFrames = <CockpitRebuildFrame>[];
  final Map<int, CockpitRebuildLocation> _rebuildLocations =
      <int, CockpitRebuildLocation>{};
  final Map<int, int> _rebuildTotals = <int, int>{};
  var _retainedRebuildEntries = 0;
  var _droppedRebuildFrames = 0;
  var _droppedRebuildEntries = 0;
  var _unresolvedRebuildLocations = 0;
  bool? _rebuildEnabledBefore;
  var _rebuildChanged = false;
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
  bool _windowEnded = false;
  int? _captureEndUs;
  final List<String> _failures = <String>[];
  bool _streamTimeline = false;
  int? _timelineCursorUs;
  Future<List<Object?>>? _timelineDrainPending;

  /// Starts a capture without blocking the action when the VM service is not
  /// available (for example, a web test or a release build).
  Future<void> start({
    required bool cpu,
    required bool heap,
    required bool timeline,
    required bool vmMemory,
    required bool perfetto,
    required bool trackRebuilds,
    bool logs = true,
    bool debug = true,
    Iterable<String> allocationClassIds = const <String>[],
    Duration heapSampleEvery = const Duration(milliseconds: 100),
    List<String> timelineStreams = const <String>['all'],
    bool streamTimeline = false,
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
    _logEvents.clear();
    _debugEvents.clear();
    _droppedIsolatesBefore = 0;
    _droppedIsolatesAfter = 0;
    _droppedIsolateEvents = 0;
    _droppedLogEvents = 0;
    _droppedDebugEvents = 0;
    _timeline = null;
    _display = null;
    _rebuildFrames.clear();
    _rebuildLocations.clear();
    _rebuildTotals.clear();
    _retainedRebuildEntries = 0;
    _droppedRebuildFrames = 0;
    _droppedRebuildEntries = 0;
    _unresolvedRebuildLocations = 0;
    _rebuildEnabledBefore = null;
    _rebuildChanged = false;
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
    _windowEnded = false;
    _captureEndUs = null;
    _streamTimeline = streamTimeline;
    _timelineCursorUs = null;
    _timelineDrainPending = null;
    _requested =
        cpu ||
        heap ||
        timeline ||
        vmMemory ||
        perfetto ||
        _allocationClassIds.isNotEmpty ||
        trackRebuilds ||
        logs ||
        debug;
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
      if (logs) await _subscribeLoggingEvents(service);
      if (debug) await _subscribeDebugEvents(service);
      final vm = await service.getVM().timeout(timeout);
      _vm = _vmProfile(vm);
      final isolateId = _mainIsolateId(vm);
      if (isolateId == null) {
        await service.dispose();
        _recordFailure('vm', StateError('No runnable isolate is available.'));
        return;
      }
      _isolateId = isolateId;
      if (trackRebuilds) {
        await _subscribeRebuildEvents(service);
        try {
          await _prepareRebuildTracking(service, isolateId);
        } on Object catch (error) {
          _recordFailure('rebuilds', error);
        }
      }
      try {
        _display = await _readDisplayProfile(service, isolateId);
      } on Object catch (error) {
        _recordFailure('display', error);
      }
      try {
        _isolatesBefore.addAll(await _readIsolates(service, vm, before: true));
        _isolateBefore = _findIsolate(_isolatesBefore, isolateId);
        _isolateBefore ??= _isolateStats(
          await service.getIsolate(isolateId).timeout(timeout),
        );
      } on Object catch (error) {
        _recordFailure('isolate', error);
      }
      if (timeline) {
        try {
          if (streamTimeline) {
            await service.setVMTimelineFlags(timelineStreams).timeout(timeout);
            await service.clearVMTimeline().timeout(timeout);
          }
          final flags = await service.getVMTimelineFlags().timeout(timeout);
          _timeline = CockpitTimelineProfile(
            recorder: _timelineRecorder(flags.recorderName),
            availableStreams: flags.availableStreams ?? const <String>[],
            recordedStreams: flags.recordedStreams ?? const <String>[],
          );
        } on Object catch (error) {
          _recordFailure('timeline-flags', error);
        }
      }
      final now = await service.getVMTimelineMicros().timeout(timeout);
      _originUs = now.timestamp ?? 0;
      _timelineCursorUs = _originUs;
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

  /// Reads only the VM timeline interval since the previous drain. This is
  /// used by long-running archives so the integration_test binding never
  /// materializes the entire action timeline in one object.
  Future<List<Object?>> drainTimeline() async {
    final pending = _timelineDrainPending;
    if (pending != null) return pending;
    final operation = _drainTimeline();
    _timelineDrainPending = operation;
    try {
      return await operation;
    } finally {
      if (identical(_timelineDrainPending, operation)) {
        _timelineDrainPending = null;
      }
    }
  }

  Future<List<Object?>> _drainTimeline() async {
    if (!_streamTimeline) return const <Object>[];
    final service = _service;
    final cursor = _timelineCursorUs;
    if (service == null || cursor == null) return const <Object>[];
    try {
      final now = await service.getVMTimelineMicros().timeout(timeout);
      final end = now.timestamp;
      if (end == null || end <= cursor) return const <Object>[];
      final timeline = await service
          .getVMTimeline(
            timeOriginMicros: cursor + 1,
            timeExtentMicros: end - cursor,
          )
          .timeout(timeout);
      _timelineCursorUs = end;
      return <Object?>[
        for (final event in timeline.traceEvents ?? const <TimelineEvent>[]) 
          if (event.json != null) event.json!,
      ];
    } on Object catch (error) {
      _recordFailure('timeline-drain', error);
      return const <Object>[];
    }
  }

  /// Freezes VM-side sampling at the end of the measured action. Queries made
  /// while assembling the report are excluded from event streams and CPU
  /// sampling extents.
  Future<void> endWindow() async {
    if (_windowEnded) return;
    _windowEnded = true;
    await _stopHeapSampling();
    final service = _service;
    if (service == null) return;
    try {
      final end = await service.getVMTimelineMicros().timeout(timeout);
      _captureEndUs = end.timestamp;
    } on Object catch (error) {
      _recordFailure('timeline-end', error);
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
      final gc = _gc(events);
      return gpu == null && gc == null
          ? null
          : CockpitDevToolsProfile(
              source: 'vmTimeline',
              state: 'available',
              gpu: gpu,
              gc: gc,
            );
    }
    final service = _service;
    final isolateId = _isolateId;
    final capturedGc = _gc(events);
    if (service == null || isolateId == null || _originUs == null) {
      return CockpitDevToolsProfile(
        source: 'vm',
        state: _hasUnsupportedFailure ? 'unsupported' : 'unavailable',
        reason: _failureReason ?? 'VM service connection was not established.',
        gc: capturedGc,
        gpu: _gpu(events),
        display: _display,
        rebuild: _rebuildProfile,
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
      int? endUs = _captureEndUs;
      try {
        if (endUs == null) {
          final end = await service.getVMTimelineMicros().timeout(timeout);
          endUs = end.timestamp ?? _originUs!;
        }
      } on Object catch (error) {
        _recordFailure('timeline', error);
      }

      if (timeline) {
        try {
          final flags = await service.getVMTimelineFlags().timeout(timeout);
          _timeline = CockpitTimelineProfile(
            recorder: _timelineRecorder(
              flags.recorderName ?? _timeline?.recorder,
            ),
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
        _isolateEvents.isNotEmpty ||
        _droppedIsolatesBefore > 0 ||
        _droppedIsolatesAfter > 0 ||
        _droppedIsolateEvents > 0 ||
        _logEvents.isNotEmpty ||
        _debugEvents.isNotEmpty ||
        _droppedLogEvents > 0 ||
        _droppedDebugEvents > 0 ||
        _timeline != null ||
        _display != null ||
        _rebuildFrames.isNotEmpty ||
        _vm != null ||
        vmMemoryProfile != null ||
        _allocationTraces.isNotEmpty ||
        _perfettoProfile != null ||
        gpu != null ||
        capturedGc != null;
    if (!hasData && _failures.isNotEmpty) {
      return CockpitDevToolsProfile(
        source: 'vm',
        state: 'unavailable',
        reason: _failureReason,
        gc: capturedGc,
        gpu: gpu,
        display: _display,
        rebuild: _rebuildProfile,
        vm: _vm,
        vmMemory: vmMemoryProfile,
        isolate: _isolateProfile,
        allocationTraces: _allocationTraces,
        logs: _logEvents,
        debug: _debugEvents,
        droppedLogs: _droppedLogEvents,
        droppedDebug: _droppedDebugEvents,
        perfetto: _perfettoProfile,
      );
    }
    return CockpitDevToolsProfile(
      source: 'vm',
      state: hasData ? 'available' : 'unavailable',
      reason: _failureReason,
      cpu: cpuProfile,
      heap: heapProfile,
      gc: capturedGc,
      gpu: gpu,
      isolate: _isolateProfile,
      timeline: _timeline,
      display: _display,
      rebuild: _rebuildProfile,
      vm: _vm,
      vmMemory: vmMemoryProfile,
      allocationTraces: _allocationTraces,
      logs: _logEvents,
      debug: _debugEvents,
      droppedLogs: _droppedLogEvents,
      droppedDebug: _droppedDebugEvents,
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
        _isolatesAfter.isEmpty &&
        _isolateEvents.isEmpty &&
        _droppedIsolatesBefore == 0 &&
        _droppedIsolatesAfter == 0 &&
        _droppedIsolateEvents == 0) {
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

  CockpitRebuildProfile? get _rebuildProfile {
    if (_rebuildFrames.isEmpty &&
        _rebuildLocations.isEmpty &&
        _rebuildTotals.isEmpty &&
        _droppedRebuildFrames == 0 &&
        _droppedRebuildEntries == 0 &&
        _unresolvedRebuildLocations == 0) {
      return null;
    }
    final locations = _rebuildLocations.values.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    final totals = _rebuildTotals.entries.toList(growable: false)
      ..sort((left, right) {
        final count = right.value.compareTo(left.value);
        return count != 0 ? count : left.key.compareTo(right.key);
      });
    return CockpitRebuildProfile(
      frames: _rebuildFrames,
      locations: locations,
      totals: totals
          .map(
            (entry) =>
                CockpitRebuildTotal(locationId: entry.key, count: entry.value),
          )
          .toList(growable: false),
      droppedFrames: _droppedRebuildFrames,
      droppedEntries: _droppedRebuildEntries,
      unresolvedLocations: _unresolvedRebuildLocations,
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

  static String? _boundedEventText(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= 64 * 1024
        ? text
        : '${text.substring(0, 64 * 1024 - 1)}…';
  }

  static String _nonEmpty(String? value, {required String fallback}) {
    final text = value?.trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static String _timelineRecorder(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized.toLowerCase() == 'null') {
      return 'none';
    }
    return normalized;
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
    final pause = isolate.pauseEvent;
    final rawHeaps = isolate.json?['_heaps'];
    final heaps = rawHeaps is Map ? rawHeaps : const <Object?, Object?>{};
    return CockpitIsolateStats(
      id: _nonEmpty(isolate.id, fallback: 'unknown'),
      name: _nonEmpty(isolate.name, fallback: 'isolate'),
      number: _nonEmptyNullable(isolate.number),
      groupId: _nonEmptyNullable(isolate.isolateGroupId),
      runnable: isolate.runnable,
      livePorts: _nonNegativeNullable(isolate.livePorts),
      libraryCount: isolate.libraries?.length,
      extensionCount: isolate.extensionRPCs?.length,
      startTimeMs: _nonNegativeNullable(isolate.startTime),
      system: isolate.isSystemIsolate,
      pauseKind: pauseKind,
      pauseTimestampMs: _nonNegativeNullable(pause?.timestamp),
      pauseAsync: pause?.atAsyncSuspension,
      error: error,
      pauseOnExit: isolate.pauseOnExit,
      exceptionPauseMode: _nonEmptyNullable(isolate.exceptionPauseMode),
      rootLibUri: _nonEmptyNullable(isolate.rootLib?.uri),
      breakpointCount: isolate.breakpoints?.length,
      newHeap: _heapPointFromRaw(heaps['new']),
      oldHeap: _heapPointFromRaw(heaps['old']),
    );
  }

  static CockpitHeapPoint? _heapPointFromRaw(Object? value) {
    if (value is! Map) return null;
    final usage = _intValue(value['used'] ?? value['usage']);
    final capacity = _intValue(value['capacity'] ?? value['cap']);
    final external = _intValue(value['external'] ?? value['ext']);
    if (usage == null || capacity == null || external == null) return null;
    if (usage < 0 || capacity < usage || external < 0) return null;
    return CockpitHeapPoint(
      usageBytes: usage,
      capacityBytes: capacity,
      externalBytes: external,
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
    if (_windowEnded) return;
    final kind = event.kind?.trim();
    if (kind == null || kind.isEmpty) return;
    if (_isolateEvents.length >= _maxIsolateEvents) {
      _droppedIsolateEvents += 1;
      return;
    }
    final record = CockpitIsolateEvent(
        kind: kind,
        timestampMs: _nonNegativeNullable(event.timestamp),
        isolateId: _nonEmptyNullable(event.isolate?.id),
        name: _nonEmptyNullable(event.isolate?.name),
        groupId: _nonEmptyNullable(event.isolateGroup?.id),
        extensionRpc: _nonEmptyNullable(event.extensionRPC),
      );
    _isolateEvents.add(record);
    try {
      onIsolateEvent?.call(record);
    } on Object {
      // An archive sink must not affect VM event delivery.
    }
  }

  Future<void> _subscribeLoggingEvents(VmService service) async {
    final subscription = service.onLoggingEvent.listen(_recordLoggingEvent);
    _loggingSubscription = subscription;
    try {
      await service.streamListen(EventStreams.kLogging).timeout(timeout);
    } on Object catch (error) {
      await subscription.cancel();
      _loggingSubscription = null;
      _recordFailure('logging-stream', error);
    }
  }

  void _recordLoggingEvent(Event event) {
    if (_windowEnded) return;
    if (_logEvents.length >= maxLogEvents) {
      _droppedLogEvents += 1;
      return;
    }
    final log = event.logRecord;
    if (log == null) return;
    final record = CockpitVmLogEvent(
      timestampMs: _nonNegativeNullable(log.time ?? event.timestamp),
      level: _nonNegativeNullable(log.level),
      sequence: _nonNegativeNullable(log.sequenceNumber),
      message: _boundedEventText(log.message?.valueAsString),
      logger: _boundedEventText(log.loggerName?.valueAsString),
      zone: _boundedEventText(log.zone?.valueAsString),
      error: _boundedEventText(log.error?.valueAsString),
      stack: _boundedEventText(log.stackTrace?.valueAsString),
      isolateId: _nonEmptyNullable(event.isolate?.id),
    );
    _logEvents.add(record);
    try {
      onLogEvent?.call(record);
    } on Object {
      // An archive sink must not affect VM event delivery.
    }
  }

  Future<void> _subscribeDebugEvents(VmService service) async {
    final subscription = service.onDebugEvent.listen(_recordDebugEvent);
    _debugSubscription = subscription;
    try {
      await service.streamListen(EventStreams.kDebug).timeout(timeout);
    } on Object catch (error) {
      await subscription.cancel();
      _debugSubscription = null;
      _recordFailure('debug-stream', error);
    }
  }

  void _recordDebugEvent(Event event) {
    if (_windowEnded) return;
    if (_debugEvents.length >= maxDebugEvents) {
      _droppedDebugEvents += 1;
      return;
    }
    final kind = event.kind?.trim();
    if (kind == null || kind.isEmpty) return;
    final frame = event.topFrame;
    final location = frame?.location;
    final functionName = frame?.function?.name?.trim().isNotEmpty == true
        ? frame!.function!.name
        : frame?.code?.name;
    final exception = event.exception?.valueAsString;
    final record = CockpitVmDebugEvent(
        kind: kind,
        timestampMs: _nonNegativeNullable(event.timestamp),
        isolateId: _nonEmptyNullable(event.isolate?.id),
        isolateName: _nonEmptyNullable(event.isolate?.name),
        status: _boundedEventText(event.status),
        // `details` is not part of the vm_service Event contract on the
        // minimum supported Flutter toolchain. Keep the projection limited to
        // the stable reload failure field and preserve exception text below.
        details: _boundedEventText(event.reloadFailureReason),
        pauseAsync: event.atAsyncSuspension,
        frame: _boundedEventText(functionName),
        uri: _boundedEventText(location?.script?.uri),
        line: _nonNegativeNullable(location?.line),
        column: _nonNegativeNullable(location?.column),
        exception: _boundedEventText(exception),
        breakpoint: _nonNegativeNullable(event.breakpoint?.breakpointNumber),
      );
    _debugEvents.add(record);
    try {
      onDebugEvent?.call(record);
    } on Object {
      // An archive sink must not affect VM event delivery.
    }
  }

  static const _rebuildExtension =
      'ext.flutter.inspector.trackRebuildDirtyWidgets';
  static const _rebuiltWidgetsEvent = 'Flutter.RebuiltWidgets';

  Future<void> _subscribeRebuildEvents(VmService service) async {
    final subscription = service.onExtensionEvent.listen(_recordExtensionEvent);
    _extensionSubscription = subscription;
    try {
      await service.streamListen(EventStreams.kExtension).timeout(timeout);
    } on Object catch (error) {
      await subscription.cancel();
      _extensionSubscription = null;
      _recordFailure('rebuild-stream', error);
    }
  }

  Future<void> _prepareRebuildTracking(
    VmService service,
    String isolateId,
  ) async {
    final current = await service
        .callServiceExtension(_rebuildExtension, isolateId: isolateId)
        .timeout(timeout);
    final enabled = _extensionEnabled(current.json?['enabled']);
    if (enabled == null) {
      throw StateError('Flutter rebuild tracking state is unavailable.');
    }
    _rebuildEnabledBefore = enabled;
    if (enabled) return;
    await service
        .callServiceExtension(
          _rebuildExtension,
          isolateId: isolateId,
          args: <String, dynamic>{'enabled': true},
        )
        .timeout(timeout);
    _rebuildChanged = true;
  }

  static bool? _extensionEnabled(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  void _recordExtensionEvent(Event event) {
    if (_windowEnded) return;
    if (event.extensionKind != _rebuiltWidgetsEvent) return;
    final data = event.extensionData?.data;
    if (data == null) return;
    _recordRebuildEvent(data);
  }

  void _recordRebuildEvent(Map<String, dynamic> data) {
    final frameNumber = _intValue(data['frameNumber']);
    final rawEvents = data['events'];
    if (frameNumber == null || rawEvents is! List || rawEvents.length.isOdd) {
      _droppedRebuildFrames += 1;
      return;
    }

    _mergeRebuildLocations(data['locations']);
    final entries = <CockpitRebuildCount>[];
    for (var index = 0; index < rawEvents.length; index += 2) {
      final locationId = _intValue(rawEvents[index]);
      final count = _intValue(rawEvents[index + 1]);
      if (locationId == null || count == null || locationId < 0 || count <= 0) {
        _droppedRebuildEntries += 1;
        continue;
      }
      if (entries.length >= 2000 ||
          _retainedRebuildEntries >= maxRebuildEntries) {
        _droppedRebuildEntries += 1;
        continue;
      }
      _ensureRebuildLocation(locationId);
      entries.add(CockpitRebuildCount(locationId: locationId, count: count));
      _retainedRebuildEntries += 1;
      _rebuildTotals[locationId] = (_rebuildTotals[locationId] ?? 0) + count;
    }

    if (_rebuildFrames.isNotEmpty &&
        frameNumber <= _rebuildFrames.last.frameNumber) {
      if (frameNumber == _rebuildFrames.last.frameNumber) {
        _removeRebuildFrame(_rebuildFrames.removeLast());
      } else {
        _droppedRebuildFrames += 1;
        return;
      }
    }
    if (_rebuildFrames.length >= maxRebuildFrames) {
      _removeRebuildFrame(_rebuildFrames.removeAt(0));
      _droppedRebuildFrames += 1;
    }
    _rebuildFrames.add(
      CockpitRebuildFrame(frameNumber: frameNumber, entries: entries),
    );
  }

  void _removeRebuildFrame(CockpitRebuildFrame frame) {
    _retainedRebuildEntries -= frame.entries.length;
    for (final entry in frame.entries) {
      final current = _rebuildTotals[entry.locationId] ?? 0;
      final next = current - entry.count;
      if (next > 0) {
        _rebuildTotals[entry.locationId] = next;
      } else {
        _rebuildTotals.remove(entry.locationId);
      }
    }
  }

  void _mergeRebuildLocations(Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final uri = entry.key as String;
      final value = Map<Object?, Object?>.from(entry.value as Map);
      final ids = value['ids'];
      final lines = value['lines'];
      final columns = value['columns'];
      final names = value['names'];
      if (ids is! List ||
          lines is! List ||
          columns is! List ||
          names is! List) {
        continue;
      }
      final count = <int>[
        ids.length,
        lines.length,
        columns.length,
        names.length,
      ].reduce((left, right) => left < right ? left : right);
      for (var index = 0; index < count; index += 1) {
        final id = _intValue(ids[index]);
        final line = _intValue(lines[index]);
        final column = _intValue(columns[index]);
        final name = names[index] is String ? (names[index] as String) : null;
        if (id == null ||
            id < 0 ||
            line == null ||
            line < 0 ||
            column == null ||
            column < 0) {
          continue;
        }
        final wasUnresolved = _rebuildLocations[id]?.isResolved != true;
        _rebuildLocations[id] = CockpitRebuildLocation(
          id: id,
          uri: uri,
          line: line,
          column: column,
          name: name,
        );
        if (wasUnresolved && _unresolvedRebuildLocations > 0) {
          _unresolvedRebuildLocations -= 1;
        }
      }
    }
  }

  void _ensureRebuildLocation(int id) {
    if (_rebuildLocations.containsKey(id)) return;
    if (_rebuildLocations.length >= 50000) return;
    _rebuildLocations[id] = CockpitRebuildLocation(id: id);
    _unresolvedRebuildLocations += 1;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.round()) {
      return value.toInt();
    }
    return null;
  }

  Future<CockpitDisplayProfile?> _readDisplayProfile(
    VmService service,
    String isolateId,
  ) async {
    String? viewId;
    try {
      final views = await service
          .callServiceExtension('_flutter.listViews', isolateId: isolateId)
          .timeout(timeout);
      final rawViews = views.json?['views'];
      if (rawViews is List) {
        for (final raw in rawViews) {
          if (raw is Map &&
              raw['type'] == 'FlutterView' &&
              raw['id'] is String &&
              (raw['id'] as String).trim().isNotEmpty) {
            viewId = raw['id'] as String;
            break;
          }
        }
      }
    } catch (_) {
      // The refresh extension can still work without an explicit view id.
    }
    final response = await service
        .callServiceExtension(
          '_flutter.getDisplayRefreshRate',
          isolateId: isolateId,
          args: <String, dynamic>{'viewId': ?viewId},
        )
        .timeout(timeout);
    final fps = response.json?['fps'];
    final refreshRate = fps is num && fps.isFinite && fps > 0
        ? fps.toDouble()
        : fps is String
        ? double.tryParse(fps)
        : null;
    final normalizedRefreshRate =
        refreshRate != null && refreshRate.isFinite && refreshRate > 0
        ? refreshRate
        : null;
    final budget = normalizedRefreshRate == null
        ? null
        : (1000000 / normalizedRefreshRate).round();
    if (normalizedRefreshRate == null && viewId == null) return null;
    return CockpitDisplayProfile(
      refreshRateHz: normalizedRefreshRate,
      frameBudgetUs: budget,
      viewId: viewId,
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
          return _isolateStats(await service.getIsolate(id).timeout(timeout));
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
      final location = _dynamicField(reference, 'location');
      final line = _dynamicInt(location, 'line');
      final column = _dynamicInt(location, 'column');
      final uri =
          _nonEmptyNullable(function.resolvedUrl) ??
          _dynamicString(_dynamicField(location, 'script'), 'uri') ??
          _dynamicString(location, 'uri');
      final name = _dynamicString(reference, 'name') ?? uri ?? '<anonymous>';
      functions.add(
        CockpitCpuFunction(
          name: name,
          kind: function.kind,
          uri: uri,
          line: line == null || line < 1 ? null : line,
          column: column,
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
      accumulatorResetAt: _nonNegativeNullable(raw.dateLastAccumulatorReset),
      serviceGcAt: _nonNegativeNullable(raw.dateLastServiceGC),
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
    if (_windowEnded) return;
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
      if (_windowEnded) return;
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
    if (_windowEnded) return;
    if (_heapSamples.length < maxHeapSamples) {
      _heapSamples.add(sample);
    } else {
      _droppedHeapSamples += 1;
    }
    try {
      onHeapSample?.call(sample);
    } on Object {
      // An archive sink must not affect VM sampling.
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

  CockpitGcProfile? _gc(Iterable<CockpitPerformanceEvent> source) {
    var count = 0;
    var timed = 0;
    var newCount = 0;
    var oldCount = 0;
    var total = 0;
    var newPause = 0;
    var oldPause = 0;
    final durations = <int>[];
    visitCockpitTimelineMeasurements(source, (event, pause, _) {
      final kind = cockpitGcEventKind(event);
      if (kind == null) return;
      count += 1;
      if (kind == 'new') newCount += 1;
      if (kind == 'old') oldCount += 1;
      if (pause <= 0) return;
      timed += 1;
      total += pause;
      durations.add(pause);
      if (kind == 'new') newPause += pause;
      if (kind == 'old') oldPause += pause;
    });
    if (count == 0) return null;
    durations.sort();
    return CockpitGcProfile(
      eventCount: count,
      timedCount: timed,
      newCount: newCount,
      oldCount: oldCount,
      totalPauseUs: total,
      p50PauseUs: _percentile(durations, .5),
      p90PauseUs: _percentile(durations, .9),
      maxPauseUs: durations.isEmpty ? 0 : durations.last,
      newPauseUs: newPause,
      oldPauseUs: oldPause,
    );
  }

  static int _percentile(List<int> values, double ratio) {
    if (values.isEmpty) return 0;
    final index = ((values.length - 1) * ratio).round().clamp(
      0,
      values.length - 1,
    );
    return values[index];
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
    final extensionSubscription = _extensionSubscription;
    final loggingSubscription = _loggingSubscription;
    final debugSubscription = _debugSubscription;
    _isolateSubscription = null;
    _extensionSubscription = null;
    _loggingSubscription = null;
    _debugSubscription = null;
    if (isolateSubscription != null) {
      await isolateSubscription.cancel();
    }
    if (extensionSubscription != null) {
      await extensionSubscription.cancel();
    }
    if (loggingSubscription != null) {
      await loggingSubscription.cancel();
    }
    if (debugSubscription != null) {
      await debugSubscription.cancel();
    }
    if (service != null && isolateId != null && _rebuildChanged) {
      try {
        await service
            .callServiceExtension(
              _rebuildExtension,
              isolateId: isolateId,
              args: <String, dynamic>{'enabled': _rebuildEnabledBefore == true},
            )
            .timeout(timeout);
      } catch (_) {
        // A disconnected VM already stopped tracking; never mask the action.
      }
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
      if (extensionSubscription != null) {
        try {
          await service.streamCancel(EventStreams.kExtension).timeout(timeout);
        } catch (_) {
          // A disconnected VM already stopped the stream.
        }
      }
      if (loggingSubscription != null) {
        try {
          await service.streamCancel(EventStreams.kLogging).timeout(timeout);
        } catch (_) {
          // A disconnected VM already stopped the stream.
        }
      }
      if (debugSubscription != null) {
        try {
          await service.streamCancel(EventStreams.kDebug).timeout(timeout);
        } catch (_) {
          // A disconnected VM already stopped the stream.
        }
      }
    }
    _enabledAllocationClassIds.clear();
    _service = null;
    _isolateId = null;
    _originUs = null;
    _timelineCursorUs = null;
    _streamTimeline = false;
    _beforeHeap = null;
    _vmMemoryBefore = null;
    _vmMemoryAfter = null;
    _rebuildEnabledBefore = null;
    _rebuildChanged = false;
    if (service != null) await service.dispose();
  }

  static String? _dynamicString(Object? value, String field) {
    final raw = _dynamicField(value, field);
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return null;
  }

  static int? _dynamicInt(Object? value, String field) {
    final raw = _dynamicField(value, field);
    if (raw is int && raw >= 0) return raw;
    if (raw is num && raw.isFinite && raw >= 0 && raw == raw.round()) {
      return raw.toInt();
    }
    return null;
  }

  static Object? _dynamicField(Object? value, String field) {
    if (value == null) return null;
    try {
      final result = (value as dynamic)?.toJson();
      if (result is Map && result.containsKey(field)) return result[field];
    } catch (_) {}
    try {
      switch (field) {
        case 'name':
          return (value as dynamic)?.name;
        case 'location':
          return (value as dynamic)?.location;
        case 'script':
          return (value as dynamic)?.script;
        case 'uri':
          return (value as dynamic)?.uri;
        case 'line':
          return (value as dynamic)?.line;
        case 'column':
          return (value as dynamic)?.column;
      }
    } catch (_) {}
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
