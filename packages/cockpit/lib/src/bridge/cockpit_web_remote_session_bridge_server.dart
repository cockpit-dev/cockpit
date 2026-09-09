import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_protocol/cockpit_remote_bridge_protocol.dart';

import 'cockpit_browser_recording_adapter_resolver.dart';
import '../remote/cockpit_remote_command_timeout_budget.dart';
import '../recording/cockpit_host_recording_adapter.dart';
import '../development/cockpit_development_session_handle.dart';

typedef CockpitBridgeArtifactTempFileFactory =
    Future<File> Function(String basename);

CockpitWebRemoteSessionBridgeServer? cockpitCreateWebRemoteSessionBridgeServer({
  required CockpitDevelopmentSessionHandle handle,
}) {
  if (handle.platform != 'web') {
    return null;
  }
  return CockpitWebRemoteSessionBridgeServer(
    bindHost: handle.baseUri.host,
    bindPort: handle.baseUri.port,
    routePrefix: handle.baseUri.path == '/' ? '' : handle.baseUri.path,
    recordingAdapter: cockpitResolveBrowserRecordingAdapter(
      deviceId: handle.deviceId,
    ),
    authToken: handle.baseUri.queryParameters['token'] ?? '',
  );
}

final class CockpitWebRemoteSessionBridgeServer {
  CockpitWebRemoteSessionBridgeServer({
    required this.bindHost,
    required this.bindPort,
    this.routePrefix = '',
    this.recordingAdapter,
    CockpitBridgeArtifactTempFileFactory? artifactTempFileFactory,
    this.requestTimeout = const Duration(seconds: 20),
    this.authToken = '',
    this.allowedOrigin,
    this.maxConnections = 4,
  }) : _artifactTempFileFactory =
           artifactTempFileFactory ?? _defaultBridgeArtifactTempFileFactory {
    if (maxConnections < 1 || maxConnections > 32) {
      throw ArgumentError.value(maxConnections, 'maxConnections');
    }
  }

  final String bindHost;
  final int bindPort;
  final String routePrefix;
  final CockpitHostRecordingAdapter? recordingAdapter;
  final Duration requestTimeout;
  final String authToken;
  final String? allowedOrigin;
  final int maxConnections;
  final CockpitBridgeArtifactTempFileFactory _artifactTempFileFactory;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requestSubscription;
  final List<_BridgeConnection> _connections = <_BridgeConnection>[];
  _BridgeConnection? _activeConnection;
  int _nextConnectionId = 0;
  final Map<String, _PendingBridgeRequest> _pending =
      <String, _PendingBridgeRequest>{};
  final Map<String, _BridgeArtifactEntry> _localArtifacts =
      <String, _BridgeArtifactEntry>{};
  Uri? _baseUri;
  CockpitRecordingSession? _activeRecordingSession;

