part of 'cockpit_workspace_registry.dart';

extension _CockpitWorkspaceRegistrySupport on CockpitWorkspaceRegistry {
  Future<
    CockpitLockedJsonUpdate<
      CockpitRegistryState,
      CockpitWorkspaceRegistrationResult
    >
  >
  _copy(
    CockpitRegistryState state,
    String rootId,
    CockpitDirectoryAttestation target,
    String projectId,
  ) async {
    final beforeWrite = await _reattestMatching(
      target,
      CockpitDirectoryAttestationScope.workspace,
    );
    final now = _clock.now().toUtc();
    final marker = CockpitWorkspaceMarker(
      workspaceId: _uniqueId(state, CockpitIdKind.workspace),
      projectId: projectId,
      checkoutId: _uniqueId(state, CockpitIdKind.checkout),
      createdAt: now,
    );
    await _markerStore.write(beforeWrite.directory.path, marker);
    final afterWrite = await _reattestMatching(
      beforeWrite,
      CockpitDirectoryAttestationScope.workspace,
    );
    final copied = _record(marker, rootId, afterWrite, now);
    state.workspaces.add(copied);
    return CockpitLockedJsonUpdate.write(
      state,
      _result(copied, CockpitWorkspaceRegistrationDisposition.copied),
    );
  }

  CockpitWorkspaceRecord _record(
    CockpitWorkspaceMarker marker,
    String rootId,
    CockpitDirectoryAttestation attestation,
    DateTime now,
  ) => CockpitWorkspaceRecord(
    workspaceId: marker.workspaceId,
    projectId: marker.projectId,
    checkoutId: marker.checkoutId,
    rootId: rootId,
    canonicalPath: attestation.directory.path,
    filesystemIdentity: attestation.identity.value,
    identityQuality: attestation.identity.quality,
    state: CockpitWorkspaceState.active,
    createdAt: marker.createdAt,
    registeredAt: now,
    updatedAt: now,
  );

  CockpitRootRecord _activeContainingRoot(
    CockpitRegistryState state,
    String rootId,
    String canonicalPath,
  ) {
    final matches = state.roots.where((value) => value.rootId == rootId);
    if (matches.isEmpty) {
      throw CockpitRegistryException(
        code: 'rootNotFound',
        message: 'Allowed root $rootId was not found.',
      );
    }
    final root = matches.single;
    if (root.state != CockpitRootState.active) {
      throw CockpitRegistryException(
        code: 'rootNotActive',
        message:
            'Allowed root ${root.rootId} (${root.canonicalPath}) does not '
            'grant mutation authority.',
      );
    }
    if (!_lexicalPaths.contains(root.canonicalPath, canonicalPath)) {
      throw CockpitRegistryException(
        code: 'workspaceOutsideRoot',
        message:
            'Workspace path $canonicalPath is outside its allowed root '
            '${root.rootId} (${root.canonicalPath}).',
      );
    }
    return root;
  }

  Future<CockpitDirectoryAttestation> _attestDirectory(String path) =>
      _directoryAttestor.attest(
        path,
        CockpitDirectoryAttestationScope.workspace,
      );

  Future<_AttestedRootAuthority> _attestActiveRoot(
    String rootId,
    String targetPath,
  ) async {
    final state = await _database.read();
    final root = _activeContainingRoot(state, rootId, targetPath);
    return _attestRoot(root, targetPath);
  }

  Future<_AttestedRootAuthority> _attestRoot(
    CockpitRootRecord root,
    String targetPath,
  ) async {
    if (root.state != CockpitRootState.active) {
      throw CockpitRegistryException(
        code: 'rootNotActive',
        message:
            'Allowed root ${root.rootId} (${root.canonicalPath}) does not '
            'grant mutation authority.',
      );
    }
    if (!_lexicalPaths.contains(root.canonicalPath, targetPath)) {
      throw CockpitRegistryException(
        code: 'workspaceOutsideRoot',
        message:
            'Workspace path $targetPath is outside its allowed root '
            '${root.rootId} (${root.canonicalPath}).',
      );
    }
    final attestation = await _directoryAttestor.attest(
      root.canonicalPath,
      CockpitDirectoryAttestationScope.root,
    );
    _verifyStoredRoot(root, attestation);
    return _AttestedRootAuthority(root, attestation);
  }

