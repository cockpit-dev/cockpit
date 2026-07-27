import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_locked_json_store.dart';
import '../registry/cockpit_registry_value_reader.dart';
import 'cockpit_lease_support.dart';

const _unsetLeaseField = Object();

final class CockpitLeaseRecord {
  const CockpitLeaseRecord({
    required this.leaseId,
    required this.workspaceId,
    required this.resourceKind,
    required this.resourceId,
    required this.holderId,
    required this.idempotencyKey,
    required this.waitTimeoutMs,
    required this.ttlMs,
    required this.sequence,
    required this.state,
    required this.requestedAt,
    this.acquiredAt,
    this.expiresAt,
    this.lastHeartbeatAt,
    this.releasedAt,
    this.cleanupClaimId,
    this.cleanupClaimExpiresAt,
    this.cleanupReason,
    this.failure,
    this.handoffToken,
    this.portPhase,
    this.portOwner,
  });

  final String leaseId;
  final String workspaceId;
  final CockpitLeaseResourceKind resourceKind;
  final String resourceId;
  final String holderId;
  final String idempotencyKey;
  final int waitTimeoutMs;
  final int ttlMs;
  final int sequence;
  final CockpitLeaseState state;
  final DateTime requestedAt;
  final DateTime? acquiredAt;
  final DateTime? expiresAt;
  final DateTime? lastHeartbeatAt;
  final DateTime? releasedAt;
  final String? cleanupClaimId;
  final DateTime? cleanupClaimExpiresAt;
  final CockpitLeaseCleanupReason? cleanupReason;
  final CockpitFailure? failure;
  final String? handoffToken;
  final CockpitDurablePortPhase? portPhase;
  final CockpitDurablePortOwner? portOwner;

  bool get blocksResource => const <CockpitLeaseState>{
    CockpitLeaseState.active,
    CockpitLeaseState.releasing,
    CockpitLeaseState.expired,
    CockpitLeaseState.quarantined,
  }.contains(state);

  bool get needsCleanup => const <CockpitLeaseState>{
    CockpitLeaseState.releasing,
    CockpitLeaseState.expired,
    CockpitLeaseState.quarantined,
  }.contains(state);

  bool sameResource(CockpitLeaseRecord other) =>
      resourceKind == other.resourceKind && resourceId == other.resourceId;

  bool matchesRequest(
    CockpitLeaseRequest request, {
    required String? handoffToken,
  }) =>
      workspaceId == request.workspaceId &&
      resourceKind == request.resourceKind &&
      resourceId == request.resourceId &&
      holderId == request.holderId &&
      idempotencyKey == request.idempotencyKey.value &&
      waitTimeoutMs == request.waitTimeoutMs &&
      ttlMs == request.ttlMs &&
      this.handoffToken == handoffToken;

  CockpitLeaseRecord copyWith({
    CockpitLeaseState? state,
    Object? acquiredAt = _unsetLeaseField,
    Object? expiresAt = _unsetLeaseField,
    Object? lastHeartbeatAt = _unsetLeaseField,
    Object? releasedAt = _unsetLeaseField,
    Object? cleanupClaimId = _unsetLeaseField,
    Object? cleanupClaimExpiresAt = _unsetLeaseField,
    Object? cleanupReason = _unsetLeaseField,
    Object? failure = _unsetLeaseField,
    Object? portPhase = _unsetLeaseField,
    Object? portOwner = _unsetLeaseField,
  }) => CockpitLeaseRecord(
    leaseId: leaseId,
    workspaceId: workspaceId,
    resourceKind: resourceKind,
    resourceId: resourceId,
    holderId: holderId,
    idempotencyKey: idempotencyKey,
    waitTimeoutMs: waitTimeoutMs,
    ttlMs: ttlMs,
    sequence: sequence,
    state: state ?? this.state,
    requestedAt: requestedAt,
    acquiredAt: identical(acquiredAt, _unsetLeaseField)
        ? this.acquiredAt
        : acquiredAt as DateTime?,
    expiresAt: identical(expiresAt, _unsetLeaseField)
        ? this.expiresAt
        : expiresAt as DateTime?,
    lastHeartbeatAt: identical(lastHeartbeatAt, _unsetLeaseField)
        ? this.lastHeartbeatAt
        : lastHeartbeatAt as DateTime?,
    releasedAt: identical(releasedAt, _unsetLeaseField)
        ? this.releasedAt
        : releasedAt as DateTime?,
    cleanupClaimId: identical(cleanupClaimId, _unsetLeaseField)
        ? this.cleanupClaimId
        : cleanupClaimId as String?,
    cleanupClaimExpiresAt: identical(cleanupClaimExpiresAt, _unsetLeaseField)
        ? this.cleanupClaimExpiresAt
        : cleanupClaimExpiresAt as DateTime?,
    cleanupReason: identical(cleanupReason, _unsetLeaseField)
        ? this.cleanupReason
        : cleanupReason as CockpitLeaseCleanupReason?,
    failure: identical(failure, _unsetLeaseField)
        ? this.failure
        : failure as CockpitFailure?,
    handoffToken: handoffToken,
    portPhase: identical(portPhase, _unsetLeaseField)
        ? this.portPhase
        : portPhase as CockpitDurablePortPhase?,
    portOwner: identical(portOwner, _unsetLeaseField)
        ? this.portOwner
        : portOwner as CockpitDurablePortOwner?,
  );

