import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_protocol/cockpit_remote_bridge_protocol.dart';
import 'package:cockpit/src/bridge/cockpit_web_remote_session_bridge_server.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/recording/cockpit_host_recording_adapter.dart';
import 'package:test/test.dart';

void main() {
  test(
    'web bridge proxies browser endpoints and serves host recording artifacts',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_web_remote_session_bridge_artifacts',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File('${tempDir.path}/recordings/web-acceptance.mp4')
        ..parent.createSync(recursive: true);
      final startedRecordings = <CockpitRecordingRequest>[];
      var stopRecordingCount = 0;
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        routePrefix: '/cockpit',
        recordingAdapter: _FakeHostRecordingAdapter(
          onStart: (request) async {
            startedRecordings.add(request);
            return CockpitRecordingSession(
              request: request,
              state: CockpitRecordingState.recording,
            );
          },
          onStop: () async {
            stopRecordingCount += 1;
            sourceFile.writeAsStringSync('host-recording');
            return CockpitRecordingResult(
              state: CockpitRecordingState.completed,
              purpose: CockpitRecordingPurpose.acceptance,
              recordingKind: CockpitRecordingKind.nativeScreen,
              artifact: const CockpitArtifactRef(
                role: 'recording',
                relativePath: 'recordings/web-acceptance.mp4',
              ),
              sourceFilePath: sourceFile.path,
              durationMs: 1800,
            );
          },
        ),
      );
      await server.start();
      addTearDown(server.close);
      expect(server.baseUri.path, '/cockpit');

      final unscopedHealthResponse = await _readBytesResponse(
        server.baseUri.replace(path: '/health'),
      );
      expect(unscopedHealthResponse.statusCode, HttpStatus.notFound);

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);

      socket.listen((payload) {
        final message = CockpitRemoteBridgeRequest.fromJson(
          Map<String, Object?>.from(
            jsonDecode(payload as String) as Map<Object?, Object?>,
          ),
        );
        final messagePath = Uri.parse(message.path).path;
        switch (messagePath) {
          case '/cockpit/health':
            socket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 200,
                  jsonBody: <String, Object?>{
                    'sessionId': 'web-session',
                    'platform': 'web',
                    'transportType': 'remoteHttp',
                    'currentRouteName': '/inbox',
                    'capabilities': CockpitCapabilities(
                      platform: 'web',
                      transportType: 'remoteHttp',
                      supportsInAppControl: true,
                      supportsFlutterViewCapture: true,
                      supportsNativeScreenCapture: false,
                      supportsHostAutomation: false,
                    ).toJson(),
                    'recordingCapabilities': CockpitRecordingCapabilities(
                      supportsNativeRecording: false,
                    ).toJson(),
                    'snapshot': CockpitSnapshot(routeName: '/inbox').toJson(),
                  },
                ).toJson(),
              ),
            );
          case '/cockpit/commands/execute':
            socket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 200,
                  jsonBody: <String, Object?>{
                    'result': CockpitCommandResult(
                      success: true,
                      commandId: 'tap-open',
                      commandType: CockpitCommandType.tap,
                      durationMs: 12,
                      artifacts: const <CockpitArtifactRef>[
                        CockpitArtifactRef(
                          role: 'screenshot',
                          relativePath: 'browser/screenshot.png',
                        ),
                      ],
                    ).toJson(),
                    'artifactPayloads': <Object?>[
                      const CockpitRemoteArtifactPayload(
                        artifact: CockpitArtifactRef(
                          role: 'screenshot',
                          relativePath: 'browser/screenshot.png',
                        ),
                        bytes: <int>[1, 2, 3, 4],
                      ).toJson(),
                    ],
                  },
                ).toJson(),
              ),
            );
          case '/cockpit/artifacts/download':
            socket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 200,
                  bytesBase64: base64Encode(utf8.encode('browser-artifact')),
                ).toJson(),
              ),
            );
          default:
            socket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 404,
                  jsonBody: <String, Object?>{'error': 'not_found'},
                ).toJson(),
              ),
            );
        }
      });

      final healthJson = await _readJson(Uri.parse('${server.baseUri}/health'));
      expect(
        (healthJson['recordingCapabilities']
            as Map<String, Object?>)['supportsNativeRecording'],
        isTrue,
      );
      expect(
        ((healthJson['recordingCapabilities']
                    as Map<String, Object?>)['recordingLimitations']!
                as List<Object?>)
            .single,
        contains('requires screen-capture permission'),
      );
      expect(
        ((healthJson['recordingCapabilities']
                    as Map<String, Object?>)['recordingLimitations']!
                as List<Object?>)
            .single,
        contains('best-effort'),
      );

      final startJson = await _postJson(
        Uri.parse('${server.baseUri}/recording/start'),
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'web_acceptance',
        ).toJson(),
      );
      expect(startedRecordings, hasLength(1));
      expect(startJson['state'], 'recording');

      final commandJson = await _postJson(
        Uri.parse('${server.baseUri}/commands/execute'),
        CockpitCommand(
          commandId: 'tap-open',
          commandType: CockpitCommandType.tap,
        ).toJson(),
      );
      expect(
        ((commandJson['result'] as Map<String, Object?>)['success']) as bool,
        isTrue,
      );
      expect(commandJson['artifactPayloads'], isEmpty);
      final commandDownloads =
          (commandJson['artifactDownloads'] as List<Object?>)
              .cast<Map<Object?, Object?>>();
      expect(commandDownloads, hasLength(1));
      final commandDownloadPath =
          commandDownloads.single['downloadPath']! as String;
      expect(
        commandDownloadPath,
        startsWith('/cockpit/artifacts/download?path='),
      );
      final commandArtifactBytes = await _readBytes(
        server.baseUri.resolve(commandDownloadPath),
      );
      expect(commandArtifactBytes, <int>[1, 2, 3, 4]);

      final stopJson = await _postJson(
        Uri.parse('${server.baseUri}/recording/stop'),
        const <String, Object?>{},
      );
      expect(stopRecordingCount, 1);
      final downloads = (stopJson['artifactDownloads'] as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(downloads, hasLength(1));
      final downloadPath = downloads.single['downloadPath']! as String;
      expect(downloadPath, startsWith('/cockpit/artifacts/download?path='));

      final hostRecordingBytes = await _readBytes(
        server.baseUri.resolve(downloadPath),
      );
      expect(utf8.decode(hostRecordingBytes), 'host-recording');
      sourceFile.deleteSync();
      final deletedResponse = await _readBytesResponse(
        server.baseUri.resolve(downloadPath),
      );
      expect(deletedResponse.statusCode, HttpStatus.notFound);

      final missingBrowserProxyArtifact = await _readBytesResponse(
        Uri.parse(
          '${server.baseUri}/artifacts/download?path=browser%2Fproxied.png',
        ),
      );
      expect(missingBrowserProxyArtifact.statusCode, HttpStatus.ok);
      expect(
        utf8.decode(missingBrowserProxyArtifact.bytes),
        'browser-artifact',
      );
    },
  );

  test(
    'web bridge protects HTTP and websocket endpoints with token, origin, and connection limits',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        authToken: 'bridge-secret',
        allowedOrigin: 'https://trusted.example',
        maxConnections: 1,
        recordingAdapter: _FakeHostRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
          onStop: () async =>
              CockpitRecordingResult(state: CockpitRecordingState.failed),
        ),
      );
      await server.start();
      addTearDown(server.close);

      final missingToken = await _readJsonResponse(
        server.baseUri.resolve('/health'),
      );
      expect(missingToken.statusCode, HttpStatus.unauthorized);
      expect(missingToken.body['error'], 'unauthorized');

      final queryTokenOnHttpEndpoint = await _readJsonResponse(
        server.baseUri.replace(
          path: '${server.baseUri.path}/health',
          queryParameters: const <String, String>{'token': 'bridge-secret'},
        ),
      );
      expect(queryTokenOnHttpEndpoint.statusCode, HttpStatus.unauthorized);

      final wrongToken = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{'x-cockpit-token': 'wrong'},
      );
      expect(wrongToken.statusCode, HttpStatus.unauthorized);

      final wrongOrigin = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{
          'x-cockpit-token': 'bridge-secret',
          'origin': 'https://untrusted.example',
        },
      );
      expect(wrongOrigin.statusCode, HttpStatus.unauthorized);

      final authorizedHealth = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{
          'x-cockpit-token': 'bridge-secret',
          'origin': 'https://trusted.example',
        },
      );
      expect(authorizedHealth.statusCode, HttpStatus.serviceUnavailable);
      expect(authorizedHealth.body['error'], 'bridgeUnavailable');

      final oversized = await _postRawResponse(
        server.baseUri.resolve('/recording/start'),
        List<int>.filled((1 << 20) + 1, 65),
        headers: const <String, String>{'x-cockpit-token': 'bridge-secret'},
      );
      expect(oversized.statusCode, HttpStatus.requestEntityTooLarge);
      expect(oversized.body['error'], 'requestTooLarge');

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);
      final tooManyConnections = await _webSocketHandshakeResponse(
        server.connectUri,
      );
      expect(tooManyConnections.statusCode, HttpStatus.tooManyRequests);
    },
  );

  test(
    'web bridge accepts browser origins when no origin allowlist is configured',
    () async {
      // Development launches never configure an allowlist: the Flutter tool
      // serves the page from an ephemeral origin. Rejecting browser origins
      // outright would keep the page's bridge connection out forever, so the
      // session token stays the only gate.
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        authToken: 'bridge-secret',
      );
      await server.start();
      addTearDown(server.close);

      final browserOriginWithoutToken = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{'origin': 'http://localhost:63119'},
      );
      expect(browserOriginWithoutToken.statusCode, HttpStatus.unauthorized);

      // The browser's query credential is confined to the /connect
      // handshake; ordinary endpoints reject it even when correct.
      final browserOriginWithQueryToken = await _readJsonResponse(
        server.baseUri.replace(
          path: '${server.baseUri.path}/health',
          queryParameters: const <String, String>{'token': 'bridge-secret'},
        ),
        headers: const <String, String>{'origin': 'http://localhost:63119'},
      );
      expect(browserOriginWithQueryToken.statusCode, HttpStatus.unauthorized);

      final browserOriginWithToken = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{
          'x-cockpit-token': 'bridge-secret',
          'origin': 'http://localhost:63119',
        },
      );
      expect(browserOriginWithToken.statusCode, HttpStatus.serviceUnavailable);
      expect(browserOriginWithToken.body['error'], 'bridgeUnavailable');

      // Host-side probes authenticate with headers instead of the query
      // string, mirroring the in-app remote session server's transports.
      final headerToken = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{'x-cockpit-token': 'bridge-secret'},
      );
      expect(headerToken.statusCode, HttpStatus.serviceUnavailable);
      expect(headerToken.body['error'], 'bridgeUnavailable');

      final bearerToken = await _readJsonResponse(
        server.baseUri.resolve('/health'),
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'bearer bridge-secret',
        },
      );
      expect(bearerToken.statusCode, HttpStatus.serviceUnavailable);
      expect(bearerToken.body['error'], 'bridgeUnavailable');

      // The /connect handshake keeps accepting the query credential that
      // browsers are forced to use.
      final socket = await WebSocket.connect(server.connectUri.toString());
      await socket.close();
    },
  );

  test('web bridge factory prefers the explicit launch token', () async {
    final handle = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-1',
      platform: 'web',
      deviceId: 'chrome',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: '',
      appBaseUrl: 'http://127.0.0.1:40477',
      supervisorBaseUrl: 'cockpit-worker://development/dev-session-1',
      launchedAt: DateTime.utc(2026, 9, 10),
      reloadGeneration: 0,
    );

    final bridge = cockpitCreateWebRemoteSessionBridgeServer(
      handle: handle,
      authToken: 'launch-token-9',
    )!;
    await bridge.start();
    addTearDown(bridge.close);

    expect(bridge.authToken, 'launch-token-9');
    expect(bridge.connectUri.queryParameters['token'], 'launch-token-9');

    final nativeHandle = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-2',
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: '',
      appBaseUrl: 'http://127.0.0.1:40478',
      supervisorBaseUrl: 'cockpit-worker://development/dev-session-2',
      launchedAt: DateTime.utc(2026, 9, 10),
      reloadGeneration: 0,
    );
    expect(
      cockpitCreateWebRemoteSessionBridgeServer(handle: nativeHandle),
      isNull,
    );
  });

  test(
    'web bridge returns a structured prerequisite failure when host recording cannot start',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        recordingAdapter: _FakeHostRecordingAdapter(
          onStart: (_) async {
            throw StateError('Screen Recording permission is missing.');
          },
          onStop: () async => throw StateError('no active recording'),
        ),
      );
      await server.start();
      addTearDown(server.close);

      final response = await _postJsonResponse(
        server.baseUri.resolve('/recording/start'),
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'web_acceptance',
        ).toJson(),
      );

      expect(response.statusCode, HttpStatus.preconditionFailed);
      expect(response.body['error'], 'recordingStartFailed');
      expect(
        response.body['message'],
        contains('Screen Recording permission is missing.'),
      );
    },
  );

  test(
    'web bridge externalizes inline recording bytes without bloating JSON responses',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_web_bridge_inline_recording',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final generatedFile = File('${tempDir.path}/web-inline.mp4');
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        artifactTempFileFactory: (_) async => generatedFile,
        recordingAdapter: _FakeHostRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
          onStop: () async => CockpitRecordingResult(
            state: CockpitRecordingState.completed,
            purpose: CockpitRecordingPurpose.acceptance,
            recordingKind: CockpitRecordingKind.nativeScreen,
            artifact: const CockpitArtifactRef(
              role: 'recording',
              relativePath: 'recordings/web-inline.mp4',
            ),
            bytes: const <int>[4, 3, 2, 1],
            sourceFilePath: '/browser/private/web-inline.mp4',
            durationMs: 1200,
          ),
        ),
      );
      await server.start();

      await _postJson(
        server.baseUri.resolve('/recording/start'),
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'web_inline',
        ).toJson(),
      );

      final stopJson = await _postJson(
        server.baseUri.resolve('/recording/stop'),
        const <String, Object?>{},
      );
      final resultPayload = Map<String, Object?>.from(
        stopJson['result']! as Map<Object?, Object?>,
      );
      expect(resultPayload.containsKey('bytes'), isFalse);
      expect(resultPayload.containsKey('sourceFilePath'), isFalse);
      final downloads = (stopJson['artifactDownloads'] as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(downloads, hasLength(1));

      expect(
        await _readBytes(
          server.baseUri.resolve(downloads.single['downloadPath']! as String),
        ),
        <int>[4, 3, 2, 1],
      );
      expect(generatedFile.existsSync(), isTrue);

      await server.close();
      expect(generatedFile.existsSync(), isFalse);
    },
  );

  test('web bridge rejects empty required command artifact payloads', () async {
    final server = CockpitWebRemoteSessionBridgeServer(
      bindHost: '127.0.0.1',
      bindPort: 0,
    );
    await server.start();
    addTearDown(server.close);

    final socket = await WebSocket.connect(server.connectUri.toString());
    addTearDown(socket.close);
    socket.listen((payload) {
      final message = CockpitRemoteBridgeRequest.fromJson(
        Map<String, Object?>.from(
          jsonDecode(payload as String) as Map<Object?, Object?>,
        ),
      );
      socket.add(
        jsonEncode(
          CockpitRemoteBridgeResponse(
            requestId: message.requestId,
            statusCode: 200,
            jsonBody: <String, Object?>{
              'result': CockpitCommandResult(
                success: true,
                commandId: 'tap-open',
                commandType: CockpitCommandType.tap,
                durationMs: 12,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/empty.png',
                  ),
                ],
              ).toJson(),
              'artifactPayloads': <Object?>[
                const CockpitRemoteArtifactPayload(
                  artifact: CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/empty.png',
                  ),
                  bytes: <int>[],
                ).toJson(),
              ],
            },
          ).toJson(),
        ),
      );
    });

    final response = await _postJsonResponse(
      server.baseUri.resolve('/commands/execute'),
      CockpitCommand(
        commandId: 'tap-open',
        commandType: CockpitCommandType.tap,
      ).toJson(),
    );

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(response.body['error'], 'artifactPayloadEmpty');
    expect(
      (response.body['details'] as Map<Object?, Object?>)['artifactPath'],
      'screenshots/empty.png',
    );
  });

  test(
    'web bridge keeps stale reconnecting clients from replacing a ready client',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(seconds: 2),
      );
      await server.start();
      addTearDown(server.close);

      final staleSocket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(staleSocket.close);
      _serveBridgeSocket(staleSocket, (message) {
        return CockpitRemoteBridgeResponse(
          requestId: message.requestId,
          statusCode: message.uri.path == '/ready' ? 200 : 500,
          jsonBody: message.uri.path == '/ready'
              ? const <String, Object?>{
                  'ready': false,
                  'currentRouteName': '/inbox',
                  'supportsInAppControl': false,
                }
              : const <String, Object?>{
                  'error': 'serverError',
                  'message': 'Bad state: FlutterCockpitRoot is not mounted.',
                },
        );
      });

      final readySocket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(readySocket.close);
      _serveBridgeSocket(readySocket, (message) {
        switch (message.uri.path) {
          case '/ready':
            return CockpitRemoteBridgeResponse(
              requestId: message.requestId,
              statusCode: 200,
              jsonBody: const <String, Object?>{
                'ready': true,
                'currentRouteName': '/inbox',
                'supportsInAppControl': true,
              },
            );
          case '/snapshot':
            return CockpitRemoteBridgeResponse(
              requestId: message.requestId,
              statusCode: 200,
              jsonBody: CockpitSnapshot(routeName: '/inbox').toJson(),
            );
          case '/commands/execute':
            return CockpitRemoteBridgeResponse(
              requestId: message.requestId,
              statusCode: 200,
              jsonBody: <String, Object?>{
                'result': CockpitCommandResult(
                  success: true,
                  commandId: 'wait-ready',
                  commandType: CockpitCommandType.waitForUiIdle,
                  durationMs: 4,
                  snapshot: CockpitSnapshot(routeName: '/inbox').toJson(),
                ).toJson(),
              },
            );
          default:
            return CockpitRemoteBridgeResponse(
              requestId: message.requestId,
              statusCode: 404,
              jsonBody: const <String, Object?>{'error': 'notFound'},
            );
        }
      });

      final staleReconnect = await WebSocket.connect(
        server.connectUri.toString(),
      );
      addTearDown(staleReconnect.close);
      _serveBridgeSocket(staleReconnect, (message) {
        return CockpitRemoteBridgeResponse(
          requestId: message.requestId,
          statusCode: message.uri.path == '/ready' ? 200 : 500,
          jsonBody: message.uri.path == '/ready'
              ? const <String, Object?>{
                  'ready': false,
                  'currentRouteName': '/inbox',
                  'supportsInAppControl': false,
                }
              : const <String, Object?>{
                  'error': 'serverError',
                  'message': 'Bad state: FlutterCockpitRoot is not mounted.',
                },
        );
      });

      final ready = await _readJson(server.baseUri.resolve('/ready'));
      expect(ready['ready'], isTrue);
      expect(ready['supportsInAppControl'], isTrue);

      final snapshot = await _readJson(server.baseUri.resolve('/snapshot'));
      expect(snapshot['routeName'], '/inbox');

      final command = await _postJson(
        server.baseUri.resolve('/commands/execute'),
        CockpitCommand(
          commandId: 'wait-ready',
          commandType: CockpitCommandType.waitForUiIdle,
          timeoutMs: 1000,
        ).toJson(),
      );
      expect((command['result'] as Map<Object?, Object?>)['success'], isTrue);
    },
  );

  test(
    'web bridge returns not-ready status when only a reconnecting client remains',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(seconds: 1),
      );
      await server.start();
      addTearDown(server.close);

      final readySocket = await WebSocket.connect(server.connectUri.toString());
      _serveBridgeSocket(readySocket, (message) {
        return CockpitRemoteBridgeResponse(
          requestId: message.requestId,
          statusCode: 200,
          jsonBody: const <String, Object?>{
            'ready': true,
            'currentRouteName': '/inbox',
            'supportsInAppControl': true,
          },
        );
      });

      final reconnectingSocket = await WebSocket.connect(
        server.connectUri.toString(),
      );
      addTearDown(reconnectingSocket.close);
      _serveBridgeSocket(reconnectingSocket, (message) {
        return CockpitRemoteBridgeResponse(
          requestId: message.requestId,
          statusCode: 200,
          jsonBody: const <String, Object?>{
            'ready': false,
            'currentRouteName': '/inbox',
            'supportsInAppControl': false,
          },
        );
      });

      await readySocket.close();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final response = await _readJsonResponse(
        server.baseUri.resolve('/ready'),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body['ready'], isFalse);
      expect(response.body['supportsInAppControl'], isFalse);
    },
  );

  test(
    'web bridge ignores cross-connection response ids without cancelling owner request',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(seconds: 1),
      );
      await server.start();
      addTearDown(server.close);

      final snapshotRequestId = Completer<String>();
      final allowSnapshotResponse = Completer<void>();
      final readySocket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(readySocket.close);
      readySocket.listen((payload) async {
        final message = CockpitRemoteBridgeRequest.fromJson(
          Map<String, Object?>.from(
            jsonDecode(payload as String) as Map<Object?, Object?>,
          ),
        );
        switch (message.uri.path) {
          case '/ready':
            readySocket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 200,
                  jsonBody: const <String, Object?>{
                    'ready': true,
                    'currentRouteName': '/inbox',
                    'supportsInAppControl': true,
                  },
                ).toJson(),
              ),
            );
          case '/snapshot':
            if (!snapshotRequestId.isCompleted) {
              snapshotRequestId.complete(message.requestId);
            }
            await allowSnapshotResponse.future;
            readySocket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 200,
                  jsonBody: CockpitSnapshot(routeName: '/inbox').toJson(),
                ).toJson(),
              ),
            );
          default:
            readySocket.add(
              jsonEncode(
                CockpitRemoteBridgeResponse(
                  requestId: message.requestId,
                  statusCode: 404,
                  jsonBody: const <String, Object?>{'error': 'notFound'},
                ).toJson(),
              ),
            );
        }
      });

      final reconnectingSocket = await WebSocket.connect(
        server.connectUri.toString(),
      );
      addTearDown(reconnectingSocket.close);
      _serveBridgeSocket(reconnectingSocket, (message) {
        return CockpitRemoteBridgeResponse(
          requestId: message.requestId,
          statusCode: 200,
          jsonBody: const <String, Object?>{
            'ready': false,
            'currentRouteName': '/inbox',
            'supportsInAppControl': false,
          },
        );
      });

      final snapshotFuture = _readJsonResponse(
        server.baseUri.resolve('/snapshot'),
      );
      final hijackedRequestId = await snapshotRequestId.future;
      reconnectingSocket.add(
        jsonEncode(
          CockpitRemoteBridgeResponse(
            requestId: hijackedRequestId,
            statusCode: 200,
            jsonBody: const <String, Object?>{'hijacked': true},
          ).toJson(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      allowSnapshotResponse.complete();

      final response = await snapshotFuture;

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body['routeName'], '/inbox');
      expect(response.body.containsKey('hijacked'), isFalse);
    },
  );

  test(
    'web bridge stops an active host recording when the server closes',
    () async {
      var stopRecordingCount = 0;
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        recordingAdapter: _FakeHostRecordingAdapter(
          onStart: (request) async => CockpitRecordingSession(
            request: request,
            state: CockpitRecordingState.recording,
          ),
          onStop: () async {
            stopRecordingCount += 1;
            return CockpitRecordingResult(
              state: CockpitRecordingState.completed,
              purpose: CockpitRecordingPurpose.acceptance,
              recordingKind: CockpitRecordingKind.nativeScreen,
            );
          },
        ),
      );
      await server.start();

      await _postJson(
        server.baseUri.resolve('/recording/start'),
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'web_acceptance',
        ).toJson(),
      );

      await server.close();

      expect(stopRecordingCount, 1);
    },
  );

  test('web bridge default timeout leaves remote client headroom', () {
    final server = CockpitWebRemoteSessionBridgeServer(
      bindHost: '127.0.0.1',
      bindPort: 0,
    );

    expect(server.requestTimeout, const Duration(seconds: 20));
    expect(server.requestTimeout, lessThan(const Duration(seconds: 30)));
  });

  test(
    'web bridge returns a structured timeout when the browser is unresponsive',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(milliseconds: 50),
      );
      await server.start();
      addTearDown(server.close);

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);
      socket.listen((_) {});

      final stopwatch = Stopwatch()..start();
      final response = await _readJsonResponse(
        server.baseUri.resolve('/health'),
      );
      stopwatch.stop();

      expect(response.statusCode, HttpStatus.gatewayTimeout);
      expect(response.body['error'], 'bridgeTimeout');
      expect(
        response.body['message'],
        contains('browser bridge did not respond'),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test(
    'web bridge honors command timeoutMs before timing out command execution',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(milliseconds: 50),
      );
      await server.start();
      addTearDown(server.close);

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);
      socket.listen((payload) async {
        final message = CockpitRemoteBridgeRequest.fromJson(
          Map<String, Object?>.from(
            jsonDecode(payload as String) as Map<Object?, Object?>,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        socket.add(
          jsonEncode(
            CockpitRemoteBridgeResponse(
              requestId: message.requestId,
              statusCode: 200,
              jsonBody: <String, Object?>{
                'result': CockpitCommandResult(
                  success: true,
                  commandId: 'slow-wait',
                  commandType: CockpitCommandType.waitFor,
                  durationMs: 120,
                ).toJson(),
              },
            ).toJson(),
          ),
        );
      });

      final response = await _postJsonResponse(
        server.baseUri.resolve('/commands/execute'),
        CockpitCommand(
          commandId: 'slow-wait',
          commandType: CockpitCommandType.waitFor,
          timeoutMs: 500,
        ).toJson(),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(
        ((response.body['result'] as Map<String, Object?>)['success']) as bool,
        isTrue,
      );
    },
  );

  test(
    'web bridge reports malformed browser responses without timeout',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(seconds: 5),
      );
      await server.start();
      addTearDown(server.close);

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);
      socket.listen((_) {
        socket.add(
          jsonEncode(const <String, Object?>{
            'statusCode': 200,
            'jsonBody': <String, Object?>{'ok': true},
          }),
        );
      });

      final stopwatch = Stopwatch()..start();
      final response = await _readJsonResponse(
        server.baseUri.resolve('/health'),
      );
      stopwatch.stop();

      expect(response.statusCode, HttpStatus.badGateway);
      expect(response.body['error'], 'bridgeInvalidResponse');
      expect(
        response.body['message'],
        contains('"requestId" must be a non-empty string'),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test(
    'web bridge reports unknown browser response ids without timeout',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(seconds: 5),
      );
      await server.start();
      addTearDown(server.close);

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);
      socket.listen((_) {
        socket.add(
          jsonEncode(
            const CockpitRemoteBridgeResponse(
              requestId: 'wrong-request-id',
              statusCode: 200,
              jsonBody: <String, Object?>{'ok': true},
            ).toJson(),
          ),
        );
      });

      final stopwatch = Stopwatch()..start();
      final response = await _readJsonResponse(
        server.baseUri.resolve('/health'),
      );
      stopwatch.stop();

      expect(response.statusCode, HttpStatus.badGateway);
      expect(response.body['error'], 'bridgeUnknownResponse');
      expect(response.body['message'], contains('wrong-request-id'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test(
    'web bridge reports invalid binary bridge responses without timeout',
    () async {
      final server = CockpitWebRemoteSessionBridgeServer(
        bindHost: '127.0.0.1',
        bindPort: 0,
        requestTimeout: const Duration(seconds: 5),
      );
      await server.start();
      addTearDown(server.close);

      final socket = await WebSocket.connect(server.connectUri.toString());
      addTearDown(socket.close);
      socket.listen((payload) {
        final message = CockpitRemoteBridgeRequest.fromJson(
          Map<String, Object?>.from(
            jsonDecode(payload as String) as Map<Object?, Object?>,
          ),
        );
        socket.add(
          jsonEncode(
            CockpitRemoteBridgeResponse(
              requestId: message.requestId,
              statusCode: 200,
              bytesBase64: 'not base64',
            ).toJson(),
          ),
        );
      });

      final stopwatch = Stopwatch()..start();
      final response = await _readJsonResponse(
        Uri.parse('${server.baseUri}/artifacts/download?path=image.png'),
      );
      stopwatch.stop();

      expect(response.statusCode, HttpStatus.badGateway);
      expect(response.body['error'], 'bridgeInvalidResponse');
      expect(response.body['message'], contains('"bytesBase64"'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );
}

final class _FakeHostRecordingAdapter implements CockpitHostRecordingAdapter {
  const _FakeHostRecordingAdapter({
    required this.onStart,
    required this.onStop,
  });

  final Future<CockpitRecordingSession> Function(
    CockpitRecordingRequest request,
  )
  onStart;
  final Future<CockpitRecordingResult> Function() onStop;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) {
    return onStart(request);
  }

  @override
  Future<CockpitRecordingResult> stopRecording() {
    return onStop();
  }
}

void _serveBridgeSocket(
  WebSocket socket,
  CockpitRemoteBridgeResponse Function(CockpitRemoteBridgeRequest request)
  handle,
) {
  socket.listen((payload) {
    final message = CockpitRemoteBridgeRequest.fromJson(
      Map<String, Object?>.from(
        jsonDecode(payload as String) as Map<Object?, Object?>,
      ),
    );
    socket.add(jsonEncode(handle(message).toJson()));
  });
}

Future<Map<String, Object?>> _readJson(Uri uri) async {
  return (await _readJsonResponse(uri)).body;
}

Future<_HttpJsonResponse> _readJsonResponse(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final rawPayload = await utf8.decoder.bind(response).join();
    return _HttpJsonResponse(
      statusCode: response.statusCode,
      body: rawPayload.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(rawPayload) as Map<Object?, Object?>,
            ),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_HttpJsonResponse> _webSocketHandshakeResponse(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
    );
    request.headers
      ..set(HttpHeaders.connectionHeader, HttpHeaders.upgradeHeader)
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('sec-websocket-version', '13')
      ..set('sec-websocket-key', base64Encode(List<int>.filled(16, 7)));
    final response = await request.close();
    final payload = await utf8.decoder.bind(response).join();
    final decoded = payload.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(
            jsonDecode(payload) as Map<Object?, Object?>,
          );
    return _HttpJsonResponse(statusCode: response.statusCode, body: decoded);
  } finally {
    client.close(force: true);
  }
}

Future<_HttpJsonResponse> _postRawResponse(
  Uri uri,
  List<int> bytes, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    request.add(bytes);
    final response = await request.close();
    final payload = await utf8.decoder.bind(response).join();
    return _HttpJsonResponse(
      statusCode: response.statusCode,
      body: payload.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(payload) as Map<Object?, Object?>,
            ),
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _postJson(
  Uri uri,
  Map<String, Object?> body,
) async {
  final response = await _postJsonResponse(uri, body);
  return response.body;
}

Future<_HttpJsonResponse> _postJsonResponse(
  Uri uri,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final payload = await utf8.decoder.bind(response).join();
    return _HttpJsonResponse(
      statusCode: response.statusCode,
      body: Map<String, Object?>.from(
        jsonDecode(payload) as Map<Object?, Object?>,
      ),
    );
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _readBytes(Uri uri) async {
  final response = await _readBytesResponse(uri);
  return response.bytes;
}

Future<_HttpBytesResponse> _readBytesResponse(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (bytes, chunk) {
      final next = List<int>.of(bytes);
      next.addAll(chunk);
      return next;
    });
    return _HttpBytesResponse(statusCode: response.statusCode, bytes: bytes);
  } finally {
    client.close(force: true);
  }
}

final class _HttpJsonResponse {
  const _HttpJsonResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
}

final class _HttpBytesResponse {
  const _HttpBytesResponse({required this.statusCode, required this.bytes});

  final int statusCode;
  final List<int> bytes;
}
