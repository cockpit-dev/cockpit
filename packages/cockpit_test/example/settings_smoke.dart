// A runnable tour of the cockpit_test authoring contract.
//
// Dart only — run it directly:
//
//   dart run package:cockpit_test/example/settings_smoke.dart
//
// Execution on real targets (Flutter integration tests, bridge-connected
// release apps, native black-box apps) stays in the cockpit package runners;
// see README.md for that wiring.
import 'dart:convert';

import 'package:cockpit_test/cockpit_test.dart';

const _savedStatus = CockpitLocalizedText(
  'settings.saved',
  values: {'en-US': 'Saved', 'zh-CN': '已保存'},
);

/// A scenario only uses selectors, protocol values, and the active locale.
final saveSettings = CockpitTestScenario(
  id: 'save-settings',
  requiredCapabilities: const {'tap', 'type', 'assertText'},
  metadata: const {'surface': 'settings'},
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
  locales: const [CockpitLocaleProfile('en-US'), CockpitLocaleProfile('zh-CN')],
  cases: [CockpitTestCaseProgram(id: 'save', scenario: saveSettings)],
);

void main() {
  // The suite program serializes to the protocol shape every runner accepts,
  // which is what a registry or queue would persist for cross-runner reuse.
  print(
    const JsonEncoder.withIndent('  ').convert(settingsSmokeSuite.toJson()),
  );

  // Translations resolve lazily against the active locale, so a language
  // switch inside a scenario body is observed by the next assertion.
  for (final locale in settingsSmokeSuite.locales) {
    print('${locale.toLanguageTag()}: ${_savedStatus.resolve(locale)}');
  }
}
