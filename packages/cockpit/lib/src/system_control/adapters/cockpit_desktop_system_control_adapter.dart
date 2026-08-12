import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../../platform/windows/cockpit_windows_native_input.dart';
import '../../platform/windows/cockpit_windows_powershell.dart';
import '../../platform/windows/cockpit_windows_window_target.dart';
import '../cockpit_macos_accessibility_tree.dart';
import '../cockpit_system_control_action.dart';
import '../cockpit_system_control_adapter.dart';
import '../cockpit_system_control_parameters.dart';
import '../cockpit_system_control_profile.dart';

final class CockpitDesktopSystemControlAdapter
    implements CockpitSystemControlAdapter {
  const CockpitDesktopSystemControlAdapter({
    required this.platform,
    required this.adapter,
    required this.inputStrategy,
    required this.screenshotStrategy,
    required this.recordingStrategy,
    required this.requires,
    this.limitations = const <String>[],
  });

  @override
  final String platform;
  final String adapter;
  final String inputStrategy;
  final String screenshotStrategy;
  final String recordingStrategy;
  final List<String> requires;
  final List<String> limitations;

  @override
  CockpitSystemControlProfile describe(
    CockpitSystemControlTargetContext target,
  ) {
    final hasInputTarget = target.hasWindowTarget;
    final hasEvidenceTarget = platform == 'macos'
        ? target.appId != null && target.appId!.trim().isNotEmpty
        : target.hasWindowTarget;
    return CockpitSystemControlProfile(
      platform: platform,
      deviceId: target.deviceId,
      appId: target.appId,
      processId: target.processId,
      adapter: adapter,
      preferredPlane: CockpitPlaneKind.flutterSemanticPlane,
      fallbackOrder: const <CockpitPlaneKind>[
        CockpitPlaneKind.flutterSemanticPlane,
        CockpitPlaneKind.nativeUiPlane,
        CockpitPlaneKind.deviceSystemPlane,
        CockpitPlaneKind.hostPlane,
      ],
      recommendedNextStep: 'preferFlutterSemanticPlane',
      capabilities: cockpitCompleteSystemControlCapabilities(
        <CockpitSystemControlCapability>[
          _coordinateInputCapability(CockpitSystemControlAction.tap),
          _coordinateInputCapability(CockpitSystemControlAction.longPress),
          _coordinateInputCapability(CockpitSystemControlAction.drag),
          _targetedInputCapability(
            CockpitSystemControlAction.typeText,
            hasInputTarget: hasInputTarget,
          ),
          _targetedInputCapability(
            CockpitSystemControlAction.pressKey,
            hasInputTarget: hasInputTarget,
          ),
          _targetedInputCapability(
            CockpitSystemControlAction.pressBack,
            hasInputTarget: hasInputTarget,
          ),
          _unsupported(
            CockpitSystemControlAction.pressHome,
            'mobile-home-key',
            'Desktop platforms do not have a stable app-scoped Home action.',
          ),
          _unsupported(
            CockpitSystemControlAction.pressVolumeUp,
            'mobile-volume-key',
            'Desktop host volume keys are global and not safe for app-scoped automation.',
          ),
          _unsupported(
            CockpitSystemControlAction.pressVolumeDown,
            'mobile-volume-key',
            'Desktop host volume keys are global and not safe for app-scoped automation.',
          ),
          _unsupported(
            CockpitSystemControlAction.pressVolumeMute,
            'mobile-volume-key',
            'Desktop host volume keys are global and not safe for app-scoped automation.',
          ),
          _activationCapability(
            CockpitSystemControlAction.activateWindow,
            hasInputTarget: hasInputTarget,
          ),
          _targetedInputCapability(
            CockpitSystemControlAction.terminateApp,
            hasInputTarget: hasInputTarget,
          ),
          _targetedInputCapability(
            CockpitSystemControlAction.dismissSystemDialog,
            hasInputTarget: hasInputTarget,
          ),
          _unsupported(
            CockpitSystemControlAction.dismissKeyboard,
            'desktop-no-software-keyboard',
            'Desktop platforms do not show a software keyboard; release focus through app semantics instead.',
          ),
          _unsupported(
            CockpitSystemControlAction.grantPermission,
            'platform-permission-manager',
            'Desktop permission prompts require app-specific or OS-specific workflows.',
          ),
          if (platform == 'macos')
            CockpitSystemControlCapability(
              action: CockpitSystemControlAction.resetPermission,
              plane: CockpitPlaneKind.hostPlane,
              availability: CockpitSystemControlAvailability.available,
              strategy: 'tccutil.reset',
              requires: const <String>['tccutil'],
              limitations: <String>[
                ...limitations,
                'Resets TCC permission state so the next access re-prompts; it cannot grant permissions.',
              ],
              parameters:
                  CockpitSystemControlParameterSets.macosResetPermission,
            ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openUrl,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _openUrlStrategy,
            requires: _openUrlRequires,
            limitations: limitations,
            parameters: CockpitSystemControlParameterSets.url,
          ),
          if (platform == 'linux')
            _hostBlocked(
              CockpitSystemControlAction.openSystemSettings,
              'desktop-system-settings',
              requires: const <String>[
                'desktop-specific settings tooling (e.g. gnome-control-center)',
              ],
            )
          else
            CockpitSystemControlCapability(
              action: CockpitSystemControlAction.openSystemSettings,
              plane: CockpitPlaneKind.hostPlane,
              availability: CockpitSystemControlAvailability.available,
              strategy: _openSystemSettingsStrategy,
              requires: _openUrlRequires,
              limitations: limitations,
              parameters: CockpitSystemControlParameterSets.systemSettings,
            ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setAppearance,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _setAppearanceStrategy,
            requires: _appearanceRequires,
            limitations: <String>[
              ...limitations,
              'Changes the host-wide appearance for the logged-in user, not just the target app.',
            ],
            parameters: CockpitSystemControlParameterSets.hostAppearance,
          ),
          _hostBlocked(
            CockpitSystemControlAction.setContentSize,
            _setContentSizeStrategy,
            requires: _contentSizeRequires,
          ),
          _unsupported(
            CockpitSystemControlAction.setLocation,
            'desktop-no-global-simulated-location',
            'Desktop hosts do not expose a stable app-scoped simulated location API.',
          ),
          _unsupported(
            CockpitSystemControlAction.setOrientation,
            'desktop-no-app-scoped-orientation',
            'Desktop hosts do not expose a stable app-scoped orientation API.',
          ),
          _hostBlocked(
            CockpitSystemControlAction.setNetworkSpeed,
            _setNetworkSpeedStrategy,
            requires: _networkConditionRequires,
          ),
          _hostBlocked(
            CockpitSystemControlAction.setNetworkDelay,
            _setNetworkDelayStrategy,
            requires: _networkConditionRequires,
          ),
          _unsupported(
            CockpitSystemControlAction.setStatusBar,
            'desktop-no-status-bar-override',
            'Desktop platforms do not expose an iOS-simulator-style status bar override.',
          ),
          _unsupported(
            CockpitSystemControlAction.clearStatusBar,
            'desktop-no-status-bar-override',
            'Desktop platforms do not expose an iOS-simulator-style status bar override.',
          ),
          _unsupported(
            CockpitSystemControlAction.expandNotifications,
            'desktop-notification-center',
            'Desktop notification centers are host-global and not safely app-scoped.',
          ),
          _unsupported(
            CockpitSystemControlAction.expandQuickSettings,
            'desktop-quick-settings',
            'Desktop quick settings are host-global and not safely app-scoped.',
          ),
          _unsupported(
            CockpitSystemControlAction.collapseSystemUi,
            'desktop-system-ui',
            'Desktop system UI collapse is host-global and not safely app-scoped.',
          ),
          if (platform == 'windows')
            _hostBlocked(
              CockpitSystemControlAction.postNotification,
              'desktop-notification-injection',
              requires: const <String>['app-specific notification helper'],
            )
          else
            CockpitSystemControlCapability(
              action: CockpitSystemControlAction.postNotification,
              plane: CockpitPlaneKind.hostPlane,
              availability: CockpitSystemControlAvailability.available,
              strategy: platform == 'macos'
                  ? 'osascript.display-notification'
                  : 'notify-send',
              requires: platform == 'macos'
                  ? const <String>['osascript']
                  : const <String>['notify-send (libnotify)'],
              limitations: <String>[
                ...limitations,
                'Posts from the scripting host identity, not the target app; use app notification flows to validate production handling.',
              ],
              parameters: CockpitSystemControlParameterSets.hostNotification,
            ),
          _hostBlocked(
            CockpitSystemControlAction.clearNotifications,
            'desktop-notification-center',
            requires: const <String>['OS-specific notification center control'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.recoverToApp,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: hasInputTarget
                ? CockpitSystemControlAvailability.available
                : CockpitSystemControlAvailability.blocked,
            strategy: _activationStrategy,
            requires: <String>[
              ..._activationRequires,
              if (!hasInputTarget) 'app id or process id',
            ],
            limitations: <String>[
              ...limitations,
              'Brings the app window to the foreground without restarting it.',
            ],
            parameters: CockpitSystemControlParameterSets.recoverToApp,
          ),
          if (platform == 'macos')
            CockpitSystemControlCapability(
              action: CockpitSystemControlAction.resolveBlockers,
              plane: CockpitPlaneKind.nativeUiPlane,
              availability: hasInputTarget
                  ? CockpitSystemControlAvailability.available
                  : CockpitSystemControlAvailability.blocked,
              strategy: 'macro.ax-dialog+activate',
              requires: <String>[
                'Accessibility permission',
                ..._activationRequires,
                if (!hasInputTarget) 'app id or process id',
              ],
              limitations: <String>[
                ...limitations,
                'Only a real target-owned accessible sheet or modal dialog is changed; no dialog is a safe no-op.',
              ],
              parameters: CockpitSystemControlParameterSets.resolveBlockers,
              fallbackActions: const <CockpitSystemControlAction>[
                CockpitSystemControlAction.dismissSystemDialog,
                CockpitSystemControlAction.recoverToApp,
              ],
            ),
          _hostFileCapability(CockpitSystemControlAction.pushFile),
          _hostFileCapability(CockpitSystemControlAction.pullFile),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.addMedia,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _hostFileStrategy,
            requires: _hostFileRequires,
            limitations: <String>[
              ...limitations,
              'Copies media into the host Downloads folder by default.',
            ],
            parameters: CockpitSystemControlParameterSets.hostAddMedia,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setClipboard,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _setClipboardStrategy,
            requires: _clipboardRequires,
            limitations: limitations,
            parameters: CockpitSystemControlParameterSets.text,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.getClipboard,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _getClipboardStrategy,
            requires: _clipboardRequires,
            limitations: limitations,
          ),
          _evidenceCapability(
            CockpitSystemControlAction.captureScreenshot,
            screenshotStrategy,
            hasWindowTarget: hasEvidenceTarget,
          ),
          _evidenceCapability(
            CockpitSystemControlAction.startRecording,
            recordingStrategy,
            hasWindowTarget: hasEvidenceTarget,
          ),
          _evidenceCapability(
            CockpitSystemControlAction.stopRecording,
            recordingStrategy,
            hasWindowTarget: hasEvidenceTarget,
            extraRequires: const <String>['active recording session'],
          ),
          _uiTreeCapability(hasInputTarget: hasInputTarget),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readProcessList,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _processListStrategy,
            requires: _processListRequires,
            limitations: limitations,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readWindows,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _windowListStrategy,
            requires: _windowListRequires,
            limitations: limitations,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readSystemState,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _systemStateStrategy,
            requires: _systemStateRequires,
            limitations: limitations,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readDeviceInfo,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _deviceInfoStrategy,
            requires: _systemStateRequires,
            limitations: limitations,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readFocusState,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _focusStateStrategy,
            requires: _focusStateRequires,
            limitations: limitations,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readSystemLogs,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: _systemLogsStrategy,
            requires: _systemLogsRequires,
            limitations: limitations,
            parameters: _systemLogsParameters,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.runShell,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.available,
            strategy: 'host.shell',
            requires: _shellRequires,
            limitations: limitations,
            parameters: CockpitSystemControlParameterSets.shellCommand,
          ),
        ],
        plane: CockpitPlaneKind.hostPlane,
        availability: CockpitSystemControlAvailability.unsupported,
        strategy: 'desktop-action-not-supported',
        limitations: const <String>[
          'This action is not implemented for desktop host automation.',
        ],
      ),
    );
  }

  @override
  CockpitResolvedSystemControlCommand resolveCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return switch (platform) {
      'macos' => _resolveMacosCommand(request),
      'windows' => _resolveWindowsCommand(request),
      'linux' => _resolveLinuxCommand(request),
      _ => CockpitResolvedSystemControlCommand.error(
        code: 'unsupportedPlatform',
        message: 'No desktop system control adapter for $platform.',
      ),
    };
  }

  String get _openUrlStrategy {
    return switch (platform) {
      'macos' => 'open.url',
      'windows' => 'powershell.start-process.url',
      'linux' => 'xdg-open.url',
      _ => 'host.open-url',
    };
  }

  String get _setClipboardStrategy {
    return switch (platform) {
      'macos' => 'pbcopy',
      'windows' => 'powershell.set-clipboard',
      'linux' => 'wl-copy|xclip|xsel',
      _ => 'host.set-clipboard',
    };
  }

  String get _getClipboardStrategy {
    return switch (platform) {
      'macos' => 'pbpaste',
      'windows' => 'powershell.get-clipboard',
      'linux' => 'wl-paste|xclip|xsel',
      _ => 'host.get-clipboard',
    };
  }

  List<String> get _clipboardRequires {
    return switch (platform) {
      'macos' => const <String>['pbcopy', 'pbpaste'],
      'windows' => const <String>['PowerShell'],
      'linux' => const <String>[
        'one clipboard tool: wl-copy/wl-paste, xclip, or xsel',
      ],
      _ => const <String>['host clipboard tool'],
    };
  }

  List<String> get _openUrlRequires {
    return switch (platform) {
      'macos' => const <String>['open'],
      'windows' => const <String>['PowerShell'],
      'linux' => const <String>['xdg-open'],
      _ => const <String>['host URL opener'],
    };
  }

  String get _uiTreeStrategy {
    return switch (platform) {
      'macos' => 'AXUIElement tree reader',
      'windows' => 'UIAutomation tree walker',
      'linux' => 'AT-SPI tree walker',
      _ => 'native accessibility tree',
    };
  }

  String get _setAppearanceStrategy {
    return switch (platform) {
      'macos' => 'osascript.system-events.appearance',
      'windows' => 'powershell.registry.apps-use-light-theme',
      'linux' => 'gsettings.color-scheme',
      _ => 'host.appearance',
    };
  }

  String get _openSystemSettingsStrategy {
    return switch (platform) {
      'macos' => 'open.x-apple.systempreferences',
      'windows' => 'powershell.start-process.ms-settings',
      _ => 'host.open-system-settings',
    };
  }

  String get _deviceInfoStrategy {
    return switch (platform) {
      'macos' => 'sw_vers+sysctl.hw-model',
      'windows' => 'powershell.cim.computer-system+operating-system',
      'linux' => 'uname+os-release',
      _ => 'host.device-info',
    };
  }

  String get _focusStateStrategy {
    return switch (platform) {
      'macos' => 'system-events.frontmost-process',
      'windows' => 'powershell.foreground-window',
      'linux' => 'xdotool.getactivewindow',
      _ => 'host.focus-state',
    };
  }

  List<String> get _focusStateRequires {
    return switch (platform) {
      'macos' => const <String>['Automation permission for System Events'],
      'windows' => const <String>['PowerShell', 'interactive desktop session'],
      'linux' => const <String>['xdotool', 'X11 DISPLAY'],
      _ => const <String>['host focus inspection tooling'],
    };
  }

  String get _systemLogsStrategy {
    return switch (platform) {
      'macos' => 'log.show.last',
      'windows' => 'powershell.get-winevent.application',
      'linux' => 'journalctl.tail',
      _ => 'host.system-logs',
    };
  }

  List<String> get _systemLogsRequires {
    return switch (platform) {
      'macos' => const <String>['log'],
      'windows' => const <String>['PowerShell'],
      'linux' => const <String>['journalctl (systemd)'],
      _ => const <String>['host log tooling'],
    };
  }

  List<CockpitSystemControlParameter> get _systemLogsParameters {
    return switch (platform) {
      'macos' => CockpitSystemControlParameterSets.appleSystemLogs,
      'windows' => CockpitSystemControlParameterSets.windowsSystemLogs,
      'linux' => CockpitSystemControlParameterSets.linuxSystemLogs,
      _ => const <CockpitSystemControlParameter>[],
    };
  }

  String get _hostFileStrategy {
    return switch (platform) {
      'macos' || 'linux' => 'host.cp',
      'windows' => 'powershell.copy-item',
      _ => 'host.file-copy',
    };
  }

  List<String> get _hostFileRequires {
    return switch (platform) {
      'macos' || 'linux' => const <String>['host shell'],
      'windows' => const <String>['PowerShell'],
      _ => const <String>['host shell'],
    };
  }

  CockpitSystemControlCapability _hostFileCapability(
    CockpitSystemControlAction action,
  ) {
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.hostPlane,
      availability: CockpitSystemControlAvailability.available,
      strategy: _hostFileStrategy,
      requires: _hostFileRequires,
      limitations: <String>[
        ...limitations,
        'Desktop file transfer is a host-side copy; both paths are on the host filesystem.',
      ],
      parameters: CockpitSystemControlParameterSets.fileTransfer,
    );
  }

  String get _setContentSizeStrategy {
    return switch (platform) {
      'macos' => 'host-accessibility-display-settings',
      'windows' => 'host-text-scale-settings',
      'linux' => 'desktop-font-scaling-settings',
      _ => 'host.content-size',
    };
  }

  String get _setNetworkSpeedStrategy {
    return switch (platform) {
      'macos' => 'network-link-conditioner-or-pf',
      'windows' => 'qos-policy-or-network-emulator',
      'linux' => 'tc-netem',
      _ => 'host.network.speed',
    };
  }

  String get _setNetworkDelayStrategy {
    return switch (platform) {
      'macos' => 'network-link-conditioner-or-pf',
      'windows' => 'qos-policy-or-network-emulator',
      'linux' => 'tc-netem',
      _ => 'host.network.delay',
    };
  }

  String get _processListStrategy {
    return switch (platform) {
      'macos' => 'ps.process-list',
      'windows' => 'powershell.get-process',
      'linux' => 'ps.process-list',
      _ => 'host.process-list',
    };
  }

  String get _windowListStrategy {
    return switch (platform) {
      'macos' => 'system-events.visible-windows',
      'windows' => 'powershell.main-window-list',
      'linux' => 'wmctrl-or-xdotool.window-list',
      _ => 'host.window-list',
    };
  }

  String get _systemStateStrategy {
    return switch (platform) {
      'macos' => 'sw_vers+uname',
      'windows' => 'powershell.cim.operating-system',
      'linux' => 'uname+desktop-session-env',
      _ => 'host.system-state',
    };
  }

  List<String> get _systemStateRequires {
    return switch (platform) {
      'macos' => const <String>['sw_vers', 'uname'],
      'windows' => const <String>['PowerShell'],
      'linux' => const <String>['uname', 'host shell'],
      _ => const <String>['host shell'],
    };
  }

  List<String> get _shellRequires {
    return switch (platform) {
      'macos' || 'linux' => const <String>['host shell'],
      'windows' => const <String>['interactive desktop session'],
      _ => const <String>['host shell'],
    };
  }

  List<String> get _coordinateInputRequires {
    return switch (platform) {
      'macos' => const <String>[
        'Accessibility permission',
        'interactive desktop session',
      ],
      'windows' => const <String>['interactive desktop session'],
      'linux' => const <String>['xdotool', 'X11 DISPLAY'],
      _ => requires,
    };
  }

  List<String> get _uiTreeRequires {
    return switch (platform) {
      'macos' => const <String>['Accessibility permission'],
      'windows' => const <String>['PowerShell', 'UI Automation'],
      'linux' => const <String>['AT-SPI tree dump helper'],
      _ => const <String>['native accessibility tree helper'],
    };
  }

  List<String> get _appearanceRequires {
    return switch (platform) {
      'macos' => const <String>['Automation permission for System Events'],
      'windows' => const <String>['PowerShell'],
      'linux' => const <String>['gsettings (GNOME color-scheme)'],
      _ => const <String>['host appearance tooling'],
    };
  }

  List<String> get _contentSizeRequires {
    return switch (platform) {
      'macos' => const <String>['explicit user approval'],
      'windows' => const <String>['explicit user approval'],
      'linux' => const <String>['desktop-specific font scaling tooling'],
      _ => const <String>['host accessibility tooling'],
    };
  }

  List<String> get _networkConditionRequires {
    return switch (platform) {
      'macos' => const <String>[
        'explicit user approval',
        'host network shaping tooling',
      ],
      'windows' => const <String>[
        'explicit user approval',
        'administrator network tooling',
      ],
      'linux' => const <String>[
        'explicit user approval',
        'tc/netem privileges',
      ],
      _ => const <String>['host network shaping tooling'],
    };
  }

  List<String> get _processListRequires {
    return switch (platform) {
      'macos' || 'linux' => const <String>['ps'],
      'windows' => const <String>['PowerShell'],
      _ => const <String>['host process listing tool'],
    };
  }

  List<String> get _windowListRequires {
    return switch (platform) {
      'macos' => const <String>['Automation permission for System Events'],
      'windows' => const <String>['PowerShell'],
      'linux' => const <String>['wmctrl or xdotool', 'desktop session'],
      _ => const <String>['host window listing tool'],
    };
  }

  List<String> get _targetedInputRequires {
    return switch (platform) {
      'macos' => const <String>[
        'Accessibility permission',
        'Automation permission for System Events',
        'interactive desktop session',
      ],
      'windows' => const <String>['interactive desktop session'],
      'linux' => const <String>['xdotool', 'X11 DISPLAY'],
      _ => requires,
    };
  }

  String get _activationStrategy => switch (platform) {
    'macos' => 'NSRunningApplication.activate',
    _ => inputStrategy,
  };

  List<String> get _activationRequires => switch (platform) {
    'macos' => const <String>['osascript', 'interactive desktop session'],
    _ => _targetedInputRequires,
  };

  List<String> get _screenshotRequires {
    return switch (platform) {
      'macos' => const <String>[
        'screencapture',
        'osascript',
        'Screen Recording permission',
      ],
      'windows' => const <String>['PowerShell', 'interactive desktop session'],
      'linux' => const <String>[
        'desktop session',
        'wmctrl recommended',
        'one screenshot path: gnome-screenshot, grim, scrot, import, xwd+ffmpeg, or ffmpeg x11grab',
      ],
      _ => requires,
    };
  }

  List<String> get _recordingRequires {
    return switch (platform) {
      'macos' => const <String>[
        'ffmpeg',
        'osascript',
        'Screen Recording permission',
      ],
      'windows' => const <String>[
        'ffmpeg',
        'PowerShell',
        'interactive desktop session',
      ],
      'linux' => const <String>['ffmpeg', 'X11 DISPLAY'],
      _ => requires,
    };
  }

  CockpitResolvedSystemControlCommand _resolveMacosCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return switch (request.action) {
      CockpitSystemControlAction.tap => cockpitCoordinateCommand(
        request,
        (x, y) => _macosJxaWithTarget(request, _macosMouseScript, <String>[
          'tap',
          '$x',
          '$y',
          '$x',
          '$y',
          '0',
        ]),
      ),
      CockpitSystemControlAction.longPress => cockpitLongPressCommand(
        request,
        (x, y, durationMs) => _macosJxaWithTarget(
          request,
          _macosMouseScript,
          <String>['longPress', '$x', '$y', '$x', '$y', '$durationMs'],
        ),
      ),
      CockpitSystemControlAction.drag => cockpitDragCommand(request, (
        startX,
        startY,
        endX,
        endY,
        durationMs,
      ) {
        return _macosJxaWithTarget(request, _macosMouseScript, <String>[
          'drag',
          '$startX',
          '$startY',
          '$endX',
          '$endY',
          '$durationMs',
        ]);
      }),
      CockpitSystemControlAction.typeText => cockpitTextCommand(
        request,
        'text',
        (text) => _macosAppleScriptWithTarget(
          request,
          _macosTypeTextScript,
          <String>[text],
        ),
      ),
      CockpitSystemControlAction.pressKey => cockpitTextCommand(
        request,
        'key',
        (key) {
          final repeat = _pressKeyRepeat(request);
          if (repeat == null) return _invalidPressKeyRepeat;
          return _macosAppleScriptWithTarget(
            request,
            _macosPressKeyScript,
            <String>[key, '$repeat'],
          );
        },
      ),
      CockpitSystemControlAction.pressBack => _macosAppleScriptWithTarget(
        request,
        _macosPressBackScript,
      ),
      CockpitSystemControlAction.activateWindow => _macosJxaWithTarget(
        request,
        _macosActivateTargetScript,
        const <String>[],
      ),
      CockpitSystemControlAction.terminateApp => _macosAppleScriptWithTarget(
        request,
        _macosTerminateTargetScript,
      ),
      CockpitSystemControlAction.dismissSystemDialog =>
        _macosDismissSystemDialogCommand(request),
      CockpitSystemControlAction.openUrl => cockpitTextCommand(
        request,
        'url',
        (url) => CockpitResolvedSystemControlCommand('open', <String>[url]),
      ),
      CockpitSystemControlAction.readUiTree => _macosReadUiTreeCommand(request),
      CockpitSystemControlAction.readProcessList =>
        CockpitResolvedSystemControlCommand('ps', const <String>[
          '-axo',
          'pid=,ppid=,comm=',
        ]),
      CockpitSystemControlAction.readWindows => _macosJxa(const <String>[
        _macosReadWindowsScript,
      ]),
      CockpitSystemControlAction.setClipboard => cockpitTextCommand(
        request,
        'text',
        (text) => CockpitResolvedSystemControlCommand('sh', <String>[
          '-c',
          r'printf "%s" "$1" | pbcopy',
          'flutter_cockpit_macos_clipboard',
          text,
        ]),
      ),
      CockpitSystemControlAction.getClipboard =>
        CockpitResolvedSystemControlCommand('pbpaste', const <String>[]),
      CockpitSystemControlAction.readSystemState =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          'sw_vers && uname -a',
        ]),
      CockpitSystemControlAction.readDeviceInfo =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          'sw_vers; uname -m; sysctl -n hw.model',
        ]),
      CockpitSystemControlAction.readFocusState =>
        CockpitResolvedSystemControlCommand('osascript', const <String>[
          '-e',
          _macosReadFocusStateScript,
        ]),
      CockpitSystemControlAction.readSystemLogs => _macosSystemLogsCommand(
        request,
      ),
      CockpitSystemControlAction.openSystemSettings => _desktopSettingsCommand(
        request,
        defaultTarget: 'x-apple.systempreferences:',
        factory: (target) =>
            CockpitResolvedSystemControlCommand('open', <String>[target]),
      ),
      CockpitSystemControlAction.setAppearance => cockpitTextCommand(
        request,
        'appearance',
        (appearance) => _macosSetAppearanceCommand(appearance),
        trim: true,
        allowedValues: const <String>['light', 'dark'],
      ),
      CockpitSystemControlAction.resetPermission =>
        _macosResetPermissionCommand(request),
      CockpitSystemControlAction.postNotification =>
        _desktopNotificationCommand(
          request,
          factory: (title, body) => CockpitResolvedSystemControlCommand(
            'osascript',
            <String>['-e', _macosPostNotificationScript, title, body],
          ),
        ),
      CockpitSystemControlAction.recoverToApp => _macosJxaWithTarget(
        request,
        _macosActivateTargetScript,
        const <String>[],
      ),
      CockpitSystemControlAction.pushFile ||
      CockpitSystemControlAction.pullFile => _posixHostFileCommand(request),
      CockpitSystemControlAction.addMedia => _posixHostAddMediaCommand(request),
      CockpitSystemControlAction.runShell => cockpitShellCommand(
        request,
        (command) => CockpitResolvedSystemControlCommand(
          command.first,
          command.skip(1).toList(growable: false),
        ),
      ),
      CockpitSystemControlAction.captureScreenshot ||
      CockpitSystemControlAction.startRecording ||
      CockpitSystemControlAction
          .stopRecording => const CockpitResolvedSystemControlCommand.error(
        code: 'systemEvidenceAction',
        message:
            'Evidence actions are executed through capture and recording adapters.',
      ),
      _ => _unsupportedCommand(request),
    };
  }

  CockpitResolvedSystemControlCommand _resolveWindowsCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return switch (request.action) {
      CockpitSystemControlAction.tap => cockpitCoordinateCommand(
        request,
        (x, y) => _windowsInput(<String>['tap', '', '', '$x', '$y']),
      ),
      CockpitSystemControlAction.longPress => cockpitLongPressCommand(
        request,
        (x, y, durationMs) => _windowsInput(<String>[
          'longPress',
          '',
          '',
          '$x',
          '$y',
          '$durationMs',
        ]),
      ),
      CockpitSystemControlAction.drag => cockpitDragCommand(request, (
        startX,
        startY,
        endX,
        endY,
        durationMs,
      ) {
        return _windowsInput(<String>[
          'drag',
          '',
          '',
          '$startX',
          '$startY',
          '$endX',
          '$endY',
          '$durationMs',
        ]);
      }),
      CockpitSystemControlAction.typeText => cockpitTextCommand(
        request,
        'text',
        (text) => _windowsInput(<String>[
          'typeText',
          request.appId ?? '',
          request.processId?.toString() ?? '',
          text,
        ]),
      ),
      CockpitSystemControlAction.pressKey => cockpitTextCommand(
        request,
        'key',
        (key) {
          final repeat = _pressKeyRepeat(request);
          if (repeat == null) return _invalidPressKeyRepeat;
          return _windowsInput(<String>[
            'pressKey',
            request.appId ?? '',
            request.processId?.toString() ?? '',
            key,
            '$repeat',
          ]);
        },
      ),
      CockpitSystemControlAction.pressBack => _windowsInput(<String>[
        'pressBack',
        request.appId ?? '',
        request.processId?.toString() ?? '',
      ]),
      CockpitSystemControlAction.activateWindow => _windowsInput(<String>[
        'activateWindow',
        request.appId ?? '',
        request.processId?.toString() ?? '',
      ]),
      CockpitSystemControlAction.terminateApp => _windowsTerminateCommand(
        request,
      ),
      CockpitSystemControlAction.dismissSystemDialog => _windowsInput(<String>[
        'pressBack',
        request.appId ?? '',
        request.processId?.toString() ?? '',
      ]),
      CockpitSystemControlAction.openUrl => cockpitTextCommand(
        request,
        'url',
        (url) => _windowsPowershell(
          r'Start-Process -FilePath $args[0]',
          arguments: <String>[url],
        ),
      ),
      CockpitSystemControlAction.readUiTree => _windowsReadUiTreeCommand(
        request,
      ),
      CockpitSystemControlAction.readProcessList => _windowsPowershell(
        r'Get-Process | Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle | ConvertTo-Json -Compress',
      ),
      CockpitSystemControlAction.readWindows => _windowsPowershell(
        r'Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | Sort-Object Id | Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle | ConvertTo-Json -Compress',
      ),
      CockpitSystemControlAction.setClipboard => cockpitTextCommand(
        request,
        'text',
        (text) => _windowsPowershell(
          r'Set-Clipboard -Value $args[0]',
          arguments: <String>[text],
        ),
      ),
      CockpitSystemControlAction.getClipboard => _windowsPowershell(
        r'Get-Clipboard -Raw',
      ),
      CockpitSystemControlAction.readSystemState => _windowsPowershell(
        r'Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture | ConvertTo-Json -Compress',
      ),
      CockpitSystemControlAction.readDeviceInfo => _windowsPowershell(
        r'[pscustomobject]@{ computerSystem = (Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory); operatingSystem = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture) } | ConvertTo-Json -Compress',
      ),
      CockpitSystemControlAction.readFocusState =>
        const CockpitResolvedSystemControlCommand(
          cockpitWindowsFocusStateCommandExecutable,
          <String>[],
        ),
      CockpitSystemControlAction.readSystemLogs => _windowsSystemLogsCommand(
        request,
      ),
      CockpitSystemControlAction.openSystemSettings => _desktopSettingsCommand(
        request,
        defaultTarget: 'ms-settings:',
        factory: (target) => _windowsPowershell(
          r'Start-Process -FilePath $args[0]',
          arguments: <String>[target],
        ),
      ),
      CockpitSystemControlAction.setAppearance => cockpitTextCommand(
        request,
        'appearance',
        (appearance) => _windowsPowershell(
          _windowsSetAppearanceScript,
          arguments: <String>[appearance.trim().toLowerCase()],
        ),
        trim: true,
        allowedValues: const <String>['light', 'dark'],
      ),
      CockpitSystemControlAction.postNotification =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemActionBlocked',
          message:
              'Windows toast notifications require an app-specific notification helper.',
        ),
      CockpitSystemControlAction.recoverToApp => _windowsInput(<String>[
        'activateWindow',
        request.appId ?? '',
        request.processId?.toString() ?? '',
      ]),
      CockpitSystemControlAction.pushFile ||
      CockpitSystemControlAction.pullFile => _windowsHostFileCommand(request),
      CockpitSystemControlAction.addMedia => _windowsHostAddMediaCommand(
        request,
      ),
      CockpitSystemControlAction.runShell => cockpitShellCommand(
        request,
        (command) => CockpitResolvedSystemControlCommand(
          command.first,
          command.skip(1).toList(growable: false),
        ),
      ),
      CockpitSystemControlAction.captureScreenshot ||
      CockpitSystemControlAction.startRecording ||
      CockpitSystemControlAction
          .stopRecording => const CockpitResolvedSystemControlCommand.error(
        code: 'systemEvidenceAction',
        message:
            'Evidence actions are executed through capture and recording adapters.',
      ),
      _ => _unsupportedCommand(request),
    };
  }

  CockpitResolvedSystemControlCommand _resolveLinuxCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return switch (request.action) {
      CockpitSystemControlAction.tap => cockpitCoordinateCommand(
        request,
        (x, y) => CockpitResolvedSystemControlCommand('xdotool', <String>[
          'mousemove',
          '$x',
          '$y',
          'click',
          '1',
        ]),
      ),
      CockpitSystemControlAction.longPress => cockpitLongPressCommand(
        request,
        (x, y, durationMs) =>
            CockpitResolvedSystemControlCommand('xdotool', <String>[
              'mousemove',
              '$x',
              '$y',
              'mousedown',
              '1',
              'sleep',
              '${durationMs / 1000.0}',
              'mouseup',
              '1',
            ]),
      ),
      CockpitSystemControlAction.drag => cockpitDragCommand(request, (
        startX,
        startY,
        endX,
        endY,
        durationMs,
      ) {
        return CockpitResolvedSystemControlCommand('xdotool', <String>[
          'mousemove',
          '$startX',
          '$startY',
          'mousedown',
          '1',
          'sleep',
          '${durationMs / 1000.0}',
          'mousemove',
          '--sync',
          '$endX',
          '$endY',
          'mouseup',
          '1',
        ]);
      }),
      CockpitSystemControlAction.typeText => cockpitTextCommand(
        request,
        'text',
        (text) => _linuxTargetedXdotool(request, <String>[
          'type',
          '--clearmodifiers',
          '--delay',
          '0',
          // Stops xdotool from parsing text beginning with '-' as an option.
          '--',
          text,
        ]),
      ),
      CockpitSystemControlAction.pressKey => cockpitTextCommand(
        request,
        'key',
        (key) {
          final repeat = _pressKeyRepeat(request);
          if (repeat == null) return _invalidPressKeyRepeat;
          return _linuxTargetedXdotool(request, <String>[
            'key',
            '--repeat',
            '$repeat',
            '--delay',
            '0',
            _normalizeDesktopKeyForXdotool(key),
          ]);
        },
      ),
      CockpitSystemControlAction.pressBack => _linuxTargetedXdotool(
        request,
        const <String>['key', 'Escape'],
      ),
      CockpitSystemControlAction.activateWindow => _linuxTargetedXdotool(
        request,
        const <String>[],
      ),
      CockpitSystemControlAction.terminateApp => _linuxTerminateCommand(
        request,
      ),
      CockpitSystemControlAction.dismissSystemDialog => _linuxTargetedXdotool(
        request,
        const <String>['key', 'Escape'],
      ),
      CockpitSystemControlAction.openUrl => cockpitTextCommand(
        request,
        'url',
        (url) => CockpitResolvedSystemControlCommand('xdg-open', <String>[url]),
      ),
      CockpitSystemControlAction.readUiTree =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemActionBlocked',
          message:
              'Linux readUiTree requires an AT-SPI tree dump helper for the active desktop session.',
        ),
      CockpitSystemControlAction.readProcessList =>
        CockpitResolvedSystemControlCommand('ps', const <String>[
          '-axo',
          'pid=,ppid=,comm=',
        ]),
      CockpitSystemControlAction.readWindows =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          _linuxReadWindowsScript,
          'flutter_cockpit_linux_windows',
        ]),
      CockpitSystemControlAction.setClipboard => cockpitTextCommand(
        request,
        'text',
        (text) => CockpitResolvedSystemControlCommand('sh', <String>[
          '-c',
          _linuxSetClipboardScript,
          'flutter_cockpit_linux_clipboard',
          text,
        ]),
      ),
      CockpitSystemControlAction.getClipboard =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          _linuxGetClipboardScript,
          'flutter_cockpit_linux_clipboard',
        ]),
      CockpitSystemControlAction.readSystemState =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          r'uname -a && printf "XDG_SESSION_TYPE=%s\nXDG_CURRENT_DESKTOP=%s\nWAYLAND_DISPLAY=%s\nDISPLAY=%s\n" "$XDG_SESSION_TYPE" "$XDG_CURRENT_DESKTOP" "$WAYLAND_DISPLAY" "$DISPLAY"',
        ]),
      CockpitSystemControlAction.readDeviceInfo =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          'uname -a; cat /etc/os-release 2>/dev/null || true',
        ]),
      CockpitSystemControlAction.readFocusState =>
        CockpitResolvedSystemControlCommand('sh', const <String>[
          '-c',
          _linuxReadFocusStateScript,
          'flutter_cockpit_linux_focus',
        ]),
      CockpitSystemControlAction.readSystemLogs => _linuxSystemLogsCommand(
        request,
      ),
      CockpitSystemControlAction.openSystemSettings =>
        const CockpitResolvedSystemControlCommand.error(
          code: 'systemActionBlocked',
          message:
              'Linux system settings require desktop-specific tooling such as gnome-control-center.',
        ),
      CockpitSystemControlAction.setAppearance => cockpitTextCommand(
        request,
        'appearance',
        (appearance) => CockpitResolvedSystemControlCommand('sh', <String>[
          '-c',
          _linuxSetAppearanceScript,
          'flutter_cockpit_linux_appearance',
          appearance.trim().toLowerCase(),
        ]),
        trim: true,
        allowedValues: const <String>['light', 'dark'],
      ),
      CockpitSystemControlAction.postNotification =>
        _desktopNotificationCommand(
          request,
          factory: (title, body) =>
              CockpitResolvedSystemControlCommand('sh', <String>[
                '-c',
                _linuxPostNotificationScript,
                'flutter_cockpit_linux_notification',
                title,
                body,
              ]),
        ),
      CockpitSystemControlAction.recoverToApp => _linuxTargetedXdotool(
        request,
        const <String>[],
      ),
      CockpitSystemControlAction.pushFile ||
      CockpitSystemControlAction.pullFile => _posixHostFileCommand(request),
      CockpitSystemControlAction.addMedia => _posixHostAddMediaCommand(request),
      CockpitSystemControlAction.runShell => cockpitShellCommand(
        request,
        (command) => CockpitResolvedSystemControlCommand(
          command.first,
          command.skip(1).toList(growable: false),
        ),
      ),
      CockpitSystemControlAction.captureScreenshot ||
      CockpitSystemControlAction.startRecording ||
      CockpitSystemControlAction
          .stopRecording => const CockpitResolvedSystemControlCommand.error(
        code: 'systemEvidenceAction',
        message:
            'Evidence actions are executed through capture and recording adapters.',
      ),
      _ => _unsupportedCommand(request),
    };
  }

  CockpitResolvedSystemControlCommand _macosJxa(List<String> scriptAndArgs) {
    return CockpitResolvedSystemControlCommand('osascript', <String>[
      '-l',
      'JavaScript',
      '-e',
      ...scriptAndArgs,
    ]);
  }

  CockpitResolvedSystemControlCommand _macosReadUiTreeCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final limits = _uiTreeReadLimits(request);
    if (limits.error != null) {
      return limits.error!;
    }
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This macOS action requires --app-id or --process-id.',
      );
    }
    return CockpitResolvedSystemControlCommand(
      cockpitMacosAccessibilityCommandExecutable,
      <String>[...target, ...limits.values],
    );
  }

  CockpitResolvedSystemControlCommand _macosDismissSystemDialogCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This macOS action requires --app-id or --process-id.',
      );
    }
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
    return CockpitResolvedSystemControlCommand(
      cockpitMacosSystemDialogCommandExecutable,
      <String>[decision.value ?? 'accept'],
    );
  }

  CockpitResolvedSystemControlCommand _macosJxaWithTarget(
    CockpitSystemControlActionRequest request,
    String script,
    List<String> extraArgs,
  ) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This macOS action requires --app-id or --process-id.',
      );
    }
    return CockpitResolvedSystemControlCommand('osascript', <String>[
      '-l',
      'JavaScript',
      '-e',
      script,
      ...target,
      ...extraArgs,
    ]);
  }

  CockpitResolvedSystemControlCommand _macosAppleScriptWithTarget(
    CockpitSystemControlActionRequest request,
    String script, [
    List<String> extraArgs = const <String>[],
  ]) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This macOS action requires --app-id or --process-id.',
      );
    }
    return CockpitResolvedSystemControlCommand('osascript', <String>[
      '-e',
      script,
      ...target,
      ...extraArgs,
    ]);
  }

  /// powershell.exe joins everything after `-Command` into one command
  /// string and never populates `$args` from argv, so the script runs as an
  /// invoked script block (`& { ... } 'arg0' 'arg1'`) whose inert
  /// single-quoted arguments populate `$args` through PowerShell's own
  /// argument binding. The whole body travels as `-EncodedCommand` to
  /// survive CreateProcess quote re-parsing without any injection surface.
  CockpitResolvedSystemControlCommand _windowsPowershell(
    String script, {
    List<String> arguments = const <String>[],
  }) {
    return CockpitResolvedSystemControlCommand('powershell', <String>[
      ...cockpitWindowsPowerShellCommand(script, arguments: arguments),
    ]);
  }

  CockpitResolvedSystemControlCommand _windowsInput(List<String> args) {
    return CockpitResolvedSystemControlCommand(
      cockpitWindowsNativeInputCommandExecutable,
      args,
    );
  }

  CockpitResolvedSystemControlCommand _windowsTerminateCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This Windows action requires --app-id or --process-id.',
      );
    }
    return _windowsPowershell(_windowsTerminateScript, arguments: target);
  }

  CockpitResolvedSystemControlCommand _windowsReadUiTreeCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This Windows action requires --app-id or --process-id.',
      );
    }
    final limits = _uiTreeReadLimits(request);
    if (limits.error != null) {
      return limits.error!;
    }
    return _windowsPowershell(
      _windowsReadUiTreeScript,
      arguments: <String>[...target, ...limits.values],
    );
  }

  CockpitResolvedSystemControlCommand _linuxTargetedXdotool(
    CockpitSystemControlActionRequest request,
    List<String> xdotoolArgs,
  ) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This Linux action requires --app-id or --process-id.',
      );
    }
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      _linuxTargetedXdotoolScript,
      'flutter_cockpit_linux_input',
      ...target,
      ...xdotoolArgs,
    ]);
  }

  CockpitResolvedSystemControlCommand _linuxTerminateCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final target = _targetArgs(request);
    if (target == null) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionTarget',
        message: 'This Linux action requires --app-id or --process-id.',
      );
    }
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      _linuxTerminateScript,
      'flutter_cockpit_linux_terminate',
      ...target,
    ]);
  }

  CockpitResolvedSystemControlCommand _macosSystemLogsCommand(
    CockpitSystemControlActionRequest request,
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
        r'log show --style compact --last "$1" --predicate "process == \"$2\"" | tail -n "$3"',
        'flutter_cockpit_macos_logs',
        '${minutes}m',
        processName.value!,
        '$lineCount',
      ]);
    }
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      r'log show --style compact --last "$1" | tail -n "$2"',
      'flutter_cockpit_macos_logs',
      '${minutes}m',
      '$lineCount',
    ]);
  }

  CockpitResolvedSystemControlCommand _windowsSystemLogsCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final lines = cockpitReadSystemControlIntParameter(
      request.parameters,
      'lines',
      minimum: 1,
      maximum: 1000,
    );
    if (lines.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'readSystemLogs accepts integer lines (1-1000).',
      );
    }
    final count = lines.value ?? 50;
    return _windowsPowershell(
      'Get-WinEvent -LogName Application -MaxEvents $count | '
      'Select-Object TimeCreated,ProviderName,LevelDisplayName,Message | '
      'ConvertTo-Json -Compress',
    );
  }

  CockpitResolvedSystemControlCommand _linuxSystemLogsCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final lines = cockpitReadSystemControlIntParameter(
      request.parameters,
      'lines',
      minimum: 1,
      maximum: 5000,
    );
    if (lines.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message: 'readSystemLogs accepts integer lines (1-5000).',
      );
    }
    final count = lines.value ?? 200;
    return CockpitResolvedSystemControlCommand('sh', <String>[
      '-c',
      _linuxSystemLogsScript,
      'flutter_cockpit_linux_logs',
      '$count',
    ]);
  }

  CockpitResolvedSystemControlCommand _desktopSettingsCommand(
    CockpitSystemControlActionRequest request, {
    required String defaultTarget,
    required CockpitResolvedSystemControlCommand Function(String target)
    factory,
  }) {
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
    final value = settingsAction.value?.trim();
    return factory(value == null || value.isEmpty ? defaultTarget : value);
  }

  CockpitResolvedSystemControlCommand _macosSetAppearanceCommand(
    String appearance,
  ) {
    final darkMode = appearance.trim().toLowerCase() == 'dark';
    return CockpitResolvedSystemControlCommand('osascript', <String>[
      '-e',
      'tell application "System Events" to tell appearance preferences to set dark mode to $darkMode',
    ]);
  }

  CockpitResolvedSystemControlCommand _macosResetPermissionCommand(
    CockpitSystemControlActionRequest request,
  ) {
    final service = cockpitReadSystemControlStringParameter(
      request.parameters,
      'permission',
      allowedValues: CockpitSystemControlAllowedValues.macosTccServices,
    );
    final parameterAppId = cockpitReadSystemControlStringParameter(
      request.parameters,
      'appId',
    );
    if (service.isInvalid || parameterAppId.isInvalid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'invalidSystemActionParameter',
        message:
            'resetPermission requires a valid macOS TCC service and optional string appId.',
      );
    }
    if (!service.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message:
            'resetPermission requires a permission (TCC service) parameter.',
      );
    }
    final topLevelAppId = request.appId?.trim();
    final appId =
        parameterAppId.value ??
        (topLevelAppId == null || topLevelAppId.isEmpty ? null : topLevelAppId);
    return CockpitResolvedSystemControlCommand('tccutil', <String>[
      'reset',
      _macosTccServiceName(service.value!),
      ?appId,
    ]);
  }

  String _macosTccServiceName(String value) {
    return switch (value.trim().toLowerCase()) {
      'all' => 'All',
      'accessibility' => 'Accessibility',
      'addressbook' => 'AddressBook',
      'calendar' => 'Calendar',
      'camera' => 'Camera',
      'microphone' => 'Microphone',
      'photos' => 'Photos',
      'reminders' => 'Reminders',
      'screencapture' => 'ScreenCapture',
      _ => value,
    };
  }

  CockpitResolvedSystemControlCommand _desktopNotificationCommand(
    CockpitSystemControlActionRequest request, {
    required CockpitResolvedSystemControlCommand Function(
      String title,
      String body,
    )
    factory,
  }) {
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
        message: 'postNotification accepts string title and body.',
      );
    }
    final resolvedTitle = title.value?.trim() ?? '';
    final resolvedBody = body.value?.trim() ?? '';
    if (resolvedTitle.isEmpty && resolvedBody.isEmpty) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'postNotification requires title or body.',
      );
    }
    return factory(
      resolvedTitle.isEmpty ? resolvedBody : resolvedTitle,
      resolvedBody,
    );
  }

  CockpitResolvedSystemControlCommand _posixHostFileCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return _hostFileTransferCommand(request, (sourcePath, destinationPath) {
      return CockpitResolvedSystemControlCommand('sh', <String>[
        '-c',
        _posixHostFileCopyScript,
        'flutter_cockpit_host_file',
        sourcePath,
        destinationPath,
      ]);
    });
  }

  CockpitResolvedSystemControlCommand _windowsHostFileCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return _hostFileTransferCommand(request, (sourcePath, destinationPath) {
      return _windowsPowershell(
        _windowsHostFileCopyScript,
        arguments: <String>[sourcePath, destinationPath],
      );
    });
  }

  CockpitResolvedSystemControlCommand _hostFileTransferCommand(
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

  CockpitResolvedSystemControlCommand _posixHostAddMediaCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return _hostAddMediaCommand(request, (sourcePath, destinationPath) {
      return CockpitResolvedSystemControlCommand('sh', <String>[
        '-c',
        _posixHostAddMediaScript,
        'flutter_cockpit_host_media',
        sourcePath,
        destinationPath ?? '',
      ]);
    });
  }

  CockpitResolvedSystemControlCommand _windowsHostAddMediaCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return _hostAddMediaCommand(request, (sourcePath, destinationPath) {
      return _windowsPowershell(
        _windowsHostAddMediaScript,
        arguments: <String>[sourcePath, destinationPath ?? ''],
      );
    });
  }

  CockpitResolvedSystemControlCommand _hostAddMediaCommand(
    CockpitSystemControlActionRequest request,
    CockpitResolvedSystemControlCommand Function(
      String sourcePath,
      String? destinationPath,
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
            'addMedia requires string sourcePath and optional destinationPath parameters.',
      );
    }
    if (!sourcePath.isValid) {
      return const CockpitResolvedSystemControlCommand.error(
        code: 'missingSystemActionParameter',
        message: 'addMedia requires a sourcePath parameter.',
      );
    }
    return factory(sourcePath.value!, destinationPath.value);
  }

  String _normalizeDesktopKeyForXdotool(String key) {
    final trimmed = key.trim();
    return switch (trimmed.toLowerCase()) {
      'enter' || 'return' => 'Return',
      'escape' || 'esc' => 'Escape',
      'tab' => 'Tab',
      'backspace' => 'BackSpace',
      'delete' => 'Delete',
      'space' => 'space',
      _ => trimmed,
    };
  }

  List<String>? _targetArgs(CockpitSystemControlActionRequest request) {
    final processId = request.processId;
    if (processId != null) {
      return <String>['processId', '$processId'];
    }
    final appId = request.appId?.trim();
    if (appId != null && appId.isNotEmpty) {
      return <String>['appId', appId];
    }
    final parameterAppId = cockpitReadFirstSystemControlStringParameter(
      request.parameters,
      const <String>['appId', 'packageId'],
    );
    if (parameterAppId.isValid) {
      return <String>['appId', parameterAppId.value!];
    }
    return null;
  }

  _UiTreeReadLimits _uiTreeReadLimits(
    CockpitSystemControlActionRequest request,
  ) {
    final maxDepth = cockpitReadSystemControlIntParameter(
      request.parameters,
      'maxDepth',
      minimum: 1,
    );
    final maxNodes = cockpitReadSystemControlIntParameter(
      request.parameters,
      'maxNodes',
      minimum: 1,
    );
    if (maxDepth.isInvalid || maxNodes.isInvalid) {
      return const _UiTreeReadLimits.error(
        CockpitResolvedSystemControlCommand.error(
          code: 'invalidSystemActionParameter',
          message:
              'readUiTree requires positive integer maxDepth and maxNodes parameters.',
        ),
      );
    }
    return _UiTreeReadLimits.values(<String>[
      '${maxDepth.value ?? 16}',
      '${maxNodes.value ?? 2000}',
    ]);
  }

  CockpitResolvedSystemControlCommand _unsupportedCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return CockpitResolvedSystemControlCommand.error(
      code: 'unsupportedSystemAction',
      message: '${request.action.name} is not executable on $platform.',
    );
  }

  CockpitSystemControlCapability _coordinateInputCapability(
    CockpitSystemControlAction action,
  ) {
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.deviceSystemPlane,
      availability: CockpitSystemControlAvailability.available,
      strategy: inputStrategy,
      requires: _coordinateInputRequires,
      limitations: <String>[
        ...limitations,
        'coordinate input has no semantic locator',
      ],
      parameters: switch (action) {
        CockpitSystemControlAction.longPress =>
          CockpitSystemControlParameterSets.longPress,
        CockpitSystemControlAction.drag =>
          CockpitSystemControlParameterSets.drag,
        _ => CockpitSystemControlParameterSets.coordinate,
      },
    );
  }

  CockpitSystemControlCapability _targetedInputCapability(
    CockpitSystemControlAction action, {
    required bool hasInputTarget,
  }) {
    final isMacosSystemDialog =
        platform == 'macos' &&
        action == CockpitSystemControlAction.dismissSystemDialog;
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.nativeUiPlane,
      availability: hasInputTarget
          ? CockpitSystemControlAvailability.available
          : CockpitSystemControlAvailability.blocked,
      strategy: isMacosSystemDialog
          ? 'AXUIElement dialog action'
          : inputStrategy,
      requires: <String>[
        ...(isMacosSystemDialog
            ? const <String>['Accessibility permission']
            : _targetedInputRequires),
        if (!hasInputTarget) 'app id or process id',
      ],
      limitations: <String>[
        ...limitations,
        if (isMacosSystemDialog)
          'Only a real target-owned accessible sheet or modal dialog is changed; no dialog is a safe no-op.',
      ],
      parameters: switch (action) {
        CockpitSystemControlAction.typeText =>
          CockpitSystemControlParameterSets.text,
        CockpitSystemControlAction.pressKey =>
          CockpitSystemControlParameterSets.key,
        CockpitSystemControlAction.dismissSystemDialog =>
          CockpitSystemControlParameterSets.systemDialogDecision,
        _ => const <CockpitSystemControlParameter>[],
      },
    );
  }

  CockpitSystemControlCapability _activationCapability(
    CockpitSystemControlAction action, {
    required bool hasInputTarget,
  }) {
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.nativeUiPlane,
      availability: hasInputTarget
          ? CockpitSystemControlAvailability.available
          : CockpitSystemControlAvailability.blocked,
      strategy: _activationStrategy,
      requires: <String>[
        ..._activationRequires,
        if (!hasInputTarget) 'app id or process id',
      ],
      limitations: limitations,
    );
  }

  CockpitSystemControlCapability _hostBlocked(
    CockpitSystemControlAction action,
    String strategy, {
    required List<String> requires,
  }) {
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.hostPlane,
      availability: CockpitSystemControlAvailability.blocked,
      strategy: strategy,
      requires: requires,
      limitations: limitations,
      parameters: switch (action) {
        CockpitSystemControlAction.setAppearance =>
          CockpitSystemControlParameterSets.hostAppearance,
        CockpitSystemControlAction.setContentSize =>
          CockpitSystemControlParameterSets.hostContentSize,
        CockpitSystemControlAction.setNetworkSpeed =>
          CockpitSystemControlParameterSets.hostNetworkSpeed,
        CockpitSystemControlAction.setNetworkDelay =>
          CockpitSystemControlParameterSets.hostNetworkDelay,
        _ => const <CockpitSystemControlParameter>[],
      },
    );
  }

  CockpitSystemControlCapability _uiTreeCapability({
    required bool hasInputTarget,
  }) {
    final isSupported = platform == 'macos' || platform == 'windows';
    return CockpitSystemControlCapability(
      action: CockpitSystemControlAction.readUiTree,
      plane: CockpitPlaneKind.nativeUiPlane,
      availability: isSupported && hasInputTarget
          ? CockpitSystemControlAvailability.available
          : CockpitSystemControlAvailability.blocked,
      strategy: _uiTreeStrategy,
      requires: <String>[
        ..._uiTreeRequires,
        if (!hasInputTarget) 'app id or process id',
      ],
      limitations: limitations,
      parameters: CockpitSystemControlParameterSets.readUiTree,
    );
  }

  CockpitSystemControlCapability _unsupported(
    CockpitSystemControlAction action,
    String strategy,
    String limitation,
  ) {
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.hostPlane,
      availability: CockpitSystemControlAvailability.unsupported,
      strategy: strategy,
      limitations: <String>[...limitations, limitation],
    );
  }

  CockpitSystemControlCapability _evidenceCapability(
    CockpitSystemControlAction action,
    String strategy, {
    required bool hasWindowTarget,
    List<String> extraRequires = const <String>[],
  }) {
    return CockpitSystemControlCapability(
      action: action,
      plane: CockpitPlaneKind.hostPlane,
      availability: hasWindowTarget
          ? CockpitSystemControlAvailability.available
          : CockpitSystemControlAvailability.blocked,
      strategy: strategy,
      requires: <String>[
        ...(action == CockpitSystemControlAction.captureScreenshot
            ? _screenshotRequires
            : _recordingRequires),
        if (!hasWindowTarget) _evidenceTargetRequirement,
        ...extraRequires,
      ],
      limitations: limitations,
      parameters: switch (action) {
        CockpitSystemControlAction.captureScreenshot =>
          CockpitSystemControlParameterSets.screenshot,
        CockpitSystemControlAction.startRecording =>
          CockpitSystemControlParameterSets.startRecording,
        CockpitSystemControlAction.stopRecording =>
          CockpitSystemControlParameterSets.stopRecording,
        _ => const <CockpitSystemControlParameter>[],
      },
    );
  }

  String get _evidenceTargetRequirement {
    if (platform == 'macos') {
      return 'app id';
    }
    return 'app id or process id';
  }

  static const String _macosMouseScript = r'''
function run(argv) {
  const targetKind = argv[0]
  const targetValue = argv[1]
  const action = argv[2]
  const startX = Number(argv[3])
  const startY = Number(argv[4])
  const endX = Number(argv[5])
  const endY = Number(argv[6])
  const durationMs = Number(argv[7] || '0')
  ObjC.import('ApplicationServices')
  ObjC.import('AppKit')
  let app = null
  if (targetKind === 'processId') {
    app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(Number(targetValue))
  } else {
    const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(targetValue)
    if (apps.count > 0) app = apps.objectAtIndex(0)
  }
  if (!app) throw new Error(`No running macOS application found for ${targetKind}:${targetValue}`)
  if (!app.activateWithOptions($.NSApplicationActivateIgnoringOtherApps)) {
    throw new Error(`Unable to activate macOS application ${targetKind}:${targetValue}`)
  }
  const activationDeadline = Date.now() + 1000
  while (!app.active && Date.now() < activationDeadline) delay(0.01)
  if (!app.active) throw new Error(`macOS application did not become active: ${targetKind}:${targetValue}`)
  delay(0.1)
  const eventTap = 0
  const leftButton = 0
  const mouseDown = 1
  const mouseUp = 2
  const mouseDragged = 6
  function point(x, y) { return $.CGPointMake(x, y) }
  function post(kind, x, y) {
    const event = $.CGEventCreateMouseEvent(null, kind, point(x, y), leftButton)
    $.CGEventPost(eventTap, event)
  }
  post(mouseDown, startX, startY)
  if (action === 'drag') {
    delay(Math.max(durationMs, 1) / 1000.0)
    post(mouseDragged, endX, endY)
  } else if (action === 'longPress') {
    delay(Math.max(durationMs, 1) / 1000.0)
  } else {
    delay(0.05)
  }
  post(mouseUp, endX, endY)
}
''';

  static const String _macosActivateTargetScript = r'''
ObjC.import('AppKit')

function run(argv) {
  const targetKind = argv[0]
  const targetValue = argv[1]
  let app = null
  if (targetKind === 'processId') {
    app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(Number(targetValue))
  } else {
    const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(targetValue)
    if (apps.count > 0) app = apps.objectAtIndex(0)
  }
  if (!app) throw new Error(`No running macOS application found for ${targetKind}:${targetValue}`)
  if (!app.activateWithOptions($.NSApplicationActivateIgnoringOtherApps)) {
    throw new Error(`Unable to activate macOS application ${targetKind}:${targetValue}`)
  }
}
''';

  static const String _macosTypeTextScript = r'''
on run argv
  set targetKind to item 1 of argv
  set targetValue to item 2 of argv
  set textValue to item 3 of argv
  if targetKind is "appId" then
    tell application id targetValue to activate
  else
    tell application "System Events"
      set frontmost of first application process whose unix id is (targetValue as integer) to true
    end tell
  end if
  tell application "System Events" to keystroke textValue
end run
''';

  static const String _macosPressKeyScript = r'''
on run argv
  set targetKind to item 1 of argv
  set targetValue to item 2 of argv
  set keyValue to item 3 of argv
  set repeatValue to (item 4 of argv) as integer
  if targetKind is "appId" then
    tell application id targetValue to activate
  else
    tell application "System Events"
      set frontmost of first application process whose unix id is (targetValue as integer) to true
    end tell
  end if
  set normalizedKey to do shell script "printf %s " & quoted form of keyValue & " | tr '[:upper:]' '[:lower:]'"
  tell application "System Events"
    repeat repeatValue times
      if normalizedKey is "enter" or normalizedKey is "return" then
        key code 36
      else if normalizedKey is "escape" or normalizedKey is "esc" then
        key code 53
      else if normalizedKey is "tab" then
        key code 48
      else if normalizedKey is "backspace" or normalizedKey is "delete" then
        key code 51
      else if normalizedKey is "space" then
        key code 49
      else
        keystroke keyValue
      end if
    end repeat
  end tell
end run
''';

  static const String _macosPressBackScript = r'''
on run argv
  set targetKind to item 1 of argv
  set targetValue to item 2 of argv
  if targetKind is "appId" then
    tell application id targetValue to activate
  else
    tell application "System Events"
      set frontmost of first application process whose unix id is (targetValue as integer) to true
    end tell
  end if
  tell application "System Events" to key code 53
end run
''';

  static const String _macosTerminateTargetScript = r'''
on run argv
  set targetKind to item 1 of argv
  set targetValue to item 2 of argv
  if targetKind is "appId" then
    tell application id targetValue to quit
  else
    do shell script "kill -TERM " & quoted form of targetValue
  end if
end run
''';

  static const String _macosReadWindowsScript = r'''
function run() {
  const systemEvents = Application('System Events')
  const processes = systemEvents.applicationProcesses.whose({ visible: true })()
  const windows = []
  function readString(factory) {
    try {
      const value = factory()
      if (value === undefined || value === null) return undefined
      const text = String(value)
      return text.length === 0 ? undefined : text
    } catch (_) {
      return undefined
    }
  }
  function readFrame(window) {
    try {
      const position = window.position()
      const size = window.size()
      return { x: Number(position[0]), y: Number(position[1]), width: Number(size[0]), height: Number(size[1]) }
    } catch (_) {
      return undefined
    }
  }
  for (let i = 0; i < processes.length; i += 1) {
    const process = processes[i]
    let processWindows = []
    try {
      processWindows = process.windows()
    } catch (_) {
      processWindows = []
    }
    for (let j = 0; j < processWindows.length; j += 1) {
      const window = processWindows[j]
      const item = {
        processName: readString(() => process.name()),
        processId: Number(process.unixId()),
        title: readString(() => window.title()) || readString(() => window.name())
      }
      const frame = readFrame(window)
      if (frame) item.frame = frame
      windows.push(item)
    }
  }
  return JSON.stringify({ platform: 'macos', windows })
}
''';

  static const String _windowsReadUiTreeScript = r'''
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$targetKind = $args[0]
$targetValue = $args[1]
$maxDepth = [Math]::Max(0, [int]$args[2])
$maxNodes = [Math]::Max(1, [int]$args[3])
if ($targetKind -eq 'processId') {
  $process = Get-Process -Id ([int]$targetValue) -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
} elseif ($targetKind -eq 'appId') {
  $process = Get-Process -Name $targetValue -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Sort-Object -Property Id -Descending |
    Select-Object -First 1
} else {
  throw "Unsupported target kind: $targetKind"
}
if ($null -eq $process) {
  throw "No visible Windows window was found for $targetKind $targetValue."
}
$root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$process.MainWindowHandle)
if ($null -eq $root) {
  throw "UI Automation could not resolve the target window."
}
$script:nodeCount = 0
function Read-Bounds($element) {
  try {
    $rect = $element.Current.BoundingRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return $null }
    return @{
      x = [int]$rect.X
      y = [int]$rect.Y
      width = [int]$rect.Width
      height = [int]$rect.Height
    }
  } catch {
    return $null
  }
}
function Read-Node($element, [int]$depth) {
  if ($script:nodeCount -ge $maxNodes) { return $null }
  $script:nodeCount += 1
  $controlType = ''
  try { $controlType = $element.Current.ControlType.ProgrammaticName -replace '^ControlType\.', '' } catch {}
  $node = [ordered]@{}
  if (-not [string]::IsNullOrWhiteSpace($controlType)) { $node.controlType = $controlType }
  if (-not [string]::IsNullOrWhiteSpace($element.Current.Name)) { $node.name = $element.Current.Name }
  if (-not [string]::IsNullOrWhiteSpace($element.Current.AutomationId)) { $node.automationId = $element.Current.AutomationId }
  if (-not [string]::IsNullOrWhiteSpace($element.Current.ClassName)) { $node.className = $element.Current.ClassName }
  $bounds = Read-Bounds $element
  if ($null -ne $bounds) { $node.frame = $bounds }
  if ($depth -lt $maxDepth -and $script:nodeCount -lt $maxNodes) {
    $children = @()
    try {
      $rawChildren = $element.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
      )
      foreach ($childElement in $rawChildren) {
        if ($script:nodeCount -ge $maxNodes) { break }
        $child = Read-Node $childElement ($depth + 1)
        if ($null -ne $child) { $children += $child }
      }
    } catch {}
    if ($children.Count -gt 0) { $node.children = $children }
  }
  return $node
}
$tree = Read-Node $root 0
[pscustomobject]@{
  platform = 'windows'
  target = @{
    kind = $targetKind
    value = $targetValue
    processId = $process.Id
  }
  maxDepth = $maxDepth
  maxNodes = $maxNodes
  nodeCount = $script:nodeCount
  truncated = ($script:nodeCount -ge $maxNodes)
  tree = $tree
} | ConvertTo-Json -Depth 64 -Compress
''';

  static const String _windowsTerminateScript = r'''
$targetKind = $args[0]
$targetValue = $args[1]
if ($targetKind -eq 'processId') {
  Stop-Process -Id ([int]$targetValue) -Force
} elseif ($targetKind -eq 'appId') {
  Get-Process -Name $targetValue -ErrorAction Stop | Stop-Process -Force
} else {
  throw "Unsupported target kind: $targetKind"
}
''';

  static const String _linuxTargetedXdotoolScript = r'''
target_kind="$1"
target_value="$2"
shift 2
window_id=""
if [ "$target_kind" = "processId" ]; then
  window_id="$(xdotool search --onlyvisible --pid "$target_value" 2>/dev/null | head -n 1)"
elif [ "$target_kind" = "appId" ]; then
  window_id="$(xdotool search --onlyvisible --class "$target_value" 2>/dev/null | head -n 1)"
fi
if [ -z "$window_id" ]; then
  exit 65
fi
if ! xdotool windowactivate --sync "$window_id" 2>/dev/null; then
  xdotool windowmap --sync "$window_id"
  xdotool windowraise "$window_id"
  xdotool windowfocus --sync "$window_id"
fi
if [ "$#" -eq 0 ]; then
  exit 0
fi
exec xdotool "$@"
''';

  static const String _linuxTerminateScript = r'''
target_kind="$1"
target_value="$2"
if [ "$target_kind" = "processId" ]; then
  exec kill -TERM "$target_value"
elif [ "$target_kind" = "appId" ]; then
  exec pkill -TERM -f "$target_value"
fi
exit 64
''';

  static const String _linuxSetClipboardScript = r'''
text="$1"
if command -v wl-copy >/dev/null 2>&1; then
  printf "%s" "$text" | wl-copy
elif command -v xclip >/dev/null 2>&1; then
  printf "%s" "$text" | xclip -selection clipboard
elif command -v xsel >/dev/null 2>&1; then
  printf "%s" "$text" | xsel --clipboard --input
else
  exit 65
fi
''';

  static const String _linuxGetClipboardScript = r'''
if command -v wl-paste >/dev/null 2>&1; then
  wl-paste --no-newline
elif command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard -out
elif command -v xsel >/dev/null 2>&1; then
  xsel --clipboard --output
else
  exit 65
fi
''';

  static const String _linuxReadWindowsScript = r'''
if command -v wmctrl >/dev/null 2>&1; then
  exec wmctrl -lp
elif command -v xdotool >/dev/null 2>&1; then
  ids="$(xdotool search --onlyvisible --name "" 2>/dev/null || true)"
  for id in $ids; do
    name="$(xdotool getwindowname "$id" 2>/dev/null || true)"
    pid="$(xdotool getwindowpid "$id" 2>/dev/null || true)"
    printf "%s %s %s\n" "$id" "$pid" "$name"
  done
else
  exit 65
fi
''';

  static const String _macosReadFocusStateScript = r'''
tell application "System Events"
  set frontProcess to first application process whose frontmost is true
  set procName to name of frontProcess
  set procId to unix id of frontProcess
  set windowTitle to ""
  try
    set windowTitle to name of front window of frontProcess
  end try
end tell
return "process=" & procName & linefeed & "pid=" & procId & linefeed & "window=" & windowTitle
''';

  static const String _macosPostNotificationScript = r'''
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
''';

  static const String _windowsSetAppearanceScript = r'''
$mode = $args[0]
$value = if ($mode -eq 'dark') { 0 } else { 1 }
$path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name AppsUseLightTheme -Value $value -Type DWord
Set-ItemProperty -Path $path -Name SystemUsesLightTheme -Value $value -Type DWord
''';

  static const String _linuxSystemLogsScript = r'''
if ! command -v journalctl >/dev/null 2>&1; then
  echo "flutter_cockpit: journalctl (systemd) is required to read Linux system logs" >&2
  exit 65
fi
journalctl --user --no-pager -n "$1" 2>/dev/null || journalctl --no-pager -n "$1"
''';

  static const String _linuxReadFocusStateScript = r'''
if ! command -v xdotool >/dev/null 2>&1; then
  echo "flutter_cockpit: xdotool is required to read Linux focus state" >&2
  exit 65
fi
window_id="$(xdotool getactivewindow 2>/dev/null || true)"
if [ -z "$window_id" ]; then
  printf "windowId=\nname=\npid=\nstate=no-active-window\n"
  exit 0
fi
printf "windowId=%s\nname=%s\npid=%s\n" \
  "$window_id" \
  "$(xdotool getwindowname "$window_id" 2>/dev/null || true)" \
  "$(xdotool getwindowpid "$window_id" 2>/dev/null || true)"
''';

  static const String _linuxSetAppearanceScript = r'''
mode="$1"
if ! command -v gsettings >/dev/null 2>&1; then
  echo "flutter_cockpit: gsettings is required to change the Linux color scheme" >&2
  exit 65
fi
case "$mode" in
  dark) exec gsettings set org.gnome.desktop.interface color-scheme prefer-dark ;;
  light) exec gsettings set org.gnome.desktop.interface color-scheme prefer-light ;;
  *) exit 64 ;;
esac
''';

  static const String _linuxPostNotificationScript = r'''
if ! command -v notify-send >/dev/null 2>&1; then
  echo "flutter_cockpit: notify-send (libnotify) is required to post Linux notifications" >&2
  exit 65
fi
if [ -n "$2" ]; then
  exec notify-send "$1" "$2"
fi
exec notify-send "$1"
''';

  static const String _posixHostFileCopyScript = r'''
mkdir -p "$(dirname "$2")" && cp -R "$1" "$2"
''';

  static const String _posixHostAddMediaScript = r'''
src="$1"
dst="$2"
if [ -z "$dst" ]; then
  dst="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}/$(basename "$src")"
fi
mkdir -p "$(dirname "$dst")" && cp -R "$src" "$dst" && printf "%s\n" "$dst"
''';

  static const String _windowsHostFileCopyScript = r'''
$source = $args[0]
$destination = $args[1]
$parent = Split-Path -Parent $destination
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
Copy-Item -Path $source -Destination $destination -Recurse -Force
''';

  static const String _windowsHostAddMediaScript = r'''
$source = $args[0]
$destination = $args[1]
if ([string]::IsNullOrWhiteSpace($destination)) {
  $destination = Join-Path (Join-Path $env:USERPROFILE 'Downloads') (Split-Path -Leaf $source)
}
$parent = Split-Path -Parent $destination
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
Copy-Item -Path $source -Destination $destination -Recurse -Force
Write-Output $destination
''';
}

