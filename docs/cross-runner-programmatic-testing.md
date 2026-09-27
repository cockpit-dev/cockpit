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

```dart
final smoke = CockpitTestScenario(
  id: 'save-settings',
  requirements: CockpitTestRequirements(
    commands: const {
      CockpitCommandType.tap,
      CockpitCommandType.enterText,
      CockpitCommandType.assertText,
    },
    locators: const {CockpitLocatorKind.cockpitId},
  ),
  body: (tester) async {
    await tester.tap('#settings');
    await tester.type('Alice', into: '#name');
    await tester.tap('#save');
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

The same scenario can run as a locale matrix:

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-Hant-TW'),
  ],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: smoke)],
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

## Capability preflight

Commands and locator strategies use `CockpitCommandType` and
`CockpitLocatorKind`; non-command target features use the small
`CockpitTestFeature` enum. This keeps method names such as `type()` from being
mistaken for protocol command names such as `enterText`.

Unsupported requirements return a `blocked` result with a structured
`CockpitTestError` before the body runs. A supported scenario that throws returns
`failed`; a completed scenario returns `passed`. Empty suites are rejected.

## Locale behavior

Locale tags are validated and canonicalized at runtime, including language,
script, and region subtags. Translation fallback is exact tag, then
language-script, then language. Flutter conversion preserves `Locale.scriptCode`,
so `zh-Hant-TW` does not degrade to `zh-TW`.

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

Enable a remote bridge only in the test variant and provide its password:

```bash
flutter build apk --release \
  --dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true \
  --dart-define=FLUTTER_COCKPIT_REMOTE_PASSWORD="$COCKPIT_PASSWORD"
```

Production releases should leave `FLUTTER_COCKPIT_REMOTE_ENABLED` disabled. A
native-only app needs no Cockpit plugin registration.
