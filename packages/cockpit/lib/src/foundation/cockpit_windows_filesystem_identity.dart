import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'cockpit_filesystem_identity.dart';
import 'cockpit_home.dart';

final class CockpitWindowsFileIdentityProbeResult {
  const CockpitWindowsFileIdentityProbeResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  factory CockpitWindowsFileIdentityProbeResult.failure(
    FileSystemException error,
  ) {
    final osError = error.osError;
    final errorCode = osError?.errorCode;
    final diagnostic = osError == null
        ? error.message
        : '${error.message} ${osError.message} (${osError.errorCode})'.trim();
    return CockpitWindowsFileIdentityProbeResult(
      exitCode: errorCode == null || errorCode == 0 ? 1 : errorCode,
      stdout: '',
      stderr: diagnostic,
    );
  }

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class CockpitWindowsFileIdentityProbe {
  Future<CockpitWindowsFileIdentityProbeResult> inspect(String canonicalPath);
}

final class CockpitNativeWindowsFileIdentityProbe
    implements CockpitWindowsFileIdentityProbe {
  const CockpitNativeWindowsFileIdentityProbe();

  @override
  Future<CockpitWindowsFileIdentityProbeResult> inspect(
    String canonicalPath,
  ) async {
    final lease = CockpitWindowsFileIdentityLease.open(
      canonicalPath,
      shareDelete: true,
    );
    try {
      return CockpitWindowsFileIdentityProbeResult(
        exitCode: 0,
        stdout: lease.read(),
        stderr: '',
      );
    } on FileSystemException catch (error) {
      return CockpitWindowsFileIdentityProbeResult.failure(error);
    } finally {
      lease.close();
    }
  }
}

final class CockpitWindowsFilesystemIdentityProvider
    implements CockpitFilesystemIdentityProvider {
  const CockpitWindowsFilesystemIdentityProvider({
    this.probe = const CockpitNativeWindowsFileIdentityProbe(),
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
    this.windowsProbe = const CockpitNativeWindowsFileIdentityProbe(),
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

final class CockpitWindowsFileIdentityLease {
  CockpitWindowsFileIdentityLease._({
    required _CockpitWindowsFileIdentityApi api,
    required int handle,
    required String path,
  }) : _api = api,
       _handle = handle,
       _path = path;

  static CockpitWindowsFileIdentityLease open(
    String canonicalPath, {
    required bool shareDelete,
  }) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows file identity requires Windows.');
    }
    final api = _CockpitWindowsFileIdentityApi.instance;
    final extendedPath = _extendedWindowsPath(canonicalPath).toNativeUtf16();
    try {
      final handle = api.createFile(
        extendedPath,
        0,
        _fileShareRead | _fileShareWrite | (shareDelete ? _fileShareDelete : 0),
        nullptr,
        _openExisting,
        _fileFlagBackupSemantics,
        0,
      );
      if (handle == _invalidHandleValue) {
        final errorCode = api.getLastError();
        throw FileSystemException(
          'Could not open Windows directory identity handle.',
          canonicalPath,
          OSError('CreateFileW failed.', errorCode),
        );
      }
      return CockpitWindowsFileIdentityLease._(
        api: api,
        handle: handle,
        path: canonicalPath,
      );
    } finally {
      calloc.free(extendedPath);
    }
  }

  final _CockpitWindowsFileIdentityApi _api;
  final String _path;
  int _handle;

  String read() {
    if (_handle == _invalidHandleValue) {
      throw StateError('Windows file identity lease is closed.');
    }
    if (sizeOf<_CockpitWindowsFileIdInfo>() != 24) {
      throw StateError('Unexpected FILE_ID_INFO size.');
    }
    final info = calloc<_CockpitWindowsFileIdInfo>();
    try {
      final succeeded = _api.getFileInformationByHandleEx(
        _handle,
        _fileIdInfoClass,
        info.cast<Void>(),
        sizeOf<_CockpitWindowsFileIdInfo>(),
      );
      if (succeeded == 0) {
        final errorCode = _api.getLastError();
        throw FileSystemException(
          'Could not read stable Windows file identity.',
          _path,
          OSError('GetFileInformationByHandleEx failed.', errorCode),
        );
      }
      final volume = info.ref.volumeSerialNumber
          .toRadixString(16)
          .padLeft(16, '0');
      final fileId = StringBuffer();
      for (var index = 0; index < 16; index += 1) {
        fileId.write(info.ref.fileId[index].toRadixString(16).padLeft(2, '0'));
      }
      return '$volume|$fileId';
    } finally {
      calloc.free(info);
    }
  }

  void close() {
    final handle = _handle;
    if (handle == _invalidHandleValue) return;
    _handle = _invalidHandleValue;
    _api.closeHandle(handle);
  }
}

final class _CockpitWindowsFileIdentityApi {
  _CockpitWindowsFileIdentityApi._()
    : _library = DynamicLibrary.open('kernel32.dll') {
    createFile = _library.lookupFunction<_CreateFileNative, _CreateFileDart>(
      'CreateFileW',
    );
    getFileInformationByHandleEx = _library
        .lookupFunction<
          _GetFileInformationByHandleExNative,
          _GetFileInformationByHandleExDart
        >('GetFileInformationByHandleEx');
    closeHandle = _library.lookupFunction<_CloseHandleNative, _CloseHandleDart>(
      'CloseHandle',
    );
    getLastError = _library
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
  }

  static final _CockpitWindowsFileIdentityApi instance =
      _CockpitWindowsFileIdentityApi._();

  final DynamicLibrary _library;
  late final _CreateFileDart createFile;
  late final _GetFileInformationByHandleExDart getFileInformationByHandleEx;
  late final _CloseHandleDart closeHandle;
  late final _GetLastErrorDart getLastError;
}

final class _CockpitWindowsFileIdInfo extends Struct {
  @Uint64()
  external int volumeSerialNumber;

  @Array(16)
  external Array<Uint8> fileId;
}

const int _fileShareRead = 0x00000001;
const int _fileShareWrite = 0x00000002;
const int _fileShareDelete = 0x00000004;
const int _openExisting = 3;
const int _fileFlagBackupSemantics = 0x02000000;
const int _fileIdInfoClass = 18;
const int _invalidHandleValue = -1;

String _extendedWindowsPath(String path) {
  if (path.startsWith(r'\\?\')) return path;
  if (path.startsWith(r'\\')) return '${r'\\?\UNC\'}${path.substring(2)}';
  return '${r'\\?\'}$path';
}

typedef _CreateFileNative =
    IntPtr Function(
      Pointer<Utf16> fileName,
      Uint32 desiredAccess,
      Uint32 shareMode,
      Pointer<Void> securityAttributes,
      Uint32 creationDisposition,
      Uint32 flagsAndAttributes,
      IntPtr templateFile,
    );
typedef _CreateFileDart =
    int Function(
      Pointer<Utf16> fileName,
      int desiredAccess,
      int shareMode,
      Pointer<Void> securityAttributes,
      int creationDisposition,
      int flagsAndAttributes,
      int templateFile,
    );
typedef _GetFileInformationByHandleExNative =
    Int32 Function(
      IntPtr file,
      Int32 fileInformationClass,
      Pointer<Void> fileInformation,
      Uint32 bufferSize,
    );
typedef _GetFileInformationByHandleExDart =
    int Function(
      int file,
      int fileInformationClass,
      Pointer<Void> fileInformation,
      int bufferSize,
    );
typedef _CloseHandleNative = Int32 Function(IntPtr handle);
typedef _CloseHandleDart = int Function(int handle);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
