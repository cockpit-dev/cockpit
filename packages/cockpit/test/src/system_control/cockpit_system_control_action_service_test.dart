import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/system_control/cockpit_android_ui_automation_client.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/adapters/cockpit_capture_adapter.dart';
import 'package:cockpit/src/adapters/cockpit_recording_adapter.dart';
import 'package:cockpit/src/system_control/cockpit_ios_webdriver_agent_client.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_action_service.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_service.dart';
import 'package:test/test.dart';

void main() {
  test('android tap executes through adb shell input tap', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.tap,
        parameters: <String, Object?>{'x': 42, 'y': 88},
      ),
    );

    expect(result.success, isTrue);
    expect(result.availability, CockpitSystemControlAvailability.available);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'tap',
      '42',
      '88',
    ]);
    expect(processManager.starts.single.executable, 'adb');
    expect(processManager.starts.single.arguments, <String>[
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'tap',
      '42',
      '88',
    ]);
  });

  test('android pressKey batches repeated keys in one process', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.pressKey,
        parameters: <String, Object?>{'key': 'backspace', 'repeat': 3},
      ),
    );

    expect(result.success, isTrue);
    expect(processManager.starts.single.arguments, <String>[
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'keyevent',
      'KEYCODE_DEL',
      'KEYCODE_DEL',
      'KEYCODE_DEL',
    ]);
  });

  test(
    'blocked ios physical action returns guidance without spawning process',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '00008110-001234',
          action: CockpitSystemControlAction.tap,
          parameters: <String, Object?>{'x': 42, 'y': 88},
        ),
      );

      expect(result.success, isFalse);
      expect(result.availability, CockpitSystemControlAvailability.blocked);
      expect(result.recommendedNextStep, 'startWebDriverAgent');
      expect(
        result.requires,
        contains(contains('reachable WebDriverAgent endpoint')),
      );
      expect(processManager.starts, isEmpty);
    },
  );

  test('ios simulator native tap executes through WebDriverAgent', () async {
    final processManager = _FakeProcessManager();
    CockpitIosWdaCommand? capturedCommand;
    final service = CockpitSystemControlActionService(
      processManager: processManager,
      systemControlService: CockpitSystemControlService(
        iosWdaEndpointProbe: (_, {required timeout}) async => true,
      ),
      iosWdaRunner: (command, {required timeout}) async {
        capturedCommand = command;
        return 'tap x=42 y=88';
      },
    );

    final result = await service.run(
      CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        metadata: <String, Object?>{'wdaUrl': 'http://127.0.0.1:8100'},
        action: CockpitSystemControlAction.tap,
        parameters: <String, Object?>{'x': 42, 'y': 88},
      ),
    );

    expect(result.success, isTrue);
    expect(result.availability, CockpitSystemControlAvailability.available);
    expect(result.stdout, 'tap x=42 y=88');
    expect(capturedCommand?.baseUri, Uri.parse('http://127.0.0.1:8100'));
    expect(capturedCommand?.action, CockpitIosWdaAction.tap);
    expect(capturedCommand?.parameters['x'], 42);
    expect(processManager.starts, isEmpty);
  });

  test(
    'ios simulator native action uses auto-discovered WebDriverAgent endpoint',
    () async {
      final processManager = _FakeProcessManager();
      CockpitIosWdaCommand? capturedCommand;
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        systemControlService: CockpitSystemControlService(
          iosWdaEndpointProbe: (uri, {required timeout}) async =>
              uri == Uri.parse('http://127.0.0.1:8100'),
        ),
        iosWdaRunner: (command, {required timeout}) async {
          capturedCommand = command;
          return 'dismissSystemDialog mode=accept';
        },
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          action: CockpitSystemControlAction.dismissSystemDialog,
          parameters: <String, Object?>{'decision': 'dismiss'},
        ),
      );

      expect(result.success, isTrue);
      expect(result.availability, CockpitSystemControlAvailability.available);
      expect(capturedCommand?.baseUri, Uri.parse('http://127.0.0.1:8100'));
      expect(capturedCommand?.action, CockpitIosWdaAction.dismissSystemDialog);
      expect(capturedCommand?.parameters['decision'], 'dismiss');
      expect(processManager.starts, isEmpty);
    },
  );

  test(
    'ios simulator dismissKeyboard executes through WebDriverAgent',
    () async {
      CockpitIosWdaCommand? capturedCommand;
      final service = CockpitSystemControlActionService(
        systemControlService: CockpitSystemControlService(
          iosWdaEndpointProbe: (_, {required timeout}) async => true,
        ),
        iosWdaRunner: (command, {required timeout}) async {
          capturedCommand = command;
          return 'dismissKeyboard';
        },
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          metadata: <String, Object?>{'wdaUrl': 'http://127.0.0.1:8100'},
          action: CockpitSystemControlAction.dismissKeyboard,
        ),
      );

      expect(result.success, isTrue);
      expect(capturedCommand?.action, CockpitIosWdaAction.dismissKeyboard);
    },
  );

  test(
    'ios simulator preparePermissions grants services and recovers app',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.preparePermissions,
          parameters: <String, Object?>{
            'permissions': <String>['microphone', 'photos'],
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.recommendedNextStep, 'readPostActionState');
      expect(
        processManager.starts.map((start) => start.arguments),
        containsAll(<List<String>>[
          <String>[
            'simctl',
            'privacy',
            '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
            'grant',
            'microphone',
            'dev.cockpit.example',
          ],
          <String>[
            'simctl',
            'privacy',
            '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
            'grant',
            'photos',
            'dev.cockpit.example',
          ],
          <String>[
            'simctl',
            'launch',
            '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
            'dev.cockpit.example',
          ],
        ]),
      );
    },
  );

  test(
    'ios simulator stabilizeForScreenshot skips WDA-only blockers when WDA is unavailable',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        systemControlService: CockpitSystemControlService(
          iosWdaEndpointProbe: (_, {required timeout}) async => false,
        ),
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.stabilizeForScreenshot,
          parameters: <String, Object?>{
            'statusBar': 'stable',
            'appearance': 'dark',
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.limitations.join('\n'), contains('dismissKeyboard'));
      final commands = processManager.starts
          .map((start) => '${start.executable} ${start.arguments.join(' ')}')
          .join('\n');
      expect(
        commands,
        contains(
          'simctl ui 6FD25DED-11E9-4AE9-B4B5-EDF4601981DC appearance dark',
        ),
      );
      expect(
        commands,
        contains(
          'simctl status_bar 6FD25DED-11E9-4AE9-B4B5-EDF4601981DC override',
        ),
      );
      expect(
        commands,
        contains(
          'simctl launch 6FD25DED-11E9-4AE9-B4B5-EDF4601981DC dev.cockpit.example',
        ),
      );
    },
  );

  test(
    'ios simulator stabilizeForScreenshot treats auto appearance and orientation as unchanged',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        systemControlService: CockpitSystemControlService(
          iosWdaEndpointProbe: (_, {required timeout}) async => false,
        ),
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.stabilizeForScreenshot,
          parameters: <String, Object?>{
            'orientation': 'auto',
            'appearance': 'auto',
            'statusBar': 'stable',
          },
        ),
      );

      expect(result.success, isTrue);
      final commands = processManager.starts
          .map((start) => '${start.executable} ${start.arguments.join(' ')}')
          .join('\n');
      expect(commands, isNot(contains('simctl ui')));
      expect(commands, isNot(contains('orientation')));
      expect(commands, contains('simctl status_bar'));
      expect(commands, contains('simctl launch'));
    },
  );

  test('ios simulator pressHome executes through WebDriverAgent', () async {
    CockpitIosWdaCommand? capturedCommand;
    final service = CockpitSystemControlActionService(
      systemControlService: CockpitSystemControlService(
        iosWdaEndpointProbe: (_, {required timeout}) async => true,
      ),
      iosWdaRunner: (command, {required timeout}) async {
        capturedCommand = command;
        return 'pressHome';
      },
    );

    final result = await service.run(
      CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        metadata: <String, Object?>{'wdaUrl': 'http://127.0.0.1:8100'},
        action: CockpitSystemControlAction.pressHome,
      ),
    );

    expect(result.success, isTrue);
    expect(capturedCommand?.action, CockpitIosWdaAction.pressHome);
  });

  test(
    'ios simulator system shade actions execute through WebDriverAgent gestures',
    () async {
      final capturedActions = <CockpitIosWdaAction>[];
      final service = CockpitSystemControlActionService(
        systemControlService: CockpitSystemControlService(
          iosWdaEndpointProbe: (_, {required timeout}) async => true,
        ),
        iosWdaRunner: (command, {required timeout}) async {
          capturedActions.add(command.action);
          return command.action.name;
        },
      );

      for (final action in <CockpitSystemControlAction>[
        CockpitSystemControlAction.expandNotifications,
        CockpitSystemControlAction.expandQuickSettings,
        CockpitSystemControlAction.collapseSystemUi,
      ]) {
        final result = await service.run(
          CockpitSystemControlActionRequest(
            platform: 'ios',
            deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
            metadata: const <String, Object?>{
              'wdaUrl': 'http://127.0.0.1:8100',
            },
            action: action,
          ),
        );

        expect(result.success, isTrue);
      }

      expect(capturedActions, <CockpitIosWdaAction>[
        CockpitIosWdaAction.expandNotifications,
        CockpitIosWdaAction.expandQuickSettings,
        CockpitIosWdaAction.collapseSystemUi,
      ]);
    },
  );

  test('missing required parameters fail before spawning process', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.tap,
      ),
    );

    expect(result.success, isFalse);
    expect(result.availability, CockpitSystemControlAvailability.available);
    expect(result.errorCode, 'missingSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test(
    'empty required string parameters fail before spawning process',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.grantPermission,
          parameters: <String, Object?>{'permission': '   '},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'missingSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(processManager.starts, isEmpty);
    },
  );

  test('fractional integer parameters fail before spawning process', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.tap,
        parameters: <String, Object?>{'x': 42.7, 'y': 88},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('bounded integer parameters reject out-of-range values early', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setStatusBar,
        parameters: <String, Object?>{'batteryLevel': 101},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('non-string text parameters fail before spawning process', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.pressKey,
        parameters: <String, Object?>{'key': 13},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('runShell rejects non-list command parameters', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.runShell,
        parameters: <String, Object?>{'command': 'echo ok'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test(
    'runShell rejects empty command arrays before spawning process',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.runShell,
          parameters: <String, Object?>{'command': <String>[]},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'missingSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(processManager.starts, isEmpty);
    },
  );

  test('runShell rejects non-string command entries', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.runShell,
        parameters: <String, Object?>{
          'command': <Object?>['echo', 1],
        },
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android grantPermission rejects non-string permission', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.grantPermission,
        parameters: <String, Object?>{'permission': 42},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setOrientation rejects non-string orientation', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setOrientation,
        parameters: <String, Object?>{'orientation': 1},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android package aliases reject non-string values', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.activateWindow,
        parameters: <String, Object?>{'packageId': 123},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios app aliases reject non-string values', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.activateWindow,
        parameters: <String, Object?>{'appId': 123},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios app payload rejects undeclared packageId aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.activateWindow,
        parameters: <String, Object?>{'packageId': 'dev.cockpit.example'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('fractional longPress duration fails before spawning process', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.longPress,
        parameters: <String, Object?>{'x': 42, 'y': 88, 'durationMs': 1.5},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('non-positive drag duration fails before spawning process', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.drag,
        parameters: <String, Object?>{
          'startX': 10,
          'startY': 20,
          'endX': 30,
          'endY': 40,
          'durationMs': 0,
        },
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test(
    'invalid optional integer parameters do not fall back to defaults',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'macos',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.readUiTree,
          parameters: <String, Object?>{'maxDepth': 'deep', 'maxNodes': 20},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'invalidSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(processManager.starts, isEmpty);
    },
  );

  test('readUiTree enforces positive integer limits', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'windows',
        processId: 4242,
        action: CockpitSystemControlAction.readUiTree,
        parameters: <String, Object?>{'maxDepth': 0, 'maxNodes': 20},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios status bar rejects invalid integer overrides', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setStatusBar,
        parameters: <String, Object?>{'time': '09:41', 'wifiBars': 1.5},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios grantPermission rejects unsupported privacy services', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.grantPermission,
        parameters: <String, Object?>{'permission': 'camera'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios grantPermission rejects undeclared service aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.grantPermission,
        parameters: <String, Object?>{'service': 'photos'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios setContentSize rejects unsupported categories', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setContentSize,
        parameters: <String, Object?>{'contentSize': 'huge'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('ios status bar rejects unsupported string overrides', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setStatusBar,
        parameters: <String, Object?>{
          'time': '09:41',
          'dataNetwork': 'bluetooth',
        },
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('setLocation rejects non-numeric coordinates', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setLocation,
        parameters: <String, Object?>{
          'latitude': 'north',
          'longitude': -122.009,
        },
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('setLocation rejects undeclared coordinate aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setLocation,
        parameters: <String, Object?>{'lat': 37.3349, 'lng': -122.009},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setContentSize rejects numeric contentSize payloads', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setContentSize,
        parameters: <String, Object?>{'contentSize': 1.3},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test(
    'android readUiTree executes the bundled UI Automation driver',
    () async {
      final processManager = _FakeProcessManager();
      final androidUiAutomation = _FakeAndroidUiAutomation();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        androidUiAutomation: androidUiAutomation,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.readUiTree,
        ),
      );

      expect(result.success, isTrue);
      expect(result.stdout, '<?xml version="1.0"?><hierarchy />');
      expect(result.command, <String>[
        'adb',
        '-s',
        'emulator-5554',
        'shell',
        'am',
        'instrument',
        '-e',
        'class',
        'dev.cockpit.driver.CockpitDriverTest#dumpUiTree',
        'dev.cockpit.driver.test/androidx.test.runner.AndroidJUnitRunner',
      ]);
      expect(androidUiAutomation.lastAction, 'readUiTree');
      expect(androidUiAutomation.deviceId, 'emulator-5554');
      expect(androidUiAutomation.maxDepth, 16);
      expect(androidUiAutomation.maxNodes, 2000);
      expect(processManager.starts, isEmpty);
    },
  );

  test('android activateWindow launches package through adb monkey', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.activateWindow,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'monkey',
      '-p',
      'dev.cockpit.example',
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ]);
  });

  test('android grantPermission accepts appId as the package id', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.grantPermission,
        parameters: <String, Object?>{
          'permission': 'android.permission.CAMERA',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'pm',
      'grant',
      'dev.cockpit.example',
      'android.permission.CAMERA',
    ]);
  });

  test('android revokePermission uses adb pm revoke', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.revokePermission,
        parameters: <String, Object?>{
          'permission': 'android.permission.CAMERA',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'pm',
      'revoke',
      'dev.cockpit.example',
      'android.permission.CAMERA',
    ]);
  });

  test('android pushFile uses adb push', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.pushFile,
        parameters: <String, Object?>{
          'sourcePath': '/tmp/input.wav',
          'destinationPath': '/sdcard/Download/input.wav',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'push',
      '/tmp/input.wav',
      '/sdcard/Download/input.wav',
    ]);
  });

  test('android pressKey sends adb keyevent', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.pressKey,
        parameters: <String, Object?>{'key': 'KEYCODE_ENTER'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'keyevent',
      'KEYCODE_ENTER',
    ]);
  });

  test('android terminateApp force-stops the package', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.terminateApp,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'am',
      'force-stop',
      'dev.cockpit.example',
    ]);
  });

  test(
    'android setAppearance maps dark mode to UiModeManager night yes',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.setAppearance,
          parameters: <String, Object?>{'appearance': 'dark'},
        ),
      );

      expect(result.success, isTrue);
      expect(result.command, <String>[
        'adb',
        '-s',
        'emulator-5554',
        'shell',
        'cmd',
        'uimode',
        'night',
        'yes',
      ]);
    },
  );

  test('android setAppearance rejects undeclared night aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setAppearance,
        parameters: <String, Object?>{'appearance': 'night'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setAppearance rejects undeclared system aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setAppearance,
        parameters: <String, Object?>{'appearance': 'system'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setContentSize maps content token to font scale', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setContentSize,
        parameters: <String, Object?>{'contentSize': 'accessibility-large'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'settings',
      'put',
      'system',
      'font_scale',
      '1.8',
    ]);
  });

  test('android pressVolumeUp sends the hardware volume key', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.pressVolumeUp,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'keyevent',
      'KEYCODE_VOLUME_UP',
    ]);
  });

  test(
    'android dismissSystemDialog accepts common system permission buttons',
    () async {
      final processManager = _FakeProcessManager();
      final androidUiAutomation = _FakeAndroidUiAutomation();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        androidUiAutomation: androidUiAutomation,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.dismissSystemDialog,
          parameters: <String, Object?>{'decision': 'accept'},
        ),
      );

      expect(result.success, isTrue);
      expect(result.command, <String>[
        'adb',
        '-s',
        'emulator-5554',
        'shell',
        'am',
        'instrument',
        '-e',
        'class',
        'dev.cockpit.driver.CockpitDriverTest#tapSystemDialog',
        'dev.cockpit.driver.test/androidx.test.runner.AndroidJUnitRunner',
      ]);
      expect(androidUiAutomation.lastAction, 'dismissSystemDialog');
      expect(androidUiAutomation.decision, 'accept');
      expect(processManager.starts, isEmpty);
    },
  );

  test(
    'android dismissSystemDialog dismisses or backs out of dialogs',
    () async {
      final processManager = _FakeProcessManager();
      final androidUiAutomation = _FakeAndroidUiAutomation();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        androidUiAutomation: androidUiAutomation,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.dismissSystemDialog,
          parameters: <String, Object?>{'decision': 'dismiss'},
        ),
      );

      expect(result.success, isTrue);
      expect(androidUiAutomation.lastAction, 'dismissSystemDialog');
      expect(androidUiAutomation.decision, 'dismiss');
      expect(processManager.starts, isEmpty);
    },
  );

  test('android dismissSystemDialog rejects invalid decisions', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.dismissSystemDialog,
        parameters: <String, Object?>{'decision': 'maybe'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(processManager.starts, isEmpty);
  });

  test('android expandNotifications opens the notification shade', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.expandNotifications,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'cmd',
      'statusbar',
      'expand-notifications',
    ]);
  });

  test('android postNotification uses cmd notification post', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.postNotification,
        parameters: <String, Object?>{
          'title': 'Download complete',
          'body': 'Model is ready',
          'tag': 'model-download',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'cmd',
      'notification',
      'post',
      '--title',
      'Download complete',
      'model-download',
      'Model is ready',
    ]);
  });

  test('android postNotification rejects empty payloads', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.postNotification,
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'missingSystemActionParameter');
    expect(processManager.starts, isEmpty);
  });

  test(
    'android tapNotification expands notifications and taps matching text',
    () async {
      final processManager = _FakeProcessManager();
      final androidUiAutomation = _FakeAndroidUiAutomation();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        androidUiAutomation: androidUiAutomation,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.tapNotification,
          parameters: <String, Object?>{'title': 'Download complete'},
        ),
      );

      expect(result.success, isTrue);
      expect(androidUiAutomation.lastAction, 'tapNotification');
      expect(androidUiAutomation.text, 'Download complete');
      expect(processManager.starts, isEmpty);
    },
  );

  test(
    'android recoverToApp collapses system UI and relaunches package',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.recoverToApp,
        ),
      );

      expect(result.success, isTrue);
      expect(result.command.take(5), <String>[
        'adb',
        '-s',
        'emulator-5554',
        'shell',
        'sh',
      ]);
      expect(result.command[5], '-c');
      expect(result.command[6], contains('cmd statusbar collapse'));
    },
  );

  test(
    'android resolveBlockers accepts dialogs and restores app focus',
    () async {
      final processManager = _FakeProcessManager();
      final androidUiAutomation = _FakeAndroidUiAutomation(
        dialogError: StateError('No matching system dialog'),
      );
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        androidUiAutomation: androidUiAutomation,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.resolveBlockers,
        ),
      );

      expect(result.success, isTrue);
      expect(androidUiAutomation.lastAction, 'dismissSystemDialog');
      expect(processManager.starts, hasLength(3));
      expect(
        processManager.starts.last.arguments.last,
        contains('dev.cockpit.example'),
      );
      expect(result.stdout, contains('dismissSystemDialog'));
      expect(result.stdout, contains('systemActionProcessFailed'));
      expect(result.stdout, contains('recoverToApp'));
    },
  );

  test(
    'android preparePermissions grants each permission and recovers app',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.preparePermissions,
          parameters: <String, Object?>{
            'permissions': <String>[
              'android.permission.CAMERA',
              'android.permission.RECORD_AUDIO',
            ],
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.recommendedNextStep, 'readPostActionState');
      final payload = jsonDecode(result.stdout!) as Map<String, Object?>;
      final steps = payload['steps']! as List<Object?>;
      expect(steps, hasLength(3));
      expect(
        processManager.starts.map((start) => start.arguments.join(' ')),
        containsAll(<String>[
          '-s emulator-5554 shell pm grant dev.cockpit.example android.permission.CAMERA',
          '-s emulator-5554 shell pm grant dev.cockpit.example android.permission.RECORD_AUDIO',
        ]),
      );
      expect(
        processManager.starts.last.arguments.join(' '),
        contains('monkey -p'),
      );
    },
  );

  test(
    'android stabilizeForScreenshot runs available stabilization steps',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.stabilizeForScreenshot,
          parameters: <String, Object?>{
            'orientation': 'portrait',
            'appearance': 'dark',
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.recommendedNextStep, 'captureScreenshot');
      final commands = processManager.starts
          .map((start) => start.arguments.join(' '))
          .join('\n');
      expect(commands, contains('input keyevent KEYCODE_BACK'));
      expect(commands, contains('cmd statusbar collapse'));
      expect(commands, contains('user_rotation 0'));
      expect(commands, contains('cmd uimode night yes'));
      expect(commands, contains('monkey -p'));
    },
  );

  test(
    'ios simulator stabilizeForScreenshot uses auto-discovered WebDriverAgent for native steps',
    () async {
      final processManager = _FakeProcessManager();
      final capturedActions = <CockpitIosWdaAction>[];
      final service = CockpitSystemControlActionService(
        processManager: processManager,
        systemControlService: CockpitSystemControlService(
          iosWdaEndpointProbe: (uri, {required timeout}) async =>
              uri == Uri.parse('http://127.0.0.1:8100'),
        ),
        iosWdaRunner: (command, {required timeout}) async {
          capturedActions.add(command.action);
          return '${command.action.name} ok';
        },
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.stabilizeForScreenshot,
        ),
      );

      expect(result.success, isTrue);
      expect(
        capturedActions,
        containsAll(<CockpitIosWdaAction>[
          CockpitIosWdaAction.dismissKeyboard,
          CockpitIosWdaAction.collapseSystemUi,
        ]),
      );
      expect(result.limitations.join('\n'), isNot(contains('dismissKeyboard')));
      expect(
        processManager.starts
            .map((start) => start.arguments.join(' '))
            .join('\n'),
        contains(
          'simctl launch 6FD25DED-11E9-4AE9-B4B5-EDF4601981DC dev.cockpit.example',
        ),
      );
    },
  );

  test(
    'android stabilizeForScreenshot without app target skips optional recovery',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.stabilizeForScreenshot,
        ),
      );

      expect(result.success, isTrue);
      expect(
        result.limitations.join('\n'),
        contains(
          'Optional system actions failed and were skipped: recoverToApp',
        ),
      );
      final payload = jsonDecode(result.stdout!) as Map<String, Object?>;
      final steps = (payload['steps']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final recoverStep = steps.singleWhere(
        (step) => step['action'] == 'recoverToApp',
      );
      expect(recoverStep['success'], isFalse);
      expect(recoverStep['optional'], isTrue);
    },
  );

  test(
    'android stabilizeForScreenshot statusBar stable applies SystemUI demo mode',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.stabilizeForScreenshot,
          parameters: <String, Object?>{'statusBar': 'stable'},
        ),
      );

      expect(result.success, isTrue);
      final commands = processManager.starts
          .map((start) => start.arguments.join(' '))
          .join('\n');
      expect(commands, contains('settings put global sysui_demo_allowed 1'));
      expect(commands, contains('-e command clock -e hhmm 0941'));
    },
  );

  test(
    'android grantPermission success omits iOS simctl limitations',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.grantPermission,
          parameters: <String, Object?>{
            'permission': 'android.permission.CAMERA',
          },
        ),
      );

      expect(result.success, isTrue);
      expect(
        result.limitations,
        isNot(contains('simctl privacy may terminate the app')),
      );
    },
  );

  test('ios physical device installs apps through devicectl', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '00008110-001234',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.installApp,
        parameters: <String, Object?>{'appPath': '/tmp/example.app'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.availability, CockpitSystemControlAvailability.available);
    expect(result.command, <String>[
      'xcrun',
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      '00008110-001234',
      '/tmp/example.app',
    ]);
    expect(processManager.starts.single.executable, 'xcrun');
    expect(processManager.starts.single.arguments, result.command.skip(1));
  });

  test('android setStatusBar drives SystemUI demo mode', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setStatusBar,
        parameters: <String, Object?>{
          'time': '9:41',
          'wifiMode': 'active',
          'wifiBars': 3,
          'cellularMode': 'active',
          'cellularBars': 4,
          'batteryState': 'charged',
          'batteryLevel': 100,
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.take(6), <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'sh',
      '-c',
    ]);
    final script = result.command.last;
    expect(script, contains('settings put global sysui_demo_allowed 1'));
    expect(script, contains('-e command enter'));
    expect(script, contains('-e command clock -e hhmm 0941'));
    expect(
      script,
      contains('-e command network -e wifi show -e fully true -e level 3'),
    );
    expect(
      script,
      contains('-e command network -e mobile show -e fully true -e level 4'),
    );
    expect(
      script,
      contains('-e command battery -e level 100 -e plugged true'),
      reason: '"charged" means full while still on power, matching iOS.',
    );
  });

  test('android clearStatusBar exits SystemUI demo mode', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.clearStatusBar,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'am',
      'broadcast',
      '-a',
      'com.android.systemui.demo',
      '-e',
      'command',
      'exit',
    ]);
  });

  test('macos openSystemSettings opens System Settings by default', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.openSystemSettings,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>['open', 'x-apple.systempreferences:']);
  });

  test('windows openSystemSettings starts the ms-settings target', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'windows',
        action: CockpitSystemControlAction.openSystemSettings,
        parameters: <String, Object?>{'settingsAction': 'ms-settings:display'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.first, 'powershell');
    final script = _decodeWindowsPowershellScript(result.command);
    expect(script, contains(r'Start-Process -FilePath $args[0]'));
    expect(script, contains("} 'ms-settings:display'"));
  });

  test('macos resetPermission resets a TCC service through tccutil', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.resetPermission,
        parameters: <String, Object?>{'permission': 'camera'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'tccutil',
      'reset',
      'Camera',
      'dev.cockpit.example',
    ]);
  });

  test('macos setAppearance toggles dark mode through System Events', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.setAppearance,
        parameters: <String, Object?>{'appearance': 'dark'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.first, 'osascript');
    expect(result.command.last, contains('set dark mode to true'));
  });

  test('windows setAppearance writes the personalize registry keys', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'windows',
        action: CockpitSystemControlAction.setAppearance,
        parameters: <String, Object?>{'appearance': 'dark'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.first, 'powershell');
    final script = _decodeWindowsPowershellScript(result.command);
    expect(script, contains('AppsUseLightTheme'));
    expect(script, contains("} 'dark'"));
  });

  test('linux postNotification posts through notify-send', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'linux',
        action: CockpitSystemControlAction.postNotification,
        parameters: <String, Object?>{
          'title': 'Build done',
          'body': 'All tests passed',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('notify-send'));
    expect(result.command, contains('Build done'));
    expect(result.command, contains('All tests passed'));
  });

  test('macos pushFile copies between host paths', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.pushFile,
        parameters: <String, Object?>{
          'sourcePath': '/tmp/in.json',
          'destinationPath': '/tmp/out/in.json',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('cp -R'));
    expect(result.command, contains('/tmp/in.json'));
    expect(result.command, contains('/tmp/out/in.json'));
  });

  test('macos addMedia defaults to the host Downloads folder', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.addMedia,
        parameters: <String, Object?>{'sourcePath': '/tmp/photo.png'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('Downloads'));
  });

  test('macos readDeviceInfo reports host hardware details', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.readDeviceInfo,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('sw_vers'));
    expect(result.command.join(' '), contains('hw.model'));
  });

  test('linux readFocusState reads the active window via xdotool', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'linux',
        action: CockpitSystemControlAction.readFocusState,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('getactivewindow'));
  });

  test('linux readFocusState reports empty focus instead of failing', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'linux',
        action: CockpitSystemControlAction.readFocusState,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('state=no-active-window'));
    expect(result.command.join(' '), contains('exit 0'));
    expect(result.errorCode, isNull);
  });

  test('macos recoverToApp activates the target application', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        appId: 'dev.cockpit.example',
        processId: 4242,
        action: CockpitSystemControlAction.recoverToApp,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.first, 'osascript');
    expect(result.command, containsAllInOrder(<String>['processId', '4242']));
    expect(result.command, contains('JavaScript'));
    expect(result.command.join('\n'), contains('NSRunningApplication'));
    expect(result.command.join('\n'), isNot(contains('System Events')));
  });

  test('desktop dismissKeyboard reports unsupported truthfully', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.dismissKeyboard,
      ),
    );

    expect(result.success, isFalse);
    expect(result.availability, CockpitSystemControlAvailability.unsupported);
    expect(processManager.starts, isEmpty);
  });

  test('android readSystemLogs tails logcat scoped to the app', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.readSystemLogs,
        parameters: <String, Object?>{'lines': 80},
      ),
    );

    expect(result.success, isTrue);
    final script = result.command.last;
    expect(script, contains('logcat -d -v time -t 80'));
    expect(script, contains('pidof -s'));
    expect(script, contains('dev.cockpit.example'));
  });

  test('android setBattery simulates an unplugged low battery', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setBattery,
        parameters: <String, Object?>{'level': 7, 'plugged': false},
      ),
    );

    expect(result.success, isTrue);
    final script = result.command.last;
    expect(script, contains('dumpsys battery unplug'));
    expect(script, contains('dumpsys battery set level 7'));
  });

  test('android setBattery requires at least one parameter', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setBattery,
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'missingSystemActionParameter');
    expect(processManager.starts, isEmpty);
  });

  test('android setBattery reset restores real battery reporting', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setBattery,
        parameters: <String, Object?>{'reset': true},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.last, "'exec dumpsys battery reset'");
  });

  test('android readSystemLogs tails logcat without app scoping', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.readSystemLogs,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.last, "'exec logcat -d -v time -t 200'");
  });

  test('linux readSystemLogs reads a bounded journalctl tail', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'linux',
        action: CockpitSystemControlAction.readSystemLogs,
        parameters: <String, Object?>{'lines': 120},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.first, 'sh');
    expect(result.command, contains('120'));
    expect(result.command.join('\n'), contains('journalctl'));
  });

  test('windows readSystemLogs reads bounded application events', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'windows',
        action: CockpitSystemControlAction.readSystemLogs,
        parameters: <String, Object?>{'lines': 25},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.first, 'powershell');
    expect(
      _decodeWindowsPowershellScript(result.command),
      contains('Get-WinEvent -LogName Application -MaxEvents 25'),
    );
  });

  test('ios setStatusBar overrides simulator status bar values', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setStatusBar,
        parameters: <String, Object?>{
          'time': '9:41',
          'batteryState': 'charged',
          'batteryLevel': 100,
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'status_bar',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'override',
      '--time',
      '9:41',
      '--batteryState',
      'charged',
      '--batteryLevel',
      '100',
    ]);
  });

  test('android setConnectivity toggles wifi and airplane mode', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setConnectivity,
        parameters: <String, Object?>{'wifi': false, 'airplaneMode': true},
      ),
    );

    expect(result.success, isTrue);
    final script = result.command.last;
    expect(script, contains('cmd connectivity airplane-mode enable'));
    expect(script, contains('svc wifi disable'));
  });

  test('ios simulator readSystemLogs reads the unified log', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.readSystemLogs,
        parameters: <String, Object?>{
          'lastMinutes': 5,
          'processName': 'Runner',
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('log show'));
    expect(result.command.join(' '), contains('tail -n'));
    expect(result.command, contains('5m'));
    expect(result.command, contains('Runner'));
  });

  test('ios simulator setLocale writes locale and language', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setLocale,
        parameters: <String, Object?>{'locale': 'zh_CN'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('AppleLocale'));
    expect(result.command, contains('zh_CN'));
    expect(result.command, contains('zh-CN'));
    expect(result.limitations.join('\n'), contains('Relaunch the app'));
  });

  test('macos readSystemLogs reads the recent unified log', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.readSystemLogs,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.join(' '), contains('log show'));
    expect(result.command.join(' '), contains('tail -n'));
    expect(result.command, contains('2m'));
    expect(result.command, contains('200'));
  });

  test('android readFocusState reports windows and IME state', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.readFocusState,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command.take(5), <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'sh',
    ]);
    expect(result.command[5], '-c');
    expect(result.command[6], contains('dumpsys input_method'));
  });

  test('android setLocation sends emulator geo fix in lon lat order', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setLocation,
        parameters: <String, Object?>{
          'latitude': 37.3349,
          'longitude': -122.009,
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'emu',
      'geo',
      'fix',
      '-122.009',
      '37.3349',
    ]);
  });

  test('android setOrientation locks device rotation', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setOrientation,
        parameters: <String, Object?>{'orientation': 'landscape'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'sh',
      '-c',
      "'settings put system accelerometer_rotation 0 && settings put system user_rotation 1'",
    ]);
  });

  test('android setOrientation rejects undeclared sensor aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setOrientation,
        parameters: <String, Object?>{'orientation': 'sensor'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setOrientation rejects undeclared hyphen aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setOrientation,
        parameters: <String, Object?>{'orientation': 'reverse-portrait'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setNetworkSpeed uses the emulator console', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setNetworkSpeed,
        parameters: <String, Object?>{'networkSpeed': 'full'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'emu',
      'network',
      'speed',
      'full',
    ]);
  });

  test('android setNetworkSpeed rejects undeclared speed aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setNetworkSpeed,
        parameters: <String, Object?>{'speed': 'full'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android setNetworkDelay uses the emulator console', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setNetworkDelay,
        parameters: <String, Object?>{'networkDelay': 'none'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'emu',
      'network',
      'delay',
      'none',
    ]);
  });

  test('android setNetworkDelay rejects undeclared value aliases', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.setNetworkDelay,
        parameters: <String, Object?>{'value': 'none'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(processManager.starts, isEmpty);
  });

  test('android readProcessList uses adb ps', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.readProcessList,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'ps',
      '-A',
    ]);
  });

  test(
    'ios simulator activateWindow brings app forward without killing debug session',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.activateWindow,
        ),
      );

      expect(result.success, isTrue);
      expect(result.command, <String>[
        'xcrun',
        'simctl',
        'launch',
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        'dev.cockpit.example',
      ]);
    },
  );

  test('ios simulator grantPermission uses simctl privacy grant', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.grantPermission,
        parameters: <String, Object?>{'permission': 'photos'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.recommendedNextStep, 'relaunchAppThenReadState');
    expect(
      result.limitations,
      contains('simctl privacy may terminate the app'),
    );
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'privacy',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'grant',
      'photos',
      'dev.cockpit.example',
    ]);
  });

  test('ios simulator resetPermission resets app privacy', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.resetPermission,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'privacy',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'reset',
      'all',
      'dev.cockpit.example',
    ]);
  });

  test('ios simulator installApp uses simctl install', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.installApp,
        parameters: <String, Object?>{'appPath': '/tmp/Runner.app'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'install',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      '/tmp/Runner.app',
    ]);
  });

  test('ios simulator readSystemState lists device JSON', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.readSystemState,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'list',
      '-j',
      'devices',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
    ]);
  });

  test(
    'ios simulator readSystemState retries transient CoreSimulator timeouts',
    () async {
      final processManager = _TransientHangingProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          action: CockpitSystemControlAction.readSystemState,
          timeout: Duration(milliseconds: 1),
        ),
      );

      expect(result.success, isTrue);
      expect(result.errorCode, isNull);
      expect(processManager.starts, hasLength(2));
      expect(
        processManager.starts.map((start) => start.arguments).toList(),
        everyElement(<String>[
          'simctl',
          'list',
          '-j',
          'devices',
          '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        ]),
      );
    },
  );

  test('ios simulator setClipboard writes through simctl pbcopy', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setClipboard,
        parameters: <String, Object?>{'text': 'hello clipboard'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'sh',
      '-c',
      r'printf "%s" "$2" | xcrun simctl pbcopy "$1"',
      'flutter_cockpit_ios_clipboard',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'hello clipboard',
    ]);
  });

  test('ios simulator setClipboard retries transient simctl exit', () async {
    final processManager = _TransientFailingProcessManager(
      failures: const <_FakeProcessExit>[
        _FakeProcessExit(
          exitCode: 60,
          stderr: 'Pasteboard service is not ready yet.',
        ),
      ],
    );
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setClipboard,
        parameters: <String, Object?>{'text': 'hello clipboard'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.errorCode, isNull);
    expect(processManager.starts, hasLength(2));
    expect(
      processManager.starts.map((start) => start.arguments).toList(),
      everyElement(<String>[
        '-c',
        r'printf "%s" "$2" | xcrun simctl pbcopy "$1"',
        'flutter_cockpit_ios_clipboard',
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        'hello clipboard',
      ]),
    );
  });

  test('ios simulator getClipboard reads through simctl pbpaste', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.getClipboard,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'pbpaste',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
    ]);
  });

  test('ios simulator terminateApp uses simctl terminate', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.terminateApp,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'terminate',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'dev.cockpit.example',
    ]);
  });

  test('ios simulator setAppearance uses simctl ui appearance', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setAppearance,
        parameters: <String, Object?>{'appearance': 'dark'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'ui',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'appearance',
      'dark',
    ]);
  });

  test(
    'ios simulator setAppearance rejects undeclared night aliases',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          action: CockpitSystemControlAction.setAppearance,
          parameters: <String, Object?>{'appearance': 'night'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'invalidSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(processManager.starts, isEmpty);
    },
  );

  test('ios simulator setContentSize uses simctl ui content_size', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setContentSize,
        parameters: <String, Object?>{'contentSize': 'accessibility-large'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'ui',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'content_size',
      'accessibility-large',
    ]);
  });

  test('ios simulator setLocation uses simctl location set', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.setLocation,
        parameters: <String, Object?>{
          'latitude': 37.3349,
          'longitude': -122.009,
        },
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'location',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'set',
      '37.3349,-122.009',
    ]);
  });

  test('ios simulator openSystemSettings uses App-Prefs by default', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.openSystemSettings,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'openurl',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'App-Prefs:',
    ]);
  });

  test(
    'ios simulator postNotification pipes APNS payload to simctl push',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          appId: 'dev.cockpit.example',
          action: CockpitSystemControlAction.postNotification,
          parameters: <String, Object?>{
            'title': 'Download complete',
            'body': 'Model is ready',
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.command, <String>[
        'sh',
        '-c',
        r'printf "%s" "$3" | xcrun simctl push "$1" "$2" -',
        'flutter_cockpit_ios_push',
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        'dev.cockpit.example',
        '{"aps":{"alert":{"title":"Download complete","body":"Model is ready"}}}',
      ]);
    },
  );

  test(
    'ios simulator setStatusBar overrides deterministic status data',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          action: CockpitSystemControlAction.setStatusBar,
          parameters: <String, Object?>{
            'time': '09:41',
            'dataNetwork': 'wifi',
            'wifiMode': 'active',
            'wifiBars': 3,
            'batteryState': 'charged',
            'batteryLevel': 100,
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.command, <String>[
        'xcrun',
        'simctl',
        'status_bar',
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        'override',
        '--time',
        '09:41',
        '--dataNetwork',
        'wifi',
        '--wifiMode',
        'active',
        '--wifiBars',
        '3',
        '--batteryState',
        'charged',
        '--batteryLevel',
        '100',
      ]);
    },
  );

  test('ios simulator clearStatusBar clears status overrides', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.clearStatusBar,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'status_bar',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      'clear',
    ]);
  });

  test('ios simulator readProcessList uses simctl spawn /bin/ps', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        action: CockpitSystemControlAction.readProcessList,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'xcrun',
      'simctl',
      'spawn',
      '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      '/bin/ps',
      '-A',
    ]);
  });

  test(
    'ios simulator runShell uses a login-free shell for PATH commands',
    () async {
      final processManager = _FakeProcessManager();
      final service = CockpitSystemControlActionService(
        processManager: processManager,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          action: CockpitSystemControlAction.runShell,
          parameters: <String, Object?>{
            'command': <String>['echo', 'hello world'],
          },
        ),
      );

      expect(result.success, isTrue);
      expect(result.command, <String>[
        'xcrun',
        'simctl',
        'spawn',
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        '/bin/sh',
        '-lc',
        "'echo' 'hello world'",
      ]);
    },
  );

  test('macos setClipboard writes through pbcopy without app target', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.setClipboard,
        parameters: <String, Object?>{'text': 'hello clipboard'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>[
      'sh',
      '-c',
      r'printf "%s" "$1" | pbcopy',
      'flutter_cockpit_macos_clipboard',
      'hello clipboard',
    ]);
  });

  test('macos readUiTree uses bounded System Events tree dump', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.readUiTree,
        parameters: <String, Object?>{'maxDepth': 2, 'maxNodes': 20},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command[0], 'osascript');
    expect(
      result.command,
      containsAllInOrder(<String>['-l', 'JavaScript', '-e']),
    );
    expect(result.command.sublist(result.command.length - 4), <String>[
      'appId',
      'dev.cockpit.example',
      '2',
      '20',
    ]);
  });

  test('macos readProcessList uses ps', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.readProcessList,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, <String>['ps', '-axo', 'pid=,ppid=,comm=']);
  });

  test('macos readWindows uses a bounded System Events window list', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'macos',
        action: CockpitSystemControlAction.readWindows,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command[0], 'osascript');
    expect(
      result.command,
      containsAllInOrder(<String>['-l', 'JavaScript', '-e']),
    );
  });

  test('windows readUiTree uses bounded UI Automation tree dump', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'windows',
        processId: 4242,
        action: CockpitSystemControlAction.readUiTree,
        parameters: <String, Object?>{'maxDepth': 3, 'maxNodes': 30},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command[0], 'powershell');
    expect(result.command, contains('-NoProfile'));
    expect(result.command, contains('-NonInteractive'));
    final script = _decodeWindowsPowershellScript(result.command);
    expect(script, contains("} 'processId' '4242' '3' '30'"));
  });

  test('windows readWindows uses visible process windows', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'windows',
        action: CockpitSystemControlAction.readWindows,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command[0], 'powershell');
    expect(result.command, contains('-NoProfile'));
    expect(result.command, contains('-NonInteractive'));
    expect(
      _decodeWindowsPowershellScript(result.command),
      contains('MainWindowTitle'),
    );
  });

  test('linux pressKey targets a window with xdotool key', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'linux',
        appId: 'dev.cockpit.example',
        action: CockpitSystemControlAction.pressKey,
        parameters: <String, Object?>{'key': 'Escape'},
      ),
    );

    expect(result.success, isTrue);
    expect(result.command, hasLength(12));
    expect(result.command[0], 'sh');
    expect(result.command[1], '-c');
    expect(
      result.command[2],
      contains(r'xdotool windowactivate --sync "$window_id"'),
    );
    expect(
      result.command[2],
      contains(r'xdotool windowfocus --sync "$window_id"'),
    );
    expect(result.command[2], contains(r'exec xdotool "$@"'));
    expect(result.command.sublist(3), <String>[
      'flutter_cockpit_linux_input',
      'appId',
      'dev.cockpit.example',
      'key',
      '--repeat',
      '1',
      '--delay',
      '0',
      'Escape',
    ]);
  });

  test('linux readWindows uses wmctrl or xdotool fallback', () async {
    final processManager = _FakeProcessManager();
    final service = CockpitSystemControlActionService(
      processManager: processManager,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'linux',
        action: CockpitSystemControlAction.readWindows,
      ),
    );

    expect(result.success, isTrue);
    expect(result.command[0], 'sh');
    expect(result.command[1], '-c');
    expect(result.command[2], contains('wmctrl -lp'));
    expect(result.command[2], contains('xdotool search --onlyvisible'));
  });

  test('timed out command returns structured action failure', () async {
    final service = _actionServiceWithReachableAndroid(
      processManager: _HangingProcessManager(),
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.tap,
        parameters: <String, Object?>{'x': 42, 'y': 88},
        timeout: Duration(milliseconds: 1),
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'systemActionTimedOut');
    expect(result.recommendedNextStep, 'inspectShellFailure');
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'tap',
      '42',
      '88',
    ]);
  });

  test('process startup failure returns structured action failure', () async {
    final service = _actionServiceWithReachableAndroid(
      processManager: _ThrowingProcessManager(),
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.pressBack,
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'systemActionProcessFailed');
    expect(result.recommendedNextStep, 'inspectShellFailure');
    expect(result.errorMessage, contains('Unable to start process'));
    expect(result.command, <String>[
      'adb',
      '-s',
      'emulator-5554',
      'shell',
      'input',
      'keyevent',
      'KEYCODE_BACK',
    ]);
  });

  test(
    'captureScreenshot copies adapter artifact to requested output path',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_system_capture_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File('${tempDir.path}/source.png');
      await sourceFile.writeAsBytes(<int>[137, 80, 78, 71]);
      final outputFile = File('${tempDir.path}/copied.png');
      final processManager = _FakeProcessManager();
      final captureAdapter = _FakeCaptureAdapter(sourceFile);
      final service = _actionServiceWithReachableAndroid(
        processManager: processManager,
        captureAdapterFactory: (_) => captureAdapter,
      );

      final result = await service.run(
        CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.captureScreenshot,
          parameters: <String, Object?>{
            'name': 'acceptance',
            'outputPath': outputFile.path,
          },
          timeout: const Duration(seconds: 37),
        ),
      );

      expect(result.success, isTrue);
      expect(result.sourceFilePath, outputFile.path);
      expect(result.artifact?['relativePath'], 'screenshots/acceptance.png');
      expect(await outputFile.readAsBytes(), <int>[137, 80, 78, 71]);
      expect(captureAdapter.command?.timeoutMs, 37000);
      expect(processManager.starts, isEmpty);
    },
  );

  test(
    'captureScreenshot rejects non-string name before adapter capture',
    () async {
      final captureAdapter = _CountingCaptureAdapter();
      final service = _actionServiceWithReachableAndroid(
        captureAdapterFactory: (_) => captureAdapter,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.captureScreenshot,
          parameters: <String, Object?>{'name': 123},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'invalidSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(captureAdapter.captureCalls, 0);
    },
  );

  test(
    'captureScreenshot rejects non-string outputPath before adapter capture',
    () async {
      final captureAdapter = _CountingCaptureAdapter();
      final service = _actionServiceWithReachableAndroid(
        captureAdapterFactory: (_) => captureAdapter,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.captureScreenshot,
          parameters: <String, Object?>{
            'outputPath': <String>['out.png'],
          },
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'invalidSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(captureAdapter.captureCalls, 0);
    },
  );

  test('captureScreenshot adapter failure returns structured result', () async {
    final service = _actionServiceWithReachableAndroid(
      captureAdapterFactory: (_) => const _FailingCaptureAdapter(),
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.captureScreenshot,
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'systemCaptureFailed');
    expect(result.recommendedNextStep, 'inspectCaptureFailure');
    expect(result.errorMessage, contains('capture permission denied'));
    expect(result.errorDetails, isEmpty);
  });

  test('captureScreenshot preserves adapter failure diagnostics', () async {
    final service = _actionServiceWithReachableAndroid(
      captureAdapterFactory: (_) => const _DetailedFailingCaptureAdapter(),
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.captureScreenshot,
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorDetails['driverError'], <String, Object?>{
      'code': 'captureFailed',
      'message': 'capture permission denied',
      'details': <String, Object?>{
        'permission': 'screenRecording',
        'stderr': 'could not create image from display',
      },
    });
    expect(result.toJson()['errorDetails'], result.errorDetails);
  });

  test(
    'captureScreenshot fails when an adapter reports success without a source file',
    () async {
      final service = _actionServiceWithReachableAndroid(
        captureAdapterFactory: (_) => const _MissingArtifactCaptureAdapter(),
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.captureScreenshot,
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'systemCaptureMissingArtifact');
      expect(result.recommendedNextStep, 'inspectCaptureFailure');
    },
  );

  test(
    'startRecording starts adapter session without spawning process',
    () async {
      final processManager = _FakeProcessManager();
      final recordingAdapter = _FakeRecordingAdapter();
      final service = _actionServiceWithReachableAndroid(
        processManager: processManager,
        recordingAdapterFactory: (_) => recordingAdapter,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.startRecording,
          parameters: <String, Object?>{'name': 'flow', 'purpose': 'repro'},
        ),
      );

      expect(result.success, isTrue);
      expect(result.recommendedNextStep, 'runFlowThenStopRecording');
      expect(result.recordingSession?['state'], 'recording');
      expect(recordingAdapter.startedRequest?.name, 'flow');
      expect(
        recordingAdapter.startedRequest?.purpose,
        CockpitRecordingPurpose.repro,
      );
      expect(processManager.starts, isEmpty);
    },
  );

  test('startRecording rejects non-string name before adapter start', () async {
    final recordingAdapter = _FakeRecordingAdapter();
    final service = _actionServiceWithReachableAndroid(
      recordingAdapterFactory: (_) => recordingAdapter,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.startRecording,
        parameters: <String, Object?>{'name': 123},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(recordingAdapter.startedRequest, isNull);
  });

  test('startRecording rejects unsupported recording mode', () async {
    final recordingAdapter = _FakeRecordingAdapter();
    final service = _actionServiceWithReachableAndroid(
      recordingAdapterFactory: (_) => recordingAdapter,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.startRecording,
        parameters: <String, Object?>{'mode': 'cinematic'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(recordingAdapter.startedRequest, isNull);
  });

  test('startRecording rejects purpose aliases outside metadata', () async {
    final recordingAdapter = _FakeRecordingAdapter();
    final service = _actionServiceWithReachableAndroid(
      recordingAdapterFactory: (_) => recordingAdapter,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.startRecording,
        parameters: <String, Object?>{'purpose': 'debug'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(recordingAdapter.startedRequest, isNull);
  });

  test('startRecording rejects layer aliases outside metadata', () async {
    final recordingAdapter = _FakeRecordingAdapter();
    final service = _actionServiceWithReachableAndroid(
      recordingAdapterFactory: (_) => recordingAdapter,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.startRecording,
        parameters: <String, Object?>{'layer': 'appWindow'},
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'invalidSystemActionParameter');
    expect(result.recommendedNextStep, 'fixActionPayload');
    expect(recordingAdapter.startedRequest, isNull);
  });

  test('stopRecording returns completed adapter artifact', () async {
    final processManager = _FakeProcessManager();
    final recordingAdapter = _FakeRecordingAdapter();
    final service = _actionServiceWithReachableAndroid(
      processManager: processManager,
      recordingAdapterFactory: (_) => recordingAdapter,
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.stopRecording,
      ),
    );

    expect(result.success, isTrue);
    expect(result.sourceFilePath, '/tmp/system-recording.mp4');
    expect(result.artifact?['relativePath'], 'recordings/system-recording.mp4');
    expect(result.recordingResult?['state'], 'completed');
    expect(processManager.starts, isEmpty);
  });

  test(
    'stopRecording rejects non-string outputPath before adapter stop',
    () async {
      final recordingAdapter = _FakeRecordingAdapter();
      final service = _actionServiceWithReachableAndroid(
        recordingAdapterFactory: (_) => recordingAdapter,
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.stopRecording,
          parameters: <String, Object?>{'outputPath': 42},
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'invalidSystemActionParameter');
      expect(result.recommendedNextStep, 'fixActionPayload');
      expect(recordingAdapter.stopCalls, 0);
    },
  );

  test(
    'stopRecording copies completed video to requested output path',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_system_recording_output_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File('${tempDir.path}/source.mp4');
      await sourceFile.writeAsBytes(<int>[0, 0, 0, 24, 102, 116, 121, 112]);
      final outputFile = File('${tempDir.path}/copied.mp4');
      final service = _actionServiceWithReachableAndroid(
        recordingAdapterFactory: (_) =>
            _FakeRecordingAdapter(sourceFilePath: sourceFile.path),
      );

      final result = await service.run(
        CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.stopRecording,
          parameters: <String, Object?>{'outputPath': outputFile.path},
        ),
      );

      expect(result.success, isTrue);
      expect(result.sourceFilePath, outputFile.path);
      expect(result.recordingResult?['sourceFilePath'], outputFile.path);
      expect(await outputFile.readAsBytes(), <int>[
        0,
        0,
        0,
        24,
        102,
        116,
        121,
        112,
      ]);
    },
  );

  test(
    'stopRecording accepts an output path that already is the source path',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_system_recording_same_output_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File('${tempDir.path}/source.mp4');
      await sourceFile.writeAsBytes(<int>[0, 0, 0, 24, 102, 116, 116, 121]);
      final service = _actionServiceWithReachableAndroid(
        recordingAdapterFactory: (_) =>
            _FakeRecordingAdapter(sourceFilePath: sourceFile.path),
      );

      final result = await service.run(
        CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.stopRecording,
          parameters: <String, Object?>{'outputPath': sourceFile.path},
        ),
      );

      expect(result.success, isTrue);
      expect(result.sourceFilePath, sourceFile.path);
      expect(await sourceFile.readAsBytes(), <int>[
        0,
        0,
        0,
        24,
        102,
        116,
        116,
        121,
      ]);
    },
  );

  test(
    'stopRecording fails when an adapter reports completion without a source file',
    () async {
      final service = _actionServiceWithReachableAndroid(
        recordingAdapterFactory: (_) =>
            _FakeRecordingAdapter(sourceFilePath: null),
      );

      final result = await service.run(
        const CockpitSystemControlActionRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
          action: CockpitSystemControlAction.stopRecording,
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'systemRecordingMissingArtifact');
      expect(result.recommendedNextStep, 'inspectRecordingFailure');
      expect(result.recordingResult?['state'], 'completed');
    },
  );

  test('stopRecording adapter failure returns structured result', () async {
    final service = _actionServiceWithReachableAndroid(
      recordingAdapterFactory: (_) => const _FailingRecordingAdapter(),
    );

    final result = await service.run(
      const CockpitSystemControlActionRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
        action: CockpitSystemControlAction.stopRecording,
      ),
    );

    expect(result.success, isFalse);
    expect(result.errorCode, 'systemRecordingFailed');
    expect(result.recommendedNextStep, 'inspectRecordingFailure');
    expect(result.errorMessage, contains('No active recording session'));
  });
}

