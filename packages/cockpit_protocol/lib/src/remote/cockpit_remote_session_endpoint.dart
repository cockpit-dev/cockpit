final class CockpitRemoteSessionEndpointRequest {
  /// Creates a CockpitRemoteSessionEndpointRequest.
  const CockpitRemoteSessionEndpointRequest({
    required this.method,
    required this.uri,
    this.jsonBody = const <String, Object?>{},
  });

  final String method;
  final Uri uri;
  final Map<String, Object?> jsonBody;
}

final class CockpitRemoteSessionEndpointResponse {
  const CockpitRemoteSessionEndpointResponse._({
    required this.statusCode,
    required this.contentType,
    this.jsonBody,
    this.binaryBody,
    this.sourceFilePath,
  });

  /// Creates a CockpitRemoteSessionEndpointResponse using the named constructor `json`.
  const CockpitRemoteSessionEndpointResponse.json(
    Map<String, Object?> body, {
    int statusCode = 200,
  }) : this._(
         statusCode: statusCode,
         contentType: 'application/json',
         jsonBody: body,
       );

  /// Creates a CockpitRemoteSessionEndpointResponse using the named constructor `binary`.
  const CockpitRemoteSessionEndpointResponse.binary(
    List<int> bytes, {
    int statusCode = 200,
    String contentType = 'application/octet-stream',
  }) : this._(
         statusCode: statusCode,
         contentType: contentType,
         binaryBody: bytes,
       );

  /// Creates a CockpitRemoteSessionEndpointResponse using the named constructor `binaryFile`.
  const CockpitRemoteSessionEndpointResponse.binaryFile(
    String sourceFilePath, {
    int statusCode = 200,
    String contentType = 'application/octet-stream',
  }) : this._(
         statusCode: statusCode,
         contentType: contentType,
         sourceFilePath: sourceFilePath,
       );

  final int statusCode;
  final String contentType;
  final Map<String, Object?>? jsonBody;
  final List<int>? binaryBody;
  final String? sourceFilePath;
}
