import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cockpit_protocol/cockpit_protocol.dart';

typedef CockpitPerformancePluginStart =
    FutureOr<void> Function(CockpitPerformancePluginContext context);

typedef CockpitPerformancePluginStop =
    FutureOr<void> Function(CockpitPerformancePluginStats stats);

/// Limits and filtering applied to one plugin during a capture.
final class CockpitPerformancePluginOptions {
  const CockpitPerformancePluginOptions({
    this.maxEvents = 10000,
    this.maxPayloadBytes = 64 * 1024,
    this.maxPayloadDepth = 8,
    this.sampleEvery = Duration.zero,
    this.categories = const <String>{},
    this.lifecycleTimeout = const Duration(seconds: 2),
  });

  CockpitPerformancePluginOptions._copy({
    required this.maxEvents,
    required this.maxPayloadBytes,
    required this.maxPayloadDepth,
    required this.sampleEvery,
    required this.lifecycleTimeout,
    required Set<String> categories,
  }) : categories = Set<String>.unmodifiable(
         categories.map((value) => value.trim()),
       );

  final int maxEvents;
  final int maxPayloadBytes;
  final int maxPayloadDepth;
  final Duration sampleEvery;
  final Set<String> categories;
  final Duration lifecycleTimeout;

  /// Takes an immutable snapshot so a caller cannot mutate capture policy
  /// after a plugin has been registered.
  CockpitPerformancePluginOptions snapshot() =>
      CockpitPerformancePluginOptions._copy(
        maxEvents: maxEvents,
        maxPayloadBytes: maxPayloadBytes,
        maxPayloadDepth: maxPayloadDepth,
        sampleEvery: sampleEvery,
        lifecycleTimeout: lifecycleTimeout,
        categories: categories,
      );

  void validate() {
    if (maxEvents < 1 ||
        maxEvents > 200000 ||
        maxPayloadBytes < 256 ||
        maxPayloadBytes > 1024 * 1024 ||
        maxPayloadDepth < 1 ||
        maxPayloadDepth > 32 ||
        sampleEvery < Duration.zero ||
        lifecycleTimeout <= Duration.zero ||
        lifecycleTimeout > const Duration(minutes: 1) ||
        categories.length > 256 ||
        categories.any(
          (value) => value.trim().isEmpty || value.trim().length > 128,
        )) {
      throw ArgumentError('Performance plugin options are invalid.');
    }
  }
}

/// A development-only instrumentation plugin.
///
/// A plugin is inert until a caller explicitly runs [CockpitTester.profile] or
/// starts a collector capture. This makes application instrumentation safe to
/// leave installed in a development shell without changing normal app work.
final class CockpitPerformancePlugin {
  CockpitPerformancePlugin({
    required String id,
    required this.start,
    this.stop,
    String? version,
    CockpitPerformancePluginOptions options =
        const CockpitPerformancePluginOptions(),
  }) : id = id.trim(),
       version = version?.trim(),
       options = options.snapshot() {
    if (this.id.isEmpty || this.id.length > 128) {
      throw ArgumentError.value(id, 'id', 'Must be 1–128 characters.');
    }
    if (this.version != null &&
        (this.version!.isEmpty || this.version!.length > 128)) {
      throw ArgumentError.value(version, 'version', 'Must not be empty.');
    }
    this.options.validate();
  }

  final String id;
  final String? version;
  final CockpitPerformancePluginStart start;
  final CockpitPerformancePluginStop? stop;
  final CockpitPerformancePluginOptions options;
}

/// Optional source mapping attached to plugin events.
final class CockpitPerformanceLocation {
  const CockpitPerformanceLocation({this.uri, this.line, this.column});

  final String? uri;
  final int? line;
  final int? column;

  bool get isValid =>
      (uri == null || uri!.trim().isNotEmpty) &&
      (line == null || line! > 0) &&
      (column == null || column! >= 0);
}

