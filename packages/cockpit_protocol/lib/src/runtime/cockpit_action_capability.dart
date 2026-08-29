enum CockpitActionCapability {
  launchApp,
  stopApp,
  focusApp,
  openDeepLink,
  grantPermission,
  dismissPermissionDialog,
  tap,
  hover,
  longPress,
  doubleTap,
  scroll,
  typeText,
  pressBack,
  pressHome,
  openNotifications,
  captureScreenshot,
  startRecording,
  stopRecording,
  readLogs,
  collectCrashInfo,
  pushFile,
  pullFile,
  runShell;

  static CockpitActionCapability fromJson(Object? json) {
    return values.byName(json! as String);
  }
}
