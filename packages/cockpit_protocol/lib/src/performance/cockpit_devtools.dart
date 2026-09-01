import 'dart:convert';

/// Bounded projections of the VM data exposed by Flutter DevTools.
///
/// These models intentionally keep the report transport compact while
/// preserving the raw sampling information needed to build a flame view or
/// inspect allocation hot spots. Unsupported data is represented by an
/// explicit state; callers must never interpret an absent metric as zero.
final class CockpitDevToolsProfile {
  CockpitDevToolsProfile({
    required this.source,
    required this.state,
    this.reason,
    this.cpu,
    this.heap,
    this.gc,
    this.gpu,
    this.isolate,
    this.timeline,
    this.display,
    this.rebuild,
    this.vm,
    this.vmMemory,
    Iterable<CockpitAllocationTrace> allocationTraces =
        const <CockpitAllocationTrace>[],
    Iterable<CockpitVmLogEvent> logs = const <CockpitVmLogEvent>[],
    Iterable<CockpitVmDebugEvent> debug = const <CockpitVmDebugEvent>[],
    this.droppedLogs = 0,
    this.droppedDebug = 0,
    this.perfetto,
  }) : allocationTraces = List<CockpitAllocationTrace>.unmodifiable(
         allocationTraces,
       ),
       logs = List<CockpitVmLogEvent>.unmodifiable(logs),
       debug = List<CockpitVmDebugEvent>.unmodifiable(debug) {
    if (source.trim().isEmpty || state.trim().isEmpty) {
      throw const FormatException('DevTools profile identity is invalid.');
    }
    if (reason != null && reason!.trim().isEmpty) {
      throw const FormatException('DevTools profile reason is invalid.');
    }
    if (this.allocationTraces.length > 20) {
      throw const FormatException('Allocation trace count is bounded.');
    }
    if (this.logs.length > 2000 || this.debug.length > 2000) {
      throw const FormatException('VM event count is bounded.');
    }
    if (droppedLogs < 0 || droppedDebug < 0) {
      throw const FormatException('VM event drop counts are invalid.');
    }
  }

  final String source;
  final String state;
  final String? reason;
  final CockpitCpuProfile? cpu;
  final CockpitHeapProfile? heap;
  final CockpitGcProfile? gc;
  final CockpitGpuProfile? gpu;
  final CockpitIsolateProfile? isolate;
  final CockpitTimelineProfile? timeline;
  final CockpitDisplayProfile? display;
  final CockpitRebuildProfile? rebuild;
  final CockpitVmRuntimeProfile? vm;
  final CockpitVmMemoryProfile? vmMemory;
  final List<CockpitAllocationTrace> allocationTraces;
  final List<CockpitVmLogEvent> logs;
  final List<CockpitVmDebugEvent> debug;
  final int droppedLogs;
  final int droppedDebug;
  final CockpitPerfettoProfile? perfetto;

  CockpitDevToolsProfile copyWith({
    CockpitCpuProfile? cpu,
    CockpitHeapProfile? heap,
    CockpitGcProfile? gc,
    CockpitGpuProfile? gpu,
    CockpitIsolateProfile? isolate,
    CockpitTimelineProfile? timeline,
    CockpitDisplayProfile? display,
    CockpitRebuildProfile? rebuild,
    CockpitVmRuntimeProfile? vm,
    CockpitVmMemoryProfile? vmMemory,
    Iterable<CockpitAllocationTrace>? allocationTraces,
    Iterable<CockpitVmLogEvent>? logs,
    Iterable<CockpitVmDebugEvent>? debug,
    int? droppedLogs,
    int? droppedDebug,
    CockpitPerfettoProfile? perfetto,
  }) => CockpitDevToolsProfile(
    source: source,
    state: state,
    reason: reason,
    cpu: cpu ?? this.cpu,
    heap: heap ?? this.heap,
    gc: gc ?? this.gc,
    gpu: gpu ?? this.gpu,
    isolate: isolate ?? this.isolate,
    timeline: timeline ?? this.timeline,
    display: display ?? this.display,
    rebuild: rebuild ?? this.rebuild,
    vm: vm ?? this.vm,
    vmMemory: vmMemory ?? this.vmMemory,
    allocationTraces: allocationTraces ?? this.allocationTraces,
    logs: logs ?? this.logs,
    debug: debug ?? this.debug,
    droppedLogs: droppedLogs ?? this.droppedLogs,
    droppedDebug: droppedDebug ?? this.droppedDebug,
    perfetto: perfetto ?? this.perfetto,
  );

  Map<String, Object?> toJson({bool includeRaw = false}) => <String, Object?>{
    'source': source,
    'state': state,
    if (reason != null && reason!.trim().isNotEmpty) 'why': reason,
    if (cpu != null) 'cpu': cpu!.toJson(includeRaw: includeRaw),
    if (heap != null) 'heap': heap!.toJson(),
    if (gc != null) 'gc': gc!.toJson(),
    if (gpu != null) 'gpu': gpu!.toJson(),
    if (isolate != null) 'isolate': isolate!.toJson(),
    if (timeline != null) 'timeline': timeline!.toJson(),
    if (display != null) 'display': display!.toJson(),
    if (rebuild != null) 'rebuild': rebuild!.toJson(),
    if (vm != null) 'vm': vm!.toJson(),
    if (vmMemory != null) 'vmem': vmMemory!.toJson(),
    if (allocationTraces.isNotEmpty)
      'alloc': allocationTraces
          .map((item) => item.toJson(includeRaw: includeRaw))
          .toList(growable: false),
    if (logs.isNotEmpty)
      'log': logs.map((item) => item.toJson()).toList(growable: false),
    if (debug.isNotEmpty)
      'dbg': debug.map((item) => item.toJson()).toList(growable: false),
    if (droppedLogs > 0) 'dropLog': droppedLogs,
    if (droppedDebug > 0) 'dropDbg': droppedDebug,
    if (perfetto != null) 'perfetto': perfetto!.toJson(includeRaw: includeRaw),
  };

  factory CockpitDevToolsProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools');
    return CockpitDevToolsProfile(
      source: _string(json['source'], r'$.devtools.source'),
      state: _string(json['state'], r'$.devtools.state'),
      reason: _optionalString(json['why'], r'$.devtools.why'),
      cpu: json['cpu'] == null ? null : CockpitCpuProfile.fromJson(json['cpu']),
      heap: json['heap'] == null
          ? null
          : CockpitHeapProfile.fromJson(json['heap']),
      gc: json['gc'] == null ? null : CockpitGcProfile.fromJson(json['gc']),
      gpu: json['gpu'] == null ? null : CockpitGpuProfile.fromJson(json['gpu']),
      isolate: json['isolate'] == null
          ? null
          : CockpitIsolateProfile.fromJson(json['isolate']),
      timeline: json['timeline'] == null
          ? null
          : CockpitTimelineProfile.fromJson(json['timeline']),
      display: json['display'] == null
          ? null
          : CockpitDisplayProfile.fromJson(json['display']),
      rebuild: json['rebuild'] == null
          ? null
          : CockpitRebuildProfile.fromJson(json['rebuild']),
      vm: json['vm'] == null
          ? null
          : CockpitVmRuntimeProfile.fromJson(json['vm']),
      vmMemory: json['vmem'] == null
          ? null
          : CockpitVmMemoryProfile.fromJson(json['vmem']),
      allocationTraces: json['alloc'] == null
          ? const <CockpitAllocationTrace>[]
          : _list(
              json['alloc'],
              r'$.devtools.alloc',
            ).map(CockpitAllocationTrace.fromJson).toList(growable: false),
      logs: json['log'] == null
          ? const <CockpitVmLogEvent>[]
          : _list(
              json['log'],
              r'$.devtools.log',
            ).map(CockpitVmLogEvent.fromJson).toList(growable: false),
      debug: json['dbg'] == null
          ? const <CockpitVmDebugEvent>[]
          : _list(
              json['dbg'],
              r'$.devtools.dbg',
            ).map(CockpitVmDebugEvent.fromJson).toList(growable: false),
      droppedLogs: json['dropLog'] == null
          ? 0
          : _nonNegativeInt(json['dropLog'], r'$.devtools.dropLog'),
      droppedDebug: json['dropDbg'] == null
          ? 0
          : _nonNegativeInt(json['dropDbg'], r'$.devtools.dropDbg'),
      perfetto: json['perfetto'] == null
          ? null
          : CockpitPerfettoProfile.fromJson(json['perfetto']),
    );
  }
}

/// Allocation call-stack samples for one explicitly selected VM class.
///
/// DevTools enables this expensive stream only for classes the user selects.
/// Cockpit follows the same rule: no class is traced unless its VM class id is
/// passed to the profiling call.
final class CockpitAllocationTrace {
  CockpitAllocationTrace({
    required this.classId,
    required this.profile,
    this.className,
  }) {
    if (classId.trim().isEmpty ||
        className != null && className!.trim().isEmpty) {
      throw const FormatException('Allocation trace identity is invalid.');
    }
  }

