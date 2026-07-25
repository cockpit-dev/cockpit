part of 'cockpit_lease_registry.dart';

extension CockpitLeaseRecoveryOperations on CockpitLeaseRegistry {
  Future<void> recover() async {
    while (true) {
      final claims = await _claimCleanup(includeQuarantined: false);
      await Future.wait<void>(claims.map(_runCleanup));
      final wait = await _pendingCrashRecoveryWait();
      if (wait == null) return;
      if (wait > Duration.zero) {
        await _clock.delay(wait < _pollInterval ? wait : _pollInterval);
      }
    }
  }

  Future<Duration?> _pendingCrashRecoveryWait() async {
    final state = await _database.read();
    final now = _now;
    Duration? earliest;
    for (final record in state.leases) {
      if (record.state != CockpitLeaseState.releasing &&
          record.state != CockpitLeaseState.expired) {
        continue;
      }
      final claimExpiry = record.cleanupClaimExpiresAt;
      if (claimExpiry == null || !claimExpiry.isAfter(now)) {
        return Duration.zero;
      }
      final remaining = claimExpiry.difference(now);
      final maximum = _cleanupTimeout + _cleanupClaimGrace;
      if (remaining > maximum) {
        throw const CockpitLeaseException(
          code: 'leaseCleanupClaimInvalid',
          message: 'Persisted cleanup claim exceeds its recovery bound.',
        );
      }
      if (earliest == null || remaining < earliest) earliest = remaining;
    }
    return earliest;
  }

  Future<List<CockpitLeaseResource>> recoverResource(
    CockpitLeaseResourceKind resourceKind,
    String resourceId,
  ) async {
    await _recoverResourceInternal(
      resourceKind,
      resourceId,
      includeQuarantined: true,
    );
    return list(resourceKind: resourceKind, resourceId: resourceId);
  }

  Future<CockpitForcedLeaseRelease> forceReleaseQuarantined({
    required String leaseId,
    required String workspaceId,
    required CockpitLeaseResourceKind resourceKind,
    required String resourceId,
    required String holderId,
  }) async {
    if (resourceKind == CockpitLeaseResourceKind.forwardedPort) {
      throw const CockpitLeaseException(
        code: 'leaseForceReleaseForbidden',
        message:
            'Forwarded ports require verified cleanup and cannot be force released.',
      );
    }
    final result = await _database.transact<CockpitForcedLeaseRelease>((
      state,
    ) async {
      final now = _now;
      _pruneReleased(state, now);
      _expireDue(state, now);
      final record = state.byId(leaseId);
      final before = _resource(state, record);
      if (record.workspaceId != workspaceId ||
          record.resourceKind != resourceKind ||
          record.resourceId != resourceId ||
          record.holderId != holderId) {
        throw CockpitLeaseException(
          code: 'leaseIdentityMismatch',
          message: 'Lease identity does not match the quarantined resource.',
          lease: before,
        );
      }
      if (record.state == CockpitLeaseState.released) {
        return CockpitLockedJsonUpdate.readOnly(
          state,
          CockpitForcedLeaseRelease(
            before: before,
            after: before,
            forceReleased: false,
          ),
        );
      }
      if (record.state != CockpitLeaseState.quarantined) {
        throw CockpitLeaseException(
          code: 'leaseNotQuarantined',
          message: 'Only a quarantined lease can be force released.',
          lease: before,
        );
      }
      if (record.cleanupClaimId != null) {
        throw CockpitLeaseException(
          code: 'leaseRecoveryInProgress',
          message: 'Lease cleanup verification is still in progress.',
          lease: before,
        );
      }
      final released = record.copyWith(
        state: CockpitLeaseState.released,
        releasedAt: now,
        cleanupClaimId: null,
        cleanupClaimExpiresAt: null,
        cleanupReason: null,
        failure: null,
      );
      _replace(state, released);
      _grantAvailable(state, now);
      return CockpitLockedJsonUpdate.write(
        state,
        CockpitForcedLeaseRelease(
          before: before,
          after: released.toResource(),
          forceReleased: true,
        ),
      );
    });
    if (result.after.state == CockpitLeaseState.released) {
      _localCleanup.remove(leaseId);
    }
    return result;
  }

  Future<void> _recoverResourceInternal(
    CockpitLeaseResourceKind resourceKind,
    String resourceId, {
    required bool includeQuarantined,
  }) async {
    final recovery = await _beginResourceRecovery(
      resourceKind,
      resourceId,
      includeQuarantined: includeQuarantined,
    );
    if (recovery != null) await recovery;
  }

  Future<Future<void>?> _beginResourceRecovery(
    CockpitLeaseResourceKind resourceKind,
    String resourceId, {
    required bool includeQuarantined,
  }) async {
    final claims = await _claimCleanup(
      resourceKind: resourceKind,
      resourceId: resourceId,
      includeQuarantined: includeQuarantined,
    );
    if (claims.isEmpty) return null;
    return Future.wait<void>(claims.map(_runCleanup));
  }

