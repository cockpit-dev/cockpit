/// JSON-RPC 2.0 message envelope and error handling for ACP.
///
/// ACP uses standard JSON-RPC 2.0 with three message kinds: requests (with
/// `id`, expecting a response), notifications (no `id`, no response), and
/// responses (with `id`, carrying `result` or `error`). This module models
/// the wire envelope generically; typed schema types plug into it via
/// [Connection].
library;

import 'dart:convert';
import '../json_codec.dart';
import '../schema/enums.dart';

export '../schema/enums.dart' show ErrorCode;

/// A JSON-RPC 2.0 error.
///
/// Carries an integer [code], a human-readable [message], and optional
/// structured [data]. Standard codes are defined in [ErrorCode]; ACP-specific
/// codes occupy the -32000 to -32099 range.
class RpcError implements Exception {
  const RpcError({required this.code, required this.message, this.data});

  /// Constructs an error from a known [ErrorCode], appending optional [data].
  factory RpcError.fromCode(ErrorCode code, {Object? data}) =>
      RpcError(code: code.code, message: code.message, data: data);

  /// The integer error code.
  final int code;

  /// Human-readable error message.
  final String message;

  /// Optional structured error data.
  final Object? data;

  /// Serializes to the JSON-RPC `error` object.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'code': code,
      'message': message,
    };
    if (data != null) json['data'] = data;
    return json;
  }

  /// Deserializes a JSON-RPC `error` object.
  factory RpcError.fromJson(Map<String, Object?> json) {
    return RpcError(
      code: requireField<int>(json, 'code'),
      message: requireField<String>(json, 'message'),
      data: json['data'],
    );
  }

  @override
  String toString() => 'RpcError($code): $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RpcError &&
          code == other.code &&
          message == other.message &&
          data == other.data;

  @override
  int get hashCode => Object.hash(code, message, data);
}

/// A JSON-RPC 2.0 request identifier: string, integer, or null.
typedef RequestId = Object?;

/// A JSON-RPC 2.0 request message.
class RpcRequest extends RpcMessage {
  const RpcRequest({
    required this.id,
    required this.method,
    this.params,
  });

  /// The constant `"2.0"` version string.
  static const version = kJsonRpcVersion;

  /// The request identifier echoed by the response.
  final RequestId id;

  /// The method name.
  final String method;

  /// Optional method parameters.
  final Object? params;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'jsonrpc': version,
      'id': id,
      'method': method,
    };
    if (params != null) json['params'] = params;
    return json;
  }

  factory RpcRequest.fromJson(Map<String, Object?> json) {
    return RpcRequest(
      id: json['id'],
      method: requireField<String>(json, 'method'),
      params: json['params'],
    );
  }
}

/// A JSON-RPC 2.0 notification (no `id`, no response expected).
class RpcNotification extends RpcMessage {
  const RpcNotification({required this.method, this.params});

  static const version = kJsonRpcVersion;

  final String method;
  final Object? params;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'jsonrpc': version,
      'method': method,
    };
    if (params != null) json['params'] = params;
    return json;
  }

  factory RpcNotification.fromJson(Map<String, Object?> json) {
    return RpcNotification(
      method: requireField<String>(json, 'method'),
      params: json['params'],
    );
  }
}

class RpcResponse extends RpcMessage {
  /// Constructs a JSON-RPC response.
  ///
  /// A success response carries a [result]; an error response carries [error].
  /// The const assert guards against accidentally building a response with
  /// neither. To faithfully reproduce a wire `"result": null` (a valid, if
  /// unusual, JSON-RPC success) use [withExplicitNullResult] or the
  /// [_deserialize] constructor reached by [fromJson].
  const RpcResponse({required this.id, this.result, this.error})
      : assert(error != null || result != null,
            'response must have result or error');

  /// A response that explicitly carries `"result": null`.
  ///
  /// This mirrors a peer that wrote `{"jsonrpc":"2.0","id":..,"result":null}`.
  /// It is only constructible here (not via the const constructor, whose
  /// assert would reject a bare `result: null`) so deserialization can round-
  /// trip an explicit null distinct from an omitted field.
  const RpcResponse.withExplicitNullResult({required this.id})
      : result = null,
        error = null;