  final String classId;
  final String? className;
  final CockpitCpuProfile profile;

  Map<String, Object?> toJson({bool includeRaw = true}) => <String, Object?>{
    'id': classId,
    if (className != null) 'name': className,
    'trace': profile.toJson(includeRaw: includeRaw),
  };

  factory CockpitAllocationTrace.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.alloc[]');
    return CockpitAllocationTrace(
      classId: _string(json['id'], r'$.devtools.alloc[].id'),
      className: _optionalString(json['name'], r'$.devtools.alloc[].name'),
      profile: CockpitCpuProfile.fromJson(json['trace']),
    );
  }
}

/// One bounded Dart VM logging-stream record.
///
/// Message, error, and stack text is copied only when the VM already includes
/// a value in the event. Cockpit never performs an additional object fetch for
/// a log record, so collecting this stream cannot unexpectedly stall the
/// profiled action.
final class CockpitVmLogEvent {
  const CockpitVmLogEvent({
    this.timestampMs,
    this.level,
    this.sequence,
    this.message,
    this.logger,
    this.zone,
    this.error,
    this.stack,
    this.isolateId,
  });

  final int? timestampMs;
  final int? level;
  final int? sequence;
  final String? message;
  final String? logger;
  final String? zone;
  final String? error;
  final String? stack;
  final String? isolateId;

  bool get isValid =>
      (timestampMs == null || timestampMs! >= 0) &&
      (level == null || level! >= 0) &&
      (sequence == null || sequence! >= 0) &&
      _validText(message) &&
      _validText(logger) &&
      _validText(zone) &&
      _validText(error) &&
      _validText(stack) &&
      _validText(isolateId);

  Map<String, Object?> toJson() => <String, Object?>{
    if (timestampMs != null) 't': timestampMs,
    if (level != null) 'lvl': level,
    if (sequence != null) 'seq': sequence,
    if (message != null && message!.isNotEmpty) 'msg': message,
    if (logger != null && logger!.isNotEmpty) 'logger': logger,
    if (zone != null && zone!.isNotEmpty) 'zone': zone,
    if (error != null && error!.isNotEmpty) 'err': error,
    if (stack != null && stack!.isNotEmpty) 'stack': stack,
    if (isolateId != null && isolateId!.isNotEmpty) 'iso': isolateId,
  };

  factory CockpitVmLogEvent.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.log[]');
    final event = CockpitVmLogEvent(
      timestampMs: json['t'] == null
          ? null
          : _nonNegativeInt(json['t'], r'$.devtools.log[].t'),
      level: json['lvl'] == null
          ? null
          : _nonNegativeInt(json['lvl'], r'$.devtools.log[].lvl'),
      sequence: json['seq'] == null
          ? null
          : _nonNegativeInt(json['seq'], r'$.devtools.log[].seq'),
      message: _optionalBoundedString(json['msg'], r'$.devtools.log[].msg'),
      logger: _optionalBoundedString(
        json['logger'],
        r'$.devtools.log[].logger',
      ),
      zone: _optionalBoundedString(json['zone'], r'$.devtools.log[].zone'),
      error: _optionalBoundedString(json['err'], r'$.devtools.log[].err'),
      stack: _optionalBoundedString(json['stack'], r'$.devtools.log[].stack'),
      isolateId: _optionalBoundedString(json['iso'], r'$.devtools.log[].iso'),
    );
    if (!event.isValid) {
      throw const FormatException('VM log event is invalid.');
    }
    return event;
  }
}

/// One bounded VM debug-stream event with the source context already present
/// in the notification. This is intentionally metadata-only; variable and
/// object evaluation remains an explicit debugger operation.
final class CockpitVmDebugEvent {
  const CockpitVmDebugEvent({
    required this.kind,
    this.timestampMs,
    this.isolateId,
    this.isolateName,
    this.status,
    this.details,
    this.pauseAsync,
    this.frame,
    this.uri,
    this.line,
    this.column,
    this.exception,
    this.breakpoint,
  });

  final String kind;
  final int? timestampMs;
  final String? isolateId;
  final String? isolateName;
  final String? status;
  final String? details;
  final bool? pauseAsync;
  final String? frame;
  final String? uri;
  final int? line;
  final int? column;
  final String? exception;
  final int? breakpoint;

  bool get isValid =>
      kind.trim().isNotEmpty &&
      kind.length <= 256 &&
      (timestampMs == null || timestampMs! >= 0) &&
      (line == null || line! >= 0) &&
      (column == null || column! >= 0) &&
      (breakpoint == null || breakpoint! >= 0) &&
      _validText(isolateId) &&
      _validText(isolateName) &&
      _validText(status) &&
      _validText(details) &&
      _validText(frame) &&
      _validText(uri) &&
      _validText(exception);

  Map<String, Object?> toJson() => <String, Object?>{
    'k': kind,
    if (timestampMs != null) 't': timestampMs,
    if (isolateId != null && isolateId!.isNotEmpty) 'iso': isolateId,
    if (isolateName != null && isolateName!.isNotEmpty) 'name': isolateName,
    if (status != null && status!.isNotEmpty) 'status': status,
    if (details != null && details!.isNotEmpty) 'details': details,
    if (pauseAsync != null) 'async': pauseAsync,
    if (frame != null && frame!.isNotEmpty) 'fn': frame,
    if (uri != null && uri!.isNotEmpty) 'uri': uri,
    if (line != null) 'line': line,
    if (column != null) 'col': column,
    if (exception != null && exception!.isNotEmpty) 'err': exception,
    if (breakpoint != null) 'bp': breakpoint,
  };

  factory CockpitVmDebugEvent.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.dbg[]');
    final event = CockpitVmDebugEvent(
      kind: _boundedString(json['k'], r'$.devtools.dbg[].k'),
      timestampMs: json['t'] == null
          ? null
          : _nonNegativeInt(json['t'], r'$.devtools.dbg[].t'),
      isolateId: _optionalBoundedString(json['iso'], r'$.devtools.dbg[].iso'),
      isolateName: _optionalBoundedString(
        json['name'],
        r'$.devtools.dbg[].name',
      ),
      status: _optionalBoundedString(
        json['status'],
        r'$.devtools.dbg[].status',
      ),
      details: _optionalBoundedString(
        json['details'],
        r'$.devtools.dbg[].details',
      ),
      pauseAsync: json['async'] == null
          ? null
          : _bool(json['async'], r'$.devtools.dbg[].async'),
      frame: _optionalBoundedString(json['fn'], r'$.devtools.dbg[].fn'),
      uri: _optionalBoundedString(json['uri'], r'$.devtools.dbg[].uri'),
      line: json['line'] == null
          ? null
          : _nonNegativeInt(json['line'], r'$.devtools.dbg[].line'),
      column: json['col'] == null
          ? null
          : _nonNegativeInt(json['col'], r'$.devtools.dbg[].col'),
      exception: _optionalBoundedString(json['err'], r'$.devtools.dbg[].err'),
      breakpoint: json['bp'] == null
          ? null
          : _nonNegativeInt(json['bp'], r'$.devtools.dbg[].bp'),
    );
    if (!event.isValid) {
      throw const FormatException('VM debug event is invalid.');
    }
    return event;
  }
}

/// Perfetto trace metadata returned by the VM Service, with optional raw data.
///
/// The base64 payload is deliberately omitted from normal [toJson] output and
/// included only by complete exports. This keeps integration-test result
/// transport compact while preserving an exact trace for offline analysis.
final class CockpitPerfettoTrace {
  CockpitPerfettoTrace({
    required this.kind,
    this.data,
    required this.originUs,
    required this.extentUs,
    this.samplePeriodUs,
    this.maxStackDepth,
    this.sampleCount,
    this.pid,
  }) {
    if (kind != 'cpu' && kind != 'timeline' ||
        data != null &&
            (data!.trim().isEmpty || data!.length > 64 * 1024 * 1024) ||
        originUs < 0 ||
        extentUs < 0 ||
        samplePeriodUs != null && samplePeriodUs! < 0 ||
        maxStackDepth != null && maxStackDepth! < 0 ||
        sampleCount != null && sampleCount! < 0 ||
        pid != null && pid! < 0) {
      throw const FormatException('Perfetto trace is invalid or too large.');
    }
    if (data != null) {
      try {
        base64Decode(data!);
      } on FormatException {
        throw const FormatException('Perfetto trace payload is not base64.');
      }
    }
  }

  final String kind;

  /// Base64 Perfetto bytes. Compact reports intentionally omit this value;
  /// complete exports retain it for offline viewers.
  final String? data;
  final int originUs;
  final int extentUs;
  final int? samplePeriodUs;
  final int? maxStackDepth;
  final int? sampleCount;
  final int? pid;