  Uri get baseUri => _baseUri!;
  Uri get connectUri => baseUri.replace(
    scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
    path: _joinPath(_normalizedRoutePrefix, 'connect'),
    queryParameters: authToken.isEmpty
        ? null
        : <String, String>{'token': authToken},
  );

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    final server = await HttpServer.bind(bindHost, bindPort);
    _server = server;
    _baseUri = Uri(
      scheme: 'http',
      host: bindHost,
      port: server.port,
      path: _normalizedRoutePrefix,
    );
    _requestSubscription = server.listen(_handleRequest);
  }

  Future<void> close() async {
    _failPending(StateError('Bridge server closed.'));
    await _bestEffortStopActiveRecording();
    final connections = _connections.toList(growable: false);
    _connections.clear();
    _activeConnection = null;
    for (final connection in connections) {
      connection.closed = true;
      await connection.subscription?.cancel();
      await connection.socket.close();
    }
    await _requestSubscription?.cancel();
    await _server?.close(force: true);
    await _deleteGeneratedArtifacts();
    _requestSubscription = null;
    _server = null;
    _baseUri = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(request) &&
          _routePathFor(request.uri.path) == '/connect') {
        if (!_isAuthorized(request)) {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }
        if (_connections.where((connection) => !connection.closed).length >=
            maxConnections) {
          request.response.statusCode = HttpStatus.tooManyRequests;
          await request.response.close();
          return;
        }
        await _handleConnect(request);
        return;
      }

      if (!_isAuthorized(request)) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      final response = await _resolveResponse(request);
      await _writeResponse(request.response, response);
    } on FormatException catch (error) {
      await _bestEffortErrorResponse(request.response, HttpStatus.badRequest, {
        'error': 'invalidPayload',
        'message': error.message,
      });
    } on _BridgeRequestTooLarge {
      await _bestEffortErrorResponse(
        request.response,
        HttpStatus.requestEntityTooLarge,
        {
          'error': 'requestTooLarge',
          'message': 'Request body exceeds the 1 MiB limit.',
        },
      );
    } catch (error) {
      await _bestEffortErrorResponse(
        request.response,
        HttpStatus.internalServerError,
        {'error': 'serverError', 'message': error.toString()},
      );
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final origin = request.headers.value('origin');
    final expectedOrigin = allowedOrigin;
    if (origin != null && origin != 'null' && origin != expectedOrigin) {
      return false;
    }
    if (authToken.isEmpty) return true;
    final provided = request.uri.queryParameters['token'];
    return _constantTimeEquals(provided ?? '', authToken);
  }

  Future<void> _handleConnect(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final connection = _BridgeConnection(
      id: ++_nextConnectionId,
      socket: socket,
    );
    _connections.add(connection);
    _activeConnection ??= connection;
    _pruneClosedConnections();
    connection.subscription = socket.listen(
      (payload) {
        _handleSocketPayload(connection, payload);
      },
      onDone: () {
        _removeConnection(
          connection,
          StateError('Bridge client disconnected.'),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _removeConnection(connection, error);
      },
      cancelOnError: true,
    );
  }

  void _handleSocketPayload(_BridgeConnection connection, Object? payload) {
    if (payload == null) {
      return;
    }
    if ('$payload'.length > _maxBridgeMessageBytes) {
      _removeConnection(
        connection,
        StateError('Bridge message exceeds the 4 MiB limit.'),
      );
      return;
    }
    try {
      final decoded = jsonDecode('$payload');
      if (decoded is! Map<Object?, Object?>) {
        _completeConnectionPendingWithBridgeError(
          connection,
          statusCode: HttpStatus.badGateway,
          error: 'bridgeInvalidResponse',
          message: 'Bridge response payload must be a JSON object.',
        );
        return;
      }
      final responseJson = Map<String, Object?>.from(decoded);
      final rawRequestId = responseJson['requestId'];
      if (rawRequestId is! String || rawRequestId.isEmpty) {
        _completeConnectionPendingWithBridgeError(
          connection,
          statusCode: HttpStatus.badGateway,
          error: 'bridgeInvalidResponse',
          message:
              'Bridge response field "requestId" must be a non-empty string.',
        );
        return;
      }
      final response = CockpitRemoteBridgeResponse.fromJson(responseJson);
      final pendingRequest = _pending[response.requestId];
      if (pendingRequest == null ||
          !identical(pendingRequest.connection, connection)) {
        _completeConnectionPendingWithBridgeError(
          connection,
          statusCode: HttpStatus.badGateway,
          error: 'bridgeUnknownResponse',
          message:
              'The browser bridge returned an unknown requestId: '
              '${response.requestId}. Pending requests were failed to avoid '
              'response misattribution.',
        );
        return;
      }
      _pending.remove(response.requestId);
      connection.pendingRequestIds.remove(response.requestId);
      connection.stale = false;
      pendingRequest.completer.complete(response);
    } on FormatException catch (error) {
      _completeConnectionPendingWithBridgeError(
        connection,
        statusCode: HttpStatus.badGateway,
        error: 'bridgeInvalidResponse',
        message: error.message,
      );
    } on Object catch (error) {
      _completeConnectionPendingWithBridgeError(
        connection,
        statusCode: HttpStatus.badGateway,
        error: 'bridgeInvalidResponse',
        message: '$error',
      );
    }
  }

  Future<void> _bestEffortErrorResponse(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    try {
      await _writeResponse(
        response,
        CockpitRemoteSessionEndpointResponse.json(body, statusCode: statusCode),
      );
    } on Object {
      try {
        await response.close();
      } on Object {
        // The peer may have closed the response already.
      }
    }
  }

  Future<CockpitRemoteSessionEndpointResponse> _resolveResponse(
    HttpRequest request,
  ) async {
    final routePath = _routePathFor(request.uri.path);
    if (routePath == null) {
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'notFound',
        'message': 'Unsupported remote session endpoint.',
      }, statusCode: HttpStatus.notFound);
    }
    if (routePath == '/recording/start' && recordingAdapter != null) {
      return _startHostRecording(request);
    }
    if (routePath == '/recording/stop' && recordingAdapter != null) {
      return _stopHostRecording();
    }
    if (routePath == '/artifacts/download') {
      final local = await _localArtifactResponse(request.uri);
      if (local != null) {
        return local;
      }
    }

    final proxied = await _forward(request);
    if (routePath == '/health' && proxied.jsonBody != null) {
      return CockpitRemoteSessionEndpointResponse.json(
        _patchedHealthBody(proxied.jsonBody!),
        statusCode: proxied.statusCode,
      );
    }
    if (routePath == '/commands/execute' && proxied.jsonBody != null) {
      return _externalizedCommandResponse(proxied);
    }
    return proxied;
  }

  Future<CockpitRemoteSessionEndpointResponse> _forward(
    HttpRequest request,
  ) async {
    _pruneClosedConnections();
    if (_connections.isEmpty) {
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'bridgeUnavailable',
        'message': 'The browser bridge is not connected.',
      }, statusCode: HttpStatus.serviceUnavailable);
    }
    final bodyText = await _readBoundedRequestText(request);
    Map<String, Object?>? jsonBody;
    if (bodyText.isNotEmpty) {
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map<Object?, Object?>) {
        return const CockpitRemoteSessionEndpointResponse.json(
          <String, Object?>{
            'error': 'invalidPayload',
            'message': 'Request body must be a JSON object.',
          },
          statusCode: HttpStatus.badRequest,
        );
      }
      jsonBody = Map<String, Object?>.from(decoded);
    }
    final routePath = _routePathFor(request.uri.path);
    if (routePath == '/ready') {
      return _readyForwardResponse();
    }

    final selected = await _selectConnectionFor(routePath);
    final connection = selected.connection;
    if (connection == null) {
      return selected.failureResponse ?? _bridgeUnavailableResponse();
    }
    final response = await _sendBridgeRequest(
      connection: connection,
      method: request.method,
      path: request.uri.toString(),
      jsonBody: jsonBody,
      timeout: _forwardTimeoutFor(request, jsonBody),
    );
    if (_isUnmountedRootResponse(response)) {
      connection.stale = true;
      final retry = await _selectConnectionFor(
        routePath,
        excludedConnection: connection,
      );
      final retryConnection = retry.connection;
      if (retryConnection != null && _canRetryForwardedRequest(jsonBody)) {
        return _endpointResponseFromBridgeResponse(
          await _sendBridgeRequest(
            connection: retryConnection,
            method: request.method,
            path: request.uri.toString(),
            jsonBody: jsonBody,
            timeout: _forwardTimeoutFor(request, jsonBody),
          ),
        );
      }
    }
    return _endpointResponseFromBridgeResponse(response);
  }

  Future<CockpitRemoteSessionEndpointResponse> _readyForwardResponse() async {
    final selected = await _selectConnectionFor('/ready');
    final connection = selected.connection;
    if (connection == null) {
      return selected.failureResponse ?? _bridgeUnavailableResponse();
    }
    final response = await _sendBridgeRequest(
      connection: connection,
      method: 'GET',
      path: _joinPath(_normalizedRoutePrefix, 'ready'),
      timeout: _probeTimeout,
    );
    return _endpointResponseFromBridgeResponse(response);
  }

  Future<_BridgeConnectionSelection> _selectConnectionFor(
    String? routePath, {
    _BridgeConnection? excludedConnection,
  }) async {
    _pruneClosedConnections();
    final candidates = _connections
        .where(
          (connection) =>
              !connection.closed && !identical(connection, excludedConnection),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const _BridgeConnectionSelection();
    }
    candidates.sort((left, right) {
      if (left.stale != right.stale) {
        return left.stale ? 1 : -1;
      }
      return right.id.compareTo(left.id);
    });

    if (routePath != '/ready' && candidates.length == 1) {
      final candidate = candidates.single;
      if (!candidate.stale) {
        _activeConnection = candidate;
        return _BridgeConnectionSelection(connection: candidate);
      }
    }

    CockpitRemoteSessionEndpointResponse? lastFailure;
    for (final candidate in candidates) {
      final response = await _sendBridgeRequest(
        connection: candidate,
        method: 'GET',
        path: _joinPath(_normalizedRoutePrefix, 'ready'),
        timeout: _probeTimeout,
      );
      if (_bridgeResponseIsReady(response)) {
        candidate.stale = false;
        _activeConnection = candidate;
        return _BridgeConnectionSelection(connection: candidate);
      }
      if (_isBridgeFailure(response)) {
        lastFailure = _endpointResponseFromBridgeResponse(response);
      }
      candidate.stale = true;
    }

    final active = _activeConnection;
    if (routePath == '/ready' &&
        active != null &&
        !active.closed &&
        !identical(active, excludedConnection)) {
      return _BridgeConnectionSelection(connection: active);
    }
    if (routePath == '/ready') {
      if (candidates.isNotEmpty) {
        return _BridgeConnectionSelection(connection: candidates.first);
      }
    }

    return _BridgeConnectionSelection(
      failureResponse: lastFailure ?? _bridgeUnavailableResponse(),
    );
  }

  Future<CockpitRemoteBridgeResponse> _sendBridgeRequest({
    required _BridgeConnection connection,
    required String method,
    required String path,
    Map<String, Object?>? jsonBody,
    required Duration timeout,
  }) async {
    if (connection.closed) {
      return _bridgeError(
        statusCode: HttpStatus.serviceUnavailable,
        error: 'bridgeUnavailable',
        message: 'The browser bridge connection is closed.',
      );
    }
    final requestId =
        'bridge-${connection.id}-${DateTime.now().toUtc().microsecondsSinceEpoch}-${_pending.length}';
    final completer = Completer<CockpitRemoteBridgeResponse>();
    _pending[requestId] = _PendingBridgeRequest(
      connection: connection,
      completer: completer,
    );
    connection.pendingRequestIds.add(requestId);
    try {
      connection.socket.add(
        jsonEncode(
          CockpitRemoteBridgeRequest(
            requestId: requestId,
            method: method,
            path: path,
            jsonBody: jsonBody,
          ).toJson(),
        ),
      );
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(requestId);
      connection.pendingRequestIds.remove(requestId);
      return _bridgeError(
        statusCode: HttpStatus.gatewayTimeout,
        error: 'bridgeTimeout',
        message: 'The browser bridge did not respond before timeout.',
      );
    } on Object catch (error) {
      _pending.remove(requestId);
      connection.pendingRequestIds.remove(requestId);
      return _bridgeError(
        statusCode: HttpStatus.serviceUnavailable,
        error: 'bridgeUnavailable',
        message: '$error',
      );
    }
  }

  CockpitRemoteSessionEndpointResponse _endpointResponseFromBridgeResponse(
    CockpitRemoteBridgeResponse response,
  ) {
    try {
      return response.jsonBody != null
          ? CockpitRemoteSessionEndpointResponse.json(
              response.jsonBody!,
              statusCode: response.statusCode,
            )
          : CockpitRemoteSessionEndpointResponse.binary(
              _binaryBodyFromBridgeResponse(response),
              statusCode: response.statusCode,
              contentType: response.contentType,
            );
    } on FormatException catch (error) {
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'bridgeInvalidResponse',
        'message': error.message,
      }, statusCode: HttpStatus.badGateway);
    }
  }

  Duration get _probeTimeout {
    const maximum = Duration(seconds: 2);
    return requestTimeout < maximum ? requestTimeout : maximum;
  }

  bool _bridgeResponseIsReady(CockpitRemoteBridgeResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    final body = response.jsonBody;
    return body != null &&
        body['ready'] == true &&
        body['supportsInAppControl'] == true;
  }

  bool _isBridgeFailure(CockpitRemoteBridgeResponse response) {
    final error = response.jsonBody?['error'];
    return response.statusCode >= 500 || error == 'bridgeTimeout';
  }

  bool _isUnmountedRootResponse(CockpitRemoteBridgeResponse response) {
    final body = response.jsonBody;
    if (body == null) {
      return false;
    }
    final message = '${body['message'] ?? ''}';
    return body['error'] == 'serverError' &&
        message.contains('FlutterCockpitRoot is not mounted');
  }

  bool _canRetryForwardedRequest(Map<String, Object?>? jsonBody) {
    if (jsonBody == null) {
      return true;
    }
    return switch (jsonBody['commandType']) {
      'assertText' ||
      'assertVisible' ||
      'captureScreenshot' ||
      'collectSnapshot' ||
      'waitFor' ||
      'waitForUiIdle' => true,
      _ => false,
    };
  }

  CockpitRemoteSessionEndpointResponse _bridgeUnavailableResponse() {
    return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
      'error': 'bridgeUnavailable',
      'message': 'The browser bridge is not connected.',
    }, statusCode: HttpStatus.serviceUnavailable);
  }

  CockpitRemoteBridgeResponse _bridgeError({
    required int statusCode,
    required String error,
    required String message,
  }) {
    return CockpitRemoteBridgeResponse(
      requestId: 'bridge-error',
      statusCode: statusCode,
      jsonBody: <String, Object?>{'error': error, 'message': message},
    );
  }

  Duration _forwardTimeoutFor(
    HttpRequest request,
    Map<String, Object?>? jsonBody,
  ) {
    final routePath = _routePathFor(request.uri.path);
    if (routePath != '/commands/execute') {
      if (routePath == '/health' ||
          routePath == '/ready' ||
          routePath == '/ping') {
        final probeTimeout = const Duration(seconds: 5);
        return requestTimeout < probeTimeout ? requestTimeout : probeTimeout;
      }
      return requestTimeout;
    }
    final timeout = cockpitRemoteCommandTransportTimeoutForJson(
      jsonBody,
      minimumTimeout: requestTimeout,
    );
    return timeout > requestTimeout ? timeout : requestTimeout;
  }

  List<int> _binaryBodyFromBridgeResponse(
    CockpitRemoteBridgeResponse response,
  ) {
    try {
      return response.binaryBody ?? const <int>[];
    } on FormatException catch (error) {
      throw FormatException(
        'Bridge response field "bytesBase64" must be valid base64: '
        '${error.message}',
      );
    }
  }

  Map<String, Object?> _patchedHealthBody(Map<String, Object?> body) {
    if (recordingAdapter == null) {
      return body;
    }
    final next = Map<String, Object?>.from(body);
    next['recordingCapabilities'] = CockpitRecordingCapabilities(
      supportsNativeRecording: true,
      preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
      supportedLayers: const <CockpitRecordingLayer>[
        CockpitRecordingLayer.hostScreen,
      ],
      preferredLayer: CockpitRecordingLayer.hostScreen,
      recordingLimitations: const <String>[
        'Browser recording runs on the host desktop and requires screen-capture permission for the terminal, Dart, and ffmpeg. When multiple browser windows or tabs share the same host process, window targeting remains best-effort and works most reliably with the target browser window foregrounded and isolated.',
      ],
    ).toJson();
    if (_activeRecordingSession != null) {
      next['activeRecording'] = _activeRecordingSession!.toJson();
    } else {
      next.remove('activeRecording');
    }
    return next;
  }

  Future<CockpitRemoteSessionEndpointResponse> _externalizedCommandResponse(
    CockpitRemoteSessionEndpointResponse endpointResponse,
  ) async {
    final body = endpointResponse.jsonBody!;
    if (!body.containsKey('result')) {
      return endpointResponse;
    }
    final response = CockpitRemoteCommandResponse.fromJson(body);
    if (response.artifactPayloads.isEmpty) {
      return endpointResponse;
    }
    final downloads = <CockpitRemoteArtifactDownload>[
      ...response.artifactDownloads,
    ];
    for (final payload in response.artifactPayloads) {
      final relativePath = payload.artifact.relativePath;
      if (relativePath.isEmpty) {
        continue;
      }
      if (payload.bytes.isEmpty) {
        if (_isRequiredEvidenceArtifact(payload.artifact)) {
          return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
            'error': 'artifactPayloadEmpty',
            'message':
                'Browser command returned an empty required evidence artifact.',
            'details': <String, Object?>{
              'artifactPath': relativePath,
              'artifactRole': payload.artifact.role,
            },
          }, statusCode: HttpStatus.internalServerError);
        }
        continue;
      }
      final file = await _persistArtifactBytes(
        _sanitizeArtifactBasename(relativePath),
        payload.bytes,
      );
      _localArtifacts[relativePath] = _BridgeArtifactEntry(
        sourceFilePath: file.path,
        deleteOnClose: true,
      );
      downloads.add(
        CockpitRemoteArtifactDownload(
          artifact: payload.artifact,
          downloadPath: _downloadPathFor(relativePath),
        ),
      );
    }

    return CockpitRemoteSessionEndpointResponse.json(
      CockpitRemoteCommandResponse(
        result: response.result,
        runtimeSteps: response.runtimeSteps,
        artifactDownloads: downloads,
      ).toJson(),
      statusCode: endpointResponse.statusCode,
    );
  }

  Future<CockpitRemoteSessionEndpointResponse> _startHostRecording(
    HttpRequest request,
  ) async {
    final adapter = recordingAdapter;
    if (adapter == null) {
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'recordingUnsupported',
        'message': 'Host recording is unavailable for this bridge.',
      }, statusCode: HttpStatus.notImplemented);
    }
    final bodyText = await _readBoundedRequestText(request);
    final decoded = bodyText.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(
            jsonDecode(bodyText) as Map<Object?, Object?>,
          );
    final recordingRequest = CockpitRecordingRequest.fromJson(decoded);
    try {
      final session = await adapter.startRecording(recordingRequest);
      _activeRecordingSession = session;
      return CockpitRemoteSessionEndpointResponse.json(session.toJson());
    } on StateError catch (error) {
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'recordingStartFailed',
        'message': error.message,
      }, statusCode: HttpStatus.preconditionFailed);
    } on Object catch (error) {
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'recordingStartFailed',
        'message': '$error',
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  Future<CockpitRemoteSessionEndpointResponse> _stopHostRecording() async {
    final adapter = recordingAdapter;
    if (adapter == null) {
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'recordingUnsupported',
        'message': 'Host recording is unavailable for this bridge.',
      }, statusCode: HttpStatus.notImplemented);
    }
    try {
      final result = await adapter.stopRecording();
      _activeRecordingSession = null;
      return CockpitRemoteSessionEndpointResponse.json(
        (await _hostRecordingResponseFor(result)).toJson(),
      );
    } on StateError catch (error) {
      _activeRecordingSession = null;
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'recordingStopFailed',
        'message': error.message,
      }, statusCode: HttpStatus.conflict);
    } on Object catch (error) {
      _activeRecordingSession = null;
      return CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'recordingStopFailed',
        'message': '$error',
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  Future<CockpitRemoteRecordingResponse> _hostRecordingResponseFor(
    CockpitRecordingResult result,
  ) async {
    final artifact = result.artifact;
    if (artifact == null) {
      return CockpitRemoteRecordingResponse(
        result: _recordingResultForTransport(result, includeArtifact: false),
      );
    }
    final artifactEntry = await _artifactEntryFor(result);
    if (artifactEntry == null) {
      return CockpitRemoteRecordingResponse(
        result: _recordingResultForTransport(result, includeArtifact: false),
      );
    }
    _localArtifacts[artifact.relativePath] = artifactEntry;
    return CockpitRemoteRecordingResponse(
      result: _recordingResultForTransport(result),
      artifactDownloads: <CockpitRemoteArtifactDownload>[
        CockpitRemoteArtifactDownload(
          artifact: artifact,
          downloadPath: _downloadPathFor(artifact.relativePath),
        ),
      ],
    );
  }

  Future<_BridgeArtifactEntry?> _artifactEntryFor(
    CockpitRecordingResult result,
  ) async {
    final bytes = result.bytes;
    if (bytes != null) {
      final file = await _persistArtifactBytes(
        _sanitizeArtifactBasename(
          result.artifact?.relativePath ?? 'recording.mp4',
        ),
        bytes,
      );
      return _BridgeArtifactEntry(
        sourceFilePath: file.path,
        deleteOnClose: true,
      );
    }
    final sourceFilePath = result.sourceFilePath;
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      return null;
    }
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync()) {
      return null;
    }
    return _BridgeArtifactEntry(sourceFilePath: sourceFile.path);
  }

  Future<File> _persistArtifactBytes(String basename, List<int> bytes) async {
    final file = await _artifactTempFileFactory(basename);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  CockpitRecordingResult _recordingResultForTransport(
    CockpitRecordingResult result, {
    bool includeArtifact = true,
  }) {
    return result.copyWith(
      artifact: includeArtifact ? result.artifact : null,
      bytes: null,
      sourceFilePath: null,
    );
  }

  Future<CockpitRemoteSessionEndpointResponse?> _localArtifactResponse(
    Uri uri,
  ) async {
    final relativePath = uri.queryParameters['path'];
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }
    final entry = _localArtifacts[relativePath];
    if (entry == null) {
      return null;
    }
    final sourceFilePath = entry.sourceFilePath;
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      _localArtifacts.remove(relativePath);
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'artifactNotFound',
        'message': 'Artifact content is unavailable.',
      }, statusCode: HttpStatus.notFound);
    }
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync()) {
      _localArtifacts.remove(relativePath);
      return const CockpitRemoteSessionEndpointResponse.json(<String, Object?>{
        'error': 'artifactNotFound',
        'message': 'Artifact file is no longer available.',
      }, statusCode: HttpStatus.notFound);
    }
    return CockpitRemoteSessionEndpointResponse.binaryFile(sourceFile.path);
  }

  Future<void> _bestEffortStopActiveRecording() async {
    if (_activeRecordingSession == null) {
      return;
    }
    final adapter = recordingAdapter;
    _activeRecordingSession = null;
    if (adapter == null) {
      return;
    }
    try {
      await adapter.stopRecording();
    } on Object {
      // Cleanup is best-effort during bridge shutdown.
    }
  }

  Future<void> _deleteGeneratedArtifacts() async {
    final artifacts = _localArtifacts.values.toList(growable: false);
    _localArtifacts.clear();
    for (final artifact in artifacts) {
      if (!artifact.deleteOnClose) {
        continue;
      }
      final sourceFilePath = artifact.sourceFilePath;
      if (sourceFilePath == null || sourceFilePath.isEmpty) {
        continue;
      }
      try {
        final file = File(sourceFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      } on Object {
        // Best-effort cleanup only for bridge-generated artifact files.
      }
    }
  }

  void _failPending(Object error) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final pendingRequest in pending) {
      pendingRequest.connection.pendingRequestIds.clear();
      if (!pendingRequest.completer.isCompleted) {
        pendingRequest.completer.completeError(error);
      }
    }
  }

  void _removeConnection(_BridgeConnection connection, Object error) {
    if (connection.closed) {
      return;
    }
    connection.closed = true;
    _connections.remove(connection);
    if (identical(_activeConnection, connection)) {
      _activeConnection = null;
    }
    _failConnectionPending(connection, error);
  }

  void _pruneClosedConnections() {
    _connections.removeWhere((connection) => connection.closed);
    final active = _activeConnection;
    if (active != null && active.closed) {
      _activeConnection = null;
    }
  }

  void _failConnectionPending(_BridgeConnection connection, Object error) {
    final requestIds = connection.pendingRequestIds.toList(growable: false);
    connection.pendingRequestIds.clear();
    for (final requestId in requestIds) {
      final pendingRequest = _pending.remove(requestId);
      if (pendingRequest != null && !pendingRequest.completer.isCompleted) {
        pendingRequest.completer.completeError(error);
      }
    }
  }

  void _completeConnectionPendingWithBridgeError(
    _BridgeConnection connection, {
    required int statusCode,
    required String error,
    required String message,
  }) {
    if (connection.pendingRequestIds.isEmpty) {
      return;
    }
    final requestIds = connection.pendingRequestIds.toList(growable: false);
    final responseBody = <String, Object?>{'error': error, 'message': message};
    for (final requestId in requestIds) {
      final pendingRequest = _pending.remove(requestId);
      connection.pendingRequestIds.remove(requestId);
      pendingRequest?.completer.complete(
        CockpitRemoteBridgeResponse(
          requestId: requestId,
          statusCode: statusCode,
          jsonBody: responseBody,
        ),
      );
    }
  }

  String get _normalizedRoutePrefix {
    if (routePrefix.isEmpty || routePrefix == '/') {
      return '';
    }
    final withLeadingSlash = routePrefix.startsWith('/')
        ? routePrefix
        : '/$routePrefix';
    return withLeadingSlash.endsWith('/')
        ? withLeadingSlash.substring(0, withLeadingSlash.length - 1)
        : withLeadingSlash;
  }

  String _downloadPathFor(String relativePath) {
    return '$_normalizedRoutePrefix/artifacts/download?path=${Uri.encodeQueryComponent(relativePath)}';
  }

  String? _routePathFor(String path) {
    final prefix = _normalizedRoutePrefix;
    if (prefix.isEmpty) {
      return path;
    }
    if (path == prefix) {
      return '/';
    }
    if (path.startsWith('$prefix/')) {
      return path.substring(prefix.length);
    }
    return null;
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

bool _isRequiredEvidenceArtifact(CockpitArtifactRef artifact) {
  return artifact.role == 'screenshot' || artifact.role == 'step_screenshot';
}

final class _BridgeArtifactEntry {
  const _BridgeArtifactEntry({this.sourceFilePath, this.deleteOnClose = false});

  final String? sourceFilePath;
  final bool deleteOnClose;
}

final class _BridgeConnection {
  _BridgeConnection({required this.id, required this.socket});

  final int id;
  final WebSocket socket;
  final Set<String> pendingRequestIds = <String>{};
  StreamSubscription<Object?>? subscription;
  bool closed = false;
  bool stale = false;
}

final class _PendingBridgeRequest {
  const _PendingBridgeRequest({
    required this.connection,
    required this.completer,
  });

  final _BridgeConnection connection;
  final Completer<CockpitRemoteBridgeResponse> completer;
}

final class _BridgeConnectionSelection {
  const _BridgeConnectionSelection({this.connection, this.failureResponse});

  final _BridgeConnection? connection;
  final CockpitRemoteSessionEndpointResponse? failureResponse;
}

String _sanitizeArtifactBasename(String relativePath) {
  final basename = relativePath.split('/').last;
  final sanitized = basename.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return sanitized.isEmpty ? 'artifact.bin' : sanitized;
}

Future<File> _defaultBridgeArtifactTempFileFactory(String basename) async {
  return File(
    [
      Directory.systemTemp.path,
      '${cockpitSortableTimestampToken(DateTime.now())}_flutter_cockpit_bridge_$basename',
    ].join(Platform.pathSeparator),
  );
}

String _joinPath(String basePath, String segment) {
  if (basePath.isEmpty || basePath == '/') {
    return '/$segment';
  }
  return '$basePath/$segment';
}

const int _maxBridgeMessageBytes = 4 * 1024 * 1024;
const int _maxBridgeRequestBytes = 1 << 20;

final class _BridgeRequestTooLarge implements Exception {
  const _BridgeRequestTooLarge();
}

Future<String> _readBoundedRequestText(HttpRequest request) async {
  if (request.contentLength > _maxBridgeRequestBytes) {
    await request.drain<void>();
    throw const _BridgeRequestTooLarge();
  }
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  var tooLarge = false;
  await for (final chunk in request) {
    if (tooLarge) continue;
    length += chunk.length;
    if (length > _maxBridgeRequestBytes) {
      tooLarge = true;
      continue;
    }
    bytes.add(chunk);
  }
  if (tooLarge) throw const _BridgeRequestTooLarge();
  return utf8.decode(bytes.takeBytes());
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
