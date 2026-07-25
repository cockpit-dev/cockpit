import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_filesystem_identity.dart';
import 'cockpit_windows_filesystem_identity.dart';

abstract interface class CockpitWindowsDirectoryAuthorityProbe {
  Future<CockpitWindowsFileIdentityProbeResult> inspect(String canonicalPath);
}

final class CockpitPowerShellWindowsDirectoryAuthorityProbe
    implements CockpitWindowsDirectoryAuthorityProbe {
  const CockpitPowerShellWindowsDirectoryAuthorityProbe();

  @override
  Future<CockpitWindowsFileIdentityProbeResult> inspect(
    String canonicalPath,
  ) async {
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
    return CockpitWindowsFileIdentityProbeResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}

final class CockpitWindowsDirectoryAuthorityProvider {
  const CockpitWindowsDirectoryAuthorityProvider({
    this.probe = const CockpitPowerShellWindowsDirectoryAuthorityProbe(),
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
if (-not ('Cockpit.NativeDirectoryAuthorityLease' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Cockpit {
  [StructLayout(LayoutKind.Sequential, Size = 16)]
  internal struct DirectoryFileId128 {
    public byte B00;
    public byte B01;
    public byte B02;
    public byte B03;
    public byte B04;
    public byte B05;
    public byte B06;
    public byte B07;
    public byte B08;
    public byte B09;
    public byte B10;
    public byte B11;
    public byte B12;
    public byte B13;
    public byte B14;
    public byte B15;

    public string ToHex() {
      return B00.ToString("x2") + B01.ToString("x2") +
        B02.ToString("x2") + B03.ToString("x2") +
        B04.ToString("x2") + B05.ToString("x2") +
        B06.ToString("x2") + B07.ToString("x2") +
        B08.ToString("x2") + B09.ToString("x2") +
        B10.ToString("x2") + B11.ToString("x2") +
        B12.ToString("x2") + B13.ToString("x2") +
        B14.ToString("x2") + B15.ToString("x2");
    }
  }

  [StructLayout(LayoutKind.Sequential)]
  internal struct DirectoryFileIdInfo {
    public ulong VolumeSerialNumber;
    public DirectoryFileId128 FileId;
  }

  public sealed class NativeDirectoryAuthorityLease : IDisposable {
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint FileFlagBackupSemantics = 0x02000000;
    private const int FileIdInfoClass = 18;

    [DllImport(
      "kernel32.dll",
      CharSet = CharSet.Unicode,
      ExactSpelling = true,
      SetLastError = true
    )]
    private static extern SafeFileHandle CreateFileW(
      string fileName,
      uint desiredAccess,
      uint shareMode,
      IntPtr securityAttributes,
      uint creationDisposition,
      uint flagsAndAttributes,
      IntPtr templateFile
    );

    [DllImport(
      "kernel32.dll",
      ExactSpelling = true,
      SetLastError = true
    )]
    private static extern bool GetFileInformationByHandleEx(
      SafeFileHandle file,
      int fileInformationClass,
      out DirectoryFileIdInfo fileInformation,
      uint bufferSize
    );

    private SafeFileHandle handle;

    private NativeDirectoryAuthorityLease(string path) {
      handle = CreateFileW(
        ExtendedPath(path),
        0,
        FileShareRead | FileShareWrite,
        IntPtr.Zero,
        OpenExisting,
        FileFlagBackupSemantics,
        IntPtr.Zero
      );
      if (handle.IsInvalid) {
        int error = Marshal.GetLastWin32Error();
        handle.Dispose();
        throw new Win32Exception(error);
      }
    }

    public static NativeDirectoryAuthorityLease Open(string path) {
      return new NativeDirectoryAuthorityLease(path);
    }

    public string ReadIdentity() {
      int size = Marshal.SizeOf(typeof(DirectoryFileIdInfo));
      if (size != 24) {
        throw new InvalidOperationException("Unexpected FILE_ID_INFO size.");
      }
      DirectoryFileIdInfo info;
      if (!GetFileInformationByHandleEx(
        handle,
        FileIdInfoClass,
        out info,
        (uint)size
      )) {
        throw new Win32Exception(Marshal.GetLastWin32Error());
      }
      return info.VolumeSerialNumber.ToString("x16") +
        "|" + info.FileId.ToHex();
    }

    public void Dispose() {
      if (handle != null) {
        handle.Dispose();
        handle = null;
      }
    }

    private static string ExtendedPath(string path) {
      if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) {
        return path;
      }
      if (path.StartsWith(@"\\", StringComparison.Ordinal)) {
        return @"\\?\UNC\" + path.Substring(2);
      }
      return @"\\?\" + path;
    }
  }
}
'@
}
$lease = [Cockpit.NativeDirectoryAuthorityLease]::Open($path)
try {
  $identity = $lease.ReadIdentity()
  $acl = Get-Acl -LiteralPath $path
  $descriptor = $acl.GetSecurityDescriptorBinaryForm()
  $control = [System.BitConverter]::ToUInt16($descriptor, 2)
  $daclOffset = [System.BitConverter]::ToUInt32($descriptor, 16)
  $daclPresent = (($control -band 0x0004) -ne 0) -and ($daclOffset -ne 0)
  $current = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  try {
    $owner = [System.Security.Principal.SecurityIdentifier]::new($acl.Owner)
  } catch {
    $owner = [System.Security.Principal.NTAccount]::new($acl.Owner).Translate(
      [System.Security.Principal.SecurityIdentifier]
    )
  }
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
  foreach ($rule in $acl.Access) {
    if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
      continue
    }
    $sid = $rule.IdentityReference.Translate(
      [System.Security.Principal.SecurityIdentifier]
    ).Value
    if ($allowedWriters -notcontains $sid -and (($rule.FileSystemRights -band $writeRights) -ne 0)) {
      $unsafe = $true
    }
  }
  [Console]::Out.WriteLine(
    "$identity|$(($owner.Value -eq $current.Value).ToString())|$(($allowedWriters -contains $owner.Value).ToString())|$($unsafe.ToString())"
  )
} finally {
  $lease.Dispose()
}
''';