  Map<String, Object?> toJson({bool includeRaw = false}) => <String, Object?>{
    'kind': kind,
    'start': originUs,
    'span': extentUs,
    if (samplePeriodUs != null) 'period': samplePeriodUs,
    if (maxStackDepth != null) 'depth': maxStackDepth,
    if (sampleCount != null) 'n': sampleCount,
    if (pid != null) 'pid': pid,
    if (includeRaw && data != null) 'data': data,
  };

  factory CockpitPerfettoTrace.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.perfetto.trace');
    return CockpitPerfettoTrace(
      kind: _string(json['kind'], r'$.devtools.perfetto.trace.kind'),
      data: _optionalString(json['data'], r'$.devtools.perfetto.trace.data'),
      originUs: _nonNegativeInt(
        json['start'],
        r'$.devtools.perfetto.trace.start',
      ),
      extentUs: _nonNegativeInt(
        json['span'],
        r'$.devtools.perfetto.trace.span',
      ),
      samplePeriodUs: json['period'] == null
          ? null
          : _nonNegativeInt(
              json['period'],
              r'$.devtools.perfetto.trace.period',
            ),
      maxStackDepth: json['depth'] == null
          ? null
          : _nonNegativeInt(json['depth'], r'$.devtools.perfetto.trace.depth'),
      sampleCount: json['n'] == null
          ? null
          : _nonNegativeInt(json['n'], r'$.devtools.perfetto.trace.n'),
      pid: json['pid'] == null
          ? null
          : _nonNegativeInt(json['pid'], r'$.devtools.perfetto.trace.pid'),
    );
  }
}

/// Optional raw CPU and VM timeline traces in Perfetto's proto format.
final class CockpitPerfettoProfile {
  const CockpitPerfettoProfile({this.cpu, this.timeline});

  final CockpitPerfettoTrace? cpu;
  final CockpitPerfettoTrace? timeline;

  bool get isEmpty => cpu == null && timeline == null;

  Map<String, Object?> toJson({bool includeRaw = false}) => <String, Object?>{
    if (cpu != null) 'cpu': cpu!.toJson(includeRaw: includeRaw),
    if (timeline != null) 'timeline': timeline!.toJson(includeRaw: includeRaw),
  };

  factory CockpitPerfettoProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.perfetto');
    return CockpitPerfettoProfile(
      cpu: json['cpu'] == null
          ? null
          : CockpitPerfettoTrace.fromJson(json['cpu']),
      timeline: json['timeline'] == null
          ? null
          : CockpitPerfettoTrace.fromJson(json['timeline']),
    );
  }
}

/// VM-level runtime identity and isolate inventory captured from VM Service.
///
/// These values are descriptive evidence only. A missing VM field remains
/// absent instead of being replaced with a guessed value.
final class CockpitVmRuntimeProfile {
  CockpitVmRuntimeProfile({
    this.name,
    this.version,
    this.operatingSystem,
    this.hostCpu,
    this.targetCpu,
    this.architectureBits,
    this.pid,
    this.startTimeMs,
    this.isolateCount,
    this.isolateGroupCount,
    this.systemIsolateCount,
    Iterable<String> extensions = const <String>[],
  }) : extensions = List<String>.unmodifiable(extensions) {
    if (architectureBits != null && architectureBits! <= 0 ||
        pid != null && pid! < 0 ||
        startTimeMs != null && startTimeMs! < 0 ||
        isolateCount != null && isolateCount! < 0 ||
        isolateGroupCount != null && isolateGroupCount! < 0 ||
        systemIsolateCount != null && systemIsolateCount! < 0 ||
        this.extensions.length > 500) {
      throw const FormatException('VM runtime profile bounds are invalid.');
    }
  }

  final String? name;
  final String? version;
  final String? operatingSystem;
  final String? hostCpu;
  final String? targetCpu;
  final int? architectureBits;
  final int? pid;
  final int? startTimeMs;
  final int? isolateCount;
  final int? isolateGroupCount;
  final int? systemIsolateCount;
  final List<String> extensions;

  Map<String, Object?> toJson() => <String, Object?>{
    if (name != null && name!.trim().isNotEmpty) 'name': name,
    if (version != null && version!.trim().isNotEmpty) 'ver': version,
    if (operatingSystem != null && operatingSystem!.trim().isNotEmpty)
      'os': operatingSystem,
    if (hostCpu != null && hostCpu!.trim().isNotEmpty) 'host': hostCpu,
    if (targetCpu != null && targetCpu!.trim().isNotEmpty) 'target': targetCpu,
    if (architectureBits != null) 'arch': architectureBits,
    if (pid != null) 'pid': pid,
    if (startTimeMs != null) 'start': startTimeMs,
    if (isolateCount != null) 'isolates': isolateCount,
    if (isolateGroupCount != null) 'groups': isolateGroupCount,
    if (systemIsolateCount != null) 'sys': systemIsolateCount,
    if (extensions.isNotEmpty) 'ext': extensions,
  };

  factory CockpitVmRuntimeProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.vm');
    return CockpitVmRuntimeProfile(
      name: _optionalString(json['name'], r'$.devtools.vm.name'),
      version: _optionalString(json['ver'], r'$.devtools.vm.ver'),
      operatingSystem: _optionalString(json['os'], r'$.devtools.vm.os'),
      hostCpu: _optionalString(json['host'], r'$.devtools.vm.host'),
      targetCpu: _optionalString(json['target'], r'$.devtools.vm.target'),
      architectureBits: json['arch'] == null
          ? null
          : _positiveInt(json['arch'], r'$.devtools.vm.arch'),
      pid: json['pid'] == null
          ? null
          : _nonNegativeInt(json['pid'], r'$.devtools.vm.pid'),
      startTimeMs: json['start'] == null
          ? null
          : _nonNegativeInt(json['start'], r'$.devtools.vm.start'),
      isolateCount: json['isolates'] == null
          ? null
          : _nonNegativeInt(json['isolates'], r'$.devtools.vm.isolates'),
      isolateGroupCount: json['groups'] == null
          ? null
          : _nonNegativeInt(json['groups'], r'$.devtools.vm.groups'),
      systemIsolateCount: json['sys'] == null
          ? null
          : _nonNegativeInt(json['sys'], r'$.devtools.vm.sys'),
      extensions: _strings(json['ext'], r'$.devtools.vm.ext'),
    );
  }
}

/// One bounded node from VM Service process-memory accounting.
final class CockpitVmMemoryNode {
  CockpitVmMemoryNode({
    required this.name,
    required this.sizeBytes,
    Iterable<CockpitVmMemoryNode> children = const <CockpitVmMemoryNode>[],
    this.droppedChildren = 0,
  }) : children = List<CockpitVmMemoryNode>.unmodifiable(children) {
    if (name.trim().isEmpty ||
        sizeBytes < 0 ||
        droppedChildren < 0 ||
        this.children.length > 64 ||
        nodeCount > 512 ||
        maxDepth > 8) {
      throw const FormatException('VM memory node bounds are invalid.');
    }
    if (this.children.any((child) => child.sizeBytes > sizeBytes)) {
      throw const FormatException('VM memory child exceeds its parent.');
    }
  }

  final String name;
  final int sizeBytes;
  final List<CockpitVmMemoryNode> children;
  final int droppedChildren;

  int get nodeCount =>
      1 + children.fold<int>(0, (sum, child) => sum + child.nodeCount);

  int get maxDepth => children.isEmpty
      ? 1
      : 1 +
            children
                .map((child) => child.maxDepth)
                .reduce((a, b) => a > b ? a : b);

  Map<String, Object?> toJson() => <String, Object?>{
    'n': name,
    's': sizeBytes,
    if (children.isNotEmpty)
      'c': children.map((child) => child.toJson()).toList(growable: false),
    if (droppedChildren > 0) 'drop': droppedChildren,
  };

  factory CockpitVmMemoryNode.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.vmem.node');
    final rawChildren = json['c'];
    return CockpitVmMemoryNode(
      name: _string(json['n'], r'$.devtools.vmem.node.n'),
      sizeBytes: _nonNegativeInt(json['s'], r'$.devtools.vmem.node.s'),
      children: rawChildren == null
          ? const <CockpitVmMemoryNode>[]
          : _list(
              rawChildren,
              r'$.devtools.vmem.node.c',
            ).map(CockpitVmMemoryNode.fromJson).toList(growable: false),
      droppedChildren: json['drop'] == null
          ? 0
          : _nonNegativeInt(json['drop'], r'$.devtools.vmem.node.drop'),
    );
  }
}

/// One timestamped process-memory snapshot from VM Service.
final class CockpitVmMemorySnapshot {
  const CockpitVmMemorySnapshot({
    required this.timestampUs,
    required this.root,
  });

