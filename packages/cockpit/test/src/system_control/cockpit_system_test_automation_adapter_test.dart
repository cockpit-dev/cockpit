import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/adapters/cockpit_capture_adapter.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/system_control/cockpit_android_ui_automation_client.dart';
import 'package:cockpit/src/system_control/cockpit_macos_accessibility_tree.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_action_service.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_service.dart';
import 'package:cockpit/src/system_control/cockpit_system_test_automation_adapter.dart';
import 'package:cockpit/src/system_control/cockpit_system_test_target.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('native wait retries a transient UI tree read failure', () async {
    final processes = _TransientUiTreeProcessManager();
    final controls = CockpitSystemControlService(processManager: processes);
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.demo',
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        processManager: processes,
        systemControlService: controls,
        androidUiAutomation: processes,
      ),
      workspaceRoot: Directory.current.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'wait-for-ready',
        commandType: CockpitCommandType.waitFor,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{'label': 'Ready'},
        },
        timeoutMs: 1000,
      ),
    );

    expect(execution.result.success, isTrue);
    expect(processes.uiTreeReads, 2);
    expect(
      execution.result.locatorResolution?.matchedSignals['adapter'],
      'native',
    );
  });

  test('native wait stops immediately for blocked UI observation', () async {
    final processes = _TransientUiTreeProcessManager(failFirst: false);
    final controls = CockpitSystemControlService(processManager: processes);
    var delayCount = 0;
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'macos',
        deviceId: 'macos',
        appId: 'dev.cockpit.demo',
        processId: 4242,
        targetKind: CockpitTargetKind.flutterApp,
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        processManager: processes,
        systemControlService: controls,
        macosAccessibilityTreeReader:
            ({
              required processId,
              required maxDepth,
              required maxNodes,
              required timeout,
            }) async => throw const CockpitMacosAccessibilityException(
              code: 'macosAccessibilityPermissionStale',
              message: 'Accessibility permission must be granted again.',
            ),
      ),
      workspaceRoot: Directory.current.path,
      delay: (_) async {
        delayCount += 1;
      },
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'wait-for-blocked-native-tree',
        commandType: CockpitCommandType.waitFor,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{'label': 'Ready'},
        },
        timeoutMs: 30000,
      ),
    );

    expect(execution.result.success, isFalse);
    expect(
      execution.result.error?.code,
      CockpitCommandError.unsupportedCapabilityCode,
    );
    expect(
      execution.result.error?.details['systemErrorCode'],
      'macosAccessibilityPermissionStale',
    );
    expect(delayCount, 0);
  });

  test('Flutter black-box resolution records its optimized adapter', () async {
    final processes = _TransientUiTreeProcessManager(
      uiTree: _flutterUiTree,
      failFirst: false,
    );
    final controls = CockpitSystemControlService(processManager: processes);
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.demo',
        targetKind: CockpitTargetKind.flutterApp,
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        processManager: processes,
        systemControlService: controls,
        androidUiAutomation: processes,
      ),
      workspaceRoot: Directory.current.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'wait-for-save',
        commandType: CockpitCommandType.waitFor,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{'text': 'Save'},
        },
        timeoutMs: 1000,
      ),
    );

    expect(execution.result.success, isTrue);
    expect(
      execution.result.locatorResolution?.matchedSignals['adapter'],
      'flutterAwareNative',
    );
  });

  test('native tap waits for moving target bounds to stabilize', () async {
    final processes = _TransientUiTreeProcessManager(
      uiTrees: const <String>[
        _movingBackTree,
        _settledBackTree,
        _settledBackTree,
      ],
      failFirst: false,
    );
    final controls = CockpitSystemControlService(processManager: processes);
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.demo',
        targetKind: CockpitTargetKind.flutterApp,
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        processManager: processes,
        systemControlService: controls,
        androidUiAutomation: processes,
      ),
      workspaceRoot: Directory.current.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'tap-back',
        commandType: CockpitCommandType.tap,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{
            'label': 'Back',
            'type': 'Button',
          },
        },
        timeoutMs: 1000,
      ),
    );

    expect(execution.result.success, isTrue);
    expect(processes.uiTreeReads, 3);
    expect(processes.starts.single, <String>[
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'tap',
      '384',
      '246',
    ]);
  });

  test('macOS native tap presses the resolved accessibility element', () async {
    final processes = _TransientUiTreeProcessManager(failFirst: false);
    final controls = CockpitSystemControlService(processManager: processes);
    String? pressedPath;
    int? pressedProcessId;
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'macos',
        deviceId: 'macos',
        appId: 'dev.cockpit.demo',
        processId: 4242,
        targetKind: CockpitTargetKind.flutterApp,
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        processManager: processes,
        systemControlService: controls,
        macosAccessibilityTreeReader:
            ({
              required processId,
              required maxDepth,
              required maxNodes,
              required timeout,
            }) async => _macosBackTree,
      ),
      macosAccessibilityElementPresser:
          ({required processId, required nativePath, required timeout}) async {
            pressedProcessId = processId;
            pressedPath = nativePath;
            return true;
          },
      workspaceRoot: Directory.current.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'press-macos-back',
        commandType: CockpitCommandType.tap,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{
            'label': 'Back',
            'type': 'Button',
          },
        },
        timeoutMs: 1000,
      ),
    );

    expect(execution.result.success, isTrue);
    expect(pressedProcessId, 4242);
    expect(pressedPath, 'w0/c0');
    expect(processes.starts, isEmpty);
  });

  test('blocked system screenshot remains a blocked capability', () async {
    final processes = _TransientUiTreeProcessManager(failFirst: false);
    final controls = CockpitSystemControlService(processManager: processes);
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'macos',
        deviceId: 'macos',
        appId: 'dev.cockpit.console',
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        processManager: processes,
        systemControlService: controls,
        captureAdapterFactory: (_) => const _ScreenRecordingDeniedAdapter(),
      ),
      workspaceRoot: Directory.current.path,
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'capture-blocked',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'blocked',
        ),
      ),
    );

    expect(execution.result.success, isFalse);
    expect(
      execution.result.error?.code,
      CockpitCommandError.unsupportedCapabilityCode,
    );
    expect(
      execution.result.error?.details['systemErrorCode'],
      'systemScreenRecordingPermissionDenied',
    );
  });
}

