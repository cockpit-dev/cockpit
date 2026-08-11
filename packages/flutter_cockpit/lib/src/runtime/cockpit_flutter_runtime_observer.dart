import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'cockpit_runtime_event.dart';
import 'cockpit_runtime_observer.dart';
import 'cockpit_runtime_query.dart';
import 'cockpit_runtime_snapshot.dart';
import 'cockpit_short_id.dart';

typedef CockpitRuntimeCurrentRouteProvider = String? Function();
typedef CockpitRuntimeCriticalEventHandler =
    void Function(CockpitRuntimeEvent event);

final class CockpitFlutterRuntimeObserver implements CockpitRuntimeObserver {
  CockpitFlutterRuntimeObserver({
    required CockpitRuntimeCurrentRouteProvider routeNameProvider,
    this.onCriticalEvent,
    this.captureDebugPrint = true,
    this.capturePrint = true,
    this.maxRetainedEvents = 120,
    this.maxMessageLength = 512,
    this.maxDetailLength = 512,
    this.maxStackTraceLines = 12,
  }) : _routeNameProvider = routeNameProvider {
    _install();
  }

  final CockpitRuntimeCurrentRouteProvider _routeNameProvider;
  final CockpitRuntimeCriticalEventHandler? onCriticalEvent;
  final bool captureDebugPrint;
  final bool capturePrint;
  final int maxRetainedEvents;
  final int maxMessageLength;
  final int maxDetailLength;
  final int maxStackTraceLines;
  final ListQueue<CockpitRuntimeEvent> _events =
      ListQueue<CockpitRuntimeEvent>();

  FlutterExceptionHandler? _previousFlutterErrorHandler;
  ErrorCallback? _previousPlatformErrorHandler;
  DebugPrintCallback? _previousDebugPrint;
  bool _disposed = false;
  bool _installedDebugPrintOverride = false;

  T runWithDiagnosticsZone<T>(
    T Function() body, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    T? result;
    runZonedGuarded(
      () {
        result = body();
      },
      (error, stackTrace) {
        recordUnhandledError(error, stackTrace, source: 'Zone');
        onError?.call(error, stackTrace);
      },
      zoneSpecification: capturePrint
          ? ZoneSpecification(
              print: (self, parent, zone, line) {
                recordDebugLog(line, source: 'print');
                parent.print(zone, line);
              },
            )
          : null,
    );
    return result as T;
  }

  @override
  CockpitRuntimeSnapshot snapshot({
    int maxEntries = 8,
    CockpitRuntimeQuery query = const CockpitRuntimeQuery(),
  }) {
    final matchingEntries = _events
        .where((entry) => _matchesQuery(entry, query))
        .toList(growable: false);
    final boundedMax = maxEntries < 0 ? 0 : maxEntries;
    final startIndex = matchingEntries.length > boundedMax
        ? matchingEntries.length - boundedMax
        : 0;
    final visibleEntries = boundedMax == 0
        ? const <CockpitRuntimeEvent>[]
        : matchingEntries.sublist(startIndex);
    return CockpitRuntimeSnapshot(
      totalEntryCount: matchingEntries.length,
      errorCount: matchingEntries.where((entry) => entry.isError).length,
      warningCount: matchingEntries.where((entry) => entry.isWarning).length,
      entries: visibleEntries,
      capturedEntryCount: _events.length,
      query: query,
      truncated: matchingEntries.length > visibleEntries.length,
    );
  }

  @override
  void clear() {
    _events.clear();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    if (identical(FlutterError.onError, _handleFlutterError)) {
      FlutterError.onError = _previousFlutterErrorHandler;
    }
    if (identical(PlatformDispatcher.instance.onError, _handlePlatformError)) {
      PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
    }
    if (_installedDebugPrintOverride &&
        identical(debugPrint, _handleDebugPrint)) {
      debugPrint = _previousDebugPrint ?? debugPrintThrottled;
    }
    _disposed = true;
  }

  @visibleForTesting
  void recordDebugLog(
    String? message, {
    String? source,
    Map<String, String> details = const <String, String>{},
  }) {
    if (message == null || message.isEmpty) {
      return;
    }
    _record(
      CockpitRuntimeEvent(
        eventId: _nextEventId(),
        kind: CockpitRuntimeEventKind.debugLog,
        severity: CockpitRuntimeEventSeverity.info,
        message: _truncate(message, maxMessageLength),
        recordedAt: DateTime.now().toUtc(),
        routeName: _routeNameProvider(),
        source: source ?? 'debugPrint',
        details: _boundedDetails(details),
      ),
    );
  }

