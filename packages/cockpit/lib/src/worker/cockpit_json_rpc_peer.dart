import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'cockpit_json_line_framer.dart';
import 'cockpit_json_rpc_message.dart';
import 'cockpit_worker_value_reader.dart';

typedef CockpitJsonRpcRequestHandler =
    FutureOr<Object?> Function(
      CockpitJsonRpcRequest request,
      CockpitRpcCancellation cancellation,
    );

typedef CockpitJsonRpcProtocolErrorHandler =
    void Function(Object error, StackTrace stackTrace);

final class CockpitJsonRpcRemoteException implements Exception {
  const CockpitJsonRpcRemoteException(this.error);

  final CockpitJsonRpcError error;

  @override
  String toString() =>
      'CockpitJsonRpcRemoteException(${error.workerCode}): ${error.message}';
}

final class CockpitJsonRpcPeerClosedException implements Exception {
  const CockpitJsonRpcPeerClosedException();

  @override
  String toString() => 'CockpitJsonRpcPeerClosedException';
}

final class CockpitJsonRpcPeerCleanupPendingException implements Exception {
  const CockpitJsonRpcPeerCleanupPendingException();

  @override
  String toString() => 'CockpitJsonRpcPeerCleanupPendingException';
}

final class CockpitRpcCancellation {
  CockpitRpcCancellation._();

  factory CockpitRpcCancellation.detached() => CockpitRpcCancellation._();

  final Completer<void> _cancelled = Completer<void>();
  final Set<_CockpitForceAbortRegistration> _forceAbortRegistrations =
      <_CockpitForceAbortRegistration>{};
  var _forceAbortRequested = false;
  var _requiresCancellationReply = false;

  bool get isCancelled => _cancelled.isCompleted;
  bool get requiresCancellationReply => _requiresCancellationReply;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() => _cancel();

  void Function() registerForceAbort(Future<void> Function() forceAbort) {
    final registration = _CockpitForceAbortRegistration(forceAbort);
    _forceAbortRegistrations.add(registration);
    if (_forceAbortRequested) unawaited(registration.invoke());
    return () => _forceAbortRegistrations.remove(registration);
  }

  Future<void> requestForceAbort() {
    _forceAbortRequested = true;
    return Future.wait<void>(
      _forceAbortRegistrations.map((registration) => registration.invoke()),
    );
  }

  void throwIfCancelled() {
    if (isCancelled) throw const CockpitRpcCancelledException();
  }

