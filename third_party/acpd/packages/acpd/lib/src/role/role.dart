/// Role layer: typed [AgentRole] and [ClientRole] builders over [Connection].
///
/// The role layer binds the generic JSON-RPC [Connection] to the typed ACP
/// schema. An [AgentRole] registers agent-side request handlers
/// (initialize, session/new, session/prompt, …) and exposes an [AgentContext]
/// for calling client-side methods. A [ClientRole] is the mirror image, with a
/// [ClientContext] for calling agent-side methods.
///
/// Handlers receive typed parameter objects plus the matching context, so they
/// can both answer the request and call back into the peer.
library;

import 'dart:async';
import '../jsonrpc/connection.dart';
import '../transport/transport.dart';
import 'agent_context.dart';
import 'client_context.dart';

export 'agent_context.dart';
export 'client_context.dart';

/// A connection that stays open independently of a single prompt turn.
abstract interface class AcpConnection {
  /// Completes when the connection closes.
  Future<void> get closed;

  /// The underlying JSON-RPC connection.
  Connection get connection;

  /// Closes the connection.
  Future<void> close();
}

/// A running agent connection — use [agent] to call client-side methods.
class AgentConnection implements AcpConnection {
  AgentConnection(this._conn);
  final Connection _conn;

  /// Context for calling client-side ACP methods.
  late final AgentContext agent = AgentContext(_conn);

  @override
  Connection get connection => _conn;

  @override
  Future<void> get closed =>
      _conn.isClosed ? Future<void>.value() : _conn.onClose.first;

  @override
  Future<void> close() => _conn.close();
}

/// A running client connection — use [client] to call agent-side methods.
class ClientConnection implements AcpConnection {
  ClientConnection(this._conn);
  final Connection _conn;

  /// Context for calling agent-side ACP methods.
  late final ClientContext client = ClientContext(_conn);

  @override
  Connection get connection => _conn;

  @override
  Future<void> get closed =>
      _conn.isClosed ? Future<void>.value() : _conn.onClose.first;

  @override
  Future<void> close() => _conn.close();
}

/// Handler signature for agent-side requests.
typedef AgentRequestHandler<P, R> = FutureOr<R> Function(
    AgentContext context, P params);

/// Handler signature for client-side notifications.
typedef ClientNotificationHandler<P> = FutureOr<void> Function(
    ClientContext context, P params);

/// Handler signature for client-side requests.
typedef ClientRequestHandler<P, R> = FutureOr<R> Function(
    ClientContext context, P params);

/// Builds an agent role: registers agent-side handlers and connects.
///
/// Handlers are keyed by JSON-RPC method name. Each receives the raw params
/// map (typed by the caller) and an [AgentContext] for callbacks. Use
/// [handle] for a raw-method entry, or the typed convenience methods.
class AgentRole {
  final Map<
      String,
      FutureOr<Object?> Function(
        AgentContext,
        Object?,
        RequestCancellation,
      )> _handlers = {};

  /// Registers a handler for a method, receiving raw params and context.
  AgentRole handle(
    String method,
    FutureOr<Object?> Function(Map<String, Object?> params, AgentContext ctx)
        handler,
  ) {
    _handlers[method] = (ctx, params, _) =>
        handler(params is Map<String, Object?> ? params : {}, ctx);
    return this;
  }

  /// Registers a handler that can observe peer cancellation.
  AgentRole handleCancellable(
    String method,
    FutureOr<Object?> Function(
      Map<String, Object?> params,
      AgentContext ctx,
      RequestCancellation cancellation,
    ) handler,
  ) {
    _handlers[method] = (ctx, params, cancellation) => handler(
          params is Map<String, Object?> ? params : {},
          ctx,
          cancellation,
        );
    return this;
  }

  /// Connects to a [Transport], returning an [AgentConnection].
  AgentConnection connect(Transport transport) {
    final conn = Connection(transport);
    final ctx = AgentContext(conn);
    for (final entry in _handlers.entries) {
      conn.onCancellableRequest(
        entry.key,
        (params, cancellation) => entry.value(ctx, params, cancellation),
      );
    }
    return AgentConnection(conn);
  }
}

/// Builds a client role: registers client-side handlers and connects.
class ClientRole {
  final Map<
      String,
      FutureOr<Object?> Function(
        ClientContext,
        Object?,
        RequestCancellation,
      )> _requestHandlers = {};
  final Map<String, FutureOr<void> Function(ClientContext, Object?)>
      _notifHandlers = {};

  /// Registers a request handler by method.
  ClientRole handleRequest(
    String method,
    FutureOr<Object?> Function(Map<String, Object?> params, ClientContext ctx)
        handler,
  ) {
    _requestHandlers[method] = (ctx, params, _) =>
        handler(params is Map<String, Object?> ? params : {}, ctx);
    return this;
  }

  /// Registers a request handler that can observe peer cancellation.
  ClientRole handleCancellableRequest(
    String method,
    FutureOr<Object?> Function(
      Map<String, Object?> params,
      ClientContext ctx,
      RequestCancellation cancellation,
    ) handler,
  ) {
    _requestHandlers[method] = (ctx, params, cancellation) => handler(
          params is Map<String, Object?> ? params : {},
          ctx,
          cancellation,
        );
    return this;
  }

  /// Registers a notification handler by method.
  ClientRole handleNotification(
    String method,
    FutureOr<void> Function(Map<String, Object?> params, ClientContext ctx)
        handler,
  ) {
    _notifHandlers[method] = (ctx, params) =>
        handler(params is Map<String, Object?> ? params : {}, ctx);
    return this;
  }

  /// Connects to a [Transport], returning a [ClientConnection].
  ClientConnection connect(Transport transport) {
    final conn = Connection(transport);
    final ctx = ClientContext(conn);
    for (final entry in _requestHandlers.entries) {
      conn.onCancellableRequest(
        entry.key,
        (params, cancellation) => entry.value(ctx, params, cancellation),
      );
    }
    for (final entry in _notifHandlers.entries) {
      conn.onNotification(entry.key, (params) => entry.value(ctx, params));
    }
    return ClientConnection(conn);
  }
}
