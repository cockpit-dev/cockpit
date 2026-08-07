/// The JSON-RPC connection engine.
///
/// [Connection] correlates outgoing requests with incoming responses by `id`,
/// dispatches incoming requests/notifications to registered handlers, supports
/// cooperative cancellation via `$/cancel_request`, and exposes typed
/// request/notification helpers. It is transport-agnostic: it reads from a
/// [Transport]'s [Stream] and writes messages back through it.
library;

import 'dart:async';
import 'dart:convert';
import '../transport/transport.dart';
import 'message.dart';

/// The JSON-RPC protocol-level cancel-request notification method.
const kCancelRequestMethod = r'$/cancel_request';

/// A handler for an incoming JSON-RPC request.
///
/// Returns the response result, or throws to produce an error response.
typedef RequestHandler = FutureOr<Object?> Function(Object? params);

/// A handler for an incoming JSON-RPC notification.
typedef NotificationHandler = FutureOr<void> Function(Object? params);

/// Cancellation signal for an inbound JSON-RPC request.
///
/// Handlers that can stop cooperatively should await [whenCancelled] or check
/// [isCancelled] between units of work. The handler's reply is always
/// delivered to the original request — its result, or a thrown [RpcError] such
/// as one built from [ErrorCode.requestCancelled] — because the ACP contract
/// guarantees the requesting side a response; cancellation never suppresses it.
final class RequestCancellation {
  RequestCancellation._();

  final Completer<void> _completer = Completer<void>();

  /// Whether the peer cancelled the request.
  bool get isCancelled => _completer.isCompleted;

  /// Completes when the peer cancels the request.
  Future<void> get whenCancelled => _completer.future;

  void _cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// A handler for an inbound request that observes peer cancellation.
typedef CancellableRequestHandler = FutureOr<Object?> Function(
  Object? params,
  RequestCancellation cancellation,
);

/// The result of registering a handler — call [dispose] to remove it.
abstract interface class HandlerRegistration {
  /// Removes this handler registration.
  void dispose();
}

/// A pending outbound request awaiting a peer response.
class _Pending {
  _Pending(this.completer, this.timer);
  final Completer<Object?> completer;
  final Timer? timer;
}

final class _ActiveRequest {
  _ActiveRequest() : cancellation = RequestCancellation._();

  final RequestCancellation cancellation;
}

/// A JSON-RPC 2.0 connection.
///
/// Drives a [Transport]: reads incoming messages, dispatches them, and sends
/// outgoing messages. Use [sendRequest] for request/response, [notify] for
/// fire-and-forget, and [onRequest]/[onNotification] to handle inbound traffic.
class Connection {
  Connection(this._transport) {
    _subscription = _transport.incoming.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
    );
    // A recoverable transport separates malformed-line outcomes from valid
    // incoming messages and fatal I/O errors. Subscribe so protocol violations
    // receive JSON-RPC error responses without tearing down the connection.
    final recoverable = _transport;
    if (recoverable is RecoverableTransport) {
      _decodeSub = recoverable.decodeOutcomes.listen(
        _handleDecodeOutcome,
        onError: _handleError,
        onDone: _handleDone,
      );
    }
    // Register the built-in cancel-request notification handler.
    onNotification(kCancelRequestMethod, _handleCancelRequest);
  }

  final Transport _transport;
  late final StreamSubscription<RpcMessage> _subscription;
  StreamSubscription<DecodedLine>? _decodeSub;

  int _nextId = 0;
  final Map<Object, _Pending> _pending = {};
  final Map<String, CancellableRequestHandler> _requestHandlers = {};
  final Map<Object?, _ActiveRequest> _activeRequests = {};
  final Map<String, List<NotificationHandler>> _notificationHandlers = {};
  final Set<NotificationHandler> _anyNotificationHandlers = {};
  bool _closed = false;
  final _closeController = StreamController<void>.broadcast();

  /// Whether the connection has been closed.
  bool get isClosed => _closed;

  /// A broadcast stream that emits once when the connection closes.
  Stream<void> get onClose => _closeController.stream;

