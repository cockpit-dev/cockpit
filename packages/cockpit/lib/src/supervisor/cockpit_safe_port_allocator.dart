import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_ids.dart';
import '../infrastructure/cockpit_monotonic_clock.dart';
import 'cockpit_lease_registry.dart';
import 'cockpit_lease_support.dart';
import 'cockpit_loopback_port_cleanup_probe.dart';
import 'cockpit_port_models.dart';

part 'cockpit_port_handoff.dart';

typedef CockpitEphemeralLoopbackBinder = Future<ServerSocket> Function();
typedef CockpitReservedLoopbackBinder =
    Future<ServerSocket> Function(InternetAddress address, int port);

enum CockpitPortReservationState {
  reserved,
  recoveryPending,
  handedOff,
  released,
  quarantined,
}

final class CockpitSafePortAllocator {
  CockpitSafePortAllocator({
    required CockpitLeaseRegistry leases,
    CockpitTokenGenerator? tokenGenerator,
    CockpitMonotonicClock? clock,
    CockpitEphemeralLoopbackBinder bindEphemeral = cockpitBindEphemeralLoopback,
    CockpitReservedLoopbackBinder bindReserved = cockpitBindReservedLoopback,
    Duration probeInterval = const Duration(milliseconds: 50),
  }) : _leases = leases,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _clock = clock ?? CockpitSystemMonotonicClock(),
       _bindEphemeral = bindEphemeral,
       _bindReserved = bindReserved,
       _probeInterval = probeInterval {
    if (probeInterval <= Duration.zero ||
        probeInterval > const Duration(seconds: 1)) {
      throw ArgumentError.value(probeInterval, 'probeInterval');
    }
  }

  final CockpitLeaseRegistry _leases;
  final CockpitTokenGenerator _tokenGenerator;
  final CockpitMonotonicClock _clock;
  final CockpitEphemeralLoopbackBinder _bindEphemeral;
  final CockpitReservedLoopbackBinder _bindReserved;
  final Duration _probeInterval;
  final Map<String, CockpitPortReservation> _reservations =
      <String, CockpitPortReservation>{};
  final _CockpitPortReservationLocks _locks = _CockpitPortReservationLocks();

  Future<CockpitPortReservation> reserve({
    required String workspaceId,
    required String holderId,
    required CockpitIdempotencyKey idempotencyKey,
    Duration ttl = const Duration(seconds: 30),
  }) {
    if (ttl < const Duration(seconds: 1) ||
        ttl > const Duration(milliseconds: cockpitMaximumLeaseTtlMs)) {
      throw const CockpitLeaseException(
        code: 'invalidLeaseTtl',
        message: 'Port reservation TTL is outside the lease bounds.',
      );
    }
    final key = '$workspaceId\u0000${idempotencyKey.value}';
    return _locks.run(key, () async {
      final existing = _reservations[key];
      if (existing != null &&
          existing.state != CockpitPortReservationState.released) {
        final replayed = await _leases.replayPortReservation(
          workspaceId: workspaceId,
          idempotencyKey: idempotencyKey,
          replay: (replay) => _reuseCachedReservation(
            existing: existing,
            replay: replay,
            holderId: holderId,
            ttl: ttl,
          ),
        );
        if (replayed != null) return replayed;
        throw const CockpitLeaseException(
          code: 'portReservationMissing',
          message: 'Cached port reservation has no durable lease record.',
        );
      }
      final replayed = await _leases.replayPortReservation(
        workspaceId: workspaceId,
        idempotencyKey: idempotencyKey,
        replay: (replay) => _restoreReservation(
          key: key,
          replay: replay,
          holderId: holderId,
          ttl: ttl,
        ),
      );
      if (replayed != null) return replayed;
      final socket = await _bindEphemeral();
      if (socket.address.type != InternetAddressType.IPv4 ||
          !socket.address.isLoopback ||
          socket.port < 1 ||
          socket.port > 65535) {
        await socket.close();
        throw const CockpitLeaseException(
          code: 'invalidPortReservation',
          message: 'Ephemeral reservation did not bind loopback IPv4.',
        );
      }
      try {
        final handoffToken = _tokenGenerator.nextToken();
        final lease = await _leases.acquire(
          CockpitLeaseRequest(
            workspaceId: workspaceId,
            resourceKind: CockpitLeaseResourceKind.forwardedPort,
            resourceId: CockpitLoopbackPortCleanupProbe.resourceId(socket.port),
            holderId: holderId,
            idempotencyKey: idempotencyKey,
            waitTimeoutMs: 0,
            ttlMs: ttl.inMilliseconds,
          ),
          handoffToken: handoffToken,
        );
        final reservation = _reservation(
          key: key,
          socket: socket,
          lease: lease,
          handoffToken: handoffToken,
          phase: CockpitDurablePortPhase.reserved,
          expectedOwner: null,
          state: CockpitPortReservationState.reserved,
        );
        _reservations[key] = reservation;
        return reservation;
      } on Object {
        await socket.close();
        rethrow;
      }
    });
  }

