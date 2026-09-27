# cockpit_test

[English](README.md) · [简体中文](README.zh-CN.md)

Platform-neutral, in-process test scenarios shared by Cockpit runners. Author a
scenario once against `CockpitTester`, then execute the same Dart closure in a
Flutter integration test, a bridge-connected release/profile app, or a native
black-box target.

`cockpit_test` depends only on `cockpit_protocol`. It owns the shared authoring,
preflight, locale, runner, and result contracts; concrete testers and platform
lifecycle remain in dependent packages.

## Author a scenario

```dart
import 'package:cockpit_test/cockpit_test.dart';

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

Requirements use protocol enums, so the tester method `type()` correctly
preflights `CockpitCommandType.enterText`; string aliases cannot drift from the
wire contract. Commands, locator strategies, and the small set of non-command
features are separate typed sets.

Compose scenarios into a non-empty locale matrix:

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-Hant-TW'),
  ],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: smoke)],
);
```

Run it with any concrete tester:

```dart
import 'package:cockpit/cockpit.dart';

final result = await const CockpitProgrammaticTestRunner().runSuite(
  suite,
  createTester: (locale) async => RemoteCockpitTester(
    client: client,
    workspaceRoot: workspaceRoot,
    initialLocale: locale,
  ),
);
```

Every attempt is `passed`, `failed`, or `blocked` and carries a structured
`CockpitTestError`. Unsupported typed requirements block the attempt before its
body runs. Empty suites are rejected, and an empty attempt collection never
reports success.

## Flutter integration tests

`flutter_cockpit_test` reuses Flutter's official `integration_test` runner and
mount/teardown lifecycle:

```dart
cockpitScenarioWidgets(
  'saves settings',
  app: buildDevelopmentApp,
  scenario: smoke,
);
```

Use `cockpitTestWidgets` instead when a test intentionally needs Flutter-only
APIs in addition to the shared `CockpitTester` surface.

## Locale behavior

`CockpitLocaleProfile` validates and canonicalizes language, script, and region
subtags at runtime. For example, `ZH-hant-tw` becomes `zh-Hant-TW`. Metadata and
translation maps are copied into immutable values.

`CockpitLocalizedText` resolves lazily against the current locale using:

1. exact tag, such as `zh-Hant-TW`;
2. language and script, such as `zh-Hant`;
3. language, such as `zh`.

A missing translation raises `CockpitTestLocalizationException`; it never
silently selects an unrelated language.

## In-process boundary

A scenario body is a Dart closure. `toManifestJson()` is only a diagnostic
projection of IDs, requirements, locale matrix, and metadata; it cannot contain
or reconstruct executable code. Use the declarative `cockpit.test/v2` document
model for persisted, queued, or language-neutral test execution.

A runnable tour lives in
[`example/settings_smoke.dart`](example/settings_smoke.dart).

## Learn more

- [Cross-runner programmatic tests](../../docs/cross-runner-programmatic-testing.md)
- [`cockpit_protocol` contracts](../cockpit_protocol/README.md)
- [`cockpit` concrete testers](../cockpit/README.md)
