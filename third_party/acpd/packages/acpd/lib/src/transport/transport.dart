/// Transport abstraction for ACP connections.
///
/// A [Transport] is the bidirectional channel a [Connection] reads from and
/// writes to. The core package defines only the interface; concrete
/// implementations (stdio, HTTP/SSE, in-memory) live in companion packages.
library;

import '../jsonrpc/message.dart';

/// A bidirectional JSON-RPC transport channel.
///
/// Implementations provide:
/// - [incoming]: a stream of decoded JSON-RPC messages from the peer.
/// - [send]: sends a message to the peer.
/// - [close]: terminates the channel, releasing resources.
abstract interface class Transport {
  /// The stream of messages received from the peer.
  Stream<RpcMessage> get incoming;

  /// Sends a message to the peer.
  void send(RpcMessage message);

  /// Closes the transport, completing [incoming] and rejecting pending sends.
  Future<void> close();
}

/// A transport that exchanges raw JSON lines (newline-delimited JSON).
///
/// Most ACP transports (stdio, HTTP/SSE) carry newline-delimited JSON. This
/// interface lets a codec layer sit between raw bytes and [Transport] without
/// forcing every implementation to re-derive the framing.
abstract interface class LineTransport implements Transport {}

/// A [Transport] that reports malformed JSON-RPC lines without closing.
///
/// A normal [Transport] reports a line that fails to decode as an [incoming]
/// stream error, which a [Connection] must treat as fatal because the channel
/// may be unreliable. A [RecoverableTransport] keeps [incoming] unchanged for
/// valid messages and transport I/O errors, while exposing recoverable
/// protocol violations separately on [decodeOutcomes]. The [Connection] can
/// answer those violations with JSON-RPC error responses without tearing down.
///
/// Transports that cannot decode line-by-line (for example, an in-memory pair
/// that exchanges pre-built [RpcMessage] objects) do not implement this
/// additive interface and retain the legacy fatal-error semantics.
abstract interface class RecoverableTransport implements Transport {
  /// Recoverable per-line decode failures not emitted on [incoming].
  ///
  /// Every event has [DecodedLine.isFailure] set. Implementations must continue
  /// to report real transport I/O errors on [incoming]'s error channel.
  Stream<DecodedLine> get decodeOutcomes;
}
