import 'dart:io';

import 'cockpit_filesystem_identity.dart';
import 'cockpit_windows_filesystem_identity.dart';
import 'cockpit_windows_security.dart';

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
      final security = await const CockpitNativeWindowsSecurityProvider()
          .inspect(canonicalPath);
      return CockpitWindowsFileIdentityProbeResult(
        exitCode: 0,
        stdout:
            '$identity|${security.ownerVerified}|${security.ownerTrusted}|'
            '${security.unsafeWritable}',
        stderr: '',
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