  CockpitLeaseResource toResource({int? queuePosition}) => CockpitLeaseResource(
    leaseId: leaseId,
    workspaceId: workspaceId,
    resourceKind: resourceKind,
    resourceId: resourceId,
    holderId: holderId,
    state: state,
    requestedAt: requestedAt,
    acquiredAt: acquiredAt,
    expiresAt: expiresAt,
    releasedAt: releasedAt,
    queuePosition: state == CockpitLeaseState.queued ? queuePosition : null,
    failure: failure,
  );
}

final class CockpitLeaseStateDocument {
  CockpitLeaseStateDocument({
    this.nextSequence = 0,
    List<CockpitLeaseRecord>? leases,
  }) : leases = leases ?? <CockpitLeaseRecord>[];

  int nextSequence;
  final List<CockpitLeaseRecord> leases;

  CockpitLeaseRecord byId(String leaseId) {
    final matches = leases.where((record) => record.leaseId == leaseId);
    if (matches.isEmpty) {
      throw const CockpitLeaseException(
        code: 'leaseNotFound',
        message: 'Lease was not found.',
      );
    }
    return matches.single;
  }
}

final class CockpitLeaseStateCodec
    implements CockpitJsonCodec<CockpitLeaseStateDocument> {
  const CockpitLeaseStateCodec();

  static const schemaVersion = 'cockpit.leases/v2';

  @override
  CockpitLeaseStateDocument decode(Object? json) => _decodeDocument(json);

  @override
  Object? encode(CockpitLeaseStateDocument value) {
    _validateDocument(value);
    return _encodeDocument(value);
  }
}

CockpitLeaseStateDocument _decodeDocument(Object? value) {
  const fields = <String>{'schemaVersion', 'nextSequence', 'leases'};
  final json = _object(value, r'$', fields, fields);
  if (json['schemaVersion'] != CockpitLeaseStateCodec.schemaVersion) {
    throw const FormatException('Unsupported lease registry schemaVersion.');
  }
  final rawLeases = CockpitRegistryValueReader.list(
    json['leases'],
    r'$.leases',
  );
  if (rawLeases.length > 65536) {
    throw const FormatException('Lease registry contains too many records.');
  }
  final document = CockpitLeaseStateDocument(
    nextSequence: _integer(json['nextSequence'], r'$.nextSequence', min: 0),
    leases: <CockpitLeaseRecord>[
      for (var index = 0; index < rawLeases.length; index += 1)
        _decodeRecord(rawLeases[index], r'$.leases[$index]'),
    ],
  );
  _validateDocument(document);
  return document;
}

