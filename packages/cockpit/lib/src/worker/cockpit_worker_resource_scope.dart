import 'dart:async';

import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_resource_grant.dart';

final class CockpitWorkerResourceScope {
  CockpitWorkerResourceScope._({
    required CockpitWorkerResourceAuthorityClient authority,
    required CockpitRpcCancellation cancellation,
    required List<CockpitWorkerResourceGrant> grants,
    required List<Duration> ttls,
  }) : _authority = authority,
       _cancellation = cancellation,
       grants = List<CockpitWorkerResourceGrant>.unmodifiable(grants) {
    for (var index = 0; index < grants.length; index += 1) {
      _scheduleHeartbeat(grants[index], ttls[index]);
    }
  }

  final CockpitWorkerResourceAuthorityClient _authority;
  final CockpitRpcCancellation _cancellation;
  final List<CockpitWorkerResourceGrant> grants;
  final List<Timer> _timers = <Timer>[];
  final Set<Future<void>> _heartbeats = <Future<void>>{};
  final Set<String> _activeGrantIds = <String>{};
  final Completer<void> _failure = Completer<void>();
  Future<void> _heartbeatTail = Future<void>.value();
  var _closed = false;

  Future<void> get failure => _failure.future;

  static Future<CockpitWorkerResourceScope> acquire({
    required CockpitWorkerResourceAuthorityClient authority,
    required CockpitRpcCancellation cancellation,
    required Iterable<CockpitWorkerResourceRequest> requests,
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  }) async {
    final requested = requests.toList(growable: false);
    final grants = <CockpitWorkerResourceGrant>[];
    try {
      for (var index = 0; index < requested.length; index += 1) {
        cancellation.throwIfCancelled();
        final request = requested[index];
        final grant = await authority.acquire(
          request,
          workspaceId: workspaceId,
          holderId: holderId,
          idempotencyKey: '$idempotencyKey-resource-$index',
          deadline: deadline,
        );
        _validateGrant(
          grant,
          request,
          workspaceId: workspaceId,
          holderId: holderId,
        );
        grants.add(grant);
      }
      return CockpitWorkerResourceScope._(
        authority: authority,
        cancellation: cancellation,
        grants: grants,
        ttls: requested.map((request) => request.ttl).toList(growable: false),
      );
    } on Object {
      for (final grant in grants.reversed) {
        try {
          await authority.release(grant, cancel: true);
        } on Object {
          // The Supervisor owns lease recovery after a failed acquisition.
        }
      }
      rethrow;
    }
  }

  Future<T> guard<T>(Future<T> operation) => Future.any<T>(<Future<T>>[
    operation,
    failure.then<T>((_) => throw StateError('Resource heartbeat failed.')),
  ]);

  Future<void> close({required bool cancel}) async {
    if (_closed) return;
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    if (_heartbeats.isNotEmpty) {
      await Future.wait<void>(_heartbeats.toList(growable: false));
    }
    Object? failure;
    StackTrace? failureStack;
    for (final grant in grants.reversed) {
      try {
        await _authority.release(grant, cancel: cancel);
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  void _scheduleHeartbeat(CockpitWorkerResourceGrant grant, Duration ttl) {
    final third = Duration(microseconds: ttl.inMicroseconds ~/ 3);
    final interval = third < const Duration(milliseconds: 250)
        ? const Duration(milliseconds: 250)
        : third > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : third;
    _timers.add(
      Timer.periodic(interval, (_) {
        if (_closed ||
            _cancellation.isCancelled ||
            !_activeGrantIds.add(grant.grantId)) {
          return;
        }
        late final Future<void> heartbeat;
        heartbeat = _heartbeatTail
            .then((_) {
              if (_closed || _cancellation.isCancelled) {
                return Future<void>.value();
              }
              return _authority.heartbeat(grant);
            })
            .catchError((Object error, StackTrace stackTrace) {
              if (!_failure.isCompleted) {
                _failure.completeError(error, stackTrace);
                _cancellation.cancel();
              }
            })
            .whenComplete(() {
              _heartbeats.remove(heartbeat);
              _activeGrantIds.remove(grant.grantId);
            });
        _heartbeatTail = heartbeat;
        _heartbeats.add(heartbeat);
      }),
    );
  }
}

void _validateGrant(
  CockpitWorkerResourceGrant grant,
  CockpitWorkerResourceRequest request, {
  required String workspaceId,
  required String holderId,
}) {
  if (grant.workspaceId != workspaceId ||
      grant.holderId != holderId ||
      grant.resourceKind != request.resourceKind ||
      grant.resourceId != request.resourceId ||
      !grant.expiresAt.isAfter(DateTime.now().toUtc()) ||
      request.requiresPort != (grant.port != null)) {
    throw const FormatException('Worker resource grant is invalid.');
  }
}
