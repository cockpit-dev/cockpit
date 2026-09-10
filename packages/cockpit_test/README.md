# cockpit_test

Platform-neutral programmatic test scenarios shared by every Cockpit runner.
A scenario is authored once against the `CockpitTester` contract and then runs
unchanged against a Flutter integration test, a release/profile app with the
Cockpit bridge, or a native black-box target.

This package is intentionally small and dependency-free beyond
`cockpit_protocol`: it owns the authoring contract only. Concrete testers,
runners, process ownership, and platform drivers live in dependent packages.

## The contract

```dart
import 'package:cockpit_test/cockpit_test.dart';

final smoke = CockpitTestScenario(
  id: 'save-settings',
  requiredCapabilities: const {'tap', 'type', 'assertText'},
  body: (tester) async {
    await tester.tap('#settings');
    await tester.type('Alice', into: '#name');
    await tester.tap('#save');
    await tester.expectText(
      '#status',
      const CockpitLocalizedText(
        'settings.saved',
        values: {'en-US': 'Saved', 'zh-CN': '已保存'},
      ),
    );
  },
);
```

Scenarios compose into a locale matrix:

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: const [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-CN'),
  ],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: smoke)],
);
```

Execution goes through a `CockpitTestRunner`. The default lifecycle runner and
the concrete testers ship in the [`cockpit`](../cockpit) package:

```dart
import 'package:cockpit/cockpit.dart';

final result = await const CockpitProgrammaticTestRunner().runSuite(
  suite,
  createTester: (locale) async => RemoteCockpitTester(
    client: CockpitRemoteSessionClient(
      baseUri: endpoint,
      authToken: remoteToken,
    ),
    workspaceRoot: workspaceRoot,
    initialLocale: locale,
  ),
);
```

Every case/locale attempt reports `passed`, `failed`, or `blocked`. A scenario
whose `requiredCapabilities` cannot be satisfied by the target is `blocked`
with a `CockpitTestCapabilityException` before its body runs; it never passes
by silently skipping work or substituting zero-valued data.

## Scenario rules

A scenario may only use selectors, protocol values, and the active locale. It
must not import `WidgetTester`, `BuildContext`, or a native SDK. Runner
lifecycle, installation, and cleanup stay outside the scenario body so the
same code path is exercised on every target:

- Flutter integration tests reuse scenarios through
  [`flutter_cockpit_test`](../flutter_cockpit_test).
- Release/profile apps with the Cockpit bridge use `RemoteCockpitTester`.
- Apps without Cockpit use `SystemCockpitTester` through the platform
  system-control adapter.

## Locale-first internationalization

`CockpitLocaleProfile` carries a validated BCP-47 tag, region, and text
direction with each attempt. `CockpitLocalizedText` resolves translations
lazily against the active locale, so a language switch made inside a scenario
is observed by the next assertion instead of a snapshot taken at construction
time. A missing translation raises `CockpitTestLocalizationException` rather
than falling back to a wrong-language string.

## Learn more

- [Cross-runner programmatic tests](../../docs/cross-runner-programmatic-testing.md)
- [`cockpit_protocol` contracts](../cockpit_protocol/README.md)
- [`cockpit` runners and testers](../cockpit/README.md)
