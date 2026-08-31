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
    this.gpu,
  }) {
    if (source.trim().isEmpty || state.trim().isEmpty) {
      throw const FormatException('DevTools profile identity is invalid.');
    }
    if (reason != null && reason!.trim().isEmpty) {
      throw const FormatException('DevTools profile reason is invalid.');
    }
  }

  final String source;
  final String state;
  final String? reason;
  final CockpitCpuProfile? cpu;
  final CockpitHeapProfile? heap;
  final CockpitGpuProfile? gpu;

  CockpitDevToolsProfile copyWith({
    CockpitCpuProfile? cpu,
    CockpitHeapProfile? heap,
    CockpitGpuProfile? gpu,
  }) => CockpitDevToolsProfile(
    source: source,
    state: state,
    reason: reason,
    cpu: cpu ?? this.cpu,
    heap: heap ?? this.heap,
    gpu: gpu ?? this.gpu,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'state': state,
    if (reason != null && reason!.trim().isNotEmpty) 'why': reason,
    if (cpu != null) 'cpu': cpu!.toJson(),
    if (heap != null) 'heap': heap!.toJson(),
    if (gpu != null) 'gpu': gpu!.toJson(),
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
      gpu: json['gpu'] == null ? null : CockpitGpuProfile.fromJson(json['gpu']),
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
          : _positiveInt(json['c'], r'$.devtools.cpu.fn.c'),
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

  Map<String, Object?> toJson() => <String, Object?>{
    'period': samplePeriodUs,
    'depth': maxStackDepth,
    'n': sampleCount,
    'start': timeOriginUs,
    'span': timeExtentUs,
    if (pid != null) 'pid': pid,
    if (functions.isNotEmpty)
      'f': functions.map((item) => item.toJson()).toList(growable: false),
    if (samples.isNotEmpty)
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

final class CockpitHeapProfile {
  CockpitHeapProfile({
    required this.before,
    required this.after,
    required Iterable<CockpitHeapClass> classes,
    this.droppedClasses = 0,
  }) : classes = List<CockpitHeapClass>.unmodifiable(classes) {
    if (droppedClasses < 0 || this.classes.length > 1000) {
      throw const FormatException('Heap profile bounds are invalid.');
    }
    if (before.capacityBytes < before.usageBytes ||
        after.capacityBytes < after.usageBytes) {
      throw const FormatException('Heap usage exceeds capacity.');
    }
  }

  final CockpitHeapPoint before;
  final CockpitHeapPoint after;
  final List<CockpitHeapClass> classes;
  final int droppedClasses;

  Map<String, Object?> toJson() => <String, Object?>{
    'before': before.toJson(),
    'after': after.toJson(),
    if (classes.isNotEmpty)
      'classes': classes.map((item) => item.toJson()).toList(growable: false),
    if (droppedClasses > 0) 'dropped': droppedClasses,
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
