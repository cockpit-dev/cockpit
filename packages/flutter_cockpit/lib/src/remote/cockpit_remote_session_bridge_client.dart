import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'cockpit_remote_bridge_protocol.dart';
import 'cockpit_remote_session_configuration.dart';

typedef CockpitRemoteBridgeChannelConnector =
    WebSocketChannel Function(Uri uri);

final class CockpitRemoteSessionBridgeClient {
  CockpitRemoteSessionBridgeClient({
    required CockpitRemoteSessionConfiguration configuration,
    required CockpitRemoteSessionBridgeProtocol protocol,
    Duration reconnectDelay = const Duration(seconds: 1),
    Future<void> Function(Duration duration)? delay,
    CockpitRemoteBridgeChannelConnector? channelConnector,
  }) : _configuration = configuration,
       _protocol = protocol,
       _reconnectDelay = reconnectDelay,
       _delay = delay ?? Future<void>.delayed,
       _channelConnector = channelConnector ?? WebSocketChannel.connect;

  final CockpitRemoteSessionConfiguration _configuration;
  final CockpitRemoteSessionBridgeProtocol _protocol;
  final Duration _reconnectDelay;
  final Future<void> Function(Duration duration) _delay;
  final CockpitRemoteBridgeChannelConnector _channelConnector;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  bool _started = false;
  bool _closing = false;
  bool _reconnectPending = false;

  Uri get publicBaseUri => _configuration.baseUri;

  Future<void> start() async {
    if (_started || _closing) {
      return;
    }
    _started = true;
    _openChannel();
  }

  Future<void> close() async {
    _closing = true;
    _reconnectPending = false;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }

  void _openChannel() {
    if (_closing) {
      return;
    }
    final channel = _channelConnector(_connectUri());
    _channel = channel;
    unawaited(
      channel.ready.catchError((Object error, StackTrace stackTrace) async {
        await _handleChannelFailure(channel);
      }),
    );
    _subscription = channel.stream.listen(
      (message) {
        unawaited(_handleMessage(channel, message));
      },
      onError: (_) {
        unawaited(_handleChannelFailure(channel));
      },
      onDone: () {
        unawaited(_handleChannelFailure(channel));
      },
      cancelOnError: true,
    );
  }

  Future<void> _handleMessage(
    WebSocketChannel originChannel,
    Object? message,
  ) async {
    if (!identical(_channel, originChannel) || message == null) {
      return;
    }
    final response = await _protocol.handleRawMessage('$message');
    if (identical(_channel, originChannel)) {
      originChannel.sink.add(response);
    }
  }

  Future<void> _handleChannelFailure(WebSocketChannel channel) async {
    if (!identical(_channel, channel)) {
      return;
    }
    await _scheduleReconnect();
  }

  Future<void> _scheduleReconnect() async {
    if (_closing || _reconnectPending) {
      return;
    }
    _reconnectPending = true;
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _channel?.sink.close();
      _channel = null;
      await _delay(_reconnectDelay);
      if (!_closing) {
        _openChannel();
      }
    } finally {
      _reconnectPending = false;
    }
  }

  Uri _connectUri() {
    final baseUri = _configuration.baseUri;
    final normalizedRoutePrefix = _configuration.normalizedRoutePrefix;
    final path = normalizedRoutePrefix.isEmpty
        ? '/connect'
        : '$normalizedRoutePrefix/connect';
    // Browsers cannot attach headers to a WebSocket upgrade, so the token is
    // confined to this handshake query; the configuration's URI stays clean.
    return baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: path,
      queryParameters: _configuration.password.isEmpty
          ? null
          : <String, String>{'token': _configuration.password},
    );
  }
}
