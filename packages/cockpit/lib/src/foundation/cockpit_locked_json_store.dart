import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'cockpit_home.dart';
import 'cockpit_permissions.dart';

final class CockpitStorageException implements Exception {
  const CockpitStorageException({
    required this.code,
    required this.path,
    required this.diagnostic,
  });

  final String code;
  final String path;
  final String diagnostic;

  @override
  String toString() => 'CockpitStorageException($code, $path): $diagnostic';
}

abstract interface class CockpitJsonCodec<T> {
  T decode(Object? json);

  Object? encode(T value);
}

abstract interface class CockpitDirectorySyncer {
  Future<void> sync(String directoryPath);
}

final class CockpitSystemDirectorySyncer implements CockpitDirectorySyncer {
  const CockpitSystemDirectorySyncer(this.platform);

  final CockpitHostPlatform platform;

  @override
  Future<void> sync(String directoryPath) async {
    if (platform == CockpitHostPlatform.windows) {
      return;
    }
    _syncPosixPath(directoryPath);
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FsyncNative = Int32 Function(Int32);
typedef _FsyncDart = int Function(int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _ErrnoDart = Pointer<Int32> Function();
typedef _StrerrorNative = Pointer<Utf8> Function(Int32);
typedef _StrerrorDart = Pointer<Utf8> Function(int);

final DynamicLibrary _posixProcess = DynamicLibrary.process();
final _OpenDart _posixOpen = _posixProcess
    .lookupFunction<_OpenNative, _OpenDart>('open');
final _FsyncDart _posixFsync = _posixProcess
    .lookupFunction<_FsyncNative, _FsyncDart>('fsync');
final _CloseDart _posixClose = _posixProcess
    .lookupFunction<_CloseNative, _CloseDart>('close');
final _ErrnoDart _posixErrno = _posixProcess
    .lookupFunction<_ErrnoNative, _ErrnoDart>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );
final _StrerrorDart _posixStrerror = _posixProcess
    .lookupFunction<_StrerrorNative, _StrerrorDart>('strerror');

void _syncPosixPath(String path) {
  if (path.contains('\x00')) {
    throw FileSystemException('Path contains a null byte.', path);
  }
  final nativePath = path.toNativeUtf8();
  var descriptor = -1;
  var failed = false;
  try {
    descriptor = _posixOpen(nativePath, 0);
    if (descriptor < 0) {
      throw _posixFileSystemException('open', path);
    }
    if (_posixFsync(descriptor) != 0) {
      throw _posixFileSystemException('fsync', path);
    }
  } on Object {
    failed = true;
    rethrow;
  } finally {
    malloc.free(nativePath);
    if (descriptor >= 0 && _posixClose(descriptor) != 0 && !failed) {
      throw _posixFileSystemException('close', path);
    }
  }
}

FileSystemException _posixFileSystemException(String operation, String path) {
  final code = _posixErrno().value;
  final message = _posixStrerror(code).toDartString();
  return FileSystemException(
    'Could not synchronize filesystem metadata during $operation',
    path,
    OSError(message, code),
  );
}

final class CockpitAtomicJsonFile {
  CockpitAtomicJsonFile({
    required this.permissionHardener,
    required this.directorySyncer,
    Random? random,
  }) : _random = random ?? Random.secure();

  final CockpitPermissionHardener permissionHardener;
  final CockpitDirectorySyncer directorySyncer;
  final Random _random;

  Future<void> write(String path, Object? value, {int? maximumBytes}) async {
    final bytes = utf8.encode('${jsonEncode(value)}\n');
    if (maximumBytes != null && bytes.length > maximumBytes) {
      throw CockpitStorageException(
        code: 'storageTooLarge',
        path: path,
        diagnostic: 'JSON document exceeds $maximumBytes bytes.',
      );
    }
    final target = File(path);
    final parent = target.parent;
    await parent.create(recursive: true);
    await permissionHardener.hardenDirectory(parent);
    final token = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final temporary = File(
      p.join(parent.path, '.${p.basename(path)}.$pid.$token.tmp'),
    );
    RandomAccessFile? handle;
    try {
      handle = await temporary.open(mode: FileMode.write);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
      await permissionHardener.hardenFile(temporary);
      await temporary.rename(target.path);
      await directorySyncer.sync(parent.path);
    } catch (_) {
      try {
        await handle?.close();
      } finally {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      }
      rethrow;
    }
  }
}

String? cockpitAtomicJsonTemporaryTargetName(String name) {
  if (!name.startsWith('.') || !name.endsWith('.tmp')) return null;
  final body = name.substring(1, name.length - '.tmp'.length);
  final tokenSeparator = body.lastIndexOf('.');
  if (tokenSeparator <= 0) return null;
  final token = body.substring(tokenSeparator + 1);
  final beforeToken = body.substring(0, tokenSeparator);
  final processSeparator = beforeToken.lastIndexOf('.');
  if (processSeparator <= 0) return null;
  final processId = beforeToken.substring(processSeparator + 1);
  final targetName = beforeToken.substring(0, processSeparator);
  if (targetName.isEmpty ||
      processId.isEmpty ||
      !_isDecimal(processId) ||
      !_isLowercaseHex(token, length: 24)) {
    return null;
  }
  return targetName;
}

Future<void> cockpitValidateCanonicalRegularFile(
  String path, {
  required String diagnostic,
}) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type != FileSystemEntityType.file) {
    throw FileSystemException(diagnostic, path);
  }
  final canonical = p.normalize(await File(path).resolveSymbolicLinks());
  if (!p.equals(canonical, p.normalize(path))) {
    throw FileSystemException(diagnostic, path);
  }
}