CockpitSystemControlActionService _actionServiceWithReachableAndroid({
  CockpitProcessManager? processManager,
  CockpitSystemControlCaptureAdapterFactory? captureAdapterFactory,
  CockpitSystemControlRecordingAdapterFactory? recordingAdapterFactory,
}) {
  return CockpitSystemControlActionService(
    processManager: processManager,
    systemControlService: CockpitSystemControlService(
      processManager: processManager,
      androidDeviceStateProbe: (_, {required timeout}) async {
        return const CockpitAndroidDeviceProbeResult.reachable('device');
      },
    ),
    captureAdapterFactory: captureAdapterFactory,
    recordingAdapterFactory: recordingAdapterFactory,
  );
}

final class _CountingCaptureAdapter implements CockpitCaptureAdapter {
  int captureCalls = 0;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) {
    captureCalls += 1;
    throw StateError('Capture should not be called for invalid payload.');
  }
}

final class _FakeCaptureAdapter implements CockpitCaptureAdapter {
  _FakeCaptureAdapter(this.sourceFile);

  final File sourceFile;
  CockpitCommand? command;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    this.command = command;
    final request = command.screenshotRequest!;
    final artifact = CockpitArtifactRef(
      role: 'screenshot',
      relativePath: 'screenshots/${request.name}.png',
    );
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 12,
        artifacts: <CockpitArtifactRef>[artifact],
      ),
      artifactSourcePaths: <String, String>{
        artifact.relativePath: sourceFile.path,
      },
    );
  }
}

