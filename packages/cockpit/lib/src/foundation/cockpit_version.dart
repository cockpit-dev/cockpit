const String cockpitVersion = '4.0.9';
const String cockpitBuildId = String.fromEnvironment(
  'COCKPIT_BUILD_ID',
  defaultValue: cockpitVersion,
);
const String cockpitWorkerBuildHeader = 'Cockpit-Worker-Build';