  final int timestampUs;
  final CockpitVmMemoryNode root;

  Map<String, Object?> toJson() => <String, Object?>{
    't': timestampUs,
    'root': root.toJson(),
  };

  factory CockpitVmMemorySnapshot.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.vmem.snapshot');
    return CockpitVmMemorySnapshot(
      timestampUs: _nonNegativeInt(json['t'], r'$.devtools.vmem.snapshot.t'),
      root: CockpitVmMemoryNode.fromJson(json['root']),
    );
  }
}

/// Before/after process-memory accounting captured from VM Service.
final class CockpitVmMemoryProfile {
  const CockpitVmMemoryProfile({this.before, this.after});

  final CockpitVmMemorySnapshot? before;
  final CockpitVmMemorySnapshot? after;

  Map<String, Object?> toJson() => <String, Object?>{
    if (before != null) 'before': before!.toJson(),
    if (after != null) 'after': after!.toJson(),
  };

  factory CockpitVmMemoryProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.vmem');
    return CockpitVmMemoryProfile(
      before: json['before'] == null
          ? null
          : CockpitVmMemorySnapshot.fromJson(json['before']),
      after: json['after'] == null
          ? null
          : CockpitVmMemorySnapshot.fromJson(json['after']),
    );
  }
}

final class CockpitCpuFunction {
  const CockpitCpuFunction({
    required this.name,
    required this.inclusiveTicks,
    required this.exclusiveTicks,
    this.kind,
    this.uri,
    this.line,
    this.column,
  });

  final String name;
  final int inclusiveTicks;
  final int exclusiveTicks;
  final String? kind;
  final String? uri;
  final int? line;
  final int? column;

  Map<String, Object?> toJson() => <String, Object?>{
    'n': name,
    'in': inclusiveTicks,
    'ex': exclusiveTicks,
    if (kind != null && kind!.trim().isNotEmpty) 'k': kind,
    if (uri != null && uri!.trim().isNotEmpty) 'u': uri,
    if (line != null) 'l': line,
    if (column != null) 'c': column,
  };

  factory CockpitCpuFunction.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.cpu.fn');
    return CockpitCpuFunction(
      name: _string(json['n'], r'$.devtools.cpu.fn.n'),
      inclusiveTicks: _nonNegativeInt(json['in'], r'$.devtools.cpu.fn.in'),
      exclusiveTicks: _nonNegativeInt(json['ex'], r'$.devtools.cpu.fn.ex'),
      kind: _optionalString(json['k'], r'$.devtools.cpu.fn.k'),
      uri: _optionalString(json['u'], r'$.devtools.cpu.fn.u'),
      line: json['l'] == null
          ? null
          : _positiveInt(json['l'], r'$.devtools.cpu.fn.l'),
      column: json['c'] == null
          ? null
          : _nonNegativeInt(json['c'], r'$.devtools.cpu.fn.c'),
    );
  }
}

final class CockpitCpuSample {
  const CockpitCpuSample({
    required this.timestampUs,
    required this.stack,
    this.threadId,
    this.vmTag,
    this.userTag,
    this.truncated = false,
  });

  final int timestampUs;
  final int? threadId;
  final List<int> stack;
  final String? vmTag;
  final String? userTag;
  final bool truncated;

  Map<String, Object?> toJson() => <String, Object?>{
    't': timestampUs,
    if (threadId != null) 'tid': threadId,
    if (stack.isNotEmpty) 's': stack,
    if (vmTag != null && vmTag!.trim().isNotEmpty) 'vm': vmTag,
    if (userTag != null && userTag!.trim().isNotEmpty) 'user': userTag,
    if (truncated) 'trunc': true,
  };

  factory CockpitCpuSample.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.cpu.sample');
    final rawStack = json['s'];
    final stack = rawStack == null
        ? const <int>[]
        : _list(rawStack, r'$.devtools.cpu.sample.s')
              .map(
                (item) => _nonNegativeInt(item, r'$.devtools.cpu.sample.s[]'),
              )
              .toList(growable: false);
    return CockpitCpuSample(
      timestampUs: _nonNegativeInt(json['t'], r'$.devtools.cpu.sample.t'),
      threadId: json['tid'] == null
          ? null
          : _nonNegativeInt(json['tid'], r'$.devtools.cpu.sample.tid'),
      stack: List<int>.unmodifiable(stack),
      vmTag: _optionalString(json['vm'], r'$.devtools.cpu.sample.vm'),
      userTag: _optionalString(json['user'], r'$.devtools.cpu.sample.user'),
      truncated: json['trunc'] == true,
    );
  }
}

final class CockpitCpuProfile {
  CockpitCpuProfile({
    required this.samplePeriodUs,
    required this.maxStackDepth,
    required this.sampleCount,
    required this.timeOriginUs,
    required this.timeExtentUs,
    required this.functions,
    required this.samples,
    this.pid,
    this.droppedSamples = 0,
  }) {
    if (samplePeriodUs < 0 ||
        maxStackDepth < 0 ||
        sampleCount < 0 ||
        timeOriginUs < 0 ||
        timeExtentUs < 0 ||
        pid != null && pid! < 0 ||
        droppedSamples < 0 ||
        sampleCount < samples.length ||
        // VM service can legitimately return tens of thousands of function
        // entries for a long-lived profile. Keep the transport bounded while
        // preserving the stack indexes returned by the VM.
        functions.length > 50000 ||
        samples.length > 50000) {
      throw const FormatException('CPU profile bounds are invalid.');
    }
    if (samples.any((sample) => sample.timestampUs < timeOriginUs)) {
      throw const FormatException('CPU sample timestamp is outside profile.');
    }
  }

  final int samplePeriodUs;
  final int maxStackDepth;
  final int sampleCount;
  final int timeOriginUs;
  final int timeExtentUs;
  final int? pid;
  final List<CockpitCpuFunction> functions;
  final List<CockpitCpuSample> samples;
  final int droppedSamples;

  Map<String, Object?> toJson({bool includeRaw = true}) => <String, Object?>{
    'period': samplePeriodUs,
    'depth': maxStackDepth,
    'n': sampleCount,
    'start': timeOriginUs,
    'span': timeExtentUs,
    if (pid != null) 'pid': pid,
    if (includeRaw && functions.isNotEmpty)
      'f': functions.map((item) => item.toJson()).toList(growable: false),
    if (includeRaw && samples.isNotEmpty)
      's': samples.map((item) => item.toJson()).toList(growable: false),
    if (droppedSamples > 0) 'dropped': droppedSamples,
  };

  factory CockpitCpuProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.cpu');
    final rawFunctions = json['f'];
    final rawSamples = json['s'];
    return CockpitCpuProfile(
      samplePeriodUs: _nonNegativeInt(json['period'], r'$.devtools.cpu.period'),
      maxStackDepth: _nonNegativeInt(json['depth'], r'$.devtools.cpu.depth'),
      sampleCount: _nonNegativeInt(json['n'], r'$.devtools.cpu.n'),
      timeOriginUs: _nonNegativeInt(json['start'], r'$.devtools.cpu.start'),
      timeExtentUs: _nonNegativeInt(json['span'], r'$.devtools.cpu.span'),
      pid: json['pid'] == null
          ? null
          : _nonNegativeInt(json['pid'], r'$.devtools.cpu.pid'),
      functions: rawFunctions == null
          ? const <CockpitCpuFunction>[]
          : _list(
              rawFunctions,
              r'$.devtools.cpu.f',
            ).map(CockpitCpuFunction.fromJson).toList(growable: false),
      samples: rawSamples == null
          ? const <CockpitCpuSample>[]
          : _list(
              rawSamples,
              r'$.devtools.cpu.s',
            ).map(CockpitCpuSample.fromJson).toList(growable: false),
      droppedSamples: json['dropped'] == null
          ? 0
          : _nonNegativeInt(json['dropped'], r'$.devtools.cpu.dropped'),
    );
  }
}

final class CockpitHeapPoint {
  const CockpitHeapPoint({
    required this.usageBytes,
    required this.capacityBytes,
    required this.externalBytes,
  });

  final int usageBytes;
  final int capacityBytes;
  final int externalBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'use': usageBytes,
    'cap': capacityBytes,
    'ext': externalBytes,
  };

  factory CockpitHeapPoint.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.heap.point');
    return CockpitHeapPoint(
      usageBytes: _nonNegativeInt(json['use'], r'$.devtools.heap.point.use'),
      capacityBytes: _nonNegativeInt(json['cap'], r'$.devtools.heap.point.cap'),
      externalBytes: _nonNegativeInt(json['ext'], r'$.devtools.heap.point.ext'),
    );
  }
}

final class CockpitHeapClass {
  const CockpitHeapClass({
    required this.name,
    required this.currentBytes,
    required this.currentInstances,
    required this.accumulatedBytes,
    required this.accumulatedInstances,
    this.id,
    this.library,
  });

