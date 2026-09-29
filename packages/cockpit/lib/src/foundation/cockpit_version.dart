const String cockpitVersion = '4.11.1';
const String cockpitBuildId = String.fromEnvironment(
  'COCKPIT_BUILD_ID',
  defaultValue: cockpitVersion,
);
