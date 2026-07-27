import 'cockpit_api_error.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';
import 'cockpit_idempotency.dart';

enum CockpitLeaseResourceKind {
  run,
  device,
  session,
  browserContext,
  desktopInput,
  desktopWindow,
  capture,
  recording,
  forwardedPort,
  workspaceMutation,
}

enum CockpitLeaseState {
  queued,
  active,
  releasing,
  released,
  expired,
  quarantined,
}

abstract final class CockpitLeaseStateMachine {
  static bool canTransition(CockpitLeaseState from, CockpitLeaseState to) {
    if (from == to) {
      return true;
    }
    return switch (from) {
      CockpitLeaseState.queued =>
        to == CockpitLeaseState.active || to == CockpitLeaseState.released,
      CockpitLeaseState.active =>
        to == CockpitLeaseState.releasing ||
            to == CockpitLeaseState.expired ||
            to == CockpitLeaseState.quarantined,
      CockpitLeaseState.releasing =>
        to == CockpitLeaseState.released || to == CockpitLeaseState.quarantined,
      CockpitLeaseState.expired =>
        to == CockpitLeaseState.released || to == CockpitLeaseState.quarantined,
      CockpitLeaseState.quarantined => to == CockpitLeaseState.released,
      CockpitLeaseState.released => false,
    };
  }
}

final class CockpitLeaseRequest {
  CockpitLeaseRequest({
    required this.workspaceId,
    required this.resourceKind,
    required this.resourceId,
    required this.holderId,
    required this.idempotencyKey,
    this.waitTimeoutMs = 30000,
    this.ttlMs = 30000,
  }) {
    CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    CockpitFoundationValueReader.string(
      resourceId,
      r'$.resourceId',
      maximum: 512,
    );
    CockpitFoundationValueReader.id(holderId, r'$.holderId');
    if (waitTimeoutMs < 0 ||
        waitTimeoutMs > 300000 ||
        ttlMs < 1000 ||
        ttlMs > cockpitMaximumLeaseTtlMs) {
      throw const FormatException('Lease timeout is invalid.');
    }
  }

  final String workspaceId;
  final CockpitLeaseResourceKind resourceKind;
  final String resourceId;
  final String holderId;
  final CockpitIdempotencyKey idempotencyKey;
  final int waitTimeoutMs;
  final int ttlMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'resourceKind': resourceKind.name,
    'resourceId': resourceId,
    'holderId': holderId,
    'idempotencyKey': idempotencyKey.toJson(),
    'waitTimeoutMs': waitTimeoutMs,
    'ttlMs': ttlMs,
  };

  factory CockpitLeaseRequest.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'workspaceId',
      'resourceKind',
      'resourceId',
      'holderId',
      'idempotencyKey',
      'waitTimeoutMs',
      'ttlMs',
    };
    CockpitFoundationValueReader.keys(json, fields, path, required: fields);
    return CockpitLeaseRequest(
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      resourceKind: _enum(
        json['resourceKind'],
        CockpitLeaseResourceKind.values,
        '$path.resourceKind',
      ),
      resourceId: CockpitFoundationValueReader.string(
        json['resourceId'],
        '$path.resourceId',
        maximum: 512,
      ),
      holderId: CockpitFoundationValueReader.id(
        json['holderId'],
        '$path.holderId',
      ),
      idempotencyKey: CockpitIdempotencyKey.fromJson(
        json['idempotencyKey'],
        path: '$path.idempotencyKey',
      ),
      waitTimeoutMs: CockpitFoundationValueReader.integer(
        json['waitTimeoutMs'],
        '$path.waitTimeoutMs',
        min: 0,
        max: 300000,
      ),
      ttlMs: CockpitFoundationValueReader.integer(
        json['ttlMs'],
        '$path.ttlMs',
        min: 1000,
        max: cockpitMaximumLeaseTtlMs,
      ),
    );
  }
}

final class CockpitLeaseResource {
  CockpitLeaseResource({
    required this.leaseId,
    required this.workspaceId,
    required this.resourceKind,
    required this.resourceId,
    required this.holderId,
    required this.state,
    required this.requestedAt,
    this.acquiredAt,
    this.expiresAt,
    this.releasedAt,
    this.queuePosition,
    this.failure,
  }) {
    CockpitFoundationValueReader.id(leaseId, r'$.leaseId');
    CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    CockpitFoundationValueReader.string(
      resourceId,
      r'$.resourceId',
      maximum: 512,
    );
    CockpitFoundationValueReader.id(holderId, r'$.holderId');
    CockpitFoundationValueReader.utcDateTime(requestedAt, r'$.requestedAt');
    for (final entry in <String, DateTime?>{
      'acquiredAt': acquiredAt,
      'expiresAt': expiresAt,
      'releasedAt': releasedAt,
    }.entries) {
      if (entry.value != null) {
        CockpitFoundationValueReader.utcDateTime(
          entry.value!,
          '\$.${entry.key}',
        );
      }
    }
    _validateLeaseState(this);
  }