  final String name;
  final String? id;
  final String? library;
  final int currentBytes;
  final int currentInstances;
  final int accumulatedBytes;
  final int accumulatedInstances;

  Map<String, Object?> toJson() => <String, Object?>{
    'n': name,
    if (id != null && id!.trim().isNotEmpty) 'id': id,
    if (library != null && library!.trim().isNotEmpty) 'lib': library,
    'bytes': currentBytes,
    'count': currentInstances,
    'allocBytes': accumulatedBytes,
    'allocCount': accumulatedInstances,
  };

  factory CockpitHeapClass.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.heap.class');
    return CockpitHeapClass(
      name: _string(json['n'], r'$.devtools.heap.class.n'),
      id: _optionalString(json['id'], r'$.devtools.heap.class.id'),
      library: _optionalString(json['lib'], r'$.devtools.heap.class.lib'),
      currentBytes: _nonNegativeInt(
        json['bytes'],
        r'$.devtools.heap.class.bytes',
      ),
      currentInstances: _nonNegativeInt(
        json['count'],
        r'$.devtools.heap.class.count',
      ),
      accumulatedBytes: _nonNegativeInt(
        json['allocBytes'],
        r'$.devtools.heap.class.allocBytes',
      ),
      accumulatedInstances: _nonNegativeInt(
        json['allocCount'],
        r'$.devtools.heap.class.allocCount',
      ),
    );
  }
}

/// One VM heap usage sample captured during a performance interval.
final class CockpitHeapSample {
  const CockpitHeapSample({
    required this.timestampUs,
    required this.usageBytes,
    required this.capacityBytes,
    required this.externalBytes,
  });

  final int timestampUs;
  final int usageBytes;
  final int capacityBytes;
  final int externalBytes;

  bool get isValid =>
      timestampUs >= 0 &&
      usageBytes >= 0 &&
      capacityBytes >= usageBytes &&
      externalBytes >= 0;

  Map<String, Object?> toJson() => <String, Object?>{
    't': timestampUs,
    'use': usageBytes,
    'cap': capacityBytes,
    'ext': externalBytes,
  };

  factory CockpitHeapSample.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.heap.sample');
    final sample = CockpitHeapSample(
      timestampUs: _nonNegativeInt(json['t'], r'$.devtools.heap.sample.t'),
      usageBytes: _nonNegativeInt(json['use'], r'$.devtools.heap.sample.use'),
      capacityBytes: _nonNegativeInt(
        json['cap'],
        r'$.devtools.heap.sample.cap',
      ),
      externalBytes: _nonNegativeInt(
        json['ext'],
        r'$.devtools.heap.sample.ext',
      ),
    );
    if (!sample.isValid) {
      throw const FormatException('Heap sample is inconsistent.');
    }
    return sample;
  }
}

final class CockpitHeapProfile {
  CockpitHeapProfile({
    required this.before,
    required this.after,
    required Iterable<CockpitHeapClass> classes,
    this.droppedClasses = 0,
    this.intervalMs = 0,
    Iterable<CockpitHeapSample> samples = const <CockpitHeapSample>[],
    this.droppedSamples = 0,
    this.groupBefore,
    this.groupAfter,
    this.accumulatorResetAt,
    this.serviceGcAt,
  }) : classes = List<CockpitHeapClass>.unmodifiable(classes),
       samples = List<CockpitHeapSample>.unmodifiable(samples) {
    if (droppedClasses < 0 ||
        droppedSamples < 0 ||
        this.classes.length > 1000 ||
        this.samples.length > 10000 ||
        intervalMs < 0 ||
        (this.samples.isNotEmpty && intervalMs < 1)) {
      throw const FormatException('Heap profile bounds are invalid.');
    }
    if (before.capacityBytes < before.usageBytes ||
        after.capacityBytes < after.usageBytes ||
        (groupBefore != null &&
            groupBefore!.capacityBytes < groupBefore!.usageBytes) ||
        (groupAfter != null &&
            groupAfter!.capacityBytes < groupAfter!.usageBytes)) {
      throw const FormatException('Heap usage exceeds capacity.');
    }
    if (accumulatorResetAt != null && accumulatorResetAt! < 0 ||
        serviceGcAt != null && serviceGcAt! < 0) {
      throw const FormatException('Heap profile timestamps are invalid.');
    }
    if (this.samples.any((sample) => !sample.isValid)) {
      throw const FormatException('Heap profile contains an invalid sample.');
    }
    for (var index = 1; index < this.samples.length; index += 1) {
      if (this.samples[index].timestampUs <
          this.samples[index - 1].timestampUs) {
        throw const FormatException('Heap samples are not ordered.');
      }
    }
  }

  final CockpitHeapPoint before;
  final CockpitHeapPoint after;
  final List<CockpitHeapClass> classes;
  final int droppedClasses;
  final int intervalMs;
  final List<CockpitHeapSample> samples;
  final int droppedSamples;
  final CockpitHeapPoint? groupBefore;
  final CockpitHeapPoint? groupAfter;

  /// VM timestamp of the last allocation accumulator reset, when reported.
  /// The value is kept in the VM's native timestamp unit and is not converted
  /// to wall-clock time.
  final int? accumulatorResetAt;

  /// VM timestamp of the last service-triggered GC, when reported.
  /// The value is kept in the VM's native timestamp unit and is not converted
  /// to wall-clock time.
  final int? serviceGcAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'before': before.toJson(),
    'after': after.toJson(),
    if (classes.isNotEmpty)
      'classes': classes.map((item) => item.toJson()).toList(growable: false),
    if (droppedClasses > 0) 'dropped': droppedClasses,
    if (samples.isNotEmpty)
      'samples': samples.map((item) => item.toJson()).toList(growable: false),
    if (intervalMs > 0) 'interval': intervalMs,
    if (droppedSamples > 0) 'drop': droppedSamples,
    if (groupBefore != null) 'gb': groupBefore!.toJson(),
    if (groupAfter != null) 'ga': groupAfter!.toJson(),
    if (accumulatorResetAt != null) 'reset': accumulatorResetAt,
    if (serviceGcAt != null) 'gcAt': serviceGcAt,
  };

  factory CockpitHeapProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.heap');
    final rawClasses = json['classes'];
    return CockpitHeapProfile(
      before: CockpitHeapPoint.fromJson(json['before']),
      after: CockpitHeapPoint.fromJson(json['after']),
      classes: rawClasses == null
          ? const <CockpitHeapClass>[]
          : _list(
              rawClasses,
              r'$.devtools.heap.classes',
            ).map(CockpitHeapClass.fromJson).toList(growable: false),
      droppedClasses: json['dropped'] == null
          ? 0
          : _nonNegativeInt(json['dropped'], r'$.devtools.heap.dropped'),
      intervalMs: json['interval'] == null
          ? 0
          : _nonNegativeInt(json['interval'], r'$.devtools.heap.interval'),
      samples: json['samples'] == null
          ? const <CockpitHeapSample>[]
          : _list(
              json['samples'],
              r'$.devtools.heap.samples',
            ).map(CockpitHeapSample.fromJson).toList(growable: false),
      droppedSamples: json['drop'] == null
          ? 0
          : _nonNegativeInt(json['drop'], r'$.devtools.heap.drop'),
      groupBefore: json['gb'] == null
          ? null
          : CockpitHeapPoint.fromJson(json['gb']),
      groupAfter: json['ga'] == null
          ? null
          : CockpitHeapPoint.fromJson(json['ga']),
      accumulatorResetAt: json['reset'] == null
          ? null
          : _nonNegativeInt(json['reset'], r'$.devtools.heap.reset'),
      serviceGcAt: json['gcAt'] == null
          ? null
          : _nonNegativeInt(json['gcAt'], r'$.devtools.heap.gcAt'),
    );
  }
}

/// Aggregate garbage-collection pauses observed in the retained VM timeline.
///
/// Durations are derived only from real GC timeline events. A missing profile
/// means the timeline did not expose a verifiable GC event, never that the app
/// had a zero-cost collection cycle.
final class CockpitGcProfile {
  const CockpitGcProfile({
    required this.eventCount,
    required this.timedCount,
    required this.newCount,
    required this.oldCount,
    required this.totalPauseUs,
    required this.p50PauseUs,
    required this.p90PauseUs,
    required this.maxPauseUs,
    required this.newPauseUs,
    required this.oldPauseUs,
  });

  final int eventCount;
  final int timedCount;
  final int newCount;
  final int oldCount;
  final int totalPauseUs;
  final int p50PauseUs;
  final int p90PauseUs;
  final int maxPauseUs;
  final int newPauseUs;
  final int oldPauseUs;

