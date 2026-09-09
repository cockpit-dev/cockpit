# Cross-runner programmatic tests

`cockpit_test` contains the platform-neutral scenario API. A scenario should
only use selectors, protocol values, and the current locale; it must not import
`WidgetTester`, `BuildContext`, or a native SDK.

```dart
final smoke = CockpitTestScenario(
  id: 'save-settings',
  requiredCapabilities: const {'tap', 'assertText'},
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

The same scenario can be run as a locale matrix:

```dart
final suite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: const [
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-CN'),
  ],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: smoke)],
);
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

## Targets

- Existing local integration tests use `cockpitTestWidgets`. Its `locale` and
  localized assertions resolve through the mounted `Localizations` boundary on
  every command, so a language switch is observed by the next assertion.
- A release/profile app that includes `flutter_cockpit` uses
  `RemoteCockpitTester`. Enable the remote session only for the test build,
  provide a per-session token, and keep the endpoint on loopback or a private
  device tunnel.
- A release app without Cockpit uses `SystemCockpitTester`. It routes through
  the platform system-control adapter and never assumes a Flutter VM or
  DevTools service exists.

Performance is capability-based. `profile()` returns the report collected by
the target; if the target cannot produce a real report it throws an explicit
`CockpitTestCapabilityException` rather than returning zero-valued data.

## Release-test build

For an integrated app, inject the remote endpoint and token only in the test
variant, for example:

```bash
flutter build apk --release \
  --dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true \
  --dart-define=FLUTTER_COCKPIT_REMOTE_AUTH_TOKEN="$COCKPIT_TOKEN"
```

Production releases should leave `FLUTTER_COCKPIT_REMOTE_ENABLED` disabled.
For a native-only app, build the normal release artifact and use the system
driver target; no Cockpit plugin registration is required.
