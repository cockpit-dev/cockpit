part of 'cockpit_safe_port_allocator.dart';

extension CockpitPortReservationOperations on CockpitPortReservation {
  Future<CockpitVerifiedPortLease> handoff({
    required CockpitPortBinder binder,
    required CockpitPortOwnerProbe ownerProbe,
    required CockpitExpectedPortOwner expectedOwner,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    while (_transition != null) {
      await _transition;
    }
    if (_verifiedLease != null) return _verifiedLease!;
    if ((_state != CockpitPortReservationState.reserved &&
            _state != CockpitPortReservationState.recoveryPending) ||
        timeout <= Duration.zero ||
        timeout > const Duration(milliseconds: cockpitMaximumLeaseTtlMs)) {
      throw const CockpitLeaseException(
        code: 'portHandoffStateInvalid',
        message: 'Port reservation cannot begin this handoff.',
      );
    }
    final operation = _leases.withActiveWorkspaceAdmission(
      _lease.workspaceId,
      () => _performHandoff(
        binder: binder,
        ownerProbe: ownerProbe,
        expectedOwner: expectedOwner,
        timeout: timeout,
      ),
    );
    _transition = operation;
    try {
      return await operation;
    } finally {
      if (identical(_transition, operation)) _transition = null;
    }
  }

  Future<CockpitVerifiedPortLease> _performHandoff({
    required CockpitPortBinder binder,
    required CockpitPortOwnerProbe ownerProbe,
    required CockpitExpectedPortOwner expectedOwner,
    required Duration timeout,
  }) async {
    final recovering = _state == CockpitPortReservationState.recoveryPending;
    final durableOwner = CockpitDurablePortOwner(
      ownerId: expectedOwner.ownerId,
      processId: expectedOwner.processId,
      processStartIdentity: expectedOwner.processStartIdentity,
      sessionId: expectedOwner.sessionId,
    );
    if (_expectedOwner != null && !_expectedOwner!.matches(durableOwner)) {
      throw CockpitLeaseException(
        code: 'portOwnerConflict',
        message: 'Port handoff owner differs from the persisted owner.',
        lease: _lease,
      );
    }
    final remainingLease = _lease.expiresAt!.difference(_clock.utcNow.toUtc());
    final budget = remainingLease < timeout ? remainingLease : timeout;
    if (budget <= Duration.zero) {
      await _quarantine(
        'portHandoffLeaseExpired',
        'Port lease expired before controlled handoff.',
      );
      throw const CockpitLeaseException(
        code: 'portHandoffLeaseExpired',
        message: 'Port lease expired before controlled handoff.',
      );
    }
    final deadline = CockpitMonotonicDeadline.after(_clock, budget);
    final wallDeadline = _clock.utcNow.toUtc().add(budget);
    try {
      final durable = await _leases.beginPortHandoff(
        leaseId: _lease.leaseId,
        holderId: _lease.holderId,
        expectedOwner: durableOwner,
      );
      _synchronize(durable);
      if (recovering) {
        final observed = await _inspectOwner(
          ownerProbe: ownerProbe,
          deadline: deadline,
          wallDeadline: wallDeadline,
        );
        if (observed != null) {
          return await _completeVerifiedHandoff(
            observed: observed,
            expectedOwner: expectedOwner,
            durableOwner: durableOwner,
          );
        }
        if (_phase == CockpitDurablePortPhase.handedOff) {
          await _quarantine(
            'portOwnerMissing',
            'Verified loopback port owner disappeared during recovery.',
          );
          throw const CockpitLeaseException(
            code: 'portOwnerMissing',
            message:
                'Verified loopback port owner disappeared during recovery.',
          );
        }
      }
      await _socket?.close();
      _socket = null;
      await cockpitRaceDeadline<void>(
        operation: binder.bind(
          CockpitPortBindRequest(
            address: InternetAddress.loopbackIPv4,
            port: port,
            handoffToken: _handoffToken,
            deadline: wallDeadline,
          ),
        ),
        clock: _clock,
        deadline: deadline,
      );
      while (true) {
        final observed = await _inspectOwner(
          ownerProbe: ownerProbe,
          deadline: deadline,
          wallDeadline: wallDeadline,
        );
        if (observed != null) {
          return await _completeVerifiedHandoff(
            observed: observed,
            expectedOwner: expectedOwner,
            durableOwner: durableOwner,
          );
        }
        if (deadline.isExpired) throw const CockpitDeadlineExceeded();
        await _clock.delay(deadline.clamp(_probeInterval));
      }
    } on CockpitLeaseException catch (error) {
      if (error.code == 'portOwnerMismatch' ||
          error.code == 'portOwnerMissing' ||
          error.code == 'portHandoffLeaseExpired' ||
          error.code == 'portOwnerConflict' ||
          error.code == 'workspaceNotActive' ||
          error.code == 'leaseAuthorityChanged') {
        rethrow;
      }
      await _quarantine(
        'portHandoffFailed',
        'Controlled port handoff failed before owner verification.',
      );
      throw const CockpitLeaseException(
        code: 'portHandoffFailed',
        message: 'Controlled port handoff failed before owner verification.',
      );
    } on CockpitDeadlineExceeded {
      await _quarantine(
        'portHandoffTimeout',
        'Controlled port handoff exceeded its bounded deadline.',
      );
      throw const CockpitLeaseException(
        code: 'portHandoffTimeout',
        message: 'Controlled port handoff exceeded its bounded deadline.',
      );
    } on Object catch (error) {
      await _quarantine(
        'portHandoffFailed',
        'Controlled port handoff failed before owner verification.',
      );
      throw CockpitLeaseException(
        code: 'portHandoffFailed',
        message:
            'Controlled port handoff failed before owner verification: $error',
      );
    }
  }

  Future<CockpitObservedPortOwner?> _inspectOwner({
    required CockpitPortOwnerProbe ownerProbe,
    required CockpitMonotonicDeadline deadline,
    required DateTime wallDeadline,
  }) async {
    try {
      return await cockpitRaceDeadline<CockpitObservedPortOwner?>(
        operation: ownerProbe.inspect(
          address: InternetAddress.loopbackIPv4,
          port: port,
          deadline: wallDeadline,
        ),
        clock: _clock,
        deadline: deadline,
      );
    } on SocketException {
      return null;
    }
  }

  Future<CockpitVerifiedPortLease> _completeVerifiedHandoff({
    required CockpitObservedPortOwner observed,
    required CockpitExpectedPortOwner expectedOwner,
    required CockpitDurablePortOwner durableOwner,
  }) async {
    if (!observed.matches(expectedOwner, _handoffToken)) {
      await _quarantine(
        'portOwnerMismatch',
        'Loopback port was bound by an unexpected owner.',
      );
      throw const CockpitLeaseException(
        code: 'portOwnerMismatch',
        message: 'Loopback port was bound by an unexpected owner.',
      );
    }
    final durable = await _leases.completePortHandoff(
      leaseId: _lease.leaseId,
      holderId: _lease.holderId,
      expectedOwner: durableOwner,
    );
    _synchronize(durable);
    final verified = CockpitVerifiedPortLease._(
      lease: _lease,
      leases: _leases,
      onUpdate: _onVerifiedLeaseUpdate,
    );
    _verifiedLease = verified;
    _state = CockpitPortReservationState.handedOff;
    return verified;
  }

  Future<CockpitLeaseResource> release() async {
    while (_transition != null) {
      await _transition;
    }
    if (_state == CockpitPortReservationState.released) return _lease;
    final operation = _performRelease();
    _transition = operation;
    try {
      return await operation;
    } finally {
      if (identical(_transition, operation)) _transition = null;
    }
  }

  Future<CockpitLeaseResource> relinquish() async {
    while (_transition != null) {
      await _transition;
    }
    if (_state == CockpitPortReservationState.released) return _lease;
    if (_state != CockpitPortReservationState.handedOff ||
        _verifiedLease == null) {
      throw CockpitLeaseException(
        code: 'portHandoffRelinquishInvalid',
        message: 'Only a verified port handoff can be relinquished.',
        lease: _lease,
      );
    }
    final operation = _verifiedLease!.relinquish();
    _transition = operation;
    try {
      return await operation;
    } finally {
      if (identical(_transition, operation)) _transition = null;
    }
  }

  Future<CockpitLeaseResource> _performRelease() async {
    await _socket?.close();
    _socket = null;
    if (_verifiedLease != null) {
      return _verifiedLease!.release();
    }
    _lease = await _leases.release(_lease.leaseId, holderId: _lease.holderId);
    _state = _lease.state == CockpitLeaseState.released
        ? CockpitPortReservationState.released
        : CockpitPortReservationState.quarantined;
    if (_state == CockpitPortReservationState.released) _terminal();
    return _lease;
  }

  void _onVerifiedLeaseUpdate(CockpitLeaseResource lease) {
    _lease = lease;
    if (lease.state == CockpitLeaseState.released) {
      _state = CockpitPortReservationState.released;
      _terminal();
    } else if (lease.state == CockpitLeaseState.quarantined) {
      _state = CockpitPortReservationState.quarantined;
      _terminal();
    }
  }

  Future<void> _quarantine(String code, String message) async {
    _lease = await _leases.quarantine(
      _lease.leaseId,
      holderId: _lease.holderId,
      failure: _portFailure(code, message),
    );
    _onVerifiedLeaseUpdate(_lease);
  }
}

final class CockpitVerifiedPortLease {
  CockpitVerifiedPortLease._({
    required CockpitLeaseResource lease,
    required CockpitLeaseRegistry leases,
    required void Function(CockpitLeaseResource lease) onUpdate,
  }) : _lease = lease,
       _leases = leases,
       _onUpdate = onUpdate;