  bool get isValid =>
      eventCount > 0 &&
      timedCount >= 0 &&
      timedCount <= eventCount &&
      newCount >= 0 &&
      oldCount >= 0 &&
      newCount + oldCount <= eventCount &&
      totalPauseUs >= 0 &&
      p50PauseUs >= 0 &&
      p90PauseUs >= 0 &&
      maxPauseUs >= 0 &&
      p50PauseUs <= p90PauseUs &&
      p90PauseUs <= maxPauseUs &&
      newPauseUs >= 0 &&
      oldPauseUs >= 0 &&
      newPauseUs + oldPauseUs <= totalPauseUs;

  Map<String, Object?> toJson() => <String, Object?>{
    'n': eventCount,
    'timed': timedCount,
    if (newCount > 0) 'new': newCount,
    if (oldCount > 0) 'old': oldCount,
    if (timedCount > 0) ...<String, Object?>{
      'total': totalPauseUs,
      'p50': p50PauseUs,
      'p90': p90PauseUs,
      'max': maxPauseUs,
      if (newPauseUs > 0) 'newUs': newPauseUs,
      if (oldPauseUs > 0) 'oldUs': oldPauseUs,
    },
  };

  factory CockpitGcProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.gc');
    final profile = CockpitGcProfile(
      eventCount: _positiveInt(json['n'], r'$.devtools.gc.n'),
      timedCount: _nonNegativeInt(json['timed'], r'$.devtools.gc.timed'),
      newCount: json['new'] == null
          ? 0
          : _nonNegativeInt(json['new'], r'$.devtools.gc.new'),
      oldCount: json['old'] == null
          ? 0
          : _nonNegativeInt(json['old'], r'$.devtools.gc.old'),
      totalPauseUs: json['total'] == null
          ? 0
          : _nonNegativeInt(json['total'], r'$.devtools.gc.total'),
      p50PauseUs: json['p50'] == null
          ? 0
          : _nonNegativeInt(json['p50'], r'$.devtools.gc.p50'),
      p90PauseUs: json['p90'] == null
          ? 0
          : _nonNegativeInt(json['p90'], r'$.devtools.gc.p90'),
      maxPauseUs: json['max'] == null
          ? 0
          : _nonNegativeInt(json['max'], r'$.devtools.gc.max'),
      newPauseUs: json['newUs'] == null
          ? 0
          : _nonNegativeInt(json['newUs'], r'$.devtools.gc.newUs'),
      oldPauseUs: json['oldUs'] == null
          ? 0
          : _nonNegativeInt(json['oldUs'], r'$.devtools.gc.oldUs'),
    );
    if (!profile.isValid) {
      throw const FormatException('GC profile is inconsistent.');
    }
    return profile;
  }
}

/// A bounded snapshot of one Dart isolate's runtime health.
final class CockpitIsolateStats {
  const CockpitIsolateStats({
    required this.id,
    required this.name,
    this.number,
    this.groupId,
    this.runnable,
    this.livePorts,
    this.libraryCount,
    this.extensionCount,
    this.startTimeMs,
    this.system,
    this.pauseKind,
    this.pauseTimestampMs,
    this.pauseAsync,
    this.error,
    this.pauseOnExit,
    this.exceptionPauseMode,
    this.rootLibUri,
    this.breakpointCount,
    this.newHeap,
    this.oldHeap,
  });

  final String id;
  final String name;
  final String? number;
  final String? groupId;
  final bool? runnable;
  final int? livePorts;
  final int? libraryCount;
  final int? extensionCount;
  final int? startTimeMs;
  final bool? system;
  final String? pauseKind;
  final int? pauseTimestampMs;
  final bool? pauseAsync;
  final String? error;
  final bool? pauseOnExit;
  final String? exceptionPauseMode;
  final String? rootLibUri;
  final int? breakpointCount;
  final CockpitHeapPoint? newHeap;
  final CockpitHeapPoint? oldHeap;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    if (number != null && number!.isNotEmpty) 'num': number,
    if (groupId != null && groupId!.isNotEmpty) 'group': groupId,
    if (runnable != null) 'run': runnable,
    if (livePorts != null) 'ports': livePorts,
    if (libraryCount != null) 'libs': libraryCount,
    if (extensionCount != null) 'ext': extensionCount,
    if (startTimeMs != null) 'start': startTimeMs,
    if (system != null) 'sys': system,
    if (pauseKind != null && pauseKind!.isNotEmpty) 'pause': pauseKind,
    if (pauseTimestampMs != null) 'pauseT': pauseTimestampMs,
    if (pauseAsync != null) 'async': pauseAsync,
    if (error != null && error!.isNotEmpty) 'error': error,
    if (pauseOnExit != null) 'exit': pauseOnExit,
    if (exceptionPauseMode != null && exceptionPauseMode!.isNotEmpty)
      'ex': exceptionPauseMode,
    if (rootLibUri != null && rootLibUri!.isNotEmpty) 'root': rootLibUri,
    if (breakpointCount != null) 'bp': breakpointCount,
    if (newHeap != null) 'new': newHeap!.toJson(),
    if (oldHeap != null) 'old': oldHeap!.toJson(),
  };

  factory CockpitIsolateStats.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.isolate.stats');
    return CockpitIsolateStats(
      id: _string(json['id'], r'$.devtools.isolate.stats.id'),
      name: _string(json['name'], r'$.devtools.isolate.stats.name'),
      number: _optionalString(json['num'], r'$.devtools.isolate.stats.num'),
      groupId: _optionalString(
        json['group'],
        r'$.devtools.isolate.stats.group',
      ),
      runnable: json['run'] == null
          ? null
          : _bool(json['run'], r'$.devtools.isolate.stats.run'),
      livePorts: json['ports'] == null
          ? null
          : _nonNegativeInt(json['ports'], r'$.devtools.isolate.stats.ports'),
      libraryCount: json['libs'] == null
          ? null
          : _nonNegativeInt(json['libs'], r'$.devtools.isolate.stats.libs'),
      extensionCount: json['ext'] == null
          ? null
          : _nonNegativeInt(json['ext'], r'$.devtools.isolate.stats.ext'),
      startTimeMs: json['start'] == null
          ? null
          : _nonNegativeInt(json['start'], r'$.devtools.isolate.stats.start'),
      system: json['sys'] == null
          ? null
          : _bool(json['sys'], r'$.devtools.isolate.stats.sys'),
      pauseKind: _optionalString(
        json['pause'],
        r'$.devtools.isolate.stats.pause',
      ),
      pauseTimestampMs: json['pauseT'] == null
          ? null
          : _nonNegativeInt(json['pauseT'], r'$.devtools.isolate.stats.pauseT'),
      pauseAsync: json['async'] == null
          ? null
          : _bool(json['async'], r'$.devtools.isolate.stats.async'),
      error: _optionalString(json['error'], r'$.devtools.isolate.stats.error'),
      pauseOnExit: json['exit'] == null
          ? null
          : _bool(json['exit'], r'$.devtools.isolate.stats.exit'),
      exceptionPauseMode: _optionalString(
        json['ex'],
        r'$.devtools.isolate.stats.ex',
      ),
      rootLibUri: _optionalString(
        json['root'],
        r'$.devtools.isolate.stats.root',
      ),
      breakpointCount: json['bp'] == null
          ? null
          : _nonNegativeInt(json['bp'], r'$.devtools.isolate.stats.bp'),
      newHeap: json['new'] == null
          ? null
          : CockpitHeapPoint.fromJson(json['new']),
      oldHeap: json['old'] == null
          ? null
          : CockpitHeapPoint.fromJson(json['old']),
    );
  }
}

/// One lifecycle notification observed on the VM Isolate stream.
final class CockpitIsolateEvent {
  const CockpitIsolateEvent({
    required this.kind,
    this.timestampMs,
    this.isolateId,
    this.name,
    this.groupId,
    this.extensionRpc,
  });

  final String kind;
  final int? timestampMs;
  final String? isolateId;
  final String? name;
  final String? groupId;
  final String? extensionRpc;

  Map<String, Object?> toJson() => <String, Object?>{
    'k': kind,
    if (timestampMs != null) 't': timestampMs,
    if (isolateId != null && isolateId!.isNotEmpty) 'id': isolateId,
    if (name != null && name!.isNotEmpty) 'name': name,
    if (groupId != null && groupId!.isNotEmpty) 'group': groupId,
    if (extensionRpc != null && extensionRpc!.isNotEmpty) 'rpc': extensionRpc,
  };

  factory CockpitIsolateEvent.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.isolate.events[]');
    final kind = _string(json['k'], r'$.devtools.isolate.events[].k');
    final timestamp = json['t'];
    return CockpitIsolateEvent(
      kind: kind,
      timestampMs: timestamp == null
          ? null
          : _nonNegativeInt(timestamp, r'$.devtools.isolate.events[].t'),
      isolateId: _optionalString(json['id'], r'$.devtools.isolate.events[].id'),
      name: _optionalString(json['name'], r'$.devtools.isolate.events[].name'),
      groupId: _optionalString(
        json['group'],
        r'$.devtools.isolate.events[].group',
      ),
      extensionRpc: _optionalString(
        json['rpc'],
        r'$.devtools.isolate.events[].rpc',
      ),
    );
  }
}

