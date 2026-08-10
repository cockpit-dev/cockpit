import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'cockpit_windows_window_target.dart';

const String cockpitWindowsNativeInputCommandExecutable =
    'cockpit.windows.input';

typedef CockpitWindowsNativeInputExecutor =
    Future<void> Function(List<String> arguments, {required Duration timeout});

Future<void> cockpitExecuteWindowsNativeInput(
  List<String> arguments, {
  required Duration timeout,
}) async {
  if (!Platform.isWindows) {
    throw const CockpitWindowsWindowException(
      'windowsHostRequired',
      'Windows input requires a Windows host.',
    );
  }
  if (arguments.length < 3) {
    throw const FormatException('Windows native input arguments are invalid.');
  }

  final deadline = _CockpitWindowsInputDeadline(timeout);
  final action = arguments[0];
  final appId = arguments[1];
  final processId = arguments[2].isEmpty ? null : int.tryParse(arguments[2]);
  final input = _CockpitWindowsInputApi.instance;

  Future<void> activate() => cockpitResolveWindowsWindowTarget(
    appId: appId,
    processId: processId,
    timeout: deadline.remaining,
    activationSettleDelay: const Duration(milliseconds: 150),
  );

  switch (action) {
    case 'activateWindow':
      await activate();
    case 'tap':
      _requireArgumentCount(arguments, 5);
      input.movePointer(_coordinate(arguments[3]), _coordinate(arguments[4]));
      input.sendMouse(buttonDown: true);
      await deadline.delay(const Duration(milliseconds: 50));
      input.sendMouse(buttonDown: false);
    case 'longPress':
      _requireArgumentCount(arguments, 6);
      input.movePointer(_coordinate(arguments[3]), _coordinate(arguments[4]));
      input.sendMouse(buttonDown: true);
      try {
        await deadline.delay(
          Duration(milliseconds: _nonNegativeInt(arguments[5], 'durationMs')),
        );
      } finally {
        input.sendMouse(buttonDown: false);
      }
    case 'drag':
      _requireArgumentCount(arguments, 8);
      input.movePointer(_coordinate(arguments[3]), _coordinate(arguments[4]));
      input.sendMouse(buttonDown: true);
      try {
        await deadline.delay(
          Duration(milliseconds: _nonNegativeInt(arguments[7], 'durationMs')),
        );
        input.movePointer(_coordinate(arguments[5]), _coordinate(arguments[6]));
      } finally {
        input.sendMouse(buttonDown: false);
      }
    case 'typeText':
      _requireArgumentCount(arguments, 4);
      await activate();
      deadline.ensureRemaining();
      input.sendText(arguments[3]);
    case 'pressKey':
      _requireArgumentCount(arguments, 5);
      await activate();
      final repeat = _positiveInt(arguments[4], 'repeat');
      for (var index = 0; index < repeat; index += 1) {
        deadline.ensureRemaining();
        input.sendKey(arguments[3]);
      }
    case 'pressBack':
      await activate();
      deadline.ensureRemaining();
      input.sendVirtualKey(_virtualKeyEscape);
    default:
      throw FormatException('Unsupported Windows native input action: $action');
  }
}

void _requireArgumentCount(List<String> arguments, int count) {
  if (arguments.length != count) {
    throw const FormatException('Windows native input arguments are invalid.');
  }
}

int _coordinate(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null) throw FormatException('Invalid coordinate: $value');
  return parsed;
}

int _nonNegativeInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw FormatException('$name must be a non-negative integer.');
  }
  return parsed;
}

int _positiveInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw FormatException('$name must be a positive integer.');
  }
  return parsed;
}

final class _CockpitWindowsInputDeadline {
  _CockpitWindowsInputDeadline(this.timeout)
    : stopwatch = Stopwatch()..start() {
    if (timeout <= Duration.zero) {
      throw TimeoutException('Windows native input deadline expired.');
    }
  }

  final Duration timeout;
  final Stopwatch stopwatch;

  Duration get remaining {
    final value = timeout - stopwatch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('Windows native input deadline expired.');
    }
    return value;
  }

  void ensureRemaining() {
    remaining;
  }

  Future<void> delay(Duration duration) async {
    if (duration <= Duration.zero) {
      ensureRemaining();
      return;
    }
    if (duration > remaining) {
      throw TimeoutException('Windows native input deadline expired.');
    }
    await Future<void>.delayed(duration);
    ensureRemaining();
  }
}

final class _CockpitWindowsInputApi {
  _CockpitWindowsInputApi._() : _user32 = DynamicLibrary.open('user32.dll') {
    _setCursorPosition = _user32
        .lookupFunction<_SetCursorPositionNative, _SetCursorPositionDart>(
          'SetCursorPos',
        );
    _sendInput = _user32.lookupFunction<_SendInputNative, _SendInputDart>(
      'SendInput',
    );
  }

  static final _CockpitWindowsInputApi instance = _CockpitWindowsInputApi._();