  Future<CockpitPortReservation> _restoreReservation({
    required String key,
    required CockpitDurablePortReservation replay,
    required String holderId,
    required Duration ttl,
  }) async {
    _validateReplayRequest(replay, holderId, ttl);
    final lease = _requireActiveReplay(replay.lease);
    if (replay.phase != CockpitDurablePortPhase.reserved) {
      final reservation = _reservation(
        key: key,
        socket: null,
        lease: lease,
        handoffToken: replay.handoffToken,
        phase: replay.phase,
        expectedOwner: replay.expectedOwner,
        state: CockpitPortReservationState.recoveryPending,
      );
      _reservations[key] = reservation;
      return reservation;
    }
    final port = CockpitLoopbackPortCleanupProbe.parseResourceId(
      lease.resourceId,
    );
    ServerSocket? socket;
    try {
      socket = await _bindReserved(InternetAddress.loopbackIPv4, port);
      if (socket.address.type != InternetAddressType.IPv4 ||
          !socket.address.isLoopback ||
          socket.port != port) {
        throw const CockpitLeaseException(
          code: 'invalidPortReservation',
          message: 'Replayed reservation did not bind its exact loopback port.',
        );
      }
      final refreshed = await _leases.heartbeat(
        lease.leaseId,
        holderId: lease.holderId,
      );
      final reservation = _reservation(
        key: key,
        socket: socket,
        lease: refreshed,
        handoffToken: replay.handoffToken,
        phase: replay.phase,
        expectedOwner: replay.expectedOwner,
        state: CockpitPortReservationState.reserved,
      );
      _reservations[key] = reservation;
      return reservation;
    } on SocketException {
      await socket?.close();
      final quarantined = await _leases.quarantine(
        lease.leaseId,
        holderId: lease.holderId,
        failure: _portFailure(
          'portReservationUnavailable',
          'The durable loopback port could not be reserved again.',
        ),
      );
      throw CockpitLeaseException(
        code: 'portReservationUnavailable',
        message: 'The durable loopback port could not be reserved again.',
        lease: quarantined,
      );
    } on Object {
      await socket?.close();
      rethrow;
    }
  }

  CockpitPortReservation _reuseCachedReservation({
    required CockpitPortReservation existing,
    required CockpitDurablePortReservation replay,
    required String holderId,
    required Duration ttl,
  }) {
    _validateReplayRequest(replay, holderId, ttl);
    final lease = _requireActiveReplay(replay.lease);
    if (lease.leaseId != existing.lease.leaseId) {
      throw CockpitLeaseException(
        code: 'idempotencyConflict',
        message: 'Cached port reservation differs from durable lease state.',
        lease: lease,
      );
    }
    existing._synchronize(replay);
    return existing;
  }

  void _validateReplayRequest(
    CockpitDurablePortReservation replay,
    String holderId,
    Duration ttl,
  ) {
    if (replay.lease.holderId != holderId ||
        replay.ttlMs != ttl.inMilliseconds) {
      throw CockpitLeaseException(
        code: 'idempotencyConflict',
        message:
            'Port reservation parameters differ from the original request.',
        lease: replay.lease,
      );
    }
  }

  CockpitLeaseResource _requireActiveReplay(CockpitLeaseResource lease) {
    switch (lease.state) {
      case CockpitLeaseState.active:
        return lease;
      case CockpitLeaseState.queued:
        throw CockpitLeaseException(
          code: 'resourceBusy',
          message: 'Port reservation is still queued.',
          lease: lease,
        );
      case CockpitLeaseState.releasing:
      case CockpitLeaseState.expired:
        throw CockpitLeaseException(
          code: 'portReservationExpired',
          message: 'Port reservation is awaiting crash cleanup.',
          lease: lease,
        );
      case CockpitLeaseState.quarantined:
        throw CockpitLeaseException(
          code: 'resourceQuarantined',
          message: 'Port reservation is quarantined.',
          lease: lease,
        );
      case CockpitLeaseState.released:
        throw CockpitLeaseException(
          code: 'portReservationReleased',
          message: 'Port reservation was already released.',
          lease: lease,
        );
    }
  }