/// Before/after isolate state captured around one performance interval.
final class CockpitIsolateProfile {
  CockpitIsolateProfile({
    this.before,
    this.after,
    Iterable<CockpitIsolateStats> beforeAll = const <CockpitIsolateStats>[],
    Iterable<CockpitIsolateStats> afterAll = const <CockpitIsolateStats>[],
    this.droppedBefore = 0,
    this.droppedAfter = 0,
    Iterable<CockpitIsolateEvent> events = const <CockpitIsolateEvent>[],
    this.droppedEvents = 0,
  }) : beforeAll = List<CockpitIsolateStats>.unmodifiable(beforeAll),
       afterAll = List<CockpitIsolateStats>.unmodifiable(afterAll),
       events = List<CockpitIsolateEvent>.unmodifiable(events) {
    if (droppedBefore < 0 ||
        droppedAfter < 0 ||
        droppedEvents < 0 ||
        this.beforeAll.length > 64 ||
        this.afterAll.length > 64 ||
        this.events.length > 1000) {
      throw const FormatException('Isolate profile bounds are invalid.');
    }
  }

  final CockpitIsolateStats? before;
  final CockpitIsolateStats? after;
  final List<CockpitIsolateStats> beforeAll;
  final List<CockpitIsolateStats> afterAll;
  final int droppedBefore;
  final int droppedAfter;
  final List<CockpitIsolateEvent> events;
  final int droppedEvents;

  Map<String, Object?> toJson() => <String, Object?>{
    if (before != null) 'before': before!.toJson(),
    if (after != null) 'after': after!.toJson(),
    if (beforeAll.isNotEmpty)
      'allB': beforeAll.map((item) => item.toJson()).toList(growable: false),
    if (afterAll.isNotEmpty)
      'allA': afterAll.map((item) => item.toJson()).toList(growable: false),
    if (droppedBefore > 0) 'dropB': droppedBefore,
    if (droppedAfter > 0) 'dropA': droppedAfter,
    if (events.isNotEmpty)
      'events': events.map((item) => item.toJson()).toList(growable: false),
    if (droppedEvents > 0) 'dropE': droppedEvents,
  };

  factory CockpitIsolateProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.isolate');
    final rawBeforeAll = json['allB'];
    final rawAfterAll = json['allA'];
    final rawEvents = json['events'];
    return CockpitIsolateProfile(
      before: json['before'] == null
          ? null
          : CockpitIsolateStats.fromJson(json['before']),
      after: json['after'] == null
          ? null
          : CockpitIsolateStats.fromJson(json['after']),
      beforeAll: rawBeforeAll == null
          ? const <CockpitIsolateStats>[]
          : _list(
              rawBeforeAll,
              r'$.devtools.isolate.allB',
            ).map(CockpitIsolateStats.fromJson).toList(growable: false),
      afterAll: rawAfterAll == null
          ? const <CockpitIsolateStats>[]
          : _list(
              rawAfterAll,
              r'$.devtools.isolate.allA',
            ).map(CockpitIsolateStats.fromJson).toList(growable: false),
      droppedBefore: json['dropB'] == null
          ? 0
          : _nonNegativeInt(json['dropB'], r'$.devtools.isolate.dropB'),
      droppedAfter: json['dropA'] == null
          ? 0
          : _nonNegativeInt(json['dropA'], r'$.devtools.isolate.dropA'),
      events: rawEvents == null
          ? const <CockpitIsolateEvent>[]
          : _list(
              rawEvents,
              r'$.devtools.isolate.events',
            ).map(CockpitIsolateEvent.fromJson).toList(growable: false),
      droppedEvents: json['dropE'] == null
          ? 0
          : _nonNegativeInt(json['dropE'], r'$.devtools.isolate.dropE'),
    );
  }
}

/// Display timing metadata queried from Flutter's engine through VM Service.
///
/// The engine reports the effective refresh rate for the selected Flutter view.
/// A zero/unknown engine response is represented by an absent value rather
/// than being treated as a 60Hz guess.
final class CockpitDisplayProfile {
  CockpitDisplayProfile({this.refreshRateHz, this.frameBudgetUs, this.viewId}) {
    if (refreshRateHz != null &&
            (!refreshRateHz!.isFinite || refreshRateHz! <= 0) ||
        frameBudgetUs != null && frameBudgetUs! <= 0 ||
        viewId != null && viewId!.trim().isEmpty) {
      throw const FormatException('Display profile values are invalid.');
    }
  }

  final double? refreshRateHz;
  final int? frameBudgetUs;
  final String? viewId;

  Map<String, Object?> toJson() => <String, Object?>{
    if (refreshRateHz != null) 'hz': refreshRateHz,
    if (frameBudgetUs != null) 'bud': frameBudgetUs,
    if (viewId != null && viewId!.trim().isNotEmpty) 'view': viewId,
  };

  factory CockpitDisplayProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.display');
    return CockpitDisplayProfile(
      refreshRateHz: json['hz'] == null
          ? null
          : _positiveFiniteDouble(json['hz'], r'$.devtools.display.hz'),
      frameBudgetUs: json['bud'] == null
          ? null
          : _positiveInt(json['bud'], r'$.devtools.display.bud'),
      viewId: _optionalString(json['view'], r'$.devtools.display.view'),
    );
  }
}

/// One widget source location reported by Flutter.RebuiltWidgets.
final class CockpitRebuildLocation {
  CockpitRebuildLocation({
    required this.id,
    this.uri,
    this.line,
    this.column,
    this.name,
  }) {
    if (id < 0 ||
        line != null && line! < 0 ||
        column != null && column! < 0 ||
        uri != null && uri!.trim().isEmpty ||
        name != null && name!.trim().isEmpty) {
      throw const FormatException('Rebuild location is invalid.');
    }
  }

  final int id;
  final String? uri;
  final int? line;
  final int? column;
  final String? name;

  bool get isResolved => uri != null && line != null && column != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (uri != null && uri!.trim().isNotEmpty) 'u': uri,
    if (line != null) 'l': line,
    if (column != null) 'c': column,
    if (name != null && name!.trim().isNotEmpty) 'n': name,
  };

  factory CockpitRebuildLocation.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.rebuild.loc[]');
    return CockpitRebuildLocation(
      id: _nonNegativeInt(json['id'], r'$.devtools.rebuild.loc[].id'),
      uri: _optionalString(json['u'], r'$.devtools.rebuild.loc[].u'),
      line: json['l'] == null
          ? null
          : _nonNegativeInt(json['l'], r'$.devtools.rebuild.loc[].l'),
      column: json['c'] == null
          ? null
          : _nonNegativeInt(json['c'], r'$.devtools.rebuild.loc[].c'),
      name: _optionalString(json['n'], r'$.devtools.rebuild.loc[].n'),
    );
  }
}

/// One location/count pair in a rebuild frame.
final class CockpitRebuildCount {
  const CockpitRebuildCount({required this.locationId, required this.count});

  final int locationId;
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': locationId,
    'n': count,
  };
}

/// Rebuild counts emitted for one Flutter frame.
final class CockpitRebuildFrame {
  CockpitRebuildFrame({
    required this.frameNumber,
    Iterable<CockpitRebuildCount> entries = const <CockpitRebuildCount>[],
  }) : entries = List<CockpitRebuildCount>.unmodifiable(entries) {
    if (frameNumber < 0 || this.entries.length > 2000) {
      throw const FormatException('Rebuild frame bounds are invalid.');
    }
    if (this.entries.any((entry) => entry.locationId < 0 || entry.count <= 0)) {
      throw const FormatException('Rebuild entries are invalid.');
    }
  }

  final int frameNumber;
  final List<CockpitRebuildCount> entries;

  Map<String, Object?> toJson() => <String, Object?>{
    'n': frameNumber,
    if (entries.isNotEmpty)
      // Match Flutter's compact wire representation: [locationId, count, …].
      'e': entries
          .expand<Object?>((entry) => <Object?>[entry.locationId, entry.count])
          .toList(growable: false),
  };

  factory CockpitRebuildFrame.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.rebuild.frames[]');
    final raw = json['e'];
    final values = raw == null
        ? const <Object?>[]
        : _list(raw, r'$.devtools.rebuild.frames[].e');
    if (values.length.isOdd) {
      throw const FormatException('Rebuild frame entries must be paired.');
    }
    final entries = <CockpitRebuildCount>[];
    for (var index = 0; index < values.length; index += 2) {
      entries.add(
        CockpitRebuildCount(
          locationId: _nonNegativeInt(
            values[index],
            r'$.devtools.rebuild.frames[].e[]',
          ),
          count: _positiveInt(
            values[index + 1],
            r'$.devtools.rebuild.frames[].e[]',
          ),
        ),
      );
    }
    return CockpitRebuildFrame(
      frameNumber: _nonNegativeInt(json['n'], r'$.devtools.rebuild.frames[].n'),
      entries: entries,
    );
  }
}

