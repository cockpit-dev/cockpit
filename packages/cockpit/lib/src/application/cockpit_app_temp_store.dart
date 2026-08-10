import 'dart:io';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_permissions.dart';

final RegExp _appTempKeyPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
);

/// Owns host temporary directories inherited by desktop Flutter applications.
///
/// These directories intentionally outlive a workspace worker so a detached
/// Flutter application can keep using temporary files after Cockpit reconnects.
final class CockpitAppTempStore {
  /// Creates a store rooted at an absolute, workspace-isolated host path.
  CockpitAppTempStore({
    required String root,
    required CockpitPermissionHardener permissionHardener,
  }) : root = p.normalize(root),
       _permissionHardener = permissionHardener {
    if (!p.isAbsolute(this.root)) {
      throw ArgumentError.value(root, 'root', 'Path must be absolute.');
    }
  }

  /// Absolute directory containing one child directory per live app runtime.
  final String root;
  final CockpitPermissionHardener _permissionHardener;

  /// Creates or reopens the stable temporary directory for [key].
  Future<String> prepare(String key) async {
    _validateKey(key);
    try {
      final canonicalRoot = await _prepareDirectory(
        Directory(root),
        expectedParent: null,
      );
      return (await _prepareDirectory(
        Directory(p.join(canonicalRoot.path, key)),
        expectedParent: canonicalRoot.path,
      )).path;
    } on Object catch (error, stackTrace) {
      try {
        await release(key);
      } on Object {
        // Preserve the preparation failure, which explains why the directory
        // is unsafe or unusable. Cleanup is retried by later lifecycle work.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Removes the stable temporary directory for [key], when present.
  Future<void> release(String key) async {
    _validateKey(key);
    final rootType = await FileSystemEntity.type(root, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) return;
    if (rootType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Application temporary root is not a directory.',
        root,
      );
    }
    final canonicalRoot = p.normalize(
      await Directory(root).resolveSymbolicLinks(),
    );
    final appPath = p.join(canonicalRoot, key);
    final appType = await FileSystemEntity.type(appPath, followLinks: false);
    if (appType == FileSystemEntityType.notFound) return;
    if (appType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Application temporary path is not a directory.',
        appPath,
      );
    }
    final canonicalApp = p.normalize(
      await Directory(appPath).resolveSymbolicLinks(),
    );
    if (!p.isWithin(canonicalRoot, canonicalApp)) {
      throw FileSystemException(
        'Application temporary path escaped its root.',
        appPath,
      );
    }
    await Directory(canonicalApp).delete(recursive: true);
  }

  Future<Directory> _prepareDirectory(
    Directory directory, {
    required String? expectedParent,
  }) async {
    final existingType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (existingType == FileSystemEntityType.notFound) {
      await directory.create(recursive: expectedParent == null);
    } else if (existingType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Application temporary path is not a directory.',
        directory.path,
      );
    }
    await _permissionHardener.hardenDirectory(directory);
    final canonical = p.normalize(await directory.resolveSymbolicLinks());
    if (expectedParent != null && !p.isWithin(expectedParent, canonical)) {
      throw FileSystemException(
        'Application temporary path escaped its root.',
        directory.path,
      );
    }
    return Directory(canonical);
  }

  void _validateKey(String key) {
    if (!_appTempKeyPattern.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Invalid application temp key.');
    }
  }
}

/// Whether desktop apps on [platform] require host-managed temporary state.
bool cockpitUsesManagedAppTemp(String platform) =>
    switch (platform.trim().toLowerCase()) {
      'macos' || 'linux' || 'windows' => true,
      _ => false,
    };

/// Returns the stable store key for a remote desktop app bound to [hostPort].
String cockpitRemoteAppTempKey({
  required String platform,
  required int hostPort,
}) {
  final normalizedPlatform = platform.trim().toLowerCase();
  if (!cockpitUsesManagedAppTemp(normalizedPlatform)) {
    throw ArgumentError.value(
      platform,
      'platform',
      'Remote app temp is only managed for desktop platforms.',
    );
  }
  if (hostPort < 1 || hostPort > 65535) {
    throw ArgumentError.value(hostPort, 'hostPort', 'Invalid host port.');
  }
  return 'remote-$normalizedPlatform-$hostPort';
}

/// Returns the cross-platform temporary environment for an app directory.
Map<String, String> cockpitAppTempEnvironment(String path) =>
    Map<String, String>.unmodifiable(<String, String>{
      'TMPDIR': path,
      'TMP': path,
      'TEMP': path,
    });
