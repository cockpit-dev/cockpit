import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'cockpit_directory_security.dart';

final class CockpitNativeWindowsSecurityProvider
    implements CockpitWindowsSecurityProvider {
  const CockpitNativeWindowsSecurityProvider();

  @override
  Future<CockpitDirectorySecurity> inspect(String canonicalPath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows directory ACLs require Windows.');
    }
    return _CockpitWindowsSecurityApi.instance.inspect(canonicalPath);
  }
}

final class _CockpitWindowsSecurityApi {
  _CockpitWindowsSecurityApi._()
    : _advapi32 = DynamicLibrary.open('advapi32.dll'),
      _kernel32 = DynamicLibrary.open('kernel32.dll') {
    _getNamedSecurityInfo = _advapi32
        .lookupFunction<_GetNamedSecurityInfoNative, _GetNamedSecurityInfoDart>(
          'GetNamedSecurityInfoW',
        );
    _openProcessToken = _advapi32
        .lookupFunction<_OpenProcessTokenNative, _OpenProcessTokenDart>(
          'OpenProcessToken',
        );
    _getTokenInformation = _advapi32
        .lookupFunction<_GetTokenInformationNative, _GetTokenInformationDart>(
          'GetTokenInformation',
        );
    _convertSidToStringSid = _advapi32
        .lookupFunction<
          _ConvertSidToStringSidNative,
          _ConvertSidToStringSidDart
        >('ConvertSidToStringSidW');
    _getAclInformation = _advapi32
        .lookupFunction<_GetAclInformationNative, _GetAclInformationDart>(
          'GetAclInformation',
        );
    _getAce = _advapi32.lookupFunction<_GetAceNative, _GetAceDart>('GetAce');
    _isValidSid = _advapi32.lookupFunction<_IsValidSidNative, _IsValidSidDart>(
      'IsValidSid',
    );
    _getLengthSid = _advapi32
        .lookupFunction<_GetLengthSidNative, _GetLengthSidDart>('GetLengthSid');
    _getCurrentProcess = _kernel32
        .lookupFunction<_GetCurrentProcessNative, _GetCurrentProcessDart>(
          'GetCurrentProcess',
        );
    _closeHandle = _kernel32
        .lookupFunction<_WindowsCloseHandleNative, _WindowsCloseHandleDart>(
          'CloseHandle',
        );
    _localFree = _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
      'LocalFree',
    );
    _getLastError = _kernel32
        .lookupFunction<_WindowsGetLastErrorNative, _WindowsGetLastErrorDart>(
          'GetLastError',
        );
  }

  static final _CockpitWindowsSecurityApi instance =
      _CockpitWindowsSecurityApi._();

  final DynamicLibrary _advapi32;
  final DynamicLibrary _kernel32;
  late final _GetNamedSecurityInfoDart _getNamedSecurityInfo;
  late final _OpenProcessTokenDart _openProcessToken;
  late final _GetTokenInformationDart _getTokenInformation;
  late final _ConvertSidToStringSidDart _convertSidToStringSid;
  late final _GetAclInformationDart _getAclInformation;
  late final _GetAceDart _getAce;
  late final _IsValidSidDart _isValidSid;
  late final _GetLengthSidDart _getLengthSid;
  late final _GetCurrentProcessDart _getCurrentProcess;
  late final _WindowsCloseHandleDart _closeHandle;
  late final _LocalFreeDart _localFree;
  late final _WindowsGetLastErrorDart _getLastError;

  CockpitDirectorySecurity inspect(String canonicalPath) {
    final path = _extendedWindowsSecurityPath(canonicalPath).toNativeUtf16();
    final owner = calloc<Pointer<Void>>();
    final dacl = calloc<Pointer<Void>>();
    final descriptor = calloc<Pointer<Void>>();
    try {
      final error = _getNamedSecurityInfo(
        path,
        _seFileObject,
        _ownerSecurityInformation | _daclSecurityInformation,
        owner,
        nullptr,
        dacl,
        nullptr,
        descriptor,
      );
      if (error != 0) {
        throw _windowsSecurityException(
          'GetNamedSecurityInfoW',
          canonicalPath,
          error,
        );
      }
      if (owner.value == nullptr || descriptor.value == nullptr) {
        throw FileSystemException(
          'Windows directory security descriptor was incomplete.',
          canonicalPath,
        );
      }
      final currentSid = _currentUserSid(canonicalPath);
      final ownerSid = _sidString(owner.value, canonicalPath);
      final trustedSids = <String>{
        currentSid,
        _localSystemSid,
        _administratorsSid,
        _trustedInstallerSid,
      };
      final unsafeWritable = dacl.value == nullptr
          ? true
          : _hasUnsafeWriter(dacl.value, trustedSids, canonicalPath);
      return CockpitDirectorySecurity(
        posixApplicable: false,
        ownerVerified: ownerSid == currentSid,
        ownerTrusted: trustedSids.contains(ownerSid),
        unsafeWritable: unsafeWritable,
      );
    } finally {
      if (descriptor.value != nullptr) _localFree(descriptor.value);
      calloc.free(descriptor);
      calloc.free(dacl);
      calloc.free(owner);
      calloc.free(path);
    }
  }

  String _currentUserSid(String path) {
    final token = calloc<IntPtr>();
    try {
      if (_openProcessToken(_getCurrentProcess(), _tokenQuery, token) == 0) {
        throw _windowsSecurityException(
          'OpenProcessToken',
          path,
          _getLastError(),
        );
      }
      final requiredLength = calloc<Uint32>();
      try {
        final first = _getTokenInformation(
          token.value,
          _tokenUserInformationClass,
          nullptr,
          0,
          requiredLength,
        );
        // ReturnLength survives the size probe reliably across Windows FFI
        // runtimes. The populated-buffer call below remains authoritative.
        if (requiredLength.value == 0) {
          throw _windowsSecurityException(
            'GetTokenInformation(size)',
            path,
            first == 0 ? _getLastError() : 0,
          );
        }
        final buffer = calloc<Uint8>(requiredLength.value);
        try {
          if (_getTokenInformation(
                token.value,
                _tokenUserInformationClass,
                buffer.cast(),
                requiredLength.value,
                requiredLength,
              ) ==
              0) {
            throw _windowsSecurityException(
              'GetTokenInformation(TokenUser)',
              path,
              _getLastError(),
            );
          }
          return _sidString(
            buffer.cast<_CockpitTokenUser>().ref.user.sid,
            path,
          );
        } finally {
          calloc.free(buffer);
        }
      } finally {
        calloc.free(requiredLength);
      }
    } finally {
      if (token.value != 0) _closeHandle(token.value);
      calloc.free(token);
    }
  }

  bool _hasUnsafeWriter(
    Pointer<Void> dacl,
    Set<String> trustedSids,
    String path,
  ) {
    final information = calloc<_CockpitAclSizeInformation>();
    try {
      if (_getAclInformation(
            dacl,
            information.cast(),
            sizeOf<_CockpitAclSizeInformation>(),
            _aclSizeInformationClass,
          ) ==
          0) {
        throw _windowsSecurityException(
          'GetAclInformation',
          path,
          _getLastError(),
        );
      }
      final ace = calloc<Pointer<Void>>();
      try {
        for (var index = 0; index < information.ref.aceCount; index += 1) {
          ace.value = nullptr;
          if (_getAce(dacl, index, ace) == 0 || ace.value == nullptr) {
            throw _windowsSecurityException('GetAce', path, _getLastError());
          }
          final bytes = ace.value.cast<Uint8>();
          final aceSize = (bytes + 2).cast<Uint16>().value;
          if (aceSize < 8) {
            throw FileSystemException(
              'Windows directory ACL contained a malformed ACE.',
              path,
            );
          }
          final sidOffset = _allowedAceSidOffset(
            bytes[0],
            bytes,
            aceSize,
            path,
          );
          if (sidOffset == null) continue;
          if (aceSize < sidOffset + 8) {
            throw FileSystemException(
              'Windows directory ACL contained a malformed allow ACE.',
              path,
            );
          }
          final mask = (bytes + 4).cast<Uint32>().value;
          if (mask & _windowsMutationRights == 0) continue;
          final sid = (bytes + sidOffset).cast<Void>();
          if (_isValidSid(sid) == 0) {
            throw FileSystemException(
              'Windows directory ACL contained an invalid SID.',
              path,
            );
          }
          final sidLength = _getLengthSid(sid);
          if (sidLength == 0 || sidOffset + sidLength > aceSize) {
            throw FileSystemException(
              'Windows directory ACL contained an out-of-bounds SID.',
              path,
            );
          }
          if (!trustedSids.contains(_sidString(sid, path))) return true;
        }
        return false;
      } finally {
        calloc.free(ace);
      }
    } finally {
      calloc.free(information);
    }
  }

  String _sidString(Pointer<Void> sid, String path) {
    final value = calloc<Pointer<Utf16>>();
    try {
      if (_convertSidToStringSid(sid, value) == 0 || value.value == nullptr) {
        throw _windowsSecurityException(
          'ConvertSidToStringSidW',
          path,
          _getLastError(),
        );
      }
      return value.value.toDartString();
    } finally {
      if (value.value != nullptr) _localFree(value.value.cast());
      calloc.free(value);
    }
  }
}