/// Aggregate rebuild counts for one widget source location.
final class CockpitRebuildTotal {
  CockpitRebuildTotal({required this.locationId, required this.count}) {
    if (locationId < 0 || count <= 0) {
      throw const FormatException('Rebuild total is invalid.');
    }
  }

  final int locationId;
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': locationId,
    'n': count,
  };

  factory CockpitRebuildTotal.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.rebuild.totals[]');
    return CockpitRebuildTotal(
      locationId: _nonNegativeInt(
        json['id'],
        r'$.devtools.rebuild.totals[].id',
      ),
      count: _positiveInt(json['n'], r'$.devtools.rebuild.totals[].n'),
    );
  }
}

/// Bounded DevTools-style widget rebuild evidence.
final class CockpitRebuildProfile {
  CockpitRebuildProfile({
    Iterable<CockpitRebuildFrame> frames = const <CockpitRebuildFrame>[],
    Iterable<CockpitRebuildLocation> locations =
        const <CockpitRebuildLocation>[],
    Iterable<CockpitRebuildTotal> totals = const <CockpitRebuildTotal>[],
    this.droppedFrames = 0,
    this.droppedEntries = 0,
    this.unresolvedLocations = 0,
  }) : frames = List<CockpitRebuildFrame>.unmodifiable(frames),
       locations = List<CockpitRebuildLocation>.unmodifiable(locations),
       totals = List<CockpitRebuildTotal>.unmodifiable(totals) {
    if (droppedFrames < 0 ||
        droppedEntries < 0 ||
        unresolvedLocations < 0 ||
        this.frames.length > 10000 ||
        this.locations.length > 50000 ||
        this.totals.length > 50000) {
      throw const FormatException('Rebuild profile bounds are invalid.');
    }
    for (var index = 1; index < this.frames.length; index += 1) {
      if (this.frames[index].frameNumber <=
          this.frames[index - 1].frameNumber) {
        throw const FormatException('Rebuild frames are not ordered.');
      }
    }
  }

  final List<CockpitRebuildFrame> frames;
  final List<CockpitRebuildLocation> locations;
  final List<CockpitRebuildTotal> totals;
  final int droppedFrames;
  final int droppedEntries;
  final int unresolvedLocations;

  Map<String, Object?> toJson() => <String, Object?>{
    if (frames.isNotEmpty)
      'frames': frames.map((item) => item.toJson()).toList(growable: false),
    if (locations.isNotEmpty)
      'loc': locations.map((item) => item.toJson()).toList(growable: false),
    if (totals.isNotEmpty)
      'tot': totals.map((item) => item.toJson()).toList(growable: false),
    if (droppedFrames > 0) 'dropF': droppedFrames,
    if (droppedEntries > 0) 'dropE': droppedEntries,
    if (unresolvedLocations > 0) 'unknown': unresolvedLocations,
  };

  factory CockpitRebuildProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.rebuild');
    final rawFrames = json['frames'];
    final rawLocations = json['loc'];
    final rawTotals = json['tot'];
    return CockpitRebuildProfile(
      frames: rawFrames == null
          ? const <CockpitRebuildFrame>[]
          : _list(
              rawFrames,
              r'$.devtools.rebuild.frames',
            ).map(CockpitRebuildFrame.fromJson).toList(growable: false),
      locations: rawLocations == null
          ? const <CockpitRebuildLocation>[]
          : _list(
              rawLocations,
              r'$.devtools.rebuild.loc',
            ).map(CockpitRebuildLocation.fromJson).toList(growable: false),
      totals: rawTotals == null
          ? const <CockpitRebuildTotal>[]
          : _list(
              rawTotals,
              r'$.devtools.rebuild.totals',
            ).map(CockpitRebuildTotal.fromJson).toList(growable: false),
      droppedFrames: json['dropF'] == null
          ? 0
          : _nonNegativeInt(json['dropF'], r'$.devtools.rebuild.dropF'),
      droppedEntries: json['dropE'] == null
          ? 0
          : _nonNegativeInt(json['dropE'], r'$.devtools.rebuild.dropE'),
      unresolvedLocations: json['unknown'] == null
          ? 0
          : _nonNegativeInt(json['unknown'], r'$.devtools.rebuild.unknown'),
    );
  }
}

/// Timeline recorder and stream capabilities observed from VM Service.
final class CockpitTimelineProfile {
  CockpitTimelineProfile({
    required this.recorder,
    required Iterable<String> availableStreams,
    required Iterable<String> recordedStreams,
  }) : availableStreams = List<String>.unmodifiable(availableStreams),
       recordedStreams = List<String>.unmodifiable(recordedStreams) {
    if (recorder.trim().isEmpty ||
        this.availableStreams.length > 500 ||
        this.recordedStreams.length > 500) {
      throw const FormatException('Timeline profile metadata is invalid.');
    }
  }

  final String recorder;
  final List<String> availableStreams;
  final List<String> recordedStreams;

  Map<String, Object?> toJson() => <String, Object?>{
    'recorder': recorder,
    if (availableStreams.isNotEmpty) 'available': availableStreams,
    if (recordedStreams.isNotEmpty) 'recorded': recordedStreams,
  };

  factory CockpitTimelineProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.timeline');
    return CockpitTimelineProfile(
      recorder: _string(json['recorder'], r'$.devtools.timeline.recorder'),
      availableStreams: _strings(
        json['available'],
        r'$.devtools.timeline.available',
      ),
      recordedStreams: _strings(
        json['recorded'],
        r'$.devtools.timeline.recorded',
      ),
    );
  }
}

final class CockpitGpuProfile {
  const CockpitGpuProfile({
    required this.source,
    required this.events,
    required this.shaderEvents,
    required this.durationUs,
  });

  final String source;
  final int events;
  final int shaderEvents;
  final int durationUs;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'events': events,
    'shaders': shaderEvents,
    if (durationUs > 0) 'time': durationUs,
  };

  factory CockpitGpuProfile.fromJson(Object? value) {
    final json = _object(value, r'$.devtools.gpu');
    return CockpitGpuProfile(
      source: _string(json['source'], r'$.devtools.gpu.source'),
      events: _nonNegativeInt(json['events'], r'$.devtools.gpu.events'),
      shaderEvents: _nonNegativeInt(json['shaders'], r'$.devtools.gpu.shaders'),
      durationUs: json['time'] == null
          ? 0
          : _nonNegativeInt(json['time'], r'$.devtools.gpu.time'),
    );
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is Map<Object?, Object?>) return Map<String, Object?>.from(value);
  if (value is Map<String, Object?>) return value;
  throw FormatException('$path must be an object.');
}

List<Object?> _list(Object? value, String path) {
  if (value is List<Object?>) return value;
  throw FormatException('$path must be an array.');
}

String _string(Object? value, String path) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$path must be a non-empty string.');
}

const _maxEventTextLength = 64 * 1024;

String _boundedString(Object? value, String path) {
  final result = _string(value, path);
  if (result.length > _maxEventTextLength) {
    throw FormatException('$path is too long.');
  }
  return result;
}

String? _optionalBoundedString(Object? value, String path) {
  if (value == null) return null;
  if (value is String && value.trim().isEmpty) return null;
  return _boundedString(value, path);
}

bool _validText(String? value) =>
    value == null || value.isEmpty || value.length <= _maxEventTextLength;

String? _optionalString(Object? value, String path) {
  if (value == null) return null;
  // VM responses may include empty optional fields (for example a class with
  // no library name). Treat those as absent so a valid profile is not rejected
  // merely because the source omitted metadata.
  if (value is String && value.trim().isEmpty) return null;
  return _string(value, path);
}

int _nonNegativeInt(Object? value, String path) {
  if (value is int && value >= 0) return value;
  throw FormatException('$path must be a non-negative integer.');
}

int _positiveInt(Object? value, String path) {
  if (value is int && value > 0) return value;
  throw FormatException('$path must be a positive integer.');
}

double _positiveFiniteDouble(Object? value, String path) {
  if (value is num && value.isFinite && value > 0) return value.toDouble();
  throw FormatException('$path must be a positive finite number.');
}

bool _bool(Object? value, String path) {
  if (value is bool) return value;
  throw FormatException('$path must be a boolean.');
}

List<String> _strings(Object? value, String path) {
  if (value == null) return const <String>[];
  if (value is! List) throw FormatException('$path must be an array.');
  return List<String>.unmodifiable(
    value.map((item) => _string(item, '$path[]')),
  );
}