final class CockpitWebSystemControlAdapter
    implements CockpitSystemControlAdapter {
  const CockpitWebSystemControlAdapter();

  @override
  String get platform => 'web';

  @override
  CockpitSystemControlProfile describe(
    CockpitSystemControlTargetContext target,
  ) {
    final hasEvidenceTarget = target.hasWindowTarget;
    return CockpitSystemControlProfile(
      platform: platform,
      deviceId: target.deviceId,
      appId: target.appId,
      processId: target.processId,
      adapter: 'browser.dom+host-recording',
      preferredPlane: CockpitPlaneKind.flutterSemanticPlane,
      fallbackOrder: const <CockpitPlaneKind>[
        CockpitPlaneKind.flutterSemanticPlane,
        CockpitPlaneKind.nativeUiPlane,
        CockpitPlaneKind.hostPlane,
      ],
      recommendedNextStep: 'preferFlutterSemanticPlane',
      capabilities: cockpitCompleteSystemControlCapabilities(
        <CockpitSystemControlCapability>[
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.tap,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.dom.click',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.coordinate,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.longPress,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.dom.pointer.longPress',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.longPress,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.drag,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.dom.pointer.drag',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.drag,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.typeText,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.dom.input',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.text,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressKey,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.keyboard.press',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.key,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressBack,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.navigation.back',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressHome,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-home-key',
            limitations: <String>[
              'Browsers do not expose a stable app-scoped Home key.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeUp,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-volume-key',
            limitations: <String>[
              'Browsers cannot safely change host volume from an app-scoped automation bridge.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeDown,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-volume-key',
            limitations: <String>[
              'Browsers cannot safely change host volume from an app-scoped automation bridge.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.pressVolumeMute,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-volume-key',
            limitations: <String>[
              'Browsers cannot safely change host volume from an app-scoped automation bridge.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.activateWindow,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.window.focus',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.terminateApp,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.close',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.dismissSystemDialog,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.dialog.dismiss',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.dismissKeyboard,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.keyboard.escape-or-blur',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.grantPermission,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.permissions',
            requires: <String>['browser driver or bridge'],
            parameters:
                CockpitSystemControlParameterSets.browserGrantPermission,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openUrl,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.page.goto',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.url,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.openSystemSettings,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-system-settings',
            limitations: <String>[
              'Browsers do not expose app-scoped system settings.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setAppearance,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.emulateMedia',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.hostAppearance,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setContentSize,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.viewport-or-accessibility-emulation',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.hostContentSize,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setLocation,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.geolocation',
            requires: <String>[
              'browser driver or bridge',
              'geolocation permission',
            ],
            parameters: CockpitSystemControlParameterSets.location,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setOrientation,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.viewport-or-orientation-emulation',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.browserOrientation,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setNetworkSpeed,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.route-or-cdp-network-emulation',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.hostNetworkSpeed,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setNetworkDelay,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.route-or-cdp-network-emulation',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.hostNetworkDelay,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setStatusBar,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-system-status-bar',
            limitations: <String>[
              'Browsers do not expose an app-scoped system status bar override.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearStatusBar,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-system-status-bar',
            limitations: <String>[
              'Browsers do not expose an app-scoped system status bar override.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.expandNotifications,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-notification-center',
            limitations: <String>[
              'Browsers do not expose the host notification center to page automation.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.expandQuickSettings,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-quick-settings',
            limitations: <String>[
              'Browsers do not expose host quick settings to page automation.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.collapseSystemUi,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-system-ui',
            limitations: <String>[
              'Browsers do not expose host system UI panels to page automation.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.postNotification,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser-notification-api',
            requires: <String>[
              'browser driver or bridge',
              'notification permission',
            ],
            parameters: CockpitSystemControlParameterSets.notification,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.clearNotifications,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-notification-clear',
            limitations: <String>[
              'Browsers cannot clear delivered host notifications through page automation.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.setClipboard,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.clipboard.writeText',
            requires: <String>[
              'browser driver or bridge',
              'clipboard permission',
            ],
            parameters: CockpitSystemControlParameterSets.text,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.getClipboard,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.clipboard.readText',
            requires: <String>[
              'browser driver or bridge',
              'clipboard permission',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.captureScreenshot,
            plane: CockpitPlaneKind.hostPlane,
            availability: hasEvidenceTarget
                ? CockpitSystemControlAvailability.available
                : CockpitSystemControlAvailability.blocked,
            strategy: 'browser.host-window-capture',
            requires: <String>[
              'host window capture tooling',
              'browser app id or process id (macOS hosts require app id)',
              if (!hasEvidenceTarget) 'app id or process id',
            ],
            parameters: CockpitSystemControlParameterSets.screenshot,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.startRecording,
            plane: CockpitPlaneKind.hostPlane,
            availability: hasEvidenceTarget
                ? CockpitSystemControlAvailability.available
                : CockpitSystemControlAvailability.blocked,
            strategy: 'browser.host-window-recording',
            requires: <String>[
              'ffmpeg',
              'host screen capture permission',
              'browser app id or process id (macOS hosts require app id)',
              if (!hasEvidenceTarget) 'app id or process id',
            ],
            parameters: CockpitSystemControlParameterSets.startRecording,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.stopRecording,
            plane: CockpitPlaneKind.hostPlane,
            availability: hasEvidenceTarget
                ? CockpitSystemControlAvailability.available
                : CockpitSystemControlAvailability.blocked,
            strategy: 'browser.host-window-recording.stop',
            requires: <String>[
              'ffmpeg',
              'host screen capture permission',
              'browser app id or process id (macOS hosts require app id)',
              if (!hasEvidenceTarget) 'app id or process id',
              'active recording session',
            ],
            parameters: CockpitSystemControlParameterSets.stopRecording,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readUiTree,
            plane: CockpitPlaneKind.nativeUiPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.accessibility.snapshot',
            requires: <String>['browser driver or bridge'],
            parameters: CockpitSystemControlParameterSets.readUiTree,
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readProcessList,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-process-list',
            limitations: <String>[
              'Browser pages do not expose host process lists; use host target tools.',
            ],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readWindows,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.pages',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.readSystemState,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.blocked,
            strategy: 'browser.context.state',
            requires: <String>['browser driver or bridge'],
          ),
          CockpitSystemControlCapability(
            action: CockpitSystemControlAction.runShell,
            plane: CockpitPlaneKind.hostPlane,
            availability: CockpitSystemControlAvailability.unsupported,
            strategy: 'browser-no-shell',
            limitations: <String>[
              'Browser pages do not expose a system shell; use host or target shell separately.',
            ],
          ),
        ],
        plane: CockpitPlaneKind.hostPlane,
        availability: CockpitSystemControlAvailability.unsupported,
        strategy: 'browser-action-not-supported',
        limitations: const <String>[
          'This action is not implemented for browser page automation.',
        ],
      ),
    );
  }

  @override
  CockpitResolvedSystemControlCommand resolveCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return const CockpitResolvedSystemControlCommand.error(
      code: 'systemActionBlocked',
      message:
          'Browser system actions require an active browser bridge; use Flutter or browser-specific target tools.',
    );
  }
}

final class CockpitUnsupportedSystemControlAdapter
    implements CockpitSystemControlAdapter {
  const CockpitUnsupportedSystemControlAdapter(this.platform);

  @override
  final String platform;

  @override
  CockpitSystemControlProfile describe(
    CockpitSystemControlTargetContext target,
  ) {
    return CockpitSystemControlProfile(
      platform: platform,
      deviceId: target.deviceId,
      appId: target.appId,
      processId: target.processId,
      adapter: 'unsupported',
      preferredPlane: CockpitPlaneKind.flutterSemanticPlane,
      fallbackOrder: const <CockpitPlaneKind>[
        CockpitPlaneKind.flutterSemanticPlane,
        CockpitPlaneKind.hostPlane,
      ],
      recommendedNextStep: 'useFlutterOrHostFallback',
      capabilities: CockpitSystemControlAction.values
          .map(
            (action) => CockpitSystemControlCapability(
              action: action,
              plane: CockpitPlaneKind.hostPlane,
              availability: CockpitSystemControlAvailability.unsupported,
              strategy: 'unsupported',
              limitations: <String>['No system control adapter for $platform'],
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  CockpitResolvedSystemControlCommand resolveCommand(
    CockpitSystemControlActionRequest request,
  ) {
    return CockpitResolvedSystemControlCommand.error(
      code: 'unsupportedPlatform',
      message: 'No system control adapter for $platform.',
    );
  }
}

final class _UiTreeReadLimits {
  const _UiTreeReadLimits.values(this.values) : error = null;

  const _UiTreeReadLimits.error(this.error) : values = const <String>[];

  final List<String> values;
  final CockpitResolvedSystemControlCommand? error;
}

int? _pressKeyRepeat(CockpitSystemControlActionRequest request) {
  final repeat = cockpitReadSystemControlIntParameter(
    request.parameters,
    'repeat',
    minimum: 1,
    maximum: 500,
  );
  return repeat.isInvalid ? null : repeat.value ?? 1;
}

const CockpitResolvedSystemControlCommand _invalidPressKeyRepeat =
    CockpitResolvedSystemControlCommand.error(
      code: 'invalidSystemActionParameter',
      message: 'pressKey repeat must be between 1 and 500.',
    );
