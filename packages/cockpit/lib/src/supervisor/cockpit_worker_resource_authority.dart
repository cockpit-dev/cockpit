import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_ids.dart';
import '../worker/cockpit_worker_resource_grant.dart';
import '../worker/cockpit_worker_value_reader.dart';
import 'cockpit_lease_registry.dart';
import 'cockpit_port_models.dart';
import 'cockpit_safe_port_allocator.dart';
import 'cockpit_supervisor_worker_port_bridge.dart';

abstract interface class CockpitSupervisorWorkerResourceAuthority {
  Future<CockpitOperationResult> execute(CockpitOperationInvocation invocation);
}

final class CockpitLeaseWorkerResourceAuthority
    implements CockpitSupervisorWorkerResourceAuthority {
  CockpitLeaseWorkerResourceAuthority({
    required this.workspaceId,
    required CockpitLeaseRegistry leases,
    required CockpitSafePortAllocator ports,
    required CockpitSupervisorWorkerPortBridge portBridge,
    CockpitTokenGenerator? tokenGenerator,
    DateTime Function()? utcNow,
  }) : _leases = leases,
       _ports = ports,
       _portBridge = portBridge,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
  }

  final String workspaceId;
  final CockpitLeaseRegistry _leases;
  final CockpitSafePortAllocator _ports;
  final CockpitSupervisorWorkerPortBridge _portBridge;
  final CockpitTokenGenerator _tokenGenerator;
  final DateTime Function() _utcNow;
  final Map<String, _AuthorityGrant> _grants = <String, _AuthorityGrant>{};
  final Map<String, Future<Map<String, Object?>>> _releaseOperations =
      <String, Future<Map<String, Object?>>>{};

  @override
  Future<CockpitOperationResult> execute(
    CockpitOperationInvocation invocation,
  ) async {
    if (invocation.workspaceId != workspaceId || invocation.rootId != null) {
      throw const FormatException('Resource authority workspace mismatch.');
    }
    final submittedAt = _utcNow();
    final operationId = _newId('resource-operation');
    final output = switch (invocation.kind) {
      'resource.acquire' => await _acquire(invocation),
      'resource.handoff' => await _handoff(invocation),
      'resource.heartbeat' => await _heartbeat(invocation),
      'resource.release' => await _release(invocation),
      _ => throw const FormatException('Unknown resource authority operation.'),
    };
    final finishedAt = _utcNow();
    return CockpitOperationResult(
      operationId: operationId,
      kind: invocation.kind,
      workspaceId: workspaceId,
      lifecycle: CockpitOperationLifecycle.completed,
      outcome: CockpitOperationOutcome.succeeded,
      submittedAt: submittedAt,
      startedAt: submittedAt,
      finishedAt: finishedAt,
      output: output,
    );
  }

  Future<Map<String, Object?>> _acquire(
    CockpitOperationInvocation invocation,
  ) async {
    final input = workerObject(invocation.input, r'$.input');
    workerKeys(
      input,
      const <String>{
        'resourceKind',
        'resourceId',
        'requiresPort',
        'ttlMs',
        'holderId',
      },
      r'$.input',
      required: const <String>{
        'resourceKind',
        'resourceId',
        'requiresPort',
        'ttlMs',
        'holderId',
      },
    );
    final kind = _resourceKind(input['resourceKind']);
    final resourceId = workerString(
      input['resourceId'],
      r'$.input.resourceId',
      maximum: 512,
    );
    final holderId = workerId(input['holderId'], r'$.input.holderId');
    final ttlMs = workerInteger(
      input['ttlMs'],
      r'$.input.ttlMs',
      minimum: 1000,
      maximum: 300000,
    );
    final requiresPort = workerBoolean(
      input['requiresPort'],
      r'$.input.requiresPort',
    );
    final key = invocation.idempotencyKey;
    if (key == null) {
      throw const FormatException('Resource acquisition requires idempotency.');
    }
    CockpitLeaseResource lease;
    CockpitPortReservation? reservation;
    if (requiresPort) {
      if (kind != CockpitLeaseResourceKind.forwardedPort) {
        throw const FormatException('Port resource kind is inconsistent.');
      }
      reservation = await _ports.reserve(
        workspaceId: workspaceId,
        holderId: holderId,
        idempotencyKey: key,
        ttl: Duration(milliseconds: ttlMs),
      );
      lease = reservation.lease;
    } else {
      lease = await _leases.acquire(
        CockpitLeaseRequest(
          workspaceId: workspaceId,
          resourceKind: kind,
          resourceId: resourceId,
          holderId: holderId,
          idempotencyKey: key,
          waitTimeoutMs: _waitTimeout(invocation.deadline),
          ttlMs: ttlMs,
        ),
      );
    }
    final expiresAt = lease.expiresAt;
    if (expiresAt == null || lease.state != CockpitLeaseState.active) {
      throw const FormatException('Resource lease is not active.');
    }
    final grantId = _newId('grant');
    final grant = CockpitWorkerResourceGrant(
      grantId: grantId,
      leaseId: lease.leaseId,
      workspaceId: workspaceId,
      holderId: holderId,
      resourceKind: kind,
      resourceId: resourceId,
      expiresAt: expiresAt,
      port: reservation?.port,
      handoffToken: reservation?.handoffToken,
    );
    _grants[grantId] = _AuthorityGrant(grant, reservation);
    return <String, Object?>{'grant': grant.toJson()};
  }

  Future<Map<String, Object?>> _heartbeat(
    CockpitOperationInvocation invocation,
  ) async {
    final active = _grant(invocation.input);
    final lease = await _leases.heartbeat(
      active.grant.leaseId,
      holderId: active.grant.holderId,
    );
    final refreshed = CockpitWorkerResourceGrant(
      grantId: active.grant.grantId,
      leaseId: lease.leaseId,
      workspaceId: workspaceId,
      holderId: lease.holderId,
      resourceKind: lease.resourceKind,
      resourceId: active.grant.resourceId,
      expiresAt: lease.expiresAt!,
      port: active.grant.port,
      handoffToken: active.grant.handoffToken,
    );
    _grants[refreshed.grantId] = _AuthorityGrant(refreshed, active.reservation);
    return <String, Object?>{'grant': refreshed.toJson()};
  }

  Future<Map<String, Object?>> _handoff(
    CockpitOperationInvocation invocation,
  ) async {
    final input = workerObject(invocation.input, r'$.input');
    workerKeys(
      input,
      const <String>{
        'grantId',
        'ownerId',
        'processId',
        'processStartIdentity',
        'sessionId',
      },
      r'$.input',
      required: const <String>{
        'grantId',
        'ownerId',
        'processId',
        'processStartIdentity',
        'sessionId',
      },
    );
    final grantId = workerId(input['grantId'], r'$.input.grantId');
    final active = _grants[grantId];
    final reservation = active?.reservation;
    if (active == null || reservation == null) {
      throw const FormatException(
        'Forwarded-port handoff grant is stale or invalid.',
      );
    }
    final expectedOwner = CockpitExpectedPortOwner(
      ownerId: workerId(input['ownerId'], r'$.input.ownerId'),
      processId: workerInteger(
        input['processId'],
        r'$.input.processId',
        minimum: 1,
      ),
      processStartIdentity: workerString(
        input['processStartIdentity'],
        r'$.input.processStartIdentity',
        maximum: 512,
      ),
      sessionId: workerId(input['sessionId'], r'$.input.sessionId'),
    );
    if (expectedOwner.sessionId != active.grant.holderId) {
      throw const FormatException('Port handoff session owner is invalid.');
    }
    _portBridge.validateExpectedOwner(grantId, expectedOwner);
    final remaining = invocation.deadline?.difference(_utcNow());
    if (remaining == null || remaining <= Duration.zero) {
      throw const FormatException('Port handoff deadline has expired.');
    }
    final timeout = remaining > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : remaining;
    final verified = await reservation.handoff(
      binder: _portBridge.binderFor(grantId),
      ownerProbe: _portBridge.ownerProbeFor(grantId),
      expectedOwner: expectedOwner,
      timeout: timeout,
    );
    final lease = verified.lease;
    final refreshed = CockpitWorkerResourceGrant(
      grantId: active.grant.grantId,
      leaseId: lease.leaseId,
      workspaceId: workspaceId,
      holderId: lease.holderId,
      resourceKind: lease.resourceKind,
      resourceId: active.grant.resourceId,
      expiresAt: lease.expiresAt!,
      port: active.grant.port,
      handoffToken: active.grant.handoffToken,
    );
    _grants[grantId] = _AuthorityGrant(refreshed, reservation);
    return <String, Object?>{'verified': true, 'grant': refreshed.toJson()};
  }

  Future<Map<String, Object?>> _release(
    CockpitOperationInvocation invocation,
  ) async {
    final input = workerObject(invocation.input, r'$.input');
    workerKeys(
      input,
      const <String>{'grantId', 'cancel'},
      r'$.input',
      required: const <String>{'grantId', 'cancel'},
    );
    final grantId = workerId(input['grantId'], r'$.input.grantId');
    final cancel = workerBoolean(input['cancel'], r'$.input.cancel');
    final inFlight = _releaseOperations[grantId];
    if (inFlight != null) return inFlight;
    late final Future<Map<String, Object?>> operation;
    operation = _releaseGrant(grantId, cancel: cancel).whenComplete(() {
      if (identical(_releaseOperations[grantId], operation)) {
        _releaseOperations.remove(grantId);
      }
    });
    _releaseOperations[grantId] = operation;
    return operation;
  }

  Future<Map<String, Object?>> _releaseGrant(
    String grantId, {
    required bool cancel,
  }) async {
    final active = _grants[grantId];
    if (active == null) {
      return <String, Object?>{'released': true, 'alreadyTerminal': true};
    }
    if (active.reservation != null) {
      final reservation = active.reservation!;
      if (!cancel &&
          reservation.state == CockpitPortReservationState.handedOff) {
        await reservation.relinquish();
      } else {
        await reservation.release();
      }
    } else if (cancel) {
      await _leases.cancel(
        active.grant.leaseId,
        holderId: active.grant.holderId,
      );
    } else {
      await _leases.release(
        active.grant.leaseId,
        holderId: active.grant.holderId,
      );
    }
    if (identical(_grants[grantId], active)) {
      _grants.remove(grantId);
    }
    return <String, Object?>{'released': true, 'alreadyTerminal': false};
  }

  _AuthorityGrant _grant(Map<String, Object?> input) {
    workerKeys(
      input,
      const <String>{'grantId'},
      r'$.input',
      required: const <String>{'grantId'},
    );
    final grantId = workerId(input['grantId'], r'$.input.grantId');
    final grant = _grants[grantId];
    if (grant == null) throw const FormatException('Resource grant is stale.');
    return grant;
  }

  CockpitLeaseResourceKind _resourceKind(Object? value) {
    final name = workerString(value, r'$.input.resourceKind', maximum: 64);
    final matches = CockpitLeaseResourceKind.values
        .where((kind) => kind.name == name)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const FormatException('Unknown resource kind.');
    }
    return matches.single;
  }

  int _waitTimeout(DateTime? deadline) {
    if (deadline == null) return 0;
    return deadline.difference(_utcNow()).inMilliseconds.clamp(0, 300000);
  }

  String _newId(String prefix) =>
      '${prefix}_${_tokenGenerator.nextToken(byteLength: 16)}';
}

final class _AuthorityGrant {
  const _AuthorityGrant(this.grant, this.reservation);

  final CockpitWorkerResourceGrant grant;
  final CockpitPortReservation? reservation;
}