  /// Sends a request and awaits the typed result.
  ///
  /// [mapResult] decodes the raw result map into [T]. Throws [RpcError] if the
  /// peer returns an error.
  Future<T> sendRequest<T>(
    String method, {
    Object? params,
    required T Function(Object? result) mapResult,
    Duration? timeout,
  }) {
    if (_closed) {
      throw StateError('Connection is closed');
    }
    final id = ++_nextId;
    final completer = Completer<Object?>();
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        // Atomically claim the pending request. A null result means a peer
        // response, an explicit cancel, or connection close already claimed
        // it — bail out to avoid double-completion and to ignore any late
        // response.
        if (_pending.remove(id) == null) return;
        // Best-effort: ask the peer to abandon the request before failing
        // locally. Transport errors here must not mask the timeout.
        _notifyCancellation(id);
        completer.completeError(
          TimeoutException('Request "$method" timed out', timeout),
        );
      });
    }
    _pending[id] = _Pending(completer, timer);
    try {
      _transport.send(RpcRequest(id: id, method: method, params: params));
    } catch (_) {
      // The transport rejected the send (e.g. it was closed independently of
      // this Connection). Remove the pending entry so it cannot leak or, when a
      // timeout is set, later complete an unawaited completer. Re-throw to keep
      // the synchronous-failure contract of an explicit caller send.
      _pending.remove(id);
      timer?.cancel();
      rethrow;
    }
    return completer.future.then(mapResult);
  }

  /// Sends a notification (no response expected).
  void notify(String method, {Object? params}) {
    if (_closed) {
      throw StateError('Connection is closed');
    }
    _transport.send(RpcNotification(method: method, params: params));
  }

  /// Registers a handler for an incoming request method.
  ///
  /// If a handler is already registered for [method], it is replaced. Call
  /// [HandlerRegistration.dispose] to remove it.
  HandlerRegistration onRequest(String method, RequestHandler handler) {
    return onCancellableRequest(method, (params, _) => handler(params));
  }

  /// Registers a handler that can observe cancellation from the peer.
  HandlerRegistration onCancellableRequest(
    String method,
    CancellableRequestHandler handler,
  ) {
    _requestHandlers[method] = handler;
    return _Registration(() {
      if (identical(_requestHandlers[method], handler)) {
        _requestHandlers.remove(method);
      }
    });
  }

  /// Registers a handler for an incoming notification method.
  ///
  /// Multiple handlers may be registered for the same method.
  HandlerRegistration onNotification(
      String method, NotificationHandler handler) {
    _notificationHandlers.putIfAbsent(method, () => []).add(handler);
    return _Registration(() {
      final list = _notificationHandlers[method];
      list?.remove(handler);
      if (list != null && list.isEmpty) _notificationHandlers.remove(method);
    });
  }

  /// Registers a catch-all handler invoked for every notification regardless
  /// of method.
  HandlerRegistration onAnyNotification(NotificationHandler handler) {
    _anyNotificationHandlers.add(handler);
    return _Registration(() => _anyNotificationHandlers.remove(handler));
  }

  /// Cancels an outbound request by its in-flight id, sending `$/cancel_request`.
  void cancelRequest(Object id) {
    notify(kCancelRequestMethod, params: {'requestId': id});
    final pending = _pending.remove(id);
    pending?.timer?.cancel();
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(
        RpcError.fromCode(ErrorCode.requestCancelled),
      );
    }
  }

  /// Best-effort `$/cancel_request` notification for [requestId].
  ///
  /// Used on the outbound request-timeout path. Transport or
  /// closed-connection errors are swallowed because the request is already
  /// failing locally, so signalling the peer must not be allowed to mask the
  /// failure. Explicit caller cancellation ([cancelRequest]) still goes through
  /// [notify] so it surfaces a closed connection to the caller.
  void _notifyCancellation(Object requestId) {
    try {
      _transport.send(
        RpcNotification(
          method: kCancelRequestMethod,
          params: {'requestId': requestId},
        ),
      );
    } catch (_) {
      // Best-effort: the request is already failing locally.
    }
  }

  /// Sends [message] best-effort on the internally-generated reply path.
  ///
  /// Replies to inbound requests (and other connection-originated messages that
  /// are not explicit caller sends) must never surface an unhandled
  /// asynchronous error when the transport is closing or rejecting writes: the
  /// peer learns of disconnection through the transport, and a reply that
  /// cannot be delivered is not actionable. This mirrors the established
  /// best-effort semantics of [_notifyCancellation]. Explicit caller sends
  /// ([sendRequest]/[notify]) still propagate transport errors to the caller.
  void _safeSend(RpcMessage message) {
    if (_closed) return;
    try {
      _transport.send(message);
    } catch (_) {
      // Best-effort: transport failure is reported via close().
    }
  }

  /// Closes the connection, rejecting all pending requests.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final error = StateError('Connection closed');
    for (final entry in _pending.entries) {
      entry.value.timer?.cancel();
      if (!entry.value.completer.isCompleted) {
        entry.value.completer.completeError(error);
      }
    }
    _pending.clear();
    for (final active in _activeRequests.values) {
      active.cancellation._cancel();
    }
    _activeRequests.clear();
    _closeController.add(null);
    await _closeController.close();
    await _subscription.cancel();
    await _decodeSub?.cancel();
    await _transport.close();
  }

  void _handleMessage(RpcMessage message) {
    switch (message) {
      case RpcRequest():
        _handleRequest(message);
      case RpcNotification():
        _handleNotification(message);
      case RpcResponse():
        _handleResponse(message);
    }
  }

  /// Handles a malformed-line outcome from a [RecoverableTransport].
  ///
  /// A recoverable failure is answered with a JSON-RPC error response —
  /// parse-error (-32700) for invalid JSON, invalid-request (-32600) for a bad
  /// envelope — without tearing down the connection, so unrelated valid
  /// traffic survives. A response-only shape is silently dropped because it
  /// cannot be correlated to a request. When a request id can be recovered it
  /// is echoed; otherwise the response carries `id: null`, matching the
  /// ACP/rust-sdk uncorrelated-error path.
  void _handleDecodeOutcome(DecodedLine outcome) {
    // The interface emits failures only. Ignore a non-conforming message event
    // defensively; valid messages already arrive on Transport.incoming.
    if (outcome.isMessage) return;
    final failure = outcome.failure;
    if (failure == null) return;
    if (outcome.responseOnlyShape) return; // silently drop stray-response shape
    _safeSend(
      RpcResponse(
        id: outcome.recoverableId,
        error: failure,
      ),
    );
  }

  Future<void> _handleRequest(RpcRequest request) async {
    final handler = _requestHandlers[request.method];
    if (handler == null) {
      _safeSend(
        RpcResponse(
          id: request.id,
          error: RpcError.fromCode(
            ErrorCode.methodNotFound,
            data: {'method': request.method},
          ),
        ),
      );
      return;
    }

    if (_activeRequests.containsKey(request.id)) {
      _safeSend(
        RpcResponse(
          id: request.id,
          error: RpcError.fromCode(
            ErrorCode.invalidRequest,
            data: {'reason': 'Request id is already active.'},
          ),
        ),
      );
      return;
    }

    final active = _ActiveRequest();
    _activeRequests[request.id] = active;
    try {
      final result = await handler(request.params, active.cancellation);
      if (!_takeActiveRequest(request.id, active)) return;
      _safeSend(
        RpcResponse(
          id: request.id,
          result: result ?? const <String, Object?>{},
        ),
      );
    } on RpcError catch (error) {
      if (!_takeActiveRequest(request.id, active)) return;
      _safeSend(RpcResponse(id: request.id, error: error));
    } catch (error) {
      if (!_takeActiveRequest(request.id, active)) return;
      _safeSend(
        RpcResponse(
          id: request.id,
          error: RpcError(
            code: ErrorCode.internalError.code,
            message: error.toString(),
          ),
        ),
      );
    }
  }

  bool _takeActiveRequest(Object? id, _ActiveRequest active) {
    // Atomically claim the active-request entry. Returns false (suppressing the
    // reply) only when the entry is already gone — i.e. [close] cleared the
    // table while the handler was in flight. Cancellation does NOT suppress the
    // reply: the ACP contract requires the requesting side to always receive a
    // response to the original request, so a handler that observed cancellation
    // still answers with its result or a requestCancelled error.
    if (!identical(_activeRequests[id], active)) return false;
    _activeRequests.remove(id);
    return true;
  }

  Future<void> _handleNotification(RpcNotification notification) async {
    final methodHandlers = _notificationHandlers[notification.method];
    if (methodHandlers != null) {
      for (final h in methodHandlers.toList()) {
        try {
          await h(notification.params);
        } catch (_) {
          // Notifications must not produce error responses; swallow.
        }
      }
    }
    for (final h in _anyNotificationHandlers.toList()) {
      try {
        await h(notification.params);
      } catch (_) {}
    }
  }

  void _handleResponse(RpcResponse response) {
    final pending = _pending.remove(response.id);
    if (pending == null) return;
    pending.timer?.cancel();
    if (response.isError) {
      pending.completer.completeError(response.error!);
    } else {
      pending.completer.complete(response.result);
    }
  }

  void _handleCancelRequest(Object? params) {
    if (params is! Map) return;
    final requestId = params['requestId'];
    final active = _activeRequests[requestId];
    if (active == null) return;
    // Cooperative cancellation only. `$/cancel_request` is a JSON-RPC
    // notification and must never receive a reply: the ACP spec mandates that
    // malformed, unknown, or already-completed requestIds are "ignored without
    // a reply, like any other malformed notification". The handler's own
    // completion delivers the response to the *original* request (its result,
    // or a requestCancelled error); signalling here is what lets a cooperative
    // handler stop and produce that response. The entry is intentionally left
    // in place so the handler's [_takeActiveRequest] owns its removal and a
    // reused id stays rejected until the in-flight handler finishes.
    active.cancellation._cancel();
  }

  void _handleError(Object error, StackTrace stack) {
    // Transport-level errors close the connection.
    _closeFromTransport();
  }

  void _handleDone() {
    _closeFromTransport();
  }

  /// Closes the connection in response to transport done/error.
  ///
  /// [Connection.close] is awaited through a guard so cleanup failures — e.g.
  /// a transport that rejects `close()` while already failing — do not surface
  /// as unhandled asynchronous errors on this fire-and-forget path. Callers
  /// that invoke [close] directly still observe its errors.
  Future<void> _closeFromTransport() async {
    try {
      await close();
    } catch (_) {
      // The transport already signalled done/error; ignore cleanup failures.
    }
  }
}

class _Registration implements HandlerRegistration {
  _Registration(this._remove);
  final void Function() _remove;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _remove();
  }
}

/// Encodes a JSON-RPC message to a newline-delimited JSON line.
String encodeMessage(RpcMessage message) => message.toLine();

/// Decodes a JSON line into a JSON-RPC message.
RpcMessage decodeMessage(String line) => RpcMessage.fromJson(jsonDecode(line));