CockpitLeaseRecord _decodeRecord(Object? value, String path) {
  const fields = <String>{
    'leaseId',
    'workspaceId',
    'resourceKind',
    'resourceId',
    'holderId',
    'idempotencyKey',
    'waitTimeoutMs',
    'ttlMs',
    'sequence',
    'state',
    'requestedAt',
    'acquiredAt',
    'expiresAt',
    'lastHeartbeatAt',
    'releasedAt',
    'cleanupClaimId',
    'cleanupClaimExpiresAt',
    'cleanupReason',
    'failure',
    'handoffToken',
    'portPhase',
    'portOwner',
  };
  final json = _object(value, path, fields, const <String>{
    'leaseId',
    'workspaceId',
    'resourceKind',
    'resourceId',
    'holderId',
    'idempotencyKey',
    'waitTimeoutMs',
    'ttlMs',
    'sequence',
    'state',
    'requestedAt',
  });
  DateTime? time(String name) => json[name] == null
      ? null
      : CockpitRegistryValueReader.timestamp(json[name], '$path.$name');
  return CockpitLeaseRecord(
    leaseId: CockpitRegistryValueReader.id(json['leaseId'], '$path.leaseId'),
    workspaceId: CockpitRegistryValueReader.id(
      json['workspaceId'],
      '$path.workspaceId',
    ),
    resourceKind: _enumByName(
      json['resourceKind'],
      CockpitLeaseResourceKind.values,
      '$path.resourceKind',
    ),
    resourceId: CockpitRegistryValueReader.string(
      json['resourceId'],
      '$path.resourceId',
      maximum: 512,
    ),
    holderId: CockpitRegistryValueReader.id(json['holderId'], '$path.holderId'),
    idempotencyKey: CockpitIdempotencyKey.fromJson(
      json['idempotencyKey'],
      path: '$path.idempotencyKey',
    ).value,
    waitTimeoutMs: _integer(
      json['waitTimeoutMs'],
      '$path.waitTimeoutMs',
      min: 0,
      max: 300000,
    ),
    ttlMs: _integer(
      json['ttlMs'],
      '$path.ttlMs',
      min: 1000,
      max: cockpitMaximumLeaseTtlMs,
    ),
    sequence: _integer(json['sequence'], '$path.sequence', min: 0),
    state: _enumByName(json['state'], CockpitLeaseState.values, '$path.state'),
    requestedAt: CockpitRegistryValueReader.timestamp(
      json['requestedAt'],
      '$path.requestedAt',
    ),
    acquiredAt: time('acquiredAt'),
    expiresAt: time('expiresAt'),
    lastHeartbeatAt: time('lastHeartbeatAt'),
    releasedAt: time('releasedAt'),
    cleanupClaimId: json['cleanupClaimId'] == null
        ? null
        : CockpitRegistryValueReader.id(
            json['cleanupClaimId'],
            '$path.cleanupClaimId',
          ),
    cleanupClaimExpiresAt: time('cleanupClaimExpiresAt'),
    cleanupReason: json['cleanupReason'] == null
        ? null
        : _enumByName(
            json['cleanupReason'],
            CockpitLeaseCleanupReason.values,
            '$path.cleanupReason',
          ),
    failure: json['failure'] == null
        ? null
        : CockpitFailure.fromJson(json['failure'], path: '$path.failure'),
    handoffToken: json['handoffToken'] == null
        ? null
        : CockpitRegistryValueReader.string(
            json['handoffToken'],
            '$path.handoffToken',
            maximum: 128,
          ),
    portPhase: json['portPhase'] == null
        ? null
        : _enumByName(
            json['portPhase'],
            CockpitDurablePortPhase.values,
            '$path.portPhase',
          ),
    portOwner: json['portOwner'] == null
        ? null
        : _decodePortOwner(json['portOwner'], '$path.portOwner'),
  );
}

Map<String, Object?> _encodeDocument(CockpitLeaseStateDocument document) =>
    <String, Object?>{
      'schemaVersion': CockpitLeaseStateCodec.schemaVersion,
      'nextSequence': document.nextSequence,
      'leases': document.leases.map(_encodeRecord).toList(),
    };

