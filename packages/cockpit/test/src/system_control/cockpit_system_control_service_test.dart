import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_adapter.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_service.dart';
import 'package:test/test.dart';

void main() {
  test('android profile reports executable adb system controls', () async {
    final service = _serviceWithReachableAndroid();

    final result = await service.describe(
      const CockpitSystemControlDescribeRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
      ),
    );

    expect(result.profile.platform, 'android');
    expect(result.profile.adapter, 'android.adb');
    expect(
      result.profile.preferredPlane,
      CockpitPlaneKind.flutterSemanticPlane,
    );
    expect(result.profile.fallbackOrder, <CockpitPlaneKind>[
      CockpitPlaneKind.flutterSemanticPlane,
      CockpitPlaneKind.nativeUiPlane,
      CockpitPlaneKind.deviceSystemPlane,
    ]);
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.tap),
    );
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.pressKey),
    );
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.terminateApp),
    );
    expect(
      result.profile.availableActions,
      containsAll(<CockpitSystemControlAction>[
        CockpitSystemControlAction.setAppearance,
        CockpitSystemControlAction.setContentSize,
        CockpitSystemControlAction.setLocation,
        CockpitSystemControlAction.setOrientation,
        CockpitSystemControlAction.setNetworkSpeed,
        CockpitSystemControlAction.setNetworkDelay,
        CockpitSystemControlAction.pressVolumeUp,
        CockpitSystemControlAction.dismissKeyboard,
        CockpitSystemControlAction.expandNotifications,
        CockpitSystemControlAction.expandQuickSettings,
        CockpitSystemControlAction.collapseSystemUi,
        CockpitSystemControlAction.postNotification,
        CockpitSystemControlAction.clearNotifications,
        CockpitSystemControlAction.readProcessList,
      ]),
    );
    expect(
      result.profile.availableActions.map((action) => action.name),
      containsAll(<String>[
        'tapNotification',
        'recoverToApp',
        'resolveBlockers',
        'readFocusState',
        'preparePermissions',
        'stabilizeForScreenshot',
      ]),
    );
    expect(
      result.profile
          .capabilityFor(CockpitSystemControlAction.preparePermissions)
          ?.effectiveGroups,
      contains('permissions'),
    );
    expect(
      result.profile
          .capabilityFor(CockpitSystemControlAction.stabilizeForScreenshot)
          ?.effectiveGroups,
      containsAll(<String>['systemUi', 'navigation']),
    );
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.captureScreenshot),
    );
    expect(
      result.profile.blockedActions,
      containsAll(<CockpitSystemControlAction>[
        CockpitSystemControlAction.setClipboard,
        CockpitSystemControlAction.getClipboard,
      ]),
    );
    expect(
      result.profile
          .capabilityFor(CockpitSystemControlAction.startRecording)
          ?.strategy,
      'adb.shell.screenrecord',
    );
    expect(result.recommendedNextStep, 'preferFlutterSemanticPlane');
  });

  test('android profile blocks device actions without a device id', () async {
    final service = CockpitSystemControlService();

    final result = await service.describe(
      const CockpitSystemControlDescribeRequest(platform: 'android'),
    );

    expect(
      result.profile.availableActions,
      isNot(contains(CockpitSystemControlAction.tap)),
    );
    expect(
      result.profile.blockedActions,
      contains(CockpitSystemControlAction.tap),
    );
    expect(
      result.profile
          .capabilityFor(CockpitSystemControlAction.captureScreenshot)
          ?.availability,
      CockpitSystemControlAvailability.blocked,
    );
    expect(
      result.profile.capabilityFor(CockpitSystemControlAction.tap)?.requires,
      contains('device id'),
    );
  });

  test(
    'android profile blocks device actions when adb reports offline',
    () async {
      final service = CockpitSystemControlService(
        androidDeviceStateProbe: (_, {required timeout}) async {
          return const CockpitAndroidDeviceProbeResult.blocked(
            state: 'offline',
            failureReason: 'device offline',
          );
        },
      );

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );

      expect(
        result.profile.blockedActions,
        contains(CockpitSystemControlAction.tap),
      );
      expect(
        result.profile.availableActions,
        isNot(contains(CockpitSystemControlAction.tap)),
      );
      expect(result.metadata['androidDeviceReachable'], isFalse);
      expect(
        result.profile.capabilityFor(CockpitSystemControlAction.tap)?.requires,
        containsAll(<String>[
          'reachable adb device',
          'adb get-state=device (current: offline)',
          'device offline',
        ]),
      );
    },
  );

  test('android device probe decodes byte stderr from adb failures', () async {
    final probe = await cockpitProbeAndroidDeviceState(
      _AdbByteStderrProcessManager(),
      'emulator-5554',
      timeout: const Duration(seconds: 1),
    );

    expect(probe.reachable, isFalse);
    expect(probe.state, isNull);
    expect(probe.failureReason, "error: device 'emulator-5554' not found");
  });

  test('ios physical profile reports WDA and devicectl capabilities', () async {
    final service = CockpitSystemControlService();

    final result = await service.describe(
      const CockpitSystemControlDescribeRequest(
        platform: 'ios',
        deviceId: '00008110-001234',
      ),
    );

    expect(result.profile.adapter, 'ios.physical+wda+devicectl');
    expect(
      result.profile.availableActions,
      isNot(contains(CockpitSystemControlAction.tap)),
    );
    expect(
      result.profile.blockedActions,
      contains(CockpitSystemControlAction.tap),
    );
    final tap = result.profile.capabilityFor(CockpitSystemControlAction.tap);
    expect(tap?.availability, CockpitSystemControlAvailability.blocked);
    expect(
      tap?.requires,
      contains(contains('reachable WebDriverAgent endpoint')),
    );
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.installApp),
    );
    expect(result.recommendedNextStep, 'startWebDriverAgent');
  });

  test('ios simulator profile exposes real simctl system controls', () async {
    final service = CockpitSystemControlService();

    final result = await service.describe(
      const CockpitSystemControlDescribeRequest(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
      ),
    );

    expect(result.profile.adapter, 'ios.simctl+xctest');
    expect(
      result.profile
          .capabilityFor(CockpitSystemControlAction.activateWindow)
          ?.limitations,
      contains(
        'Brings the app to the foreground without terminating an existing debug or hot-reload session.',
      ),
    );
    expect(
      result.profile.availableActions,
      containsAll(<CockpitSystemControlAction>[
        CockpitSystemControlAction.activateWindow,
        CockpitSystemControlAction.grantPermission,
        CockpitSystemControlAction.openUrl,
        CockpitSystemControlAction.openSystemSettings,
        CockpitSystemControlAction.setAppearance,
        CockpitSystemControlAction.setContentSize,
        CockpitSystemControlAction.setLocation,
        CockpitSystemControlAction.setStatusBar,
        CockpitSystemControlAction.clearStatusBar,
        CockpitSystemControlAction.postNotification,
        CockpitSystemControlAction.setClipboard,
        CockpitSystemControlAction.getClipboard,
        CockpitSystemControlAction.terminateApp,
        CockpitSystemControlAction.captureScreenshot,
        CockpitSystemControlAction.startRecording,
        CockpitSystemControlAction.stopRecording,
        CockpitSystemControlAction.readProcessList,
        CockpitSystemControlAction.readSystemState,
        CockpitSystemControlAction.runShell,
      ]),
    );
    expect(
      result.profile.blockedActions,
      containsAll(<CockpitSystemControlAction>[
        CockpitSystemControlAction.tap,
        CockpitSystemControlAction.pressHome,
        CockpitSystemControlAction.typeText,
        CockpitSystemControlAction.pressKey,
        CockpitSystemControlAction.setOrientation,
        CockpitSystemControlAction.setNetworkSpeed,
        CockpitSystemControlAction.setNetworkDelay,
        CockpitSystemControlAction.dismissSystemDialog,
        CockpitSystemControlAction.dismissKeyboard,
        CockpitSystemControlAction.expandNotifications,
        CockpitSystemControlAction.expandQuickSettings,
        CockpitSystemControlAction.collapseSystemUi,
        CockpitSystemControlAction.readUiTree,
      ]),
    );
    expect(
      result.profile.unsupportedActions,
      containsAll(<CockpitSystemControlAction>[
        CockpitSystemControlAction.pressBack,
        CockpitSystemControlAction.pressVolumeUp,
        CockpitSystemControlAction.pressVolumeDown,
        CockpitSystemControlAction.pressVolumeMute,
        CockpitSystemControlAction.clearNotifications,
      ]),
    );
  });

  test('ios booted simulator alias exposes simctl controls', () async {
    final service = CockpitSystemControlService();

    final result = await service.describe(
      const CockpitSystemControlDescribeRequest(
        platform: 'ios',
        deviceId: 'booted',
      ),
    );

    expect(result.profile.adapter, 'ios.simctl+xctest');
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.openUrl),
    );
    expect(
      result.profile.availableActions,
      contains(CockpitSystemControlAction.readSystemState),
    );
  });

  test(
    'ios simulator profile enables native actions when a WebDriverAgent endpoint is supplied',
    () async {
      final service = CockpitSystemControlService(
        iosWdaEndpointProbe: (_, {required timeout}) async => true,
      );

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          metadata: <String, Object?>{'wdaUrl': 'http://127.0.0.1:8100'},
        ),
      );

      expect(
        result.profile.availableActions,
        containsAll(<CockpitSystemControlAction>[
          CockpitSystemControlAction.tap,
          CockpitSystemControlAction.drag,
          CockpitSystemControlAction.typeText,
          CockpitSystemControlAction.pressKey,
          CockpitSystemControlAction.pressHome,
          CockpitSystemControlAction.dismissSystemDialog,
          CockpitSystemControlAction.dismissKeyboard,
          CockpitSystemControlAction.expandNotifications,
          CockpitSystemControlAction.expandQuickSettings,
          CockpitSystemControlAction.collapseSystemUi,
          CockpitSystemControlAction.setOrientation,
          CockpitSystemControlAction.readUiTree,
        ]),
      );
      expect(
        result.profile.availableActions.map((action) => action.name),
        containsAll(<String>[
          'tapNotification',
          'recoverToApp',
          'resolveBlockers',
          'readFocusState',
          'preparePermissions',
          'stabilizeForScreenshot',
        ]),
      );
      expect(
        result.profile.capabilityFor(CockpitSystemControlAction.tap)?.strategy,
        'webdriveragent.w3c.actions.tap',
      );
    },
  );

  test(
    'ios simulator keeps native actions blocked when WebDriverAgent is unreachable',
    () async {
      final service = CockpitSystemControlService(
        iosWdaEndpointProbe: (_, {required timeout}) async => false,
      );

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          metadata: <String, Object?>{'wdaUrl': 'http://127.0.0.1:8100'},
        ),
      );

      expect(
        result.profile.blockedActions,
        contains(CockpitSystemControlAction.tap),
      );
      expect(
        result.profile.capabilityFor(CockpitSystemControlAction.tap)?.requires,
        contains('reachable WebDriverAgent endpoint'),
      );
    },
  );

  test(
    'android readFocusState is advertised as a parameterless inspection action',
    () async {
      final service = _serviceWithReachableAndroid();

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'android',
          deviceId: 'emulator-5554',
        ),
      );

      final capability = result.profile.capabilityFor(
        CockpitSystemControlAction.readFocusState,
      );
      expect(
        capability?.availability,
        CockpitSystemControlAvailability.available,
      );
      expect(capability?.groups, isEmpty);
      expect(capability?.effectiveGroups, contains('inspection'));
      expect(capability?.parameters, isEmpty);
    },
  );

  test(
    'ios simulator readFocusState is advertised as a parameterless inspection action',
    () async {
      final service = CockpitSystemControlService(
        iosWdaEndpointProbe: (_, {required timeout}) async => true,
      );

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
          metadata: <String, Object?>{'wdaUrl': 'http://127.0.0.1:8100'},
        ),
      );

      final capability = result.profile.capabilityFor(
        CockpitSystemControlAction.readFocusState,
      );
      expect(
        capability?.availability,
        CockpitSystemControlAvailability.available,
      );
      expect(capability?.effectiveGroups, contains('inspection'));
      expect(capability?.parameters, isEmpty);
    },
  );

  test(
    'ios simulator auto-discovers a reachable local WebDriverAgent endpoint',
    () async {
      final probedUris = <Uri>[];
      final service = CockpitSystemControlService(
        iosWdaEndpointProbe: (uri, {required timeout}) async {
          probedUris.add(uri);
          return uri == Uri.parse('http://127.0.0.1:8100');
        },
      );

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'ios',
          deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        ),
      );

      expect(probedUris, contains(Uri.parse('http://127.0.0.1:8100')));
      expect(
        result.profile.availableActions,
        contains(CockpitSystemControlAction.dismissSystemDialog),
      );
      expect(
        result.profile.capabilityFor(CockpitSystemControlAction.tap)?.requires,
        contains('WebDriverAgent endpoint'),
      );
    },
  );

  test('WebDriverAgent auto-discovery only runs for iOS', () async {
    var probeCount = 0;
    final service = CockpitSystemControlService(
      androidDeviceStateProbe: (_, {required timeout}) async {
        return const CockpitAndroidDeviceProbeResult.reachable('device');
      },
      iosWdaEndpointProbe: (_, {required timeout}) async {
        probeCount += 1;
        return true;
      },
    );

    await service.describe(
      const CockpitSystemControlDescribeRequest(
        platform: 'android',
        deviceId: 'emulator-5554',
      ),
    );

    expect(probeCount, 0);
  });

  test('unknown platform reports unsupported capability profile', () async {
    final service = CockpitSystemControlService();

    final result = await service.describe(
      const CockpitSystemControlDescribeRequest(platform: 'freebsd'),
    );

    expect(result.profile.platform, 'freebsd');
    expect(result.profile.adapter, 'unsupported');
    expect(
      result.profile.unsupportedActions,
      contains(CockpitSystemControlAction.tap),
    );
    expect(result.recommendedNextStep, 'useFlutterOrHostFallback');
  });

  test(
    'web profile blocks browser bridge actions until bridge is wired',
    () async {
      final service = CockpitSystemControlService();

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'web',
          deviceId: 'chrome',
        ),
      );

      expect(result.profile.adapter, 'browser.dom+host-recording');
      expect(result.profile.availableActions, isEmpty);
      expect(
        result.profile.blockedActions,
        containsAll(<CockpitSystemControlAction>[
          CockpitSystemControlAction.tap,
          CockpitSystemControlAction.typeText,
          CockpitSystemControlAction.captureScreenshot,
          CockpitSystemControlAction.startRecording,
          CockpitSystemControlAction.stopRecording,
        ]),
      );
      expect(
        result.profile.capabilityFor(CockpitSystemControlAction.tap)?.requires,
        contains('browser driver or bridge'),
      );
      expect(
        result.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        contains('app id or process id'),
      );
    },
  );

  test(
    'web profile enables host-window evidence with a browser window target',
    () async {
      final service = CockpitSystemControlService();

      final result = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'web',
          deviceId: 'chrome',
          appId: 'com.google.Chrome',
        ),
      );

      expect(
        result.profile.availableActions,
        containsAll(<CockpitSystemControlAction>[
          CockpitSystemControlAction.captureScreenshot,
          CockpitSystemControlAction.startRecording,
          CockpitSystemControlAction.stopRecording,
        ]),
      );
      expect(
        result.profile
            .capabilityFor(CockpitSystemControlAction.startRecording)
            ?.strategy,
        'browser.host-window-recording',
      );
      expect(
        result.profile.blockedActions,
        contains(CockpitSystemControlAction.tap),
      );
    },
  );

  test(
    'desktop profile enables evidence actions only with window target',
    () async {
      final service = CockpitSystemControlService();

      final withoutTarget = await service.describe(
        const CockpitSystemControlDescribeRequest(platform: 'macos'),
      );
      expect(
        withoutTarget.profile.availableActions,
        contains(CockpitSystemControlAction.tap),
      );
      expect(
        withoutTarget.profile.blockedActions,
        contains(CockpitSystemControlAction.typeText),
      );
      expect(
        withoutTarget.profile.blockedActions,
        contains(CockpitSystemControlAction.captureScreenshot),
      );
      expect(
        withoutTarget.profile.blockedActions,
        contains(CockpitSystemControlAction.startRecording),
      );

      final withTarget = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'macos',
          appId: 'dev.cockpit.example',
        ),
      );

      expect(withTarget.profile.appId, 'dev.cockpit.example');
      expect(
        withTarget.profile.availableActions,
        contains(CockpitSystemControlAction.typeText),
      );
      expect(
        withTarget.profile.availableActions,
        contains(CockpitSystemControlAction.activateWindow),
      );
      expect(
        withTarget.profile.availableActions,
        containsAll(<CockpitSystemControlAction>[
          CockpitSystemControlAction.pressKey,
          CockpitSystemControlAction.readUiTree,
          CockpitSystemControlAction.setClipboard,
          CockpitSystemControlAction.getClipboard,
          CockpitSystemControlAction.readProcessList,
          CockpitSystemControlAction.readWindows,
          CockpitSystemControlAction.terminateApp,
        ]),
      );
      expect(
        withTarget.profile.availableActions,
        contains(CockpitSystemControlAction.captureScreenshot),
      );
      expect(
        withTarget.profile.availableActions,
        contains(CockpitSystemControlAction.startRecording),
      );
      expect(
        withTarget.profile.availableActions,
        contains(CockpitSystemControlAction.stopRecording),
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.openUrl)
            ?.requires,
        <String>['open'],
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.tap)
            ?.requires,
        contains('Accessibility permission'),
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        contains('screencapture'),
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        contains('Screen Recording permission'),
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        isNot(contains('Accessibility permission')),
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.readUiTree)
            ?.requires,
        contains('Automation permission for System Events'),
      );
      expect(
        withTarget.profile
            .capabilityFor(CockpitSystemControlAction.readUiTree)
            ?.requires,
        isNot(contains('Screen Recording permission')),
      );

      final macosProcessOnly = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'macos',
          processId: 4242,
        ),
      );
      expect(
        macosProcessOnly.profile.blockedActions,
        contains(CockpitSystemControlAction.captureScreenshot),
      );
      expect(
        macosProcessOnly.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        contains('app id'),
      );
      expect(
        macosProcessOnly.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        isNot(contains('app id or process id')),
      );

      final windowsProcessOnly = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'windows',
          processId: 4242,
        ),
      );
      expect(
        windowsProcessOnly.profile.availableActions,
        contains(CockpitSystemControlAction.captureScreenshot),
      );
      expect(
        windowsProcessOnly.profile.availableActions,
        contains(CockpitSystemControlAction.readUiTree),
      );
      expect(
        windowsProcessOnly.profile.availableActions,
        contains(CockpitSystemControlAction.readWindows),
      );

      final linuxWithTarget = await service.describe(
        const CockpitSystemControlDescribeRequest(
          platform: 'linux',
          appId: 'dev.cockpit.example',
        ),
      );
      expect(
        linuxWithTarget.profile
            .capabilityFor(CockpitSystemControlAction.tap)
            ?.requires,
        containsAll(<String>['xdotool', 'X11 DISPLAY']),
      );
      expect(
        linuxWithTarget.profile
            .capabilityFor(CockpitSystemControlAction.captureScreenshot)
            ?.requires,
        contains(
          'one screenshot path: gnome-screenshot, grim, scrot, import, xwd+ffmpeg, or ffmpeg x11grab',
        ),
      );
      expect(
        linuxWithTarget.profile.blockedActions,
        contains(CockpitSystemControlAction.readUiTree),
      );
      expect(
        linuxWithTarget.profile.availableActions,
        containsAll(<CockpitSystemControlAction>[
          CockpitSystemControlAction.readProcessList,
          CockpitSystemControlAction.readWindows,
        ]),
      );
    },
  );

  test('available capabilities resolve to executable commands', () async {
    const registry = CockpitSystemControlRegistry();
    for (final entry in <({String platform, String deviceId})>[
      (platform: 'android', deviceId: 'emulator-5554'),
      (platform: 'ios', deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC'),
      (platform: 'macos', deviceId: 'host'),
      (platform: 'windows', deviceId: 'host'),
      (platform: 'linux', deviceId: 'host'),
      (platform: 'web', deviceId: 'chrome'),
    ]) {
      final adapter = registry.resolve(entry.platform);
      final profile = adapter.describe(
        CockpitSystemControlTargetContext(
          deviceId: entry.deviceId,
          appId:
              entry.platform == 'macos' ||
                  entry.platform == 'ios' ||
                  entry.platform == 'windows' ||
                  entry.platform == 'linux'
              ? 'dev.cockpit.example'
              : null,
        ),
      );
      for (final capability in profile.capabilities.where(
        (capability) =>
            capability.availability ==
            CockpitSystemControlAvailability.available,
      )) {
        if (_isServiceLevelAction(capability.action)) {
          continue;
        }
        final request = CockpitSystemControlActionRequest(
          platform: entry.platform,
          deviceId: entry.deviceId,
          appId:
              entry.platform == 'macos' ||
                  entry.platform == 'ios' ||
                  entry.platform == 'windows' ||
                  entry.platform == 'linux'
              ? 'dev.cockpit.example'
              : null,
          action: capability.action,
          parameters: _validParametersFor(capability),
        );
        final command = adapter.resolveCommand(request);

        expect(
          command.hasError,
          isFalse,
          reason:
              '${entry.platform}.${capability.action.name} is declared available but resolves ${command.errorCode}: ${command.errorMessage}',
        );
        expect(command.executable, isNot(isEmpty));
      }
    }
  });

  test(
    'parameter-scoped actions remain available for action-time payloads',
    () {
      const registry = CockpitSystemControlRegistry();

      final androidProfile = registry
          .resolve('android')
          .describe(
            const CockpitSystemControlTargetContext(deviceId: 'emulator-5554'),
          );
      expect(
        androidProfile
            .capabilityFor(CockpitSystemControlAction.activateWindow)
            ?.availability,
        CockpitSystemControlAvailability.available,
      );

      final iosProfile = registry
          .resolve('ios')
          .describe(
            const CockpitSystemControlTargetContext(deviceId: 'booted'),
          );
      expect(
        iosProfile
            .capabilityFor(CockpitSystemControlAction.activateWindow)
            ?.availability,
        CockpitSystemControlAvailability.available,
      );
      expect(
        iosProfile
            .capabilityFor(CockpitSystemControlAction.grantPermission)
            ?.availability,
        CockpitSystemControlAvailability.available,
      );
    },
  );

  test('platform capability profiles expose action parameter metadata', () {
    const registry = CockpitSystemControlRegistry();

    final android = registry
        .resolve('android')
        .describe(
          const CockpitSystemControlTargetContext(deviceId: 'emulator-5554'),
        );
    expect(
      _parameter(android, CockpitSystemControlAction.tap, 'x')?.valueType,
      CockpitSystemControlParameterType.integer,
    );
    expect(
      _parameter(android, CockpitSystemControlAction.tap, 'x')?.required,
      isTrue,
    );
    expect(
      _parameter(
        android,
        CockpitSystemControlAction.setAppearance,
        'appearance',
      )?.allowedValues,
      <String>['light', 'dark', 'auto'],
    );
    expect(
      _parameter(
        android,
        CockpitSystemControlAction.setNetworkSpeed,
        'networkSpeed',
      )?.allowedValues,
      containsAll(<String>['gsm', 'lte', 'full']),
    );
    expect(
      android.capabilityFor(CockpitSystemControlAction.readUiTree)?.parameters,
      isEmpty,
      reason:
          'Android uiautomator dump does not consume maxDepth/maxNodes; do not advertise inert parameters.',
    );

    final ios = registry
        .resolve('ios')
        .describe(const CockpitSystemControlTargetContext(deviceId: 'booted'));
    expect(
      _parameter(
        ios,
        CockpitSystemControlAction.dismissSystemDialog,
        'decision',
      )?.allowedValues,
      <String>['accept', 'dismiss'],
    );
    expect(
      _parameter(
        ios,
        CockpitSystemControlAction.setAppearance,
        'appearance',
      )?.allowedValues,
      <String>['light', 'dark'],
    );
    expect(
      _parameter(
        ios,
        CockpitSystemControlAction.setAppearance,
        'appearance',
      )?.allowedValues,
      isNot(contains('auto')),
    );
    expect(
      _parameter(
        ios,
        CockpitSystemControlAction.setStatusBar,
        'dataNetwork',
      )?.allowedValues,
      containsAll(<String>['wifi', 'lte', '5g']),
    );
    expect(
      _parameter(
        ios,
        CockpitSystemControlAction.setStatusBar,
        'wifiBars',
      )?.minimum,
      0,
    );
    expect(
      _parameter(
        ios,
        CockpitSystemControlAction.setStatusBar,
        'wifiBars',
      )?.maximum,
      3,
    );

    final macos = registry
        .resolve('macos')
        .describe(
          const CockpitSystemControlTargetContext(appId: 'dev.cockpit.example'),
        );
    expect(
      _parameter(macos, CockpitSystemControlAction.typeText, 'text')?.required,
      isTrue,
    );
    expect(
      _parameter(
        macos,
        CockpitSystemControlAction.readUiTree,
        'maxDepth',
      )?.valueType,
      CockpitSystemControlParameterType.integer,
    );
    expect(
      _parameter(
        macos,
        CockpitSystemControlAction.captureScreenshot,
        'name',
      )?.valueType,
      CockpitSystemControlParameterType.string,
    );
    expect(
      _parameter(
        macos,
        CockpitSystemControlAction.runShell,
        'command',
      )?.valueType,
      CockpitSystemControlParameterType.stringList,
    );

    final web = registry
        .resolve('web')
        .describe(const CockpitSystemControlTargetContext(deviceId: 'chrome'));
    expect(
      _parameter(web, CockpitSystemControlAction.tap, 'x')?.required,
      isTrue,
    );
  });

  test('every platform profile declares every system action explicitly', () {
    const registry = CockpitSystemControlRegistry();
    for (final entry in <({String platform, String deviceId, String? appId})>[
      (platform: 'android', deviceId: 'emulator-5554', appId: null),
      (
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        appId: 'dev.cockpit.example',
      ),
      (platform: 'macos', deviceId: 'host', appId: 'dev.cockpit.example'),
      (platform: 'windows', deviceId: 'host', appId: 'dev.cockpit.example'),
      (platform: 'linux', deviceId: 'host', appId: 'dev.cockpit.example'),
      (platform: 'web', deviceId: 'chrome', appId: null),
      (platform: 'freebsd', deviceId: 'host', appId: null),
    ]) {
      final profile = registry
          .resolve(entry.platform)
          .describe(
            CockpitSystemControlTargetContext(
              deviceId: entry.deviceId,
              appId: entry.appId,
            ),
          );
      final declaredActions = profile.capabilities
          .map((capability) => capability.action)
          .toSet();

      expect(
        declaredActions,
        CockpitSystemControlAction.values.toSet(),
        reason: '${entry.platform} capability matrix must be exhaustive.',
      );
    }
  });
}

