import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_home.dart';

enum CockpitFilesystemIdentityQuality {
  deviceAndInode,
  windowsVolumeAndFileId,
  stablePathFallback,
}

extension CockpitFilesystemIdentityQualityStrength
    on CockpitFilesystemIdentityQuality {
  bool get isStrong => switch (this) {
    CockpitFilesystemIdentityQuality.deviceAndInode ||
    CockpitFilesystemIdentityQuality.windowsVolumeAndFileId => true,
    CockpitFilesystemIdentityQuality.stablePathFallback => false,
  };
}

final class CockpitFilesystemIdentity {
  const CockpitFilesystemIdentity({required this.value, required this.quality});

  final String value;
  final CockpitFilesystemIdentityQuality quality;
}

final class CockpitPosixMetadata {
  const CockpitPosixMetadata({
    required this.device,
    required this.inode,
    required this.ownerUserId,
    required this.mode,
    this.objectInstance,
  });

  final int device;
  final int inode;
  final int ownerUserId;
  final int mode;
  final String? objectInstance;
}

abstract interface class CockpitPosixMetadataProvider {
  Future<CockpitPosixMetadata?> read(String canonicalPath);

  Future<int?> currentUserId();
}

final class CockpitSystemPosixMetadataProvider
    implements CockpitPosixMetadataProvider {
  const CockpitSystemPosixMetadataProvider(this.platform);

  final CockpitHostPlatform platform;

  @override
  Future<CockpitPosixMetadata?> read(String canonicalPath) async {
    if (platform == CockpitHostPlatform.windows) {
      return null;
    }
    final arguments = platform == CockpitHostPlatform.macos
        ? <String>['-f', '%d|%i|%u|%p|%B|%v', canonicalPath]
        : <String>['-c', '%d|%i|%u|%a|%w', canonicalPath];
    final result = await cockpitRunIsolatedProcess('stat', arguments);
    if (result.exitCode != 0) {
      return null;
    }
    final fields = result.stdout.toString().trim().split('|');
    final expectedFields = platform == CockpitHostPlatform.macos ? 6 : 5;
    if (fields.length != expectedFields) {
      return null;
    }
    final device = int.tryParse(fields[0]);
    final inode = int.tryParse(fields[1]);
    final owner = int.tryParse(fields[2]);
    final mode = int.tryParse(fields[3], radix: 8);
    if (device == null || inode == null || owner == null || mode == null) {
      return null;
    }
    return CockpitPosixMetadata(
      device: device,
      inode: inode,
      ownerUserId: owner,
      mode: mode,
      objectInstance: _posixObjectInstance(platform, fields),
    );
  }

  @override
  Future<int?> currentUserId() async {
    if (platform == CockpitHostPlatform.windows) {
      return null;
    }
    final result = await cockpitRunIsolatedProcess('id', const <String>['-u']);
    return result.exitCode == 0
        ? int.tryParse(result.stdout.toString().trim())
        : null;
  }
}

abstract interface class CockpitFilesystemIdentityProvider {
  Future<CockpitFilesystemIdentity> identify(String canonicalPath);
}

abstract interface class CockpitWindowsSecurityProvider {
  Future<CockpitDirectorySecurity> inspect(String canonicalPath);
}

final class CockpitPowerShellWindowsSecurityProvider
    implements CockpitWindowsSecurityProvider {
  const CockpitPowerShellWindowsSecurityProvider();

  @override
  Future<CockpitDirectorySecurity> inspect(String canonicalPath) async {
    final result = await cockpitRunIsolatedProcess(
      'powershell.exe',
      <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        cockpitWindowsSecurityInspectionPowerShell,
      ],
      environment: <String, String>{
        'COCKPIT_DIRECTORY_SECURITY_PATH': canonicalPath,
      },
    );
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not verify Windows directory ACL.',
        canonicalPath,
      );
    }
    final fields = result.stdout.toString().trim().toLowerCase().split('|');
    if (fields.length != 3 ||
        !const <String>{'true', 'false'}.contains(fields[0]) ||
        !const <String>{'true', 'false'}.contains(fields[1]) ||
        !const <String>{'true', 'false'}.contains(fields[2])) {
      throw FileSystemException(
        'Windows directory ACL verifier returned invalid data.',
        canonicalPath,
      );
    }
    return CockpitDirectorySecurity(
      posixApplicable: false,
      ownerVerified: fields[0] == 'true',
      ownerTrusted: fields[1] == 'true',
      unsafeWritable: fields[2] == 'true',
    );
  }
}

final class CockpitBestEffortFilesystemIdentityProvider
    implements CockpitFilesystemIdentityProvider {
  const CockpitBestEffortFilesystemIdentityProvider(this.metadataProvider);

  final CockpitPosixMetadataProvider metadataProvider;

  @override
  Future<CockpitFilesystemIdentity> identify(String canonicalPath) async {
    final metadata = await metadataProvider.read(canonicalPath);
    if (metadata != null) {
      return CockpitFilesystemIdentity(
        value: cockpitPosixFilesystemIdentityValue(metadata),
        quality: CockpitFilesystemIdentityQuality.deviceAndInode,
      );
    }
    final digest = sha256.convert(utf8.encode(canonicalPath)).toString();
    return CockpitFilesystemIdentity(
      value: 'path-sha256:$digest',
      quality: CockpitFilesystemIdentityQuality.stablePathFallback,
    );
  }
}

