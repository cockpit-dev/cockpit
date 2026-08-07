import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/adapters/cockpit_capture_adapter.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/system_control/cockpit_android_ui_automation_client.dart';
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
    this.failFirst = true,
  });

  final String uiTree;
  final bool failFirst;
  int uiTreeReads = 0;

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
    throw StateError('Unexpected process: $executable ${arguments.join(' ')}');
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
