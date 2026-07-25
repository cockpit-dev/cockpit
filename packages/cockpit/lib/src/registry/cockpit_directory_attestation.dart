import 'dart:io';

import '../foundation/cockpit_canonical_paths.dart';
import '../foundation/cockpit_filesystem_identity.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_windows_directory_authority.dart';
import 'cockpit_directory_ancestor_policy.dart';
import 'cockpit_registry_models.dart';

enum CockpitDirectoryAttestationScope { root, workspace }

final class CockpitDirectoryAttestation {
  const CockpitDirectoryAttestation({
    required this.directory,
    required this.identity,
    required this.security,
  });

  final CockpitCanonicalDirectory directory;
  final CockpitFilesystemIdentity identity;
  final CockpitDirectorySecurity security;
}

abstract interface class CockpitDirectoryAttestationProvider {
  Future<CockpitDirectoryAttestation> attest(
    String path,
    CockpitDirectoryAttestationScope scope,
  );
}

final class CockpitDirectoryAttestor
    implements CockpitDirectoryAttestationProvider {
  const CockpitDirectoryAttestor({
    required CockpitCanonicalDirectoryResolver directoryResolver,
    required CockpitFilesystemIdentityProvider identityProvider,
    required CockpitDirectorySecurityInspector securityInspector,
    required CockpitDirectoryAncestorPolicy ancestorPolicy,
    required CockpitLexicalPaths lexicalPaths,
    required bool requireStrongIdentity,
  }) : _directoryResolver = directoryResolver,
       _identityProvider = identityProvider,
       _securityInspector = securityInspector,
       _ancestorPolicy = ancestorPolicy,
       _lexicalPaths = lexicalPaths,
       _requireStrongIdentity = requireStrongIdentity;

  final CockpitCanonicalDirectoryResolver _directoryResolver;
  final CockpitFilesystemIdentityProvider _identityProvider;
  final CockpitDirectorySecurityInspector _securityInspector;
  final CockpitDirectoryAncestorPolicy _ancestorPolicy;
  final CockpitLexicalPaths _lexicalPaths;
  final bool _requireStrongIdentity;

  @override
  Future<CockpitDirectoryAttestation> attest(
    String path,
    CockpitDirectoryAttestationScope scope,
  ) async {
    final beforeDirectory = await _directoryResolver.resolve(path);
    final beforeIdentity = await _identityProvider.identify(
      beforeDirectory.path,
    );
    final beforeSecurity = await _securityInspector.inspect(
      beforeDirectory.path,
    );
    await _ancestorPolicy.verify(beforeDirectory.path);
    final afterDirectory = await _directoryResolver.resolve(path);
    final afterIdentity = await _identityProvider.identify(afterDirectory.path);
    final afterSecurity = await _securityInspector.inspect(afterDirectory.path);
    if (!_lexicalPaths.equals(beforeDirectory.path, afterDirectory.path) ||
        beforeIdentity.quality != afterIdentity.quality ||
        beforeIdentity.value != afterIdentity.value ||
        !_sameSecurity(beforeSecurity, afterSecurity)) {
      _throwAttestationChanged();
    }
    if (_requireStrongIdentity && !afterIdentity.quality.isStrong) {
      throw const CockpitRegistryException(
        code: 'directoryIdentityNotStrong',
        message: 'System directory authority requires a strong identity.',
      );
    }
    _validateTargetSecurity(afterSecurity, scope);
    return CockpitDirectoryAttestation(
      directory: afterDirectory,
      identity: afterIdentity,
      security: afterSecurity,
    );
  }
}

