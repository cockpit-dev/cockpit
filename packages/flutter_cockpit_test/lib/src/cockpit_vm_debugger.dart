import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import 'cockpit_vm_debugger_models.dart';
import 'cockpit_vm_service_connect.dart';

/// A bounded, source-aware facade over the Dart VM debugger protocol.
///
/// This is development/test tooling only. It keeps the common Dart-Code
/// debugger workflow in one reusable session: inspect a stack, pause/resume or
/// step an isolate, evaluate a small expression, manage a source breakpoint,
/// and call a known Flutter service extension. It never attaches implicitly
/// from production code and never fetches large objects unless requested.
final class CockpitVmDebugger {
  CockpitVmDebugger({this.timeout = const Duration(seconds: 3)}) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  final Duration timeout;

  VmService? _service;
  Future<VmService>? _connecting;
  String? _defaultIsolateId;

  /// Whether a VM Service connection can be established right now.
  ///
  /// This probe has no mutation side effects. A `false` result means the
  /// current runner does not expose a VM Service (for example web or release
  /// without a native debug harness).
  Future<bool> get available async {
    try {
      await _ensureService();
      return true;
    } on Object {
      return false;
    }
  }

  /// Reads the selected isolate's live pause/runnable state and a bounded
  /// stack. The default isolate is the first non-system isolate, preferring
  /// one named `main`.
  Future<CockpitVmDebuggerStatus> status({
    String? isolateId,
    int stackLimit = 64,
  }) async {
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final isolate = await _call('getIsolate', () => service.getIsolate(id));
    final stack = await _readStack(service, id, stackLimit: stackLimit);
    final pause = isolate.pauseEvent;
    return CockpitVmDebuggerStatus(
      isolateId: id,
      isolateName: _text(isolate.name),
      runnable: isolate.runnable,
      pauseKind: _text(pause?.json?['kind']),
      pauseTimestampMs: _nonNegative(pause?.timestamp),
      stack: stack,
    );
  }

  /// Returns a bounded synchronous and asynchronous stack for an isolate.
  Future<CockpitVmStack> stack({String? isolateId, int limit = 64}) async {
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    return _readStack(service, id, stackLimit: limit);
  }

  /// Requests an isolate pause. The VM reports completion when the interrupt
  /// is queued; call [status] or [stack] to observe the resulting pause event.
  Future<void> pause({String? isolateId}) async {
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    await _call('pause', () => service.pause(id));
  }

