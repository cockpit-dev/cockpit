import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef CockpitWindowsWindowResolver =
    Future<CockpitWindowsWindowTarget> Function({
      required String appId,
      required int? processId,
      required Duration timeout,
      required Duration activationSettleDelay,
    });

const String cockpitWindowsFocusStateCommandExecutable =
    'cockpit.windows.focus';

typedef CockpitWindowsFocusStateReader =
    Future<String> Function({required Duration timeout});

final class CockpitWindowsWindowTarget {
  const CockpitWindowsWindowTarget({
    required this.processId,
    required this.title,
    required this.handle,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int processId;
  final String title;
  final int handle;
  final int left;
  final int top;
  final int width;
  final int height;
}

final class CockpitWindowsWindowException implements Exception {
  const CockpitWindowsWindowException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Future<CockpitWindowsWindowTarget> cockpitResolveWindowsWindowTarget({
  required String appId,
  required int? processId,
  required Duration timeout,
  required Duration activationSettleDelay,
}) async {
  if (!Platform.isWindows) {
    throw const CockpitWindowsWindowException(
      'windowsHostRequired',
      'Windows window control requires a Windows host.',
    );
  }
  if (timeout <= Duration.zero) {
    throw TimeoutException('Windows window activation deadline expired.');
  }

  final stopwatch = Stopwatch()..start();
  final api = _CockpitWindowsApi.instance;
  api.setProcessDpiAware();
  final target = api.resolveTarget(appId: appId, processId: processId);
  api.activate(target.handle);

  final remaining = timeout - stopwatch.elapsed;
  if (activationSettleDelay > Duration.zero) {
    if (remaining <= Duration.zero || activationSettleDelay > remaining) {
      throw TimeoutException('Windows window activation deadline expired.');
    }
    await Future<void>.delayed(activationSettleDelay);
  }
  if (stopwatch.elapsed >= timeout) {
    throw TimeoutException('Windows window activation deadline expired.');
  }
  return api.refreshBounds(target);
}

Future<String> cockpitReadWindowsFocusState({required Duration timeout}) async {
  if (!Platform.isWindows) {
    throw const CockpitWindowsWindowException(
      'windowsHostRequired',
      'Windows focus inspection requires a Windows host.',
    );
  }
  if (timeout <= Duration.zero) {
    throw TimeoutException('Windows focus inspection deadline expired.');
  }
  final stopwatch = Stopwatch()..start();
  final result = _CockpitWindowsApi.instance.readFocusState();
  if (stopwatch.elapsed >= timeout) {
    throw TimeoutException('Windows focus inspection deadline expired.');
  }
  return jsonEncode(result);
}

String cockpitNormalizeWindowsProcessName(String value) {
  final trimmed = value.trim().replaceAll('/', r'\');
  if (trimmed.isEmpty) return '';
  final basename = p.windows.basename(trimmed).toLowerCase();
  return basename.endsWith('.exe')
      ? basename.substring(0, basename.length - 4)
      : basename;
}

CockpitWindowsWindowTarget cockpitSelectWindowsWindowTarget(
  Iterable<CockpitWindowsWindowTarget> candidates, {
  required String appId,
  required int? processId,
}) {
  final matches = candidates.toList(growable: false);
  if (matches.isEmpty) {
    final identity = processId == null
        ? "process '$appId'"
        : 'process id $processId';
    throw CockpitWindowsWindowException(
      'windowsWindowNotFound',
      'No visible main window was found for $identity.',
    );
  }
  final matchingProcessIds = matches
      .map((candidate) => candidate.processId)
      .toSet();
  if (processId == null && matchingProcessIds.length > 1) {
    final sortedProcessIds = matchingProcessIds.toList()..sort();
    throw CockpitWindowsWindowException(
      'windowsWindowAmbiguous',
      "Multiple visible processes match '$appId': $sortedProcessIds. "
          'Select the exact process id.',
    );
  }
  final ranked = matches.toList()
    ..sort((left, right) {
      final processOrder = right.processId.compareTo(left.processId);
      if (processOrder != 0) return processOrder;
      return (right.width * right.height).compareTo(left.width * left.height);
    });
  return ranked.first;
}

final class _CockpitWindowsApi {
  _CockpitWindowsApi._()
    : _user32 = DynamicLibrary.open('user32.dll'),
      _kernel32 = DynamicLibrary.open('kernel32.dll') {
    _enumWindows = _user32.lookupFunction<_EnumWindowsNative, _EnumWindowsDart>(
      'EnumWindows',
    );
    _isWindowVisible = _user32
        .lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>(
          'IsWindowVisible',
        );
    _getWindow = _user32.lookupFunction<_GetWindowNative, _GetWindowDart>(
      'GetWindow',
    );
    _getWindowTextLength = _user32
        .lookupFunction<_GetWindowTextLengthNative, _GetWindowTextLengthDart>(
          'GetWindowTextLengthW',
        );
    _getWindowText = _user32
        .lookupFunction<_GetWindowTextNative, _GetWindowTextDart>(
          'GetWindowTextW',
        );
    _getWindowRect = _user32
        .lookupFunction<_GetWindowRectNative, _GetWindowRectDart>(
          'GetWindowRect',
        );
    _getWindowThreadProcessId = _user32
        .lookupFunction<
          _GetWindowThreadProcessIdNative,
          _GetWindowThreadProcessIdDart
        >('GetWindowThreadProcessId');
    _getForegroundWindow = _user32
        .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
          'GetForegroundWindow',
        );
    _showWindowAsync = _user32
        .lookupFunction<_ShowWindowAsyncNative, _ShowWindowAsyncDart>(
          'ShowWindowAsync',
        );
    _bringWindowToTop = _user32
        .lookupFunction<_BringWindowToTopNative, _BringWindowToTopDart>(
          'BringWindowToTop',
        );
    _setForegroundWindow = _user32
        .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
          'SetForegroundWindow',
        );
    _setProcessDpiAware = _user32
        .lookupFunction<_SetProcessDpiAwareNative, _SetProcessDpiAwareDart>(
          'SetProcessDPIAware',
        );
    _openProcess = _kernel32
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    _queryFullProcessImageName = _kernel32
        .lookupFunction<
          _QueryFullProcessImageNameNative,
          _QueryFullProcessImageNameDart
        >('QueryFullProcessImageNameW');
    _closeHandle = _kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  }

  static final _CockpitWindowsApi instance = _CockpitWindowsApi._();

  final DynamicLibrary _user32;
  final DynamicLibrary _kernel32;
  late final _EnumWindowsDart _enumWindows;
  late final _IsWindowVisibleDart _isWindowVisible;
  late final _GetWindowDart _getWindow;
  late final _GetWindowTextLengthDart _getWindowTextLength;
  late final _GetWindowTextDart _getWindowText;
  late final _GetWindowRectDart _getWindowRect;
  late final _GetWindowThreadProcessIdDart _getWindowThreadProcessId;
  late final _GetForegroundWindowDart _getForegroundWindow;
  late final _ShowWindowAsyncDart _showWindowAsync;
  late final _BringWindowToTopDart _bringWindowToTop;
  late final _SetForegroundWindowDart _setForegroundWindow;
  late final _SetProcessDpiAwareDart _setProcessDpiAware;
  late final _OpenProcessDart _openProcess;
  late final _QueryFullProcessImageNameDart _queryFullProcessImageName;
  late final _CloseHandleDart _closeHandle;

  void setProcessDpiAware() {
    _setProcessDpiAware();
  }

  CockpitWindowsWindowTarget resolveTarget({
    required String appId,
    required int? processId,
  }) {
    final normalizedAppId = cockpitNormalizeWindowsProcessName(appId);
    if (processId == null && normalizedAppId.isEmpty) {
      throw const CockpitWindowsWindowException(
        'missingWindowsWindowTarget',
        'Windows window control requires an app id or process id.',
      );
    }

    final processNames = <int, String?>{};
    final candidates = <CockpitWindowsWindowTarget>[];
    final callback = NativeCallable<_EnumWindowsProcNative>.isolateLocal((
      int windowHandle,
      int _,
    ) {
      if (_isWindowVisible(windowHandle) == 0 ||
          _getWindow(windowHandle, _gwOwner) != 0) {
        return 1;
      }
      final processIdPointer = calloc<Uint32>();
      try {
        _getWindowThreadProcessId(windowHandle, processIdPointer);
        final windowProcessId = processIdPointer.value;
        if (windowProcessId == 0 ||
            (processId != null && windowProcessId != processId)) {
          return 1;
        }
        if (processId == null) {
          final processName = processNames.putIfAbsent(
            windowProcessId,
            () => _readProcessName(windowProcessId),
          );
          if (processName != normalizedAppId) return 1;
        }
        final title = _readWindowTitle(windowHandle);
        if (title.isEmpty) return 1;
        final bounds = _readBounds(windowHandle);
        if (bounds == null) return 1;
        candidates.add(
          CockpitWindowsWindowTarget(
            processId: windowProcessId,
            title: title,
            handle: windowHandle,
            left: bounds.left,
            top: bounds.top,
            width: bounds.width,
            height: bounds.height,
          ),
        );
        return 1;
      } finally {
        calloc.free(processIdPointer);
      }
    }, exceptionalReturn: 0);
    try {
      _enumWindows(callback.nativeFunction, 0);
    } finally {
      callback.close();
    }
    return cockpitSelectWindowsWindowTarget(
      candidates,
      appId: appId,
      processId: processId,
    );
  }

  void activate(int windowHandle) {
    _showWindowAsync(windowHandle, _swRestore);
    _bringWindowToTop(windowHandle);
    _setForegroundWindow(windowHandle);
  }

  Map<String, Object?> readFocusState() {
    final windowHandle = _getForegroundWindow();
    if (windowHandle == 0) {
      return const <String, Object?>{
        'processId': 0,
        'processName': '',
        'windowTitle': '',
      };
    }
    final processIdPointer = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(windowHandle, processIdPointer);
      final processId = processIdPointer.value;
      return <String, Object?>{
        'processId': processId,
        'processName': _readProcessName(processId) ?? '',
        'windowTitle': _readWindowTitle(windowHandle),
      };
    } finally {
      calloc.free(processIdPointer);
    }
  }

  CockpitWindowsWindowTarget refreshBounds(CockpitWindowsWindowTarget target) {
    final bounds = _readBounds(target.handle);
    if (bounds == null) {
      throw CockpitWindowsWindowException(
        'windowsWindowBoundsUnavailable',
        'The target window for process ${target.processId} has invalid bounds.',
      );
    }
    return CockpitWindowsWindowTarget(
      processId: target.processId,
      title: _readWindowTitle(target.handle),
      handle: target.handle,
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );
  }

  String? _readProcessName(int processId) {
    final processHandle = _openProcess(
      _processQueryLimitedInformation,
      0,
      processId,
    );
    if (processHandle == 0) return null;
    final buffer = calloc<Uint16>(_maximumProcessPathLength);
    final length = calloc<Uint32>()..value = _maximumProcessPathLength;
    try {
      if (_queryFullProcessImageName(processHandle, 0, buffer, length) == 0 ||
          length.value == 0) {
        return null;
      }
      return cockpitNormalizeWindowsProcessName(
        String.fromCharCodes(buffer.asTypedList(length.value)),
      );
    } finally {
      calloc.free(buffer);
      calloc.free(length);
      _closeHandle(processHandle);
    }
  }

  String _readWindowTitle(int windowHandle) {
    final length = _getWindowTextLength(windowHandle);
    if (length <= 0) return '';
    final buffer = calloc<Uint16>(length + 1);
    try {
      final written = _getWindowText(windowHandle, buffer, length + 1);
      if (written <= 0) return '';
      return String.fromCharCodes(buffer.asTypedList(written));
    } finally {
      calloc.free(buffer);
    }
  }

  ({int left, int top, int width, int height})? _readBounds(int windowHandle) {
    final rect = calloc<_WindowsRect>();
    try {
      if (_getWindowRect(windowHandle, rect) == 0) return null;
      final width = rect.ref.right - rect.ref.left;
      final height = rect.ref.bottom - rect.ref.top;
      if (width <= 0 || height <= 0) return null;
      return (
        left: rect.ref.left,
        top: rect.ref.top,
        width: width,
        height: height,
      );
    } finally {
      calloc.free(rect);
    }
  }
}

const int _gwOwner = 4;
const int _swRestore = 9;
const int _processQueryLimitedInformation = 0x1000;
const int _maximumProcessPathLength = 32768;

final class _WindowsRect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

typedef _EnumWindowsProcNative = Int32 Function(IntPtr, IntPtr);
typedef _EnumWindowsNative =
    Int32 Function(Pointer<NativeFunction<_EnumWindowsProcNative>>, IntPtr);
typedef _EnumWindowsDart =
    int Function(Pointer<NativeFunction<_EnumWindowsProcNative>>, int);
typedef _IsWindowVisibleNative = Int32 Function(IntPtr);
typedef _IsWindowVisibleDart = int Function(int);
typedef _GetWindowNative = IntPtr Function(IntPtr, Uint32);
typedef _GetWindowDart = int Function(int, int);
typedef _GetWindowTextLengthNative = Int32 Function(IntPtr);
typedef _GetWindowTextLengthDart = int Function(int);
typedef _GetWindowTextNative = Int32 Function(IntPtr, Pointer<Uint16>, Int32);
typedef _GetWindowTextDart = int Function(int, Pointer<Uint16>, int);
typedef _GetWindowRectNative = Int32 Function(IntPtr, Pointer<_WindowsRect>);
typedef _GetWindowRectDart = int Function(int, Pointer<_WindowsRect>);
typedef _GetWindowThreadProcessIdNative =
    Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);
typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();
typedef _ShowWindowAsyncNative = Int32 Function(IntPtr, Int32);
typedef _ShowWindowAsyncDart = int Function(int, int);
typedef _BringWindowToTopNative = Int32 Function(IntPtr);
typedef _BringWindowToTopDart = int Function(int);
typedef _SetForegroundWindowNative = Int32 Function(IntPtr);
typedef _SetForegroundWindowDart = int Function(int);
typedef _SetProcessDpiAwareNative = Int32 Function();
typedef _SetProcessDpiAwareDart = int Function();
typedef _OpenProcessNative = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _QueryFullProcessImageNameNative =
    Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>);
typedef _QueryFullProcessImageNameDart =
    int Function(int, int, Pointer<Uint16>, Pointer<Uint32>);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