  CockpitPortReservation _reservation({
    required String key,
    required ServerSocket? socket,
    required CockpitLeaseResource lease,
    required String handoffToken,
    required CockpitDurablePortPhase phase,
    required CockpitDurablePortOwner? expectedOwner,
    required CockpitPortReservationState state,
  }) {
    final reservation = CockpitPortReservation._(
      socket: socket,
      lease: lease,
      leases: _leases,
      clock: _clock,
      probeInterval: _probeInterval,
      handoffToken: handoffToken,
      phase: phase,
      expectedOwner: expectedOwner,
      state: state,
      onTerminal: () => _reservations.remove(key),
    );
    reservation._attachLocalCleanup();
    return reservation;
  }
}

Future<ServerSocket> cockpitBindEphemeralLoopback() =>
    ServerSocket.bind(InternetAddress.loopbackIPv4, 0, shared: false);

Future<ServerSocket> cockpitBindReservedLoopback(
  InternetAddress address,
  int port,
) => ServerSocket.bind(address, port, shared: false);

final class CockpitPortReservation {
  CockpitPortReservation._({
    required ServerSocket? socket,
    required CockpitLeaseResource lease,
    required CockpitLeaseRegistry leases,
    required CockpitMonotonicClock clock,
    required Duration probeInterval,
    required String handoffToken,
    required CockpitDurablePortPhase phase,
    required CockpitDurablePortOwner? expectedOwner,
    required CockpitPortReservationState state,
    required void Function() onTerminal,
  }) : _socket = socket,
       _lease = lease,
       _leases = leases,
       _clock = clock,
       _probeInterval = probeInterval,
       _handoffToken = handoffToken,
       _phase = phase,
       _expectedOwner = expectedOwner,
       _state = state,
       _onTerminal = onTerminal;

  ServerSocket? _socket;
  CockpitLeaseResource _lease;
  final CockpitLeaseRegistry _leases;
  final CockpitMonotonicClock _clock;
  final Duration _probeInterval;
  final String _handoffToken;
  CockpitDurablePortPhase _phase;
  CockpitDurablePortOwner? _expectedOwner;
  final void Function() _onTerminal;
  CockpitPortReservationState _state;
  CockpitVerifiedPortLease? _verifiedLease;
  Future<Object?>? _transition;
  Future<void> Function()? _localCleanup;

  int get port =>
      _lease.resourceId.startsWith(
        CockpitLoopbackPortCleanupProbe.resourcePrefix,
      )
      ? CockpitLoopbackPortCleanupProbe.parseResourceId(_lease.resourceId)
      : throw StateError('Reservation lease is not a loopback port.');

  CockpitLeaseResource get lease => _lease;
  String get handoffToken => _handoffToken;
  CockpitPortReservationState get state => _state;
  CockpitVerifiedPortLease? get verifiedLease => _verifiedLease;

  void _synchronize(CockpitDurablePortReservation reservation) {
    _lease = reservation.lease;
    _phase = reservation.phase;
    _expectedOwner = reservation.expectedOwner;
    if (_lease.state == CockpitLeaseState.released) {
      _state = CockpitPortReservationState.released;
      _terminal();
    } else if (_lease.state == CockpitLeaseState.quarantined) {
      _state = CockpitPortReservationState.quarantined;
      _terminal();
    }
  }

  void _attachLocalCleanup() {
    final cleanup = _prepareLocalCleanup;
    _localCleanup = cleanup;
    _leases.registerLocalCleanup(_lease.leaseId, cleanup);
  }

  Future<void> _prepareLocalCleanup() async {
    await _socket?.close();
    _socket = null;
    _terminal();
  }

  void _terminal() {
    final cleanup = _localCleanup;
    if (cleanup != null) {
      _leases.unregisterLocalCleanup(_lease.leaseId, cleanup);
      _localCleanup = null;
    }
    _onTerminal();
  }
}

final class _CockpitPortReservationLocks {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  Future<R> run<R>(String key, Future<R> Function() action) async {
    final previous = _tails[key] ?? Future<void>.value();
    final turn = Completer<void>();
    _tails[key] = turn.future;
    await previous;
    try {
      return await action();
    } finally {
      turn.complete();
      if (identical(_tails[key], turn.future)) _tails.remove(key);
    }
  }
}
