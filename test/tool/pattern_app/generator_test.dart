import 'package:test/test.dart';

import '../../../tool/src/pattern_app/generator.dart';

void main() {
  const generator = PatternAppGenerator();

  PatternAppOutput generate(
    PatternAppKind kind,
    int seed, {
    String name = 'sample_app',
  }) {
    return generator.generate(
      kind: kind,
      name: name,
      seed: seed,
      flutterCockpitPath: '../../../packages/flutter_cockpit',
    );
  }

  test('same seed reproduces identical output', () {
    final first = generate(PatternAppKind.formFlow, 7);
    final second = generate(PatternAppKind.formFlow, 7);
    expect(second.files, first.files);
  });

  test('different seeds vary the generated UI', () {
    final first = generate(PatternAppKind.formFlow, 1);
    final second = generate(PatternAppKind.formFlow, 2);
    expect(second.files['main.dart'], isNot(first.files['main.dart']));
  });

  test('every pattern wires the cockpit bridge and its home screen', () {
    for (final kind in PatternAppKind.values) {
      final output = generate(kind, 3);
      final main = output.files['main.dart']!;
      expect(
        main,
        contains('FlutterCockpitApp('),
        reason: patternAppKindToString(kind),
      );
      expect(
        main,
        contains('CockpitRemoteSessionConfiguration'),
        reason: patternAppKindToString(kind),
      );
      final home = switch (kind) {
        PatternAppKind.settingsFlow => 'SettingsScreen',
        PatternAppKind.formFlow => 'SubmitFormScreen',
        PatternAppKind.lazyFeed => 'FeedScreen',
      };
      expect(main, contains('const $home()'));
      expect(output.files['pubspec.yaml'], contains('flutter_cockpit'));
      expect(output.files['README.md'], contains('cockpit dev start'));
    }
  });

  test('app name becomes the shell class name', () {
    final output = generate(PatternAppKind.lazyFeed, 5, name: 'amber_harbor');
    expect(output.files['main.dart'], contains('class AmberHarborApp '));
  });

  test('unknown pattern names are rejected', () {
    expect(
      () => patternAppKindFromString('chess_board'),
      throwsFormatException,
    );
  });
}