/// Context supplied to a plugin for one active capture.
final class CockpitPerformancePluginContext {
  const CockpitPerformancePluginContext({
    required this.pluginId,
    required this.sink,
    required this.startedAtUs,
    this.isolateId,
  });

  final String pluginId;
  final CockpitPerformanceSink sink;
  final int startedAtUs;
  final String? isolateId;
}

/// A completed or in-progress span returned by [CockpitPerformanceSink.begin].
final class CockpitPerformanceSpan {
  CockpitPerformanceSpan._(
    this._sink,
    this._name,
    this._category,
    this._startUs,
    this._location,
    this._args,
  );

  final CockpitPerformanceSink _sink;
  final String _name;
  final String _category;
  final int _startUs;
  final CockpitPerformanceLocation? _location;
  final Map<String, Object?> _args;
  var _ended = false;

  /// Ends the span once. Repeated calls are safe no-ops.
  void end({Map<String, Object?> args = const <String, Object?>{}}) {
    if (_ended) return;
    _ended = true;
    _sink._span(
      name: _name,
      category: _category,
      startUs: _startUs,
      endUs: _sink.nowUs,
      args: <String, Object?>{..._args, ...args},
      location: _location,
    );
  }
}

/// Synchronous, bounded event sink exposed to a plugin or AOP adapter.
final class CockpitPerformanceSink {
  CockpitPerformanceSink._(this._capture, this._plugin, this._isolateId);

  final CockpitPerformancePluginCapture _capture;
  final CockpitPerformancePlugin _plugin;
  final String? _isolateId;

  bool get enabled =>
      _capture.isRecording &&
      !_capture.failed &&
      _capture.isAvailable(_plugin.id);

  /// Returns the VM-compatible monotonic timeline timestamp in microseconds.
  int get nowUs => developer.Timeline.now;

  void instant(
    String name, {
    String category = 'app',
    Map<String, Object?> args = const <String, Object?>{},
    CockpitPerformanceLocation? location,
  }) {
    _record(
      name: name,
      category: category,
      timestampUs: nowUs,
      durationUs: 0,
      phase: 'i',
      args: args,
      location: location,
      kind: _PluginEventKind.instant,
    );
  }

  CockpitPerformanceSpan begin(
    String name, {
    String category = 'app',
    Map<String, Object?> args = const <String, Object?>{},
    CockpitPerformanceLocation? location,
  }) => CockpitPerformanceSpan._(
    this,
    name,
    category,
    nowUs,
    location,
    Map<String, Object?>.unmodifiable(args),
  );

  void span(
    String name, {
    required int startUs,
    required int endUs,
    String category = 'app',
    Map<String, Object?> args = const <String, Object?>{},
    CockpitPerformanceLocation? location,
  }) {
    _span(
      name: name,
      category: category,
      startUs: startUs,
      endUs: endUs,
      args: args,
      location: location,
    );
  }

  void counter(
    String name,
    num value, {
    String category = 'app',
    Map<String, Object?> args = const <String, Object?>{},
    CockpitPerformanceLocation? location,
  }) {
    if (!value.isFinite) {
      _capture.invalid(_plugin.id);
      return;
    }
    _record(
      name: name,
      category: category,
      timestampUs: nowUs,
      durationUs: 0,
      phase: 'C',
      args: <String, Object?>{...args, 'value': value},
      location: location,
      kind: _PluginEventKind.counter,
      applySampling: true,
    );
  }

  void sample(
    String name,
    num value, {
    String category = 'sample',
    Map<String, Object?> args = const <String, Object?>{},
    CockpitPerformanceLocation? location,
  }) =>
      counter(name, value, category: category, args: args, location: location);

  Future<T> trace<T>(
    String name,
    FutureOr<T> Function() action, {
    String category = 'app',
    Map<String, Object?> args = const <String, Object?>{},
    CockpitPerformanceLocation? location,
  }) async {
    final span = begin(
      name,
      category: category,
      args: args,
      location: location,
    );
    try {
      return await action();
    } finally {
      span.end();
    }
  }