final class _CockpitSidAndAttributes extends Struct {
  external Pointer<Void> sid;

  @Uint32()
  external int attributes;
}

final class _CockpitTokenUser extends Struct {
  external _CockpitSidAndAttributes user;
}

final class _CockpitAclSizeInformation extends Struct {
  @Uint32()
  external int aceCount;

  @Uint32()
  external int aclBytesInUse;

  @Uint32()
  external int aclBytesFree;
}

int? _allowedAceSidOffset(
  int type,
  Pointer<Uint8> bytes,
  int aceSize,
  String path,
) {
  if (type == _accessAllowedAceType || type == _accessAllowedCallbackAceType) {
    return 8;
  }
  if (type == _accessAllowedCompoundAceType) {
    if (aceSize < 12) _throwMalformedObjectAce(path);
    return 12;
  }
  if (type == _accessAllowedObjectAceType ||
      type == _accessAllowedCallbackObjectAceType) {
    if (aceSize < 12) _throwMalformedObjectAce(path);
    final flags = (bytes + 8).cast<Uint32>().value;
    return 12 +
        (flags & _aceObjectTypePresent != 0 ? 16 : 0) +
        (flags & _aceInheritedObjectTypePresent != 0 ? 16 : 0);
  }
  return null;
}

Never _throwMalformedObjectAce(String path) => throw FileSystemException(
  'Windows directory ACL contained a malformed object ACE.',
  path,
);

