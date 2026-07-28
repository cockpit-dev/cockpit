import 'cockpit_system_control_profile.dart';

final class CockpitSystemControlAllowedValues {
  const CockpitSystemControlAllowedValues._();

  static const iosPrivacyServices = <String>[
    'all',
    'calendar',
    'contacts-limited',
    'contacts',
    'location',
    'location-always',
    'photos-add',
    'photos',
    'media-library',
    'microphone',
    'motion',
    'reminders',
    'siri',
  ];

  static const iosContentSizeCategories = <String>[
    'extra-small',
    'small',
    'medium',
    'large',
    'extra-large',
    'extra-extra-large',
    'extra-extra-extra-large',
    'accessibility-medium',
    'accessibility-large',
    'accessibility-extra-large',
    'accessibility-extra-extra-large',
    'accessibility-extra-extra-extra-large',
    'increment',
    'decrement',
  ];

  static const iosStatusBarDataNetworks = <String>[
    'hide',
    'wifi',
    '3g',
    '4g',
    'lte',
    'lte-a',
    'lte+',
    '5g',
    '5g+',
    '5g-uwb',
    '5g-uc',
  ];

  static const iosStatusBarWifiModes = <String>[
    'searching',
    'failed',
    'active',
  ];

  static const iosStatusBarCellularModes = <String>[
    'notSupported',
    'searching',
    'failed',
    'active',
  ];

  static const iosStatusBarBatteryStates = <String>[
    'charging',
    'charged',
    'discharging',
  ];

  static const androidStatusBarDataNetworks = <String>[
    'hide',
    'wifi',
    '3g',
    '4g',
    'lte',
  ];

  static const androidStatusBarSignalModes = <String>['active', 'hide'];

  static const macosTccServices = <String>[
    'all',
    'accessibility',
    'addressbook',
    'calendar',
    'camera',
    'microphone',
    'photos',
    'reminders',
    'screencapture',
  ];
}

final class CockpitSystemControlParameterSets {
  const CockpitSystemControlParameterSets._();