  final String leaseId;
  final String workspaceId;
  final CockpitLeaseResourceKind resourceKind;
  final String resourceId;
  final String holderId;
  final CockpitLeaseState state;
  final DateTime requestedAt;
  final DateTime? acquiredAt;
  final DateTime? expiresAt;
  final DateTime? releasedAt;
  final int? queuePosition;
  final CockpitFailure? failure;

  Map<String, Object?> toJson() => <String, Object?>{
    'leaseId': leaseId,
    'workspaceId': workspaceId,
    'resourceKind': resourceKind.name,
    'resourceId': resourceId,
    'holderId': holderId,
    'state': state.name,
    'requestedAt': requestedAt.toIso8601String(),
    if (acquiredAt != null) 'acquiredAt': acquiredAt!.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (releasedAt != null) 'releasedAt': releasedAt!.toIso8601String(),
    if (queuePosition != null) 'queuePosition': queuePosition,
    if (failure != null) 'failure': failure!.toJson(),
  };

  factory CockpitLeaseResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'leaseId',
        'workspaceId',
        'resourceKind',
        'resourceId',
        'holderId',
        'state',
        'requestedAt',
        'acquiredAt',
        'expiresAt',
        'releasedAt',
        'queuePosition',
        'failure',
      },
      path,
      required: const <String>{
        'leaseId',
        'workspaceId',
        'resourceKind',
        'resourceId',
        'holderId',
        'state',
        'requestedAt',
      },
      policy: decodePolicy,
    );
    DateTime? optionalTime(String key) => json[key] == null
        ? null
        : CockpitFoundationValueReader.dateTime(json[key], '$path.$key');
    return CockpitLeaseResource(
      leaseId: CockpitFoundationValueReader.id(
        json['leaseId'],
        '$path.leaseId',
      ),
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      resourceKind: _enum(
        json['resourceKind'],
        CockpitLeaseResourceKind.values,
        '$path.resourceKind',
      ),
      resourceId: CockpitFoundationValueReader.string(
        json['resourceId'],
        '$path.resourceId',
        maximum: 512,
      ),
      holderId: CockpitFoundationValueReader.id(
        json['holderId'],
        '$path.holderId',
      ),
      state: _enum(json['state'], CockpitLeaseState.values, '$path.state'),
      requestedAt: CockpitFoundationValueReader.dateTime(
        json['requestedAt'],
        '$path.requestedAt',
      ),
      acquiredAt: optionalTime('acquiredAt'),
      expiresAt: optionalTime('expiresAt'),
      releasedAt: optionalTime('releasedAt'),
      queuePosition: json['queuePosition'] == null
          ? null
          : CockpitFoundationValueReader.integer(
              json['queuePosition'],
              '$path.queuePosition',
              min: 0,
            ),
      failure: json['failure'] == null
          ? null
          : CockpitFailure.fromJson(
              json['failure'],
              path: '$path.failure',
              decodePolicy: decodePolicy,
            ),
    );
  }
}

void _validateLeaseState(CockpitLeaseResource lease) {
  if (lease.acquiredAt != null &&
          lease.acquiredAt!.isBefore(lease.requestedAt) ||
      lease.expiresAt != null &&
          lease.expiresAt!.isBefore(lease.acquiredAt ?? lease.requestedAt) ||
      lease.releasedAt != null &&
          lease.releasedAt!.isBefore(lease.acquiredAt ?? lease.requestedAt)) {
    throw const FormatException('Lease timestamps are inconsistent.');
  }
  final queued = lease.state == CockpitLeaseState.queued;
  final activeLike = const <CockpitLeaseState>{
    CockpitLeaseState.active,
    CockpitLeaseState.releasing,
    CockpitLeaseState.expired,
    CockpitLeaseState.quarantined,
  }.contains(lease.state);
  final terminal = lease.state == CockpitLeaseState.released;
  if (queued != (lease.queuePosition != null) ||
      (queued && (lease.acquiredAt != null || lease.expiresAt != null)) ||
      (activeLike && (lease.acquiredAt == null || lease.expiresAt == null)) ||
      terminal != (lease.releasedAt != null)) {
    throw const FormatException('Lease state is inconsistent.');
  }
  if (lease.state == CockpitLeaseState.quarantined && lease.failure == null ||
      lease.state != CockpitLeaseState.quarantined && lease.failure != null) {
    throw const FormatException('Lease quarantine failure is inconsistent.');
  }
}

T _enum<T extends Enum>(Object? value, List<T> values, String path) {
  return CockpitEnumValue<T>.parse(
    value,
    values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}

const int cockpitMaximumLeaseTtlMs = 1800000;
