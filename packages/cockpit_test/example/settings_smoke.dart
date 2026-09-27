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

/// A scenario only uses selectors, protocol values, and the active locale.
final saveSettings = CockpitTestScenario(
  id: 'save-settings',
  requirements: CockpitTestRequirements(
    commands: const <CockpitCommandType>{
      CockpitCommandType.tap,
      CockpitCommandType.enterText,
      CockpitCommandType.assertText,
    },
    locators: const <CockpitLocatorKind>{CockpitLocatorKind.cockpitId},
  ),
  metadata: const <String, Object?>{'surface': 'settings'},
  body: (tester) async {
    await tester.tap('#settings');
    await tester.type('Alice', into: '#name');
    await tester.tap('#save');
    await tester.expectText('#status', _savedStatus);
  },
);

/// The same scenario is crossed with a locale matrix once, not per target.
final settingsSmokeSuite = CockpitTestSuiteProgram(
  id: 'settings-smoke',
  locales: <CockpitLocaleProfile>[
    CockpitLocaleProfile('en-US'),
    CockpitLocaleProfile('zh-CN'),
  ],
  cases: <CockpitTestCaseProgram>[
    CockpitTestCaseProgram(id: 'save', scenario: saveSettings),
  ],
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
