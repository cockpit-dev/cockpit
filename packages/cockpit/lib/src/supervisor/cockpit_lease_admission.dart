part of 'cockpit_lease_registry.dart';

extension CockpitLeaseAdmissionOperations on CockpitLeaseRegistry {
  Future<R> withActiveWorkspaceAdmission<R>(
    String workspaceId,
    Future<R> Function() action,
  ) async {
    final initialScope = await _workspaceAuthority.resolveActive(workspaceId);
    return _admissionLocks.run(
      <String>{initialScope.rootId},
      <String>{workspaceId},
      () async {
        final currentScope = await _workspaceAuthority.resolveActive(
          workspaceId,
        );
        if (currentScope.rootId != initialScope.rootId ||
            currentScope.workspaceId != initialScope.workspaceId) {
          throw const CockpitLeaseException(
            code: 'leaseAuthorityChanged',
            message: 'Workspace lease authority changed during admission.',
          );
        }
        return action();
      },
    );
  }

  Future<CockpitLeaseResource> acquire(
    CockpitLeaseRequest request, {
    CockpitLeaseCancellationSignal? cancellation,
    String? handoffToken,
  }) async {
    _cleanupProbes.resolve(request.resourceKind);
    if (handoffToken != null &&
        (request.resourceKind != CockpitLeaseResourceKind.forwardedPort ||
            !cockpitIsValidPortHandoffToken(handoffToken) ||
            !cockpitIsValidLoopbackPortResource(request.resourceId))) {
      throw const CockpitLeaseException(
        code: 'invalidPortHandoff',
        message: 'Port handoff metadata is invalid.',
      );
    }
    if (cancellation?.isCancelled ?? false) {
      throw const CockpitLeaseException(
        code: 'leaseCancelled',
        message: 'Lease acquisition was cancelled before admission.',
      );
    }
    final admitted = await withActiveWorkspaceAdmission(
      request.workspaceId,
      () async {
        if (cancellation?.isCancelled ?? false) {
          throw const CockpitLeaseException(
            code: 'leaseCancelled',
            message: 'Lease acquisition was cancelled during admission.',
          );
        }
        return _submit(request, handoffToken);
      },
    );
    if (cancellation?.isCancelled ?? false) {
      return _cancelWaitingLease(admitted.leaseId, request.holderId);
    }
    if (admitted.state == CockpitLeaseState.active) return admitted;
    return _waitForAdmission(admitted.leaseId, request, cancellation);
  }

  Future<CockpitLeaseResource> _submit(
    CockpitLeaseRequest request,
    String? handoffToken,
  ) => _database.transact<CockpitLeaseResource>((state) async {
    final now = _now;
    _pruneReleased(state, now);
    _expireDue(state, now);
    final matches = state.leases
        .where(
          (record) =>
              record.workspaceId == request.workspaceId &&
              record.idempotencyKey == request.idempotencyKey.value,
        )
        .toList();
    late final CockpitLeaseRecord record;
    if (matches.isNotEmpty) {
      if (matches.length != 1 ||
          !matches.single.matchesRequest(request, handoffToken: handoffToken)) {
        throw const CockpitLeaseException(
          code: 'idempotencyConflict',
          message:
              'Idempotency key was already used for another lease request.',
        );
      }
      record = matches.single;
    } else {
      final quarantined = state.leases
          .where(
            (candidate) =>
                candidate.resourceKind == request.resourceKind &&
                candidate.resourceId == request.resourceId &&
                candidate.state == CockpitLeaseState.quarantined,
          )
          .firstOrNull;
      if (quarantined != null) {
        throw CockpitLeaseException(
          code: 'resourceQuarantined',
          message: 'Lease resource is quarantined.',
          lease: _resource(state, quarantined),
        );
      }
      record = CockpitLeaseRecord(
        leaseId: _newId(state, CockpitIdKind.lease),
        workspaceId: request.workspaceId,
        resourceKind: request.resourceKind,
        resourceId: request.resourceId,
        holderId: request.holderId,
        idempotencyKey: request.idempotencyKey.value,
        waitTimeoutMs: request.waitTimeoutMs,
        ttlMs: request.ttlMs,
        sequence: state.nextSequence,
        state: CockpitLeaseState.queued,
        requestedAt: now,
        handoffToken: handoffToken,
        portPhase: handoffToken == null
            ? null
            : CockpitDurablePortPhase.reserved,
      );
      state.nextSequence += 1;
      state.leases.add(record);
    }
    _grantAvailable(state, now);
    final current = state.byId(record.leaseId);
    return CockpitLockedJsonUpdate.write(state, _resource(state, current));
  });