  void _span({
    required String name,
    required String category,
    required int startUs,
    required int endUs,
    required Map<String, Object?> args,
    required CockpitPerformanceLocation? location,
  }) {
    if (endUs < startUs) {
      _capture.invalid(_plugin.id);
      return;
    }
    _record(
      name: name,
      category: category,
      timestampUs: startUs,
      durationUs: endUs - startUs,
      phase: 'X',
      args: args,
      location: location,
      kind: _PluginEventKind.span,
    );
  }

  void _record({
    required String name,
    required String category,
    required int timestampUs,
    required int durationUs,
    required String phase,
    required Map<String, Object?> args,
    required CockpitPerformanceLocation? location,
    required _PluginEventKind kind,
    bool applySampling = false,
  }) {
    if (!enabled) return;
    final normalizedName = name.trim();
    final normalizedCategory = category.trim();
    if (normalizedName.isEmpty ||
        normalizedName.length > 256 ||
        normalizedCategory.isEmpty ||
        normalizedCategory.length > 128 ||
        durationUs < 0 ||
        location != null && !location.isValid ||
        _plugin.options.categories.isNotEmpty &&
            !_plugin.options.categories.contains(normalizedCategory)) {
      _capture.invalid(_plugin.id);
      return;
    }
    if (applySampling && !_capture.shouldSample(_plugin.id, normalizedName)) {
      _capture.dropped(_plugin.id);
      return;
    }
    final payload = _sanitizeArgs(
      args,
      maxDepth: _plugin.options.maxPayloadDepth,
      maxBytes: _plugin.options.maxPayloadBytes,
    );
    if (payload.invalid) {
      _capture.invalid(_plugin.id);
      return;
    }
    if (payload.truncated) _capture.truncated(_plugin.id);
    if (!_capture._add(
      _plugin.id,
      CockpitPerformanceEvent(
        name: normalizedName,
        category: normalizedCategory,
        timestampUs: timestampUs,
        durationUs: durationUs,
        phase: phase,
        args: payload.value,
        source: _plugin.id,
        isolateId: _isolateId,
        uri: location?.uri?.trim(),
        line: location?.line,
        column: location?.column,
      ),
      kind,
    )) {
      _capture.dropped(_plugin.id);
    }
  }
}

/// Registry configured on a development-only [FlutterCockpitConfig].
final class CockpitPerformancePluginRegistry {
  CockpitPerformancePluginRegistry({
    Iterable<CockpitPerformancePlugin> plugins =
        const <CockpitPerformancePlugin>[],
  }) {
    replace(plugins);
  }

  final Map<String, CockpitPerformancePlugin> _plugins =
      <String, CockpitPerformancePlugin>{};

  List<CockpitPerformancePlugin> get plugins =>
      List<CockpitPerformancePlugin>.unmodifiable(_plugins.values);

  void replace(Iterable<CockpitPerformancePlugin> plugins) {
    final next = <String, CockpitPerformancePlugin>{};
    for (final plugin in plugins) {
      if (next.containsKey(plugin.id)) {
        throw ArgumentError.value(
          plugin.id,
          'plugins',
          'Plugin ids must be unique.',
        );
      }
      next[plugin.id] = plugin;
    }
    if (next.length > 128) {
      throw ArgumentError.value(
        plugins,
        'plugins',
        'At most 128 performance plugins may be registered.',
      );
    }
    _plugins
      ..clear()
      ..addAll(next);
  }

  void register(CockpitPerformancePlugin plugin) {
    if (_plugins.containsKey(plugin.id)) {
      throw ArgumentError.value(
        plugin.id,
        'plugin',
        'Plugin id is already registered.',
      );
    }
    if (_plugins.length >= 128) {
      throw ArgumentError.value(
        plugin,
        'plugin',
        'At most 128 performance plugins may be registered.',
      );
    }
    _plugins[plugin.id] = plugin;
  }

  bool remove(String id) => _plugins.remove(id) != null;

