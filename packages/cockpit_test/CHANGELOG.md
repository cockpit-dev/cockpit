# Changelog

## 4.9.0

- Initial cross-runner scenario contract: `CockpitTestScenario`,
  `CockpitTestCaseProgram`, and `CockpitTestSuiteProgram` author
  platform-neutral cases that run unchanged on Flutter integration tests,
  bridge-connected release apps, and native black-box targets.
- Added locale-first attempts: every case runs against a validated
  `CockpitLocaleProfile` matrix and `CockpitLocalizedText` resolves
  translations lazily so in-scenario language switches are observed by the
  next assertion.
- Added explicit attempt outcomes: `passed`, `failed`, or `blocked`. A target
  that cannot satisfy a scenario's `requiredCapabilities` is blocked with a
  `CockpitTestCapabilityException` before the body runs instead of silently
  skipping work.