final class _AdbByteStderrProcessManager implements CockpitProcessManager {
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
    return ProcessResult(
      0,
      1,
      const <int>[],
      "error: device 'emulator-5554' not found".codeUnits,
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
  }) {
    throw UnimplementedError('start is not used by this test.');
  }
}

CockpitSystemControlService _serviceWithReachableAndroid() {
  return CockpitSystemControlService(
    androidDeviceStateProbe: (_, {required timeout}) async {
      return const CockpitAndroidDeviceProbeResult.reachable('device');
    },
  );
}

bool _isEvidenceAction(CockpitSystemControlAction action) {
  return switch (action) {
    CockpitSystemControlAction.captureScreenshot ||
    CockpitSystemControlAction.startRecording ||
    CockpitSystemControlAction.stopRecording => true,
    _ => false,
  };
}

bool _isServiceLevelAction(CockpitSystemControlAction action) {
  return switch (action) {
    CockpitSystemControlAction.preparePermissions ||
    CockpitSystemControlAction.stabilizeForScreenshot => true,
    _ => _isEvidenceAction(action),
  };
}

CockpitSystemControlParameter? _parameter(
  CockpitSystemControlProfile profile,
  CockpitSystemControlAction action,
  String name,
) {
  final parameters =
      profile.capabilityFor(action)?.parameters ??
      const <CockpitSystemControlParameter>[];
  for (final parameter in parameters) {
    if (parameter.name == name) {
      return parameter;
    }
  }
  return null;
}

