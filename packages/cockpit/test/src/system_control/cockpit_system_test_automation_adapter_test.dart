import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/adapters/cockpit_capture_adapter.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/system_control/cockpit_android_ui_automation_client.dart';
import 'package:cockpit/src/system_control/cockpit_ios_webdriver_agent_client.dart';
import 'package:cockpit/src/system_control/cockpit_macos_accessibility_tree.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_action_service.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_service.dart';
import 'package:cockpit/src/system_control/cockpit_system_test_automation_adapter.dart';
import 'package:cockpit/src/system_control/cockpit_system_test_target.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:image/image.dart' as img;
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

  test('iOS native tap uses the stable resolved WDA coordinate', () async {
    final commands = <CockpitIosWdaCommand>[];
    final controls = CockpitSystemControlService(
      iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
    );
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'ios',
        deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
        appId: 'dev.cockpit.demo',
        metadata: const <String, Object?>{
          'wdaUrl': 'http://127.0.0.1:8100',
          'wdaReachable': true,
        },
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        systemControlService: controls,
        iosWdaRunner: (command, {required timeout}) async {
          commands.add(command);
          return command.action == CockpitIosWdaAction.readUiTree
              ? _iosNewTaskTree
              : 'tap x=292 y=99';
        },
      ),
      workspaceRoot: Directory.current.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'tap-new-task',
        commandType: CockpitCommandType.tap,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{'label': 'New task'},
        },
        timeoutMs: 1000,
      ),
    );

    expect(
      execution.result.success,
      isTrue,
      reason:
          '${execution.result.error?.code} '
          '${execution.result.error?.message} '
          '${execution.result.error?.details}',
    );
    final tap = commands.singleWhere(
      (command) => command.action == CockpitIosWdaAction.tap,
    );
    final treeReads = commands.where(
      (command) => command.action == CockpitIosWdaAction.readUiTree,
    );
    expect(treeReads, isNotEmpty);
    expect(treeReads.every((command) => !command.stabilitySnapshot), isTrue);
    expect(tap.parameters['x'], 292);
    expect(tap.parameters['y'], 99);
    expect(tap.parameters['nativePath'], isNull);
  });

  test(
    'iOS native tap falls back to the session source when foreground source lags',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      Future<String> runner(
        CockpitIosWdaCommand command, {
        required Duration timeout,
      }) async {
        commands.add(command);
        if (command.action == CockpitIosWdaAction.readUiTree) {
          return command.parameters['source'] == 'session'
              ? _iosNewTaskTree
              : _iosVisualViewportTree;
        }
        return 'tap x=292 y=99';
      }

      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          targetKind: CockpitTargetKind.flutterApp,
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: runner,
        ),
        iosWdaRunner: runner,
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'tap-new-task-session-source',
          commandType: CockpitCommandType.tap,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 1000,
        ),
      );

      expect(execution.result.success, isTrue);
      expect(
        execution.result.locatorResolution?.matchedSignals['adapter'],
        'flutterAwareNative',
      );
      expect(
        commands.any(
          (command) =>
              command.action == CockpitIosWdaAction.readUiTree &&
              command.parameters['source'] == 'session',
        ),
        isTrue,
      );
      final tap = commands.singleWhere(
        (command) => command.action == CockpitIosWdaAction.tap,
      );
      expect(tap.parameters['x'], 292);
      expect(tap.parameters['y'], 99);
    },
  );

  test(
    'iOS native tap continues past transient foreground ambiguity',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      Future<String> runner(
        CockpitIosWdaCommand command, {
        required Duration timeout,
      }) async {
        commands.add(command);
        if (command.action == CockpitIosWdaAction.readUiTree) {
          return command.parameters['source'] == 'session'
              ? _iosNewTaskTree
              : _iosDuplicateNewTaskTree;
        }
        return 'tap x=292 y=99';
      }

      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          targetKind: CockpitTargetKind.flutterApp,
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: runner,
        ),
        iosWdaRunner: runner,
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'tap-new-task-ambiguous-foreground',
          commandType: CockpitCommandType.tap,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 1000,
        ),
      );

      expect(execution.result.success, isTrue);
      expect(
        commands.any(
          (command) =>
              command.action == CockpitIosWdaAction.readUiTree &&
              command.parameters['source'] == 'session',
        ),
        isTrue,
      );
      expect(
        commands.any((command) => command.action == CockpitIosWdaAction.tap),
        isTrue,
      );
    },
  );

  test(
    'iOS Flutter native tap falls back to WDA accessibility id lookup',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      Future<String> runner(
        CockpitIosWdaCommand command, {
        required Duration timeout,
      }) async {
        commands.add(command);
        if (command.action == CockpitIosWdaAction.resolveElement &&
            command.parameters['using'] == 'accessibility id') {
          throw StateError('accessibility id is not exposed by this tree');
        }
        return switch (command.action) {
          CockpitIosWdaAction.readUiTree => _iosVisualViewportTree,
          CockpitIosWdaAction.resolveElement => jsonEncode(<String, Object?>{
            'x': 100,
            'y': 200,
            'width': 120,
            'height': 48,
          }),
          _ => 'tap x=160 y=224',
        };
      }

      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          targetKind: CockpitTargetKind.flutterApp,
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: runner,
        ),
        iosWdaRunner: runner,
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'tap-new-task',
          commandType: CockpitCommandType.tap,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 1000,
        ),
      );

      expect(execution.result.success, isTrue);
      expect(
        execution.result.locatorResolution?.matchedSignals['adapter'],
        'iosWdaElement',
      );
      expect(
        commands.any(
          (command) => command.action == CockpitIosWdaAction.resolveElement,
        ),
        isTrue,
      );
      expect(
        commands.any(
          (command) =>
              command.action == CockpitIosWdaAction.resolveElement &&
              command.parameters['using'] == 'predicate string',
        ),
        isTrue,
      );
      final tap = commands.singleWhere(
        (command) => command.action == CockpitIosWdaAction.tap,
      );
      expect(tap.parameters['x'], 160);
      expect(tap.parameters['y'], 224);
    },
  );

  test('iOS UI idle waits use lightweight WDA source snapshots', () async {
    final commands = <CockpitIosWdaCommand>[];
    final controls = CockpitSystemControlService(
      iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
    );
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'ios',
        deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
        appId: 'dev.cockpit.demo',
        metadata: const <String, Object?>{
          'wdaUrl': 'http://127.0.0.1:8100',
          'wdaReachable': true,
        },
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        systemControlService: controls,
        iosWdaRunner: (command, {required timeout}) async {
          commands.add(command);
          return _iosNewTaskTree;
        },
      ),
      workspaceRoot: Directory.current.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'wait-for-ios-idle',
        commandType: CockpitCommandType.waitForUiIdle,
        parameters: const <String, Object?>{'quietMs': 0},
        timeoutMs: 1000,
      ),
    );

    expect(execution.result.success, isTrue);
    final treeReads = commands
        .where((command) => command.action == CockpitIosWdaAction.readUiTree)
        .toList(growable: false);
    expect(treeReads, hasLength(2));
    expect(treeReads.every((command) => command.stabilitySnapshot), isTrue);
  });

  test(
    'iOS native condition waits use lightweight WDA source snapshots',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: (command, {required timeout}) async {
            commands.add(command);
            return _iosNewTaskTree;
          },
        ),
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'wait-for-ios-native-target',
          commandType: CockpitCommandType.waitFor,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 1000,
        ),
      );

      expect(execution.result.success, isTrue);
      final treeReads = commands
          .where((command) => command.action == CockpitIosWdaAction.readUiTree)
          .toList(growable: false);
      expect(treeReads, hasLength(1));
      expect(treeReads.single.stabilitySnapshot, isTrue);
    },
  );

  test(
    'iOS Flutter condition waits ignore stale WDA visibility attributes',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      Future<String> runner(
        CockpitIosWdaCommand command, {
        required Duration timeout,
      }) async {
        commands.add(command);
        if (command.action == CockpitIosWdaAction.readUiTree) {
          return command.stabilitySnapshot
              ? _iosLightweightNewTaskTree
              : _iosStaleVisibilityNewTaskTree;
        }
        throw StateError('WDA element lookup should not be needed.');
      }

      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          targetKind: CockpitTargetKind.flutterApp,
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: runner,
        ),
        iosWdaRunner: runner,
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'wait-for-ios-flutter-target',
          commandType: CockpitCommandType.waitFor,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 1000,
        ),
      );

      expect(execution.result.success, isTrue);
      final treeReads = commands
          .where((command) => command.action == CockpitIosWdaAction.readUiTree)
          .toList(growable: false);
      expect(treeReads, hasLength(1));
      expect(treeReads.single.stabilitySnapshot, isTrue);
    },
  );

  test(
    'iOS native condition waits refresh without activating the foreground app',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      var sourceReads = 0;
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      Future<String> runner(
        CockpitIosWdaCommand command, {
        required Duration timeout,
      }) async {
        commands.add(command);
        if (command.action == CockpitIosWdaAction.readUiTree) {
          sourceReads += 1;
          return sourceReads >= 3 ? _iosNewTaskTree : _iosVisualViewportTree;
        }
        if (command.action == CockpitIosWdaAction.resolveElement) {
          if (command.parameters['activate'] == true) {
            throw TimeoutException('activation must not be used by a wait');
          }
          throw StateError('target is not in the current source yet');
        }
        return 'ok';
      }

      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: runner,
        ),
        iosWdaRunner: runner,
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'wait-for-ios-native-target-after-refresh',
          commandType: CockpitCommandType.waitFor,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 1000,
        ),
      );

      expect(execution.result.success, isTrue);
      expect(
        commands.where(
          (command) => command.action == CockpitIosWdaAction.resolveElement,
        ),
        isNotEmpty,
      );
      expect(
        commands.any(
          (command) =>
              command.action == CockpitIosWdaAction.resolveElement &&
              command.parameters['activate'] == true,
        ),
        isFalse,
      );
      final treeReads = commands
          .where((command) => command.action == CockpitIosWdaAction.readUiTree)
          .toList(growable: false);
      expect(treeReads, hasLength(3));
      expect(treeReads.every((command) => command.stabilitySnapshot), isTrue);
    },
  );

  test(
    'iOS Flutter condition wait refreshes a stale WDA snapshot once',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      Future<String> runner(
        CockpitIosWdaCommand command, {
        required Duration timeout,
      }) async {
        commands.add(command);
        if (command.action == CockpitIosWdaAction.readUiTree) {
          return _iosVisualViewportTree;
        }
        if (command.action == CockpitIosWdaAction.resolveElement) {
          if (command.parameters['activate'] == true) {
            return jsonEncode(<String, Object?>{
              'x': 233,
              'y': 75,
              'width': 117,
              'height': 48,
            });
          }
          throw StateError('stale WDA snapshot');
        }
        return 'ok';
      }

      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          targetKind: CockpitTargetKind.flutterApp,
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: runner,
        ),
        iosWdaRunner: runner,
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'wait-for-ios-stale-native-target',
          commandType: CockpitCommandType.waitFor,
          parameters: const <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          timeoutMs: 5000,
        ),
      );

      expect(execution.result.success, isTrue);
      final activations = commands
          .where(
            (command) =>
                command.action == CockpitIosWdaAction.resolveElement &&
                command.parameters['activate'] == true,
          )
          .toList(growable: false);
      expect(activations, hasLength(1));
    },
  );

  test(
    'iOS repeated and focus taps use stable resolved WDA coordinates',
    () async {
      final commands = <CockpitIosWdaCommand>[];
      final controls = CockpitSystemControlService(
        iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
      );
      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'ios',
          deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
          appId: 'dev.cockpit.demo',
          metadata: const <String, Object?>{
            'wdaUrl': 'http://127.0.0.1:8100',
            'wdaReachable': true,
          },
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          systemControlService: controls,
          iosWdaRunner: (command, {required timeout}) async {
            commands.add(command);
            return command.action == CockpitIosWdaAction.readUiTree
                ? _iosNewTaskTree
                : 'ok';
          },
        ),
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );
      final cases = <(CockpitCommandType, Map<String, Object?>, int)>[
        (
          CockpitCommandType.doubleTap,
          <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
          },
          2,
        ),
        (
          CockpitCommandType.enterText,
          <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
            'text': 'Hello',
          },
          1,
        ),
        (
          CockpitCommandType.eraseText,
          <String, Object?>{
            'cockpitTestLocator': <String, Object?>{'label': 'New task'},
            'characters': 1,
          },
          1,
        ),
      ];

      for (final (type, parameters, expectedTapCount) in cases) {
        commands.clear();
        final execution = await adapter.execute(
          CockpitCommand(
            commandId: type.name,
            commandType: type,
            parameters: parameters,
            timeoutMs: 1000,
          ),
        );

        expect(execution.result.success, isTrue, reason: type.name);
        final taps = commands
            .where((command) => command.action == CockpitIosWdaAction.tap)
            .toList(growable: false);
        expect(taps, hasLength(expectedTapCount), reason: type.name);
        for (final tap in taps) {
          expect(tap.parameters['x'], 292, reason: type.name);
          expect(tap.parameters['y'], 99, reason: type.name);
          expect(tap.parameters['nativePath'], isNull, reason: type.name);
        }
      }
    },
  );

  test('iOS visual taps scale screenshot pixels to the WDA viewport', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'cockpit-ios-visual-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final template = img.Image(width: 8, height: 8, numChannels: 4);
    for (var y = 0; y < template.height; y += 1) {
      for (var x = 0; x < template.width; x += 1) {
        template.setPixelRgba(
          x,
          y,
          (x * 29 + y * 7) % 256,
          (x * 11 + y * 31) % 256,
          (x * 17 + y * 13) % 256,
          255,
        );
      }
    }
    final screenshot = img.Image(width: 90, height: 180, numChannels: 4);
    img.fill(screenshot, color: img.ColorRgba8(12, 18, 24, 255));
    _copyImage(template, screenshot, x: 54, y: 30);
    await _writePng(workspace, 'assets/target.png', template);
    final screenshotFile = await _writePng(
      workspace,
      'captures/screen.png',
      screenshot,
    );
    final commands = <CockpitIosWdaCommand>[];
    final controls = CockpitSystemControlService(
      iosWdaEndpointProbe: (baseUri, {required timeout}) async => true,
    );
    final adapter = CockpitSystemTestAutomationAdapter(
      target: CockpitSystemTestTarget(
        platform: 'ios',
        deviceId: 'D3884373-E926-49AF-92E6-7A241C50B64C',
        appId: 'dev.cockpit.demo',
        metadata: const <String, Object?>{
          'wdaUrl': 'http://127.0.0.1:8100',
          'wdaReachable': true,
        },
      ),
      controlService: controls,
      actionService: CockpitSystemControlActionService(
        systemControlService: controls,
        captureAdapterFactory: (_) =>
            _ScreenshotCaptureAdapter(screenshotFile.path),
        iosWdaRunner: (command, {required timeout}) async {
          commands.add(command);
          return command.action == CockpitIosWdaAction.readUiTree
              ? _iosVisualViewportTree
              : 'ok';
        },
      ),
      workspaceRoot: workspace.path,
      delay: (_) async {},
    );

    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'tap-visual-target',
        commandType: CockpitCommandType.tap,
        parameters: <String, Object?>{
          'cockpitTestLocator': <String, Object?>{
            'visual': 'assets/target.png',
            'threshold': 0.99,
          },
        },
        timeoutMs: 3000,
      ),
    );

    expect(execution.result.success, isTrue);
    final tap = commands.singleWhere(
      (command) => command.action == CockpitIosWdaAction.tap,
    );
    expect(tap.parameters['nativePath'], isNull);
    expect(tap.parameters['x'], 19);
    expect(tap.parameters['y'], 11);
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

  test(
    'macOS native tap uses the process id resolved during tree observation',
    () async {
      final processes = _TransientUiTreeProcessManager(failFirst: false);
      final controls = CockpitSystemControlService(processManager: processes);
      int? pressedProcessId;
      final adapter = CockpitSystemTestAutomationAdapter(
        target: CockpitSystemTestTarget(
          platform: 'macos',
          deviceId: 'macos',
          appId: 'dev.cockpit.demo',
        ),
        controlService: controls,
        actionService: CockpitSystemControlActionService(
          processManager: processes,
          systemControlService: controls,
          macosApplicationProcessIdResolver:
              ({required appId, required timeout}) async => 8642,
          macosAccessibilityTreeReader:
              ({
                required processId,
                required maxDepth,
                required maxNodes,
                required timeout,
              }) async => _macosBackTree,
        ),
        macosAccessibilityElementPresser:
            ({
              required processId,
              required nativePath,
              required timeout,
            }) async {
              pressedProcessId = processId;
              return true;
            },
        workspaceRoot: Directory.current.path,
        delay: (_) async {},
      );

      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'press-macos-back-with-resolved-pid',
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
      expect(pressedProcessId, 8642);
      expect(processes.starts, isEmpty);
    },
  );

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

