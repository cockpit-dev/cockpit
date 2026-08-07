import 'package:collection/collection.dart';

final class CockpitNetworkEndpointSummary {
  /// Creates a CockpitNetworkEndpointSummary.
  const CockpitNetworkEndpointSummary({
    required this.method,
    required this.uriPattern,
    required this.requestCount,
    required this.failureCount,
    required this.averageDurationMs,
    this.lastStatusCode,
    this.latestUri,
  });

  final String method;
  final String uriPattern;
  final int requestCount;
  final int failureCount;
  final int averageDurationMs;
  final int? lastStatusCode;
  final String? latestUri;

  static const MapEquality<String, Object?> _mapEquality =
      MapEquality<String, Object?>();

  /// Encodes this CockpitNetworkEndpointSummary as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'method': method,
    'uriPattern': uriPattern,
    'requestCount': requestCount,
    'failureCount': failureCount,
    'averageDurationMs': averageDurationMs,
    if (lastStatusCode != null) 'lastStatusCode': lastStatusCode,
    if (latestUri != null) 'latestUri': latestUri,
  };

  /// Decodes a CockpitNetworkEndpointSummary from a JSON object.
  factory CockpitNetworkEndpointSummary.fromJson(Map<String, Object?> json) {
    return CockpitNetworkEndpointSummary(
      method: json['method']! as String,
      uriPattern: json['uriPattern']! as String,
      requestCount: json['requestCount'] as int? ?? 0,
      failureCount: json['failureCount'] as int? ?? 0,
      averageDurationMs: json['averageDurationMs'] as int? ?? 0,
      lastStatusCode: json['lastStatusCode'] as int?,
      latestUri: json['latestUri'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitNetworkEndpointSummary &&
            _mapEquality.equals(other.toJson(), toJson());
  }

  @override
  int get hashCode => _mapEquality.hash(toJson());
}