final class _FailingCaptureAdapter implements CockpitCaptureAdapter {
  const _FailingCaptureAdapter();

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) {
    throw StateError('capture permission denied');
  }
}

final class _DetailedFailingCaptureAdapter implements CockpitCaptureAdapter {
  const _DetailedFailingCaptureAdapter();

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: false,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 1,
        error: CockpitCommandError.captureFailed(
          message: 'capture permission denied',
          details: const <String, Object?>{
            'permission': 'screenRecording',
            'stderr': 'could not create image from display',
          },
        ),
      ),
    );
  }
}

final class _MissingArtifactCaptureAdapter implements CockpitCaptureAdapter {
  const _MissingArtifactCaptureAdapter();

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 12,
      ),
    );
  }
}

final class _FakeRecordingAdapter implements CockpitRecordingAdapter {
  _FakeRecordingAdapter({this.sourceFilePath = '/tmp/system-recording.mp4'});

  final String? sourceFilePath;
  CockpitRecordingRequest? startedRequest;
  int stopCalls = 0;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    startedRequest = request;
    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    stopCalls += 1;
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: CockpitRecordingPurpose.acceptance,
      recordingKind: CockpitRecordingKind.nativeScreen,
      effectiveLayer: CockpitRecordingLayer.system,
      artifact: const CockpitArtifactRef(
        role: 'recording',
        relativePath: 'recordings/system-recording.mp4',
      ),
      durationMs: 1200,
      sourceFilePath: sourceFilePath,
    );
  }
}

