const String cockpitVersion = '4.0.19';
const String cockpitBuildId = String.fromEnvironment(
  'COCKPIT_BUILD_ID',
  defaultValue: cockpitVersion,
);
const String cockpitWorkerBuildHeader = 'Cockpit-Worker-Build';
