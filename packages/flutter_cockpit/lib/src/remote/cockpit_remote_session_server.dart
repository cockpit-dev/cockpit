import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cockpit_remote_session_configuration.dart';
import 'cockpit_remote_session_endpoint_handler.dart';

final class CockpitRemoteSessionServer {
  CockpitRemoteSessionServer({
    required CockpitRemoteSessionConfiguration configuration,
    required CockpitRemoteSessionStatusProvider statusProvider,
    CockpitRemoteSessionReadyProvider? readyProvider,
    required CockpitRemoteSessionSnapshotProvider snapshotProvider,
    required CockpitRemoteSessionCommandExecutor commandExecutor,
    CockpitRemoteViewportResizer? viewportResizer,
    CockpitRemoteRuntimeStepDrainer? runtimeStepDrainer,
    required CockpitRemoteRecordingStarter startRecording,
    required CockpitRemoteRecordingStopper stopRecording,
    CockpitRemotePerformanceStarter? startPerformance,
    CockpitRemotePerformanceStopper? stopPerformance,
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
  }) : _configuration = configuration,
       _endpointHandler = CockpitRemoteSessionEndpointHandler(
         configuration: configuration,
         statusProvider: statusProvider,
         readyProvider: readyProvider,
         snapshotProvider: snapshotProvider,
         commandExecutor: commandExecutor,
         viewportResizer: viewportResizer,
         runtimeStepDrainer: runtimeStepDrainer,
         startRecording: startRecording,
         stopRecording: stopRecording,
         startPerformance: startPerformance,
         stopPerformance: stopPerformance,
         artifactTempFileFactory: artifactTempFileFactory,
       );

  final CockpitRemoteSessionConfiguration _configuration;
  final CockpitRemoteSessionEndpointHandler _endpointHandler;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  Uri? _baseUri;

  bool get isRunning => _server != null;
  Uri? get baseUri => _baseUri;

  Future<void> start() async {
    if (isRunning || !_configuration.enabled) {
      return;
    }

    final server = await HttpServer.bind(
      _configuration.host,
      _configuration.port,
    );
    _server = server;
    _baseUri = Uri(
      scheme: 'http',
      host: _configuration.host,
      port: server.port,
      path: _configuration.normalizedRoutePrefix,
    );
    _subscription = server.listen(_handleRequest);
  }

  Future<void> close() async {
    await _endpointHandler.close();
    await _subscription?.cancel();
    await _server?.close(force: true);
    _subscription = null;
    _server = null;
    _baseUri = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (!_isAuthorized(request)) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final bodyText = await _readRequestBody(request);
      Map<String, Object?> jsonBody = const <String, Object?>{};
      if (bodyText.isNotEmpty) {
        final decoded = jsonDecode(bodyText);
        if (decoded is! Map<Object?, Object?>) {
          throw const FormatException('Request body must be a JSON object.');
        }
        jsonBody = Map<String, Object?>.from(decoded);
      }
      final response = await _endpointHandler.handle(
        CockpitRemoteSessionEndpointRequest(
          method: request.method,
          uri: request.uri,
          jsonBody: jsonBody,
        ),
      );
      await _writeResponse(request.response, response);
    } on _CockpitRequestTooLarge {
      await _bestEffortErrorResponse(
        request.response,
        HttpStatus.requestEntityTooLarge,
        {
          'error': 'requestTooLarge',
          'message': 'Request body exceeds the 1 MiB limit.',
        },
      );
    } on FormatException catch (error) {
      await _bestEffortErrorResponse(request.response, HttpStatus.badRequest, {
        'error': 'invalidPayload',
        'message': error.message,
      });
    } catch (error) {
      await _bestEffortErrorResponse(
        request.response,
        HttpStatus.internalServerError,
        {'error': 'serverError', 'message': error.toString()},
      );
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final expected = _configuration.authToken;
    final origin = request.headers.value('origin');
    if (origin != null && origin != 'null') {
      final allowed = _configuration.allowedOrigin;
      if (allowed == null || origin != allowed) return false;
    }
    if (expected.isEmpty) return true;
    final provided =
        request.headers.value('x-cockpit-token') ??
        request.headers
            .value(HttpHeaders.authorizationHeader)
            ?.replaceFirst(RegExp('^Bearer\\s+'), '') ??
        request.uri.queryParameters['token'];
    return _constantTimeEquals(provided ?? '', expected);
  }

  Future<String> _readRequestBody(HttpRequest request) async {
    if (request.contentLength > _maxRequestBytes) {
      throw const _CockpitRequestTooLarge();
    }
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request) {
      length += chunk.length;
      if (length > _maxRequestBytes) throw const _CockpitRequestTooLarge();
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<void> _bestEffortErrorResponse(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    try {
      // HttpResponse exposes a default text/plain content type even before
      // any application response has been written. Do not use that header as
      // a proxy for "already committed": doing so would close malformed or
      // oversized requests with the default 200 status. Always attempt the
      // explicit structured error response and fall back to close only when
      // the peer has already committed/closed the response.
      await _writeResponse(
        response,
        CockpitRemoteSessionEndpointResponse.json(body, statusCode: statusCode),
      );
    } on Object {
      try {
        await response.close();
      } on Object {
        // The peer may already have closed the socket.
      }
    }
  }

  Future<void> _writeResponse(
    HttpResponse response,
    CockpitRemoteSessionEndpointResponse endpointResponse,
  ) async {
    response.statusCode = endpointResponse.statusCode;
    if (endpointResponse.jsonBody != null) {
      response.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      response.write(jsonEncode(_compactJsonValue(endpointResponse.jsonBody)));
    } else if (endpointResponse.sourceFilePath != null) {
      response.headers.contentType = ContentType.parse(
        endpointResponse.contentType,
      );
      await response.addStream(
        File(endpointResponse.sourceFilePath!).openRead(),
      );
    } else {
      response.headers.contentType = ContentType.parse(
        endpointResponse.contentType,
      );
      response.add(endpointResponse.binaryBody ?? const <int>[]);
    }
    await response.close();
  }
}

const int _maxRequestBytes = 1 << 20;

final class _CockpitRequestTooLarge implements Exception {
  const _CockpitRequestTooLarge();
}

bool _constantTimeEquals(String actual, String expected) {
  var difference = actual.length ^ expected.length;
  final length = actual.length < expected.length
      ? actual.length
      : expected.length;
  for (var index = 0; index < length; index += 1) {
    difference |= actual.codeUnitAt(index) ^ expected.codeUnitAt(index);
  }
  return difference == 0;
}

Object? _compactJsonValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    final compacted = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      final compactedValue = _compactJsonValue(entry.value);
      if (compactedValue != null) {
        compacted[key] = compactedValue;
      }
    }
    return compacted;
  }
  if (value is List<Object?>) {
    return value.map(_compactJsonValue).toList(growable: false);
  }
  return value;
}