final class _FailingRecordingAdapter implements CockpitRecordingAdapter {
  const _FailingRecordingAdapter();

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) {
    throw StateError('Recording could not start.');
  }

  @override
  Future<CockpitRecordingResult> stopRecording() {
    throw StateError('No active recording session exists.');
  }
}

final class _FakeAndroidUiAutomation implements CockpitAndroidUiAutomation {
  _FakeAndroidUiAutomation({this.dialogError});

  final Object? dialogError;
  String? lastAction;
  String? deviceId;
  String? decision;
  String? text;
  int? maxDepth;
  int? maxNodes;

  @override
  Future<String> dismissSystemDialog({
    required String deviceId,
    required String decision,
    required Duration timeout,
  }) async {
    lastAction = 'dismissSystemDialog';
    this.deviceId = deviceId;
    this.decision = decision;
    final error = dialogError;
    if (error != null) throw error;
    return 'dismissSystemDialog decision=$decision handled=true';
  }

  @override
  Future<String> readUiTree({
    required String deviceId,
    required int maxDepth,
    required int maxNodes,
    required Duration timeout,
  }) async {
    lastAction = 'readUiTree';
    this.deviceId = deviceId;
    this.maxDepth = maxDepth;
    this.maxNodes = maxNodes;
    return '<?xml version="1.0"?><hierarchy />';
  }

