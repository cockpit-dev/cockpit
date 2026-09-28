// A runnable tour of the cockpit_test authoring contract.
//
// Dart only — run it directly:
//
//   dart run package:cockpit_test/example/settings_smoke.dart
//
// Execution on real targets (Flutter integration tests, bridge-connected
// release apps, native black-box apps) stays in dependent runner packages.
import 'dart:convert';

import 'package:cockpit_test/cockpit_test.dart';

final _savedStatus = CockpitLocalizedText(
  'settings.saved',
  values: const <String, String>{'en-US': 'Saved', 'zh-CN': '已保存'},
);

/// The simplest scenario: an id and a body. Text, tooltip, type, and path
/// locators resolve on every surface, so this runs in-app, over the bridge,
/// and against native black-box targets unchanged.
final saveSettings = CockpitTestScenario(
  id: 'save-settings',
  metadata: const <String, Object?>{'surface': 'settings'},
  body: (tester) async {
    await tester.tap('Settings');
    await tester.type('Alice', into: 'Name');
    await tester.tap('Save');
    await tester.expectText(
      'Saved',
      _savedStatus,
      match: CockpitTextMatchMode.contains,
    );
  },
);

/// A scenario can also assert absence and read real UI state back. Host-side
/// helpers throw structured failures the runner reports as `failed` attempts.
/// Unlike the first scenario, this one reaches for `#spinner`, which only
/// resolves inside Flutter apps — in-app and bridge surfaces, not black-box.
final saveSettingsAndVerify = CockpitTestScenario(
  id: 'save-settings-verified',
  body: (tester) async {
    await tester.tap('Settings');
    await tester.waitFor('Save');
    await tester.tap('Save');
    await tester.waitFor('#spinner', absent: true);
    final snapshot = await tester.collectSnapshot();
    cockpitExpectEquals(snapshot.routeName, 'settings');
    cockpitExpectContains(
      snapshot.visibleTargets.map((target) => target.text),
      _savedStatus.resolve(CockpitLocaleProfile('en-US')),
    );
  },
);

/// Bare scenarios each become a case named after the scenario id; crossing the
/// locale matrix happens once, not per target.
final settingsSmokeSuite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: <CockpitLocaleProfile>[
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-CN'),
  ],
  scenarios: <CockpitTestScenario>[saveSettings],
);

void main() {
  // A manifest is a diagnostic description of the in-process code program. The
  // executable scenario body remains a Dart closure and is not serialized.
  print(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(settingsSmokeSuite.toManifestJson()),
  );

  // Translations resolve lazily against the active locale, so a language
  // switch inside a scenario body is observed by the next assertion.
  for (final locale in settingsSmokeSuite.locales) {
    print('${locale.toLanguageTag()}: ${_savedStatus.resolve(locale)}');
  }
}
