import 'package:collection/collection.dart';

import 'cockpit_web_socket_activity.dart';

enum CockpitNetworkProtocol { http, webSocket }

enum CockpitNetworkState {
  sending,
  waiting,
  receiving,
  complete,
  cancelled,
  failed,
  open,
  closing,
  closed,
}

final class CockpitNetworkEntry {
  /// Creates a CockpitNetworkEntry.
  const CockpitNetworkEntry({
    required this.requestId,
    required this.method,
    required this.uri,
    required this.startedAt,
    required this.durationMs,
    this.protocol = CockpitNetworkProtocol.http,
    this.state = CockpitNetworkState.complete,
    this.updatedAt,
    this.statusCode,
    this.requestHeaders = const <String, String>{},
    this.responseHeaders = const <String, String>{},
    this.requestBodyPreview,
    this.responseBodyPreview,
    this.requestBodyBytes = 0,
    this.responseBodyBytes = 0,
    this.requestBodyTruncated = false,
    this.responseBodyTruncated = false,
    this.webSocket,
    this.error,
  });

  final String requestId;
  final String method;
  final String uri;
  final DateTime startedAt;
  final int durationMs;
  final CockpitNetworkProtocol protocol;
  final CockpitNetworkState state;
  final DateTime? updatedAt;
  final int? statusCode;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestBodyPreview;
  final String? responseBodyPreview;
  final int requestBodyBytes;
  final int responseBodyBytes;
  final bool requestBodyTruncated;
  final bool responseBodyTruncated;
  final CockpitWebSocketActivity? webSocket;
  final String? error;

  bool get isFailure =>
      state == CockpitNetworkState.failed ||
      error != null ||
      (statusCode != null && statusCode! >= 400);

  bool get isActive => switch (state) {
    CockpitNetworkState.sending ||
    CockpitNetworkState.waiting ||
    CockpitNetworkState.receiving ||
    CockpitNetworkState.open ||
    CockpitNetworkState.closing => true,
    CockpitNetworkState.complete ||
    CockpitNetworkState.cancelled ||
    CockpitNetworkState.failed ||
    CockpitNetworkState.closed => false,
  };

  static const MapEquality<String, String> _mapEquality =
      MapEquality<String, String>();

  /// Encodes this CockpitNetworkEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'method': method,
    'uri': uri,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'protocol': protocol.name,
    'state': state.name,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    if (statusCode != null) 'statusCode': statusCode,
    'requestHeaders': requestHeaders,
    'responseHeaders': responseHeaders,
    if (requestBodyPreview != null) 'requestBodyPreview': requestBodyPreview,
    if (responseBodyPreview != null) 'responseBodyPreview': responseBodyPreview,
    'requestBodyBytes': requestBodyBytes,
    'responseBodyBytes': responseBodyBytes,
    'requestBodyTruncated': requestBodyTruncated,
    'responseBodyTruncated': responseBodyTruncated,
    if (webSocket != null) 'webSocket': webSocket!.toJson(),
    if (error != null) 'error': error,
  };

  /// Decodes a CockpitNetworkEntry from a JSON object.
  factory CockpitNetworkEntry.fromJson(Map<String, Object?> json) {
    return CockpitNetworkEntry(
      requestId: json['requestId']! as String,
      method: json['method']! as String,
      uri: json['uri']! as String,
      startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
      durationMs: json['durationMs'] as int? ?? 0,
      protocol: CockpitNetworkProtocol.values.byName(
        json['protocol'] as String? ?? CockpitNetworkProtocol.http.name,
      ),
      state: CockpitNetworkState.values.byName(
        json['state'] as String? ?? CockpitNetworkState.complete.name,
      ),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt']! as String).toUtc(),
      statusCode: json['statusCode'] as int?,
      requestHeaders: Map<String, String>.from(
        (json['requestHeaders'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
      responseHeaders: Map<String, String>.from(
        (json['responseHeaders'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
      requestBodyPreview: json['requestBodyPreview'] as String?,
      responseBodyPreview: json['responseBodyPreview'] as String?,
      requestBodyBytes: json['requestBodyBytes'] as int? ?? 0,
      responseBodyBytes: json['responseBodyBytes'] as int? ?? 0,
      requestBodyTruncated: json['requestBodyTruncated'] as bool? ?? false,
      responseBodyTruncated: json['responseBodyTruncated'] as bool? ?? false,
      webSocket: json['webSocket'] == null
          ? null
          : CockpitWebSocketActivity.fromJson(
              Map<String, Object?>.from(
                json['webSocket']! as Map<Object?, Object?>,
              ),
            ),
      error: json['error'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitNetworkEntry &&
            other.requestId == requestId &&
            other.method == method &&
            other.uri == uri &&
            other.startedAt == startedAt &&
            other.durationMs == durationMs &&
            other.protocol == protocol &&
            other.state == state &&
            other.updatedAt == updatedAt &&
            other.statusCode == statusCode &&
            _mapEquality.equals(other.requestHeaders, requestHeaders) &&
            _mapEquality.equals(other.responseHeaders, responseHeaders) &&
            other.requestBodyPreview == requestBodyPreview &&
            other.responseBodyPreview == responseBodyPreview &&
            other.requestBodyBytes == requestBodyBytes &&
            other.responseBodyBytes == responseBodyBytes &&
            other.requestBodyTruncated == requestBodyTruncated &&
            other.responseBodyTruncated == responseBodyTruncated &&
            other.webSocket == webSocket &&
            other.error == error;
  }

  @override
  int get hashCode => Object.hash(
    requestId,
    method,
    uri,
    startedAt,
    durationMs,
    protocol,
    state,
    updatedAt,
    statusCode,
    _mapEquality.hash(requestHeaders),
    _mapEquality.hash(responseHeaders),
    requestBodyPreview,
    responseBodyPreview,
    requestBodyBytes,
    responseBodyBytes,
    requestBodyTruncated,
    responseBodyTruncated,
    webSocket,
    error,
  );
}