  static const coordinate = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'x',
      valueType: CockpitSystemControlParameterType.integer,
      required: true,
      description: 'Screen X coordinate in physical pixels.',
    ),
    CockpitSystemControlParameter(
      name: 'y',
      valueType: CockpitSystemControlParameterType.integer,
      required: true,
      description: 'Screen Y coordinate in physical pixels.',
    ),
  ];

  static const longPress = <CockpitSystemControlParameter>[
    ...coordinate,
    CockpitSystemControlParameter(
      name: 'durationMs',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      description: 'Hold duration in milliseconds; default is 800.',
    ),
  ];

  static const drag = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'startX',
      valueType: CockpitSystemControlParameterType.integer,
      required: true,
      description: 'Start screen X coordinate in physical pixels.',
    ),
    CockpitSystemControlParameter(
      name: 'startY',
      valueType: CockpitSystemControlParameterType.integer,
      required: true,
      description: 'Start screen Y coordinate in physical pixels.',
    ),
    CockpitSystemControlParameter(
      name: 'endX',
      valueType: CockpitSystemControlParameterType.integer,
      required: true,
      description: 'End screen X coordinate in physical pixels.',
    ),
    CockpitSystemControlParameter(
      name: 'endY',
      valueType: CockpitSystemControlParameterType.integer,
      required: true,
      description: 'End screen Y coordinate in physical pixels.',
    ),
    CockpitSystemControlParameter(
      name: 'durationMs',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      description: 'Drag duration in milliseconds; default is 300.',
    ),
  ];

  static const text = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'text',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
    ),
  ];

  static const key = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'key',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description:
          'Platform key token, for example enter, escape, tab, or KEYCODE_ENTER.',
    ),
    CockpitSystemControlParameter(
      name: 'repeat',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 500,
      description: 'Number of key presses in the same platform operation.',
    ),
  ];

  static const systemDialogDecision = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'decision',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['accept', 'dismiss'],
      description:
          'System dialog decision. accept taps the primary action; dismiss taps the cancel/deny action when available.',
    ),
  ];

  static const url = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'url',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
    ),
  ];

  static const systemSettings = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'settingsAction',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Platform settings target. Android: an android.settings.* intent action (for example android.settings.APPLICATION_DETAILS_SETTINGS). iOS simulator: a settings URL passed to simctl openurl (defaults to App-Prefs:).',
    ),
  ];

  static const androidSystemSettings = <CockpitSystemControlParameter>[
    ...systemSettings,
    CockpitSystemControlParameter(
      name: 'packageId',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Opens the application details page for this package (falls back to --app-id).',
    ),
  ];

  static const androidNotification = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'title',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification title.',
    ),
    CockpitSystemControlParameter(
      name: 'body',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification body text.',
    ),
    CockpitSystemControlParameter(
      name: 'tag',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Stable notification tag; default is cockpit.',
    ),
  ];

  static const installApp = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'appPath',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description:
          'Host path to an Android APK, iOS .app bundle, or platform package.',
    ),
    CockpitSystemControlParameter(
      name: 'grantPermissions',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'Android only: pass -g to grant runtime permissions during install.',
    ),
  ];

  static const uninstallApp = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'packageId',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Android package id; top-level appId is also accepted.',
    ),
    CockpitSystemControlParameter(
      name: 'appId',
      valueType: CockpitSystemControlParameterType.string,
      description: 'iOS bundle id; top-level appId is also accepted.',
    ),
    CockpitSystemControlParameter(
      name: 'keepData',
      valueType: CockpitSystemControlParameterType.boolean,
      description: 'Android only: keep data and cache directories.',
    ),
  ];

  static const iosNotification = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'title',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification title used to build an APNS alert payload.',
    ),
    CockpitSystemControlParameter(
      name: 'body',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification body used to build an APNS alert payload.',
    ),
    CockpitSystemControlParameter(
      name: 'payloadJson',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Full simulated APNS payload JSON. When present, title/body are ignored.',
    ),
  ];

  static const notification = <CockpitSystemControlParameter>[
    ...androidNotification,
    CockpitSystemControlParameter(
      name: 'payloadJson',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Platform notification payload JSON when supported.',
    ),
  ];

  static const tapNotification = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'title',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification title or visible text to match.',
    ),
    CockpitSystemControlParameter(
      name: 'body',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification body or secondary visible text to match.',
    ),
    CockpitSystemControlParameter(
      name: 'tag',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Stable notification tag when the platform exposes it; Android uses it as an optional match hint.',
    ),
    CockpitSystemControlParameter(
      name: 'text',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Generic visible text to match when title/body are unknown.',
    ),
  ];

  static const recoverToApp = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'packageId',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Android package id; top-level appId is also accepted.',
    ),
    CockpitSystemControlParameter(
      name: 'appId',
      valueType: CockpitSystemControlParameterType.string,
      description: 'iOS bundle id; top-level appId is also accepted.',
    ),
  ];

  static const resolveBlockers = <CockpitSystemControlParameter>[
    ...recoverToApp,
    CockpitSystemControlParameter(
      name: 'decision',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['accept', 'dismiss'],
      description:
          'Preferred system dialog decision before recovering the app; default is accept.',
    ),
    CockpitSystemControlParameter(
      name: 'dismissKeyboard',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'Whether to dismiss the keyboard before app recovery. Defaults to true.',
    ),
  ];

  static const preparePermissions = <CockpitSystemControlParameter>[
    ...recoverToApp,
    CockpitSystemControlParameter(
      name: 'permissions',
      valueType: CockpitSystemControlParameterType.stringList,
      required: true,
      description:
          'Permission names to prepare. Android uses runtime permission constants; iOS uses simctl privacy services.',
    ),
    CockpitSystemControlParameter(
      name: 'mode',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['grant', 'revoke', 'reset'],
      description: 'Permission operation to apply to each permission.',
    ),
    CockpitSystemControlParameter(
      name: 'recover',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'Whether to bring the app back to foreground after preparing permissions. Defaults to true.',
    ),
  ];

  static const stabilizeForScreenshot = <CockpitSystemControlParameter>[
    ...recoverToApp,
    CockpitSystemControlParameter(
      name: 'dismissKeyboard',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'Whether to dismiss the native keyboard before capturing evidence. Defaults to true.',
    ),
    CockpitSystemControlParameter(
      name: 'collapseSystemUi',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'Whether to collapse notification, control, or quick settings surfaces. Defaults to true.',
    ),
    CockpitSystemControlParameter(
      name: 'recover',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'Whether to bring the app back to foreground after stabilizing. Defaults to true.',
    ),
    CockpitSystemControlParameter(
      name: 'orientation',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>[
        'portrait',
        'landscape',
        'reversePortrait',
        'reverseLandscape',
        'auto',
      ],
      description:
          'Optional orientation to apply before screenshot evidence. iOS simulator requires WebDriverAgent and does not support auto.',
    ),
    CockpitSystemControlParameter(
      name: 'statusBar',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['default', 'clear', 'stable'],
      description:
          'Status bar handling. default leaves it unchanged, clear removes overrides (iOS simctl) or exits demo mode (Android), stable sets deterministic screenshot values.',
    ),
    CockpitSystemControlParameter(
      name: 'time',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Fixed status bar time such as 9:41 when statusBar=stable.',
    ),
    CockpitSystemControlParameter(
      name: 'appearance',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['light', 'dark', 'auto'],
      description:
          'Optional appearance mode to apply before screenshot evidence. iOS supports light/dark; Android also supports auto.',
    ),
  ];

  static const androidApp = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'packageId',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Android package id; top-level appId is also accepted.',
    ),
  ];

  static const iosApp = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'appId',
      valueType: CockpitSystemControlParameterType.string,
      description: 'iOS bundle id; top-level appId is also accepted.',
    ),
  ];

  static const androidGrantPermission = <CockpitSystemControlParameter>[
    ...androidApp,
    CockpitSystemControlParameter(
      name: 'permission',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description: 'Android permission name such as android.permission.CAMERA.',
    ),
  ];

  static const androidRevokePermission = <CockpitSystemControlParameter>[
    ...androidGrantPermission,
  ];

  static const androidResetPermission = <CockpitSystemControlParameter>[
    ...androidApp,
    CockpitSystemControlParameter(
      name: 'permission',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Optional Android permission name. When omitted, app permissions are reset with pm reset-permissions when supported.',
    ),
  ];

  static const iosGrantPermission = <CockpitSystemControlParameter>[
    ...iosApp,
    CockpitSystemControlParameter(
      name: 'permission',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: CockpitSystemControlAllowedValues.iosPrivacyServices,
      description: 'simctl privacy service.',
    ),
  ];

  static const iosRevokePermission = <CockpitSystemControlParameter>[
    ...iosGrantPermission,
  ];

  static const iosResetPermission = <CockpitSystemControlParameter>[
    ...iosApp,
    CockpitSystemControlParameter(
      name: 'permission',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: CockpitSystemControlAllowedValues.iosPrivacyServices,
      description: 'simctl privacy service to reset; default all when omitted.',
    ),
  ];

  static const browserGrantPermission = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'permission',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description:
          'Browser permission token supported by the active browser driver.',
    ),
  ];

  static const androidAppearance = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'appearance',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>['light', 'dark', 'auto'],
    ),
  ];

  static const iosAppearance = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'appearance',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>['light', 'dark'],
    ),
  ];

  static const hostAppearance = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'appearance',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>['light', 'dark'],
    ),
  ];

  static const androidContentSize = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'contentSize',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Android content size token; required unless fontScale is provided.',
    ),
    CockpitSystemControlParameter(
      name: 'fontScale',
      valueType: CockpitSystemControlParameterType.number,
      minimum: 0.5,
      maximum: 3.5,
      description: 'Android font scale between 0.5 and 3.5.',
    ),
  ];

  static const iosContentSize = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'contentSize',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: CockpitSystemControlAllowedValues.iosContentSizeCategories,
    ),
  ];

  static const hostContentSize = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'contentSize',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Host accessibility text or content-size token.',
    ),
    CockpitSystemControlParameter(
      name: 'fontScale',
      valueType: CockpitSystemControlParameterType.number,
      minimum: 0.1,
      description: 'Host text scale when supported by the adapter.',
    ),
  ];

  static const location = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'latitude',
      valueType: CockpitSystemControlParameterType.number,
      required: true,
      minimum: -90,
      maximum: 90,
      description: 'Latitude in -90..90.',
    ),
    CockpitSystemControlParameter(
      name: 'longitude',
      valueType: CockpitSystemControlParameterType.number,
      required: true,
      minimum: -180,
      maximum: 180,
      description: 'Longitude in -180..180.',
    ),
    CockpitSystemControlParameter(
      name: 'altitude',
      valueType: CockpitSystemControlParameterType.number,
      description: 'Optional altitude when the platform adapter supports it.',
    ),
  ];

  static const androidOrientation = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'orientation',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>[
        'portrait',
        'landscape',
        'reversePortrait',
        'reverseLandscape',
        'auto',
      ],
    ),
  ];

  static const browserOrientation = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'orientation',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>['portrait', 'landscape'],
      description: 'Viewport or screen orientation emulation when supported.',
    ),
  ];

  static const iosOrientation = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'orientation',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>[
        'portrait',
        'landscape',
        'reversePortrait',
        'reverseLandscape',
      ],
    ),
  ];

  static const androidNetworkSpeed = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'networkSpeed',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>[
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
  ];

  static const androidNetworkDelay = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'networkDelay',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: <String>['gprs', 'edge', 'umts', 'none'],
    ),
  ];

  static const hostNetworkSpeed = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'networkSpeed',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description: 'Host network shaping profile supported by local tooling.',
    ),
  ];

  static const hostNetworkDelay = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'networkDelay',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description: 'Host network delay profile supported by local tooling.',
    ),
  ];

  static const iosStatusBar = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'time',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Fixed iOS simulator status bar time.',
    ),
    CockpitSystemControlParameter(
      name: 'dataNetwork',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: CockpitSystemControlAllowedValues.iosStatusBarDataNetworks,
    ),
    CockpitSystemControlParameter(
      name: 'wifiMode',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: CockpitSystemControlAllowedValues.iosStatusBarWifiModes,
    ),
    CockpitSystemControlParameter(
      name: 'wifiBars',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 3,
      description: 'Wi-Fi bars, 0-3.',
    ),
    CockpitSystemControlParameter(
      name: 'cellularMode',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues:
          CockpitSystemControlAllowedValues.iosStatusBarCellularModes,
    ),
    CockpitSystemControlParameter(
      name: 'cellularBars',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 4,
      description: 'Cellular bars, 0-4.',
    ),
    CockpitSystemControlParameter(
      name: 'operatorName',
      valueType: CockpitSystemControlParameterType.string,
    ),
    CockpitSystemControlParameter(
      name: 'batteryState',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues:
          CockpitSystemControlAllowedValues.iosStatusBarBatteryStates,
    ),
    CockpitSystemControlParameter(
      name: 'batteryLevel',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 100,
      description: 'Battery level, 0-100.',
    ),
  ];

  static const androidStatusBar = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'time',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Fixed status bar clock such as 9:41; mapped to SystemUI demo-mode hhmm.',
    ),
    CockpitSystemControlParameter(
      name: 'dataNetwork',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues:
          CockpitSystemControlAllowedValues.androidStatusBarDataNetworks,
      description:
          'wifi shows the Wi-Fi icon, cellular types set the mobile datatype, hide hides the mobile icon.',
    ),
    CockpitSystemControlParameter(
      name: 'wifiMode',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues:
          CockpitSystemControlAllowedValues.androidStatusBarSignalModes,
    ),
    CockpitSystemControlParameter(
      name: 'wifiBars',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 4,
      description: 'Wi-Fi bars, 0-4.',
    ),
    CockpitSystemControlParameter(
      name: 'cellularMode',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues:
          CockpitSystemControlAllowedValues.androidStatusBarSignalModes,
    ),
    CockpitSystemControlParameter(
      name: 'cellularBars',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 4,
      description: 'Cellular bars, 0-4.',
    ),
    CockpitSystemControlParameter(
      name: 'batteryState',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues:
          CockpitSystemControlAllowedValues.iosStatusBarBatteryStates,
    ),
    CockpitSystemControlParameter(
      name: 'batteryLevel',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 100,
      description: 'Battery level, 0-100.',
    ),
  ];

  static const screenshot = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'name',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Artifact name; default is system-screenshot.',
    ),
    CockpitSystemControlParameter(
      name: 'outputPath',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Optional path to copy the captured image to.',
    ),
  ];

  static const startRecording = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'name',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Recording artifact name; default is system-recording.',
    ),
    CockpitSystemControlParameter(
      name: 'purpose',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['acceptance', 'repro'],
      description: 'Recording purpose; default is acceptance.',
    ),
    CockpitSystemControlParameter(
      name: 'mode',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['auto', 'cheap', 'native', 'full'],
      description: 'Recording mode; default is native.',
    ),
    CockpitSystemControlParameter(
      name: 'layer',
      valueType: CockpitSystemControlParameterType.string,
      allowedValues: <String>['flutter', 'app-window', 'host-screen', 'system'],
      description: 'Recording layer; default is system.',
    ),
  ];

  static const stopRecording = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'outputPath',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Optional path to copy the completed recording to.',
    ),
  ];

  static const fileTransfer = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'sourcePath',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description:
          'Source path. For pushFile, this is a host path; for pullFile, this is a device path.',
    ),
    CockpitSystemControlParameter(
      name: 'destinationPath',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description:
          'Destination path. For pushFile, this is a device path; for pullFile, this is a host path.',
    ),
  ];

  static const iosAddMedia = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'sourcePath',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description:
          'Host media file path to add to simulator media library or Android MediaStore scan path.',
    ),
  ];

  static const androidAddMedia = <CockpitSystemControlParameter>[
    ...iosAddMedia,
    CockpitSystemControlParameter(
      name: 'destinationPath',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Android only: device destination path before scanning media. Defaults to /sdcard/Download/<filename>.',
    ),
  ];

  static const hostAddMedia = <CockpitSystemControlParameter>[
    ...iosAddMedia,
    CockpitSystemControlParameter(
      name: 'destinationPath',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Host destination path. Defaults to the host Downloads folder.',
    ),
  ];

  static const hostNotification = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'title',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification title.',
    ),
    CockpitSystemControlParameter(
      name: 'body',
      valueType: CockpitSystemControlParameterType.string,
      description: 'Notification body text.',
    ),
  ];

  static const androidSystemLogs = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'lines',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 5000,
      description: 'Number of recent logcat lines to read; default is 200.',
    ),
    CockpitSystemControlParameter(
      name: 'packageId',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Optional package filter; logs are scoped to the running app process when it is found.',
    ),
  ];

  static const appleSystemLogs = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'lastMinutes',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 60,
      description:
          'How many recent minutes of unified log to read; default is 2.',
    ),
    CockpitSystemControlParameter(
      name: 'lines',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 5000,
      description:
          'Maximum trailing log lines to return; default is 200 to keep output bounded.',
    ),
    CockpitSystemControlParameter(
      name: 'processName',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Optional process name predicate filter, for example Runner.',
    ),
  ];

  static const linuxSystemLogs = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'lines',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 5000,
      description: 'Number of recent journal lines to read; default is 200.',
    ),
  ];

  static const windowsSystemLogs = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'lines',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 1000,
      description:
          'Number of recent Application event log entries to read; default is 50.',
    ),
  ];

  static const androidBattery = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'level',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 0,
      maximum: 100,
      description: 'Simulated battery level, 0-100.',
    ),
    CockpitSystemControlParameter(
      name: 'plugged',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'true simulates AC charging; false simulates running on battery.',
    ),
    CockpitSystemControlParameter(
      name: 'reset',
      valueType: CockpitSystemControlParameterType.boolean,
      description:
          'true restores real battery reporting and clears simulated state.',
    ),
  ];

  static const androidConnectivity = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'wifi',
      valueType: CockpitSystemControlParameterType.boolean,
      description: 'Enable or disable Wi-Fi.',
    ),
    CockpitSystemControlParameter(
      name: 'mobileData',
      valueType: CockpitSystemControlParameterType.boolean,
      description: 'Enable or disable mobile data.',
    ),
    CockpitSystemControlParameter(
      name: 'airplaneMode',
      valueType: CockpitSystemControlParameterType.boolean,
      description: 'Enable or disable airplane mode (Android 11+).',
    ),
  ];

  static const iosLocale = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'locale',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      description: 'Locale identifier such as zh_CN or en_US.',
    ),
    CockpitSystemControlParameter(
      name: 'language',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Optional preferred language tag such as zh-Hans; defaults to the locale language.',
    ),
  ];

  static const macosResetPermission = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'permission',
      valueType: CockpitSystemControlParameterType.string,
      required: true,
      allowedValues: CockpitSystemControlAllowedValues.macosTccServices,
      description:
          'macOS TCC service to reset so the next access re-prompts the user.',
    ),
    CockpitSystemControlParameter(
      name: 'appId',
      valueType: CockpitSystemControlParameterType.string,
      description:
          'Optional bundle id scope; when omitted the service is reset for all apps.',
    ),
  ];

  static const readUiTree = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'maxDepth',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 64,
      description: 'Maximum accessibility tree depth; default is 16.',
    ),
    CockpitSystemControlParameter(
      name: 'maxNodes',
      valueType: CockpitSystemControlParameterType.integer,
      minimum: 1,
      maximum: 10000,
      description: 'Maximum accessibility nodes; default is 2000.',
    ),
  ];

  static const shellCommand = <CockpitSystemControlParameter>[
    CockpitSystemControlParameter(
      name: 'command',
      valueType: CockpitSystemControlParameterType.stringList,
      required: true,
      description: 'Executable plus arguments, for example ["echo","ok"].',
    ),
  ];
}
