const String cockpitVersion = '4.0.43';
const String cockpitBuildId = String.fromEnvironment(
  'COCKPIT_BUILD_ID',
  defaultValue: cockpitVersion,
);
