import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../cockpit_system_control_action.dart';
import '../cockpit_system_control_adapter.dart';
import '../cockpit_ios_webdriver_agent_client.dart';
import '../cockpit_system_control_parameters.dart';
import '../cockpit_system_control_profile.dart';

final class CockpitIosSystemControlAdapter
    implements CockpitSystemControlAdapter {
  const CockpitIosSystemControlAdapter();

  @override
  String get platform => 'ios';

  @override
  CockpitSystemControlProfile describe(
    CockpitSystemControlTargetContext target,
  ) {
    final deviceId = target.deviceId;
    if (_looksLikeIosSimulatorDeviceId(deviceId)) {
      final wdaBaseUri = _readWdaBaseUri(target.metadata);
      final wdaReachable = target.metadata['wdaReachable'] == true;
      final wdaAvailability = wdaBaseUri == null || !wdaReachable
          ? CockpitSystemControlAvailability.blocked
          : CockpitSystemControlAvailability.available;
      final wdaRequires = _wdaRequires(
        hasEndpoint: wdaBaseUri != null,
        reachable: wdaReachable,
      );
      return CockpitSystemControlProfile(
        platform: platform,
        deviceId: deviceId,
        appId: target.appId,
        processId: target.processId,
        adapter: 'ios.simctl+xctest',
        preferredPlane: CockpitPlaneKind.flutterSemanticPlane,
        fallbackOrder: const <CockpitPlaneKind>[
          CockpitPlaneKind.flutterSemanticPlane,
          CockpitPlaneKind.nativeUiPlane,
          CockpitPlaneKind.deviceSystemPlane,
        ],
        recommendedNextStep: 'preferFlutterSemanticPlane',
        capabilities: <CockpitSystemControlCapability>[
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.tap,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.tap',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.coordinate,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.longPress,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.longPress',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.longPress,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.drag,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.drag',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.drag,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.typeText,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.typeText',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.text,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressKey,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.key',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.key,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressBack,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-global-back-key',
            limitations: <String>[
              'iOS has no stable app-scoped Back key outside app UI semantics.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressHome,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.homescreen',
            requires: wdaRequires,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeUp,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-simulator-no-volume-key',
            limitations: <String>[
              'XCTest/WebDriverAgent excludes iOS simulator volumeUp; use real-device WDA if volume keys must be validated.',
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeDown,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-simulator-no-volume-key',
            limitations: <String>[
              'XCTest/WebDriverAgent excludes iOS simulator volumeDown; use real-device WDA if volume keys must be validated.',
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeMute,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-volume-mute-button',
            limitations: <String>[
              'XCTest/WebDriverAgent does not expose a stable iOS volume mute button.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.activateWindow,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.launch',
            requires: <String>['xcrun', 'simulator device id', 'app id'],
            limitations: <String>[
              'Brings the app to the foreground without terminating an existing debug or hot-reload session.',
            ],
            parameters: CockpitSystemControlParameterSets.iosApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.terminateApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.terminate',
            requires: <String>['xcrun', 'simulator device id', 'app id'],
            parameters: CockpitSystemControlParameterSets.iosApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.installApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.install',
            requires: <String>['xcrun', 'simulator device id', '.app path'],
            parameters: CockpitSystemControlParameterSets.installApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.uninstallApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.uninstall',
            requires: <String>['xcrun', 'simulator device id', 'app id'],
            parameters: CockpitSystemControlParameterSets.uninstallApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearAppData,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.privacy.reset+app-container-delete',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'app id',
              'installed app data container',
            ],
            limitations: <String>[
              'Deletes the app data container contents while preserving the installed app bundle.',
            ],
            parameters: CockpitSystemControlParameterSets.iosApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.dismissSystemDialog,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.alert.accept',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.systemDialogDecision,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.dismissKeyboard,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.keyboard.dismiss',
            requires: wdaRequires,
            limitations: <String>[
              'Falls back to WebDriverAgent keyboard dismissal; Flutter dismissKeyboard remains preferred for Flutter-owned focus.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.grantPermission,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.privacy.grant',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'privacy service',
              'app id',
            ],
            limitations: <String>['simctl privacy may terminate the app'],
            parameters: CockpitSystemControlParameterSets.iosGrantPermission,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.revokePermission,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.privacy.revoke',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'privacy service',
              'app id',
            ],
            limitations: <String>['simctl privacy may terminate the app'],
            parameters: CockpitSystemControlParameterSets.iosRevokePermission,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.resetPermission,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.privacy.reset',
            requires: <String>['xcrun', 'simulator device id'],
            limitations: <String>['simctl privacy may terminate the app'],
            parameters: CockpitSystemControlParameterSets.iosResetPermission,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.preparePermissions,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'macro.simctl.privacy+recover',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'privacy services',
              'app id',
            ],
            limitations: <String>[
              'Runs simctl privacy grant, revoke, or reset for each service; simctl privacy may terminate the app.',
            ],
            parameters: CockpitSystemControlParameterSets.preparePermissions,
            fallbackActions: <CockpitSystemControlAction>[
              CockpitSystemControlAction.grantPermission,
              CockpitSystemControlAction.revokePermission,
              CockpitSystemControlAction.resetPermission,
              CockpitSystemControlAction.recoverToApp,
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openUrl,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.openurl',
            requires: <String>['xcrun', 'simulator device id'],
            parameters: CockpitSystemControlParameterSets.url,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openSystemSettings,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.openurl.App-Prefs',
            requires: <String>['xcrun', 'simulator device id'],
            limitations: <String>[
              'Uses the simulator App-Prefs URL scheme; exact destination can vary by iOS runtime.',
            ],
            parameters: CockpitSystemControlParameterSets.systemSettings,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setAppearance,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.ui.appearance',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'appearance mode',
            ],
            parameters: CockpitSystemControlParameterSets.iosAppearance,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setContentSize,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.ui.content_size',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'content size category',
            ],
            parameters: CockpitSystemControlParameterSets.iosContentSize,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setLocation,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.location.set',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'latitude',
              'longitude',
            ],
            parameters: CockpitSystemControlParameterSets.location,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setOrientation,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.orientation',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.iosOrientation,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setNetworkSpeed,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'network-link-conditioner-or-host-proxy',
            requires: <String>[
              'Network Link Conditioner or host proxy tooling',
            ],
            limitations: <String>[
              'simctl status_bar can change network icons but not real network transport.',
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setNetworkDelay,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'network-link-conditioner-or-host-proxy',
            requires: <String>[
              'Network Link Conditioner or host proxy tooling',
            ],
            limitations: <String>[
              'simctl status_bar can change network icons but not real network transport.',
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setStatusBar,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.status_bar.override',
            requires: <String>['xcrun', 'simulator device id'],
            parameters: CockpitSystemControlParameterSets.iosStatusBar,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearStatusBar,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.status_bar.clear',
            requires: <String>['xcrun', 'simulator device id'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.expandNotifications,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.notification-center.drag',
            requires: wdaRequires,
            limitations: <String>[
              'simctl has no stable notification-center expansion command; WebDriverAgent uses a top-edge drag that depends on simulator geometry.',
            ],
            fallbackActions: <CockpitSystemControlAction>[
              CockpitSystemControlAction.drag,
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.expandQuickSettings,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.control-center.drag',
            requires: wdaRequires,
            limitations: <String>[
              'simctl has no stable Control Center expansion command; WebDriverAgent uses a top-edge drag that depends on simulator geometry.',
            ],
            fallbackActions: <CockpitSystemControlAction>[
              CockpitSystemControlAction.drag,
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.collapseSystemUi,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.system-ui-collapse-gesture',
            requires: wdaRequires,
            limitations: <String>[
              'Uses a bottom-edge upward gesture to dismiss notification center or control center without intentionally leaving the app.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.postNotification,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.push',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'bundle id',
              'APNS payload',
            ],
            limitations: <String>[
              'Only simulates remote push delivery. The app must be installed and configured to receive remote notifications.',
            ],
            parameters: CockpitSystemControlParameterSets.iosNotification,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearNotifications,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'simctl-no-clear-notifications',
            limitations: <String>[
              'simctl does not expose a stable clear-delivered-notifications command.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.tapNotification,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.notification-center.tap-text',
            requires: wdaRequires,
            limitations: <String>[
              'Uses WebDriverAgent source and coordinate taps after opening Notification Center; exact behavior depends on simulator geometry and delivered notification visibility.',
            ],
            parameters: CockpitSystemControlParameterSets.tapNotification,
            fallbackActions: <CockpitSystemControlAction>[
              CockpitSystemControlAction.drag,
              CockpitSystemControlAction.tap,
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.recoverToApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.launch',
            requires: <String>['xcrun', 'simulator device id', 'app id'],
            limitations: <String>[
              'Brings the app to the foreground without terminating an existing Flutter debug or hot-reload session.',
            ],
            parameters: CockpitSystemControlParameterSets.recoverToApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.resolveBlockers,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.alert+keyboard+simctl.launch',
            requires: <String>[...wdaRequires, 'app id'],
            limitations: <String>[
              'Handles common alerts and keyboard blockers before restoring the app; privacy grants should still prefer simctl privacy for deterministic setup.',
            ],
            parameters: CockpitSystemControlParameterSets.resolveBlockers,
            fallbackActions: <CockpitSystemControlAction>[
              CockpitSystemControlAction.dismissSystemDialog,
              CockpitSystemControlAction.dismissKeyboard,
              CockpitSystemControlAction.recoverToApp,
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.stabilizeForScreenshot,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'macro.simctl+xctest.stabilize-screenshot',
            requires: <String>['xcrun', 'simulator device id'],
            limitations: <String>[
              'Uses simctl for deterministic status bar, appearance, and app recovery; WDA-only steps such as keyboard dismissal, system UI collapse, and orientation are skipped unless WebDriverAgent is reachable.',
            ],
            parameters:
                CockpitSystemControlParameterSets.stabilizeForScreenshot,
            fallbackActions: <CockpitSystemControlAction>[
              CockpitSystemControlAction.dismissKeyboard,
              CockpitSystemControlAction.collapseSystemUi,
              CockpitSystemControlAction.setOrientation,
              CockpitSystemControlAction.setAppearance,
              CockpitSystemControlAction.setStatusBar,
              CockpitSystemControlAction.clearStatusBar,
              CockpitSystemControlAction.recoverToApp,
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setClipboard,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.pbcopy',
            requires: <String>['xcrun', 'simulator device id'],
            parameters: CockpitSystemControlParameterSets.text,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.getClipboard,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.pbpaste',
            requires: <String>['xcrun', 'simulator device id'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pushFile,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.get_app_container+cp',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'app id',
              'host file path',
              'app data container path',
            ],
            limitations: <String>[
              'iOS simulator file transfer is app-container scoped; destinationPath is relative to the app data container unless absolute.',
            ],
            parameters: CockpitSystemControlParameterSets.fileTransfer,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pullFile,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.get_app_container+cp',
            requires: <String>[
              'xcrun',
              'simulator device id',
              'app id',
              'app data container path',
              'host destination path',
            ],
            limitations: <String>[
              'iOS simulator file transfer is app-container scoped; sourcePath is relative to the app data container unless absolute.',
            ],
            parameters: CockpitSystemControlParameterSets.fileTransfer,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.addMedia,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.addmedia',
            requires: <String>['xcrun', 'simulator device id', 'media path'],
            parameters: CockpitSystemControlParameterSets.iosAddMedia,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.captureScreenshot,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.io.screenshot',
            requires: <String>['xcrun', 'booted simulator'],
            parameters: CockpitSystemControlParameterSets.screenshot,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.startRecording,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.io.recordVideo',
            requires: <String>['xcrun', 'booted simulator'],
            parameters: CockpitSystemControlParameterSets.startRecording,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.stopRecording,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.io.recordVideo.stop',
            requires: <String>[
              'xcrun',
              'booted simulator',
              'active recording session',
            ],
            parameters: CockpitSystemControlParameterSets.stopRecording,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readUiTree,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.source',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.readUiTree,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readProcessList,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.spawn.bin-ps',
            requires: <String>['xcrun', 'simulator device id'],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readWindows,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-window-manager',
            limitations: <String>[
              'iOS simulator does not expose app windows through a stable simctl API.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readSystemState,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.list.devices',
            requires: <String>['xcrun', 'simulator device id'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readDeviceInfo,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.list+appinfo+ui',
            requires: <String>['xcrun', 'simulator device id'],
            parameters: CockpitSystemControlParameterSets.iosApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readFocusState,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.keyboard+source',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readNotificationState,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'ios-simulator-notification-database',
            requires: <String>['app notification assertions or WDA UI tree'],
            limitations: <String>[
              'simctl does not expose delivered notification state through a stable public command.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readDeviceInfo,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.device.info',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readSystemLogs,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.spawn.log-show',
            requires: <String>['xcrun', 'simulator device id'],
            limitations: <String>[
              'Reads the recent unified log; pass processName to scope to the app process.',
            ],
            parameters: CockpitSystemControlParameterSets.appleSystemLogs,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setLocale,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.spawn.defaults.locale',
            requires: <String>['xcrun', 'simulator device id'],
            limitations: <String>[
              'Relaunch the app (terminateApp then activateWindow) so the new locale takes effect.',
            ],
            parameters: CockpitSystemControlParameterSets.iosLocale,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setBattery,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-simulator-no-battery-simulation',
            limitations: <String>[
              'The iOS simulator cannot simulate battery state; setStatusBar only changes the indicator.',
            ],
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setConnectivity,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-simulator-shares-host-network',
            limitations: <String>[
              'The iOS simulator shares the host network; toggle host connectivity or use a proxy instead.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.runShell,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.simctl.spawn',
            requires: <String>['xcrun', 'simulator device id'],
            parameters: CockpitSystemControlParameterSets.shellCommand,
          ),
        ],
      );
    }
    final wdaBaseUri = _readWdaBaseUri(target.metadata);
    final wdaReachable = target.metadata['wdaReachable'] == true;
    final wdaAvailability = wdaBaseUri == null || !wdaReachable
        ? CockpitSystemControlAvailability.blocked
        : CockpitSystemControlAvailability.available;
    final wdaRequires = _wdaRequires(
      hasEndpoint: wdaBaseUri != null,
      reachable: wdaReachable,
      deviceRequirement: 'connected iOS device',
    );
    return CockpitSystemControlProfile(
      platform: platform,
      deviceId: deviceId,
      appId: target.appId,
      processId: target.processId,
      adapter: 'ios.physical+wda+devicectl',
      preferredPlane: CockpitPlaneKind.nativeUiPlane,
      fallbackOrder: const <CockpitPlaneKind>[
        CockpitPlaneKind.nativeUiPlane,
        CockpitPlaneKind.deviceSystemPlane,
      ],
      recommendedNextStep:
          wdaAvailability == CockpitSystemControlAvailability.available
          ? 'runNativeAutomation'
          : 'startWebDriverAgent',
      capabilities: cockpitCompleteSystemControlCapabilities(
        <CockpitSystemControlCapability>[
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.tap,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.tap',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.coordinate,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.longPress,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.longPress',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.longPress,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.drag,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.drag',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.drag,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.typeText,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.typeText',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.text,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressKey,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.w3c.actions.key',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.key,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressBack,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-global-back-key',
            limitations: <String>[
              'iOS has no stable app-scoped Back key outside app UI semantics.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressHome,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.homescreen',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeUp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.pressButton.volumeUp',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeDown,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.pressButton.volumeDown',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeMute,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-volume-mute-button',
            limitations: <String>[
              'XCTest/WebDriverAgent does not expose a stable iOS volume mute button.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.activateWindow,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.apps.activate',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.iosApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.terminateApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.apps.terminate',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.iosApp,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.installApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.devicectl.device.install.app',
            requires: <String>['Xcode devicectl', 'connected iOS device'],
            parameters: CockpitSystemControlParameterSets.installApp,
          ),
          const CockpitSystemControlCapability(
            action: CockpitSystemControlAction.uninstallApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'xcrun.devicectl.device.uninstall.app',
            requires: <String>['Xcode devicectl', 'connected iOS device'],
            parameters: CockpitSystemControlParameterSets.uninstallApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.dismissSystemDialog,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.alert',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.systemDialogDecision,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.dismissKeyboard,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.keyboard.dismiss',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.grantPermission,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-permission-flow',
            requires: <String>[
              'developer signing and app-specific permission flow',
            ],
            parameters: CockpitSystemControlParameterSets.iosGrantPermission,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.preparePermissions,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-permission-flow',
            requires: <String>[
              'developer signing and app-specific permission flow',
            ],
            parameters: CockpitSystemControlParameterSets.preparePermissions,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openUrl,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-open-url',
            requires: <String>['developer signing and device URL tooling'],
            parameters: CockpitSystemControlParameterSets.url,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openSystemSettings,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-open-settings',
            requires: <String>['developer signing and device URL tooling'],
            parameters: CockpitSystemControlParameterSets.systemSettings,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setAppearance,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-appearance',
            requires: <String>[
              'developer signing and device appearance tooling',
            ],
            parameters: CockpitSystemControlParameterSets.iosAppearance,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setContentSize,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-content-size',
            requires: <String>[
              'developer signing and device accessibility tooling',
            ],
            parameters: CockpitSystemControlParameterSets.iosContentSize,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setLocation,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-location',
            requires: <String>[
              'developer signing and location simulation tooling',
            ],
            parameters: CockpitSystemControlParameterSets.location,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setOrientation,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.orientation',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.iosOrientation,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setNetworkSpeed,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-network-conditioning',
            requires: <String>[
              'developer signing and network conditioning tooling',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setNetworkDelay,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-network-conditioning',
            requires: <String>[
              'developer signing and network conditioning tooling',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setStatusBar,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-status-bar',
            requires: <String>['developer-signed XCTest/WebDriverAgent runner'],
            parameters: CockpitSystemControlParameterSets.iosStatusBar,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearStatusBar,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-status-bar.clear',
            requires: <String>['developer-signed XCTest/WebDriverAgent runner'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.expandNotifications,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.notification-center.drag',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.expandQuickSettings,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.control-center.drag',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.collapseSystemUi,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.system-ui-collapse-gesture',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.postNotification,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-push-notification',
            requires: <String>['APNS development environment or Xcode tooling'],
            parameters: CockpitSystemControlParameterSets.iosNotification,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearNotifications,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-notification-center',
            requires: <String>['developer-signed XCTest/WebDriverAgent runner'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.tapNotification,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.notification-center.tap-text',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.tapNotification,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.recoverToApp,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.apps.activate',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.recoverToApp,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.resolveBlockers,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.alert+keyboard+activate',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.resolveBlockers,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.stabilizeForScreenshot,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.stabilize-screenshot',
            requires: wdaRequires,
            parameters:
                CockpitSystemControlParameterSets.stabilizeForScreenshot,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setClipboard,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-pasteboard',
            requires: <String>[
              'developer signing and device pasteboard tooling',
            ],
            parameters: CockpitSystemControlParameterSets.text,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.getClipboard,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-pasteboard',
            requires: <String>[
              'developer signing and device pasteboard tooling',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.captureScreenshot,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.screenshot',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.screenshot,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.startRecording,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-recording',
            requires: <String>['developer signing and device capture tooling'],
            parameters: CockpitSystemControlParameterSets.startRecording,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.stopRecording,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-recording.stop',
            requires: <String>[
              'developer signing and active device capture tooling',
            ],
            parameters: CockpitSystemControlParameterSets.stopRecording,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readUiTree,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.source',
            requires: wdaRequires,
            parameters: CockpitSystemControlParameterSets.readUiTree,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readProcessList,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-process-list',
            requires: <String>[
              'developer signing and device diagnostics tooling',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readWindows,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-window-manager',
            limitations: <String>[
              'iOS does not expose app windows through a stable public device API.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readSystemState,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'developer-device-diagnostics',
            requires: <String>[
              'developer signing and device diagnostics tooling',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readFocusState,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: wdaAvailability,
            strategy: 'webdriveragent.keyboard+source',
            requires: wdaRequires,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.runShell,
            plane: CockpitPlaneKind.deviceSystemPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'ios-no-device-shell',
            limitations: <String>[
              'iOS does not expose a general public device shell.',
            ],
          ),
        ],
        plane: CockpitPlaneKind.deviceSystemPlane,
        availability: CockpitSystemControlAvailability.blocked,
        strategy: 'developer-device-tooling',
        requires: <String>[
          'developer signing and device automation tooling (devicectl, ios-deploy, or Xcode)',
        ],
      ),
    );
  }

  @override
  CockpitResolvedSystemControlCommand resolveCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final deviceId = request.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingDeviceId',
        message: 'iOS system actions require --device-id.',
      );
    }
    if (!_looksLikeIosSimulatorDeviceId(deviceId)) {
      return _resolvePhysicalCommand(request, deviceId);
    }
    return switch (request.action) {
      CockpitSystemControlAction.activateWindow => _appScopedCommand(
        request,
        (appId) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'launch',
          deviceId,
          appId,
        ]),
      ),
      CockpitSystemControlAction.terminateApp => _appScopedCommand(
        request,
        (appId) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'terminate',
          deviceId,
          appId,
        ]),
      ),
      CockpitSystemControlAction.installApp => _iosInstallAppCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.uninstallApp => _appScopedCommand(
        request,
        (appId) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'uninstall',
          deviceId,
          appId,
        ]),
      ),
      CockpitSystemControlAction.clearAppData => _iosClearAppDataCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.tap => _wdaCommand(
        request,
        CockpitIosWdaAction.tap,
      ),
      CockpitSystemControlAction.longPress => _wdaCommand(
        request,
        CockpitIosWdaAction.longPress,
      ),
      CockpitSystemControlAction.drag => _wdaCommand(
        request,
        CockpitIosWdaAction.drag,
      ),
      CockpitSystemControlAction.typeText => _wdaCommand(
        request,
        CockpitIosWdaAction.typeText,
      ),
      CockpitSystemControlAction.pressKey => _wdaCommand(
        request,
        CockpitIosWdaAction.pressKey,
      ),
      CockpitSystemControlAction.pressHome => _wdaCommand(
        request,
        CockpitIosWdaAction.pressHome,
      ),
      // Matches the capability matrix: XCTest/WebDriverAgent excludes
      // simulator volume keys, so resolution must refuse instead of issuing
      // a WDA pressButton that can never succeed.
      CockpitSystemControlAction.pressVolumeUp ||
      CockpitSystemControlAction
          .pressVolumeDown => const CockpitResolvedSystemControlCommand.error(
        code: 'unsupportedSystemAction',
        message:
            'iOS simulator volume keys are excluded by XCTest/WebDriverAgent.',
      ),
      CockpitSystemControlAction.pressVolumeMute =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'unsupportedSystemAction',
          message: 'iOS does not expose a stable volume mute button.',
        ),
      CockpitSystemControlAction.dismissSystemDialog => _wdaCommand(
        request,
        CockpitIosWdaAction.dismissSystemDialog,
      ),
      CockpitSystemControlAction.dismissKeyboard => _wdaCommand(
        request,
        CockpitIosWdaAction.dismissKeyboard,
      ),
      CockpitSystemControlAction.setOrientation => _wdaCommand(
        request,
        CockpitIosWdaAction.setOrientation,
      ),
      CockpitSystemControlAction.readUiTree => _wdaCommand(
        request,
        CockpitIosWdaAction.readUiTree,
      ),
      CockpitSystemControlAction.openUrl => cockpitTextCommand(
        request,
        'url',
        (url) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'openurl',
          deviceId,
          url,
        ]),
      ),
      CockpitSystemControlAction.openSystemSettings =>
        _iosOpenSystemSettingsCommand(
          request,
          (url) => CockpitResolvedSystemControlCommand('xcrun', <String>[
            'simctl',
            'openurl',
            deviceId,
            url,
          ]),
        ),
      CockpitSystemControlAction.setAppearance => cockpitTextCommand(
        request,
        'appearance',
        (appearance) => _iosSetAppearanceCommand(
          appearance,
          (mode) => CockpitResolvedSystemControlCommand('xcrun', <String>[
            'simctl',
            'ui',
            deviceId,
            'appearance',
            mode,
          ]),
        ),
        trim: true,
        allowedValues: const <String>['light', 'dark'],
      ),
      CockpitSystemControlAction.setContentSize => cockpitTextCommand(
        request,
        'contentSize',
        (contentSize) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'ui',
          deviceId,
          'content_size',
          contentSize,
        ]),
        trim: true,
        allowedValues:
            CockpitSystemControlAllowedValues.iosContentSizeCategories,
      ),
      CockpitSystemControlAction.setLocation => cockpitLocationCommand(
        request,
        (latitude, longitude, altitude) {
          return CockpitResolvedSystemControlCommand('xcrun', <String>[
            'simctl',
            'location',
            deviceId,
            'set',
            '${_formatCoordinate(latitude)},${_formatCoordinate(longitude)}',
          ]);
        },
      ),
      CockpitSystemControlAction.setStatusBar => _iosSetStatusBarCommand(
        request,
        (args) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'status_bar',
          deviceId,
          'override',
          ...args,
        ]),
      ),
      CockpitSystemControlAction.clearStatusBar =>
        CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'status_bar',
          deviceId,
          'clear',
        ]),
      CockpitSystemControlAction.clearNotifications => _unsupportedCommand(
        request,
      ),
      CockpitSystemControlAction.expandQuickSettings => _wdaCommand(
        request,
        CockpitIosWdaAction.expandQuickSettings,
      ),
      CockpitSystemControlAction.expandNotifications => _wdaCommand(
        request,
        CockpitIosWdaAction.expandNotifications,
      ),
      CockpitSystemControlAction.collapseSystemUi => _wdaCommand(
        request,
        CockpitIosWdaAction.collapseSystemUi,
      ),
      CockpitSystemControlAction.tapNotification => _wdaCommand(
        request,
        CockpitIosWdaAction.tapNotification,
      ),
      CockpitSystemControlAction.recoverToApp => _appScopedCommand(
        request,
        (appId) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'launch',
          deviceId,
          appId,
        ]),
      ),
      CockpitSystemControlAction.resolveBlockers => _iosResolveBlockersCommand(
        request,
      ),
      CockpitSystemControlAction.preparePermissions ||
      CockpitSystemControlAction.stabilizeForScreenshot =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemMacroAction',
          message: 'Macro actions are executed through the action service.',
        ),
      CockpitSystemControlAction.postNotification =>
        _iosPostNotificationCommand(
          request,
          (appId, payloadJson) =>
              CockpitResolvedSystemControlCommand('sh', <String>[
                '-c',
                r'printf "%s" "$3" | xcrun simctl push "$1" "$2" -',
                'flutter_cockpit_ios_push',
                deviceId,
                appId,
                payloadJson,
              ]),
        ),
      CockpitSystemControlAction.setClipboard => cockpitTextCommand(
        request,
        'text',
        (text) => CockpitResolvedSystemControlCommand('sh', <String>[
          '-c',
          r'printf "%s" "$2" | xcrun simctl pbcopy "$1"',
          'flutter_cockpit_ios_clipboard',
          deviceId,
          text,
        ]),
      ),
      CockpitSystemControlAction.getClipboard =>
        CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'pbpaste',
          deviceId,
        ]),
      CockpitSystemControlAction.captureScreenshot => cockpitTextCommand(
        request,
        'outputPath',
        (outputPath) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'io',
          deviceId,
          'screenshot',
          outputPath,
        ]),
      ),
      CockpitSystemControlAction.grantPermission => _permissionCommand(
        request,
        actionName: 'grantPermission',
        factory: (appId, service) => CockpitResolvedSystemControlCommand(
          'xcrun',
          <String>['simctl', 'privacy', deviceId, 'grant', service, appId],
        ),
      ),
      CockpitSystemControlAction.revokePermission => _permissionCommand(
        request,
        actionName: 'revokePermission',
        factory: (appId, service) => CockpitResolvedSystemControlCommand(
          'xcrun',
          <String>['simctl', 'privacy', deviceId, 'revoke', service, appId],
        ),
      ),
      CockpitSystemControlAction.resetPermission => _iosResetPermissionCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.startRecording ||
      CockpitSystemControlAction.stopRecording =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemEvidenceAction',
          message: 'Recording actions are executed through recording adapters.',
        ),
      CockpitSystemControlAction.pushFile => _iosContainerFileCommand(
        request,
        deviceId,
        mode: _IosContainerFileMode.push,
      ),
      CockpitSystemControlAction.pullFile => _iosContainerFileCommand(
        request,
        deviceId,
        mode: _IosContainerFileMode.pull,
      ),
      CockpitSystemControlAction.addMedia => _iosAddMediaCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.runShell => cockpitShellCommand(
        request,
        (command) => CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'spawn',
          deviceId,
          ..._iosSimulatorShellCommand(command),
        ]),
      ),
      CockpitSystemControlAction.readProcessList =>
        CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'spawn',
          deviceId,
          '/bin/ps',
          '-A',
        ]),
      CockpitSystemControlAction.readSystemState =>
        CockpitResolvedSystemControlCommand('xcrun', <String>[
          'simctl',
          'list',
          '-j',
          'devices',
          deviceId,
        ]),
      CockpitSystemControlAction.readDeviceInfo => _iosReadDeviceInfoCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.readFocusState => _wdaCommand(
        request,
        CockpitIosWdaAction.readFocusState,
      ),
      CockpitSystemControlAction.readNotificationState =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemActionBlocked',
          message:
              'iOS simulator delivered notification state has no stable public simctl command.',
        ),
      CockpitSystemControlAction.readSystemLogs => _iosSystemLogsCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.setLocale => _iosSetLocaleCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.setBattery =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'unsupportedSystemAction',
          message:
              'The iOS simulator cannot simulate battery state; use setStatusBar for the indicator only.',
        ),
      CockpitSystemControlAction.setConnectivity =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'unsupportedSystemAction',
          message:
              'The iOS simulator shares the host network; toggle host connectivity or use a proxy instead.',
        ),
      CockpitSystemControlAction.pressBack =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'unsupportedSystemAction',
          message:
              'iOS has no stable app-scoped Back key outside app UI semantics.',
        ),
      CockpitSystemControlAction.setNetworkSpeed ||
      CockpitSystemControlAction
          .setNetworkDelay => const CockpitResolvedSystemControlCommand.error(
        code: 'systemActionBlocked',
        message:
            'iOS network conditioning requires Network Link Conditioner or host proxy tooling; simctl cannot change real network transport.',
      ),
      CockpitSystemControlAction.readWindows =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'unsupportedSystemAction',
          message:
              'iOS simulator does not expose app windows through a stable simctl API.',
        ),
    };
  }

  CockpitResolvedSystemControlCommand _resolvePhysicalCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    switch (request.action) {
      case CockpitSystemControlAction.tap:
        return _wdaCommand(request, CockpitIosWdaAction.tap);
      case CockpitSystemControlAction.longPress:
        return _wdaCommand(request, CockpitIosWdaAction.longPress);
      case CockpitSystemControlAction.drag:
        return _wdaCommand(request, CockpitIosWdaAction.drag);
      case CockpitSystemControlAction.typeText:
        return _wdaCommand(request, CockpitIosWdaAction.typeText);
      case CockpitSystemControlAction.pressKey:
        return _wdaCommand(request, CockpitIosWdaAction.pressKey);
      case CockpitSystemControlAction.pressHome:
        return _wdaCommand(request, CockpitIosWdaAction.pressHome);
      case CockpitSystemControlAction.pressVolumeUp:
        return _wdaButtonCommand(request, 'volumeUp');
      case CockpitSystemControlAction.pressVolumeDown:
        return _wdaButtonCommand(request, 'volumeDown');
      case CockpitSystemControlAction.activateWindow:
      case CockpitSystemControlAction.recoverToApp:
        return _wdaAppCommand(request, CockpitIosWdaAction.activateApp);
      case CockpitSystemControlAction.terminateApp:
        return _wdaAppCommand(request, CockpitIosWdaAction.terminateApp);
      case CockpitSystemControlAction.installApp:
        return _iosPhysicalInstallAppCommand(request, deviceId);
      case CockpitSystemControlAction.uninstallApp:
        return _iosPhysicalUninstallAppCommand(request, deviceId);
      case CockpitSystemControlAction.dismissSystemDialog:
        return _wdaCommand(request, CockpitIosWdaAction.dismissSystemDialog);
      case CockpitSystemControlAction.dismissKeyboard:
        return _wdaCommand(request, CockpitIosWdaAction.dismissKeyboard);
      case CockpitSystemControlAction.setOrientation:
        return _wdaCommand(request, CockpitIosWdaAction.setOrientation);
      case CockpitSystemControlAction.expandNotifications:
        return _wdaCommand(request, CockpitIosWdaAction.expandNotifications);
      case CockpitSystemControlAction.expandQuickSettings:
        return _wdaCommand(request, CockpitIosWdaAction.expandQuickSettings);
      case CockpitSystemControlAction.collapseSystemUi:
        return _wdaCommand(request, CockpitIosWdaAction.collapseSystemUi);
      case CockpitSystemControlAction.tapNotification:
        return _wdaCommand(request, CockpitIosWdaAction.tapNotification);
      case CockpitSystemControlAction.resolveBlockers:
        return _iosResolveBlockersCommand(request);
      case CockpitSystemControlAction.readUiTree:
        return _wdaCommand(request, CockpitIosWdaAction.readUiTree);
      case CockpitSystemControlAction.readDeviceInfo:
        return _wdaCommand(request, CockpitIosWdaAction.readDeviceInfo);
      case CockpitSystemControlAction.readFocusState:
        return _wdaCommand(request, CockpitIosWdaAction.readFocusState);
      case CockpitSystemControlAction.preparePermissions:
      case CockpitSystemControlAction.stabilizeForScreenshot:
        return const CockpitResolvedSystemControlCommand.error(
          code: 'systemMacroAction',
          message: 'Macro actions are executed through the action service.',
        );
      case CockpitSystemControlAction.captureScreenshot:
      case CockpitSystemControlAction.startRecording:
      case CockpitSystemControlAction.stopRecording:
        return const CockpitResolvedSystemControlCommand.error(
          code: 'systemEvidenceAction',
          message: 'Evidence actions are executed through evidence adapters.',
        );
      default:
        return CockpitResolvedSystemControlCommand.error(
          code: 'systemActionBlocked',
          message:
              '${request.action.name} has no reliable iOS physical-device implementation.',
        );
    }
  }

  CockpitResolvedSystemControlCommand _wdaButtonCommand(
    CockpitSystemControlActionRequest request,
    String name,
  ) => _wdaCommand(
    CockpitSystemControlActionRequest(
      platform: request.platform,
      deviceId: request.deviceId,
      appId: request.appId,
      processId: request.processId,
      metadata: request.metadata,
      action: request.action,
      parameters: <String, Object?>{'name': name},
      timeout: request.timeout,
    ),
    CockpitIosWdaAction.pressButton,
  );

  CockpitResolvedSystemControlCommand _wdaAppCommand(
    CockpitSystemControlActionRequest request,
    CockpitIosWdaAction action,
  ) {
    final appId = _readAppId(request);
    if (!appId.isValid) {
      return CockpitResolvedSystemControlCommand.error(
        code: appId.isInvalid
            ? 'invalidSystemActionParameter'
            : 'missingSystemActionParameter',
        message: '${request.action.name} requires --app-id or appId.',
      );
    }
    return _wdaCommand(
      CockpitSystemControlActionRequest(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        metadata: request.metadata,
        action: request.action,
        parameters: <String, Object?>{'bundleId': appId.value!},
        timeout: request.timeout,
      ),
      action,
    );
  }

  CockpitResolvedSystemControlCommand _iosPhysicalInstallAppCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final appPath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'appPath',
    );
    final grantPermissions = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'grantPermissions',
    );
    if (!appPath.isValid || grantPermissions.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'installApp requires a valid appPath.',
      );
    }
    if (grantPermissions.value == true) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'unsupportedSystemActionParameter',
        message: 'iOS physical-device install cannot pre-grant permissions.',
      );
    }
    return CockpitResolvedSystemControlCommand('xcrun', <String>[
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      deviceId,
      appPath.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosPhysicalUninstallAppCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final appId = _readAppId(request);
    final keepData = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'keepData',
    );
    if (!appId.isValid || keepData.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'uninstallApp requires a valid appId.',
      );
    }
    if (keepData.value == true) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'unsupportedSystemActionParameter',
        message: 'iOS physical-device uninstall cannot retain app data.',
      );
    }
    return CockpitResolvedSystemControlCommand('xcrun', <String>[
      'devicectl',
      'device',
      'uninstall',
      'app',
      '--device',
      deviceId,
      appId.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _wdaCommand(
    CockpitSystemControlActionRequest request,
    CockpitIosWdaAction action,
  ) {
    final baseUri = _readWdaBaseUri(request.metadata);
    if (baseUri == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingWebDriverAgentEndpoint',
        message:
            'This iOS native action requires a reachable WebDriverAgent endpoint.',
      );
    }
    return CockpitIosWebDriverAgentClient.resolvedCommand(
      CockpitIosWdaCommand(
        baseUri: baseUri,
        action: action,
        stabilitySnapshot:
            action == CockpitIosWdaAction.readUiTree &&
            request.metadata[cockpitIosUiStabilitySnapshotMetadataKey] == true,
        parameters: request.parameters,
      ),
    );
  }

  CockpitResolvedSystemControlCommand _unsupportedCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return CockpitResolvedSystemControlCommand.error(
      code: 'unsupportedSystemAction',
      message: '${request.action.name} is not executable on iOS simulator.',
    );
  }

  CockpitResolvedSystemControlCommand _iosResolveBlockersCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final appId = _readAppId(request);
    final decision = cockpitReadSystemControlStringParameter(
      request.parameters,
      'decision',
      allowedValues: const <String>['accept', 'dismiss'],
    );
    final dismissKeyboard = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'dismissKeyboard',
    );
    if (appId.isInvalid || decision.isInvalid || dismissKeyboard.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'resolveBlockers requires string appId plus optional decision and dismissKeyboard parameters.',
      );
    }
    if (!appId.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'resolveBlockers requires --app-id or appId.',
      );
    }
    return _wdaCommand(
      CockpitSystemControlActionRequest(
        platform: request.platform,
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        metadata: request.metadata,
        action: request.action,
        parameters: <String, Object?>{
          ...request.parameters,
          'appId': appId.value!,
          if (request.deviceId != null) 'deviceId': request.deviceId,
          if (decision.value != null) 'decision': decision.value,
          'dismissKeyboard': dismissKeyboard.value ?? false,
        },
        timeout: request.timeout,
      ),
      CockpitIosWdaAction.resolveBlockers,
    );
  }

  CockpitResolvedSystemControlCommand _appScopedCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String appId) factory,
  ) {
    final appId = _readAppId(request);
    if (appId.isInvalid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: '${request.action.name} requires a string appId.',
      );
    }
    if (!appId.isValid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: '${request.action.name} requires --app-id or appId.',
      );
    }
    return factory(appId.value!);
  }

  CockpitResolvedSystemControlCommand _iosInstallAppCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final appPath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'appPath',
    );
    final grantPermissions = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'grantPermissions',
    );
    if (appPath.isInvalid || grantPermissions.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'installApp requires string appPath and optional boolean grantPermissions parameters.',
      );
    }
    if (!appPath.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'installApp requires an appPath parameter.',
      );
    }
    return CockpitResolvedSystemControlCommand('xcrun', <String>[
      'simctl',
      'install',
      deviceId,
      appPath.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosClearAppDataCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final appId = _readAppId(request);
    if (appId.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'clearAppData requires a string appId.',
      );
    }
    if (!appId.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'clearAppData requires --app-id or appId.',
      );
    }
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      r'container="$(xcrun simctl get_app_container "$1" "$2" data)" && find "$container" -mindepth 1 -maxdepth 1 -exec rm -rf {} + && xcrun simctl privacy "$1" reset all "$2"',
      'flutter_cockpit_ios_clear_app_data',
      deviceId,
      appId.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosResetPermissionCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final appId = _readAppId(request);
    final service = cockpitReadSystemControlStringParameter(
      request.parameters,
      'permission',
      allowedValues: CockpitSystemControlAllowedValues.iosPrivacyServices,
    );
    if (appId.isInvalid || service.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'resetPermission requires optional string appId and valid iOS simulator privacy service.',
      );
    }
    final resolvedService = service.value ?? 'all';
    return CockpitResolvedSystemControlCommand('xcrun', <String>[
      'simctl',
      'privacy',
      deviceId,
      'reset',
      resolvedService,
      if (appId.isValid) appId.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosContainerFileCommand(
    CockpitSystemControlActionRequest request,
    String deviceId, {
    required _IosContainerFileMode mode,
  }) {
    final appId = _readAppId(request);
    final sourcePath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'sourcePath',
    );
    final destinationPath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'destinationPath',
    );
    if (appId.isInvalid || sourcePath.isInvalid || destinationPath.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'iOS file transfer requires string appId, sourcePath, and destinationPath parameters.',
      );
    }
    if (!appId.isValid || !sourcePath.isValid || !destinationPath.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'iOS file transfer requires --app-id or appId plus sourcePath and destinationPath.',
      );
    }
    final script = mode == _IosContainerFileMode.push
        ? r'container="$(xcrun simctl get_app_container "$1" "$2" data)" && destination="$4"; case "$destination" in /*) target="$destination" ;; *) target="$container/$destination" ;; esac && mkdir -p "$(dirname "$target")" && cp -R "$3" "$target"'
        : r'container="$(xcrun simctl get_app_container "$1" "$2" data)" && source="$3"; case "$source" in /*) input="$source" ;; *) input="$container/$source" ;; esac && mkdir -p "$(dirname "$4")" && cp -R "$input" "$4"';
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      script,
      'flutter_cockpit_ios_container_file',
      deviceId,
      appId.value!,
      sourcePath.value!,
      destinationPath.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosAddMediaCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final sourcePath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'sourcePath',
    );
    final destinationPath = cockpitReadSystemControlStringParameter(
      request.parameters,
      'destinationPath',
    );
    if (sourcePath.isInvalid || destinationPath.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'addMedia requires string sourcePath and optional destinationPath parameters.',
      );
    }
    if (!sourcePath.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'addMedia requires a sourcePath parameter.',
      );
    }
    if (destinationPath.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'unsupportedSystemActionParameter',
        message: 'iOS addMedia does not use destinationPath.',
      );
    }
    return CockpitResolvedSystemControlCommand('xcrun', <String>[
      'simctl',
      'addmedia',
      deviceId,
      sourcePath.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosSystemLogsCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final lastMinutes = cockpitReadSystemControlIntParameter(
      request.parameters,
      'lastMinutes',
      minimum: 1,
      maximum: 60,
    );
    final lines = cockpitReadSystemControlIntParameter(
      request.parameters,
      'lines',
      minimum: 1,
      maximum: 5000,
    );
    final processName = cockpitReadSystemControlStringParameter(
      request.parameters,
      'processName',
      // Quotes and backslashes would break the NSPredicate string literal.
      pattern: cockpitSystemControlProcessNamePattern,
    );
    if (lastMinutes.isInvalid || lines.isInvalid || processName.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'readSystemLogs accepts integer lastMinutes (1-60), integer lines (1-5000), and optional string processName without quotes or backslashes.',
      );
    }
    final minutes = lastMinutes.value ?? 2;
    final lineCount = lines.value ?? 200;
    // Tail keeps unified-log output bounded for AI consumption.
    if (processName.isValid) {
      return CockpitResolvedSystemControlCommand('sh', <String>[
        '-c',
        r'xcrun simctl spawn "$1" log show --style compact --last "$2" --predicate "process == \"$3\"" | tail -n "$4"',
        'flutter_cockpit_ios_logs',
        deviceId,
        '${minutes}m',
        processName.value!,
        '$lineCount',
      ]);
    }
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      r'xcrun simctl spawn "$1" log show --style compact --last "$2" | tail -n "$3"',
      'flutter_cockpit_ios_logs',
      deviceId,
      '${minutes}m',
      '$lineCount',
    ]);
  }

  CockpitResolvedSystemControlCommand _iosSetLocaleCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final locale = cockpitReadSystemControlStringParameter(
      request.parameters,
      'locale',
    );
    final language = cockpitReadSystemControlStringParameter(
      request.parameters,
      'language',
    );
    if (locale.isInvalid || language.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setLocale requires a string locale and optional string language.',
      );
    }
    if (!locale.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'setLocale requires a locale parameter such as zh_CN.',
      );
    }
    final resolvedLocale = locale.value!;
    final resolvedLanguage =
        language.value ?? resolvedLocale.replaceAll('_', '-');
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      r'xcrun simctl spawn "$1" defaults write .GlobalPreferences AppleLocale -string "$2" && xcrun simctl spawn "$1" defaults write .GlobalPreferences AppleLanguages -array "$3"',
      'flutter_cockpit_ios_locale',
      deviceId,
      resolvedLocale,
      resolvedLanguage,
    ]);
  }

  CockpitResolvedSystemControlCommand _iosReadDeviceInfoCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final appId = _readAppId(request);
    if (appId.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'readDeviceInfo requires optional string appId.',
      );
    }
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      r'xcrun simctl list -j devices "$1"; xcrun simctl spawn "$1" defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true; xcrun simctl spawn "$1" defaults read NSGlobalDomain AppleContentSizeCategory 2>/dev/null || true; if [ -n "$2" ]; then xcrun simctl appinfo "$1" "$2"; fi',
      'flutter_cockpit_ios_device_info',
      deviceId,
      appId.value ?? '',
    ]);
  }

  CockpitResolvedSystemControlCommand _iosOpenSystemSettingsCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String url) factory,
  ) {
    final settingsAction = cockpitReadSystemControlStringParameter(
      request.parameters,
      'settingsAction',
    );
    if (settingsAction.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'openSystemSettings requires a string settingsAction.',
      );
    }
    final value = settingsAction.value;
    if (value == null || value.trim().isEmpty) {
      return factory('App-Prefs:');
    }
    return factory(value);
  }

  CockpitResolvedSystemControlCommand _iosPostNotificationCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(
      String appId,
      String payloadJson,
    )
    factory,
  ) {
    final appId = _readAppId(request);
    if (appId.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'postNotification requires a string appId.',
      );
    }
    if (!appId.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'postNotification requires --app-id or appId.',
      );
    }
    final payloadJson = cockpitReadSystemControlStringParameter(
      request.parameters,
      'payloadJson',
    );
    if (payloadJson.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'postNotification requires a string payloadJson.',
      );
    }
    if (payloadJson.isValid) {
      return factory(appId.value!, payloadJson.value!);
    }
    final title = cockpitReadSystemControlStringParameter(
      request.parameters,
      'title',
    );
    final body = cockpitReadSystemControlStringParameter(
      request.parameters,
      'body',
    );
    if (title.isInvalid || body.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'postNotification accepts string title, body, and payloadJson.',
      );
    }
    if (!title.isValid && !body.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'postNotification requires payloadJson, title, or body.',
      );
    }
    return factory(
      appId.value!,
      _iosNotificationPayloadJson(title.value, body.value),
    );
  }

  CockpitResolvedSystemControlCommand _permissionCommand(
    CockpitSystemControlActionRequest request, {
    required String actionName,
    required CockpitResolvedSystemControlCommand Function(
      String appId,
      String service,
    )
    factory,
  }) {
    final appId = _readAppId(request);
    if (appId.isInvalid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: '$actionName requires a string appId.',
      );
    }
    if (!appId.isValid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: '$actionName requires --app-id or appId.',
      );
    }
    final service = cockpitReadSystemControlStringParameter(
      request.parameters,
      'permission',
      allowedValues: CockpitSystemControlAllowedValues.iosPrivacyServices,
    );
    if (service.isInvalid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: '$actionName requires a valid iOS simulator privacy service.',
      );
    }
    if (!service.isValid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: '$actionName requires a permission or service parameter.',
      );
    }
    return factory(appId.value!, service.value!);
  }

  CockpitResolvedSystemControlCommand _iosSetStatusBarCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(List<String> args) factory,
  ) {
    final args = <String>[];
    String? errorMessage;
    void addString(
      String parameterName,
      String flagName, {
      List<String> allowedValues = const <String>[],
    }) {
      final value = cockpitReadSystemControlStringParameter(
        request.parameters,
        parameterName,
        allowedValues: allowedValues,
      );
      if (!value.isPresent) {
        return;
      }
      if (value.isInvalid) {
        errorMessage = '$parameterName has an unsupported value.';
        return;
      }
      args.addAll(<String>['--$flagName', value.value!]);
    }

    void addInt(String parameterName, String flagName, int min, int max) {
      final value = cockpitReadSystemControlIntParameter(
        request.parameters,
        parameterName,
        minimum: min,
        maximum: max,
      );
      if (!value.isPresent) {
        return;
      }
      if (value.isInvalid) {
        errorMessage =
            '$parameterName must be an integer between $min and $max.';
        return;
      }
      args.addAll(<String>['--$flagName', '${value.value}']);
    }

    addString('time', 'time');
    addString(
      'dataNetwork',
      'dataNetwork',
      allowedValues: CockpitSystemControlAllowedValues.iosStatusBarDataNetworks,
    );
    addString(
      'wifiMode',
      'wifiMode',
      allowedValues: CockpitSystemControlAllowedValues.iosStatusBarWifiModes,
    );
    addInt('wifiBars', 'wifiBars', 0, 3);
    addString(
      'cellularMode',
      'cellularMode',
      allowedValues:
          CockpitSystemControlAllowedValues.iosStatusBarCellularModes,
    );
    addInt('cellularBars', 'cellularBars', 0, 4);
    addString('operatorName', 'operatorName');
    addString(
      'batteryState',
      'batteryState',
      allowedValues:
          CockpitSystemControlAllowedValues.iosStatusBarBatteryStates,
    );
    addInt('batteryLevel', 'batteryLevel', 0, 100);
    if (errorMessage != null) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: errorMessage!,
      );
    }
    if (args.isEmpty) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'setStatusBar requires at least one status bar parameter such as time, dataNetwork, wifiBars, or batteryLevel.',
      );
    }
    return factory(args);
  }

  CockpitSystemControlStringParameter _readAppId(
    CockpitSystemControlActionRequest request,
  ) {
    final appId = request.appId?.trim();
    if (appId != null && appId.isNotEmpty) {
      return CockpitSystemControlStringParameter.valid(appId);
    }
    return cockpitReadFirstSystemControlStringParameter(
      request.parameters,
      const <String>['appId'],
    );
  }

  CockpitResolvedSystemControlCommand _iosSetAppearanceCommand(
    String appearance,
    CockpitResolvedSystemControlCommand Function(String mode) factory,
  ) {
    final mode = switch (appearance.trim().toLowerCase()) {
      'dark' => 'dark',
      'light' => 'light',
      _ => null,
    };
    if (mode == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'setAppearance requires appearance light or dark on iOS.',
      );
    }
    return factory(mode);
  }

  String _formatCoordinate(double value) {
    final text = value.toStringAsFixed(6);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _iosNotificationPayloadJson(String? title, String? body) {
    final alert = <String, Object?>{
      if (title != null && title.trim().isNotEmpty) 'title': title,
      if (body != null && body.trim().isNotEmpty) 'body': body,
    };
    return jsonEncode(<String, Object?>{
      'aps': <String, Object?>{
        'alert': alert.isEmpty ? (body ?? title ?? '') : alert,
      },
    });
  }

  bool _looksLikeIosSimulatorDeviceId(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) {
      return false;
    }
    // Match the service's case-insensitive handling of the simctl
    // "booted" alias.
    if (deviceId.toLowerCase() == 'booted') {
      return true;
    }
    return RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    ).hasMatch(deviceId);
  }

  Uri? _readWdaBaseUri(Map<String, Object?> metadata) {
    final value = metadata['wdaUrl'];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  List<String> _wdaRequires({
    required bool hasEndpoint,
    required bool reachable,
    String deviceRequirement = 'booted simulator',
  }) {
    if (!hasEndpoint) {
      return <String>[
        deviceRequirement,
        'reachable WebDriverAgent endpoint (default probe http://127.0.0.1:8100, --wda-url, or FLUTTER_COCKPIT_IOS_WDA_URL)',
      ];
    }
    if (!reachable) {
      return <String>[deviceRequirement, 'reachable WebDriverAgent endpoint'];
    }
    return <String>[deviceRequirement, 'WebDriverAgent endpoint'];
  }
}

List<String> _iosSimulatorShellCommand(List<String> command) {
  if (command.first.startsWith('/')) {
    return command;
  }
  return <String>['/bin/sh', '-lc', _shellCommandLine(command)];
}

String _shellCommandLine(List<String> command) {
  return command.map(_shellSingleQuoted).join(' ');
}

String _shellSingleQuoted(String value) {
  if (value.isEmpty) {
    return "''";
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

enum _IosContainerFileMode { push, pull }