  void _cancel({bool requiresCancellationReply = false}) {
    _requiresCancellationReply =
        _requiresCancellationReply || requiresCancellationReply;
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class _CockpitForceAbortRegistration {
  _CockpitForceAbortRegistration(this._callback);

  final Future<void> Function() _callback;
  Future<void>? _invocation;

  Future<void> invoke() => _invocation ??= Future<void>.sync(_callback);
}

final class CockpitRpcCancelledException implements Exception {
  const CockpitRpcCancelledException();

  @override
  String toString() => 'CockpitRpcCancelledException';
}

enum CockpitRpcCancellationResult { cancelled, alreadyTerminal, unknown }

final class CockpitJsonRpcPeer {
  CockpitJsonRpcPeer({
    required Stream<List<int>> input,
    required StreamSink<List<int>> output,
    required CockpitJsonRpcRequestHandler requestHandler,
    CockpitJsonRpcProtocolErrorHandler? onProtocolError,
    DateTime Function()? utcNow,
    int maximumPayloadBytes = cockpitWorkerMaximumPayloadBytes,
    int maximumRememberedRequestIds = 8192,
    int maximumIdempotencyEntries = 2048,
    int maximumActiveIdempotentFollowers = 2048,
    Duration cancellationGrace = const Duration(milliseconds: 250),
    Duration forcedAbortGrace = const Duration(seconds: 2),
  }) : _input = input,
       _output = output,
       _requestHandler = requestHandler,
       _onProtocolError = onProtocolError,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _maximumPayloadBytes = maximumPayloadBytes,
       _maximumRememberedRequestIds = maximumRememberedRequestIds,
       _maximumIdempotencyEntries = maximumIdempotencyEntries,
       _maximumActiveIdempotentFollowers = maximumActiveIdempotentFollowers,
       _cancellationGrace = cancellationGrace,
       _forcedAbortGrace = forcedAbortGrace {
    if (maximumPayloadBytes < 1024 ||
        maximumPayloadBytes > cockpitWorkerMaximumPayloadBytes) {
      throw ArgumentError.value(maximumPayloadBytes, 'maximumPayloadBytes');
    }
    if (maximumRememberedRequestIds < 128 ||
        maximumRememberedRequestIds > 65536) {
      throw ArgumentError.value(
        maximumRememberedRequestIds,
        'maximumRememberedRequestIds',
      );
    }
    if (maximumIdempotencyEntries < 32 || maximumIdempotencyEntries > 16384) {
      throw ArgumentError.value(
        maximumIdempotencyEntries,
        'maximumIdempotencyEntries',
      );
    }
    if (maximumActiveIdempotentFollowers < 1 ||
        maximumActiveIdempotentFollowers > 16384) {
      throw ArgumentError.value(
        maximumActiveIdempotentFollowers,
        'maximumActiveIdempotentFollowers',
      );
    }
    if (cancellationGrace < Duration.zero ||
        cancellationGrace > const Duration(minutes: 5) ||
        forcedAbortGrace <= Duration.zero ||
        forcedAbortGrace > const Duration(seconds: 30)) {
      throw ArgumentError('JSON-RPC cancellation grace is invalid.');
    }
  }

  final Stream<List<int>> _input;
  final StreamSink<List<int>> _output;
  final CockpitJsonRpcRequestHandler _requestHandler;
  final CockpitJsonRpcProtocolErrorHandler? _onProtocolError;
  final DateTime Function() _utcNow;
  final int _maximumPayloadBytes;
  final int _maximumRememberedRequestIds;
  final int _maximumIdempotencyEntries;
  final int _maximumActiveIdempotentFollowers;
  final Duration _cancellationGrace;
  final Duration _forcedAbortGrace;
  final Map<String, _PendingCall> _pending = <String, _PendingCall>{};
  final Set<String> _outboundCleanupPending = <String>{};
  final Map<String, _InboundCall> _activeInbound = <String, _InboundCall>{};
  final Set<String> _seenInbound = <String>{};
  final Queue<String> _seenInboundOrder = Queue<String>();
  final LinkedHashMap<String, _IdempotentExecution> _idempotency =
      LinkedHashMap<String, _IdempotentExecution>();
  final Completer<void> _done = Completer<void>();
  final String _requestPrefix = _randomPrefix();
  StreamSubscription<Map<String, Object?>>? _subscription;
  var _requestCounter = 0;
  var _activeIdempotentFollowers = 0;
  var _started = false;
  var _closed = false;

  bool get isClosed => _closed;
  int get activeInboundRequestCount => _activeInbound.length;
  int get pendingOutboundRequestCount => _pending.length;
  bool get isOutboundCleanupPending => _outboundCleanupPending.isNotEmpty;
  Future<void> get done => _done.future;

  void start() {
    if (_started) throw StateError('JSON-RPC peer has already started.');
    if (_closed) throw const CockpitJsonRpcPeerClosedException();
    _started = true;
    _subscription = _input
        .transform(CockpitJsonLineFramer(maximumBytes: _maximumPayloadBytes))
        .listen(
          _receive,
          onError: (Object error, StackTrace stackTrace) {
            _reportProtocolError(error, stackTrace);
            unawaited(close());
          },
          onDone: () => unawaited(close(closeOutput: false)),
          cancelOnError: false,
        );
  }

  Future<Object?> call({
    required String method,
    required Map<String, Object?> params,
    required DateTime deadline,
    String? requestId,
  }) {
    if (!_started || _closed) {
      throw const CockpitJsonRpcPeerClosedException();
    }
    if (_outboundCleanupPending.isNotEmpty) {
      throw const CockpitJsonRpcPeerCleanupPendingException();
    }
    workerMethod(method, r'$.method');
    final now = _utcNow();
    final normalizedDeadline = deadline.toUtc();
    if (!normalizedDeadline.isAfter(now)) {
      throw TimeoutException('JSON-RPC request deadline has expired.');
    }
    final effectiveRequestId =
        requestId ?? '$_requestPrefix-${++_requestCounter}';
    workerId(effectiveRequestId, r'$.requestId');
    if (_pending.containsKey(effectiveRequestId)) {
      throw FormatException(
        'Outbound JSON-RPC request id $effectiveRequestId is already active.',
      );
    }
    final wireParams = <String, Object?>{
      ...params,
      'requestId': effectiveRequestId,
      'deadline': normalizedDeadline.toIso8601String(),
    };
    workerValidateJsonValue(wireParams, r'$.params');
    final completer = Completer<Object?>();
    final pending = _PendingCall(completer);
    pending.deadlineTimer = Timer(
      normalizedDeadline.difference(now),
      () => _beginOutboundDeadline(effectiveRequestId, pending),
    );
    _pending[effectiveRequestId] = pending;
    try {
      _send(
        CockpitJsonRpcRequest(
          id: effectiveRequestId,
          method: method,
          params: wireParams,
        ),
      );
    } on Object catch (error, stackTrace) {
      _pending.remove(effectiveRequestId);
      pending.cancelTimers();
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  CockpitRpcCancellationResult cancelInbound(String requestId) {
    workerId(requestId, r'$.requestId');
    final call = _activeInbound[requestId];
    if (call != null) {
      if (call.isIdempotentFollower) {
        call.cancellation._cancel(requiresCancellationReply: true);
        _finishIdempotentFollower(requestId, call, _cancelledReply(call));
      } else {
        _beginInboundCancellation(call, deadlineExceeded: false);
      }
      return CockpitRpcCancellationResult.cancelled;
    }
    return _seenInbound.contains(requestId)
        ? CockpitRpcCancellationResult.alreadyTerminal
        : CockpitRpcCancellationResult.unknown;
  }

  Future<void> close({bool closeOutput = true}) async {
    if (_closed) return done;
    _closed = true;
    for (final pending in _pending.values) {
      pending.cancelTimers();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          pending.deadlineExpired
              ? TimeoutException('JSON-RPC request deadline has expired.')
              : const CockpitJsonRpcPeerClosedException(),
        );
      }
    }
    _pending.clear();
    _outboundCleanupPending.clear();
    for (final call in _activeInbound.values) {
      call.cancellation._cancel();
      if (!call.isIdempotentFollower) {
        unawaited(call.cancellation.requestForceAbort());
      }
      call.deadlineTimer?.cancel();
      call.forceAbortTimer?.cancel();
      call.forceCloseTimer?.cancel();
    }
    _activeInbound.clear();
    _activeIdempotentFollowers = 0;
    for (final execution in _idempotency.values) {
      execution.followers.clear();
    }
    _idempotency.clear();
    await _subscription?.cancel();
    if (closeOutput) await _output.close();
    if (!_done.isCompleted) _done.complete();
  }

  void _receive(Map<String, Object?> json) {
    if (_closed) return;
    try {
      final message = CockpitJsonRpcMessage.fromJson(json);
      switch (message) {
        case CockpitJsonRpcRequest():
          unawaited(_receiveRequest(message));
        case CockpitJsonRpcResponse():
          _receiveResponse(message);
      }
    } on Object catch (error, stackTrace) {
      _reportProtocolError(error, stackTrace);
      unawaited(close());
    }
  }

  void _receiveResponse(CockpitJsonRpcResponse response) {
    final pending = _pending.remove(response.id);
    if (pending == null) {
      _reportProtocolError(
        FormatException('Late or unknown JSON-RPC response ${response.id}.'),
        StackTrace.current,
      );
      return;
    }
    pending.cancelTimers();
    _outboundCleanupPending.remove(response.id);
    if (pending.deadlineExpired) {
      pending.completer.completeError(
        TimeoutException('JSON-RPC request deadline has expired.'),
      );
      return;
    }
    if (response.error case final error?) {
      pending.completer.completeError(CockpitJsonRpcRemoteException(error));
    } else {
      pending.completer.complete(response.result);
    }
  }

  void _beginOutboundDeadline(String requestId, _PendingCall pending) {
    if (_pending[requestId] != pending || pending.deadlineExpired) return;
    pending.deadlineExpired = true;
    _outboundCleanupPending.add(requestId);
    pending.terminalGraceTimer = Timer(
      _cancellationGrace + _forcedAbortGrace,
      () {
        if (_pending[requestId] == pending && !_closed) {
          unawaited(close());
        }
      },
    );
  }

  Future<void> _receiveRequest(CockpitJsonRpcRequest request) async {
    if (!_rememberInbound(request.id)) {
      _sendFailure(
        request.id,
        workerCode: 'duplicateRequestId',
        message: 'JSON-RPC request id has already been used.',
      );
      return;
    }
    if (!cockpitWorkerMethods.contains(request.method)) {
      _sendFailure(
        request.id,
        code: -32601,
        workerCode: 'methodNotFound',
        message: 'Unknown worker method ${request.method}.',
      );
      return;
    }

    final idempotencyIdentity = _idempotencyIdentity(request);
    final fingerprint = idempotencyIdentity == null
        ? null
        : _requestFingerprint(request);
    if (idempotencyIdentity != null) {
      final existing = _idempotency.remove(idempotencyIdentity);
      if (existing != null) {
        _idempotency[idempotencyIdentity] = existing;
        if (existing.fingerprint != fingerprint) {
          _sendFailure(
            request.id,
            workerCode: 'idempotencyConflict',
            message: 'Idempotency key was reused with a different request.',
          );
          return;
        }
        _receiveIdempotentFollower(request, existing);
        return;
      }
      _evictCompletedIdempotencyEntries();
      if (_idempotency.length >= _maximumIdempotencyEntries) {
        _sendFailure(
          request.id,
          workerCode: 'idempotencyCapacityExceeded',
          message: 'Worker idempotency capacity is temporarily exhausted.',
        );
        return;
      }
    }

    final idempotentExecution = idempotencyIdentity == null
        ? null
        : _IdempotentExecution(fingerprint!);
    if (idempotencyIdentity != null) {
      _idempotency[idempotencyIdentity] = idempotentExecution!;
    }

    final cancellation = CockpitRpcCancellation._();
    final inbound = _InboundCall(cancellation);
    _activeInbound[request.id] = inbound;
    final deadline = _requestDeadline(request.params);
    if (deadline != null) {
      final remaining = deadline.difference(_utcNow());
      if (remaining <= Duration.zero) {
        final reply = _failureReply(
          workerCode: 'deadlineExceeded',
          message: 'Worker request deadline has expired.',
        );
        _finishInbound(request.id, inbound, idempotentExecution, reply);
        return;
      }
      inbound.deadlineTimer = Timer(remaining, () {
        _beginInboundCancellation(inbound, deadlineExceeded: true);
      });
    }

    try {
      final result = await _requestHandler(request, cancellation);
      final reply = cancellation.requiresCancellationReply
          ? _cancelledReply(inbound)
          : _RpcReply.success(result);
      _finishInbound(request.id, inbound, idempotentExecution, reply);
    } on CockpitJsonRpcRemoteException catch (error) {
      _finishInbound(
        request.id,
        inbound,
        idempotentExecution,
        _RpcReply.failure(error.error),
      );
    } on CockpitRpcCancelledException {
      _finishInbound(
        request.id,
        inbound,
        idempotentExecution,
        _cancelledReply(inbound),
      );
    } on FormatException {
      _finishInbound(
        request.id,
        inbound,
        idempotentExecution,
        _failureReply(
          code: -32602,
          workerCode: 'invalidRequest',
          message: 'Worker request parameters are invalid.',
        ),
      );
    } on Object catch (error, stackTrace) {
      _reportProtocolError(error, stackTrace);
      _finishInbound(
        request.id,
        inbound,
        idempotentExecution,
        _failureReply(
          code: -32603,
          workerCode: 'internalError',
          message: 'Worker request failed internally.',
        ),
      );
    }
  }

  void _receiveIdempotentFollower(
    CockpitJsonRpcRequest request,
    _IdempotentExecution execution,
  ) {
    if (execution.completedReply case final reply?) {
      _sendReply(request.id, reply);
      return;
    }
    if (_activeIdempotentFollowers >= _maximumActiveIdempotentFollowers) {
      _sendFailure(
        request.id,
        workerCode: 'idempotencyFollowerCapacityExceeded',
        message: 'Worker idempotency follower capacity is exhausted.',
      );
      return;
    }

    final inbound = _InboundCall(
      CockpitRpcCancellation._(),
      followedExecution: execution,
    );
    _activeInbound[request.id] = inbound;
    execution.followers[request.id] = inbound;
    _activeIdempotentFollowers += 1;
    final deadline = _requestDeadline(request.params);
    if (deadline != null) {
      final remaining = deadline.difference(_utcNow());
      if (remaining <= Duration.zero) {
        inbound.deadlineExceeded = true;
        inbound.cancellation._cancel(requiresCancellationReply: true);
        _finishIdempotentFollower(
          request.id,
          inbound,
          _cancelledReply(inbound),
        );
        return;
      }
      inbound.deadlineTimer = Timer(remaining, () {
        if (inbound.isTerminal || _closed) return;
        inbound.deadlineExceeded = true;
        inbound.cancellation._cancel(requiresCancellationReply: true);
        _finishIdempotentFollower(
          request.id,
          inbound,
          _cancelledReply(inbound),
        );
      });
    }
  }

  void _finishIdempotentFollower(
    String requestId,
    _InboundCall inbound,
    _RpcReply reply,
  ) {
    if (!inbound.finish()) return;
    inbound.deadlineTimer?.cancel();
    final followedExecution = inbound.followedExecution;
    if (followedExecution != null &&
        identical(followedExecution.followers[requestId], inbound)) {
      followedExecution.followers.remove(requestId);
    }
    if (identical(_activeInbound[requestId], inbound)) {
      _activeInbound.remove(requestId);
      _activeIdempotentFollowers -= 1;
    }
    if (!_closed) _sendReply(requestId, reply);
  }

  void _finishInbound(
    String requestId,
    _InboundCall inbound,
    _IdempotentExecution? idempotentExecution,
    _RpcReply reply,
  ) {
    if (!inbound.finish()) return;
    inbound.deadlineTimer?.cancel();
    inbound.forceAbortTimer?.cancel();
    inbound.forceCloseTimer?.cancel();
    if (identical(_activeInbound[requestId], inbound)) {
      _activeInbound.remove(requestId);
    }
    if (!_closed) _sendReply(requestId, reply);
    if (idempotentExecution != null) {
      _finishIdempotentExecution(idempotentExecution, reply);
    }
  }

  void _finishIdempotentExecution(
    _IdempotentExecution execution,
    _RpcReply reply,
  ) {
    if (execution.completedReply != null) return;
    execution.completedReply = reply;
    final followers = execution.followers.entries.toList(growable: false);
    for (final follower in followers) {
      _finishIdempotentFollower(follower.key, follower.value, reply);
    }
  }

  void _beginInboundCancellation(
    _InboundCall inbound, {
    required bool deadlineExceeded,
  }) {
    if (inbound.isTerminal) return;
    inbound.deadlineExceeded = inbound.deadlineExceeded || deadlineExceeded;
    inbound.cancellation._cancel(requiresCancellationReply: true);
    inbound.forceAbortTimer ??= Timer(_cancellationGrace, () {
      if (inbound.isTerminal || _closed) return;
      unawaited(inbound.cancellation.requestForceAbort());
      inbound.forceCloseTimer ??= Timer(_forcedAbortGrace, () {
        if (!inbound.isTerminal && !_closed) unawaited(close());
      });
    });
  }

  _RpcReply _cancelledReply(_InboundCall inbound) => _failureReply(
    workerCode: inbound.deadlineExceeded ? 'deadlineExceeded' : 'cancelled',
    message: inbound.deadlineExceeded
        ? 'Worker request deadline has expired.'
        : 'Worker request was cancelled.',
  );

  bool _rememberInbound(String requestId) {
    if (_activeInbound.containsKey(requestId)) return false;
    if (!_seenInbound.add(requestId)) return false;
    _seenInboundOrder.addLast(requestId);
    while (_seenInboundOrder.length > _maximumRememberedRequestIds) {
      _seenInbound.remove(_seenInboundOrder.removeFirst());
    }
    return true;
  }

  void _evictCompletedIdempotencyEntries() {
    if (_idempotency.length < _maximumIdempotencyEntries) return;
    final completed = _idempotency.entries
        .where((entry) => entry.value.isCompleted)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in completed) {
      _idempotency.remove(key);
      if (_idempotency.length < _maximumIdempotencyEntries) return;
    }
  }

  DateTime? _requestDeadline(Map<String, Object?> params) {
    final raw = params['deadline'];
    if (raw == null) return null;
    try {
      return workerUtcDateTime(raw, r'$.params.deadline');
    } on FormatException {
      return null;
    }
  }

  void _sendReply(String requestId, _RpcReply reply) {
    if (reply.error case final error?) {
      _send(CockpitJsonRpcResponse.failure(id: requestId, error: error));
    } else {
      _send(
        CockpitJsonRpcResponse.success(id: requestId, result: reply.result),
      );
    }
  }

  void _sendFailure(
    String requestId, {
    int code = -32000,
    required String workerCode,
    required String message,
  }) => _sendReply(
    requestId,
    _failureReply(code: code, workerCode: workerCode, message: message),
  );

  void _send(CockpitJsonRpcMessage message) {
    if (_closed) throw const CockpitJsonRpcPeerClosedException();
    final bytes = utf8.encode('${jsonEncode(message.toJson())}\n');
    if (bytes.length - 1 > _maximumPayloadBytes) {
      throw const CockpitJsonLineFrameException(
        'frameTooLarge',
        'Worker protocol frame exceeds the payload limit.',
      );
    }
    _output.add(bytes);
  }

  void _reportProtocolError(Object error, StackTrace stackTrace) {
    _onProtocolError?.call(error, stackTrace);
  }
}

final class _PendingCall {
  _PendingCall(this.completer);