  @override
  Future<String> tapNotification({
    required String deviceId,
    required String text,
    required Duration timeout,
  }) async {
    lastAction = 'tapNotification';
    this.deviceId = deviceId;
    this.text = text;
    return 'tapNotification text=$text handled=true';
  }
}

final class _FakeProcessManager implements CockpitProcessManager {
  final starts = <_StartedProcess>[];

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
  }) {
    if (executable == 'adb' &&
        arguments.length == 3 &&
        arguments[0] == '-s' &&
        arguments[2] == 'get-state') {
      return Future<ProcessResult>.value(ProcessResult(0, 0, 'device\n', ''));
    }
    throw UnimplementedError(
      'Unexpected run: $executable ${arguments.join(' ')}',
    );
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
    starts.add(
      _StartedProcess(
        executable: executable,
        arguments: List<String>.unmodifiable(arguments),
      ),
    );
    return _FakeManagedProcess();
  }
}

final class _StartedProcess {
  const _StartedProcess({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}

final class _HangingProcessManager implements CockpitProcessManager {
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
  }) {
    throw UnimplementedError();
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
    return _HangingManagedProcess();
  }
}

final class _TransientHangingProcessManager implements CockpitProcessManager {
  final starts = <_StartedProcess>[];

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
  }) {
    throw UnimplementedError();
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
    starts.add(
      _StartedProcess(
        executable: executable,
        arguments: List<String>.unmodifiable(arguments),
      ),
    );
    return starts.length == 1
        ? _HangingManagedProcess()
        : _FakeManagedProcess();
  }
}

