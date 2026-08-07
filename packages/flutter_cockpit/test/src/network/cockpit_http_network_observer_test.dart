import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:test/test.dart';

void main() {
  test('explicit parent overrides are retained for advanced setups', () {
    final observer = CockpitHttpNetworkObserver();

    expect(observer.hasAttachedParentOverrides, isFalse);
    observer.attachParentOverrides(HttpOverrides.current);
    expect(observer.hasAttachedParentOverrides, isTrue);
  });

  test('network redactor covers URLs, forms, and truncated payloads', () {
    const redactor = CockpitNetworkRedactor();
    final uri = redactor.uri(
      Uri.parse(
        'https://user:url-password-secret@example.test/callback'
        '?signature=query-signature-secret&visible=yes',
      ),
    );
    final form = redactor.body(
      'username=visible-user&password=form-password-secret',
      contentType: 'application/x-www-form-urlencoded; charset=utf-8',
    );
    final truncatedJson = redactor.body(
      '{"access_token":"truncated-token-secret"',
      contentType: 'application/json',
    );

    expect(Uri.decodeComponent(uri.userInfo), CockpitNetworkRedactor.masked);
    expect(uri.toString(), isNot(contains('url-password-secret')));
    expect(uri.queryParameters['signature'], CockpitNetworkRedactor.masked);
    expect(uri.queryParameters['visible'], 'yes');
    expect(Uri(query: form).queryParameters['username'], 'visible-user');
    expect(
      Uri(query: form).queryParameters['password'],
      CockpitNetworkRedactor.masked,
    );
    expect(truncatedJson, isNot(contains('truncated-token-secret')));
    expect(
      redactor.body(
        'multipart-password-secret',
        contentType: 'multipart/form-data; boundary=test',
      ),
      CockpitNetworkRedactor.masked,
    );
    expect(
      redactor.text('-----BEGIN PRIVATE KEY-----\nprivate-key-secret'),
      CockpitNetworkRedactor.masked,
    );
  });

  test(
    'CockpitHttpNetworkObserver captures bounded request and response data',
    () async {
      final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
      observer.attachParentOverrides(HttpOverrides.current);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{'received': body, 'status': 'ok'}),
        );
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = HttpClient();
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/probe'),
        );
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode('{"probe":"sync"}'));
        final response = await request.close();
        await utf8.decoder.bind(response).join();
        client.close(force: true);
      }, createHttpClient: observer.createHttpClient);

      final snapshot = observer.snapshot(maxEntries: 5);
      expect(snapshot.totalEntryCount, 1);
      expect(snapshot.failureCount, 0);
      expect(snapshot.entries, hasLength(1));
      expect(snapshot.endpointSummaries, hasLength(1));
      expect(snapshot.entries.single.method, 'POST');
      expect(snapshot.entries.single.statusCode, 200);
      expect(snapshot.entries.single.uri, contains('/probe'));
      expect(snapshot.entries.single.requestBodyPreview, contains('sync'));
      expect(snapshot.entries.single.responseBodyPreview, contains('status'));
      expect(snapshot.endpointSummaries.single.method, 'POST');
      expect(snapshot.endpointSummaries.single.uriPattern, '/probe');
      expect(snapshot.endpointSummaries.single.requestCount, 1);
    },
  );

  test('CockpitHttpNetworkObserver redacts captured credentials', () async {
    final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
    observer.attachParentOverrides(HttpOverrides.current);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.setCookieHeader, 'session=server-cookie-secret');
      request.response.write(
        jsonEncode(<String, Object?>{
          'access_token': 'response-token-secret',
          'received': jsonDecode(body),
        }),
      );
      await request.response.close();
    });

    await HttpOverrides.runZoned(() async {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/login'
          '?access_token=query-token-secret&visible=yes',
        ),
      );
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer header-token-secret')
        ..set('X-Api-Key', 'header-api-secret')
        ..set('X-Diagnostic', 'Bearer diagnostic-token-secret');
      request.cookies.add(Cookie('session', 'request-cookie-secret'));
      request.write(
        jsonEncode(<String, Object?>{
          'username': 'visible-user',
          'password': 'body-password-secret',
          'nested': <String, Object?>{'refreshToken': 'body-token-secret'},
        }),
      );
      final response = await request.close();
      await utf8.decoder.bind(response).join();
      client.close(force: true);
    }, createHttpClient: observer.createHttpClient);

    final entry = observer.snapshot(maxEntries: 1).entries.single;
    final requestBody =
        jsonDecode(entry.requestBodyPreview!) as Map<String, Object?>;
    final responseBody =
        jsonDecode(entry.responseBodyPreview!) as Map<String, Object?>;

    expect(Uri.parse(entry.uri).queryParameters['access_token'], '********');
    expect(Uri.parse(entry.uri).queryParameters['visible'], 'yes');
    expect(
      _header(entry.requestHeaders, HttpHeaders.authorizationHeader),
      'Bearer ********',
    );
    expect(_header(entry.requestHeaders, 'x-api-key'), '********');
    expect(_header(entry.requestHeaders, 'x-diagnostic'), 'Bearer ********');
    expect(
      _header(entry.requestHeaders, HttpHeaders.cookieHeader),
      'session=********',
    );
    expect(requestBody['username'], 'visible-user');
    expect(requestBody['password'], '********');
    expect(
      (requestBody['nested']! as Map<String, Object?>)['refreshToken'],
      '********',
    );
    expect(
      _header(entry.responseHeaders, HttpHeaders.setCookieHeader),
      'session=********',
    );
    expect(responseBody['access_token'], '********');
    final captured = entry.toJson().toString();
    for (final secret in const <String>[
      'query-token-secret',
      'header-token-secret',
      'header-api-secret',
      'diagnostic-token-secret',
      'request-cookie-secret',
      'body-password-secret',
      'body-token-secret',
      'server-cookie-secret',
      'response-token-secret',
    ]) {
      expect(captured, isNot(contains(secret)));
    }
  });

  test(
    'CockpitHttpNetworkObserver can explicitly retain raw diagnostics',
    () async {
      final observer = CockpitHttpNetworkObserver(
        maxRetainedEntries: 10,
        redact: false,
      );
      observer.attachParentOverrides(HttpOverrides.current);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"token":"raw-response-token"}');
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = HttpClient();
        final request = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${server.port}/login?token=raw-query-token',
          ),
        );
        request.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.authorizationHeader, 'Bearer raw-header-token');
        request.write('{"password":"raw-body-password"}');
        final response = await request.close();
        await utf8.decoder.bind(response).join();
        client.close(force: true);
      }, createHttpClient: observer.createHttpClient);

      final captured = observer.snapshot(maxEntries: 1).entries.single.toJson();
      final text = captured.toString();
      expect(text, contains('raw-query-token'));
      expect(text, contains('raw-header-token'));
      expect(text, contains('raw-body-password'));
      expect(text, contains('raw-response-token'));
    },
  );

  test(
    'CockpitHttpNetworkObserver filters captured traffic for diagnostics',
    () async {
      final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
      observer.attachParentOverrides(HttpOverrides.current);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        switch ((request.method, request.uri.path)) {
          case ('GET', '/tasks'):
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(<String, Object?>{'items': 3}));
          case ('POST', '/sync/health'):
            request.response.statusCode = HttpStatus.serviceUnavailable;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, Object?>{'error': 'upstream timeout'}),
            );
          case ('POST', '/tasks'):
            request.response.statusCode = HttpStatus.created;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, Object?>{'status': 'ok'}),
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      await HttpOverrides.runZoned(() async {
        final client = HttpClient();
        final tasksResponse = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/tasks'),
        )).close();
        await utf8.decoder.bind(tasksResponse).join();

        final syncRequest = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/sync/health'),
        );
        final syncResponse = await syncRequest.close();
        await utf8.decoder.bind(syncResponse).join();

        final createRequest = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/tasks'),
        );
        final createResponse = await createRequest.close();
        await utf8.decoder.bind(createResponse).join();
        client.close(force: true);
      }, createHttpClient: observer.createHttpClient);

      final snapshot = observer.snapshot(
        maxEntries: 4,
        query: const CockpitNetworkQuery(
          method: 'POST',
          uriContains: '/sync',
          onlyFailures: true,
          statusCodeAtLeast: 500,
        ),
      );

      expect(snapshot.capturedEntryCount, 3);
      expect(snapshot.totalEntryCount, 1);
      expect(snapshot.failureCount, 1);
      expect(snapshot.query.onlyFailures, isTrue);
      expect(snapshot.entries.single.uri, contains('/sync/health'));
      expect(snapshot.endpointSummaries, hasLength(1));
      expect(snapshot.endpointSummaries.single.uriPattern, '/sync/health');
      expect(snapshot.endpointSummaries.single.failureCount, 1);
    },
  );

  test(
    'CockpitHttpNetworkObserver can wait until captured traffic goes idle',
    () async {
      final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
      observer.attachParentOverrides(HttpOverrides.current);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 90));
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      final requestFuture = HttpOverrides.runZoned(() async {
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/slow'),
        );
        final response = await request.close();
        await response.drain<void>();
        client.close(force: true);
      }, createHttpClient: observer.createHttpClient);

      final waitFuture = observer.waitForIdle(
        quietWindow: const Duration(milliseconds: 40),
        timeout: const Duration(seconds: 2),
      );

      await requestFuture;

      expect(await waitFuture, isTrue);
      expect(observer.snapshot(maxEntries: 2).inFlightCount, 0);
    },
  );

  test(
    'CockpitHttpNetworkObserver uses the injected tick handler while polling for idle',
    () async {
      var tickCount = 0;
      final releaseResponse = Completer<void>();
      final requestStarted = Completer<void>();
      final observer = CockpitHttpNetworkObserver(
        tickHandler: (duration) async {
          tickCount += 1;
          if (!releaseResponse.isCompleted) releaseResponse.complete();
          await Future<void>.delayed(Duration.zero);
        },
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requestStarted.complete();
        await releaseResponse.future;
        await request.response.close();
      });
      final requestFuture = HttpOverrides.runZoned(() async {
        final client = HttpClient();
        final response = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/tick'),
        )).close();
        await response.drain<void>();
        client.close(force: true);
      }, createHttpClient: observer.createHttpClient);
      await requestStarted.future;

      final didGoIdle = await observer.waitForIdle(
        quietWindow: Duration.zero,
        timeout: const Duration(milliseconds: 80),
      );
      await requestFuture;

      expect(didGoIdle, isTrue);
      expect(tickCount, greaterThan(0));
    },
  );

  test('records an unfinished SSE response as continuing', () async {
    final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
    final releaseResponse = Completer<void>();
    final firstChunk = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write('data: first\n\n');
      await request.response.flush();
      await releaseResponse.future;
      request.response.write('data: final\n\n');
      await request.response.close();
    });

    final requestFuture = HttpOverrides.runZoned(() async {
      final client = HttpClient();
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/events'),
      )).close();
      await response.listen((chunk) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      }).asFuture<void>();
      client.close(force: true);
    }, createHttpClient: observer.createHttpClient);
    await firstChunk.future;

    final active = observer.snapshot(maxEntries: 2).entries.single;
    expect(active.state, CockpitNetworkState.receiving);
    expect(active.isActive, isTrue);
    expect(active.responseBodyPreview, contains('data: first'));
    expect(active.responseBodyBytes, greaterThan(0));
    expect(observer.snapshot(maxEntries: 2).inFlightCount, 1);

    releaseResponse.complete();
    await requestFuture;
    final complete = observer.snapshot(maxEntries: 2).entries.single;
    expect(complete.state, CockpitNetworkState.complete);
    expect(complete.isActive, isFalse);
    expect(complete.responseBodyPreview, contains('data: final'));
  });

  test('records a consumer-cancelled SSE response as cancelled', () async {
    final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
    final releaseResponse = Completer<void>();
    final firstChunk = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write('data: first\n\n');
      await request.response.flush();
      await releaseResponse.future;
      try {
        await request.response.close();
      } on Object {
        // The client intentionally ended this response before the server.
      }
    });

    await HttpOverrides.runZoned(() async {
      final client = HttpClient();
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/events'),
      )).close();
      late final StreamSubscription<List<int>> subscription;
      subscription = response.listen((chunk) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      });
      await firstChunk.future;
      await subscription.cancel();
      client.close(force: true);
    }, createHttpClient: observer.createHttpClient);

    final cancelled = observer.snapshot(maxEntries: 2).entries.single;
    expect(cancelled.state, CockpitNetworkState.cancelled);
    expect(cancelled.isActive, isFalse);
    expect(cancelled.responseBodyPreview, contains('data: first'));
    expect(observer.snapshot(maxEntries: 2).inFlightCount, 0);
    releaseResponse.complete();
  });

  test('records WebSocket connection and frame activity', () async {
    final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
    final clientMessage = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.add('server hello');
      socket.listen((message) {
        if (message == 'client hello' && !clientMessage.isCompleted) {
          clientMessage.complete();
        }
      });
    });

    await HttpOverrides.runZoned(() async {
      final client = observer.createHttpClient(null);
      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/socket',
        compression: CompressionOptions.compressionOff,
        customClient: client,
      );
      final serverMessage = Completer<void>();
      final socketClosed = Completer<void>();
      socket.listen((message) {
        if (message == 'server hello' && !serverMessage.isCompleted) {
          serverMessage.complete();
        }
      }, onDone: socketClosed.complete);
      socket.add('client hello');
      await Future.wait(<Future<void>>[
        serverMessage.future,
        clientMessage.future,
      ]);

      final active = observer.snapshot(maxEntries: 2).entries.single;
      expect(active.protocol, CockpitNetworkProtocol.webSocket);
      expect(active.state, CockpitNetworkState.open);
      expect(active.statusCode, HttpStatus.switchingProtocols);
      expect(active.webSocket?.sentFrames, greaterThanOrEqualTo(1));
      expect(active.webSocket?.receivedFrames, greaterThanOrEqualTo(1));
      expect(
        active.webSocket?.recentFrames.map((frame) => frame.preview),
        containsAll(<String?>['client hello', 'server hello']),
      );

      await socket.close();
      await socketClosed.future;
      client.close(force: true);
    }, createHttpClient: observer.createHttpClient);

    final closed = observer.snapshot(maxEntries: 2).entries.single;
    expect(closed.state, CockpitNetworkState.closed);
    expect(closed.isActive, isFalse);
  });

  test(
    'CockpitHttpNetworkObserver records connection failures raised before a request is returned',
    () async {
      final observer = CockpitHttpNetworkObserver(maxRetainedEntries: 10);
      observer.attachParentOverrides(_ThrowingHttpOverrides());

      final client = observer.createHttpClient(null);

      await expectLater(
        client.getUrl(Uri.parse('http://127.0.0.1:63341/sync/health')),
        throwsA(isA<SocketException>()),
      );

      final snapshot = observer.snapshot(maxEntries: 5);
      expect(snapshot.totalEntryCount, 1);
      expect(snapshot.failureCount, 1);
      expect(snapshot.entries.single.method, 'GET');
      expect(snapshot.entries.single.uri, contains('/sync/health'));
      expect(snapshot.entries.single.error, contains('Connection failed'));
      expect(snapshot.inFlightCount, 0);
    },
  );
}

String? _header(Map<String, String> headers, String name) => headers.entries
    .where((entry) => entry.key.toLowerCase() == name.toLowerCase())
    .firstOrNull
    ?.value;

final class _ThrowingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _ThrowingHttpClient();
  }
}

final class _ThrowingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    throw SocketException(
      'Connection failed',
      address: InternetAddress('127.0.0.1'),
      port: 63341,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
