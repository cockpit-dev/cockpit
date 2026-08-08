import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_canonical_paths.dart';
import '../foundation/cockpit_filesystem_identity.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../infrastructure/cockpit_clock.dart';
import 'cockpit_directory_attestation.dart';
import 'cockpit_registry_database.dart';
import 'cockpit_registry_invariants.dart';
import 'cockpit_registry_models.dart';
import 'cockpit_registry_records.dart';
import 'cockpit_registry_state.dart';

final class CockpitAllowedRootRegistry {
  const CockpitAllowedRootRegistry({
    required CockpitRegistryDatabase database,
    required CockpitDirectoryAttestationProvider directoryAttestor,
    required CockpitIdGenerator idGenerator,
    required CockpitClock clock,
    required CockpitLexicalPaths lexicalPaths,
    required CockpitRegistryActivityController activityController,
    List<CockpitRegistryReferenceOwner> referenceOwners =
        const <CockpitRegistryReferenceOwner>[],
  }) : _database = database,
       _directoryAttestor = directoryAttestor,
       _idGenerator = idGenerator,
       _clock = clock,
       _lexicalPaths = lexicalPaths,
       _activityController = activityController,
       _referenceOwners = referenceOwners;

  final CockpitRegistryDatabase _database;
  final CockpitDirectoryAttestationProvider _directoryAttestor;
  final CockpitIdGenerator _idGenerator;
  final CockpitClock _clock;
  final CockpitLexicalPaths _lexicalPaths;
  final CockpitRegistryActivityController _activityController;
  final List<CockpitRegistryReferenceOwner> _referenceOwners;

  Future<CockpitRootResource> register(String path) async {
    final attestation = await _directoryAttestor.attest(
      path,
      CockpitDirectoryAttestationScope.root,
    );
    final directory = attestation.directory;
    final identity = attestation.identity;
    return _database.transact<CockpitRootResource>((state) async {
      for (final root in state.roots) {
        if (root.state == CockpitRootState.retired) {
          continue;
        }
        if (_lexicalPaths.equals(root.canonicalPath, directory.path)) {
          if (root.identityQuality.isStrong &&
              (identity.quality != root.identityQuality ||
                  identity.value != root.filesystemIdentity)) {
            throw const CockpitRegistryException(
              code: 'rootIdentityChanged',
              message: 'Allowed root filesystem identity changed.',
            );
          }
          return CockpitLockedJsonUpdate.readOnly(state, root.toResource());
        }
        if (_lexicalPaths.overlaps(root.canonicalPath, directory.path) ||
            root.filesystemIdentity == identity.value) {
          throw CockpitRegistryException(
            code: root.state == CockpitRootState.retired
                ? 'rootRetiredOverlap'
                : 'rootOverlap',
            message: 'Allowed roots cannot be nested or overlap.',
          );
        }
      }
      final now = _clock.now().toUtc();
      final root = CockpitRootRecord(
        rootId: _uniqueRootId(state.roots),
        canonicalPath: directory.path,
        filesystemIdentity: identity.value,
        identityQuality: identity.quality,
        state: CockpitRootState.active,
        registeredAt: now,
        updatedAt: now,
      );
      state.roots.add(root);
      return CockpitLockedJsonUpdate.write(state, root.toResource());
    });
  }

  Future<List<CockpitRootResource>> list() async {
    final state = await _database.read();
    return state.roots.map((value) => value.toResource()).toList();
  }

  Future<CockpitRootResource> get(String rootId) async {
    final state = await _database.read();
    final matches = state.roots.where((value) => value.rootId == rootId);
    if (matches.isEmpty) {
      throw const CockpitRegistryException(
        code: 'rootNotFound',
        message: 'Allowed root was not found.',
      );
    }
    return matches.single.toResource();
  }

  Future<CockpitRetirementResult> remove(
    String rootId, {
    CockpitRemovalPolicy policy = CockpitRemovalPolicy.reject,
    Duration drainTimeout = const Duration(seconds: 30),
  }) {
    _validateTimeout(drainTimeout);
    return CockpitRegistryAdmissionFences.run(
      _referenceOwners,
      <String>{rootId},
      const <String>{},
      () => _removeWithinAdmissionFence(
        rootId,
        policy: policy,
        drainTimeout: drainTimeout,
      ),
    );
  }