  @visibleForTesting
  void recordUnhandledError(
    Object error,
    StackTrace stackTrace, {
    String? source,
  }) {
    _recordCritical(
      CockpitRuntimeEvent(
        eventId: _nextEventId(),
        kind: CockpitRuntimeEventKind.uncaughtError,
        severity: CockpitRuntimeEventSeverity.error,
        message: _truncate(error.toString(), maxMessageLength),
        recordedAt: DateTime.now().toUtc(),
        routeName: _routeNameProvider(),
        source: source ?? 'PlatformDispatcher.onError',
        stackTracePreview: _formatStackTrace(stackTrace),
        stackTraceTruncated: _stackTraceWasTruncated(stackTrace),
      ),
    );
  }

  @visibleForTesting
  void recordFlutterFrameworkError(
    FlutterErrorDetails details, {
    String? source,
  }) {
    final exceptionMessage = details.exceptionAsString();
    final library = details.library;
    _recordCritical(
      CockpitRuntimeEvent(
        eventId: _nextEventId(),
        kind: CockpitRuntimeEventKind.flutterError,
        severity: CockpitRuntimeEventSeverity.error,
        message: _truncate(exceptionMessage, maxMessageLength),
        recordedAt: DateTime.now().toUtc(),
        routeName: _routeNameProvider(),
        source: source ?? library ?? 'FlutterError.onError',
        details: _boundedDetails(<String, String>{
          if (library != null && library.isNotEmpty) 'library': library,
          if (details.context != null) 'context': '${details.context}',
        }),
        stackTracePreview: details.stack == null
            ? null
            : _formatStackTrace(details.stack!),
        stackTraceTruncated: details.stack == null
            ? false
            : _stackTraceWasTruncated(details.stack!),
      ),
    );
  }

  void _install() {
    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;
    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _handlePlatformError;
    if (captureDebugPrint && !_isTestWidgetsBinding()) {
      _previousDebugPrint = debugPrint;
      debugPrint = _handleDebugPrint;
      _installedDebugPrintOverride = true;
    }
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    recordFlutterFrameworkError(details);
    _previousFlutterErrorHandler?.call(details);
  }

  bool _handlePlatformError(Object error, StackTrace stackTrace) {
    recordUnhandledError(error, stackTrace);
    return _previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
  }

  void _handleDebugPrint(String? message, {int? wrapWidth}) {
    recordDebugLog(message);
    final previous = _previousDebugPrint;
    if (previous != null) {
      previous(message, wrapWidth: wrapWidth);
    }
  }

  void _recordCritical(CockpitRuntimeEvent event) {
    _record(event);
    onCriticalEvent?.call(event);
  }

  void _record(CockpitRuntimeEvent event) {
    if (_disposed) {
      return;
    }
    _events.add(event);
    while (_events.length > maxRetainedEvents) {
      _events.removeFirst();
    }
  }

  bool _matchesQuery(CockpitRuntimeEvent event, CockpitRuntimeQuery query) {
    if (query.onlyErrors && !event.isError) {
      return false;
    }
    final messageContains = query.messageContains;
    if (messageContains != null &&
        messageContains.isNotEmpty &&
        !event.message.contains(messageContains)) {
      return false;
    }
    return true;
  }

  String _nextEventId() => cockpitShortId('e');

  Map<String, String> _boundedDetails(Map<String, String> details) {
    final bounded = <String, String>{};
    for (final entry in details.entries) {
      bounded[entry.key] = _truncate(entry.value, maxDetailLength);
    }
    return Map<String, String>.unmodifiable(bounded);
  }

  String _truncate(String value, int maxLength) {
    if (maxLength <= 0 || value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  String _formatStackTrace(StackTrace stackTrace) {
    final lines = stackTrace
        .toString()
        .trimRight()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    final bounded =
        maxStackTraceLines <= 0 || lines.length <= maxStackTraceLines
        ? lines
        : lines.take(maxStackTraceLines).toList(growable: false);
    return bounded.join('\n');
  }

  bool _stackTraceWasTruncated(StackTrace stackTrace) {
    if (maxStackTraceLines <= 0) {
      return false;
    }
    final lines = stackTrace
        .toString()
        .trimRight()
        .split('\n')
        .where((line) => line.trim().isNotEmpty);
    return lines.length > maxStackTraceLines;
  }

  bool _isTestWidgetsBinding() {
    WidgetsBinding binding;
    try {
      binding = WidgetsBinding.instance;
    } catch (_) {
      return false;
    }
    return binding.runtimeType.toString().contains('TestWidgetsFlutterBinding');
  }
}