  CockpitPerformancePluginCapture capture({
    Iterable<CockpitPerformancePlugin> additional =
        const <CockpitPerformancePlugin>[],
    int maxEvents = 200000,
    String? isolateId,
    void Function(CockpitPerformanceEvent event)? onEvent,
  }) {
    if (maxEvents < 0 || maxEvents > 200000) {
      throw ArgumentError.value(
        maxEvents,
        'maxEvents',
        'Must be between 0 and 200000.',
      );
    }
    final selected = <String, CockpitPerformancePlugin>{..._plugins};
    for (final plugin in additional) {
      if (selected.containsKey(plugin.id)) {
        throw ArgumentError.value(
          plugin.id,
          'additional',
          'Plugin id is already registered.',
        );
      }
      selected[plugin.id] = plugin;
    }
    if (selected.length > 128) {
      throw ArgumentError.value(
        additional,
        'additional',
        'At most 128 performance plugins may be captured.',
      );
    }
    final normalizedIsolateId = isolateId?.trim();
    if (normalizedIsolateId != null && normalizedIsolateId.isEmpty) {
      throw ArgumentError.value(isolateId, 'isolateId', 'Must not be blank.');
    }
    return CockpitPerformancePluginCapture._(
      selected.values,
      isolateId: normalizedIsolateId,
      maxEvents: maxEvents,
      onEvent: onEvent,
    );
  }
}

/// One bounded plugin capture. It is intentionally separate from the frame
/// collector so app instrumentation can be reused by other capture hosts.
final class CockpitPerformancePluginCapture {
  CockpitPerformancePluginCapture._(
    Iterable<CockpitPerformancePlugin> plugins, {
    required this.isolateId,
    required int maxEvents,
    required this.onEvent,
  }) : _maxEvents = maxEvents,
       _registrations = <_PluginRegistration>[
         for (final plugin in plugins) _PluginRegistration(plugin),
       ];

  final String? isolateId;
  final void Function(CockpitPerformanceEvent event)? onEvent;
  final int _maxEvents;
  final List<_PluginRegistration> _registrations;
  bool isRunning = false;
  bool _started = false;
  bool _recording = false;
  int _retentionDrops = 0;
  int _retainedEvents = 0;

  bool get isRecording => _recording;
  int get retentionDrops => _retentionDrops;

  Future<void> start() async {
    if (isRunning) throw StateError('Plugin capture is already running.');
    if (_started) throw StateError('Plugin capture cannot be reused.');
    _started = true;
    isRunning = true;
    for (final registration in _registrations) {
      registration.startAttempted = true;
      try {
        await _withinLifecycleTimeout(
          () => registration.plugin.start(
            CockpitPerformancePluginContext(
              pluginId: registration.plugin.id,
              sink: CockpitPerformanceSink._(
                this,
                registration.plugin,
                isolateId,
              ),
              startedAtUs: developer.Timeline.now,
              isolateId: isolateId,
            ),
          ),
          registration.plugin.options.lifecycleTimeout,
        );
        registration.state = 'available';
      } on Object catch (error) {
        registration.state = 'failed';
        registration.reason = _boundedReason(error);
      }
    }
  }

  /// Opens the measured window after plugin setup has completed.
  void beginWindow() {
    if (!isRunning) {
      throw StateError('Plugin capture has not started.');
    }
    _recording = true;
  }

  /// Closes the measured window without running plugin cleanup callbacks.
  /// Cleanup is deferred to [stop] so teardown is not attributed to the capture.
  void endWindow() {
    _recording = false;
  }

  Future<List<CockpitPerformanceEvent>> stop({int maxEvents = 200000}) async {
    if (maxEvents < 0 || maxEvents > 200000) {
      throw ArgumentError.value(
        maxEvents,
        'maxEvents',
        'Must be between 0 and 200000.',
      );
    }
    if (!isRunning) return const <CockpitPerformanceEvent>[];
    _recording = false;
    isRunning = false;
    final retained = _retainEvents(maxEvents);
    for (final registration in _registrations) {
      final callback = registration.plugin.stop;
      if (callback == null || !registration.startAttempted) continue;
      try {
        await _withinLifecycleTimeout(
          () => callback(registration.stats()),
          registration.plugin.options.lifecycleTimeout,
        );
      } on Object catch (error) {
        final reason = _boundedReason(error);
        registration.state = 'failed';
        registration.reason = registration.reason == null
            ? reason
            : '${registration.reason}; cleanup: $reason';
      }
    }
    return retained;
  }

