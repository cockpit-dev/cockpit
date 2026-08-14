import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../infrastructure/cockpit_monotonic_clock.dart';
import '../registry/cockpit_registry_models.dart';
import 'cockpit_lease_database.dart';
import 'cockpit_lease_state.dart';
import 'cockpit_lease_support.dart';

part 'cockpit_lease_admission.dart';
part 'cockpit_lease_lifecycle.dart';
part 'cockpit_port_lease_lifecycle.dart';
part 'cockpit_lease_recovery.dart';
part 'cockpit_lease_registry_support.dart';

final class CockpitLeaseRegistry implements CockpitRegistryReferenceOwner {
  CockpitLeaseRegistry({
    required CockpitLeaseDatabase database,
    required CockpitIdGenerator idGenerator,
    required CockpitMonotonicClock clock,
    required CockpitLeaseWorkspaceAuthority workspaceAuthority,
    required CockpitLeaseCleanupProbeResolver cleanupProbes,
    Duration pollInterval = const Duration(milliseconds: 50),
    Duration cleanupTimeout = const Duration(seconds: 30),
    Duration cleanupClaimGrace = const Duration(seconds: 5),
    Duration idempotencyRetention = const Duration(hours: 24),
  }) : _database = database,
       _idGenerator = idGenerator,
       _clock = clock,
       _workspaceAuthority = workspaceAuthority,
       _cleanupProbes = cleanupProbes,
       _pollInterval = pollInterval,
       _cleanupTimeout = cleanupTimeout,
       _cleanupClaimGrace = cleanupClaimGrace,
       _idempotencyRetention = idempotencyRetention {
    if (pollInterval <= Duration.zero ||
        pollInterval > const Duration(seconds: 1) ||
        cleanupTimeout <= Duration.zero ||
        cleanupTimeout > const Duration(minutes: 5) ||
        cleanupClaimGrace.isNegative ||
        cleanupClaimGrace > const Duration(minutes: 1) ||
        idempotencyRetention < const Duration(minutes: 1) ||
        idempotencyRetention > const Duration(days: 30)) {
      throw ArgumentError('Lease registry timing bounds are invalid.');
    }
  }

  factory CockpitLeaseRegistry.create({
    required CockpitHomePaths paths,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    required CockpitLeaseWorkspaceAuthority workspaceAuthority,
    required CockpitLeaseCleanupProbeResolver cleanupProbes,
    CockpitIdGenerator? idGenerator,
    CockpitMonotonicClock? clock,
    Duration pollInterval = const Duration(milliseconds: 50),
    Duration cleanupTimeout = const Duration(seconds: 30),
    Duration cleanupClaimGrace = const Duration(seconds: 5),
    Duration idempotencyRetention = const Duration(hours: 24),
  }) => CockpitLeaseRegistry(
    database: CockpitLeaseDatabase.create(
      paths: paths,
      permissionHardener: permissionHardener,
      directorySyncer: directorySyncer,
    ),
    idGenerator: idGenerator ?? CockpitSecureIdGenerator(),
    clock: clock ?? CockpitSystemMonotonicClock(),
    workspaceAuthority: workspaceAuthority,
    cleanupProbes: cleanupProbes,
    pollInterval: pollInterval,
    cleanupTimeout: cleanupTimeout,
    cleanupClaimGrace: cleanupClaimGrace,
    idempotencyRetention: idempotencyRetention,
  );

  final CockpitLeaseDatabase _database;
  final CockpitIdGenerator _idGenerator;
  final CockpitMonotonicClock _clock;
  final CockpitLeaseWorkspaceAuthority _workspaceAuthority;
  final CockpitLeaseCleanupProbeResolver _cleanupProbes;
  final Duration _pollInterval;
  final Duration _cleanupTimeout;
  final Duration _cleanupClaimGrace;
  final Duration _idempotencyRetention;
  final _CockpitLeaseAdmissionLocks _admissionLocks =
      _CockpitLeaseAdmissionLocks();
  final Map<String, Future<void> Function()> _localCleanup =
      <String, Future<void> Function()>{};

  void registerLocalCleanup(String leaseId, Future<void> Function() cleanup) {
    _localCleanup[leaseId] = cleanup;
  }

  void unregisterLocalCleanup(String leaseId, Future<void> Function() cleanup) {
    if (identical(_localCleanup[leaseId], cleanup)) {
      _localCleanup.remove(leaseId);
    }
  }

  Future<CockpitLeaseResource> get(String leaseId) =>
      _readCurrentState((state) => _resource(state, state.byId(leaseId)));

  Future<List<CockpitLeaseResource>> list({
    String? workspaceId,
    CockpitLeaseResourceKind? resourceKind,
    String? resourceId,
  }) => _readCurrentState(
    (state) => <CockpitLeaseResource>[
      for (final record in state.leases)
        if ((workspaceId == null || record.workspaceId == workspaceId) &&
            (resourceKind == null || record.resourceKind == resourceKind) &&
            (resourceId == null || record.resourceId == resourceId))
          _resource(state, record),
    ],
  );

  Future<({List<CockpitLeaseResource> items, int total, String? next})>
  listPage({
    String? workspaceId,
    CockpitLeaseResourceKind? resourceKind,
    String? resourceId,
    CockpitLeaseState? leaseState,
    required int limit,
    String? before,
  }) => _readCurrentState((state) {
    CockpitLeaseRecord? boundary;
    if (before != null) {
      boundary = state.leases
          .where((record) => record.leaseId == before)
          .firstOrNull;
      if (boundary == null ||
          workspaceId != null && boundary.workspaceId != workspaceId ||
          resourceKind != null && boundary.resourceKind != resourceKind ||
          resourceId != null && boundary.resourceId != resourceId) {
        throw const CockpitLeaseException(
          code: 'leasePageInvalid',
          message: 'Lease page cursor is invalid for these filters.',
        );
      }
    }

    final matches = state.leases.where(
      (record) =>
          (workspaceId == null || record.workspaceId == workspaceId) &&
          (resourceKind == null || record.resourceKind == resourceKind) &&
          (resourceId == null || record.resourceId == resourceId) &&
          (leaseState == null || record.state == leaseState),
    );
    final total = matches.length;
    final page =
        matches
            .where(
              (record) =>
                  boundary == null || record.sequence < boundary.sequence,
            )
            .toList(growable: false)
          ..sort((left, right) => right.sequence.compareTo(left.sequence));
    final hasMore = page.length > limit;
    final records = page.take(limit).toList(growable: false);
    return (
      items: <CockpitLeaseResource>[
        for (final record in records) _resource(state, record),
      ],
      total: total,
      next: hasMore ? records.last.leaseId : null,
    );
  });

  @override
  Future<int> activeReferenceCount(String workspaceId) => _readCurrentState(
    (state) => state.leases
        .where(
          (record) =>
              record.workspaceId == workspaceId &&
              record.state != CockpitLeaseState.released &&
              record.state != CockpitLeaseState.quarantined,
        )
        .length,
  );

  @override
  Future<R> withAdmissionFence<R>(
    Set<String> rootIds,
    Set<String> workspaceIds,
    Future<R> Function() action,
  ) => _admissionLocks.run(rootIds, workspaceIds, action);
}
