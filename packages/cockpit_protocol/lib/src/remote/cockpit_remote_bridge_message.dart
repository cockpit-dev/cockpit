import 'dart:convert';

import 'cockpit_remote_session_endpoint.dart';

final class CockpitRemoteBridgeRequest {
  /// Creates a CockpitRemoteBridgeRequest.
  const CockpitRemoteBridgeRequest({
    required this.requestId,
    required this.method,
    required this.path,
    this.jsonBody,
  });

  final String requestId;
  final String method;
  final String path;
  final Map<String, Object?>? jsonBody;

  Uri get uri => Uri.parse(path);

  /// Encodes this CockpitRemoteBridgeRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'method': method,
    'path': path,
    if (jsonBody != null) 'jsonBody': jsonBody,
  };

  /// Decodes a CockpitRemoteBridgeRequest from a JSON object.
  factory CockpitRemoteBridgeRequest.fromJson(Map<String, Object?> json) {
    final jsonBody = json['jsonBody'];
    final requestId = json['requestId'];
    final method = json['method'];
    final path = json['path'];
    if (requestId is! String || requestId.isEmpty) {
      throw const FormatException(
        'Bridge request field "requestId" must be a non-empty string.',
      );
    }
    if (method is! String || method.isEmpty) {
      throw const FormatException(
        'Bridge request field "method" must be a non-empty string.',
      );
    }
    if (path is! String || path.isEmpty) {
      throw const FormatException(
        'Bridge request field "path" must be a non-empty string.',
      );
    }
    if (jsonBody != null && jsonBody is! Map<Object?, Object?>) {
      throw const FormatException(
        'Bridge request field "jsonBody" must be a JSON object.',
      );
    }
    return CockpitRemoteBridgeRequest(
      requestId: requestId,
      method: method,
      path: path,
      jsonBody: jsonBody == null
          ? null
          : Map<String, Object?>.from(jsonBody as Map<Object?, Object?>),
    );
  }
}

final class CockpitRemoteBridgeResponse {
  /// Creates a CockpitRemoteBridgeResponse.
  const CockpitRemoteBridgeResponse({
    required this.requestId,
    required this.statusCode,
    this.contentType = 'application/json',
    this.jsonBody,
    this.bytesBase64,
  });

  final String requestId;
  final int statusCode;
  final String contentType;
  final Map<String, Object?>? jsonBody;
  final String? bytesBase64;

  List<int>? get binaryBody =>
      bytesBase64 == null ? null : base64Decode(bytesBase64!);

  /// Encodes this CockpitRemoteBridgeResponse as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'statusCode': statusCode,
    'contentType': contentType,
    if (jsonBody != null) 'jsonBody': jsonBody,
    if (bytesBase64 != null) 'bytesBase64': bytesBase64,
  };

  /// Decodes a CockpitRemoteBridgeResponse from a JSON object.
  factory CockpitRemoteBridgeResponse.fromJson(Map<String, Object?> json) {
    final jsonBody = json['jsonBody'];
    final requestId = json['requestId'];
    final statusCode = json['statusCode'];
    final contentType = json['contentType'];
    final bytesBase64 = json['bytesBase64'];
    if (requestId is! String || requestId.isEmpty) {
      throw const FormatException(
        'Bridge response field "requestId" must be a non-empty string.',
      );
    }
    if (statusCode is! int) {
      throw const FormatException(
        'Bridge response field "statusCode" must be an integer.',
      );
    }
    if (statusCode < 100 || statusCode > 599) {
      throw const FormatException(
        'Bridge response field "statusCode" must be an HTTP status code from 100 to 599.',
      );
    }
    if (contentType != null && contentType is! String) {
      throw const FormatException(
        'Bridge response field "contentType" must be a string.',
      );
    }
    if (jsonBody != null && jsonBody is! Map<Object?, Object?>) {
      throw const FormatException(
        'Bridge response field "jsonBody" must be a JSON object.',
      );
    }
    if (bytesBase64 != null && bytesBase64 is! String) {
      throw const FormatException(
        'Bridge response field "bytesBase64" must be a string.',
      );
    }
    if (jsonBody != null && bytesBase64 != null) {
      throw const FormatException(
        'Bridge response must not contain both "jsonBody" and "bytesBase64".',
      );
    }
    return CockpitRemoteBridgeResponse(
      requestId: requestId,
      statusCode: statusCode,
      contentType: contentType as String? ?? 'application/json',
      jsonBody: jsonBody == null
          ? null
          : Map<String, Object?>.from(jsonBody as Map<Object?, Object?>),
      bytesBase64: bytesBase64 as String?,
    );
  }

  /// Creates a CockpitRemoteBridgeResponse using the named constructor `fromEndpointResponse`.
  factory CockpitRemoteBridgeResponse.fromEndpointResponse({
    required String requestId,
    required CockpitRemoteSessionEndpointResponse response,
  }) {
    return CockpitRemoteBridgeResponse(
      requestId: requestId,
      statusCode: response.statusCode,
      contentType: response.contentType,
      jsonBody: response.jsonBody,
      bytesBase64: response.binaryBody == null
          ? null
          : base64Encode(response.binaryBody!),
    );
  }
}
