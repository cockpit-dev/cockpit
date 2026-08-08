import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_filesystem_identity.dart';
import 'cockpit_windows_filesystem_identity.dart';

abstract interface class CockpitWindowsDirectoryAuthorityProbe {
  Future<CockpitWindowsFileIdentityProbeResult> inspect(String canonicalPath);
}

final class CockpitSystemWindowsDirectoryAuthorityProbe
    implements CockpitWindowsDirectoryAuthorityProbe {
  const CockpitSystemWindowsDirectoryAuthorityProbe();

  @override
  Future<CockpitWindowsFileIdentityProbeResult> inspect(
    String canonicalPath,
  ) async {
    CockpitWindowsFileIdentityLease? lease;
    try {
      lease = CockpitWindowsFileIdentityLease.open(
        canonicalPath,
        shareDelete: false,
      );
      final identity = lease.read();
      final result = await cockpitRunIsolatedProcess(
        'powershell.exe',
        <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          cockpitWindowsDirectoryAuthorityPowerShell,
        ],
        environment: <String, String>{
          'COCKPIT_DIRECTORY_AUTHORITY_PATH': canonicalPath,
        },
      );
      final security = result.stdout.toString().trim();
      return CockpitWindowsFileIdentityProbeResult(
        exitCode: result.exitCode,
        stdout: result.exitCode == 0 ? '$identity|$security' : '',
        stderr: result.stderr.toString(),
      );
    } on FileSystemException catch (error) {
      return CockpitWindowsFileIdentityProbeResult(
        exitCode: error.osError?.errorCode ?? 1,
        stdout: '',
        stderr: error.message,
      );
    } finally {
      lease?.close();
    }
  }
}

final class CockpitWindowsDirectoryAuthorityProvider {
  const CockpitWindowsDirectoryAuthorityProvider({
    this.probe = const CockpitSystemWindowsDirectoryAuthorityProbe(),
  });

  final CockpitWindowsDirectoryAuthorityProbe probe;

  Future<CockpitDirectoryAuthoritySnapshot> inspect(
    String canonicalPath,
  ) async {
    final result = await probe.inspect(canonicalPath);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not verify Windows directory authority: '
        '${_boundedDiagnostic(result.stderr)}',
        canonicalPath,
      );
    }
    final fields = result.stdout.trim().split('|');
    final ownerVerified = fields.length == 5 ? _parseBoolean(fields[2]) : null;
    final ownerTrusted = fields.length == 5 ? _parseBoolean(fields[3]) : null;
    final unsafeWritable = fields.length == 5 ? _parseBoolean(fields[4]) : null;
    if (fields.length != 5 ||
        !_isFixedWidthHex(fields[0], 16) ||
        !_isFixedWidthHex(fields[1], 32) ||
        ownerVerified == null ||
        ownerTrusted == null ||
        unsafeWritable == null) {
      throw FileSystemException(
        'Windows directory authority probe returned invalid data: '
        '${_boundedDiagnostic(result.stdout)}',
        canonicalPath,
      );
    }
    return CockpitDirectoryAuthoritySnapshot(
      identity: CockpitFilesystemIdentity(
        value: 'windows:${fields[0].toLowerCase()}:${fields[1].toLowerCase()}',
        quality: CockpitFilesystemIdentityQuality.windowsVolumeAndFileId,
      ),
      security: CockpitDirectorySecurity(
        posixApplicable: false,
        ownerVerified: ownerVerified,
        ownerTrusted: ownerTrusted,
        unsafeWritable: unsafeWritable,
      ),
    );
  }
}

String _boundedDiagnostic(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'no diagnostic output';
  return text.length <= 256 ? text : '${text.substring(0, 256)}...';
}

bool _isFixedWidthHex(String value, int width) =>
    value.length == width &&
    value.codeUnits.every(
      (codeUnit) =>
          (codeUnit >= 0x30 && codeUnit <= 0x39) ||
          (codeUnit >= 0x41 && codeUnit <= 0x46) ||
          (codeUnit >= 0x61 && codeUnit <= 0x66),
    );

bool? _parseBoolean(String value) => switch (value.toLowerCase()) {
  'true' => true,
  'false' => false,
  _ => null,
};

const cockpitWindowsDirectoryAuthorityPowerShell = r'''
$ErrorActionPreference = 'Stop'
$path = $env:COCKPIT_DIRECTORY_AUTHORITY_PATH
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
[Console]::Out.WriteLine(
  "$(($owner.Value -eq $current.Value).ToString())|$(($allowedWriters -contains $owner.Value).ToString())|$($unsafe.ToString())"
)
''';
