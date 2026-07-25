import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';

enum CockpitPermissionPolicy {
  posixOwnerOnly,
  windowsRestrictedAcl,
  windowsInheritedAcl,
}

abstract interface class CockpitPermissionHardener {
  CockpitPermissionPolicy get policy;

  Future<void> hardenDirectory(Directory directory);

  Future<void> hardenFile(File file);
}

final class CockpitPosixPermissionHardener
    implements CockpitPermissionHardener {
  const CockpitPosixPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {
    await _chmod(directory.path, '700');
  }

  @override
  Future<void> hardenFile(File file) async {
    await _chmod(file.path, '600');
  }

  Future<void> _chmod(String path, String mode) async {
    final result = await cockpitRunIsolatedProcess('chmod', <String>[
      mode,
      path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not apply mode $mode: ${_bounded(result.stderr)}',
        path,
      );
    }
  }
}

/// Dart-created files inherit the current user's Windows ACL. This boundary is
/// deliberately explicit: it does not claim to have installed or verified an
/// ACL that `dart:io` cannot manage.
final class CockpitWindowsInheritedAclPermissionHardener
    implements CockpitPermissionHardener {
  const CockpitWindowsInheritedAclPermissionHardener();

  @override
  CockpitPermissionPolicy get policy =>
      CockpitPermissionPolicy.windowsInheritedAcl;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class CockpitWindowsAclPermissionHardener
    implements CockpitPermissionHardener {
  const CockpitWindowsAclPermissionHardener();

  static Future<String>? _currentSid;

  @override
  CockpitPermissionPolicy get policy =>
      CockpitPermissionPolicy.windowsRestrictedAcl;

  @override
  Future<void> hardenDirectory(Directory directory) =>
      _apply(directory.path, directory: true);

  @override
  Future<void> hardenFile(File file) => _apply(file.path, directory: false);

  Future<void> hardenDirectories(Iterable<Directory> directories) async {
    for (final directory in directories) {
      await _apply(directory.path, directory: true);
    }
  }

  Future<void> _apply(String path, {required bool directory}) async {
    final sid = await (_currentSid ??= _readCurrentSid());
    await _runIcacls(path, const <String>['/reset', '/Q', '/C']);
    final inheritance = directory ? '(OI)(CI)' : '';
    await _runIcacls(path, <String>[
      '/inheritance:r',
      '/grant:r',
      '*$sid:$inheritance(F)',
      '*S-1-5-18:$inheritance(F)',
      '*S-1-5-32-544:$inheritance(F)',
      '/Q',
      '/C',
    ]);
    await _runIcacls(path, <String>['/setowner', '*$sid', '/Q', '/C']);
  }

  static Future<String> _readCurrentSid() async {
    final result = await cockpitRunIsolatedProcess('whoami.exe', const <String>[
      '/user',
      '/fo',
      'csv',
      '/nh',
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not resolve the current Windows identity: ${_bounded(result.stderr)}',
      );
    }
    final match = RegExp(
      r'S-\d-(?:\d+-)+\d+',
      caseSensitive: false,
    ).firstMatch(result.stdout.toString());
    if (match == null) {
      throw const FileSystemException(
        'Could not parse the current Windows identity.',
      );
    }
    return match.group(0)!;
  }

  static Future<void> _runIcacls(String path, List<String> arguments) async {
    final result = await cockpitRunIsolatedProcess('icacls.exe', <String>[
      path,
      ...arguments,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not install restricted Windows ACL: ${_bounded(result.stderr)}',
        path,
      );
    }
  }
}

String _bounded(Object? value) {
  final text = value.toString().trim();
  return text.length <= 256 ? text : '${text.substring(0, 256)}...';
}