final class _ScreenRecordingDeniedAdapter implements CockpitCaptureAdapter {
  const _ScreenRecordingDeniedAdapter();

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async =>
      CockpitCommandExecution(
        result: CockpitCommandResult(
          success: false,
          commandId: command.commandId,
          commandType: command.commandType,
          durationMs: 1,
          error: CockpitCommandError.captureFailed(
            message: 'Screen recording permission denied.',
            details: const <String, Object?>{'permission': 'screenRecording'},
          ),
        ),
      );
}

final class _TransientUiTreeProcessManager
    implements CockpitProcessManager, CockpitAndroidUiAutomation {
  _TransientUiTreeProcessManager({
    this.uiTree = _uiTree,
    this.uiTrees = const <String>[],
    this.failFirst = true,
  });

  final String uiTree;
  final List<String> uiTrees;
  final bool failFirst;
  int uiTreeReads = 0;
  final List<List<String>> starts = <List<String>>[];

  @override
  Future<String> readUiTree({
    required String deviceId,
    required int maxDepth,
    required int maxNodes,
    required Duration timeout,
  }) async {
    uiTreeReads += 1;
    if (failFirst && uiTreeReads == 1) {
      throw StateError('UI hierarchy unavailable');
    }
    if (uiTrees.isNotEmpty) {
      return uiTrees[(uiTreeReads - 1).clamp(0, uiTrees.length - 1)];
    }
    return uiTree;
  }

  @override
  Future<String> dismissSystemDialog({
    required String deviceId,
    required String decision,
    required Duration timeout,
  }) => throw UnsupportedError('Not used by this test.');

  @override
  Future<String> tapNotification({
    required String deviceId,
    required String text,
    required Duration timeout,
  }) => throw UnsupportedError('Not used by this test.');

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    if (executable == 'adb' &&
        arguments.isNotEmpty &&
        arguments.last == 'get-state') {
      return ProcessResult(1, 0, 'device\n', '');
    }
    throw StateError('Unexpected process: $executable ${arguments.join(' ')}');
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    if (executable == 'adb' && arguments.contains('tap')) {
      starts.add(List<String>.unmodifiable(arguments));
      return _CompletedProcess();
    }
    throw StateError('Unexpected process: $executable ${arguments.join(' ')}');
  }
}

final class _CompletedProcess implements Process {
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();

  @override
  Future<int> get exitCode async => 0;

  @override
  int get pid => 1234;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _stdinController.close();
    return true;
  }
}

const _uiTree = '''<?xml version="1.0" encoding="UTF-8"?>
<hierarchy bounds="[0,0][100,100]">
  <node content-desc="Ready" bounds="[10,10][90,90]" />
</hierarchy>''';

const _flutterUiTree = '''<?xml version="1.0" encoding="UTF-8"?>
<hierarchy bounds="[0,0][400,800]">
  <node text="Save" class="android.view.View" enabled="true" clickable="true" bounds="[40,100][360,180]">
    <node text="Save" class="android.view.View" enabled="true" clickable="false" bounds="[40,100][360,180]" />
  </node>
</hierarchy>''';

const _movingBackTree = '''<?xml version="1.0" encoding="UTF-8"?>
<hierarchy bounds="[0,0][1200,800]">
  <node content-desc="Back" class="Button" enabled="true" clickable="true" bounds="[432,218][488,274]" />
</hierarchy>''';

const _settledBackTree = '''<?xml version="1.0" encoding="UTF-8"?>
<hierarchy bounds="[0,0][1200,800]">
  <node content-desc="Back" class="Button" enabled="true" clickable="true" bounds="[356,218][412,274]" />
</hierarchy>''';

const _macosBackTree = '''{
  "platform": "macos",
  "windows": [
    {
      "nativePath": "w0",
      "role": "AXWindow",
      "frame": {"x": 100, "y": 50, "width": 800, "height": 600},
      "children": [
        {
          "nativePath": "w0/c0",
          "role": "AXButton",
          "title": "Back",
          "description": "Back",
          "enabled": true,
          "frame": {"x": 110, "y": 60, "width": 56, "height": 56}
        }
      ]
    }
  ]
}''';