  void _confirmAttestedRoot(
    CockpitRegistryState state,
    _AttestedRootAuthority expected,
    String targetPath,
  ) {
    final current = _activeContainingRoot(
      state,
      expected.root.rootId,
      targetPath,
    );
    if (!_sameRootRecord(current, expected.root)) {
      throw CockpitRegistryException(
        code: 'rootAuthorityChanged',
        message:
            'Allowed root ${expected.root.rootId} authority changed during '
            'workspace admission.',
      );
    }
  }

  Future<_AttestedWorkspaceAuthority> _attestWorkspaceAuthority(
    CockpitRegistryState state,
    CockpitWorkspaceRecord workspace,
  ) async {
    if (workspace.state != CockpitWorkspaceState.active) {
      throw const CockpitRegistryException(
        code: 'workspaceNotActive',
        message: 'Workspace does not grant mutation authority.',
      );
    }
    final workspaceAttestation = await _attestDirectory(
      workspace.canonicalPath,
    );
    _verifyStoredWorkspace(
      workspace,
      workspaceAttestation,
      code: 'workspaceIdentityChanged',
    );
    final root = _activeContainingRoot(
      state,
      workspace.rootId,
      workspace.canonicalPath,
    );
    final rootAuthority = await _attestRoot(root, workspace.canonicalPath);
    return _AttestedWorkspaceAuthority(
      workspace,
      workspaceAttestation,
      rootAuthority,
    );
  }

  Future<_AttestedWorkspaceAuthority> _reattestWorkspaceAuthority(
    _AttestedWorkspaceAuthority expected,
  ) async {
    final workspaceAttestation = await _reattestMatching(
      expected.workspaceAttestation,
      CockpitDirectoryAttestationScope.workspace,
    );
    final rootAttestation = await _reattestMatching(
      expected.rootAuthority.attestation,
      CockpitDirectoryAttestationScope.root,
    );
    _verifyStoredWorkspace(
      expected.workspace,
      workspaceAttestation,
      code: 'workspaceIdentityChanged',
    );
    _verifyStoredRoot(expected.rootAuthority.root, rootAttestation);
    return _AttestedWorkspaceAuthority(
      expected.workspace,
      workspaceAttestation,
      _AttestedRootAuthority(expected.rootAuthority.root, rootAttestation),
    );
  }

  void _confirmWorkspaceAuthority(
    CockpitRegistryState state,
    _AttestedWorkspaceAuthority expected,
  ) {
    final current = _workspace(state, expected.workspace.workspaceId);
    if (!_sameWorkspaceRecord(current, expected.workspace)) {
      throw const CockpitRegistryException(
        code: 'markerMutationConflict',
        message: 'Registry changed during marker mutation recovery.',
      );
    }
    _confirmAttestedRoot(
      state,
      expected.rootAuthority,
      expected.workspace.canonicalPath,
    );
  }

  Future<CockpitDirectoryAttestation> _reattestMatching(
    CockpitDirectoryAttestation expected,
    CockpitDirectoryAttestationScope scope,
  ) async {
    final current = await _directoryAttestor.attest(
      expected.directory.path,
      scope,
    );
    if (!_sameAttestation(expected, current)) {
      throw const CockpitRegistryException(
        code: 'directoryAttestationChanged',
        message: 'Directory authority changed between validation points.',
      );
    }
    return current;
  }

  void _verifyStoredRoot(
    CockpitRootRecord root,
    CockpitDirectoryAttestation attestation,
  ) {
    if (!_lexicalPaths.equals(root.canonicalPath, attestation.directory.path) ||
        root.identityQuality != attestation.identity.quality ||
        root.filesystemIdentity != attestation.identity.value) {
      throw const CockpitRegistryException(
        code: 'rootIdentityChanged',
        message: 'Allowed root filesystem identity changed.',
      );
    }
  }

  void _verifyStoredWorkspace(
    CockpitWorkspaceRecord workspace,
    CockpitDirectoryAttestation attestation, {
    required String code,
  }) {
    if (!_lexicalPaths.equals(
          workspace.canonicalPath,
          attestation.directory.path,
        ) ||
        workspace.identityQuality != attestation.identity.quality ||
        workspace.filesystemIdentity != attestation.identity.value) {
      throw CockpitRegistryException(
        code: code,
        message: 'Registered workspace filesystem identity changed.',
      );
    }
  }

  bool _sameAttestation(
    CockpitDirectoryAttestation left,
    CockpitDirectoryAttestation right,
  ) =>
      _lexicalPaths.equals(left.directory.path, right.directory.path) &&
      left.identity.quality == right.identity.quality &&
      left.identity.value == right.identity.value &&
      left.security.posixApplicable == right.security.posixApplicable &&
      left.security.ownerVerified == right.security.ownerVerified &&
      left.security.ownerTrusted == right.security.ownerTrusted &&
      left.security.unsafeWritable == right.security.unsafeWritable &&
      left.security.mode == right.security.mode;