  final DynamicLibrary _user32;
  late final _SetCursorPositionDart _setCursorPosition;
  late final _SendInputDart _sendInput;

  void movePointer(int x, int y) {
    if (_setCursorPosition(x, y) == 0) {
      throw const CockpitWindowsWindowException(
        'windowsPointerMoveFailed',
        'Windows could not move the pointer to the requested coordinate.',
      );
    }
  }

  void sendMouse({required bool buttonDown}) {
    final inputs = calloc<_WindowsInput>();
    try {
      inputs.ref.type = _inputMouse;
      inputs.ref.data.mouse.dwFlags = buttonDown
          ? _mouseEventLeftDown
          : _mouseEventLeftUp;
      _submit(inputs, 1);
    } finally {
      calloc.free(inputs);
    }
  }

  void sendVirtualKey(int virtualKey) {
    final inputs = calloc<_WindowsInput>(2);
    try {
      inputs[0].type = _inputKeyboard;
      inputs[0].data.keyboard.wVk = virtualKey;
      inputs[1].type = _inputKeyboard;
      inputs[1].data.keyboard.wVk = virtualKey;
      inputs[1].data.keyboard.dwFlags = _keyEventKeyUp;
      _submit(inputs, 2);
    } finally {
      calloc.free(inputs);
    }
  }

  void sendText(String text) {
    if (text.isEmpty) return;
    final codeUnits = text.codeUnits;
    final inputs = calloc<_WindowsInput>(codeUnits.length * 2);
    try {
      for (var index = 0; index < codeUnits.length; index += 1) {
        final down = inputs[index * 2];
        down.type = _inputKeyboard;
        down.data.keyboard.wScan = codeUnits[index];
        down.data.keyboard.dwFlags = _keyEventUnicode;
        final up = inputs[index * 2 + 1];
        up.type = _inputKeyboard;
        up.data.keyboard.wScan = codeUnits[index];
        up.data.keyboard.dwFlags = _keyEventUnicode | _keyEventKeyUp;
      }
      _submit(inputs, codeUnits.length * 2);
    } finally {
      calloc.free(inputs);
    }
  }

  void sendKey(String value) {
    final virtualKey = switch (value.trim().toLowerCase()) {
      'enter' || 'return' => _virtualKeyReturn,
      'escape' || 'esc' => _virtualKeyEscape,
      'tab' => _virtualKeyTab,
      'backspace' => _virtualKeyBackspace,
      'delete' => _virtualKeyDelete,
      'space' => _virtualKeySpace,
      _ => null,
    };
    if (virtualKey != null) {
      sendVirtualKey(virtualKey);
    } else {
      sendText(value);
    }
  }

  void _submit(Pointer<_WindowsInput> inputs, int count) {
    final sent = _sendInput(count, inputs, sizeOf<_WindowsInput>());
    if (sent != count) {
      throw CockpitWindowsWindowException(
        'windowsInputRejected',
        'Windows accepted $sent of $count requested input events.',
      );
    }
  }
}

const int _inputMouse = 0;
const int _inputKeyboard = 1;
const int _mouseEventLeftDown = 0x0002;
const int _mouseEventLeftUp = 0x0004;
const int _keyEventKeyUp = 0x0002;
const int _keyEventUnicode = 0x0004;
const int _virtualKeyBackspace = 0x08;
const int _virtualKeyTab = 0x09;
const int _virtualKeyReturn = 0x0D;
const int _virtualKeyEscape = 0x1B;
const int _virtualKeySpace = 0x20;
const int _virtualKeyDelete = 0x2E;

final class _WindowsMouseInput extends Struct {
  @Int32()
  external int dx;

  @Int32()
  external int dy;

  @Uint32()
  external int mouseData;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int time;

  @IntPtr()
  external int dwExtraInfo;
}

final class _WindowsKeyboardInput extends Struct {
  @Uint16()
  external int wVk;

  @Uint16()
  external int wScan;

  @Uint32()
  external int dwFlags;

  @Uint32()
  external int time;

  @IntPtr()
  external int dwExtraInfo;
}

final class _WindowsHardwareInput extends Struct {
  @Uint32()
  external int message;

  @Uint16()
  external int parameterLow;

  @Uint16()
  external int parameterHigh;
}

final class _WindowsInputUnion extends Union {
  external _WindowsMouseInput mouse;
  external _WindowsKeyboardInput keyboard;
  external _WindowsHardwareInput hardware;
}

final class _WindowsInput extends Struct {
  @Uint32()
  external int type;

  external _WindowsInputUnion data;
}

typedef _SetCursorPositionNative = Int32 Function(Int32, Int32);
typedef _SetCursorPositionDart = int Function(int, int);
typedef _SendInputNative =
    Uint32 Function(Uint32, Pointer<_WindowsInput>, Int32);
typedef _SendInputDart = int Function(int, Pointer<_WindowsInput>, int);
