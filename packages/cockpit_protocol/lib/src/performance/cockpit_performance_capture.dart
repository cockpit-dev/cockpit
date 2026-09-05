import 'cockpit_performance.dart';

/// Request for one bounded performance capture segment.
final class CockpitPerformanceCaptureRequest {
  CockpitPerformanceCaptureRequest({
    required this.name,
    this.mode = CockpitPerformanceMode.profile,
  }) {
    if (name.trim().isEmpty ||
        name.length > 128 ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(name)) {
      throw const FormatException('Performance capture name is invalid.');
    }
  }

  final String name;
  final CockpitPerformanceMode mode;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (mode != CockpitPerformanceMode.profile) 'mode': mode.jsonValue,
  };

  factory CockpitPerformanceCaptureRequest.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException(
        'Performance capture request must be an object.',
      );
    }
    final json = Map<String, Object?>.from(value);
    for (final key in json.keys) {
      if (key != 'name' && key != 'mode') {
        throw FormatException('Unknown performance request field: $key.');
      }
    }
    final name = json['name'];
    if (name is! String) {
      throw const FormatException('Performance capture name is required.');
    }
    return CockpitPerformanceCaptureRequest(
      name: name,
      mode: json['mode'] == null
          ? CockpitPerformanceMode.profile
          : CockpitPerformanceMode.fromJson(json['mode']),
    );
  }
}

/// State returned after a capture window is opened.
final class CockpitPerformanceCaptureSession {
  CockpitPerformanceCaptureSession({
    required this.request,
    required this.startedAt,
    required this.buildMode,
  }) {
    if (!startedAt.isUtc ||
        !const <String>{'debug', 'profile', 'release'}.contains(buildMode)) {
      throw const FormatException('Performance capture session is invalid.');
    }
  }

  final CockpitPerformanceCaptureRequest request;
  final DateTime startedAt;
  final String buildMode;

  Map<String, Object?> toJson() => <String, Object?>{
    'request': request.toJson(),
    'started': startedAt.toIso8601String(),
    'build': buildMode,
  };

  factory CockpitPerformanceCaptureSession.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException(
        'Performance capture session must be an object.',
      );
    }
    final json = Map<String, Object?>.from(value);
    for (final key in json.keys) {
      if (key != 'request' && key != 'started' && key != 'build') {
        throw FormatException('Unknown performance session field: $key.');
      }
    }
    final startedValue = json['started'];
    final started = startedValue is String
        ? DateTime.tryParse(startedValue)
        : null;
    final build = json['build'];
    if (started == null || !started.isUtc || build is! String) {
      throw const FormatException(
        'Performance capture session metadata is invalid.',
      );
    }
    return CockpitPerformanceCaptureSession(
      request: CockpitPerformanceCaptureRequest.fromJson(json['request']),
      startedAt: started,
      buildMode: build,
    );
  }
}