  Future<void> _recoverLease(
    String leaseId, {
    required bool includeQuarantined,
  }) async {
    final claims = await _claimCleanup(
      leaseId: leaseId,
      includeQuarantined: includeQuarantined,
    );
    await Future.wait<void>(claims.map(_runCleanup));
  }

  Future<List<_CockpitLeaseCleanupClaim>> _claimCleanup({
    String? leaseId,
    CockpitLeaseResourceKind? resourceKind,
    String? resourceId,
    required bool includeQuarantined,
  }) => _database.transact<List<_CockpitLeaseCleanupClaim>>((state) async {
    final now = _now;
    _pruneReleased(state, now);
    _expireDue(state, now);
    _grantAvailable(state, now);
    final claims = <_CockpitLeaseCleanupClaim>[];
    for (final record in state.leases.toList()) {
      if (leaseId != null && record.leaseId != leaseId ||
          resourceKind != null && record.resourceKind != resourceKind ||
          resourceId != null && record.resourceId != resourceId ||
          !record.needsCleanup ||
          record.state == CockpitLeaseState.quarantined &&
              !includeQuarantined ||
          record.cleanupClaimExpiresAt?.isAfter(now) == true) {
        continue;
      }
      final claimId = _newId(state, CockpitIdKind.cleanup);
      final cleanupDeadline = now.add(_cleanupTimeout);
      final claimed = record.copyWith(
        cleanupClaimId: claimId,
        cleanupClaimExpiresAt: cleanupDeadline.add(_cleanupClaimGrace),
        cleanupReason: record.state == CockpitLeaseState.quarantined
            ? CockpitLeaseCleanupReason.recovery
            : record.cleanupReason,
      );
      _replace(state, claimed);
      claims.add(
        _CockpitLeaseCleanupClaim(
          record: claimed,
          claimId: claimId,
          deadline: cleanupDeadline,
        ),
      );
    }
    return CockpitLockedJsonUpdate.write(state, claims);
  });

  Future<void> _runCleanup(_CockpitLeaseCleanupClaim claim) async {
    CockpitLeaseCleanupResult result;
    try {
      final probe = _cleanupProbes.resolve(claim.record.resourceKind);
      final context = CockpitLeaseCleanupContext(
        leaseId: claim.record.leaseId,
        workspaceId: claim.record.workspaceId,
        resourceKind: claim.record.resourceKind,
        resourceId: claim.record.resourceId,
        holderId: claim.record.holderId,
        reason: claim.record.cleanupReason!,
        deadline: claim.deadline,
      );
      final localCleanup = _localCleanup.remove(claim.record.leaseId);
      final cleanup = () async {
        await localCleanup?.call();
        return probe.cleanupAndVerify(context);
      }();
      result = await Future.any<CockpitLeaseCleanupResult>(
        <Future<CockpitLeaseCleanupResult>>[
          cleanup,
          _clock
              .delay(_cleanupTimeout)
              .then(
                (_) => CockpitLeaseCleanupResult.quarantined(
                  _cleanupFailure(
                    'leaseCleanupTimeout',
                    'Resource cleanup exceeded its bounded deadline.',
                  ),
                ),
              ),
        ],
      );
      result.validate();
    } on Object {
      result = CockpitLeaseCleanupResult.quarantined(
        _cleanupFailure('leaseCleanupFailed', 'Resource cleanup probe failed.'),
      );
    }
    await _completeCleanup(claim, result);
  }

  Future<void> _completeCleanup(
    _CockpitLeaseCleanupClaim claim,
    CockpitLeaseCleanupResult result,
  ) => _database.transact<void>((state) async {
    final record = state.byId(claim.record.leaseId);
    if (record.cleanupClaimId != claim.claimId || !record.needsCleanup) {
      return CockpitLockedJsonUpdate.readOnly(state, null);
    }
    final now = _now;
    if (result.restored) {
      final released = record.copyWith(
        state: CockpitLeaseState.released,
        releasedAt: now,
        cleanupClaimId: null,
        cleanupClaimExpiresAt: null,
        cleanupReason: null,
        failure: null,
      );
      _replace(state, released);
      _grantAvailable(state, now);
    } else {
      _replace(
        state,
        record.copyWith(
          state: CockpitLeaseState.quarantined,
          cleanupClaimId: null,
          cleanupClaimExpiresAt: null,
          failure: result.failure,
        ),
      );
    }
    return CockpitLockedJsonUpdate.write(state, null);
  });
}

final class CockpitForcedLeaseRelease {
  const CockpitForcedLeaseRelease({
    required this.before,
    required this.after,
    required this.forceReleased,
  });

  final CockpitLeaseResource before;
  final CockpitLeaseResource after;
  final bool forceReleased;
}

final class _CockpitLeaseCleanupClaim {
  const _CockpitLeaseCleanupClaim({
    required this.record,
    required this.claimId,
    required this.deadline,
  });

  final CockpitLeaseRecord record;
  final String claimId;
  final DateTime deadline;
}
