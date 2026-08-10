part of 'cockpit_lease_registry.dart';

extension CockpitLeaseLifecycleOperations on CockpitLeaseRegistry {
  Future<CockpitLeaseResource> heartbeat(
    String leaseId, {
    required String holderId,
  }) async {
    final current = await _renewInternal(leaseId, holderId, ttl: null);
    if (current.state != CockpitLeaseState.active) {
      await _recoverLease(leaseId, includeQuarantined: false);
      throw CockpitLeaseException(
        code: 'leaseNotActive',
        message: 'Only an active unexpired lease can heartbeat.',
        lease: current,
      );
    }
    return current;
  }

  Future<CockpitLeaseResource> renew(
    String leaseId, {
    required String holderId,
    required Duration ttl,
  }) async {
    if (ttl < const Duration(seconds: 1) ||
        ttl > const Duration(milliseconds: cockpitMaximumLeaseTtlMs)) {
      throw const CockpitLeaseException(
        code: 'invalidLeaseTtl',
        message: 'Lease TTL must be between one second and thirty minutes.',
      );
    }
    final current = await _renewInternal(leaseId, holderId, ttl: ttl);
    if (current.state != CockpitLeaseState.active) {
      await _recoverLease(leaseId, includeQuarantined: false);
      throw CockpitLeaseException(
        code: 'leaseNotActive',
        message: 'Only an active unexpired lease can be renewed.',
        lease: current,
      );
    }
    return current;
  }

  Future<CockpitLeaseResource> _renewInternal(
    String leaseId,
    String holderId, {
    required Duration? ttl,
  }) => _database.transact<CockpitLeaseResource>((state) async {
    final now = _now;
    _expireDue(state, now);
    final record = _requireHolder(state, leaseId, holderId);
    if (record.state != CockpitLeaseState.active) {
      return CockpitLockedJsonUpdate.write(state, _resource(state, record));
    }
    final duration = ttl ?? Duration(milliseconds: record.ttlMs);
    final renewed = record.copyWith(
      lastHeartbeatAt: now,
      expiresAt: now.add(duration),
    );
    _replace(state, renewed);
    return CockpitLockedJsonUpdate.write(state, renewed.toResource());
  });

  Future<CockpitLeaseResource> release(
    String leaseId, {
    required String holderId,
  }) => _endLease(leaseId, holderId, CockpitLeaseCleanupReason.release);

  Future<CockpitLeaseResource> cancel(
    String leaseId, {
    required String holderId,
  }) => _endLease(leaseId, holderId, CockpitLeaseCleanupReason.cancellation);

  Future<CockpitLeaseResource> _endLease(
    String leaseId,
    String holderId,
    CockpitLeaseCleanupReason reason,
  ) async {
    final started = await _database.transact<CockpitLeaseResource>((
      state,
    ) async {
      final now = _now;
      _expireDue(state, now);
      final record = _requireHolder(state, leaseId, holderId);
      final canReleaseImmediately =
          _cleanupProbes.resolve(record.resourceKind)
              is CockpitImmediateLeaseReleaseProbe;
      late final CockpitLeaseRecord updated;
      switch (record.state) {
        case CockpitLeaseState.queued:
          updated = record.copyWith(
            state: CockpitLeaseState.released,
            releasedAt: now,
          );
          _replace(state, updated);
          _grantAvailable(state, now);
        case CockpitLeaseState.active:
          updated = canReleaseImmediately
              ? record.copyWith(
                  state: CockpitLeaseState.released,
                  releasedAt: now,
                  cleanupReason: null,
                  cleanupClaimId: null,
                  cleanupClaimExpiresAt: null,
                  failure: null,
                )
              : record.copyWith(
                  state: CockpitLeaseState.releasing,
                  cleanupReason: reason,
                  cleanupClaimId: null,
                  cleanupClaimExpiresAt: null,
                );
          _replace(state, updated);
          if (canReleaseImmediately) _grantAvailable(state, now);
        case CockpitLeaseState.releasing || CockpitLeaseState.expired:
          updated = record;
        case CockpitLeaseState.quarantined || CockpitLeaseState.released:
          updated = record;
      }
      return CockpitLockedJsonUpdate.write(state, _resource(state, updated));
    });
    if (started.state == CockpitLeaseState.releasing ||
        started.state == CockpitLeaseState.expired ||
        started.state == CockpitLeaseState.quarantined) {
      await _recoverLease(
        leaseId,
        includeQuarantined: started.state == CockpitLeaseState.quarantined,
      );
      return get(leaseId);
    }
    return started;
  }

  Future<CockpitLeaseResource> _finishQueuedWait(
    String leaseId,
    String holderId,
  ) => _database.transact<CockpitLeaseResource>((state) async {
    final now = _now;
    _expireDue(state, now);
    final record = _requireHolder(state, leaseId, holderId);
    if (record.state != CockpitLeaseState.queued) {
      return CockpitLockedJsonUpdate.write(state, _resource(state, record));
    }
    final released = record.copyWith(
      state: CockpitLeaseState.released,
      releasedAt: now,
    );
    _replace(state, released);
    _grantAvailable(state, now);
    return CockpitLockedJsonUpdate.write(state, released.toResource());
  });

  Future<CockpitLeaseResource> quarantine(
    String leaseId, {
    required String holderId,
    required CockpitFailure failure,
  }) => _database.transact<CockpitLeaseResource>((state) async {
    final now = _now;
    _expireDue(state, now);
    final record = _requireHolder(state, leaseId, holderId);
    if (record.state == CockpitLeaseState.released) {
      return CockpitLockedJsonUpdate.readOnly(state, record.toResource());
    }
    if (record.state == CockpitLeaseState.queued) {
      throw const CockpitLeaseException(
        code: 'leaseNotActive',
        message: 'A queued lease cannot quarantine a resource.',
      );
    }
    final quarantined = record.copyWith(
      state: CockpitLeaseState.quarantined,
      cleanupClaimId: null,
      cleanupClaimExpiresAt: null,
      cleanupReason: record.cleanupReason ?? CockpitLeaseCleanupReason.recovery,
      failure: failure,
    );
    _replace(state, quarantined);
    return CockpitLockedJsonUpdate.write(state, quarantined.toResource());
  });
}
