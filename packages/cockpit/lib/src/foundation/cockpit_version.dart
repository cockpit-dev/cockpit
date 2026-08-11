const String cockpitVersion = '3.0.14';
const String cockpitBuildId = String.fromEnvironment(
  'COCKPIT_BUILD_ID',
  defaultValue: cockpitVersion,
);
const String cockpitWorkerBuildHeader = 'Cockpit-Worker-Build';
