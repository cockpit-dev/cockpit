/// Compact, source-aware projections of Dart VM debugger responses.
///
/// The VM service protocol is intentionally not exposed directly from the
/// public test facade. These models keep debugger reads bounded and make the
/// useful fields obvious to both test authors and AI agents.

library;

final class CockpitVmLocation {
  const CockpitVmLocation({this.uri, this.line, this.column});

  final String? uri;
  final int? line;
  final int? column;

  Map<String, Object?> toJson() => <String, Object?>{
    if (uri != null && uri!.trim().isNotEmpty) 'u': uri,
    if (line != null) 'l': line,
    if (column != null) 'c': column,
  };
}

final class CockpitVmValue {
  const CockpitVmValue({
    this.id,
    this.kind,
    this.type,
    this.className,
    this.value,
    this.length,
    this.offset,
    this.count,
    this.error,
    this.truncated = false,
  });

  final String? id;
  final String? kind;
  final String? type;
  final String? className;
  final String? value;
  final int? length;
  final int? offset;
  final int? count;
  final String? error;
  final bool truncated;

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null && id!.trim().isNotEmpty) 'id': id,
    if (kind != null && kind!.trim().isNotEmpty) 'kind': kind,
    if (type != null && type!.trim().isNotEmpty) 'type': type,
    if (className != null && className!.trim().isNotEmpty) 'class': className,
    if (value != null) 'value': value,
    if (length != null) 'len': length,
    if (offset != null) 'off': offset,
    if (count != null) 'n': count,
    if (error != null && error!.trim().isNotEmpty) 'error': error,
    if (truncated) 'trunc': true,
  };
}

final class CockpitVmVariable {
  const CockpitVmVariable({required this.name, this.value});

  final String name;
  final CockpitVmValue? value;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (value != null) 'value': value!.toJson(),
  };
}

final class CockpitVmFrame {
  const CockpitVmFrame({
    required this.index,
    this.name,
    this.kind,
    this.location,
    this.variables = const <CockpitVmVariable>[],
  });

  final int index;
  final String? name;
  final String? kind;
  final CockpitVmLocation? location;
  final List<CockpitVmVariable> variables;

  Map<String, Object?> toJson() => <String, Object?>{
    'i': index,
    if (name != null && name!.trim().isNotEmpty) 'name': name,
    if (kind != null && kind!.trim().isNotEmpty) 'kind': kind,
    if (location != null && location!.toJson().isNotEmpty)
      'loc': location!.toJson(),
    if (variables.isNotEmpty)
      'vars': variables.map((item) => item.toJson()).toList(growable: false),
  };
}

final class CockpitVmStack {
  const CockpitVmStack({
    required this.isolateId,
    this.frames = const <CockpitVmFrame>[],
    this.asyncFrames = const <CockpitVmFrame>[],
    this.messageCount = 0,
    this.truncated = false,
  });

  final String isolateId;
  final List<CockpitVmFrame> frames;
  final List<CockpitVmFrame> asyncFrames;
  final int messageCount;
  final bool truncated;

  Map<String, Object?> toJson() => <String, Object?>{
    'iso': isolateId,
    if (frames.isNotEmpty)
      'frames': frames.map((item) => item.toJson()).toList(growable: false),
    if (asyncFrames.isNotEmpty)
      'async': asyncFrames.map((item) => item.toJson()).toList(growable: false),
    if (messageCount > 0) 'messages': messageCount,
    if (truncated) 'trunc': true,
  };
}

final class CockpitVmDebuggerStatus {
  const CockpitVmDebuggerStatus({
    required this.isolateId,
    this.isolateName,
    this.runnable,
    this.pauseKind,
    this.pauseTimestampMs,
    this.stack,
  });

  final String isolateId;
  final String? isolateName;
  final bool? runnable;
  final String? pauseKind;
  final int? pauseTimestampMs;
  final CockpitVmStack? stack;

  Map<String, Object?> toJson() => <String, Object?>{
    'iso': isolateId,
    if (isolateName != null && isolateName!.trim().isNotEmpty)
      'name': isolateName,
    if (runnable != null) 'run': runnable,
    if (pauseKind != null && pauseKind!.trim().isNotEmpty) 'pause': pauseKind,
    if (pauseTimestampMs != null) 'pauseT': pauseTimestampMs,
    if (stack != null) 'stack': stack!.toJson(),
  };
}

final class CockpitVmEvaluation {
  const CockpitVmEvaluation({this.value, this.error});

  final CockpitVmValue? value;
  final String? error;

  bool get hasError => error != null && error!.trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    if (value != null) 'value': value!.toJson(),
    if (hasError) 'error': error,
  };
}

final class CockpitVmBreakpoint {
  const CockpitVmBreakpoint({
    required this.id,
    this.number,
    this.enabled,
    this.resolved,
    this.location,
  });

  final String id;
  final int? number;
  final bool? enabled;
  final bool? resolved;
  final CockpitVmLocation? location;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (number != null) 'n': number,
    if (enabled != null) 'enabled': enabled,
    if (resolved != null) 'resolved': resolved,
    if (location != null && location!.toJson().isNotEmpty)
      'loc': location!.toJson(),
  };
}

enum CockpitVmStep {
  into('Into'),
  over('Over'),
  out('Out'),
  overAsyncSuspension('OverAsyncSuspension');

  const CockpitVmStep(this.wireValue);

  final String wireValue;
}
