import 'package:collection/collection.dart';

enum CockpitRuntimeEventKind {
  flutterError('flutterError'),
  uncaughtError('uncaughtError'),
  debugLog('debugLog');

  /// Creates a CockpitRuntimeEventKind.
  const CockpitRuntimeEventKind(this.jsonValue);

  final String jsonValue;

  static CockpitRuntimeEventKind fromJson(Object? json) {
    return values.firstWhere(
      (value) => value.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported runtime event kind.',
      ),
    );
  }
}

enum CockpitRuntimeEventSeverity {
  info('info'),
  warning('warning'),
  error('error');

  /// Creates a CockpitRuntimeEventSeverity.
  const CockpitRuntimeEventSeverity(this.jsonValue);

  final String jsonValue;

  static CockpitRuntimeEventSeverity fromJson(Object? json) {
    return values.firstWhere(
      (value) => value.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported runtime event severity.',
      ),
    );
  }
}

final class CockpitRuntimeEvent {
  /// Creates a CockpitRuntimeEvent.
  const CockpitRuntimeEvent({
    required this.eventId,
    required this.kind,
    required this.severity,
    required this.message,
    required this.recordedAt,
    this.routeName,
    this.source,
    this.details = const <String, String>{},
    this.stackTracePreview,
    this.stackTraceTruncated = false,
  });

  final String eventId;
  final CockpitRuntimeEventKind kind;
  final CockpitRuntimeEventSeverity severity;
  final String message;
  final DateTime recordedAt;
  final String? routeName;
  final String? source;
  final Map<String, String> details;
  final String? stackTracePreview;
  final bool stackTraceTruncated;

  static const MapEquality<String, String> _mapEquality =
      MapEquality<String, String>();

  bool get isError => severity == CockpitRuntimeEventSeverity.error;
  bool get isWarning => severity == CockpitRuntimeEventSeverity.warning;

  /// Encodes this CockpitRuntimeEvent as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'eventId': eventId,
    'kind': kind.jsonValue,
    'severity': severity.jsonValue,
    'message': message,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    if (routeName != null) 'routeName': routeName,
    if (source != null) 'source': source,
    'details': details,
    if (stackTracePreview != null) 'stackTracePreview': stackTracePreview,
    'stackTraceTruncated': stackTraceTruncated,
  };

  /// Decodes a CockpitRuntimeEvent from a JSON object.
  factory CockpitRuntimeEvent.fromJson(Map<String, Object?> json) {
    return CockpitRuntimeEvent(
      eventId: json['eventId']! as String,
      kind: CockpitRuntimeEventKind.fromJson(json['kind']),
      severity: CockpitRuntimeEventSeverity.fromJson(json['severity']),
      message: json['message']! as String,
      recordedAt: DateTime.parse(json['recordedAt']! as String).toUtc(),
      routeName: json['routeName'] as String?,
      source: json['source'] as String?,
      details: Map<String, String>.from(
        (json['details'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
      stackTracePreview: json['stackTracePreview'] as String?,
      stackTraceTruncated: json['stackTraceTruncated'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRuntimeEvent &&
            other.eventId == eventId &&
            other.kind == kind &&
            other.severity == severity &&
            other.message == message &&
            other.recordedAt == recordedAt &&
            other.routeName == routeName &&
            other.source == source &&
            _mapEquality.equals(other.details, details) &&
            other.stackTracePreview == stackTracePreview &&
            other.stackTraceTruncated == stackTraceTruncated;
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    kind,
    severity,
    message,
    recordedAt,
    routeName,
    source,
    _mapEquality.hash(details),
    stackTracePreview,
    stackTraceTruncated,
  );
}