Map<String, Object?> _validParametersFor(
  CockpitSystemControlCapability capability,
) {
  final parameters = <String, Object?>{
    ..._fallbackParametersFor(capability.action),
  };
  for (final parameter in capability.parameters) {
    parameters[parameter.name] = _sampleValueFor(parameter);
  }
  return parameters;
}

Object? _sampleValueFor(CockpitSystemControlParameter parameter) {
  if (parameter.allowedValues.isNotEmpty) {
    return parameter.allowedValues.first;
  }
  return switch (parameter.valueType) {
    CockpitSystemControlParameterType.string => _sampleStringFor(
      parameter.name,
    ),
    CockpitSystemControlParameterType.integer =>
      (parameter.minimum ?? 1).toInt(),
    CockpitSystemControlParameterType.number =>
      (parameter.minimum ?? 1).toDouble(),
    CockpitSystemControlParameterType.boolean => true,
    CockpitSystemControlParameterType.stringList => <String>['echo', 'ok'],
  };
}

String _sampleStringFor(String parameterName) {
  return switch (parameterName) {
    'text' => 'hello',
    'key' => 'enter',
    'url' => 'https://example.com',
    'settingsAction' => 'android.settings.SETTINGS',
    'appId' || 'packageId' => 'dev.cockpit.example',
    'permission' => 'android.permission.CAMERA',
    'title' => 'Download complete',
    'body' => 'Model is ready',
    'tag' => 'model-download',
    'payloadJson' => '{"aps":{"alert":"Ready"}}',
    'time' => '09:41',
    'operatorName' => 'Cockpit',
    'outputPath' => '/tmp/cockpit-system-screenshot.png',
    'appPath' => '/tmp/cockpit-app.apk',
    'sourcePath' => '/tmp/cockpit-source.dat',
    'destinationPath' => '/tmp/cockpit-destination.dat',
    'name' => 'system-recording',
    'command' => 'echo',
    _ => 'value',
  };
}