final class _ScreenshotCaptureAdapter implements CockpitCaptureAdapter {
  const _ScreenshotCaptureAdapter(this.sourcePath);

  final String sourcePath;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    const artifact = CockpitArtifactRef(
      role: 'systemScreenshot',
      relativePath: 'screenshots/system.png',
    );
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 1,
        artifacts: const <CockpitArtifactRef>[artifact],
      ),
      artifactSourcePaths: <String, String>{artifact.relativePath: sourcePath},
    );
  }
}

Future<File> _writePng(
  Directory workspace,
  String relativePath,
  img.Image image,
) async {
  final file = File('${workspace.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(img.encodePng(image), flush: true);
  return file;
}

void _copyImage(
  img.Image source,
  img.Image destination, {
  required int x,
  required int y,
}) {
  for (var sourceY = 0; sourceY < source.height; sourceY += 1) {
    for (var sourceX = 0; sourceX < source.width; sourceX += 1) {
      destination.setPixel(
        x + sourceX,
        y + sourceY,
        source.getPixel(sourceX, sourceY),
      );
    }
  }
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
    String? appId,
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

const _iosNewTaskTree = '''<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication type="XCUIElementTypeApplication" x="0" y="0" width="402" height="874">
  <XCUIElementTypeWindow type="XCUIElementTypeWindow" x="0" y="0" width="402" height="874">
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="New task" label="New task" enabled="true" visible="true" accessible="true" x="233" y="75" width="117" height="48" />
  </XCUIElementTypeWindow>
</XCUIElementTypeApplication>''';

const _iosLightweightNewTaskTree = '''<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication type="XCUIElementTypeApplication" x="0" y="0" width="402" height="874">
  <XCUIElementTypeWindow type="XCUIElementTypeWindow" x="0" y="0" width="402" height="874">
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="New task" label="New task" enabled="true" x="233" y="75" width="117" height="48" />
  </XCUIElementTypeWindow>
</XCUIElementTypeApplication>''';

const _iosStaleVisibilityNewTaskTree = '''<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication type="XCUIElementTypeApplication" x="0" y="0" width="402" height="874">
  <XCUIElementTypeWindow type="XCUIElementTypeWindow" x="0" y="0" width="402" height="874">
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="New task" label="New task" enabled="true" visible="false" accessible="false" x="233" y="75" width="117" height="48" />
  </XCUIElementTypeWindow>
</XCUIElementTypeApplication>''';

const _iosDuplicateNewTaskTree = '''<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication type="XCUIElementTypeApplication" x="0" y="0" width="402" height="874">
  <XCUIElementTypeWindow type="XCUIElementTypeWindow" x="0" y="0" width="402" height="874">
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="New task" label="New task" enabled="true" visible="true" accessible="true" x="30" y="75" width="117" height="48" />
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="New task" label="New task" enabled="true" visible="true" accessible="true" x="233" y="75" width="117" height="48" />
  </XCUIElementTypeWindow>
</XCUIElementTypeApplication>''';

const _iosVisualViewportTree = '''<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication type="XCUIElementTypeApplication" x="0" y="0" width="30" height="60">
  <XCUIElementTypeWindow type="XCUIElementTypeWindow" x="0" y="0" width="30" height="60" />
</XCUIElementTypeApplication>''';

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
