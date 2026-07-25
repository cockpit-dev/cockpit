import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_filesystem_identity.dart';
import 'cockpit_home.dart';

final class CockpitWindowsFileIdentityProbeResult {
  const CockpitWindowsFileIdentityProbeResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class CockpitWindowsFileIdentityProbe {
  Future<CockpitWindowsFileIdentityProbeResult> inspect(String canonicalPath);
}

final class CockpitPowerShellWindowsFileIdentityProbe
    implements CockpitWindowsFileIdentityProbe {
  const CockpitPowerShellWindowsFileIdentityProbe();

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
        cockpitWindowsFileIdentityPowerShell,
      ],
      environment: <String, String>{
        'COCKPIT_FILE_IDENTITY_PATH': canonicalPath,
      },
    );
    return CockpitWindowsFileIdentityProbeResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}

final class CockpitWindowsFilesystemIdentityProvider
    implements CockpitFilesystemIdentityProvider {
  const CockpitWindowsFilesystemIdentityProvider({
    this.probe = const CockpitPowerShellWindowsFileIdentityProbe(),
  });

  final CockpitWindowsFileIdentityProbe probe;

  @override
  Future<CockpitFilesystemIdentity> identify(String canonicalPath) async {
    final result = await probe.inspect(canonicalPath);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not read stable Windows file identity: '
        '${_boundedWindowsDiagnostic(result.stderr)}',
        canonicalPath,
      );
    }
    final fields = result.stdout.trim().split('|');
    if (fields.length != 2 ||
        !_isFixedWidthHex(fields[0], 16) ||
        !_isFixedWidthHex(fields[1], 32)) {
      throw FileSystemException(
        'Windows file identity probe returned invalid data: '
        '${_boundedWindowsDiagnostic(result.stdout)}',
        canonicalPath,
      );
    }
    final volume = fields[0].toLowerCase();
    final fileId = fields[1].toLowerCase();
    return CockpitFilesystemIdentity(
      value: 'windows:$volume:$fileId',
      quality: CockpitFilesystemIdentityQuality.windowsVolumeAndFileId,
    );
  }
}

final class CockpitSystemFilesystemIdentityProvider
    implements CockpitFilesystemIdentityProvider {
  const CockpitSystemFilesystemIdentityProvider({
    required this.platform,
    required this.metadataProvider,
    this.windowsProbe = const CockpitPowerShellWindowsFileIdentityProbe(),
  });

  final CockpitHostPlatform platform;
  final CockpitPosixMetadataProvider metadataProvider;
  final CockpitWindowsFileIdentityProbe windowsProbe;

  @override
  Future<CockpitFilesystemIdentity> identify(String canonicalPath) {
    if (platform == CockpitHostPlatform.windows) {
      return CockpitWindowsFilesystemIdentityProvider(
        probe: windowsProbe,
      ).identify(canonicalPath);
    }
    return CockpitPosixFilesystemIdentityProvider(
      metadataProvider,
    ).identify(canonicalPath);
  }
}

String _boundedWindowsDiagnostic(String value) {
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

const cockpitWindowsFileIdentityPowerShell = r'''
$ErrorActionPreference = 'Stop'
$path = $env:COCKPIT_FILE_IDENTITY_PATH
if (-not ('Cockpit.NativeFileIdentity' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Cockpit {
  [StructLayout(LayoutKind.Sequential, Size = 16)]
  internal struct FileId128 {
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
  internal struct FileIdInfo {
    public ulong VolumeSerialNumber;
    public FileId128 FileId;
  }

  public static class NativeFileIdentity {
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint FileShareDelete = 0x00000004;
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
      out FileIdInfo fileInformation,
      uint bufferSize
    );

    public static string Read(string path) {
      using (SafeFileHandle handle = CreateFileW(
        ExtendedPath(path),
        0,
        FileShareRead | FileShareWrite | FileShareDelete,
        IntPtr.Zero,
        OpenExisting,
        FileFlagBackupSemantics,
        IntPtr.Zero
      )) {
        if (handle.IsInvalid) {
          throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        int size = Marshal.SizeOf(typeof(FileIdInfo));
        if (size != 24) {
          throw new InvalidOperationException("Unexpected FILE_ID_INFO size.");
        }
        FileIdInfo info;
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
[Console]::Out.WriteLine([Cockpit.NativeFileIdentity]::Read($path))
''';