  bool _sameRootRecord(CockpitRootRecord left, CockpitRootRecord right) =>
      left.rootId == right.rootId &&
      _lexicalPaths.equals(left.canonicalPath, right.canonicalPath) &&
      left.filesystemIdentity == right.filesystemIdentity &&
      left.identityQuality == right.identityQuality &&
      left.state == right.state &&
      left.registeredAt == right.registeredAt &&
      left.updatedAt == right.updatedAt &&
      left.retiredAt == right.retiredAt;

  bool _sameWorkspaceRecord(
    CockpitWorkspaceRecord left,
    CockpitWorkspaceRecord right,
  ) =>
      left.workspaceId == right.workspaceId &&
      left.projectId == right.projectId &&
      left.checkoutId == right.checkoutId &&
      left.rootId == right.rootId &&
      _lexicalPaths.equals(left.canonicalPath, right.canonicalPath) &&
      left.filesystemIdentity == right.filesystemIdentity &&
      left.identityQuality == right.identityQuality &&
      left.state == right.state &&
      left.createdAt == right.createdAt &&
      left.registeredAt == right.registeredAt &&
      left.updatedAt == right.updatedAt &&
      left.retiredAt == right.retiredAt;

  String _uniqueId(CockpitRegistryState state, CockpitIdKind kind) {
    for (var attempt = 0; attempt < 32; attempt += 1) {
      final candidate = _idGenerator.next(kind);
      final exists = switch (kind) {
        CockpitIdKind.root => state.roots.any(
          (value) => value.rootId == candidate,
        ),
        CockpitIdKind.workspace => state.workspaces.any(
          (value) => value.workspaceId == candidate,
        ),
        CockpitIdKind.checkout => state.workspaces.any(
          (value) => value.checkoutId == candidate,
        ),
        CockpitIdKind.project => state.workspaces.any(
          (value) => value.projectId == candidate,
        ),
        CockpitIdKind.lease || CockpitIdKind.cleanup => throw ArgumentError(
          'Lease identifiers cannot be allocated by the workspace registry.',
        ),
      };
      if (!exists) return candidate;
    }
    throw const CockpitRegistryException(
      code: 'idGenerationFailed',
      message: 'Could not generate a unique secure identifier.',
    );
  }

  bool _markerMatches(
    CockpitWorkspaceRecord workspace,
    CockpitWorkspaceMarker marker,
  ) =>
      workspace.workspaceId == marker.workspaceId &&
      workspace.projectId == marker.projectId &&
      workspace.checkoutId == marker.checkoutId &&
      workspace.createdAt == marker.createdAt;

  bool _isStrongSameIdentity(
    CockpitWorkspaceRecord source,
    CockpitFilesystemIdentity target,
  ) =>
      source.identityQuality.isStrong &&
      target.quality.isStrong &&
      source.identityQuality == target.quality &&
      source.filesystemIdentity == target.value;

  CockpitWorkspaceRegistrationResult _result(
    CockpitWorkspaceRecord workspace,
    CockpitWorkspaceRegistrationDisposition disposition,
  ) => CockpitWorkspaceRegistrationResult(
    workspaceId: workspace.workspaceId,
    projectId: workspace.projectId,
    checkoutId: workspace.checkoutId,
    rootId: workspace.rootId,
    canonicalPath: workspace.canonicalPath,
    disposition: disposition,
  );

  CockpitWorkspaceRecord _workspace(
    CockpitRegistryState state,
    String workspaceId,
  ) {
    final matches = state.workspaces.where(
      (value) => value.workspaceId == workspaceId,
    );
    if (matches.isEmpty) {
      throw const CockpitRegistryException(
        code: 'workspaceNotFound',
        message: 'Workspace was not found.',
      );
    }
    return matches.single;
  }
}

final class _AttestedRootAuthority {
  const _AttestedRootAuthority(this.root, this.attestation);

  final CockpitRootRecord root;
  final CockpitDirectoryAttestation attestation;
}

final class _AttestedWorkspaceAuthority {
  const _AttestedWorkspaceAuthority(
    this.workspace,
    this.workspaceAttestation,
    this.rootAuthority,
  );

  final CockpitWorkspaceRecord workspace;
  final CockpitDirectoryAttestation workspaceAttestation;
  final _AttestedRootAuthority rootAuthority;
}
