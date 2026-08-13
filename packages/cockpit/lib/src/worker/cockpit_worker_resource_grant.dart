import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_worker_value_reader.dart';

final class CockpitWorkerResourceRequest {
  CockpitWorkerResourceRequest({
    required this.resourceKind,
    required this.resourceId,
    this.requiresPort = false,
    this.ttl = const Duration(seconds: 30),
    this.wait,
  }) {
    workerString(resourceId, r'$.resourceId', maximum: 512);
    if (ttl < const Duration(seconds: 1) ||
        ttl > const Duration(milliseconds: cockpitMaximumLeaseTtlMs)) {
      throw const FormatException('Worker resource TTL is invalid.');
    }
    if (requiresPort &&
        resourceKind != CockpitLeaseResourceKind.forwardedPort) {
      throw const FormatException('Only a forwarded-port grant has a port.');
    }
    if (wait case final value?
        when value.isNegative || value > const Duration(minutes: 5)) {
      throw const FormatException('Worker resource wait is invalid.');
    }
  }

  final CockpitLeaseResourceKind resourceKind;
  final String resourceId;
  final bool requiresPort;
  final Duration ttl;
  final Duration? wait;

  Map<String, Object?> toJson() => <String, Object?>{
    'resourceKind': resourceKind.name,
    'resourceId': resourceId,
    'requiresPort': requiresPort,
    'ttlMs': ttl.inMilliseconds,
    if (wait != null) 'waitMs': wait!.inMilliseconds,
  };
}

final class CockpitWorkerResourceException implements Exception {
  const CockpitWorkerResourceException({
    required this.code,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'CockpitWorkerResourceException($code): $message';
}

final class CockpitWorkerResourceGrant {
  CockpitWorkerResourceGrant({
    required this.grantId,
    required this.leaseId,
    required this.workspaceId,
    required this.holderId,
    required this.resourceKind,
    required this.resourceId,
    required this.expiresAt,
    this.port,
    this.handoffToken,
  }) {
    workerId(grantId, r'$.grantId');
    workerId(leaseId, r'$.leaseId');
    workerId(workspaceId, r'$.workspaceId');
    workerId(holderId, r'$.holderId');
    workerString(resourceId, r'$.resourceId', maximum: 512);
    workerUtcDateTimeValue(expiresAt, r'$.expiresAt');
    if ((port == null) != (handoffToken == null) ||
        port != null && (port! < 1 || port! > 65535) ||
        handoffToken != null && handoffToken!.length < 16) {
      throw const FormatException('Worker port grant is invalid.');
    }
  }

  final String grantId;
  final String leaseId;
  final String workspaceId;
  final String holderId;
  final CockpitLeaseResourceKind resourceKind;
  final String resourceId;
  final DateTime expiresAt;
  final int? port;
  final String? handoffToken;

  Map<String, Object?> toJson() => <String, Object?>{
    'grantId': grantId,
    'leaseId': leaseId,
    'workspaceId': workspaceId,
    'holderId': holderId,
    'resourceKind': resourceKind.name,
    'resourceId': resourceId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (port != null) 'port': port,
    if (handoffToken != null) 'handoffToken': handoffToken,
  };

  factory CockpitWorkerResourceGrant.fromJson(Object? value) {
    final json = workerObject(value, r'$');
    workerKeys(
      json,
      const <String>{
        'grantId',
        'leaseId',
        'workspaceId',
        'holderId',
        'resourceKind',
        'resourceId',
        'expiresAt',
        'port',
        'handoffToken',
      },
      r'$',
      required: const <String>{
        'grantId',
        'leaseId',
        'workspaceId',
        'holderId',
        'resourceKind',
        'resourceId',
        'expiresAt',
      },
    );
    final kindName = workerString(
      json['resourceKind'],
      r'$.resourceKind',
      maximum: 64,
    );
    final kinds = CockpitLeaseResourceKind.values
        .where((kind) => kind.name == kindName)
        .toList(growable: false);
    if (kinds.length != 1) {
      throw const FormatException('Worker resource kind is invalid.');
    }
    return CockpitWorkerResourceGrant(
      grantId: workerId(json['grantId'], r'$.grantId'),
      leaseId: workerId(json['leaseId'], r'$.leaseId'),
      workspaceId: workerId(json['workspaceId'], r'$.workspaceId'),
      holderId: workerId(json['holderId'], r'$.holderId'),
      resourceKind: kinds.single,
      resourceId: workerString(
        json['resourceId'],
        r'$.resourceId',
        maximum: 512,
      ),
      expiresAt: workerUtcDateTime(json['expiresAt'], r'$.expiresAt'),
      port: json['port'] == null
          ? null
          : workerInteger(json['port'], r'$.port', minimum: 1, maximum: 65535),
      handoffToken: json['handoffToken'] == null
          ? null
          : workerString(
              json['handoffToken'],
              r'$.handoffToken',
              minimum: 16,
              maximum: 128,
            ),
    );
  }
}

abstract interface class CockpitWorkerResourceAuthorityClient {
  Future<CockpitWorkerResourceGrant> acquire(
    CockpitWorkerResourceRequest request, {
    required String workspaceId,
    required String holderId,
    required String idempotencyKey,
    required DateTime deadline,
  });

  Future<void> heartbeat(CockpitWorkerResourceGrant grant);

  Future<void> release(
    CockpitWorkerResourceGrant grant, {
    required bool cancel,
  });
}
