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
- Added host-side assertion helpers — `cockpitExpectEquals` (deep equality
  over numbers, strings, booleans, lists, sets, and maps),
  `cockpitExpectTrue`, `cockpitExpectNotNull`, and `cockpitExpectContains` —
  throwing `CockpitTestAssertionException` with bounded, frozen actual and
  expected details that the runner reports as `failed` attempts instead of
  internal errors.
- Extended the shared `CockpitTester` contract with `waitFor(target, absent:)`
  absence waits, `expectText(..., match:)` text match modes, and
  `collectSnapshot()` UI read-back; every surface maps them to the same
  protocol operations.
- Added ICU MessageFormat support to `CockpitLocalizedText` via opt-in
  `params`, powered by `intl`'s CLDR rules: placeholders, `plural` with exact
  `=N` precedence over categories, `select`, nesting, `#`, and apostrophe
  quoting; without params, values keep resolving verbatim.
- Added `CockpitArbCatalog` and `CockpitJsonCatalog` — eager, fail-loud
  catalogs over the app's own `gen_l10n` ARB files or `slang` /
  `easy_localization` JSON — plus `validateMatrix` coverage reports through
  the runtime fallback chain and VM file loaders in
  `package:cockpit_test/catalog_io.dart`.
- Aligned late capability discovery with preflight: a target that answers
  "unsupported capability" while a scenario body runs now blocks the attempt
  exactly like a declared-requirement mismatch.
- Simplified authoring: suites accept bare `scenarios:` that each become a
  case named after the scenario id, and `run()`/`runSuite()` treat the locale
  as optional, defaulting to `en-US`.
- Rewrote the README (English and Chinese), the cross-runner guide, and the
  runnable example around the simplest scenario first — no requirements,
  cross-surface text locators — with requirements demoted to an advanced
  preflight topic, and kept the example executable under a compile-and-run
  test.

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
