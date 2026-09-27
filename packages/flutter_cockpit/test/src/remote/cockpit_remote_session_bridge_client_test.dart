import 'dart:async';

import 'package:flutter_cockpit/src/remote/cockpit_remote_bridge_protocol.dart';
import 'package:flutter_cockpit/src/remote/cockpit_remote_session_bridge_client.dart';
import 'package:flutter_cockpit/src/remote/cockpit_remote_session_configuration.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test(
    'bridge client retries when the browser channel ready future fails',
    () async {
      final firstChannel = _FakeWebSocketChannel(
        ready: Future<void>.error(StateError('connect failed')),
      );
      final secondChannel = _FakeWebSocketChannel(ready: Future<void>.value());
      final createdChannels = <_FakeWebSocketChannel>[];

      final client = CockpitRemoteSessionBridgeClient(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          host: '127.0.0.1',
          port: 59331,
          routePrefix: '/cockpit',
        ),
        protocol: CockpitRemoteSessionBridgeProtocol(
          requestHandler: (_) async {
            throw UnimplementedError();
          },
        ),
        reconnectDelay: Duration.zero,
        delay: (_) async {},
        channelConnector: (_) {
          final channel = createdChannels.isEmpty
              ? firstChannel
              : secondChannel;
          createdChannels.add(channel);
          return channel;
        },
      );
      addTearDown(client.close);

      await client.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(createdChannels, hasLength(2));
      expect(client.publicBaseUri.toString(), 'http://127.0.0.1:59331/cockpit');
      expect(secondChannel.closeCount, 0);
    },
  );

  test(
    'bridge client authenticates the handshake query only when a token exists',
    () async {
      final connectedUris = <Uri>[];
      final buildClient = _buildRecordingClient(connectedUris);

      final unauthenticated = buildClient(password: '');
      await unauthenticated.start();
      expect(connectedUris.single.queryParameters, isEmpty);

      connectedUris.clear();
      final authenticated = buildClient(password: 'bridge-secret');
      await authenticated.start();
      expect(connectedUris.single.queryParameters['token'], 'bridge-secret');
      expect(authenticated.publicBaseUri.hasQuery, isFalse);
    },
  );
}

_CockpitRemoteSessionBridgeClientFactory _buildRecordingClient(
  List<Uri> connectedUris,
) {
  return ({required String password}) {
    final client = CockpitRemoteSessionBridgeClient(
      configuration: CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        host: '127.0.0.1',
        port: 59331,
        routePrefix: '/cockpit',
        password: password,
      ),
      protocol: CockpitRemoteSessionBridgeProtocol(
        requestHandler: (_) async {
          throw UnimplementedError();
        },
      ),
      channelConnector: (uri) {
        connectedUris.add(uri);
        return _FakeWebSocketChannel(ready: Future<void>.value());
      },
    );
    return client;
  };
}

typedef _CockpitRemoteSessionBridgeClientFactory =
    CockpitRemoteSessionBridgeClient Function({required String password});

final class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel({required this.ready});

  final StreamController<Object?> _controller = StreamController<Object?>();
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  @override
  final Future<void> ready;

  int closeCount = 0;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Stream<Object?> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> close() async {
    closeCount += 1;
    await _controller.close();
    await _sink.close();
  }
}

final class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink();

  final List<Object?> sentMessages = <Object?>[];
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Future<void> addStream(Stream stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  void add(Object? data) {
    sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }

  @override
  Future<void> get done => _doneCompleter.future;
}
