part of 'cockpit_workspace_registry.dart';

extension CockpitWorkspaceRegistrationOperations on CockpitWorkspaceRegistry {
  Future<CockpitWorkspaceRegistrationResult> register({
    required String rootId,
    required String path,
  }) async {
    await _recoverMarkerMutations();
    final target = await _attestDirectory(path);
    final rootAuthority = await _attestActiveRoot(
      rootId,
      target.directory.path,
    );
    return _database.transact<CockpitWorkspaceRegistrationResult>((
      state,
    ) async {
      _confirmAttestedRoot(state, rootAuthority, target.directory.path);
      final samePath = state.workspaces
          .where(
            (value) =>
                value.state != CockpitWorkspaceState.retired &&
                _lexicalPaths.equals(
                  value.canonicalPath,
                  target.directory.path,
                ),
          )
          .toList();
      var freshTarget = await _reattestMatching(
        target,
        CockpitDirectoryAttestationScope.workspace,
      );
      final marker = await _markerStore.read(freshTarget.directory.path);
      freshTarget = await _reattestMatching(
        freshTarget,
        CockpitDirectoryAttestationScope.workspace,
      );
      if (samePath.isNotEmpty) {
        return _existingPath(state, samePath, marker, freshTarget);
      }
      if (marker == null) {
        return _createLocal(state, rootId, freshTarget);
      }
      return _registerMarker(state, rootId, freshTarget, marker);
    });
  }

  CockpitLockedJsonUpdate<
    CockpitRegistryState,
    CockpitWorkspaceRegistrationResult
  >
  _existingPath(
    CockpitRegistryState state,
    List<CockpitWorkspaceRecord> matches,
    CockpitWorkspaceMarker? marker,
    CockpitDirectoryAttestation target,
  ) {
    if (matches.length != 1) {
      throw const CockpitRegistryException(
        code: 'ambiguousWorkspace',
        message: 'Multiple workspace records target the same path.',
      );
    }
    final workspace = matches.single;
    if (workspace.state != CockpitWorkspaceState.active) {
      throw const CockpitRegistryException(
        code: 'workspaceNotActive',
        message: 'A retired or draining workspace cannot be reauthorized.',
      );
    }
    if (marker == null || !_markerMatches(workspace, marker)) {
      throw const CockpitRegistryException(
        code: 'workspaceMarkerConflict',
        message: 'Workspace marker does not match its registry record.',
      );
    }
    if (workspace.identityQuality.isStrong &&
        (target.identity.quality != workspace.identityQuality ||
            target.identity.value != workspace.filesystemIdentity)) {
      throw const CockpitRegistryException(
        code: 'workspaceIdentityChanged',
        message:
            'Workspace filesystem identity changed at its registered path.',
      );
    }
    return CockpitLockedJsonUpdate.readOnly(
      state,
      _result(workspace, CockpitWorkspaceRegistrationDisposition.existing),
    );
  }

  Future<
    CockpitLockedJsonUpdate<
      CockpitRegistryState,
      CockpitWorkspaceRegistrationResult
    >
  >
  _createLocal(
    CockpitRegistryState state,
    String rootId,
    CockpitDirectoryAttestation target,
  ) async {
    final beforeWrite = await _reattestMatching(
      target,
      CockpitDirectoryAttestationScope.workspace,
    );
    final now = _clock.now().toUtc();
    final marker = CockpitWorkspaceMarker(
      workspaceId: _uniqueId(state, CockpitIdKind.workspace),
      projectId: _uniqueId(state, CockpitIdKind.project),
      checkoutId: _uniqueId(state, CockpitIdKind.checkout),
      createdAt: now,
    );
    await _markerStore.write(beforeWrite.directory.path, marker);
    final afterWrite = await _reattestMatching(
      beforeWrite,
      CockpitDirectoryAttestationScope.workspace,
    );
    final record = _record(marker, rootId, afterWrite, now);
    state.workspaces.add(record);
    return CockpitLockedJsonUpdate.write(
      state,
      _result(record, CockpitWorkspaceRegistrationDisposition.created),
    );
  }

  Future<
    CockpitLockedJsonUpdate<
      CockpitRegistryState,
      CockpitWorkspaceRegistrationResult
    >
  >
  _registerMarker(
    CockpitRegistryState state,
    String rootId,
    CockpitDirectoryAttestation target,
    CockpitWorkspaceMarker marker,
  ) async {
    if (state.retiredWorkspaceIdentities.any(
      (value) =>
          value.workspaceId == marker.workspaceId ||
          value.checkoutId == marker.checkoutId,
    )) {
      return _createLocal(state, rootId, target);
    }
    final candidates = state.workspaces
        .where(
          (value) =>
              value.workspaceId == marker.workspaceId ||
              value.checkoutId == marker.checkoutId,
        )
        .toList();
    if (candidates.isEmpty) {
      final now = _clock.now().toUtc();
      final record = _record(marker, rootId, target, now);
      state.workspaces.add(record);
      return CockpitLockedJsonUpdate.write(
        state,
        _result(record, CockpitWorkspaceRegistrationDisposition.created),
      );
    }
    if (candidates.length != 1 || !_markerMatches(candidates.single, marker)) {
      throw const CockpitRegistryException(
        code: 'ambiguousWorkspace',
        message:
            'Marker identity conflicts with live registry records; '
            'explicit rebind is required.',
      );
    }
    final source = candidates.single;
    if (source.state != CockpitWorkspaceState.active) {
      throw const CockpitRegistryException(
        code: 'workspaceNotActive',
        message: 'A retired or draining identity cannot be reauthorized.',
      );
    }
    final sourceType = await FileSystemEntity.type(
      source.canonicalPath,
      followLinks: true,
    );
    if (sourceType == FileSystemEntityType.notFound) {
      if (!_isStrongSameIdentity(source, target.identity)) {
        throw const CockpitRegistryException(
          code: 'workspaceMoveRequiresRebind',
          message: 'Missing source cannot be proven to have moved here.',
        );
      }
      final now = _clock.now().toUtc();
      final moved = source.copyWith(
        rootId: rootId,
        canonicalPath: target.directory.path,
        filesystemIdentity: target.identity.value,
        identityQuality: target.identity.quality,
        updatedAt: now,
      );
      state.workspaces[state.workspaces.indexOf(source)] = moved;
      return CockpitLockedJsonUpdate.write(
        state,
        _result(moved, CockpitWorkspaceRegistrationDisposition.moved),
      );
    }
    if (sourceType != FileSystemEntityType.directory) {
      throw const CockpitRegistryException(
        code: 'workspaceSourceConflict',
        message: 'Registered workspace path no longer names a directory.',
      );
    }
    final sourceAttestation = await _attestDirectory(source.canonicalPath);
    _verifyStoredWorkspace(
      source,
      sourceAttestation,
      code: 'workspaceSourceIdentityChanged',
    );
    if (sourceAttestation.identity.value == target.identity.value) {
      throw const CockpitRegistryException(
        code: 'ambiguousWorkspaceIdentity',
        message: 'Two live paths report the same filesystem identity.',
      );
    }
    return _copy(state, rootId, target, source.projectId);
  }
}
