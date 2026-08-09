import 'package:path/path.dart' as p;

import '../foundation/cockpit_filesystem_identity.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_windows_security.dart';
import 'cockpit_registry_models.dart';

abstract interface class CockpitDirectoryAncestorPolicy {
  Future<void> verify(String canonicalPath);
}

final class CockpitSystemDirectoryAncestorPolicy
    implements CockpitDirectoryAncestorPolicy {
  const CockpitSystemDirectoryAncestorPolicy({
    required CockpitHostPlatform platform,
    required CockpitPosixMetadataProvider metadataProvider,
    CockpitWindowsSecurityProvider windowsSecurityProvider =
        const CockpitNativeWindowsSecurityProvider(),
  }) : _platform = platform,
       _metadataProvider = metadataProvider,
       _windowsSecurityProvider = windowsSecurityProvider;

  final CockpitHostPlatform _platform;
  final CockpitPosixMetadataProvider _metadataProvider;
  final CockpitWindowsSecurityProvider _windowsSecurityProvider;

  @override
  Future<void> verify(String canonicalPath) async {
    final ancestors = _ancestorPaths(canonicalPath);
    if (_platform == CockpitHostPlatform.windows) {
      await _verifyWindows(ancestors);
      return;
    }
    await _verifyPosix(ancestors, canonicalPath);
  }

  Future<void> _verifyWindows(List<String> ancestors) async {
    for (final ancestor in ancestors) {
      final security = await _windowsSecurityProvider.inspect(ancestor);
      if (!security.ownerTrusted) {
        _throwUntrustedOwner(ancestor);
      }
      if (security.unsafeWritable && !_isWindowsDriveRoot(ancestor)) {
        _throwUnsafePermissions(ancestor);
      }
    }
  }

  Future<void> _verifyPosix(
    List<String> ancestors,
    String canonicalPath,
  ) async {
    final currentUserId = await _metadataProvider.currentUserId();
    if (currentUserId == null) {
      throw const CockpitRegistryException(
        code: 'directoryAncestorInspectionFailed',
        message: 'Could not identify the current user for ancestor checks.',
      );
    }
    for (var index = 0; index < ancestors.length; index += 1) {
      final ancestor = ancestors[index];
      final metadata = await _requiredMetadata(ancestor);
      if (!_isTrustedOwner(metadata.ownerUserId, currentUserId)) {
        _throwUntrustedOwner(ancestor);
      }
      if (!_isUnsafeWritable(metadata.mode)) continue;
      final child = index + 1 < ancestors.length
          ? ancestors[index + 1]
          : canonicalPath;
      final stickyWorldWritable =
          metadata.mode & 0x200 != 0 && metadata.mode & 0x2 != 0;
      if (!stickyWorldWritable) {
        _throwUnsafePermissions(ancestor);
      }
      final childMetadata = await _requiredMetadata(child);
      if (!_isTrustedOwner(childMetadata.ownerUserId, currentUserId)) {
        _throwUntrustedOwner(child);
      }
    }
  }

  Future<CockpitPosixMetadata> _requiredMetadata(String path) async {
    final metadata = await _metadataProvider.read(path);
    if (metadata == null) {
      throw CockpitRegistryException(
        code: 'directoryAncestorInspectionFailed',
        message: 'Could not inspect directory ancestor: $path',
      );
    }
    return metadata;
  }

  List<String> _ancestorPaths(String canonicalPath) {
    final context = _platform == CockpitHostPlatform.windows
        ? p.windows
        : p.posix;
    final target = context.normalize(canonicalPath);
    var current = context.dirname(target);
    if (_samePath(current, target)) return const <String>[];
    final result = <String>[];
    while (true) {
      result.add(current);
      final parent = context.dirname(current);
      if (_samePath(parent, current)) break;
      current = parent;
    }
    return result.reversed.toList(growable: false);
  }

  bool _samePath(String left, String right) {
    if (_platform == CockpitHostPlatform.windows) {
      return left.toLowerCase() == right.toLowerCase();
    }
    return left == right;
  }

  bool _isWindowsDriveRoot(String path) =>
      path.length == 3 &&
      ((path.codeUnitAt(0) >= 0x41 && path.codeUnitAt(0) <= 0x5a) ||
          (path.codeUnitAt(0) >= 0x61 && path.codeUnitAt(0) <= 0x7a)) &&
      path.codeUnitAt(1) == 0x3a &&
      path.codeUnitAt(2) == 0x5c;

  bool _isTrustedOwner(int ownerUserId, int currentUserId) =>
      ownerUserId == currentUserId || ownerUserId == 0;

  bool _isUnsafeWritable(int mode) => mode & 0x12 != 0;

  Never _throwUntrustedOwner(String path) {
    throw CockpitRegistryException(
      code: 'directoryAncestorOwnerUntrusted',
      message: 'Directory ancestor has an untrusted owner: $path',
    );
  }

  Never _throwUnsafePermissions(String path) {
    throw CockpitRegistryException(
      code: 'directoryAncestorUnsafePermissions',
      message: 'Directory ancestor grants unsafe mutation authority: $path',
    );
  }
}
