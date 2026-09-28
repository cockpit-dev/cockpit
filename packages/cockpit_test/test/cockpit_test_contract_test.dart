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

  test('tester contract exposes describeApp app state', () async {
    final tester = _StubTester(
      appState: const <String, Object?>{'environment': 'staging'},
    );

    expect(await tester.describeApp(), <String, Object?>{
      'environment': 'staging',
    });
  });

  group('host-side cockpitExpect assertions', () {
    test('equals compares primitives and JSON shapes deeply', () {
      cockpitExpectEquals(1, 1);
      cockpitExpectEquals(1, 1.0);
      cockpitExpectEquals('Saved', 'Saved');
      cockpitExpectEquals(
        <String, Object?>{
          'items': <Object?>[
            1,
            <String, Object?>{'done': true},
          ],
        },
        <String, Object?>{
          'items': <Object?>[
            1,
            <String, Object?>{'done': true},
          ],
        },
      );
      cockpitExpectEquals(<Object?>{1, 2}, <Object?>{2, 1});
    });

    test('equals reports bounded structured failures', () {
      expect(
        () => cockpitExpectEquals(1, 2, reason: 'settings row'),
        throwsA(
          isA<CockpitTestAssertionException>()
              .having(
                (error) => error.message,
                'message',
                allOf(contains('settings row'), contains('2')),
              )
              .having((error) => error.details['expected'], 'expected', 2)
              .having((error) => error.details['actual'], 'actual', 1),
        ),
      );
      expect(
        () => cockpitExpectEquals(
          <String, Object?>{'a': 1},
          <String, Object?>{'a': 2},
        ),
        throwsA(
          isA<CockpitTestAssertionException>()
              .having((error) => error.message, 'message', contains('{a: 2}'))
              // Composite values are reported as bounded strings so details
              // stay flat and size-capped at every level.
              .having(
                (error) => error.details['expected'],
                'expected',
                '{a: 2}',
              ),
        ),
      );
      expect(
        () => cockpitExpectEquals('x' * 2000, 'y'),
        throwsA(
          isA<CockpitTestAssertionException>().having(
            (error) => (error.details['actual']! as String).length,
            'bounded actual',
            lessThanOrEqualTo(1024),
          ),
        ),
      );
    });

    test('assertion details are frozen', () {
      late CockpitTestAssertionException failure;
      try {
        cockpitExpectEquals(1, 2);
      } on CockpitTestAssertionException catch (error) {
        failure = error;
      }
      expect(() => failure.details['actual'] = 2, throwsUnsupportedError);
    });

    test('true, notNull, and contains cover the remaining primitives', () {
      cockpitExpectTrue(true);
      cockpitExpectNotNull('value');
      cockpitExpectContains('Saved settings', 'Saved');
      cockpitExpectContains(<Object?>[1, 2], 2);
      cockpitExpectContains(<String, int>{'a': 1}, 'a');

      expect(
        () => cockpitExpectTrue(false, reason: 'drawer closed'),
        throwsA(
          isA<CockpitTestAssertionException>().having(
            (error) => error.message,
            'message',
            contains('drawer closed'),
          ),
        ),
      );
      expect(
        () => cockpitExpectNotNull(null),
        throwsA(isA<CockpitTestAssertionException>()),
      );
      expect(
        () => cockpitExpectContains('Saved', 'missing'),
        throwsA(isA<CockpitTestAssertionException>()),
      );
      expect(
        () => cockpitExpectContains(42, 'anything'),
        throwsA(isA<CockpitTestAssertionException>()),
      );
    });
  });

  group('programmatic runner result classification', () {
    test('host assertion failures classify as failed assertions', () async {
      final result = await const CockpitProgrammaticTestRunner().run(
        CockpitTestScenario(
          id: 'host-assert',
          body: (_) async {
            cockpitExpectEquals(3, 4, reason: 'item count');
          },
        ),
        createTester: (_) async => _StubTester(),
      );

      expect(result.status, CockpitTestRunStatus.failed);
      expect(result.locale.toLanguageTag(), 'en-US');
      expect(result.error?.code, CockpitTestErrorCode.assertionFailed);
      expect(result.error?.message, contains('item count'));
      expect(result.error?.details['expected'], 4);
    });

    test('plain exceptions stay internal failures', () async {
      final result = await const CockpitProgrammaticTestRunner().run(
        CockpitTestScenario(
          id: 'boom',
          body: (_) async => throw StateError('boom'),
        ),
        createTester: (_) async => _StubTester(),
      );

      expect(result.status, CockpitTestRunStatus.failed);
      expect(result.error?.code, CockpitTestErrorCode.internalFailure);
    });

    test('unsupported capability commands block instead of failing', () async {
      final result = await const CockpitProgrammaticTestRunner().run(
        CockpitTestScenario(
          id: 'needs-scroll',
          body: (tester) => tester.scroll('#list'),
        ),
        createTester: (_) async => _StubTester(
          failures: <String, CockpitCommandError>{
            'scrollUntilVisible': CockpitCommandError(
              code: CockpitCommandError.unsupportedCapabilityCode,
              message: 'No scroll handler is configured on this target.',
            ),
          },
        ),
      );

      expect(result.status, CockpitTestRunStatus.blocked);
      expect(result.error?.code, CockpitTestErrorCode.unsupportedAction);
      expect(result.error?.details['commandType'], 'scrollUntilVisible');
    });

    test('other command failures stay failed assertions', () async {
      final result = await const CockpitProgrammaticTestRunner().run(
        CockpitTestScenario(
          id: 'assert-text',
          body: (tester) => tester.expectText('#status', 'Saved'),
        ),
        createTester: (_) async => _StubTester(
          failures: <String, CockpitCommandError>{
            'assertText': CockpitCommandError(
              code: CockpitCommandError.assertionFailedCode,
              message: 'Text did not match.',
            ),
          },
        ),
      );

      expect(result.status, CockpitTestRunStatus.failed);
      expect(result.error?.code, CockpitTestErrorCode.assertionFailed);
    });
  });

  group('suite scenario composition', () {
    test('scenarios become cases named after their scenario ids', () {
      final suite = CockpitTestSuiteProgram(
        id: 'settings-smoke',
        scenarios: <CockpitTestScenario>[
          CockpitTestScenario(id: 'save', body: (_) async {}),
          CockpitTestScenario(id: 'clear', body: (_) async {}),
        ],
      );

      expect(suite.cases.map((item) => item.id), <String>['save', 'clear']);
      expect(suite.cases.map((item) => item.scenario.id), <String>[
        'save',
        'clear',
      ]);
    });

    test('cases and scenarios compose in declaration order', () {
      final suite = CockpitTestSuiteProgram(
        id: 'mixed',
        cases: <CockpitTestCaseProgram>[
          CockpitTestCaseProgram(
            id: 'custom',
            scenario: CockpitTestScenario(id: 'inner', body: (_) async {}),
          ),
        ],
        scenarios: <CockpitTestScenario>[
          CockpitTestScenario(id: 'plain', body: (_) async {}),
        ],
      );

      expect(suite.cases.map((item) => item.id), <String>['custom', 'plain']);
    });

    test('duplicate scenario ids and empty composition are rejected', () {
      expect(
        () => CockpitTestSuiteProgram(
          id: 'duplicate',
          scenarios: <CockpitTestScenario>[
            CockpitTestScenario(id: 'same', body: (_) async {}),
            CockpitTestScenario(id: 'same', body: (_) async {}),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CockpitTestSuiteProgram(
          id: 'empty',
          scenarios: const <CockpitTestScenario>[],
        ),
        throwsArgumentError,
      );
    });
  });
}

/// Minimal tester double that records commands and can fail them by type.
final class _StubTester implements CockpitTester {
  _StubTester({
    this.failures = const <String, CockpitCommandError>{},
    this.appState,
  });

  final Map<String, CockpitCommandError> failures;
  final Map<String, Object?>? appState;

  @override
  CockpitLocaleProfile get locale => CockpitLocaleProfile('en-US');

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) async {
    final error = failures[command.commandType.name];
    final execution = CockpitCommandExecution(
      result: CockpitCommandResult(
        success: error == null,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 0,
        appState: error == null ? appState : null,
        error: error,
      ),
    );
    if (error != null) {
      throw CockpitTestCommandException(command: command, execution: execution);
    }
    return execution;
  }

  @override
  Future<Map<String, Object?>> describeApp() async {
    final execution = await _run(CockpitCommandType.describeApp, null);
    return execution.result.appState ?? const <String, Object?>{};
  }

  @override
  Future<CockpitCommandExecution> tap(Object? target) =>
      _run(CockpitCommandType.tap, target);

  @override
  Future<CockpitCommandExecution> scroll(Object target) =>
      _run(CockpitCommandType.scrollUntilVisible, target);

  @override
  Future<CockpitCommandExecution> expectText(
    Object target,
    Object expected, {
    CockpitTextMatchMode match = CockpitTextMatchMode.exact,
  }) => _run(CockpitCommandType.assertText, target, <String, Object?>{
    'text': expected.toString(),
  });

  Future<CockpitCommandExecution> _run(
    CockpitCommandType type,
    Object? target, [
    Map<String, Object?> parameters = const <String, Object?>{},
  ]) => execute(
    CockpitCommand(
      commandId: '$type',
      commandType: type,
      locator: target is String ? CockpitSelector.parse(target) : null,
      parameters: parameters,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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