FileSystemException _windowsSecurityException(
  String operation,
  String path,
  int errorCode,
) => FileSystemException(
  'Could not verify Windows directory ACL.',
  path,
  OSError('$operation failed.', errorCode),
);

String _extendedWindowsSecurityPath(String path) {
  if (path.startsWith(r'\\?\')) return path;
  if (path.startsWith(r'\\')) return '${r'\\?\UNC\'}${path.substring(2)}';
  return '${r'\\?\'}$path';
}

const int _seFileObject = 1;
const int _ownerSecurityInformation = 0x00000001;
const int _daclSecurityInformation = 0x00000004;
const int _tokenQuery = 0x0008;
const int _tokenUserInformationClass = 1;
const int _aclSizeInformationClass = 2;
const int _accessAllowedAceType = 0x00;
const int _accessAllowedCompoundAceType = 0x04;
const int _accessAllowedObjectAceType = 0x05;
const int _accessAllowedCallbackAceType = 0x09;
const int _accessAllowedCallbackObjectAceType = 0x0b;
const int _aceObjectTypePresent = 0x00000001;
const int _aceInheritedObjectTypePresent = 0x00000002;

const int _fileWriteData = 0x00000002;
const int _fileAppendData = 0x00000004;
const int _fileWriteEa = 0x00000010;
const int _fileDeleteChild = 0x00000040;
const int _fileWriteAttributes = 0x00000100;
const int _delete = 0x00010000;
const int _writeDac = 0x00040000;
const int _writeOwner = 0x00080000;
const int _genericAll = 0x10000000;
const int _genericWrite = 0x40000000;
const int _windowsMutationRights =
    _fileWriteData |
    _fileAppendData |
    _fileWriteEa |
    _fileDeleteChild |
    _fileWriteAttributes |
    _delete |
    _writeDac |
    _writeOwner |
    _genericAll |
    _genericWrite;

const String _localSystemSid = 'S-1-5-18';
const String _administratorsSid = 'S-1-5-32-544';
const String _trustedInstallerSid =
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464';

typedef _GetNamedSecurityInfoNative =
    Uint32 Function(
      Pointer<Utf16> objectName,
      Int32 objectType,
      Uint32 securityInfo,
      Pointer<Pointer<Void>> owner,
      Pointer<Pointer<Void>> group,
      Pointer<Pointer<Void>> dacl,
      Pointer<Pointer<Void>> sacl,
      Pointer<Pointer<Void>> securityDescriptor,
    );
typedef _GetNamedSecurityInfoDart =
    int Function(
      Pointer<Utf16> objectName,
      int objectType,
      int securityInfo,
      Pointer<Pointer<Void>> owner,
      Pointer<Pointer<Void>> group,
      Pointer<Pointer<Void>> dacl,
      Pointer<Pointer<Void>> sacl,
      Pointer<Pointer<Void>> securityDescriptor,
    );
typedef _OpenProcessTokenNative =
    Int32 Function(
      IntPtr processHandle,
      Uint32 desiredAccess,
      Pointer<IntPtr> tokenHandle,
    );
typedef _OpenProcessTokenDart =
    int Function(
      int processHandle,
      int desiredAccess,
      Pointer<IntPtr> tokenHandle,
    );
typedef _GetTokenInformationNative =
    Int32 Function(
      IntPtr tokenHandle,
      Int32 tokenInformationClass,
      Pointer<Void> tokenInformation,
      Uint32 tokenInformationLength,
      Pointer<Uint32> returnLength,
    );
typedef _GetTokenInformationDart =
    int Function(
      int tokenHandle,
      int tokenInformationClass,
      Pointer<Void> tokenInformation,
      int tokenInformationLength,
      Pointer<Uint32> returnLength,
    );
typedef _ConvertSidToStringSidNative =
    Int32 Function(Pointer<Void> sid, Pointer<Pointer<Utf16>> stringSid);
typedef _ConvertSidToStringSidDart =
    int Function(Pointer<Void> sid, Pointer<Pointer<Utf16>> stringSid);
typedef _GetAclInformationNative =
    Int32 Function(
      Pointer<Void> acl,
      Pointer<Void> information,
      Uint32 informationLength,
      Int32 informationClass,
    );
typedef _GetAclInformationDart =
    int Function(
      Pointer<Void> acl,
      Pointer<Void> information,
      int informationLength,
      int informationClass,
    );
typedef _GetAceNative =
    Int32 Function(Pointer<Void> acl, Uint32 index, Pointer<Pointer<Void>> ace);
typedef _GetAceDart =
    int Function(Pointer<Void> acl, int index, Pointer<Pointer<Void>> ace);
typedef _IsValidSidNative = Int32 Function(Pointer<Void> sid);
typedef _IsValidSidDart = int Function(Pointer<Void> sid);
typedef _GetLengthSidNative = Uint32 Function(Pointer<Void> sid);
typedef _GetLengthSidDart = int Function(Pointer<Void> sid);
typedef _GetCurrentProcessNative = IntPtr Function();
typedef _GetCurrentProcessDart = int Function();
typedef _WindowsCloseHandleNative = Int32 Function(IntPtr handle);
typedef _WindowsCloseHandleDart = int Function(int handle);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);
typedef _WindowsGetLastErrorNative = Uint32 Function();
typedef _WindowsGetLastErrorDart = int Function();
