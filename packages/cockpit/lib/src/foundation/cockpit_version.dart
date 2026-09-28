const String cockpitVersion = '4.11.0';
const String cockpitBuildId = String.fromEnvironment(
  'COCKPIT_BUILD_ID',
  defaultValue: cockpitVersion,
);