final class CockpitPosixFilesystemIdentityProvider
    implements CockpitFilesystemIdentityProvider {
  const CockpitPosixFilesystemIdentityProvider(this.metadataProvider);

  final CockpitPosixMetadataProvider metadataProvider;

  @override
  Future<CockpitFilesystemIdentity> identify(String canonicalPath) async {
    final metadata = await metadataProvider.read(canonicalPath);
    if (metadata == null) {
      throw FileSystemException(
        'Could not read stable POSIX filesystem identity.',
        canonicalPath,
      );
    }
    return CockpitFilesystemIdentity(
      value: cockpitPosixFilesystemIdentityValue(metadata),
      quality: CockpitFilesystemIdentityQuality.deviceAndInode,
    );
  }
}

String cockpitPosixFilesystemIdentityValue(CockpitPosixMetadata metadata) {
  final base = 'posix:${metadata.device}:${metadata.inode}';
  final objectInstance = metadata.objectInstance;
  if (objectInstance == null) return base;
  final digest = sha256.convert(utf8.encode(objectInstance));
  return '$base:$digest';
}

String? _posixObjectInstance(
  CockpitHostPlatform platform,
  List<String> fields,
) {
  if (platform == CockpitHostPlatform.macos) {
    final birthTime = int.tryParse(fields[4]);
    final generation = int.tryParse(fields[5]);
    if (birthTime == null || birthTime <= 0 || generation == null) return null;
    return 'birth=$birthTime;generation=$generation';
  }
  final birthTime = fields[4].trim();
  return birthTime.isEmpty || birthTime == '-' ? null : 'birth=$birthTime';
}

final class CockpitDirectorySecurity {
  const CockpitDirectorySecurity({
    required this.posixApplicable,
    required this.ownerVerified,
    required this.unsafeWritable,
    bool? ownerTrusted,
    this.mode,
  }) : ownerTrusted = ownerTrusted ?? ownerVerified;

  final bool posixApplicable;
  final bool ownerVerified;
  final bool ownerTrusted;
  final bool unsafeWritable;
  final int? mode;
}

final class CockpitDirectoryAuthoritySnapshot {
  const CockpitDirectoryAuthoritySnapshot({
    required this.identity,
    required this.security,
  });

  final CockpitFilesystemIdentity identity;
  final CockpitDirectorySecurity security;
}

final class CockpitDirectorySecurityInspector {
  const CockpitDirectorySecurityInspector({
    required this.platform,
    required this.metadataProvider,
    this.windowsSecurityProvider =
        const CockpitPowerShellWindowsSecurityProvider(),
  });

  final CockpitHostPlatform platform;
  final CockpitPosixMetadataProvider metadataProvider;
  final CockpitWindowsSecurityProvider windowsSecurityProvider;

  Future<CockpitDirectorySecurity> inspect(String canonicalPath) async {
    if (platform == CockpitHostPlatform.windows) {
      return windowsSecurityProvider.inspect(canonicalPath);
    }
    final metadata = await metadataProvider.read(canonicalPath);
    final userId = await metadataProvider.currentUserId();
    if (metadata == null || userId == null) {
      throw FileSystemException(
        'Could not verify directory ownership and permissions.',
        canonicalPath,
      );
    }
    return CockpitDirectorySecurity(
      posixApplicable: true,
      ownerVerified: metadata.ownerUserId == userId,
      ownerTrusted: metadata.ownerUserId == userId || metadata.ownerUserId == 0,
      unsafeWritable: metadata.mode & 0x12 != 0,
      mode: metadata.mode,
    );
  }
}

const cockpitWindowsSecurityInspectionPowerShell = r'''
$ErrorActionPreference = 'Stop'
$path = $env:COCKPIT_DIRECTORY_SECURITY_PATH
$acl = Get-Acl -LiteralPath $path
$descriptor = $acl.GetSecurityDescriptorBinaryForm()
$control = [System.BitConverter]::ToUInt16($descriptor, 2)
$daclOffset = [System.BitConverter]::ToUInt32($descriptor, 16)
$daclPresent = (($control -band 0x0004) -ne 0) -and ($daclOffset -ne 0)
$current = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
$allowedWriters = @(
  $current.Value,
  'S-1-5-18',
  'S-1-5-32-544',
  'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
)
# Generic rights may remain unexpanded in an ACE.
$writeRights =
  [System.Security.AccessControl.FileSystemRights]::WriteData -bor
  [System.Security.AccessControl.FileSystemRights]::AppendData -bor
  [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
  [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor
  [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
  [System.Security.AccessControl.FileSystemRights]::Delete -bor
  [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
  [System.Security.AccessControl.FileSystemRights]::TakeOwnership -bor
  0x40000000 -bor
  0x10000000
$unsafe = -not $daclPresent
$rules = $acl.GetAccessRules(
  $true,
  $true,
  [System.Security.Principal.SecurityIdentifier]
)
foreach ($rule in $rules) {
  if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
    continue
  }
  $sid = $rule.IdentityReference.Value
  if ($allowedWriters -notcontains $sid -and (($rule.FileSystemRights -band $writeRights) -ne 0)) {
    $unsafe = $true
  }
}
Write-Output "$(($owner.Value -eq $current.Value).ToString())|$(($allowedWriters -contains $owner.Value).ToString())|$($unsafe.ToString())"
''';