  Future<R?> replayPortReservation<R>({
    required String workspaceId,
    required CockpitIdempotencyKey idempotencyKey,
    required FutureOr<R> Function(CockpitDurablePortReservation reservation)
    replay,
  }) async {
    return withActiveWorkspaceAdmission(workspaceId, () async {
      final reservation = await _findPortReservation(
        workspaceId: workspaceId,
        idempotencyKey: idempotencyKey,
      );
      if (reservation == null) return null;
      return replay(reservation);
    });
  }

  Future<CockpitDurablePortReservation?> _findPortReservation({
    required String workspaceId,
    required CockpitIdempotencyKey idempotencyKey,
  }) => _database.transact<CockpitDurablePortReservation?>((state) async {
    final now = _now;
    _pruneReleased(state, now);
    _expireDue(state, now);
    _grantAvailable(state, now);
    final matches = state.leases
        .where(
          (record) =>
              record.workspaceId == workspaceId &&
              record.idempotencyKey == idempotencyKey.value,
        )
        .toList();
    if (matches.isEmpty) {
      return CockpitLockedJsonUpdate.write(state, null);
    }
    final record = matches.single;
    if (record.resourceKind != CockpitLeaseResourceKind.forwardedPort ||
        record.handoffToken == null) {
      throw const CockpitLeaseException(
        code: 'idempotencyConflict',
        message: 'Idempotency key belongs to another lease operation.',
      );
    }
    return CockpitLockedJsonUpdate.write(
      state,
      CockpitDurablePortReservation(
        lease: _resource(state, record),
        handoffToken: record.handoffToken!,
        ttlMs: record.ttlMs,
        phase: record.portPhase!,
        expectedOwner: record.portOwner,
      ),
    );
  });

  Future<CockpitLeaseResource> _waitForAdmission(
    String leaseId,
    CockpitLeaseRequest request,
    CockpitLeaseCancellationSignal? cancellation,
  ) async {
    final deadline = request.waitTimeoutMs == 0
        ? null
        : CockpitMonotonicDeadline.after(
            _clock,
            Duration(milliseconds: request.waitTimeoutMs),
          );
    while (true) {
      final current = await get(leaseId);
      if (cancellation?.isCancelled ?? false) {
        return _cancelWaitingLease(leaseId, request.holderId);
      }
      switch (current.state) {
        case CockpitLeaseState.active:
          return current;
        case CockpitLeaseState.queued:
          break;
        case CockpitLeaseState.quarantined:
          throw CockpitLeaseException(
            code: 'resourceQuarantined',
            message: 'Lease resource is quarantined.',
            lease: current,
          );
        case CockpitLeaseState.releasing || CockpitLeaseState.expired:
          break;
        case CockpitLeaseState.released:
          throw CockpitLeaseException(
            code: 'resourceBusy',
            message: 'Lease wait ended before the resource became available.',
            lease: current,
          );
      }
      if (deadline == null || deadline.isExpired) {
        return _timeoutWaitingLease(leaseId, request.holderId);
      }
      final delay = deadline.clamp(_pollInterval);
      final recovery = await _beginResourceRecovery(
        request.resourceKind,
        request.resourceId,
        includeQuarantined: false,
      );
      final waits = <Future<void>>[_clock.delay(delay)];
      if (recovery != null) waits.add(recovery);
      if (cancellation != null) waits.add(cancellation.whenCancelled);
      await Future.any<void>(waits);
    }
  }

  Future<CockpitLeaseResource> _timeoutWaitingLease(
    String leaseId,
    String holderId,
  ) async {
    final current = await _finishQueuedWait(leaseId, holderId);
    if (current.state == CockpitLeaseState.active) return current;
    throw CockpitLeaseException(
      code: 'resourceBusy',
      message: 'Lease wait timeout expired.',
      lease: current,
    );
  }

  Future<CockpitLeaseResource> _cancelWaitingLease(
    String leaseId,
    String holderId,
  ) async {
    final current = await cancel(leaseId, holderId: holderId);
    throw CockpitLeaseException(
      code: 'leaseCancelled',
      message: 'Lease acquisition was cancelled.',
      lease: current,
    );
  }
}
