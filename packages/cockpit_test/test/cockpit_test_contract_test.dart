import 'package:cockpit_test/cockpit_test.dart';
import 'package:test/test.dart';

void main() {
  test(
    'localized text uses exact, language-script, then language fallback',
    () {
      final text = CockpitLocalizedText(
        'settings.saved',
        values: const <String, String>{
          'zh-Hant-HK': '已儲存（香港）',
          'zh-Hant': '已儲存',
          'zh': '已保存',
        },
      );

      expect(text.resolve(CockpitLocaleProfile('zh-Hant-HK')), '已儲存（香港）');
      expect(text.resolve(CockpitLocaleProfile('zh-Hant-TW')), '已儲存');
      expect(text.resolve(CockpitLocaleProfile('zh-CN')), '已保存');
    },
  );

  test('localized text fails explicitly when a locale value is missing', () {
    final text = CockpitLocalizedText(
      'settings.saved',
      values: const <String, String>{'en-US': 'Saved'},
    );

    expect(
      () => text.resolve(CockpitLocaleProfile('fr-FR')),
      throwsA(isA<CockpitTestLocalizationException>()),
    );
  });

  test('locale profile validates and canonicalizes language tags', () {
    final locale = CockpitLocaleProfile('ZH-hant-tw');
    final languageAndRegion = CockpitLocaleProfile('en', region: 'us');

    expect(locale.toLanguageTag(), 'zh-Hant-TW');
    expect(locale.languageCode, 'zh');
    expect(locale.scriptCode, 'Hant');
    expect(locale.regionCode, 'TW');
    expect(languageAndRegion.toLanguageTag(), 'en-US');
    expect(() => CockpitLocaleProfile('zh_Hant_TW'), throwsArgumentError);
    expect(
      () => CockpitLocaleProfile('zh-Hant-TW', region: 'CN'),
      throwsArgumentError,
    );
  });

  test('locale and translation metadata are immutable by value', () {
    final metadata = <String, String>{'market': 'consumer'};
    final translations = <String, String>{'en-us': 'Saved'};
    final locale = CockpitLocaleProfile('en-US', metadata: metadata);
    final equal = CockpitLocaleProfile(
      'EN-us',
      metadata: const <String, String>{'market': 'consumer'},
    );
    final text = CockpitLocalizedText('saved', values: translations);

    metadata['market'] = 'enterprise';
    translations['en-us'] = 'Changed';

    expect(locale.metadata, const <String, String>{'market': 'consumer'});
    expect(text.resolve(locale), 'Saved');
    expect(locale, equal);
    expect(locale.hashCode, equal.hashCode);
    expect(<CockpitLocaleProfile>{locale, equal}, hasLength(1));
    expect(() => locale.metadata['new'] = 'value', throwsUnsupportedError);
    expect(() => text.values['en-US'] = 'Changed', throwsUnsupportedError);
  });

  test('scenario uses typed requirements and immutable metadata', () {
    final commands = <CockpitCommandType>[CockpitCommandType.enterText];
    final metadata = <String, Object?>{
      'labels': <Object?>['smoke'],
    };
    final scenario = CockpitTestScenario(
      id: ' create-task ',
      body: (_) async {},
      requirements: CockpitTestRequirements(
        commands: commands,
        locators: const <CockpitLocatorKind>{CockpitLocatorKind.cockpitId},
        features: const <CockpitTestFeature>{CockpitTestFeature.inAppControl},
      ),
      metadata: metadata,
    );

    commands.add(CockpitCommandType.tap);
    (metadata['labels']! as List<Object?>).add('changed');

    expect(scenario.id, 'create-task');
    expect(scenario.requirements.commands, const <CockpitCommandType>{
      CockpitCommandType.enterText,
    });
    expect(scenario.metadata['labels'], const <Object?>['smoke']);
    expect(
      scenario.toManifestJson()['requirements'],
      isA<Map<String, Object?>>(),
    );
    expect(
      () => CockpitTestScenario(id: ' ', body: (_) async {}),
      throwsArgumentError,
    );
  });

  test(
    'programmatic suite preserves order and rejects empty or duplicate cases',
    () {
      final suite = CockpitTestSuiteProgram(
        id: ' smoke ',
        cases: <CockpitTestCaseProgram>[
          CockpitTestCaseProgram(
            id: 'a',
            scenario: CockpitTestScenario(id: 'a', body: (_) async {}),
          ),
          CockpitTestCaseProgram(
            id: 'b',
            scenario: CockpitTestScenario(id: 'b', body: (_) async {}),
          ),
        ],
        locales: <CockpitLocaleProfile>[
          CockpitLocaleProfile('en-US'),
          CockpitLocaleProfile('zh-CN'),
        ],
      );

      expect(suite.id, 'smoke');
      expect(suite.cases.map((item) => item.id), <String>['a', 'b']);
      expect(suite.locales.map((locale) => locale.toLanguageTag()), <String>[
        'en-US',
        'zh-CN',
      ]);
      expect(suite.toManifestJson()['locales'], hasLength(2));
      expect(
        () => CockpitTestSuiteProgram(
          id: 'empty',
          cases: const <CockpitTestCaseProgram>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => CockpitTestSuiteProgram(
          id: 'duplicate',
          cases: <CockpitTestCaseProgram>[
            CockpitTestCaseProgram(
              id: 'same',
              scenario: CockpitTestScenario(id: 'a', body: (_) async {}),
            ),
            CockpitTestCaseProgram(
              id: ' same ',
              scenario: CockpitTestScenario(id: 'b', body: (_) async {}),
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('tester command contract can execute a neutral command', () async {
    final tester = _RecordingTester();
    final execution = await tester.tap('#save');
    expect(execution.result.success, isTrue);
    expect(tester.commands.single.commandType, CockpitCommandType.tap);
  });
}

final class _RecordingTester implements CockpitTester {
  final commands = <CockpitCommand>[];

  @override
  CockpitLocaleProfile get locale => CockpitLocaleProfile('en-US');

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) async {
    commands.add(command);
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 0,
      ),
    );
  }

  @override
  Future<CockpitCommandExecution> tap(Object? target) => execute(
    CockpitCommand(
      commandId: '1',
      commandType: CockpitCommandType.tap,
      locator: target is String ? CockpitLocator(key: target) : null,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
