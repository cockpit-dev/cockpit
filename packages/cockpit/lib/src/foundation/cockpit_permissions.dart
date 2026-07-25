import 'dart:convert';
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

  @override
  CockpitPermissionPolicy get policy =>
      CockpitPermissionPolicy.windowsRestrictedAcl;

  @override
  Future<void> hardenDirectory(Directory directory) =>
      _apply(directory.path, directory: true);

  @override
  Future<void> hardenFile(File file) => _apply(file.path, directory: false);

  Future<void> hardenDirectories(Iterable<Directory> directories) async {
    final paths = <String>[for (final directory in directories) directory.path];
    if (paths.isEmpty) return;
    final result = await cockpitRunIsolatedProcess(
      'powershell.exe',
      <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        _windowsDirectoryAclScript,
      ],
      environment: <String, String>{'COCKPIT_ACL_PATHS': jsonEncode(paths)},
    );
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not install restricted Windows ACLs: ${_bounded(result.stderr)}',
        paths.first,
      );
    }
  }

  Future<void> _apply(String path, {required bool directory}) async {
    final result = await cockpitRunIsolatedProcess(
      'powershell.exe',
      <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        _windowsAclScript,
      ],
      environment: <String, String>{
        'COCKPIT_ACL_PATH': path,
        'COCKPIT_ACL_KIND': directory ? 'directory' : 'file',
      },
    );
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not install restricted Windows ACL: ${_bounded(result.stderr)}',
        path,
      );
    }
  }
}

const _windowsAclScript = r'''
$ErrorActionPreference = 'Stop'
$path = $env:COCKPIT_ACL_PATH
$isDirectory = $env:COCKPIT_ACL_KIND -eq 'directory'
$acl = Get-Acl -LiteralPath $path
$acl.SetAccessRuleProtection($true, $false)
foreach ($rule in @($acl.Access)) {
  [void]$acl.RemoveAccessRuleSpecific($rule)
}
$current = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$administrators = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$inheritance = if ($isDirectory) {
  [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
} else {
  [System.Security.AccessControl.InheritanceFlags]::None
}
foreach ($sid in @($current, $system, $administrators)) {
  $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $sid,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    $inheritance,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
  )
  [void]$acl.AddAccessRule($rule)
}
$acl.SetOwner($current)
Set-Acl -LiteralPath $path -AclObject $acl
''';

const _windowsDirectoryAclScript = r'''
$ErrorActionPreference = 'Stop'
$paths = ConvertFrom-Json -InputObject $env:COCKPIT_ACL_PATHS
foreach ($path in @($paths)) {
  $acl = Get-Acl -LiteralPath $path
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($rule in @($acl.Access)) {
    [void]$acl.RemoveAccessRuleSpecific($rule)
  }
  $current = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $administrators = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
  $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
  foreach ($sid in @($current, $system, $administrators)) {
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
      $sid,
      [System.Security.AccessControl.FileSystemRights]::FullControl,
      $inheritance,
      [System.Security.AccessControl.PropagationFlags]::None,
      [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($rule)
  }
  $acl.SetOwner($current)
  Set-Acl -LiteralPath $path -AclObject $acl
}
''';

String _bounded(Object? value) {
  final text = value.toString().trim();
  return text.length <= 256 ? text : '${text.substring(0, 256)}...';
}