Map<String, Object?> _fallbackParametersFor(CockpitSystemControlAction action) {
  return switch (action) {
    CockpitSystemControlAction.tap => const <String, Object?>{'x': 10, 'y': 20},
    CockpitSystemControlAction.longPress => const <String, Object?>{
      'x': 10,
      'y': 20,
      'durationMs': 800,
    },
    CockpitSystemControlAction.drag => const <String, Object?>{
      'startX': 10,
      'startY': 20,
      'endX': 30,
      'endY': 40,
      'durationMs': 300,
    },
    CockpitSystemControlAction.typeText => const <String, Object?>{
      'text': 'hello',
    },
    CockpitSystemControlAction.pressKey => const <String, Object?>{
      'key': 'enter',
    },
    CockpitSystemControlAction.pressBack ||
    CockpitSystemControlAction.pressHome ||
    CockpitSystemControlAction.pressVolumeUp ||
    CockpitSystemControlAction.pressVolumeDown ||
    CockpitSystemControlAction.pressVolumeMute ||
    CockpitSystemControlAction.dismissSystemDialog ||
    CockpitSystemControlAction.dismissKeyboard ||
    CockpitSystemControlAction.clearStatusBar ||
    CockpitSystemControlAction.expandNotifications ||
    CockpitSystemControlAction.expandQuickSettings ||
    CockpitSystemControlAction.collapseSystemUi ||
    CockpitSystemControlAction.clearNotifications ||
    CockpitSystemControlAction.readFocusState ||
    CockpitSystemControlAction.readUiTree ||
    CockpitSystemControlAction.readProcessList ||
    CockpitSystemControlAction.readWindows ||
    CockpitSystemControlAction.readSystemState ||
    CockpitSystemControlAction.readDeviceInfo ||
    CockpitSystemControlAction.readSystemLogs ||
    CockpitSystemControlAction.readNotificationState =>
      const <String, Object?>{},
    CockpitSystemControlAction.setBattery => const <String, Object?>{
      'level': 50,
      'plugged': false,
    },
    CockpitSystemControlAction.setConnectivity => const <String, Object?>{
      'wifi': true,
    },
    CockpitSystemControlAction.setLocale => const <String, Object?>{
      'locale': 'zh_CN',
    },
    CockpitSystemControlAction.preparePermissions => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
      'permissions': <String>['android.permission.CAMERA'],
    },
    CockpitSystemControlAction.stabilizeForScreenshot =>
      const <String, Object?>{'packageId': 'dev.cockpit.example'},
    CockpitSystemControlAction.activateWindow ||
    CockpitSystemControlAction.terminateApp => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
    },
    CockpitSystemControlAction.setClipboard => const <String, Object?>{
      'text': 'hello clipboard',
    },
    CockpitSystemControlAction.getClipboard => const <String, Object?>{},
    CockpitSystemControlAction.installApp => const <String, Object?>{
      'appPath': '/tmp/cockpit-app.apk',
      'grantPermissions': true,
    },
    CockpitSystemControlAction.uninstallApp => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
      'keepData': false,
    },
    CockpitSystemControlAction.clearAppData => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
    },
    CockpitSystemControlAction.grantPermission => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
      'permission': 'android.permission.CAMERA',
    },
    CockpitSystemControlAction.revokePermission => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
      'permission': 'android.permission.CAMERA',
    },
    CockpitSystemControlAction.resetPermission => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
      'permission': 'android.permission.CAMERA',
    },
    CockpitSystemControlAction.openUrl => const <String, Object?>{
      'url': 'https://example.com',
    },
    CockpitSystemControlAction.openSystemSettings => const <String, Object?>{
      'settingsAction': 'android.settings.SETTINGS',
    },
    CockpitSystemControlAction.setAppearance => const <String, Object?>{
      'appearance': 'dark',
    },
    CockpitSystemControlAction.setContentSize => const <String, Object?>{
      'contentSize': 'accessibility-large',
    },
    CockpitSystemControlAction.setLocation => const <String, Object?>{
      'latitude': 37.3349,
      'longitude': -122.009,
    },
    CockpitSystemControlAction.setOrientation => const <String, Object?>{
      'orientation': 'landscape',
    },
    CockpitSystemControlAction.setNetworkSpeed => const <String, Object?>{
      'networkSpeed': 'full',
    },
    CockpitSystemControlAction.setNetworkDelay => const <String, Object?>{
      'networkDelay': 'none',
    },
    CockpitSystemControlAction.setStatusBar => const <String, Object?>{
      'time': '09:41',
      'dataNetwork': 'wifi',
      'wifiMode': 'active',
      'wifiBars': 3,
      'batteryState': 'charged',
      'batteryLevel': 100,
    },
    CockpitSystemControlAction.postNotification => const <String, Object?>{
      'title': 'Download complete',
      'body': 'Model is ready',
      'tag': 'model-download',
    },
    CockpitSystemControlAction.tapNotification => const <String, Object?>{
      'title': 'Download complete',
    },
    CockpitSystemControlAction.recoverToApp ||
    CockpitSystemControlAction.resolveBlockers => const <String, Object?>{
      'packageId': 'dev.cockpit.example',
    },
    CockpitSystemControlAction.pushFile => const <String, Object?>{
      'sourcePath': '/tmp/cockpit-source.dat',
      'destinationPath': '/tmp/cockpit-destination.dat',
    },
    CockpitSystemControlAction.pullFile => const <String, Object?>{
      'sourcePath': '/tmp/cockpit-source.dat',
      'destinationPath': '/tmp/cockpit-destination.dat',
    },
    CockpitSystemControlAction.addMedia => const <String, Object?>{
      'sourcePath': '/tmp/cockpit-media.png',
    },
    CockpitSystemControlAction.captureScreenshot => const <String, Object?>{
      'outputPath': '/tmp/cockpit-system-screenshot.png',
    },
    CockpitSystemControlAction.startRecording => const <String, Object?>{
      'name': 'system-recording',
    },
    CockpitSystemControlAction.stopRecording => const <String, Object?>{},
    CockpitSystemControlAction.runShell => const <String, Object?>{
      'command': <String>['echo', 'ok'],
    },
  };
}
