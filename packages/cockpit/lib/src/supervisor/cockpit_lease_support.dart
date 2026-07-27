import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

final class CockpitLeaseException implements Exception {
  const CockpitLeaseException({
    required this.code,
    required this.message,
    this.lease,
  });

  final String code;
  final String message;
  final CockpitLeaseResource? lease;

  @override
  String toString() => 'CockpitLeaseException($code): $message';
}

abstract interface class CockpitLeaseCancellationSignal {
  bool get isCancelled;

  Future<void> get whenCancelled;
}

final class CockpitLeaseCancellationToken
    implements CockpitLeaseCancellationSignal {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

enum CockpitLeaseCleanupReason { release, cancellation, expiry, recovery }

final class CockpitLeaseCleanupContext {
  const CockpitLeaseCleanupContext({
    required this.leaseId,
    required this.workspaceId,
    required this.resourceKind,
    required this.resourceId,
    required this.holderId,
    required this.reason,
    required this.deadline,
  });

  final String leaseId;
  final String workspaceId;
  final CockpitLeaseResourceKind resourceKind;
  final String resourceId;
  final String holderId;
  final CockpitLeaseCleanupReason reason;
  final DateTime deadline;
}

final class CockpitLeaseCleanupResult {
  const CockpitLeaseCleanupResult._({required this.restored, this.failure});

  const CockpitLeaseCleanupResult.restored() : this._(restored: true);

  const CockpitLeaseCleanupResult.quarantined(CockpitFailure failure)
    : this._(restored: false, failure: failure);

  final bool restored;
  final CockpitFailure? failure;

  void validate() {
    if (restored == (failure != null)) {
      throw const FormatException(
        'Cleanup result must contain a failure only when quarantine is needed.',
      );
    }
  }
}

abstract interface class CockpitLeaseCleanupProbe {
  Future<CockpitLeaseCleanupResult> cleanupAndVerify(
    CockpitLeaseCleanupContext context,
  );
}

abstract interface class CockpitLeaseCleanupProbeResolver {
  CockpitLeaseCleanupProbe resolve(CockpitLeaseResourceKind resourceKind);
}

final class CockpitLeaseCleanupProbeMap
    implements CockpitLeaseCleanupProbeResolver {
  CockpitLeaseCleanupProbeMap(
    Map<CockpitLeaseResourceKind, CockpitLeaseCleanupProbe> probes,
  ) : _probes = Map<CockpitLeaseResourceKind, CockpitLeaseCleanupProbe>.of(
        probes,
      );

  final Map<CockpitLeaseResourceKind, CockpitLeaseCleanupProbe> _probes;

  @override
  CockpitLeaseCleanupProbe resolve(CockpitLeaseResourceKind resourceKind) {
    final probe = _probes[resourceKind];
    if (probe == null) {
      throw CockpitLeaseException(
        code: 'leaseCleanupProbeMissing',
        message: 'No cleanup probe is registered for ${resourceKind.name}.',
      );
    }
    return probe;
  }
}

final class CockpitLeaseWorkspaceScope {
  const CockpitLeaseWorkspaceScope({
    required this.workspaceId,
    required this.rootId,
  });

  final String workspaceId;
  final String rootId;
}

abstract interface class CockpitLeaseWorkspaceAuthority {
  Future<CockpitLeaseWorkspaceScope> resolveActive(String workspaceId);
}

enum CockpitDurablePortPhase { reserved, handingOff, handedOff }

final class CockpitDurablePortOwner {
  CockpitDurablePortOwner({
    required this.ownerId,
    required this.processId,
    required this.processStartIdentity,
    required this.sessionId,
  }) {
    if (!cockpitIsValidSupervisorId(ownerId) ||
        processId <= 0 ||
        processId > 4294967295 ||
        processStartIdentity.trim().isEmpty ||
        processStartIdentity.length > 512 ||
        !cockpitIsValidSupervisorId(sessionId)) {
      throw const FormatException('Durable port owner is invalid.');
    }
  }

  final String ownerId;
  final int processId;
  final String processStartIdentity;
  final String sessionId;

  bool matches(CockpitDurablePortOwner other) =>
      ownerId == other.ownerId &&
      processId == other.processId &&
      processStartIdentity == other.processStartIdentity &&
      sessionId == other.sessionId;
}

final class CockpitDurablePortReservation {
  CockpitDurablePortReservation({
    required this.lease,
    required this.handoffToken,
    required this.ttlMs,
    required this.phase,
    required this.expectedOwner,
  }) {
    if (lease.resourceKind != CockpitLeaseResourceKind.forwardedPort ||
        !cockpitIsValidPortHandoffToken(handoffToken) ||
        ttlMs < 1000 ||
        ttlMs > cockpitMaximumLeaseTtlMs ||
        (phase == CockpitDurablePortPhase.reserved) !=
            (expectedOwner == null)) {
      throw const FormatException('Durable port reservation is invalid.');
    }
  }

  final CockpitLeaseResource lease;
  final String handoffToken;
  final int ttlMs;
  final CockpitDurablePortPhase phase;
  final CockpitDurablePortOwner? expectedOwner;
}

bool cockpitIsValidSupervisorId(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      !_cockpitIsAsciiLetter(value.codeUnitAt(0))) {
    return false;
  }
  for (final unit in value.codeUnits.skip(1)) {
    if (!_cockpitIsAsciiLetter(unit) &&
        (unit < 48 || unit > 57) &&
        unit != 45 &&
        unit != 46 &&
        unit != 95) {
      return false;
    }
  }
  return true;
}

bool cockpitIsValidPortHandoffToken(String value) {
  if (value.length < 22 || value.length > 128) return false;
  for (final unit in value.codeUnits) {
    final valid =
        unit >= 65 && unit <= 90 ||
        unit >= 97 && unit <= 122 ||
        unit >= 48 && unit <= 57 ||
        unit == 45 ||
        unit == 95;
    if (!valid) return false;
  }
  return true;
}

bool cockpitIsValidLoopbackPortResource(String value) {
  const prefix = 'loopback-v4:';
  if (!value.startsWith(prefix)) return false;
  final digits = value.substring(prefix.length);
  final port = int.tryParse(digits);
  return port != null &&
      port >= 1 &&
      port <= 65535 &&
      port.toString() == digits;
}

bool _cockpitIsAsciiLetter(int unit) =>
    unit >= 65 && unit <= 90 || unit >= 97 && unit <= 122;
