part of 'cockpit_lease_registry.dart';

extension CockpitPortLeaseLifecycleOperations on CockpitLeaseRegistry {
  Future<CockpitDurablePortReservation> beginPortHandoff({
    required String leaseId,
    required String holderId,
    required CockpitDurablePortOwner expectedOwner,
  }) => _database.transact<CockpitDurablePortReservation>((state) async {
    final now = _now;
    _expireDue(state, now);
    final record = _requireHolder(state, leaseId, holderId);
    if (record.state != CockpitLeaseState.active ||
        record.handoffToken == null ||
        record.portPhase == null) {
      throw CockpitLeaseException(
        code: 'portHandoffLeaseInvalid',
        message: 'Only an active durable port reservation can be handed off.',
        lease: _resource(state, record),
      );
    }
    late final CockpitLeaseRecord updated;
    if (record.portPhase == CockpitDurablePortPhase.reserved) {
      updated = record.copyWith(
        portPhase: CockpitDurablePortPhase.handingOff,
        portOwner: expectedOwner,
      );
      _replace(state, updated);
    } else {
      if (!record.portOwner!.matches(expectedOwner)) {
        throw CockpitLeaseException(
          code: 'portOwnerConflict',
          message: 'Port handoff owner differs from the persisted owner.',
          lease: _resource(state, record),
        );
      }
      updated = record;
    }
    return CockpitLockedJsonUpdate.write(
      state,
      _portReservation(state, updated),
    );
  });

  Future<CockpitDurablePortReservation> completePortHandoff({
    required String leaseId,
    required String holderId,
    required CockpitDurablePortOwner expectedOwner,
  }) => _database.transact<CockpitDurablePortReservation>((state) async {
    final now = _now;
    _expireDue(state, now);
    final record = _requireHolder(state, leaseId, holderId);
    if (record.state != CockpitLeaseState.active ||
        record.portPhase == CockpitDurablePortPhase.reserved ||
        record.portOwner == null ||
        !record.portOwner!.matches(expectedOwner)) {
      throw CockpitLeaseException(
        code: 'portHandoffLeaseInvalid',
        message: 'Port handoff completion does not match durable state.',
        lease: _resource(state, record),
      );
    }
    final updated = record.copyWith(
      portPhase: CockpitDurablePortPhase.handedOff,
      lastHeartbeatAt: now,
      expiresAt: now.add(Duration(milliseconds: record.ttlMs)),
    );
    _replace(state, updated);
    return CockpitLockedJsonUpdate.write(
      state,
      _portReservation(state, updated),
    );
  });

  Future<CockpitLeaseResource> relinquishPortHandoff({
    required String leaseId,
    required String holderId,
  }) => _database.transact<CockpitLeaseResource>((state) async {
    final now = _now;
    _expireDue(state, now);
    final record = _requireHolder(state, leaseId, holderId);
    if (record.state != CockpitLeaseState.active ||
        record.resourceKind != CockpitLeaseResourceKind.forwardedPort ||
        record.portPhase != CockpitDurablePortPhase.handedOff ||
        record.portOwner == null) {
      throw CockpitLeaseException(
        code: 'portHandoffRelinquishInvalid',
        message: 'Only a verified active port handoff can be relinquished.',
        lease: _resource(state, record),
      );
    }
    final released = record.copyWith(
      state: CockpitLeaseState.released,
      releasedAt: now,
      cleanupReason: null,
      cleanupClaimId: null,
      cleanupClaimExpiresAt: null,
      failure: null,
    );
    _replace(state, released);
    _grantAvailable(state, now);
    return CockpitLockedJsonUpdate.write(state, released.toResource());
  });
}
