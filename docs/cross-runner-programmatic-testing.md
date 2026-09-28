# Cross-runner programmatic tests

`cockpit_test` is an in-process Dart DSL for scenarios that share one
`CockpitTester` surface across Flutter integration tests, bridge-connected
release/profile apps, and native black-box targets. Scenario code should use
only selectors, protocol values, and the active locale; it should not import
`WidgetTester`, `BuildContext`, or a native SDK.

The shared runner and contracts live in
[`packages/cockpit_test`](../packages/cockpit_test). Concrete execution remains
at the platform boundary:

- [`packages/cockpit`](../packages/cockpit) provides `RemoteCockpitTester` and
  `SystemCockpitTester` plus process and device lifecycle.
- [`packages/flutter_cockpit_test`](../packages/flutter_cockpit_test) provides
  `cockpitScenarioWidgets`, which reuses `cockpitTestWidgets` and Flutter's
  official `integration_test` lifecycle.

A scenario is an id and a body; requirements and metadata are optional. Text,
tooltip, type, and path locators resolve on every surface, so they keep the
scenario portable:

```dart
final smoke = CockpitTestScenario(
  id: 'save-settings',
  body: (tester) async {
    await tester.tap('Settings');
    await tester.type('Alice', into: 'Name');
    await tester.tap('Save');
    await tester.expectText(
      '#status',
      CockpitLocalizedText(
        'settings.saved',
        values: const {'en-US': 'Saved', 'zh-CN': '已保存'},
      ),
    );
  },
);
```

`#cockpitId` and `@key` locators resolve only inside Flutter apps (in-app and
bridge surfaces); a black-box target sees the accessibility tree, not Flutter
keys.

The same scenario can run as a locale matrix — bare scenarios each become a
case named after the scenario id:

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-Hant-TW'),
  ],
  scenarios: [smoke],
);

final result = await const CockpitProgrammaticTestRunner().runSuite(
  suite,
  createTester: (locale) async => RemoteCockpitTester(
    client: client,
    workspaceRoot: workspaceRoot,
    initialLocale: locale,
  ),
);
```

For a source-owned Flutter test, reuse the same object directly:

```dart
cockpitScenarioWidgets(
  'saves settings',
  app: buildDevelopmentApp,
  scenario: smoke,
);
```

## Assertions and read-back

Every surface maps these to the same protocol operations:

- `expectText(target, expected, match: ...)` — exact match by default, plus
  `contains`, `fuzzy`, and `regex` modes.
- `waitFor(target)` / `waitFor(target, absent: true)` — bounded presence and
  absence waits; the absent form is the shared way to assert that something
  disappeared.
- `collectSnapshot()` — reads real UI state (route name, visible targets) back
  for host-side comparison.
- `describeApp()` — reads app-authored state: whatever the application chose to
  expose through its app state provider (`FlutterCockpitApp` /
  `FlutterCockpitRoot` `appStateProvider`), evaluated at call time. The payload
  is normalized to JSON-safe values, redacted, and size-bounded before it
  leaves the app process; targets without a provider answer with an
  unsupported-capability failure, which the runner reports as `blocked`. On
  Flutter targets every report also carries the settings derived live from the
  widget tree — `locale`, `brightness`, `themeColor`, `textScale`, `platform` —
  so no provider is needed to learn the effective locale and theme; the
  declarative `cockpit.test/v2` model exposes the same read as a `describeApp`
  action (no locator, no parameters) for shipped cases and suites.

Host-side helpers in `cockpit_test` — `cockpitExpectEquals` (deep equality),
`cockpitExpectTrue`, `cockpitExpectNotNull`, `cockpitExpectContains` — throw
structured failures the runner reports as `failed` with the actual/expected
values attached, not as internal errors.

## Capability preflight

Commands and locator strategies use `CockpitCommandType` and
`CockpitLocatorKind`; non-command target features use the small
`CockpitTestFeature` enum. This keeps method names such as `type()` from being
mistaken for protocol command names such as `enterText`.

Declaring requirements is optional. Unsupported requirements return a `blocked`
result with a structured `CockpitTestError` before the body runs. Without
declared requirements, a target that answers "unsupported capability" while the
body runs blocks the attempt with the same semantics — declared requirements
simply move that verdict earlier and report every gap at once. A supported
scenario that throws returns `failed`; a completed scenario returns `passed`.
Empty suites are rejected.

## Locale behavior

Locale tags are validated and canonicalized at runtime, including language,
script, and region subtags. Translation fallback is exact tag, then
language-script, then language. Flutter conversion preserves `Locale.scriptCode`,
so `zh-Hant-TW` does not degrade to `zh-TW`.

`CockpitLocalizedText` accepts optional `params` to format ICU MessageFormat
messages — placeholders, `plural` (exact `=N` before CLDR categories),
`select`, nesting, and `#` — using the same CLDR rules the app renders with.
Without `params` a value resolves verbatim. `CockpitArbCatalog` and
`CockpitJsonCatalog` load the app's own `gen_l10n` ARB files or `slang` /
`easy_localization` JSON as the single source of expected text, and
`validateMatrix` checks coverage across the locale matrix before a suite runs.
See the `cockpit_test` README for details.

## Persistence boundary

`CockpitTestScenario.body` is executable Dart code and is intentionally not a
wire protocol. `toManifestJson()` is a diagnostic projection only. Persisted,
queued, or language-neutral execution must use the declarative
`cockpit.test/v2` model.

## Targets

- Flutter source tests use `cockpitScenarioWidgets` or `cockpitTestWidgets`.
- A test build that embeds `flutter_cockpit` uses `RemoteCockpitTester`.
- An app without Cockpit uses `SystemCockpitTester` through platform system
  control.

Performance is feature-based. `profile()` returns a real target report; targets
without performance capture fail explicitly instead of returning synthetic
zero-valued data. Remote preflight reads the live session status rather than
assuming that the presence of an adapter proves support.

## Release-test build

Enable a remote bridge only in the test variant and provide a per-session token:

```bash
flutter build apk --release \
  --dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true \
  --dart-define=FLUTTER_COCKPIT_REMOTE_AUTH_TOKEN="$COCKPIT_TOKEN"
```

Production releases should leave `FLUTTER_COCKPIT_REMOTE_ENABLED` disabled. A
native-only app needs no Cockpit plugin registration.