Map<String, Object?> _encodeRecord(
  CockpitLeaseRecord record,
) => <String, Object?>{
  'leaseId': record.leaseId,
  'workspaceId': record.workspaceId,
  'resourceKind': record.resourceKind.name,
  'resourceId': record.resourceId,
  'holderId': record.holderId,
  'idempotencyKey': record.idempotencyKey,
  'waitTimeoutMs': record.waitTimeoutMs,
  'ttlMs': record.ttlMs,
  'sequence': record.sequence,
  'state': record.state.name,
  'requestedAt': record.requestedAt.toIso8601String(),
  if (record.acquiredAt != null)
    'acquiredAt': record.acquiredAt!.toIso8601String(),
  if (record.expiresAt != null)
    'expiresAt': record.expiresAt!.toIso8601String(),
  if (record.lastHeartbeatAt != null)
    'lastHeartbeatAt': record.lastHeartbeatAt!.toIso8601String(),
  if (record.releasedAt != null)
    'releasedAt': record.releasedAt!.toIso8601String(),
  if (record.cleanupClaimId != null) 'cleanupClaimId': record.cleanupClaimId,
  if (record.cleanupClaimExpiresAt != null)
    'cleanupClaimExpiresAt': record.cleanupClaimExpiresAt!.toIso8601String(),
  if (record.cleanupReason != null) 'cleanupReason': record.cleanupReason!.name,
  if (record.failure != null) 'failure': record.failure!.toJson(),
  if (record.handoffToken != null) 'handoffToken': record.handoffToken,
  if (record.portPhase != null) 'portPhase': record.portPhase!.name,
  if (record.portOwner != null)
    'portOwner': _encodePortOwner(record.portOwner!),
};

void _validateDocument(CockpitLeaseStateDocument document) {
  if (document.nextSequence < 0 || document.leases.length > 65536) {
    throw const FormatException('Lease registry bounds are invalid.');
  }
  final leaseIds = <String>{};
  final sequences = <int>{};
  final idempotencyScopes = <String>{};
  final blockers = <String, CockpitLeaseRecord>{};
  var maximumSequence = -1;
  for (final record in document.leases) {
    _validateRecord(record);
    if (!leaseIds.add(record.leaseId) || !sequences.add(record.sequence)) {
      throw const FormatException('Lease identity or sequence is duplicated.');
    }
    final idempotencyScope =
        '${record.workspaceId}\u0000'
        '${record.idempotencyKey}';
    if (!idempotencyScopes.add(idempotencyScope)) {
      throw const FormatException('Lease idempotency scope is duplicated.');
    }
    final resourceKey = '${record.resourceKind.name}\u0000${record.resourceId}';
    if (record.blocksResource && blockers[resourceKey] != null) {
      throw const FormatException('Resource has multiple blocking leases.');
    }
    if (record.blocksResource) blockers[resourceKey] = record;
    if (record.sequence > maximumSequence) maximumSequence = record.sequence;
  }
  if (document.nextSequence <= maximumSequence) {
    throw const FormatException('Lease nextSequence is not monotonic.');
  }
  for (final record in document.leases) {
    if (record.state != CockpitLeaseState.queued) continue;
    final key = '${record.resourceKind.name}\u0000${record.resourceId}';
    final blocker = blockers[key];
    if (blocker != null && record.sequence < blocker.sequence) {
      throw const FormatException('Lease FIFO order is inconsistent.');
    }
  }
}

