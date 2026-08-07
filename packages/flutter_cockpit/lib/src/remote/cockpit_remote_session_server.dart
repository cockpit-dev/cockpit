import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      final bodyText = await utf8.decoder.bind(request).join();
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
    } on FormatException catch (error) {
      await _writeResponse(
        request.response,
        CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
          'error': 'invalidPayload',
          'message': error.message,
        }, statusCode: HttpStatus.badRequest),
      );
    } catch (error) {
      await _writeResponse(
        request.response,
        CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
          'error': 'serverError',
          'message': error.toString(),
        }, statusCode: HttpStatus.internalServerError),
      );
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