  List<CockpitPerformancePluginStats> stats() =>
      <CockpitPerformancePluginStats>[
        for (final registration in _registrations) registration.stats(),
      ];

  bool _add(String id, CockpitPerformanceEvent event, _PluginEventKind kind) {
    final registration = _registration(id);
    if (registration == null ||
        registration.state != 'available' ||
        _retainedEvents >= _maxEvents ||
        registration.events.length >= registration.plugin.options.maxEvents) {
      return false;
    }
    registration.events.add(event);
    final sink = onEvent;
    if (sink != null) {
      try {
        sink(event);
      } on Object {
        // Archive failures are reported by the archive itself and must never
        // make an instrumented application action fail.
      }
    }
    _retainedEvents += 1;
    registration.eventCount += 1;
    switch (kind) {
      case _PluginEventKind.span:
        registration.spanCount += 1;
        registration.durationUs += event.durationUs;
        if (event.durationUs > registration.maxDurationUs) {
          registration.maxDurationUs = event.durationUs;
        }
      case _PluginEventKind.instant:
        registration.instantCount += 1;
      case _PluginEventKind.counter:
        registration.counterCount += 1;
    }
    registration.categories[event.category] =
        (registration.categories[event.category] ?? 0) + 1;
    return true;
  }

  void dropped(String id) {
    final registration = _registration(id);
    if (registration != null) registration.droppedEvents += 1;
  }

  void invalid(String id) {
    final registration = _registration(id);
    if (registration != null) registration.invalidEvents += 1;
  }

  void truncated(String id) {
    final registration = _registration(id);
    if (registration != null) registration.truncatedEvents += 1;
  }

  bool shouldSample(String id, String name) {
    final registration = _registration(id);
    if (registration == null) return false;
    final interval = registration.plugin.options.sampleEvery;
    if (interval == Duration.zero) return true;
    final now = developer.Timeline.now;
    final previous = registration.lastSampleUs[name];
    if (previous != null && now - previous < interval.inMicroseconds) {
      return false;
    }
    registration.lastSampleUs[name] = now;
    return true;
  }

  bool isAvailable(String id) => _registration(id)?.state == 'available';

  bool get failed =>
      _registrations.isNotEmpty &&
      _registrations.every((registration) => registration.state == 'failed');

  _PluginRegistration? _registration(String id) {
    for (final registration in _registrations) {
      if (registration.plugin.id == id) return registration;
    }
    return null;
  }

  List<CockpitPerformanceEvent> _retainEvents(int maxEvents) {
    final events = <CockpitPerformanceEvent>[
      for (final registration in _registrations) ...registration.events,
    ]..sort((left, right) => left.timestampUs.compareTo(right.timestampUs));
    if (events.length <= maxEvents) return events;
    final retained = events.take(maxEvents).toList(growable: false);
    final retainedIdentity = Set<CockpitPerformanceEvent>.identity()
      ..addAll(retained);
    for (final registration in _registrations) {
      _retentionDrops += registration.retain(retainedIdentity);
    }
    _retainedEvents = retained.length;
    return retained;
  }

  Future<void> _withinLifecycleTimeout(
    FutureOr<void> Function() action,
    Duration timeout,
  ) async {
    try {
      await (() async => action())().timeout(timeout);
    } on TimeoutException {
      throw TimeoutException(
        'Plugin lifecycle exceeded ${timeout.inMilliseconds}ms.',
      );
    }
  }
}

enum _PluginEventKind { span, instant, counter }

final class _PluginRegistration {
  _PluginRegistration(this.plugin);