  static const version = kJsonRpcVersion;

  /// The request identifier this response resolves.
  final RequestId id;

  /// The successful result.
  ///
  /// `null` means the peer wrote `"result": null` (see
  /// [withExplicitNullResult]) OR this is an error response ([error] is set).
  /// Distinguish with [isError].
  final Object? result;

  /// The error (null when this is a success response).
  final RpcError? error;

  /// Whether this response carries an error.
  bool get isError => error != null;

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'jsonrpc': version,
      'id': id,
    };
    if (error != null) {
      json['error'] = error!.toJson();
    } else {
      // Serialize the result verbatim. A null result is valid JSON-RPC
      // (`"result": null`) and is preserved exactly. Callers that build a
      // response without an explicit result still pass a non-null value (the
      // Connection layer defaults to `{}`), so this path only emits literal
      // null for withExplicitNullResult / deserialized null results.
      json['result'] = result;
    }
    return json;
  }

  const RpcResponse._deserialize({required this.id, this.result, this.error});

  factory RpcResponse.fromJson(Map<String, Object?> json) {
    final hasResult = json.containsKey('result');
    final hasError = json.containsKey('error');
    if (hasResult && hasError) {
      throw FormatException(
        'JSON-RPC response must not have both result and error: $json',
      );
    }
    if (!hasResult && !hasError) {
      throw FormatException(
        'JSON-RPC response must have result or error: $json',
      );
    }
    final errorRaw = json['error'];
    if (hasError && errorRaw is! Map) {
      throw FormatException('JSON-RPC response error must be an object: $json');
    }
    return RpcResponse._deserialize(
      id: json['id'],
      result: json['result'],
      error: hasError ? RpcError.fromJson(asJsonObject(errorRaw)) : null,
    );
  }
}

/// A discriminated union over all JSON-RPC message kinds.
sealed class RpcMessage {
  const RpcMessage();

  /// Parses any JSON-RPC message from a decoded JSON object.
  ///
  /// Enforces the JSON-RPC 2.0 envelope invariants: the `jsonrpc` member must
  /// equal `"2.0"`, `method` (when present) must be a string, `id` must be a
  /// string, integer, or `null` (booleans, fractional numbers, arrays, and
  /// objects are rejected), and `params` must be an array, object, or omitted.
  /// Throws [FormatException] for any envelope violation.
  static RpcMessage fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('Not a JSON-RPC message: $json');
    }
    final map = asJsonObject(json);
    final version = map['jsonrpc'];
    if (version != kJsonRpcVersion) {
      throw FormatException(
          'JSON-RPC version must be "$kJsonRpcVersion": $json');
    }
    final hasId = map.containsKey('id');
    final hasMethod = map.containsKey('method');
    if (hasId) {
      _validateId(map['id']);
    }
    if (hasMethod) {
      final method = map['method'];
      if (method is! String) {
        throw FormatException('JSON-RPC method must be a string: $json');
      }
      if (map.containsKey('params')) {
        _validateParams(map['params']);
      }
    }
    if (hasMethod && hasId) {
      return RpcRequest.fromJson(map);
    } else if (hasMethod) {
      return RpcNotification.fromJson(map);
    } else if (hasId) {
      return RpcResponse.fromJson(map);
    }
    throw FormatException('Unrecognized JSON-RPC message shape: $json');
  }

  /// Serializes the message to a JSON map.
  Map<String, Object?> toJson();

  /// Serializes to a newline-delimited JSON string.
  String toLine() => '${jsonEncode(toJson())}\n';
}

/// Validates a JSON-RPC 2.0 request `id`.
///
/// Per the spec, an id must be a string, integer, or null. Booleans, fractional
/// numbers, arrays, and objects are invalid.
void _validateId(Object? id) {
  if (id == null || id is String || id is int) return;
  throw FormatException('JSON-RPC id must be a string, integer, or null: $id');
}

/// Validates a JSON-RPC 2.0 `params` member.
///
/// Params must be an array or object when present.
void _validateParams(Object? params) {
  if (params == null || params is List || params is Map) return;
  throw FormatException('JSON-RPC params must be an array or object: $params');
}