final class _TransientFailingProcessManager implements CockpitProcessManager {
  _TransientFailingProcessManager({required List<_FakeProcessExit> failures})
    : _failures = List<_FakeProcessExit>.of(failures);

  final List<_FakeProcessExit> _failures;
  final starts = <_StartedProcess>[];

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
  }) {
    throw UnimplementedError();
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
    starts.add(
      _StartedProcess(
        executable: executable,
        arguments: List<String>.unmodifiable(arguments),
      ),
    );
    if (_failures.isEmpty) {
      return _FakeManagedProcess();
    }
    return _FakeManagedProcess(exit: _failures.removeAt(0));
  }
}

final class _FakeProcessExit {
  const _FakeProcessExit({required this.exitCode, this.stderr = ''});

  final int exitCode;
  final String stderr;
}

final class _ThrowingProcessManager implements CockpitProcessManager {
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw ProcessException(executable, arguments, 'Unable to start process');
  }
}

final class _FakeManagedProcess implements Process {
  _FakeManagedProcess({
    _FakeProcessExit exit = const _FakeProcessExit(exitCode: 0),
  }) : _exit = exit;

  final _FakeProcessExit _exit;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => _streamText(_exit.stderr);

  @override
  Future<int> get exitCode async => _exit.exitCode;

  @override
  int get pid => 1234;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _stdinController.close();
    return true;
  }
}

Stream<List<int>> _streamText(String text) {
  if (text.isEmpty) {
    return const Stream<List<int>>.empty();
  }
  return Stream<List<int>>.value(utf8.encode(text));
}

/// Windows scripts travel as -EncodedCommand (base64 UTF-16LE) so positional
/// values stay inert; tests assert against the decoded body.
String _decodeWindowsPowershellScript(List<String> command) {
  final encodedIndex = command.indexOf('-EncodedCommand');
  expect(encodedIndex, isNot(-1), reason: 'expected -EncodedCommand');
  final bytes = base64.decode(command[encodedIndex + 1]);
  return String.fromCharCodes(<int>[
    for (var index = 0; index < bytes.length; index += 2)
      bytes[index] | (bytes[index + 1] << 8),
  ]);
}

final class _HangingManagedProcess implements Process {
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 5678;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(-9);
    }
    _stdinController.close();
    return true;
  }
}
