import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_test/cockpit_test.dart';
import 'package:test/test.dart';

void main() {
  test('localized text resolves against the locale at dispatch time', () {
    const text = CockpitLocalizedText(
      'settings.saved',
      values: <String, String>{'en-US': 'Saved', 'zh-CN': '已保存'},
    );

    expect(text.resolve(const CockpitLocaleProfile('en-US')), 'Saved');
    expect(text.resolve(const CockpitLocaleProfile('zh-CN')), '已保存');
  });

  test('localized text fails explicitly when a locale value is missing', () {
    const text = CockpitLocalizedText(
      'settings.saved',
      values: <String, String>{'en-US': 'Saved'},
    );

    expect(
      () => text.resolve(const CockpitLocaleProfile('fr-FR')),
      throwsA(isA<CockpitTestLocalizationException>()),
    );
  });

  test('scenario metadata validates required capabilities', () {
    final scenario = CockpitTestScenario(
      id: 'create-task',
      body: (_) async {},
      requiredCapabilities: const <String>{'semantic', 'input'},
    );

    expect(scenario.id, 'create-task');
    expect(scenario.requiredCapabilities, contains('semantic'));
    expect(
      () => CockpitTestScenario(id: ' ', body: (_) async {}),
      throwsArgumentError,
    );
  });

  test('programmatic suite preserves case order and locale matrix', () {
    final suite = CockpitTestSuiteProgram(
      id: 'smoke',
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
      locales: const <CockpitLocaleProfile>[
        CockpitLocaleProfile('en-US'),
        CockpitLocaleProfile('zh-CN'),
      ],
    );

    expect(suite.cases.map((item) => item.id), <String>['a', 'b']);
    expect(suite.locales.map((locale) => locale.toLanguageTag()), <String>[
      'en-US',
      'zh-CN',
    ]);
    expect(suite.toJson()['locales'], hasLength(2));
  });

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
  CockpitLocaleProfile get locale => const CockpitLocaleProfile('en-US');

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
  Future<CockpitCommandExecution> type(String value, {required Object into}) =>
      execute(
        CockpitCommand(
          commandId: '2',
          commandType: CockpitCommandType.enterText,
          locator: into is String ? CockpitLocator(key: into) : null,
          parameters: <String, Object?>{'text': value},
        ),
      );

  @override
  Future<CockpitCommandExecution> expectText(Object target, Object expected) =>
      execute(
        CockpitCommand(
          commandId: '3',
          commandType: CockpitCommandType.assertText,
          locator: target is String ? CockpitLocator(key: target) : null,
          parameters: <String, Object?>{'text': expected.toString()},
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
