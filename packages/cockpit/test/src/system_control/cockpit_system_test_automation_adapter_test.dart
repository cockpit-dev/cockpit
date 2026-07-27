import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
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
}

final class _TransientUiTreeProcessManager implements CockpitProcessManager {
  _TransientUiTreeProcessManager({
    this.uiTree = _uiTree,
    this.failFirst = true,
  });

  final String uiTree;
  final bool failFirst;
  int uiTreeReads = 0;

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
    uiTreeReads += 1;
    return failFirst && uiTreeReads == 1
        ? _CompletedProcess(
            exitCodeValue: 1,
            stderrText: 'UI hierarchy unavailable',
          )
        : _CompletedProcess(stdoutText: uiTree);
  }
}

final class _CompletedProcess implements Process {
  _CompletedProcess({
    this.exitCodeValue = 0,
    this.stdoutText = '',
    this.stderrText = '',
  });

  final int exitCodeValue;
  final String stdoutText;
  final String stderrText;
  final StreamController<List<int>> _stdin = StreamController<List<int>>();

  @override
  Future<int> get exitCode async => exitCodeValue;

  @override
  int get pid => 1234;

  @override
  Stream<List<int>> get stdout =>
      Stream<List<int>>.value(utf8.encode(stdoutText));

  @override
  Stream<List<int>> get stderr =>
      Stream<List<int>>.value(utf8.encode(stderrText));

  @override
  IOSink get stdin => IOSink(_stdin.sink);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(_stdin.close());
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