  /// Resumes an isolate, optionally performing one debugger step.
  Future<void> resume({
    String? isolateId,
    CockpitVmStep? step,
    int? frameIndex,
  }) async {
    if (frameIndex != null && frameIndex < 1) {
      throw ArgumentError.value(
        frameIndex,
        'frameIndex',
        'Must be at least 1.',
      );
    }
    if (step == null && frameIndex != null) {
      throw ArgumentError.value(
        frameIndex,
        'frameIndex',
        'Requires a step mode.',
      );
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    await _call(
      'resume',
      () => service.resume(id, step: step?.wireValue, frameIndex: frameIndex),
    );
  }

  /// Evaluates an expression against a VM library/class/instance target.
  ///
  /// When [targetId] is omitted, the selected isolate's root library is used.
  /// The returned value is a summary; use [getObject] for an explicitly
  /// requested object body or collection page.
  Future<CockpitVmEvaluation> evaluate(
    String expression, {
    String? targetId,
    String? isolateId,
    Map<String, String>? scope,
    bool disableBreakpoints = true,
  }) async {
    final normalized = expression.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(expression, 'expression', 'Must not be empty.');
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    var target = _text(targetId);
    if (target == null) {
      final isolate = await _call('getIsolate', () => service.getIsolate(id));
      target = _text(isolate.rootLib?.id);
    }
    if (target == null) {
      throw const CockpitVmDebuggerException(
        operation: 'evaluate',
        reason: 'The isolate root library is unavailable.',
      );
    }
    final response = await _call(
      'evaluate',
      () => service.evaluate(
        id,
        target!,
        normalized,
        scope: scope,
        disableBreakpoints: disableBreakpoints,
      ),
    );
    return _evaluation(response.toJson());
  }

  /// Evaluates an expression in one frame of the current paused stack.
  Future<CockpitVmEvaluation> evaluateInFrame(
    int frameIndex,
    String expression, {
    String? isolateId,
    Map<String, String>? scope,
    bool disableBreakpoints = true,
  }) async {
    if (frameIndex < 0) {
      throw ArgumentError.value(
        frameIndex,
        'frameIndex',
        'Must be non-negative.',
      );
    }
    final normalized = expression.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(expression, 'expression', 'Must not be empty.');
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final response = await _call(
      'evaluateInFrame',
      () => service.evaluateInFrame(
        id,
        frameIndex,
        normalized,
        scope: scope,
        disableBreakpoints: disableBreakpoints,
      ),
    );
    return _evaluation(response.toJson());
  }

  /// Reads one VM object summary. Collection/list contents are bounded by
  /// [count] and [offset] and remain absent until explicitly requested.
  Future<CockpitVmValue> getObject(
    String objectId, {
    String? isolateId,
    int? offset,
    int? count,
  }) async {
    final normalized = objectId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(objectId, 'objectId', 'Must not be empty.');
    }
    if (offset != null && offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must be non-negative.');
    }
    if (count != null && (count < 1 || count > 1000)) {
      throw ArgumentError.value(count, 'count', 'Must be between 1 and 1000.');
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final value = await _call(
      'getObject',
      () => service.getObject(id, normalized, offset: offset, count: count),
    );
    return _value(value.toJson());
  }

  /// Calls one explicitly named Flutter/Dart service extension.
  ///
  /// The response is recursively bounded to prevent an accidental extension
  /// call from flooding test output. The raw VM response remains available to
  /// callers through the returned map up to those limits.
  Future<Map<String, Object?>> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, Object?> args = const <String, Object?>{},
    int maxDepth = 8,
    int maxEntries = 256,
    int maxString = 64 * 1024,
  }) async {
    final normalized = method.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(method, 'method', 'Must not be empty.');
    }
    _validateBounds(maxDepth, maxEntries, maxString);
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final response = await _call(
      'callServiceExtension',
      () => service.callServiceExtension(
        normalized,
        isolateId: id,
        args: Map<String, dynamic>.from(args),
      ),
    );
    final value = _boundedJson(
      response.toJson(),
      depth: 0,
      maxDepth: maxDepth,
      maxEntries: maxEntries,
      maxString: maxString,
    );
    return value is Map<String, Object?>
        ? value
        : <String, Object?>{'value': value};
  }

  /// Adds a source breakpoint to one isolate.
  Future<CockpitVmBreakpoint> addBreakpoint(
    String scriptUri,
    int line, {
    int? column,
    String? isolateId,
  }) async {
    final uri = scriptUri.trim();
    if (uri.isEmpty) {
      throw ArgumentError.value(scriptUri, 'scriptUri', 'Must not be empty.');
    }
    if (line < 1) {
      throw ArgumentError.value(line, 'line', 'Must be at least 1.');
    }
    if (column != null && column < 0) {
      throw ArgumentError.value(column, 'column', 'Must be non-negative.');
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final breakpoint = await _call(
      'addBreakpoint',
      () => service.addBreakpointWithScriptUri(id, uri, line, column: column),
    );
    return _breakpoint(breakpoint);
  }

  /// Removes a breakpoint from one isolate.
  Future<void> removeBreakpoint(
    String breakpointId, {
    String? isolateId,
  }) async {
    final normalized = breakpointId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        breakpointId,
        'breakpointId',
        'Must not be empty.',
      );
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    await _call(
      'removeBreakpoint',
      () => service.removeBreakpoint(id, normalized),
    );
  }

  /// Enables or disables an existing breakpoint without removing it.
  Future<CockpitVmBreakpoint> setBreakpointEnabled(
    String breakpointId,
    bool enabled, {
    String? isolateId,
  }) async {
    final normalized = breakpointId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        breakpointId,
        'breakpointId',
        'Must not be empty.',
      );
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final breakpoint = await _call(
      'setBreakpointState',
      () => service.setBreakpointState(id, normalized, enabled),
    );
    return _breakpoint(breakpoint);
  }

  /// Controls exception and isolate-exit pause behavior for the selected
  /// isolate. The VM protocol accepts `None`, `Unhandled`, or `All`.
  Future<void> setPauseMode({
    String? isolateId,
    String? exceptionPauseMode,
    bool? pauseOnExit,
  }) async {
    final mode = _text(exceptionPauseMode);
    if (mode != null &&
        !const <String>{'None', 'Unhandled', 'All'}.contains(mode)) {
      throw ArgumentError.value(
        exceptionPauseMode,
        'exceptionPauseMode',
        'Must be None, Unhandled, or All.',
      );
    }
    if (mode == null && pauseOnExit == null) {
      throw ArgumentError('Provide a pause mode or pauseOnExit.');
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    await _call(
      'setIsolatePauseMode',
      () => service.setIsolatePauseMode(
        id,
        exceptionPauseMode: mode,
        shouldPauseOnExit: pauseOnExit,
      ),
    );
  }

  /// Enables or disables breakpoint/stepping support for one VM library.
  Future<void> setLibraryDebuggable(
    String libraryId,
    bool enabled, {
    String? isolateId,
  }) async {
    final normalized = libraryId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(libraryId, 'libraryId', 'Must not be empty.');
    }
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    await _call(
      'setLibraryDebuggable',
      () => service.setLibraryDebuggable(id, normalized, enabled),
    );
  }

  /// Performs a VM source reload for the selected isolate and returns the
  /// bounded reload report. Flutter UI hot reload should normally use
  /// `cockpit dev reload`; this method is useful for a pure VM debug harness.
  Future<Map<String, Object?>> reloadSources({
    String? isolateId,
    bool force = false,
    String? rootLibUri,
    String? packagesUri,
  }) async {
    final service = await _ensureService();
    final id = await _resolveIsolate(service, isolateId);
    final report = await _call(
      'reloadSources',
      () => service.reloadSources(
        id,
        force: force,
        rootLibUri: rootLibUri,
        packagesUri: packagesUri,
      ),
    );
    final value = _boundedJson(
      report.toJson(),
      depth: 0,
      maxDepth: 8,
      maxEntries: 256,
      maxString: 64 * 1024,
    );
    return value is Map<String, Object?>
        ? value
        : <String, Object?>{'value': value};
  }

  /// Releases the VM socket. A later operation may establish a fresh session.
  Future<void> close() async {
    final pending = _connecting;
    if (pending != null) {
      try {
        await pending;
      } on Object {
        // The connection failed; there is nothing to dispose.
      }
    }
    final service = _service;
    _service = null;
    _connecting = null;
    _defaultIsolateId = null;
    await service?.dispose();
  }

  Future<VmService> _ensureService() {
    final current = _service;
    if (current != null) return Future<VmService>.value(current);
    final pending = _connecting;
    if (pending != null) return pending;
    final operation = _connect();
    _connecting = operation;
    return operation.whenComplete(() {
      if (identical(_connecting, operation)) _connecting = null;
    });
  }

  Future<VmService> _connect() async {
    if (kIsWeb) {
      throw const CockpitVmDebuggerException(
        operation: 'connect',
        reason: 'The Dart VM Service is unavailable on web.',
      );
    }
    try {
      final info = await developer.Service.getInfo().timeout(timeout);
      final uri = info.serverUri;
      if (uri == null) {
        throw const CockpitVmDebuggerException(
          operation: 'connect',
          reason: 'The VM Service URI is unavailable.',
        );
      }
      final service = await connectCockpitVmService(uri).timeout(timeout);
      try {
        final vm = await service.getVM().timeout(timeout);
        _defaultIsolateId = _pickIsolate(vm);
        if (_defaultIsolateId == null) {
          await service.dispose();
          throw const CockpitVmDebuggerException(
            operation: 'connect',
            reason: 'No runnable isolate is available.',
          );
        }
        _service = service;
        return service;
      } on Object {
        await service.dispose();
        rethrow;
      }
    } on CockpitVmDebuggerException {
      rethrow;
    } on Object catch (error) {
      throw CockpitVmDebuggerException(
        operation: 'connect',
        reason: _reason(error),
        cause: error,
      );
    }
  }

  Future<T> _call<T>(String operation, Future<T> Function() callback) async {
    try {
      return await callback().timeout(timeout);
    } on CockpitVmDebuggerException {
      rethrow;
    } on Object catch (error) {
      throw CockpitVmDebuggerException(
        operation: operation,
        reason: _reason(error),
        cause: error,
      );
    }
  }

  Future<String> _resolveIsolate(VmService service, String? isolateId) async {
    final explicit = _text(isolateId);
    if (explicit != null) return explicit;
    final cached = _defaultIsolateId;
    if (cached != null) return cached;
    final vm = await _call('getVM', service.getVM);
    final selected = _pickIsolate(vm);
    if (selected == null) {
      throw const CockpitVmDebuggerException(
        operation: 'getVM',
        reason: 'No runnable isolate is available.',
      );
    }
    _defaultIsolateId = selected;
    return selected;
  }

  Future<CockpitVmStack> _readStack(
    VmService service,
    String isolateId, {
    required int stackLimit,
  }) async {
    if (stackLimit < 1 || stackLimit > 500) {
      throw ArgumentError.value(
        stackLimit,
        'limit',
        'Must be between 1 and 500.',
      );
    }
    final raw = await _call(
      'getStack',
      () => service.getStack(isolateId, limit: stackLimit),
    );
    return CockpitVmStack(
      isolateId: isolateId,
      frames: _frames(raw.frames),
      asyncFrames: _frames(raw.asyncCausalFrames),
      messageCount: raw.messages?.length ?? 0,
      truncated: raw.truncated ?? false,
    );
  }

  static List<CockpitVmFrame> _frames(List<Frame>? source) {
    if (source == null || source.isEmpty) return const <CockpitVmFrame>[];
    return <CockpitVmFrame>[
      for (final frame in source.take(500))
        CockpitVmFrame(
          index: frame.index ?? 0,
          name: _text(frame.function?.name) ?? _text(frame.code?.name),
          kind: _text(frame.kind),
          location: _location(frame.location),
          variables: _variables(frame.vars),
        ),
    ];
  }

  static List<CockpitVmVariable> _variables(List<BoundVariable>? source) {
    if (source == null || source.isEmpty) return const <CockpitVmVariable>[];
    return <CockpitVmVariable>[
      for (final variable in source.take(64))
        if (_text(variable.name) case final name?)
          CockpitVmVariable(
            name: name,
            value: _valueFromObject(variable.value),
          ),
    ];
  }

  static CockpitVmValue? _valueFromObject(Object? value) {
    if (value is! Obj) return null;
    return _value(value.toJson());
  }

  static CockpitVmLocation? _location(SourceLocation? location) {
    if (location == null) return null;
    return CockpitVmLocation(
      uri: _text(location.script?.uri),
      line: _nonPositive(location.line),
      column: _nonNegative(location.column),
    );
  }

  static CockpitVmEvaluation _evaluation(Map<String, dynamic> raw) {
    final value = _value(raw);
    final error = _text(raw['message']);
    return CockpitVmEvaluation(
      value: value.error == null ? value : null,
      error: error ?? value.error,
    );
  }

  static CockpitVmValue _value(Map<String, dynamic> raw) {
    final classRef = raw['classRef'];
    final className = classRef is Map ? _text(classRef['name']) : null;
    final value = _text(raw['valueAsString']);
    final error = _text(raw['message']);
    return CockpitVmValue(
      id: _text(raw['id']),
      kind: _text(raw['kind']),
      type: _text(raw['type']),
      className: className,
      value: value,
      length: _nonNegative(raw['length']),
      offset: _nonNegative(raw['offset']),
      count: _nonNegative(raw['count']),
      error: error,
      truncated: raw['valueAsStringIsTruncated'] == true,
    );
  }

  static CockpitVmBreakpoint _breakpoint(Breakpoint value) {
    final rawLocation = value.location;
    CockpitVmLocation? location;
    if (rawLocation is SourceLocation) location = _location(rawLocation);
    return CockpitVmBreakpoint(
      id: _text(value.id) ?? 'unknown',
      number: _nonNegative(value.breakpointNumber),
      enabled: value.enabled,
      resolved: value.resolved,
      location: location,
    );
  }

  static String? _pickIsolate(VM vm) {
    final isolates = vm.isolates ?? const <IsolateRef>[];
    for (final isolate in isolates) {
      if (isolate.isSystemIsolate != true &&
          _text(isolate.name)?.toLowerCase() == 'main' &&
          _text(isolate.id) != null) {
        return isolate.id;
      }
    }
    for (final isolate in isolates) {
      if (isolate.isSystemIsolate != true && _text(isolate.id) != null) {
        return isolate.id;
      }
    }
    return isolates
        .map((item) => _text(item.id))
        .whereType<String>()
        .firstOrNull;
  }

  static void _validateBounds(int depth, int entries, int stringLength) {
    if (depth < 1 || depth > 32) {
      throw ArgumentError.value(depth, 'maxDepth', 'Must be between 1 and 32.');
    }
    if (entries < 1 || entries > 10000) {
      throw ArgumentError.value(
        entries,
        'maxEntries',
        'Must be between 1 and 10000.',
      );
    }
    if (stringLength < 1 || stringLength > 1024 * 1024) {
      throw ArgumentError.value(
        stringLength,
        'maxString',
        'Must be between 1 and 1048576.',
      );
    }
  }

  static Object? _boundedJson(
    Object? value, {
    required int depth,
    required int maxDepth,
    required int maxEntries,
    required int maxString,
  }) {
    if (value is String) {
      return value.length <= maxString
          ? value
          : '${value.substring(0, maxString - 1)}…';
    }
    if (value is num || value is bool || value == null) return value;
    if (depth >= maxDepth) return '[depth-limit]';
    if (value is List) {
      return <Object?>[
        for (final item in value.take(maxEntries))
          _boundedJson(
            item,
            depth: depth + 1,
            maxDepth: maxDepth,
            maxEntries: maxEntries,
            maxString: maxString,
          ),
      ];
    }
    if (value is Map) {
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= maxEntries) break;
        final key = entry.key.toString();
        result[key] = _boundedJson(
          entry.value,
          depth: depth + 1,
          maxDepth: maxDepth,
          maxEntries: maxEntries,
          maxString: maxString,
        );
        count += 1;
      }
      return result;
    }
    return value.toString();
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static int? _nonNegative(Object? value) {
    if (value is int) return value < 0 ? null : value;
    if (value is num &&
        value.isFinite &&
        value >= 0 &&
        value == value.round()) {
      return value.toInt();
    }
    return null;
  }

  static int? _nonPositive(Object? value) {
    final result = _nonNegative(value);
    return result == null || result < 1 ? null : result;
  }

  static String _reason(Object error) {
    final text = error.toString().trim();
    return text.isEmpty ? error.runtimeType.toString() : text;
  }
}

/// A debugger operation could not be completed or the target has no VM
/// Service. The operation name is stable for compact test diagnostics.
final class CockpitVmDebuggerException implements Exception {
  const CockpitVmDebuggerException({
    required this.operation,
    required this.reason,
    this.cause,
  });

  final String operation;
  final String reason;
  final Object? cause;

  @override
  String toString() => 'Cockpit VM debugger $operation failed: $reason';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
