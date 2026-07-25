import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../cockpit_system_control_action.dart';
import '../cockpit_system_control_adapter.dart';
import '../cockpit_system_control_parameters.dart';
import '../cockpit_system_control_profile.dart';

final class CockpitAndroidSystemControlAdapter
    implements CockpitSystemControlAdapter {
  const CockpitAndroidSystemControlAdapter();

  @override
  String get platform => 'android';

  @override
  CockpitSystemControlProfile describe(
    CockpitSystemControlTargetContext target,
  ) {
    final hasDeviceId =
        target.deviceId != null && target.deviceId!.trim().isNotEmpty;
    final deviceReachable = target.metadata['androidDeviceReachable'];
    final deviceAvailable =
        hasDeviceId && (deviceReachable is! bool || deviceReachable);
    final availability = deviceAvailable
        ? CockpitSystemControlAvailability.available
        : CockpitSystemControlAvailability.blocked;
    final isEmulator = (target.deviceId ?? '').startsWith('emulator-');
    final emulatorAvailability = isEmulator && deviceAvailable
        ? CockpitSystemControlAvailability.available
        : CockpitSystemControlAvailability.blocked;
    final deviceRequires = _deviceRequires(target);
    final emulatorRequires = _emulatorRequires(target);
    return CockpitSystemControlProfile(
      platform: platform,
      deviceId: target.deviceId,
      appId: target.appId,
      processId: target.processId,
      adapter: 'android.adb',
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
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.tap',
          requires: deviceRequires,
          limitations: <String>['coordinate input has no semantic locator'],
          parameters: CockpitSystemControlParameterSets.coordinate,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.longPress,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.swipe.hold',
          requires: deviceRequires,
          limitations: <String>['coordinate input has no semantic locator'],
          parameters: CockpitSystemControlParameterSets.longPress,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.drag,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.swipe',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.drag,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.typeText,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.text',
          requires: deviceRequires,
          limitations: <String>['text must be escaped for adb input'],
          parameters: CockpitSystemControlParameterSets.text,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pressKey,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent',
          requires: <String>[...deviceRequires, 'key name'],
          parameters: CockpitSystemControlParameterSets.key,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pressBack,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent.KEYCODE_BACK',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pressHome,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent.KEYCODE_HOME',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pressVolumeUp,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent.KEYCODE_VOLUME_UP',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pressVolumeDown,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent.KEYCODE_VOLUME_DOWN',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pressVolumeMute,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent.KEYCODE_VOLUME_MUTE',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.activateWindow,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.monkey.launcher',
          requires: <String>[...deviceRequires, 'package id'],
          parameters: CockpitSystemControlParameterSets.androidApp,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.terminateApp,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.am.force-stop',
          requires: <String>[...deviceRequires, 'package id'],
          parameters: CockpitSystemControlParameterSets.androidApp,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.installApp,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.install',
          requires: <String>[...deviceRequires, 'apk path'],
          parameters: CockpitSystemControlParameterSets.installApp,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.uninstallApp,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.uninstall',
          requires: <String>[...deviceRequires, 'package id'],
          parameters: CockpitSystemControlParameterSets.uninstallApp,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.clearAppData,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.pm.clear',
          requires: <String>[...deviceRequires, 'package id'],
          limitations: <String>[
            'Clears all app data and cache on the emulator/device.',
          ],
          parameters: CockpitSystemControlParameterSets.androidApp,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.dismissSystemDialog,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.uiautomator.permission-button',
          requires: deviceRequires,
          limitations: <String>[
            'Matches common Android permission and system dialog button ids/text; custom OEM dialogs may still require coordinate or semantic fallback.',
          ],
          parameters: CockpitSystemControlParameterSets.systemDialogDecision,
          fallbackActions: <CockpitSystemControlAction>[
            CockpitSystemControlAction.pressBack,
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.dismissKeyboard,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.input.keyevent.KEYCODE_BACK',
          requires: deviceRequires,
          limitations: <String>[
            'Back dismisses the current IME when it is visible; otherwise it may navigate back.',
          ],
          fallbackActions: <CockpitSystemControlAction>[
            CockpitSystemControlAction.pressBack,
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.grantPermission,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.pm.grant',
          requires: <String>[
            ...deviceRequires,
            'package id',
            'permission name',
          ],
          parameters: CockpitSystemControlParameterSets.androidGrantPermission,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.revokePermission,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.pm.revoke',
          requires: <String>[
            ...deviceRequires,
            'package id',
            'permission name',
          ],
          parameters: CockpitSystemControlParameterSets.androidRevokePermission,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.resetPermission,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.pm.reset-permissions-or-revoke',
          requires: <String>[...deviceRequires, 'package id'],
          limitations: <String>[
            'When permission is omitted, pm reset-permissions support depends on Android API level. Prefer explicit permission for deterministic app-scoped reset.',
          ],
          parameters: CockpitSystemControlParameterSets.androidResetPermission,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.preparePermissions,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'macro.adb.permissions+recover',
          requires: <String>[...deviceRequires, 'package id'],
          limitations: <String>[
            'Executes grant, revoke, or reset for each declared permission and can restore app focus afterwards.',
          ],
          parameters: CockpitSystemControlParameterSets.preparePermissions,
          fallbackActions: <CockpitSystemControlAction>[
            CockpitSystemControlAction.grantPermission,
            CockpitSystemControlAction.revokePermission,
            CockpitSystemControlAction.resetPermission,
            CockpitSystemControlAction.recoverToApp,
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.openUrl,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.am.start.VIEW',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.url,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.openSystemSettings,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.am.start.android.settings.SETTINGS',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.androidSystemSettings,
          limitations: <String>[
            'Use settingsAction for a custom android.settings.* action; default opens the main Settings app.',
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setAppearance,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.cmd.uimode.night',
          requires: <String>[...deviceRequires, 'appearance mode'],
          limitations: <String>[
            'Uses Android UiModeManager night mode; OEM behavior can vary.',
          ],
          parameters: CockpitSystemControlParameterSets.androidAppearance,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setContentSize,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.settings.put.system.font_scale',
          requires: <String>[...deviceRequires, 'content size or font scale'],
          limitations: <String>[
            'Applies the system font scale and can affect all apps on the device.',
          ],
          parameters: CockpitSystemControlParameterSets.androidContentSize,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setLocation,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: emulatorAvailability,
          strategy: 'adb.emu.geo.fix',
          requires: <String>[...emulatorRequires, 'latitude', 'longitude'],
          limitations: <String>[
            'adb emu geo fix is emulator-only; physical devices require app-specific mock-location setup.',
          ],
          parameters: CockpitSystemControlParameterSets.location,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setOrientation,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.settings.user_rotation',
          requires: <String>[...deviceRequires, 'orientation'],
          limitations: <String>[
            'Changes the device-wide rotation setting; use auto to restore sensor rotation.',
          ],
          parameters: CockpitSystemControlParameterSets.androidOrientation,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setNetworkSpeed,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: emulatorAvailability,
          strategy: 'adb.emu.network.speed',
          requires: <String>[...emulatorRequires, 'network speed'],
          limitations: <String>[
            'Android emulator console network speed is emulator-only.',
          ],
          parameters: CockpitSystemControlParameterSets.androidNetworkSpeed,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setNetworkDelay,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: emulatorAvailability,
          strategy: 'adb.emu.network.delay',
          requires: <String>[...emulatorRequires, 'network delay'],
          limitations: <String>[
            'Android emulator console network delay is emulator-only.',
          ],
          parameters: CockpitSystemControlParameterSets.androidNetworkDelay,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setStatusBar,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.systemui.demo-mode.override',
          requires: <String>[
            ...deviceRequires,
            'SystemUI demo mode (sysui_demo_allowed)',
          ],
          limitations: <String>[
            'Uses SystemUI demo mode; some OEM system UIs ignore demo-mode broadcasts.',
          ],
          parameters: CockpitSystemControlParameterSets.androidStatusBar,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.clearStatusBar,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.systemui.demo-mode.exit',
          requires: deviceRequires,
          limitations: <String>[
            'Exits SystemUI demo mode and restores live status bar content.',
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.expandNotifications,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.cmd.statusbar.expand-notifications',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.expandQuickSettings,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.cmd.statusbar.expand-settings',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.collapseSystemUi,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.cmd.statusbar.collapse',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.postNotification,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.cmd.notification.post',
          requires: deviceRequires,
          limitations: <String>[
            'Posts from the Android shell package; use app notification flows to validate production notification handling.',
          ],
          parameters: CockpitSystemControlParameterSets.androidNotification,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.clearNotifications,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.cmd.statusbar.collapse',
          requires: deviceRequires,
          limitations: <String>[
            'Android shell has no stable public clear-all-notifications command; this collapses system UI after notification assertions.',
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.tapNotification,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.statusbar.expand+uiautomator.notification-tap',
          requires: <String>[...deviceRequires, 'visible notification text'],
          limitations: <String>[
            'Matches visible notification text after expanding the shade; OEM notification layouts may require coordinate fallback.',
          ],
          parameters: CockpitSystemControlParameterSets.tapNotification,
          fallbackActions: <CockpitSystemControlAction>[
            CockpitSystemControlAction.expandNotifications,
            CockpitSystemControlAction.tap,
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.recoverToApp,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.statusbar.collapse+monkey.launcher',
          requires: <String>[...deviceRequires, 'package id'],
          limitations: <String>[
            'Brings the app launcher activity forward without clearing app data or killing the process.',
          ],
          parameters: CockpitSystemControlParameterSets.recoverToApp,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.resolveBlockers,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.dismiss-dialog+keyboard+statusbar+recover-app',
          requires: <String>[...deviceRequires, 'package id'],
          limitations: <String>[
            'Handles common permission dialogs, IME focus, and notification shade blockers before restoring the app.',
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
          availability: availability,
          strategy: 'macro.adb.stabilize-screenshot',
          requires: deviceRequires,
          limitations: <String>[
            'Executes available keyboard, system UI, orientation, appearance, status bar, and app recovery actions before screenshot evidence.',
          ],
          parameters: CockpitSystemControlParameterSets.stabilizeForScreenshot,
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
          availability: CockpitSystemControlAvailability.blocked,
          strategy: 'android-clipboard-requires-app-or-api-specific-helper',
          requires: <String>[
            'app instrumentation or API-specific clipboard helper',
          ],
          limitations: <String>[
            'Android does not expose a stable adb clipboard command across supported API levels.',
          ],
        ),
        const CockpitSystemControlCapability(
          action: CockpitSystemControlAction.getClipboard,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: CockpitSystemControlAvailability.blocked,
          strategy: 'android-clipboard-requires-app-or-api-specific-helper',
          requires: <String>[
            'app instrumentation or API-specific clipboard helper',
          ],
          limitations: <String>[
            'Android does not expose a stable adb clipboard command across supported API levels.',
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pushFile,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.push',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.fileTransfer,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.pullFile,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.pull',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.fileTransfer,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.addMedia,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.push+media-scan',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.androidAddMedia,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.captureScreenshot,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.exec-out.screencap',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.screenshot,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.startRecording,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.screenrecord',
          requires: deviceRequires,
          limitations: <String>['Android screenrecord has duration limits'],
          parameters: CockpitSystemControlParameterSets.startRecording,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.stopRecording,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.screenrecord.stop-and-pull',
          requires: <String>[...deviceRequires, 'active recording session'],
          parameters: CockpitSystemControlParameterSets.stopRecording,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readUiTree,
          plane: CockpitPlaneKind.nativeUiPlane,
          availability: availability,
          strategy: 'adb.shell.uiautomator.dump',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readProcessList,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.ps',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readWindows,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.dumpsys.window.windows',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readSystemState,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.dumpsys',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readDeviceInfo,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.getprop+wm+settings',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readFocusState,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.dumpsys.window+input_method',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readNotificationState,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell.dumpsys.notification',
          requires: deviceRequires,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.readSystemLogs,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.logcat.tail',
          requires: deviceRequires,
          limitations: <String>[
            'Reads recent logcat output; pass packageId to scope to the running app process.',
          ],
          parameters: CockpitSystemControlParameterSets.androidSystemLogs,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setBattery,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.dumpsys.battery',
          requires: deviceRequires,
          limitations: <String>[
            'Simulated battery state persists until setBattery runs with reset=true.',
          ],
          parameters: CockpitSystemControlParameterSets.androidBattery,
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setConnectivity,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.svc+cmd.connectivity',
          requires: deviceRequires,
          limitations: <String>[
            'Changes device-wide connectivity; airplane mode toggling requires Android 11+.',
          ],
          parameters: CockpitSystemControlParameterSets.androidConnectivity,
        ),
        const CockpitSystemControlCapability(
          action: CockpitSystemControlAction.setLocale,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: CockpitSystemControlAvailability.blocked,
          strategy: 'android-locale-requires-root-or-app-override',
          requires: <String>[
            'rooted build or app-side locale override (e.g. dart-define / in-app setting)',
          ],
          limitations: <String>[
            'Android exposes no stable unrooted adb command to change the device locale.',
          ],
        ),
        CockpitSystemControlCapability(
          action: CockpitSystemControlAction.runShell,
          plane: CockpitPlaneKind.deviceSystemPlane,
          availability: availability,
          strategy: 'adb.shell',
          requires: deviceRequires,
          parameters: CockpitSystemControlParameterSets.shellCommand,
        ),
      ],
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
        message: 'Android system actions require --device-id.',
      );
    }

    List<String> adbShell(List<String> shellArgs) {
      return <String>['-s', deviceId, 'shell', ...shellArgs];
    }

    // adb's shell service space-joins its arguments and the device shell
    // re-parses the joined string, so a script must travel as one pre-quoted
    // word or only its first line would reach the inner `sh -c`.
    List<String> adbShellScript(String script) {
      return adbShell(<String>['sh', '-c', _shellSingleQuoted(script)]);
    }

    return switch (request.action) {
      CockpitSystemControlAction.tap => cockpitCoordinateCommand(
        request,
        (x, y) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['input', 'tap', '$x', '$y']),
        ),
      ),
      CockpitSystemControlAction.longPress => cockpitLongPressCommand(
        request,
        (x, y, durationMs) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>[
            'input',
            'swipe',
            '$x',
            '$y',
            '$x',
            '$y',
            '$durationMs',
          ]),
        ),
      ),
      CockpitSystemControlAction.drag => cockpitDragCommand(request, (
        startX,
        startY,
        endX,
        endY,
        durationMs,
      ) {
        return CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>[
            'input',
            'swipe',
            '$startX',
            '$startY',
            '$endX',
            '$endY',
            '$durationMs',
          ]),
        );
      }),
      CockpitSystemControlAction.typeText => cockpitTextCommand(
        request,
        'text',
        (text) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['input', 'text', _escapeAdbText(text)]),
        ),
      ),
      CockpitSystemControlAction.pressKey => cockpitTextCommand(
        request,
        'key',
        (key) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['input', 'keyevent', _normalizeAndroidKey(key)]),
        ),
      ),
      CockpitSystemControlAction.pressBack =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['input', 'keyevent', 'KEYCODE_BACK']),
        ),
      CockpitSystemControlAction.pressHome =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['input', 'keyevent', 'KEYCODE_HOME']),
        ),
      CockpitSystemControlAction.pressVolumeUp =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['input', 'keyevent', 'KEYCODE_VOLUME_UP']),
        ),
      CockpitSystemControlAction.pressVolumeDown =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['input', 'keyevent', 'KEYCODE_VOLUME_DOWN']),
        ),
      CockpitSystemControlAction.pressVolumeMute =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['input', 'keyevent', 'KEYCODE_VOLUME_MUTE']),
        ),
      CockpitSystemControlAction.activateWindow => _packageCommand(
        request,
        (packageId) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>[
            'monkey',
            '-p',
            packageId,
            '-c',
            'android.intent.category.LAUNCHER',
            '1',
          ]),
        ),
      ),
      CockpitSystemControlAction.terminateApp => _packageCommand(
        request,
        (packageId) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['am', 'force-stop', packageId]),
        ),
      ),
      CockpitSystemControlAction.installApp => _androidInstallAppCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.uninstallApp => _androidUninstallAppCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.clearAppData => _packageCommand(
        request,
        (packageId) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['pm', 'clear', packageId]),
        ),
      ),
      CockpitSystemControlAction.openUrl => cockpitTextCommand(
        request,
        'url',
        (url) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>[
            'am',
            'start',
            '-a',
            'android.intent.action.VIEW',
            '-d',
            url,
          ]),
        ),
      ),
      CockpitSystemControlAction.openSystemSettings =>
        _androidOpenSystemSettingsCommand(
          request,
          (settingsAction) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShell(<String>['am', 'start', '-a', settingsAction]),
          ),
        ),
      CockpitSystemControlAction.setAppearance => cockpitTextCommand(
        request,
        'appearance',
        (appearance) => _androidSetAppearanceCommand(
          appearance,
          (mode) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShell(<String>['cmd', 'uimode', 'night', mode]),
          ),
        ),
      ),
      CockpitSystemControlAction.setContentSize =>
        _androidSetContentSizeCommand(
          request,
          (fontScale) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShell(<String>[
              'settings',
              'put',
              'system',
              'font_scale',
              fontScale,
            ]),
          ),
        ),
      CockpitSystemControlAction.setLocation => cockpitLocationCommand(request, (
        latitude,
        longitude,
        altitude,
      ) {
        if (!deviceId.startsWith('emulator-')) {
          return const CockpitResolvedSystemControlCommand.error(
            code: 'systemActionBlocked',
            message:
                'Android setLocation is available only for emulator-* device ids.',
          );
        }
        return CockpitResolvedSystemControlCommand('adb', <String>[
          '-s',
          deviceId,
          'emu',
          'geo',
          'fix',
          _formatCoordinate(longitude),
          _formatCoordinate(latitude),
          if (altitude != null) _formatCoordinate(altitude),
        ]);
      }),
      CockpitSystemControlAction.setOrientation =>
        _androidSetOrientationCommand(
          request,
          (script) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShellScript(script),
          ),
        ),
      CockpitSystemControlAction.setNetworkSpeed =>
        _androidEmulatorNetworkCommand(
          request,
          deviceId: deviceId,
          parameterName: 'networkSpeed',
          commandName: 'speed',
          allowedValues: const <String>[
            'gsm',
            'hscsd',
            'gprs',
            'edge',
            'umts',
            'hsdpa',
            'lte',
            'evdo',
            'full',
          ],
        ),
      CockpitSystemControlAction.setNetworkDelay =>
        _androidEmulatorNetworkCommand(
          request,
          deviceId: deviceId,
          parameterName: 'networkDelay',
          commandName: 'delay',
          allowedValues: const <String>['gprs', 'edge', 'umts', 'none'],
        ),
      CockpitSystemControlAction.setStatusBar => _androidSetStatusBarCommand(
        request,
        (script) =>
            CockpitResolvedSystemControlCommand('adb', adbShellScript(script)),
      ),
      CockpitSystemControlAction.clearStatusBar =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>[
            'am',
            'broadcast',
            '-a',
            'com.android.systemui.demo',
            '-e',
            'command',
            'exit',
          ]),
        ),
      CockpitSystemControlAction.expandNotifications =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['cmd', 'statusbar', 'expand-notifications']),
        ),
      CockpitSystemControlAction.expandQuickSettings =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['cmd', 'statusbar', 'expand-settings']),
        ),
      CockpitSystemControlAction.collapseSystemUi ||
      CockpitSystemControlAction.clearNotifications =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['cmd', 'statusbar', 'collapse']),
        ),
      CockpitSystemControlAction.tapNotification =>
        _androidTapNotificationCommand(
          request,
          (script) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShellScript(script),
          ),
        ),
      CockpitSystemControlAction.recoverToApp => _packageCommand(
        request,
        (packageId) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShellScript(_androidRecoverToAppScript(packageId)),
        ),
      ),
      CockpitSystemControlAction.resolveBlockers =>
        _androidResolveBlockersCommand(
          request,
          (script) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShellScript(script),
          ),
        ),
      CockpitSystemControlAction.preparePermissions ||
      CockpitSystemControlAction.stabilizeForScreenshot =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemMacroAction',
          message: 'Macro actions are executed through the action service.',
        ),
      CockpitSystemControlAction.postNotification =>
        _androidPostNotificationCommand(
          request,
          (args) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShell(<String>['cmd', 'notification', 'post', ...args]),
          ),
        ),
      CockpitSystemControlAction.setClipboard ||
      CockpitSystemControlAction
          .getClipboard => const CockpitResolvedSystemControlCommand.error(
        code: 'systemActionBlocked',
        message:
            'Android clipboard actions require app instrumentation or an API-specific clipboard helper.',
      ),
      CockpitSystemControlAction.pushFile => _fileTransferCommand(
        request,
        (sourcePath, destinationPath) => CockpitResolvedSystemControlCommand(
          'adb',
          <String>['-s', deviceId, 'push', sourcePath, destinationPath],
        ),
      ),
      CockpitSystemControlAction.pullFile => _fileTransferCommand(
        request,
        (sourcePath, destinationPath) => CockpitResolvedSystemControlCommand(
          'adb',
          <String>['-s', deviceId, 'pull', sourcePath, destinationPath],
        ),
      ),
      CockpitSystemControlAction.addMedia => _androidAddMediaCommand(
        request,
        deviceId,
      ),
      CockpitSystemControlAction.grantPermission => _grantPermissionCommand(
        request,
        (packageId, permission) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['pm', 'grant', packageId, permission]),
        ),
      ),
      CockpitSystemControlAction.revokePermission => _grantPermissionCommand(
        request,
        (packageId, permission) => CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(<String>['pm', 'revoke', packageId, permission]),
        ),
      ),
      CockpitSystemControlAction.resetPermission =>
        _androidResetPermissionCommand(
          request,
          (packageId, permission) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShell(<String>[
              if (permission == null) ...<String>[
                'pm',
                'reset-permissions',
              ] else ...<String>['pm', 'revoke', packageId, permission],
            ]),
          ),
        ),
      CockpitSystemControlAction.dismissSystemDialog =>
        _androidDismissSystemDialogCommand(
          request,
          (script) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShellScript(script),
          ),
        ),
      CockpitSystemControlAction.dismissKeyboard =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['input', 'keyevent', 'KEYCODE_BACK']),
        ),
      CockpitSystemControlAction.captureScreenshot =>
        CockpitResolvedSystemControlCommand('adb', <String>[
          '-s',
          deviceId,
          'exec-out',
          'screencap',
          '-p',
        ]),
      CockpitSystemControlAction.startRecording ||
      CockpitSystemControlAction.stopRecording =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemEvidenceAction',
          message: 'Recording actions are executed through recording adapters.',
        ),
      CockpitSystemControlAction.readUiTree =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShellScript(
            'uiautomator dump /sdcard/window.xml >/dev/null && cat /sdcard/window.xml && rm /sdcard/window.xml',
          ),
        ),
      CockpitSystemControlAction.readProcessList =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['ps', '-A']),
        ),
      CockpitSystemControlAction.readWindows =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['dumpsys', 'window', 'windows']),
        ),
      CockpitSystemControlAction.readSystemState =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['dumpsys', 'window']),
        ),
      CockpitSystemControlAction.readDeviceInfo =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShellScript(
            'printf "serial=" && getprop ro.serialno; printf "model=" && getprop ro.product.model; printf "sdk=" && getprop ro.build.version.sdk; printf "release=" && getprop ro.build.version.release; wm size; wm density; settings get system font_scale; settings get secure default_input_method; dumpsys input_method | grep -E "mInputShown|InputShown" | head -n 5 || true',
          ),
        ),
      CockpitSystemControlAction.readFocusState =>
        CockpitResolvedSystemControlCommand(
          'adb',
          // Focus fields moved out of `dumpsys window windows` on modern
          // Android; the full `dumpsys window` output still carries them.
          adbShellScript(
            'printf "windowFocus=\\n"; dumpsys window | grep -E "mCurrentFocus|mFocusedApp|mFocusedWindow|imeLayeringTarget|mInputMethodTarget" | head -n 20 || true; printf "\\ninputMethod=\\n"; dumpsys input_method | grep -E "mInputShown|InputShown|mServedView|mCurrentFocus|mCurMethodId" | head -n 40 || true',
          ),
        ),
      CockpitSystemControlAction.readNotificationState =>
        CockpitResolvedSystemControlCommand(
          'adb',
          adbShell(const <String>['dumpsys', 'notification']),
        ),
      CockpitSystemControlAction.readSystemLogs => _androidSystemLogsCommand(
        request,
        (script) =>
            CockpitResolvedSystemControlCommand('adb', adbShellScript(script)),
      ),
      CockpitSystemControlAction.setBattery => _androidSetBatteryCommand(
        request,
        (script) =>
            CockpitResolvedSystemControlCommand('adb', adbShellScript(script)),
      ),
      CockpitSystemControlAction.setConnectivity =>
        _androidSetConnectivityCommand(
          request,
          (script) => CockpitResolvedSystemControlCommand(
            'adb',
            adbShellScript(script),
          ),
        ),
      CockpitSystemControlAction.setLocale =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemActionBlocked',
          message:
              'Android device locale changes require a rooted build or an app-side locale override.',
        ),
      CockpitSystemControlAction.runShell => cockpitShellCommand(
        request,
        (command) => CockpitResolvedSystemControlCommand('adb', <String>[
          '-s',
          deviceId,
          'shell',
          ...command,
        ]),
      ),
    };
  }

  CockpitResolvedSystemControlCommand _androidSetStatusBarCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final time = cockpitReadSystemControlStringParameter(
      request.parameters,
      'time',
    );
    final dataNetwork = cockpitReadSystemControlStringParameter(
      request.parameters,
      'dataNetwork',
      allowedValues:
          CockpitSystemControlAllowedValues.androidStatusBarDataNetworks,
    );
    final wifiMode = cockpitReadSystemControlStringParameter(
      request.parameters,
      'wifiMode',
      allowedValues:
          CockpitSystemControlAllowedValues.androidStatusBarSignalModes,
    );
    final wifiBars = cockpitReadSystemControlIntParameter(
      request.parameters,
      'wifiBars',
      minimum: 0,
      maximum: 4,
    );
    final cellularMode = cockpitReadSystemControlStringParameter(
      request.parameters,
      'cellularMode',
      allowedValues:
          CockpitSystemControlAllowedValues.androidStatusBarSignalModes,
    );
    final cellularBars = cockpitReadSystemControlIntParameter(
      request.parameters,
      'cellularBars',
      minimum: 0,
      maximum: 4,
    );
    final batteryState = cockpitReadSystemControlStringParameter(
      request.parameters,
      'batteryState',
      allowedValues:
          CockpitSystemControlAllowedValues.iosStatusBarBatteryStates,
    );
    final batteryLevel = cockpitReadSystemControlIntParameter(
      request.parameters,
      'batteryLevel',
      minimum: 0,
      maximum: 100,
    );
    if (time.isInvalid ||
        dataNetwork.isInvalid ||
        wifiMode.isInvalid ||
        wifiBars.isInvalid ||
        cellularMode.isInvalid ||
        cellularBars.isInvalid ||
        batteryState.isInvalid ||
        batteryLevel.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setStatusBar accepts time, dataNetwork, wifiMode, wifiBars, cellularMode, cellularBars, batteryState, and batteryLevel parameters declared by system capabilities.',
      );
    }
    final clock = time.isValid ? _androidDemoClock(time.value!) : null;
    if (time.isValid && clock == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'setStatusBar time must be H:MM or HH:MM, for example 9:41.',
      );
    }
    final broadcasts = <String>[];
    if (clock != null) {
      broadcasts.add('-e command clock -e hhmm $clock');
    }
    final wantsWifi =
        wifiMode.value == 'active' ||
        (wifiMode.value == null &&
            (dataNetwork.value == 'wifi' || wifiBars.isValid));
    if (wifiMode.value == 'hide') {
      broadcasts.add('-e command network -e wifi hide');
    } else if (wantsWifi) {
      broadcasts.add(
        '-e command network -e wifi show -e fully true -e level ${wifiBars.value ?? 4}',
      );
    }
    final cellularDataType = switch (dataNetwork.value) {
      '3g' => '3g',
      '4g' => '4g',
      'lte' => 'lte',
      _ => null,
    };
    final wantsCellular =
        cellularMode.value == 'active' ||
        (cellularMode.value == null &&
            (cellularDataType != null || cellularBars.isValid));
    if (cellularMode.value == 'hide' ||
        (cellularMode.value == null && dataNetwork.value == 'hide')) {
      broadcasts.add('-e command network -e mobile hide');
    } else if (wantsCellular) {
      broadcasts.add(
        '-e command network -e mobile show -e fully true -e level ${cellularBars.value ?? 4}'
        '${cellularDataType == null ? '' : ' -e datatype $cellularDataType'}',
      );
    }
    if (batteryState.isValid || batteryLevel.isValid) {
      // "charged" means full while still on power, so it must render as
      // plugged just like the iOS simctl charged state does.
      final plugged =
          batteryState.value == 'charging' || batteryState.value == 'charged';
      broadcasts.add(
        '-e command battery -e level ${batteryLevel.value ?? 100} -e plugged $plugged',
      );
    }
    if (broadcasts.isEmpty) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'setStatusBar requires at least one status bar parameter such as time, dataNetwork, wifiBars, or batteryLevel.',
      );
    }
    const demoBroadcast = 'am broadcast -a com.android.systemui.demo';
    final script = <String>[
      'set -e',
      'settings put global sysui_demo_allowed 1',
      '$demoBroadcast -e command enter >/dev/null',
      for (final broadcast in broadcasts)
        '$demoBroadcast $broadcast >/dev/null',
    ].join('\n');
    return factory(script);
  }

  String? _androidDemoClock(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return '${hour.toString().padLeft(2, '0')}${match.group(2)!}';
  }

  CockpitResolvedSystemControlCommand _grantPermissionCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(
      String packageId,
      String permission,
    )
    factory,
  ) {
    final packageId = _readPackageId(request);
    final permission = cockpitReadSystemControlStringParameter(
      request.parameters,
      'permission',
    );
    if (packageId.isInvalid || permission.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'grantPermission requires string packageId/appId and permission parameters.',
      );
    }
    if (!packageId.isValid || !permission.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'grantPermission requires --app-id or packageId plus permission.',
      );
    }
    return factory(packageId.value!, permission.value!);
  }

  CockpitResolvedSystemControlCommand _androidResetPermissionCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(
      String packageId,
      String? permission,
    )
    factory,
  ) {
    final packageId = _readPackageId(request);
    final permission = cockpitReadSystemControlStringParameter(
      request.parameters,
      'permission',
    );
    if (packageId.isInvalid || permission.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'resetPermission requires string packageId/appId and optional permission parameters.',
      );
    }
    if (!packageId.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'resetPermission requires --app-id or packageId.',
      );
    }
    return factory(packageId.value!, permission.value);
  }

  CockpitResolvedSystemControlCommand _androidInstallAppCommand(
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
    return CockpitResolvedSystemControlCommand('adb', <String>[
      '-s',
      deviceId,
      'install',
      '-r',
      if (grantPermissions.value == true) '-g',
      appPath.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _androidUninstallAppCommand(
    CockpitSystemControlActionRequest request,
    String deviceId,
  ) {
    final packageId = _readPackageId(request);
    final keepData = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'keepData',
    );
    if (packageId.isInvalid || keepData.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'uninstallApp requires string packageId/appId and optional boolean keepData parameters.',
      );
    }
    if (!packageId.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'uninstallApp requires --app-id or packageId.',
      );
    }
    return CockpitResolvedSystemControlCommand('adb', <String>[
      '-s',
      deviceId,
      'uninstall',
      if (keepData.value == true) '-k',
      packageId.value!,
    ]);
  }

  CockpitResolvedSystemControlCommand _fileTransferCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(
      String sourcePath,
      String destinationPath,
    )
    factory,
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
            'File transfer actions require string sourcePath and destinationPath parameters.',
      );
    }
    if (!sourcePath.isValid || !destinationPath.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'File transfer actions require sourcePath and destinationPath parameters.',
      );
    }
    return factory(sourcePath.value!, destinationPath.value!);
  }

  CockpitResolvedSystemControlCommand _androidAddMediaCommand(
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
    final target =
        destinationPath.value ?? _defaultAndroidMediaPath(sourcePath.value!);
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      r'adb -s "$1" push "$2" "$3" && adb -s "$1" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$3"',
      'flutter_cockpit_android_add_media',
      deviceId,
      sourcePath.value!,
      target,
    ]);
  }

  CockpitResolvedSystemControlCommand _androidOpenSystemSettingsCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String settingsAction) factory,
  ) {
    final value = cockpitReadSystemControlStringParameter(
      request.parameters,
      'settingsAction',
    );
    final packageId = cockpitReadSystemControlStringParameter(
      request.parameters,
      'packageId',
    );
    if (value.isInvalid || packageId.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'openSystemSettings requires string settingsAction and optional packageId parameters.',
      );
    }
    if (value.value == 'android.settings.APPLICATION_DETAILS_SETTINGS' ||
        packageId.isValid) {
      final appPackageId = packageId.value ?? request.appId?.trim();
      if (appPackageId == null || appPackageId.isEmpty) {
        return const CockpitResolvedSystemControlCommand.error(
          code: 'missingSystemActionParameter',
          message:
              'Application details settings require --app-id or packageId.',
        );
      }
      return CockpitResolvedSystemControlCommand('adb', <String>[
        '-s',
        request.deviceId!,
        'shell',
        'am',
        'start',
        '-a',
        'android.settings.APPLICATION_DETAILS_SETTINGS',
        '-d',
        'package:$appPackageId',
      ]);
    }
    return factory(value.value ?? 'android.settings.SETTINGS');
  }

  CockpitResolvedSystemControlCommand _androidPostNotificationCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(List<String> args) factory,
  ) {
    final payloadJson = cockpitReadSystemControlStringParameter(
      request.parameters,
      'payloadJson',
    );
    if (payloadJson.isPresent) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'unsupportedSystemActionParameter',
        message:
            'Android postNotification does not accept payloadJson; use title and body.',
      );
    }
    final title = cockpitReadSystemControlStringParameter(
      request.parameters,
      'title',
    );
    final body = cockpitReadSystemControlStringParameter(
      request.parameters,
      'body',
    );
    final tag = cockpitReadSystemControlStringParameter(
      request.parameters,
      'tag',
    );
    if (title.isInvalid || body.isInvalid || tag.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'postNotification accepts string title, body, and tag.',
      );
    }
    final notificationBody = body.value ?? title.value;
    if (notificationBody == null || notificationBody.trim().isEmpty) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'postNotification requires title or body.',
      );
    }
    return factory(<String>[
      if (title.value != null) ...<String>['--title', title.value!],
      tag.value ?? 'cockpit',
      notificationBody,
    ]);
  }

  CockpitResolvedSystemControlCommand _androidDismissSystemDialogCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final decision = cockpitReadSystemControlStringParameter(
      request.parameters,
      'decision',
      allowedValues: const <String>['accept', 'dismiss'],
    );
    if (decision.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'dismissSystemDialog decision must be accept or dismiss when provided.',
      );
    }
    final mode = decision.value ?? 'accept';
    return factory(_androidDismissSystemDialogScript(mode));
  }

  CockpitResolvedSystemControlCommand _androidTapNotificationCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final title = cockpitReadSystemControlStringParameter(
      request.parameters,
      'title',
    );
    final body = cockpitReadSystemControlStringParameter(
      request.parameters,
      'body',
    );
    final tag = cockpitReadSystemControlStringParameter(
      request.parameters,
      'tag',
    );
    final text = cockpitReadSystemControlStringParameter(
      request.parameters,
      'text',
    );
    if (title.isInvalid || body.isInvalid || tag.isInvalid || text.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'tapNotification accepts string title, body, tag, and text parameters.',
      );
    }
    final matchText = text.value ?? title.value ?? body.value ?? tag.value;
    if (matchText == null || matchText.trim().isEmpty) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'tapNotification requires title, body, tag, or text to match the delivered notification.',
      );
    }
    return factory(_androidTapNotificationScript(matchText));
  }

  CockpitResolvedSystemControlCommand _androidResolveBlockersCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final packageId = _readPackageId(request);
    final decision = cockpitReadSystemControlStringParameter(
      request.parameters,
      'decision',
      allowedValues: const <String>['accept', 'dismiss'],
    );
    final dismissKeyboard = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'dismissKeyboard',
    );
    if (packageId.isInvalid ||
        decision.isInvalid ||
        dismissKeyboard.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'resolveBlockers requires string packageId/appId plus optional decision and dismissKeyboard parameters.',
      );
    }
    if (!packageId.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'resolveBlockers requires --app-id or packageId.',
      );
    }
    return factory(
      _androidResolveBlockersScript(
        packageId.value!,
        decision.value ?? 'accept',
        dismissKeyboard: dismissKeyboard.value ?? true,
      ),
    );
  }

  CockpitResolvedSystemControlCommand _androidSystemLogsCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final lines = cockpitReadSystemControlIntParameter(
      request.parameters,
      'lines',
      minimum: 1,
      maximum: 5000,
    );
    final packageId = _readPackageId(request);
    if (lines.isInvalid || packageId.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'readSystemLogs accepts integer lines (1-5000) and optional string packageId.',
      );
    }
    final lineCount = lines.value ?? 200;
    final quotedPackage = packageId.isValid
        ? _shellSingleQuoted(packageId.value!)
        : null;
    final script = quotedPackage == null
        ? 'exec logcat -d -v time -t $lineCount'
        : '''
pid="\$(pidof -s $quotedPackage 2>/dev/null || true)"
if [ -n "\$pid" ]; then
  exec logcat -d -v time -t $lineCount --pid "\$pid"
fi
exec logcat -d -v time -t $lineCount
''';
    return factory(script);
  }

  CockpitResolvedSystemControlCommand _androidSetBatteryCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final level = cockpitReadSystemControlIntParameter(
      request.parameters,
      'level',
      minimum: 0,
      maximum: 100,
    );
    final plugged = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'plugged',
    );
    final reset = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'reset',
    );
    if (level.isInvalid || plugged.isInvalid || reset.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setBattery accepts integer level (0-100) plus boolean plugged and reset parameters.',
      );
    }
    if (reset.value == true) {
      return factory('exec dumpsys battery reset');
    }
    if (!level.isValid && plugged.value == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'setBattery requires level, plugged, or reset.',
      );
    }
    final commands = <String>[
      if (plugged.value == true) 'dumpsys battery set ac 1',
      if (plugged.value == false) 'dumpsys battery unplug',
      if (level.isValid) 'dumpsys battery set level ${level.value}',
    ];
    return factory('set -e\n${commands.join('\n')}');
  }

  CockpitResolvedSystemControlCommand _androidSetConnectivityCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final wifi = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'wifi',
    );
    final mobileData = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'mobileData',
    );
    final airplaneMode = cockpitReadSystemControlBoolParameter(
      request.parameters,
      'airplaneMode',
    );
    if (wifi.isInvalid || mobileData.isInvalid || airplaneMode.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setConnectivity accepts boolean wifi, mobileData, and airplaneMode parameters.',
      );
    }
    if (wifi.value == null &&
        mobileData.value == null &&
        airplaneMode.value == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'setConnectivity requires wifi, mobileData, or airplaneMode.',
      );
    }
    final commands = <String>[
      if (airplaneMode.value != null)
        'cmd connectivity airplane-mode ${airplaneMode.value! ? 'enable' : 'disable'}',
      if (wifi.value != null) 'svc wifi ${wifi.value! ? 'enable' : 'disable'}',
      if (mobileData.value != null)
        'svc data ${mobileData.value! ? 'enable' : 'disable'}',
    ];
    return factory('set -e\n${commands.join('\n')}');
  }

  String _androidDismissSystemDialogScript(String decision) {
    final buttonSpecs = decision == 'dismiss'
        ? const <String>[
            'resource-id="com.android.permissioncontroller:id/permission_deny_button"',
            'resource-id="com.android.packageinstaller:id/permission_deny_button"',
            'text="Deny"',
            'text="DENY"',
            'text="Don’t allow"',
            'text="Cancel"',
            'text="CANCEL"',
          ]
        : const <String>[
            'resource-id="com.android.permissioncontroller:id/permission_allow_button"',
            'resource-id="com.android.permissioncontroller:id/permission_allow_foreground_only_button"',
            'resource-id="com.android.permissioncontroller:id/permission_allow_one_time_button"',
            'resource-id="com.android.packageinstaller:id/permission_allow_button"',
            'text="Allow"',
            'text="ALLOW"',
            'text="While using the app"',
            'text="Only this time"',
            'text="OK"',
          ];
    final patterns = buttonSpecs.map((spec) => "  -e '$spec'").join(' ');
    final notFoundFallback = decision == 'dismiss'
        ? 'input keyevent KEYCODE_BACK'
        : 'echo "flutter_cockpit: no matching Android system dialog accept button" >&2; exit 2';
    return '''
set -e
dump="/sdcard/flutter_cockpit_window.xml"
uiautomator dump "\$dump" >/dev/null
match=\$(grep -E $patterns "\$dump" | head -n 1 || true)
rm -f "\$dump"
if [ -z "\$match" ]; then
  $notFoundFallback
  exit \$?
fi
bounds=\$(printf "%s" "\$match" | sed -n 's/.*bounds="\\[\\([0-9][0-9]*\\),\\([0-9][0-9]*\\)\\]\\[\\([0-9][0-9]*\\),\\([0-9][0-9]*\\)\\]".*/\\1 \\2 \\3 \\4/p')
if [ -z "\$bounds" ]; then
  echo "flutter_cockpit: Android system dialog button had no bounds" >&2
  exit 2
fi
set -- \$bounds
x=\$(( (\$1 + \$3) / 2 ))
y=\$(( (\$2 + \$4) / 2 ))
input tap "\$x" "\$y"
''';
  }

  String _androidTapNotificationScript(String matchText) {
    final quotedMatch = _shellSingleQuoted(matchText);
    return '''
set -e
cmd statusbar expand-notifications >/dev/null 2>&1 || true
sleep 0.4
dump="/sdcard/flutter_cockpit_notification.xml"
uiautomator dump "\$dump" >/dev/null
match=\$(grep -F $quotedMatch "\$dump" | head -n 1 || true)
if [ -z "\$match" ]; then
  rm -f "\$dump"
  echo "flutter_cockpit: no notification text matched $quotedMatch" >&2
  exit 2
fi
bounds=\$(printf "%s" "\$match" | sed -n 's/.*bounds="\\[\\([0-9][0-9]*\\),\\([0-9][0-9]*\\)\\]\\[\\([0-9][0-9]*\\),\\([0-9][0-9]*\\)\\]".*/\\1 \\2 \\3 \\4/p')
rm -f "\$dump"
if [ -z "\$bounds" ]; then
  echo "flutter_cockpit: matched notification node had no bounds" >&2
  exit 2
fi
set -- \$bounds
x=\$(( (\$1 + \$3) / 2 ))
y=\$(( (\$2 + \$4) / 2 ))
input tap "\$x" "\$y"
''';
  }

  String _androidRecoverToAppScript(String packageId) {
    final quotedPackage = _shellSingleQuoted(packageId);
    return '''
set -e
cmd statusbar collapse >/dev/null 2>&1 || true
monkey -p $quotedPackage -c android.intent.category.LAUNCHER 1 >/dev/null
''';
  }

  String _androidResolveBlockersScript(
    String packageId,
    String decision, {
    required bool dismissKeyboard,
  }) {
    final quotedPackage = _shellSingleQuoted(packageId);
    final dialogScript = _androidDismissSystemDialogScript(decision);
    return '''
set +e
(
$dialogScript
) >/dev/null 2>&1
if [ "$dismissKeyboard" = "true" ]; then
  input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
fi
cmd statusbar collapse >/dev/null 2>&1 || true
monkey -p $quotedPackage -c android.intent.category.LAUNCHER 1 >/dev/null
exit 0
''';
  }

  CockpitResolvedSystemControlCommand _packageCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String packageId) factory,
  ) {
    final packageId = _readPackageId(request);
    if (packageId.isInvalid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: '${request.action.name} requires a string packageId or appId.',
      );
    }
    if (!packageId.isValid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: '${request.action.name} requires --app-id or packageId.',
      );
    }
    return factory(packageId.value!);
  }

  CockpitSystemControlStringParameter _readPackageId(
    CockpitSystemControlActionRequest request,
  ) {
    final appId = request.appId?.trim();
    if (appId != null && appId.isNotEmpty) {
      return CockpitSystemControlStringParameter.valid(appId);
    }
    return cockpitReadFirstSystemControlStringParameter(
      request.parameters,
      const <String>['packageId'],
    );
  }

  String _normalizeAndroidKey(String key) {
    final trimmed = key.trim();
    final lower = trimmed.toLowerCase();
    return switch (lower) {
      'enter' || 'return' => 'KEYCODE_ENTER',
      'escape' || 'esc' => 'KEYCODE_ESCAPE',
      'tab' => 'KEYCODE_TAB',
      'backspace' || 'delete' => 'KEYCODE_DEL',
      'space' => 'KEYCODE_SPACE',
      'back' => 'KEYCODE_BACK',
      'home' => 'KEYCODE_HOME',
      'menu' => 'KEYCODE_MENU',
      'volumeup' || 'volume_up' || 'volume-up' => 'KEYCODE_VOLUME_UP',
      'volumedown' || 'volume_down' || 'volume-down' => 'KEYCODE_VOLUME_DOWN',
      _ => trimmed,
    };
  }

  CockpitResolvedSystemControlCommand _androidSetAppearanceCommand(
    String appearance,
    CockpitResolvedSystemControlCommand Function(String mode) factory,
  ) {
    final mode = switch (appearance.trim().toLowerCase()) {
      'dark' => 'yes',
      'light' => 'no',
      'auto' => 'auto',
      _ => null,
    };
    if (mode == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'setAppearance requires appearance light, dark, or auto.',
      );
    }
    return factory(mode);
  }

  CockpitResolvedSystemControlCommand _androidSetContentSizeCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String fontScale) factory,
  ) {
    final fontScaleParameter = cockpitReadSystemControlDoubleParameter(
      request.parameters,
      'fontScale',
      minimum: 0.5,
      maximum: 3.5,
    );
    final contentSizeParameter = cockpitReadSystemControlStringParameter(
      request.parameters,
      'contentSize',
    );
    if (fontScaleParameter.isInvalid || contentSizeParameter.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setContentSize requires a known content size token or font scale between 0.5 and 3.5.',
      );
    }
    if (!fontScaleParameter.isValid && !contentSizeParameter.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'setContentSize requires contentSize or fontScale parameter.',
      );
    }
    final fontScale =
        fontScaleParameter.value ??
        _androidFontScaleForContentSize(contentSizeParameter.value!);
    if (fontScale == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setContentSize requires a known content size token or font scale between 0.5 and 3.5.',
      );
    }
    return factory(_formatDecimal(fontScale));
  }

  CockpitResolvedSystemControlCommand _androidSetOrientationCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(String script) factory,
  ) {
    final raw = cockpitReadSystemControlStringParameter(
      request.parameters,
      'orientation',
    );
    if (raw.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'setOrientation requires a string orientation parameter.',
      );
    }
    if (!raw.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'setOrientation requires an orientation parameter.',
      );
    }
    final orientation = raw.value!;
    if (orientation == 'auto') {
      return factory('settings put system accelerometer_rotation 1');
    }
    final rotation = switch (orientation) {
      'portrait' => 0,
      'landscape' => 1,
      'reversePortrait' => 2,
      'reverseLandscape' => 3,
      _ => null,
    };
    if (rotation == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'setOrientation requires portrait, landscape, reversePortrait, reverseLandscape, or auto.',
      );
    }
    return factory(
      'settings put system accelerometer_rotation 0 && settings put system user_rotation $rotation',
    );
  }

  CockpitResolvedSystemControlCommand _androidEmulatorNetworkCommand(
    CockpitSystemControlActionRequest request, {
    required String deviceId,
    required String parameterName,
    required String commandName,
    required List<String> allowedValues,
  }) {
    if (!deviceId.startsWith('emulator-')) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'systemActionBlocked',
        message: 'Android $commandName is available only for emulator-* ids.',
      );
    }
    final value = cockpitReadSystemControlStringParameter(
      request.parameters,
      parameterName,
      allowedValues: allowedValues,
    );
    if (value.isInvalid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            '${request.action.name} requires one of ${allowedValues.join(", ")}.',
      );
    }
    if (!value.isValid) {
      return CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: '${request.action.name} requires a $parameterName parameter.',
      );
    }
    return CockpitResolvedSystemControlCommand('adb', <String>[
      '-s',
      deviceId,
      'emu',
      'network',
      commandName,
      value.value!,
    ]);
  }

  double? _androidFontScaleForContentSize(String value) {
    return switch (value.trim().toLowerCase()) {
      'extra-small' => 0.85,
      'small' => 0.9,
      'medium' || 'normal' || 'large' => 1.0,
      'extra-large' => 1.15,
      'extra-extra-large' => 1.3,
      'extra-extra-extra-large' => 1.45,
      'accessibility-medium' => 1.6,
      'accessibility-large' => 1.8,
      'accessibility-extra-large' => 2.0,
      'accessibility-extra-extra-large' => 2.4,
      'accessibility-extra-extra-extra-large' => 2.8,
      _ => null,
    };
  }

  String _formatCoordinate(double value) => _formatDecimal(value);

  String _defaultAndroidMediaPath(String sourcePath) {
    final normalized = sourcePath.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    final fileName = lastSlash == -1
        ? normalized
        : normalized.substring(lastSlash + 1);
    final safeName = fileName.trim().isEmpty
        ? 'flutter_cockpit_media'
        : fileName;
    return '/sdcard/Download/$safeName';
  }

  String _formatDecimal(double value) {
    final text = value.toStringAsFixed(6);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _escapeAdbText(String text) {
    return text
        .replaceAll('%', r'\%')
        .replaceAll(' ', '%s')
        .replaceAll('"', r'\"')
        .replaceAll("'", r"\'");
  }

  String _shellSingleQuoted(String value) {
    return "'${value.replaceAll("'", r"""'"'"'""")}'";
  }

  List<String> _deviceRequires(CockpitSystemControlTargetContext target) {
    final requires = <String>['adb', 'device id'];
    final reachable = target.metadata['androidDeviceReachable'];
    if (reachable == false) {
      requires.add('reachable adb device');
      final state = target.metadata['androidDeviceState'];
      if (state is String && state.trim().isNotEmpty) {
        requires.add('adb get-state=device (current: ${state.trim()})');
      }
      final reason = target.metadata['androidDeviceFailureReason'];
      if (reason is String && reason.trim().isNotEmpty) {
        requires.add(reason.trim());
      }
    }
    return requires;
  }

  List<String> _emulatorRequires(CockpitSystemControlTargetContext target) {
    final requires = _deviceRequires(target);
    requires.add('Android emulator id');
    return requires;
  }
}