/// The outcome of decoding one newline-delimited line.
///
/// Recoverable transports (see [RecoverableTransport]) produce a [DecodedLine]
/// per complete line instead of throwing on the stream, so the [Connection] can
/// answer protocol violations with a JSON-RPC error response without tearing
/// down. A line is either a valid [message] or a recoverable [failure]; never
/// both.
final class DecodedLine {
  DecodedLine.message(RpcMessage this.message)
      : failure = null,
        recoverableId = null,
        responseOnlyShape = false;

  /// A recoverable decode failure carrying [failure] and optional metadata.
  ///
  /// Public so transport codecs (e.g. [LineBufferedCodec]) can construct
  /// framing-level failures such as over-length or malformed-UTF-8 lines.
  const DecodedLine.failure(
    this.failure, {
    this.recoverableId,
    this.responseOnlyShape = false,
  }) : message = null;

  /// The decoded message, when the line was a valid JSON-RPC message.
  final RpcMessage? message;

  /// The protocol error, when the line was malformed.
  ///
  /// [ErrorCode.parseError] (-32700) means the line was not valid JSON;
  /// [ErrorCode.invalidRequest] (-32600) means the JSON parsed but was not a
  /// valid JSON-RPC envelope.
  final RpcError? failure;

  /// Whether this line is a valid JSON-RPC *value* that is a bare response
  /// shape (an object carrying `result` or `error` but no `method`).
  ///
  /// Per the ACP/rust-sdk contract, a malformed line of this shape gets no
  /// error reply: it looks like a response the peer intended for someone else
  /// (or garbage we cannot correlate to a request), so replying would only
  /// generate noise. Only set (and meaningful) when [failure] is non-null.
  final bool responseOnlyShape;

  /// A request id recovered from a malformed request-shaped envelope, when one
  /// is present and valid (a string, integer, or null).
  ///
  /// When set, the [Connection] echoes it in the error response instead of
  /// falling back to `id: null`. Only meaningful when [failure] is non-null
  /// and [responseOnlyShape] is false.
  final Object? recoverableId;

  /// Whether this line decoded to a valid message.
  bool get isMessage => message != null;

  /// Whether this line is a recoverable failure.
  bool get isFailure => failure != null;
}

/// Decodes one newline-delimited line into a [DecodedLine].
///
/// This is the recoverable counterpart of [decodeMessage]: it never throws.
/// Invalid JSON yields a [DecodedLine] whose [DecodedLine.failure] is a
/// [ErrorCode.parseError]; valid JSON with an invalid JSON-RPC envelope yields
/// [ErrorCode.invalidRequest]. The recoverable id and response-only-shape
/// flags are populated so a [Connection] can answer correctly per the ACP
/// contract.
DecodedLine decodeLine(String line) {
  Object? value;
  try {
    value = jsonDecode(line);
  } catch (e) {
    return DecodedLine.failure(
      RpcError.fromCode(ErrorCode.parseError, data: {'line': line}),
    );
  }
  try {
    return DecodedLine.message(RpcMessage.fromJson(value));
  } on FormatException {
    // Not a valid JSON-RPC envelope. Classify the shape so the connection can
    // decide whether and how to reply, mirroring rust-sdk's frame_entries.
    final obj = value is Map ? asJsonObject(value) : null;
    if (obj != null &&
        !obj.containsKey('method') &&
        (obj.containsKey('result') || obj.containsKey('error'))) {
      return DecodedLine.failure(
        RpcError.fromCode(ErrorCode.invalidRequest, data: {'line': line}),
        responseOnlyShape: true,
      );
    }
    // Call-shaped (or entirely alien): try to recover a request id so the error
    // response can echo it; fall back to null.
    Object? id;
    if (obj != null && obj.containsKey('id')) {
      final raw = obj['id'];
      if (raw == null || raw is String || raw is int) {
        id = raw;
      }
    }
    return DecodedLine.failure(
      RpcError.fromCode(ErrorCode.invalidRequest, data: {'line': line}),
      recoverableId: id,
    );
  }
}
