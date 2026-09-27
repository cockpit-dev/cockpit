# Changelog

## 4.10.0

- Published the package for public use instead of `publish_to: none`, closing
  the external dependency graph for `cockpit` and `flutter_cockpit_test`.
- Added the shared programmatic runner used by remote, system, and Flutter
  execution surfaces with one preflight, result, and error semantics.
- Replaced string capability requirements with typed ones built from
  `CockpitCommandType` and `CockpitLocatorKind`, eliminating command, locator,
  and feature alias drift.
- Hardened suite construction: empty case lists, blank or duplicate case IDs
  are rejected and IDs are normalized deterministically.
- Made `CockpitTestRunResult` carry structured `CockpitTestError` values with
  a passed/error invariant and recursively immutable metadata; a failing
  cleanup step no longer overwrites the primary error.
- Fixed `CockpitLocaleProfile` to parse and canonicalize BCP-47 language,
  script, and region subtags (`en-US`, `zh-Hant-TW`) with immutable metadata
  and equality/hash contracts built on the canonical tag.

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