final class CockpitSystemDirectoryAttestor
    implements CockpitDirectoryAttestationProvider {
  const CockpitSystemDirectoryAttestor({
    required CockpitHostPlatform platform,
    required CockpitCanonicalDirectoryResolver directoryResolver,
    required CockpitPosixMetadataProvider metadataProvider,
    required CockpitDirectoryAncestorPolicy ancestorPolicy,
    required CockpitLexicalPaths lexicalPaths,
    CockpitWindowsDirectoryAuthorityProvider windowsAuthorityProvider =
        const CockpitWindowsDirectoryAuthorityProvider(),
  }) : _platform = platform,
       _directoryResolver = directoryResolver,
       _metadataProvider = metadataProvider,
       _ancestorPolicy = ancestorPolicy,
       _lexicalPaths = lexicalPaths,
       _windowsAuthorityProvider = windowsAuthorityProvider;

  final CockpitHostPlatform _platform;
  final CockpitCanonicalDirectoryResolver _directoryResolver;
  final CockpitPosixMetadataProvider _metadataProvider;
  final CockpitDirectoryAncestorPolicy _ancestorPolicy;
  final CockpitLexicalPaths _lexicalPaths;
  final CockpitWindowsDirectoryAuthorityProvider _windowsAuthorityProvider;

  @override
  Future<CockpitDirectoryAttestation> attest(
    String path,
    CockpitDirectoryAttestationScope scope,
  ) async {
    final currentUserId = _platform == CockpitHostPlatform.windows
        ? null
        : await _metadataProvider.currentUserId();
    if (_platform != CockpitHostPlatform.windows && currentUserId == null) {
      throw FileSystemException(
        'Could not identify the current user for directory attestation.',
        path,
      );
    }
    final beforeDirectory = await _directoryResolver.resolve(path);
    final beforeSnapshot = await _snapshot(beforeDirectory.path, currentUserId);
    await _ancestorPolicy.verify(beforeDirectory.path);
    final afterDirectory = await _directoryResolver.resolve(path);
    final afterSnapshot = await _snapshot(afterDirectory.path, currentUserId);
    if (!_lexicalPaths.equals(beforeDirectory.path, afterDirectory.path) ||
        !_sameSnapshot(beforeSnapshot, afterSnapshot)) {
      _throwAttestationChanged();
    }
    if (!afterSnapshot.identity.quality.isStrong) {
      throw const CockpitRegistryException(
        code: 'directoryIdentityNotStrong',
        message: 'System directory authority requires a strong identity.',
      );
    }
    _validateTargetSecurity(afterSnapshot.security, scope);
    return CockpitDirectoryAttestation(
      directory: afterDirectory,
      identity: afterSnapshot.identity,
      security: afterSnapshot.security,
    );
  }

  Future<CockpitDirectoryAuthoritySnapshot> _snapshot(
    String canonicalPath,
    int? currentUserId,
  ) async {
    if (_platform == CockpitHostPlatform.windows) {
      return _windowsAuthorityProvider.inspect(canonicalPath);
    }
    final metadata = await _metadataProvider.read(canonicalPath);
    if (metadata == null) {
      throw FileSystemException(
        'Could not read coherent POSIX directory authority.',
        canonicalPath,
      );
    }
    return CockpitDirectoryAuthoritySnapshot(
      identity: CockpitFilesystemIdentity(
        value: cockpitPosixFilesystemIdentityValue(metadata),
        quality: CockpitFilesystemIdentityQuality.deviceAndInode,
      ),
      security: CockpitDirectorySecurity(
        posixApplicable: true,
        ownerVerified: metadata.ownerUserId == currentUserId,
        ownerTrusted:
            metadata.ownerUserId == currentUserId || metadata.ownerUserId == 0,
        unsafeWritable: metadata.mode & 0x12 != 0,
        mode: metadata.mode,
      ),
    );
  }
}

bool _sameSnapshot(
  CockpitDirectoryAuthoritySnapshot left,
  CockpitDirectoryAuthoritySnapshot right,
) =>
    left.identity.quality == right.identity.quality &&
    left.identity.value == right.identity.value &&
    _sameSecurity(left.security, right.security);

bool _sameSecurity(
  CockpitDirectorySecurity left,
  CockpitDirectorySecurity right,
) =>
    left.posixApplicable == right.posixApplicable &&
    left.ownerVerified == right.ownerVerified &&
    left.ownerTrusted == right.ownerTrusted &&
    left.unsafeWritable == right.unsafeWritable &&
    left.mode == right.mode;

void _validateTargetSecurity(
  CockpitDirectorySecurity security,
  CockpitDirectoryAttestationScope scope,
) {
  if (!security.ownerVerified) {
    throw CockpitRegistryException(
      code: scope == CockpitDirectoryAttestationScope.root
          ? 'rootOwnershipMismatch'
          : 'workspaceOwnershipMismatch',
      message: 'Directory must be owned by the current user.',
    );
  }
  if (security.unsafeWritable) {
    throw CockpitRegistryException(
      code: scope == CockpitDirectoryAttestationScope.root
          ? 'rootUnsafePermissions'
          : 'workspaceUnsafePermissions',
      message: 'Directory must not be writable by unsafe principals.',
    );
  }
}

Never _throwAttestationChanged() {
  throw const CockpitRegistryException(
    code: 'directoryAttestationChanged',
    message: 'Directory changed while its authority was being verified.',
  );
}