  final Completer<Object?> completer;
  Timer? deadlineTimer;
  Timer? terminalGraceTimer;
  var deadlineExpired = false;

  void cancelTimers() {
    deadlineTimer?.cancel();
    terminalGraceTimer?.cancel();
  }
}

final class _InboundCall {
  _InboundCall(this.cancellation, {this.followedExecution});

  final CockpitRpcCancellation cancellation;
  final _IdempotentExecution? followedExecution;
  Timer? deadlineTimer;
  Timer? forceAbortTimer;
  Timer? forceCloseTimer;
  var deadlineExceeded = false;
  var _terminal = false;

  bool get isTerminal => _terminal;
  bool get isIdempotentFollower => followedExecution != null;

  bool finish() {
    if (_terminal) return false;
    _terminal = true;
    return true;
  }
}

final class _IdempotentExecution {
  _IdempotentExecution(this.fingerprint);

  final String fingerprint;
  final Map<String, _InboundCall> followers = <String, _InboundCall>{};
  _RpcReply? completedReply;

  bool get isCompleted => completedReply != null;
}

final class _RpcReply {
  const _RpcReply.success(this.result) : error = null;
  const _RpcReply.failure(this.error) : result = null;

  final Object? result;
  final CockpitJsonRpcError? error;
}

_RpcReply _failureReply({
  int code = -32000,
  required String workerCode,
  required String message,
}) => _RpcReply.failure(
  CockpitJsonRpcError(code: code, message: message, workerCode: workerCode),
);

String? _idempotencyIdentity(CockpitJsonRpcRequest request) {
  final key = request.params['idempotencyKey'];
  final workspaceId = request.params['workspaceId'];
  if (key is! String || workspaceId is! String) return null;
  try {
    workerId(key, r'$.params.idempotencyKey');
    workerId(workspaceId, r'$.params.workspaceId');
  } on FormatException {
    return null;
  }
  return '${request.method}\u0000$workspaceId\u0000$key';
}

String _requestFingerprint(CockpitJsonRpcRequest request) {
  final semanticParams = <String, Object?>{
    for (final entry in request.params.entries)
      if (entry.key != 'requestId' && entry.key != 'deadline')
        entry.key: entry.value,
  };
  final invocation = semanticParams['invocation'];
  if (request.method == 'operation' && invocation is Map<String, Object?>) {
    semanticParams['invocation'] = <String, Object?>{
      for (final entry in invocation.entries)
        if (entry.key != 'deadline') entry.key: entry.value,
    };
  }
  return sha256
      .convert(
        utf8.encode(
          _canonicalJson(<String, Object?>{
            'method': request.method,
            'params': semanticParams,
          }),
        ),
      )
      .toString();
}

String _canonicalJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(_canonicalFingerprintField(key, value[key]))}').join(',')}}';
  }
  if (value is List<Object?>) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

Object? _canonicalFingerprintField(String key, Object? value) {
  if (key != 'requiredFeatures' || value is! List<Object?>) return value;
  if (value.any((feature) => feature is! String)) return value;
  return value.cast<String>().toList()..sort();
}

String _randomPrefix() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  return 'rpc_${base64Url.encode(bytes).replaceAll('=', '')}';
}