Future<void> cockpitDeleteAtomicJsonTemporary({
  required String path,
  required CockpitDirectorySyncer directorySyncer,
}) async {
  await cockpitValidateCanonicalRegularFile(
    path,
    diagnostic: 'Atomic JSON temporary file is not canonical and regular.',
  );
  final file = File(path);
  await file.delete();
  await directorySyncer.sync(file.parent.path);
}

bool _isDecimal(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 48 || codeUnit > 57) return false;
  }
  return true;
}

bool _isLowercaseHex(String value, {required int length}) {
  if (value.length != length) return false;
  for (final codeUnit in value.codeUnits) {
    if ((codeUnit < 48 || codeUnit > 57) && (codeUnit < 97 || codeUnit > 102)) {
      return false;
    }
  }
  return true;
}

final class CockpitLockedJsonUpdate<T, R> {
  const CockpitLockedJsonUpdate._({
    required this.value,
    required this.result,
    required this.shouldWrite,
  });

  factory CockpitLockedJsonUpdate.write(T value, R result) =>
      CockpitLockedJsonUpdate._(
        value: value,
        result: result,
        shouldWrite: true,
      );

  factory CockpitLockedJsonUpdate.readOnly(T value, R result) =>
      CockpitLockedJsonUpdate._(
        value: value,
        result: result,
        shouldWrite: false,
      );

  final T value;
  final R result;
  final bool shouldWrite;
}

typedef CockpitLockedJsonTransaction<T, R> =
    FutureOr<CockpitLockedJsonUpdate<T, R>> Function(T current);

final class CockpitLockedJsonStore<T> {
  CockpitLockedJsonStore({
    required this.path,
    required this.codec,
    required this.createInitial,
    required this.permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    this.maximumBytes = 8 * 1024 * 1024,
  }) : _atomicFile = CockpitAtomicJsonFile(
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
       ),
       _directorySyncer = directorySyncer;

  final String path;
  final CockpitJsonCodec<T> codec;
  final T Function() createInitial;
  final CockpitPermissionHardener permissionHardener;
  final int maximumBytes;
  final CockpitAtomicJsonFile _atomicFile;
  final CockpitDirectorySyncer _directorySyncer;

  String get lockPath => '$path.lock';

  Future<T> read() => transact<T>(
    (current) => CockpitLockedJsonUpdate<T, T>.readOnly(current, current),
  );

  Future<R> transact<R>(CockpitLockedJsonTransaction<T, R> transaction) async {
    return _CockpitInProcessLocks.run(
      p.normalize(p.absolute(path)),
      () => _transactWithFileLock(transaction),
    );
  }

  Future<R> _transactWithFileLock<R>(
    CockpitLockedJsonTransaction<T, R> transaction,
  ) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    await permissionHardener.hardenDirectory(target.parent);
    final lockFile = File(lockPath);
    final lockHandle = await lockFile.open(mode: FileMode.append);
    var acquired = false;
    try {
      await permissionHardener.hardenFile(lockFile);
      await lockHandle.lock(FileLock.blockingExclusive);
      acquired = true;
      await _cleanupTemporariesLocked(target);
      final current = await _readLocked(target);
      final update = await transaction(current);
      if (update.shouldWrite) {
        await _atomicFile.write(
          path,
          codec.encode(update.value),
          maximumBytes: maximumBytes,
        );
      }
      return update.result;
    } finally {
      try {
        if (acquired) {
          await lockHandle.unlock();
        }
      } finally {
        await lockHandle.close();
      }
    }
  }

  Future<void> _cleanupTemporariesLocked(File target) async {
    final targetName = p.basename(target.path);
    await for (final entity in target.parent.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (cockpitAtomicJsonTemporaryTargetName(name) != targetName) continue;
      try {
        await cockpitDeleteAtomicJsonTemporary(
          path: entity.path,
          directorySyncer: _directorySyncer,
        );
      } on FileSystemException {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound) rethrow;
      }
    }
  }

  Future<T> _readLocked(File target) async {
    if (!await target.exists()) {
      return createInitial();
    }
    final length = await target.length();
    if (length > maximumBytes) {
      throw CockpitStorageException(
        code: 'storageTooLarge',
        path: path,
        diagnostic: 'JSON document exceeds $maximumBytes bytes.',
      );
    }
    try {
      final source = await target.readAsString();
      return codec.decode(jsonDecode(source));
    } on CockpitStorageException {
      rethrow;
    } on Object catch (error) {
      throw CockpitStorageException(
        code: 'storageCorrupt',
        path: path,
        diagnostic: _bounded(error),
      );
    }
  }
}

abstract final class _CockpitInProcessLocks {
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  static Future<R> run<R>(String path, Future<R> Function() action) async {
    final previous = _tails[path] ?? Future<void>.value();
    final turn = Completer<void>();
    _tails[path] = turn.future;
    await previous;
    try {
      return await action();
    } finally {
      turn.complete();
      if (identical(_tails[path], turn.future)) {
        _tails.remove(path);
      }
    }
  }
}

String _bounded(Object? value) {
  final text = value
      .toString()
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll('\t', ' ')
      .trim();
  return text.length <= 256 ? text : '${text.substring(0, 256)}...';
}