  CockpitLeaseResource _lease;
  final CockpitLeaseRegistry _leases;
  final void Function(CockpitLeaseResource lease) _onUpdate;

  int get port =>
      CockpitLoopbackPortCleanupProbe.parseResourceId(_lease.resourceId);
  CockpitLeaseResource get lease => _lease;

  Future<CockpitLeaseResource> heartbeat() async {
    _lease = await _leases.heartbeat(_lease.leaseId, holderId: _lease.holderId);
    _onUpdate(_lease);
    return _lease;
  }

  Future<CockpitLeaseResource> renew(Duration ttl) async {
    _lease = await _leases.renew(
      _lease.leaseId,
      holderId: _lease.holderId,
      ttl: ttl,
    );
    _onUpdate(_lease);
    return _lease;
  }

  Future<CockpitLeaseResource> release() async {
    _lease = await _leases.release(_lease.leaseId, holderId: _lease.holderId);
    _onUpdate(_lease);
    return _lease;
  }

  Future<CockpitLeaseResource> relinquish() async {
    _lease = await _leases.relinquishPortHandoff(
      leaseId: _lease.leaseId,
      holderId: _lease.holderId,
    );
    _onUpdate(_lease);
    return _lease;
  }
}

CockpitFailure _portFailure(String code, String message) => CockpitFailure(
  primary: CockpitApiError(
    code: code,
    category: CockpitErrorCategory.resource,
    message: message,
    retryable: true,
    responsibleLayer: CockpitResponsibleLayer.supervisor,
  ),
);