  Future<CockpitRetirementResult> _removeWithinAdmissionFence(
    String rootId, {
    required CockpitRemovalPolicy policy,
    required Duration drainTimeout,
  }) async {
    final initialState = await _database.read();
    final root = _root(initialState.roots, rootId);
    final workspaceIds = initialState.workspaces
        .where((value) => value.rootId == rootId)
        .map((value) => value.workspaceId)
        .toSet();
    _rejectPendingMarkerMutations(initialState, workspaceIds);
    final external = await _externalCounts(workspaceIds);
    final initialCounts = CockpitRegistryInvariants.rootCounts(
      initialState,
      rootId,
      externalActive: external,
    );
    if (root.state == CockpitRootState.retired) {
      return CockpitRetirementResult(
        id: rootId,
        tombstoneRetained: true,
        referenceCounts: initialCounts,
      );
    }
    if (policy == CockpitRemovalPolicy.reject &&
        initialCounts.activeTotal > 0) {
      throw CockpitRegistryException(
        code: 'rootInUse',
        message: 'Allowed root still has live references.',
        referenceCounts: initialCounts,
      );
    }
    if (policy != CockpitRemovalPolicy.reject) {
      final drainingWorkspaceIds = await _markDraining(rootId);
      workspaceIds
        ..clear()
        ..addAll(drainingWorkspaceIds);
      if (policy == CockpitRemovalPolicy.drain) {
        await _drainWithTimeout(
          _activityController.drainWorkspaces(workspaceIds, drainTimeout),
          drainTimeout,
        );
      } else {
        await _activityController.forceWorkspaces(workspaceIds);
      }
    }
    final currentExternal = await _externalCounts(workspaceIds);
    return _database.transact<CockpitRetirementResult>((state) async {
      _root(state.roots, rootId);
      final currentWorkspaceIds = state.workspaces
          .where((value) => value.rootId == rootId)
          .map((value) => value.workspaceId)
          .toSet();
      _rejectPendingMarkerMutations(state, currentWorkspaceIds);
      if (policy == CockpitRemovalPolicy.force) {
        CockpitRegistryInvariants.clearActiveReferences(
          state,
          currentWorkspaceIds,
        );
      }
      final counts = CockpitRegistryInvariants.rootCounts(
        state,
        rootId,
        externalActive: currentExternal,
      );
      final blockingActive = policy == CockpitRemovalPolicy.reject
          ? counts.activeTotal
          : counts.activeSessions + counts.activeRuns + counts.otherActive;
      if (blockingActive > 0) {
        throw CockpitRegistryException(
          code: 'rootInUse',
          message: 'Allowed root still has live references after draining.',
          referenceCounts: counts,
        );
      }
      final now = _clock.now().toUtc();
      for (final workspaceId in currentWorkspaceIds) {
        CockpitRegistryInvariants.retireWorkspace(state, workspaceId, now);
      }
      final index = state.roots.indexWhere((value) => value.rootId == rootId);
      state.roots[index] = state.roots[index].copyWith(
        state: CockpitRootState.retired,
        updatedAt: now,
        retiredAt: now,
      );
      final retainedCounts = CockpitRegistryInvariants.rootCounts(
        state,
        rootId,
      );
      CockpitRegistryInvariants.cleanupTombstones(state);
      final tombstone = state.roots.any((value) => value.rootId == rootId);
      return CockpitLockedJsonUpdate.write(
        state,
        CockpitRetirementResult(
          id: rootId,
          tombstoneRetained: tombstone,
          referenceCounts: retainedCounts,
        ),
      );
    });
  }

  Future<Set<String>> _markDraining(String rootId) =>
      _database.transact<Set<String>>((state) async {
        final workspaceIds = state.workspaces
            .where((value) => value.rootId == rootId)
            .map((value) => value.workspaceId)
            .toSet();
        _rejectPendingMarkerMutations(state, workspaceIds);
        final now = _clock.now().toUtc();
        final rootIndex = state.roots.indexWhere(
          (value) => value.rootId == rootId,
        );
        if (rootIndex < 0) {
          throw const CockpitRegistryException(
            code: 'rootNotFound',
            message: 'Allowed root was not found.',
          );
        }
        final root = state.roots[rootIndex];
        if (root.state == CockpitRootState.active) {
          state.roots[rootIndex] = root.copyWith(
            state: CockpitRootState.draining,
            updatedAt: now,
          );
        }
        for (var index = 0; index < state.workspaces.length; index += 1) {
          final workspace = state.workspaces[index];
          if (workspaceIds.contains(workspace.workspaceId) &&
              workspace.state == CockpitWorkspaceState.active) {
            state.workspaces[index] = workspace.copyWith(
              state: CockpitWorkspaceState.draining,
              updatedAt: now,
            );
          }
        }
        return CockpitLockedJsonUpdate.write(
          state,
          Set<String>.unmodifiable(workspaceIds),
        );
      });

  Future<Map<String, int>> _externalCounts(Set<String> workspaceIds) async {
    final result = <String, int>{};
    for (final workspaceId in workspaceIds) {
      var count = 0;
      for (final owner in _referenceOwners) {
        final ownerCount = await owner.activeReferenceCount(workspaceId);
        if (ownerCount < 0) {
          throw const CockpitRegistryException(
            code: 'invalidReferenceCount',
            message: 'Reference owner returned a negative count.',
          );
        }
        count += ownerCount;
      }
      result[workspaceId] = count;
    }
    return result;
  }

  void _rejectPendingMarkerMutations(
    CockpitRegistryState state,
    Set<String> workspaceIds,
  ) {
    if (state.markerMutations.any(
      (value) => workspaceIds.contains(value.workspaceId),
    )) {
      throw const CockpitRegistryException(
        code: 'markerMutationPending',
        message: 'Pending workspace marker mutation must recover first.',
      );
    }
  }

  CockpitRootRecord _root(Iterable<CockpitRootRecord> roots, String rootId) {
    final matches = roots.where((value) => value.rootId == rootId);
    if (matches.isEmpty) {
      throw const CockpitRegistryException(
        code: 'rootNotFound',
        message: 'Allowed root was not found.',
      );
    }
    return matches.single;
  }

  void _validateTimeout(Duration timeout) {
    if (timeout.isNegative || timeout > const Duration(minutes: 5)) {
      throw const CockpitRegistryException(
        code: 'invalidDrainTimeout',
        message: 'Drain timeout must be between zero and five minutes.',
      );
    }
  }

  String _uniqueRootId(Iterable<CockpitRootRecord> roots) {
    for (var attempt = 0; attempt < 32; attempt += 1) {
      final candidate = _idGenerator.next(CockpitIdKind.root);
      if (!roots.any((value) => value.rootId == candidate)) return candidate;
    }
    throw const CockpitRegistryException(
      code: 'idGenerationFailed',
      message: 'Could not generate a unique secure identifier.',
    );
  }

  Future<void> _drainWithTimeout(Future<void> operation, Duration timeout) =>
      operation.timeout(
        timeout,
        onTimeout: () => throw const CockpitRegistryException(
          code: 'drainTimeout',
          message: 'Activity drain exceeded its bounded timeout.',
        ),
      );
}
