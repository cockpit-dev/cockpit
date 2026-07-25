import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class CockpitWindowsProcessSnapshot {
  const CockpitWindowsProcessSnapshot({
    required this.processId,
    required this.parentProcessId,
    required this.startIdentity,
  });

  final int processId;
  final int parentProcessId;
  final String startIdentity;
}

CockpitWindowsProcessSnapshot? cockpitReadWindowsProcessSnapshot(
  int processId,
) {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows process snapshots require Windows.');
  }
  if (processId <= 1 || processId > 0xffffffff) return null;
  final api = _WindowsProcessApi.instance;
  final parentProcessId = api.readParentProcessId(processId);
  if (parentProcessId == null) return null;
  final startIdentity = api.readStartIdentity(processId);
  if (startIdentity == null) return null;
  return CockpitWindowsProcessSnapshot(
    processId: processId,
    parentProcessId: parentProcessId,
    startIdentity: startIdentity,
  );
}

final class _WindowsProcessApi {
  _WindowsProcessApi._() : _library = DynamicLibrary.open('kernel32.dll') {
    _createSnapshot = _library
        .lookupFunction<_CreateSnapshotNative, _CreateSnapshotDart>(
          'CreateToolhelp32Snapshot',
        );
    _processFirst = _library
        .lookupFunction<_ProcessFirstNative, _ProcessFirstDart>(
          'Process32FirstW',
        );
    _processNext = _library
        .lookupFunction<_ProcessNextNative, _ProcessNextDart>('Process32NextW');
    _openProcess = _library
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    _getProcessTimes = _library
        .lookupFunction<_GetProcessTimesNative, _GetProcessTimesDart>(
          'GetProcessTimes',
        );
    _closeHandle = _library
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  }

  static final _WindowsProcessApi instance = _WindowsProcessApi._();

  static const int _snapshotProcesses = 0x00000002;
  static const int _queryLimitedInformation = 0x00001000;

  final DynamicLibrary _library;
  late final _CreateSnapshotDart _createSnapshot;
  late final _ProcessFirstDart _processFirst;
  late final _ProcessNextDart _processNext;
  late final _OpenProcessDart _openProcess;
  late final _GetProcessTimesDart _getProcessTimes;
  late final _CloseHandleDart _closeHandle;

  int? readParentProcessId(int processId) {
    final snapshot = _createSnapshot(_snapshotProcesses, 0);
    if (snapshot == -1) return null;
    final entry = calloc<_NativeProcessEntry>();
    try {
      entry.ref.size = sizeOf<_NativeProcessEntry>();
      if (_processFirst(snapshot, entry) == 0) return null;
      do {
        if (entry.ref.processId == processId) {
          return entry.ref.parentProcessId;
        }
      } while (_processNext(snapshot, entry) != 0);
      return null;
    } finally {
      calloc.free(entry);
      _closeHandle(snapshot);
    }
  }

  String? readStartIdentity(int processId) {
    final process = _openProcess(_queryLimitedInformation, 0, processId);
    if (process == 0) return null;
    final times = calloc<_NativeFileTime>(4);
    try {
      final creation = times + 0;
      final exit = times + 1;
      final kernel = times + 2;
      final user = times + 3;
      if (_getProcessTimes(process, creation, exit, kernel, user) == 0) {
        return null;
      }
      final value =
          ((creation.ref.high & 0xffffffff) << 32) |
          (creation.ref.low & 0xffffffff);
      return '$value';
    } finally {
      calloc.free(times);
      _closeHandle(process);
    }
  }
}

final class _NativeFileTime extends Struct {
  @Uint32()
  external int low;

  @Uint32()
  external int high;
}

final class _NativeProcessEntry extends Struct {
  @Uint32()
  external int size;

  @Uint32()
  external int usage;

  @Uint32()
  external int processId;

  external Pointer<Void> defaultHeapId;

  @Uint32()
  external int moduleId;

  @Uint32()
  external int threadCount;

  @Uint32()
  external int parentProcessId;

  @Int32()
  external int basePriority;

  @Uint32()
  external int flags;

  @Array(260)
  external Array<Uint16> executableFile;
}

typedef _CreateSnapshotNative = IntPtr Function(Uint32 flags, Uint32 processId);
typedef _CreateSnapshotDart = int Function(int flags, int processId);
typedef _ProcessFirstNative =
    Int32 Function(IntPtr snapshot, Pointer<_NativeProcessEntry> entry);
typedef _ProcessFirstDart =
    int Function(int snapshot, Pointer<_NativeProcessEntry> entry);
typedef _ProcessNextNative =
    Int32 Function(IntPtr snapshot, Pointer<_NativeProcessEntry> entry);
typedef _ProcessNextDart =
    int Function(int snapshot, Pointer<_NativeProcessEntry> entry);
typedef _OpenProcessNative =
    IntPtr Function(Uint32 access, Int32 inheritHandle, Uint32 processId);
typedef _OpenProcessDart =
    int Function(int access, int inheritHandle, int processId);
typedef _GetProcessTimesNative =
    Int32 Function(
      IntPtr process,
      Pointer<_NativeFileTime> creation,
      Pointer<_NativeFileTime> exit,
      Pointer<_NativeFileTime> kernel,
      Pointer<_NativeFileTime> user,
    );
typedef _GetProcessTimesDart =
    int Function(
      int process,
      Pointer<_NativeFileTime> creation,
      Pointer<_NativeFileTime> exit,
      Pointer<_NativeFileTime> kernel,
      Pointer<_NativeFileTime> user,
    );
typedef _CloseHandleNative = Int32 Function(IntPtr handle);
typedef _CloseHandleDart = int Function(int handle);