  final CockpitPerformancePlugin plugin;
  final List<CockpitPerformanceEvent> events = <CockpitPerformanceEvent>[];
  final Map<String, int> categories = <String, int>{};
  final Map<String, int> lastSampleUs = <String, int>{};
  String state = 'unavailable';
  bool startAttempted = false;
  String? reason;
  int eventCount = 0;
  int spanCount = 0;
  int instantCount = 0;
  int counterCount = 0;
  int droppedEvents = 0;
  int invalidEvents = 0;
  int truncatedEvents = 0;
  int durationUs = 0;
  int maxDurationUs = 0;

  int retain(Set<CockpitPerformanceEvent> retained) {
    final next = events.where(retained.contains).toList(growable: false);
    final removed = events.length - next.length;
    if (removed == 0) return 0;
    events
      ..clear()
      ..addAll(next);
    droppedEvents += removed;
    _rebuildStats();
    return removed;
  }

  void _rebuildStats() {
    eventCount = 0;
    spanCount = 0;
    instantCount = 0;
    counterCount = 0;
    durationUs = 0;
    maxDurationUs = 0;
    categories.clear();
    for (final event in events) {
      eventCount += 1;
      switch (event.phase) {
        case 'X':
          spanCount += 1;
          durationUs += event.durationUs;
          if (event.durationUs > maxDurationUs) {
            maxDurationUs = event.durationUs;
          }
        case 'C':
          counterCount += 1;
        default:
          instantCount += 1;
      }
      categories[event.category] = (categories[event.category] ?? 0) + 1;
    }
  }

  CockpitPerformancePluginStats stats() => CockpitPerformancePluginStats(
    id: plugin.id,
    state: state,
    version: plugin.version,
    reason: reason,
    eventCount: eventCount,
    spanCount: spanCount,
    instantCount: instantCount,
    counterCount: counterCount,
    dropped: droppedEvents,
    invalid: invalidEvents,
    truncated: truncatedEvents,
    durationUs: durationUs,
    maxDurationUs: maxDurationUs,
    categories: categories,
  );
}

final class _SanitizedPayload {
  const _SanitizedPayload(
    this.value, {
    this.invalid = false,
    this.truncated = false,
  });

  final Map<String, Object?> value;
  final bool invalid;
  final bool truncated;
}

_SanitizedPayload _sanitizeArgs(
  Map<String, Object?> args, {
  required int maxDepth,
  required int maxBytes,
}) {
  try {
    final normalized = <String, Object?>{};
    var truncated = false;
    var invalid = false;
    Object? visit(Object? value, int depth) {
      if (depth > maxDepth) {
        truncated = true;
        return '<depth-limit>';
      }
      if (value == null || value is String || value is bool) return value;
      if (value is num) {
        if (!value.isFinite) invalid = true;
        return value.isFinite ? value : null;
      }
      if (value is List) {
        return value
            .map((item) => visit(item, depth + 1))
            .toList(growable: false);
      }
      if (value is Map) {
        final map = <String, Object?>{};
        for (final entry in value.entries) {
          if (entry.key is String) {
            map[entry.key as String] = visit(entry.value, depth + 1);
          } else {
            invalid = true;
          }
        }
        return map;
      }
      truncated = true;
      return '<unsupported:${value.runtimeType}>';
    }

    normalized.addAll(args.map((key, value) => MapEntry(key, visit(value, 1))));
    final encoded = jsonEncode(normalized);
    if (utf8.encode(encoded).length > maxBytes) {
      return const _SanitizedPayload(<String, Object?>{}, truncated: true);
    }
    return _SanitizedPayload(
      normalized,
      invalid: invalid,
      truncated: truncated,
    );
  } on Object {
    return const _SanitizedPayload(<String, Object?>{}, invalid: true);
  }
}

String _boundedReason(Object error) {
  final text = error.toString().trim();
  if (text.isEmpty) return 'plugin failed';
  return text.length <= 512 ? text : '${text.substring(0, 511)}…';
}