void _validateRecord(CockpitLeaseRecord record) {
  CockpitLeaseRequest(
    workspaceId: record.workspaceId,
    resourceKind: record.resourceKind,
    resourceId: record.resourceId,
    holderId: record.holderId,
    idempotencyKey: CockpitIdempotencyKey(record.idempotencyKey),
    waitTimeoutMs: record.waitTimeoutMs,
    ttlMs: record.ttlMs,
  );
  if (record.sequence < 0 || !record.requestedAt.isUtc) {
    throw const FormatException('Lease record identity is invalid.');
  }
  final queue = record.state == CockpitLeaseState.queued;
  final activeLike = record.blocksResource;
  final released = record.state == CockpitLeaseState.released;
  if (queue &&
          (record.acquiredAt != null ||
              record.expiresAt != null ||
              record.lastHeartbeatAt != null ||
              record.releasedAt != null) ||
      activeLike &&
          (record.acquiredAt == null ||
              record.expiresAt == null ||
              record.lastHeartbeatAt == null ||
              record.releasedAt != null) ||
      released != (record.releasedAt != null)) {
    throw const FormatException('Lease lifecycle fields are inconsistent.');
  }
  if ((record.cleanupClaimId == null) !=
          (record.cleanupClaimExpiresAt == null) ||
      record.cleanupClaimId != null && !record.needsCleanup ||
      record.needsCleanup != (record.cleanupReason != null) ||
      (record.state == CockpitLeaseState.quarantined) !=
          (record.failure != null)) {
    throw const FormatException('Lease cleanup fields are inconsistent.');
  }
  final hasPortReservation = record.handoffToken != null;
  if (hasPortReservation != (record.portPhase != null) ||
      hasPortReservation &&
          (record.resourceKind != CockpitLeaseResourceKind.forwardedPort ||
              !cockpitIsValidPortHandoffToken(record.handoffToken!) ||
              !cockpitIsValidLoopbackPortResource(record.resourceId) ||
              (record.portPhase == CockpitDurablePortPhase.reserved) !=
                  (record.portOwner == null)) ||
      !hasPortReservation && record.portOwner != null) {
    throw const FormatException('Lease port handoff state is inconsistent.');
  }
  final times = <DateTime?>[
    record.acquiredAt,
    record.expiresAt,
    record.lastHeartbeatAt,
    record.releasedAt,
    record.cleanupClaimExpiresAt,
  ];
  if (times.whereType<DateTime>().any((value) => !value.isUtc) ||
      record.acquiredAt != null &&
          record.acquiredAt!.isBefore(record.requestedAt) ||
      record.lastHeartbeatAt != null &&
          record.lastHeartbeatAt!.isBefore(record.acquiredAt!) ||
      record.expiresAt != null &&
          record.expiresAt!.isBefore(record.lastHeartbeatAt!) ||
      record.cleanupClaimExpiresAt != null &&
          record.cleanupClaimExpiresAt!.isBefore(
            record.acquiredAt ?? record.requestedAt,
          ) ||
      record.releasedAt != null &&
          record.releasedAt!.isBefore(
            record.acquiredAt ?? record.requestedAt,
          )) {
    throw const FormatException('Lease timestamps are inconsistent.');
  }
  record.toResource(queuePosition: queue ? 0 : null);
}

CockpitDurablePortOwner _decodePortOwner(Object? value, String path) {
  const fields = <String>{
    'ownerId',
    'processId',
    'processStartIdentity',
    'sessionId',
  };
  final json = _object(value, path, fields, fields);
  return CockpitDurablePortOwner(
    ownerId: CockpitRegistryValueReader.string(
      json['ownerId'],
      '$path.ownerId',
      maximum: 128,
    ),
    processId: _integer(
      json['processId'],
      '$path.processId',
      min: 1,
      max: 4294967295,
    ),
    processStartIdentity: CockpitRegistryValueReader.string(
      json['processStartIdentity'],
      '$path.processStartIdentity',
      maximum: 512,
    ),
    sessionId: CockpitRegistryValueReader.string(
      json['sessionId'],
      '$path.sessionId',
      maximum: 128,
    ),
  );
}

Map<String, Object?> _encodePortOwner(CockpitDurablePortOwner owner) =>
    <String, Object?>{
      'ownerId': owner.ownerId,
      'processId': owner.processId,
      'processStartIdentity': owner.processStartIdentity,
      'sessionId': owner.sessionId,
    };

T _enumByName<T extends Enum>(Object? value, List<T> values, String path) {
  final name = CockpitRegistryValueReader.string(value, path, maximum: 64);
  final matches = values.where((candidate) => candidate.name == name);
  if (matches.length != 1) {
    throw FormatException('Unknown enum value at $path.');
  }
  return matches.single;
}

Map<String, Object?> _object(
  Object? value,
  String path,
  Set<String> allowed,
  Set<String> required,
) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Expected object at $path.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('Expected string key at $path.');
    }
    final key = entry.key! as String;
    if (!allowed.contains(key)) {
      throw FormatException('Unknown field $path.$key.');
    }
    result[key] = entry.value;
  }
  for (final key in required) {
    if (!result.containsKey(key)) {
      throw FormatException('Missing field $path.$key.');
    }
  }
  return result;
}

int _integer(Object? value, String path, {int min = 0, int? max}) {
  if (value is! int || value < min || max != null && value > max) {
    throw FormatException('Expected bounded integer at $path.');
  }
  return value;
}
