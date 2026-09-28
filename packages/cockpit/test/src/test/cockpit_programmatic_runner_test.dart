import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('automation tester maps selectors and localized assertions', () async {
    final adapter = _FakeAutomationAdapter();
    var activeLocale = CockpitLocaleProfile('en-US');
    final tester = CockpitAutomationTester(
      automation: adapter,
      initialLocale: activeLocale,
      localeProvider: () => activeLocale,
    );

    await tester.tap('#save');
    activeLocale = CockpitLocaleProfile('zh-CN');
    await tester.expectText(
      '#status',
      CockpitLocalizedText(
        'status.saved',
        values: const <String, String>{'en-US': 'Saved', 'zh-CN': '已保存'},
      ),
    );

    expect(adapter.commands[0].locator?.cockpitId, 'save');
    expect(adapter.commands[1].parameters['text'], '已保存');
  });

  test(
    'automation tester exposes match modes, absence waits, and snapshots',
    () async {
      final adapter = _FakeAutomationAdapter(
        snapshot: CockpitSnapshot(routeName: 'settings').toJson(),
      );
      final tester = CockpitAutomationTester(
        automation: adapter,
        initialLocale: CockpitLocaleProfile('en-US'),
      );

      await tester.expectText(
        '#status',
        'Saved',
        match: CockpitTextMatchMode.contains,
      );
      await tester.waitFor('#drawer', absent: true);
      final snapshot = await tester.collectSnapshot(
        options: const CockpitSnapshotOptions(
          maxTargets: 5,
          includeStyleDetails: true,
        ),
      );

      expect(adapter.commands[0].parameters['matchMode'], 'contains');
      expect(adapter.commands[1].commandType, CockpitCommandType.waitFor);
      expect(adapter.commands[1].parameters['absent'], isTrue);
      expect(
        adapter.commands[2].commandType,
        CockpitCommandType.collectSnapshot,
      );
      expect(adapter.commands[2].snapshotOptions?.maxTargets, 5);
      expect(adapter.commands[2].snapshotOptions?.includeStyleDetails, isTrue);
      expect(snapshot.routeName, 'settings');
    },
  );

  test(
    'collectSnapshot fails through the command exception contract',
    () async {
      final tester = CockpitAutomationTester(
        automation: _FakeAutomationAdapter(
          failures: <String, CockpitCommandError>{
            'collectSnapshot': CockpitCommandError(
              code: CockpitCommandError.unsupportedCapabilityCode,
              message: 'The target exposes no UI tree.',
            ),
          },
        ),
        initialLocale: CockpitLocaleProfile('en-US'),
      );

      final result = await const CockpitProgrammaticTestRunner().run(
        CockpitTestScenario(
          id: 'read-tree',
          body: (tester) => tester.collectSnapshot(),
        ),
        locale: CockpitLocaleProfile('en-US'),
        createTester: (_) async => tester,
      );

      expect(result.status, CockpitTestRunStatus.blocked);
      expect(result.error?.details['commandType'], 'collectSnapshot');
      await expectLater(
        tester.collectSnapshot(),
        throwsA(isA<CockpitTestCommandException>()),
      );
    },
  );

  test('typed command requirements use protocol command names', () async {
    var executed = false;
    final result = await const CockpitProgrammaticTestRunner().run(
      CockpitTestScenario(
        id: 'enter-text',
        requirements: CockpitTestRequirements(
          commands: const <CockpitCommandType>{CockpitCommandType.enterText},
        ),
        body: (_) async {
          executed = true;
        },
      ),
      locale: CockpitLocaleProfile('en-US'),
      createTester: (locale) async => CockpitAutomationTester(
        automation: _FakeAutomationAdapter(),
        initialLocale: locale,
      ),
    );

    expect(executed, isTrue);
    expect(result.status, CockpitTestRunStatus.passed);
    expect(result.error, isNull);
  });

  test('programmatic runner blocks unsupported typed requirements', () async {
    final result = await const CockpitProgrammaticTestRunner().run(
      CockpitTestScenario(
        id: 'needs-semantic',
        requirements: CockpitTestRequirements(
          locators: const <CockpitLocatorKind>{CockpitLocatorKind.semanticId},
        ),
        body: (_) async {},
      ),
      locale: CockpitLocaleProfile('en-US'),
      createTester: (locale) async => CockpitAutomationTester(
        automation: _FakeAutomationAdapter(
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'system-control',
            supportsInAppControl: false,
            supportsFlutterViewCapture: false,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
        ),
        initialLocale: locale,
      ),
    );

    expect(result.status, CockpitTestRunStatus.blocked);
    expect(result.error?.code, CockpitTestErrorCode.targetMismatch);
    expect(result.error?.details['missingRequirements'], <Object?>[
      <String, Object?>{'kind': 'locator', 'value': 'semanticId'},
    ]);
    expect(result.toJson()['error'], isA<Map<String, Object?>>());
  });

  test('performance requirements use tester feature support', () async {
    final runner = const CockpitProgrammaticTestRunner();
    final scenario = CockpitTestScenario(
      id: 'profile',
      requirements: CockpitTestRequirements(
        features: const <CockpitTestFeature>{
          CockpitTestFeature.performanceCapture,
        },
      ),
      body: (_) async {},
    );

    final blocked = await runner.run(
      scenario,
      locale: CockpitLocaleProfile('en-US'),
      createTester: (locale) async => CockpitAutomationTester(
        automation: _FakeAutomationAdapter(),
        initialLocale: locale,
      ),
    );
    final passed = await runner.run(
      scenario,
      locale: CockpitLocaleProfile('en-US'),
      createTester: (locale) async => CockpitAutomationTester(
        automation: _FakeAutomationAdapter(),
        initialLocale: locale,
        performance: _FakePerformanceAdapter(),
      ),
    );

    expect(blocked.status, CockpitTestRunStatus.blocked);
    expect(passed.status, CockpitTestRunStatus.passed);
  });

  test(
    'suite runner executes deterministic locale matrix and metadata',
    () async {
      final suite = CockpitTestSuiteProgram(
        id: 'smoke',
        locales: <CockpitLocaleProfile>[
          CockpitLocaleProfile('en-US'),
          CockpitLocaleProfile('zh-CN'),
        ],
        metadata: const <String, Object?>{'scope': 'suite'},
        cases: <CockpitTestCaseProgram>[
          CockpitTestCaseProgram(
            id: 'save',
            metadata: const <String, Object?>{'case': 'settings'},
            scenario: CockpitTestScenario(
              id: 'save-flow',
              metadata: const <String, Object?>{'surface': 'settings'},
              body: (tester) async {
                await tester.tap('#save');
              },
            ),
          ),
        ],
      );

      final result = await const CockpitProgrammaticTestRunner().runSuite(
        suite,
        createTester: (locale) async => CockpitAutomationTester(
          automation: _FakeAutomationAdapter(),
          initialLocale: locale,
        ),
      );

      expect(result.attempts.map((attempt) => attempt.scenarioId), <String>[
        'save/save-flow',
        'save/save-flow',
      ]);
      expect(
        result.attempts
            .singleWhere((attempt) => attempt.locale.languageTag == 'en-US')
            .metadata,
        <String, Object?>{
          'scope': 'suite',
          'case': 'settings',
          'surface': 'settings',
        },
      );
      expect(result.passed, isTrue);
    },
  );

  test('suite result never reports an empty attempt set as passed', () {
    final result = CockpitSuiteRunResult(
      suiteId: 'empty-result',
      attempts: const <CockpitTestRunResult>[],
    );

    expect(result.passed, isFalse);
  });

  test('profile returns the report and closes the capture window', () async {
    final performance = _FakePerformanceAdapter();
    final tester = CockpitAutomationTester(
      automation: _FakeAutomationAdapter(),
      initialLocale: CockpitLocaleProfile('en-US'),
      performance: performance,
    );

    final report = await tester.profile(() async {}, name: 'smoke');

    expect(report.platform, 'android');
    expect(performance.started, 1);
    expect(performance.stopped, 1);
  });

  test(
    'profile preserves the action failure after successful cleanup',
    () async {
      final performance = _FakePerformanceAdapter();
      final tester = CockpitAutomationTester(
        automation: _FakeAutomationAdapter(),
        initialLocale: CockpitLocaleProfile('en-US'),
        performance: performance,
      );
      final primary = StateError('action failed');

      await expectLater(
        tester.profile(() async => throw primary),
        throwsA(same(primary)),
      );
      expect(performance.stopped, 1);
    },
  );

  test('profile preserves action and cleanup failures', () async {
    final cleanup = StateError('cleanup failed');
    final performance = _FakePerformanceAdapter(stopError: cleanup);
    final tester = CockpitAutomationTester(
      automation: _FakeAutomationAdapter(),
      initialLocale: CockpitLocaleProfile('en-US'),
      performance: performance,
    );
    final primary = StateError('action failed');

    await expectLater(
      tester.profile(() async => throw primary),
      throwsA(
        isA<CockpitTestCleanupException>()
            .having(
              (error) => error.primaryError,
              'primaryError',
              same(primary),
            )
            .having(
              (error) => error.cleanupError,
              'cleanupError',
              same(cleanup),
            ),
      ),
    );
    expect(performance.stopped, 1);
  });

  test('profile fails explicitly without a performance adapter', () async {
    final tester = CockpitAutomationTester(
      automation: _FakeAutomationAdapter(),
      initialLocale: CockpitLocaleProfile('en-US'),
    );

    await expectLater(
      tester.profile(() async {}),
      throwsA(isA<CockpitTestCapabilityException>()),
    );
  });
}

final class _FakeAutomationAdapter implements CockpitAutomationAdapter {
  _FakeAutomationAdapter({
    CockpitCapabilities? capabilities,
    this.failures = const <String, CockpitCommandError>{},
    this.snapshot,
  }) : _capabilities =
           capabilities ??
           CockpitCapabilities(
             platform: 'flutter',
             transportType: 'test',
             supportsInAppControl: true,
             supportsFlutterViewCapture: true,
             supportsNativeScreenCapture: false,
             supportsHostAutomation: false,
             supportedCommands: CockpitCommandType.values,
             supportedLocatorStrategies: CockpitLocatorKind.values,
           );

  final CockpitCapabilities _capabilities;
  final Map<String, CockpitCommandError> failures;
  final Map<String, Object?>? snapshot;
  final commands = <CockpitCommand>[];

  @override
  Future<CockpitCapabilities> describeCapabilities() async => _capabilities;

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) async {
    commands.add(command);
    final error = failures[command.commandType.name];
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: error == null,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 0,
        snapshot: error == null ? snapshot : null,
        error: error,
      ),
    );
  }
}

final class _FakePerformanceAdapter implements CockpitPerformanceAdapter {
  _FakePerformanceAdapter({this.stopError});

  final Object? stopError;
  int started = 0;
  int stopped = 0;

  @override
  Future<CockpitPerformanceCaptureSession> startPerformance(
    CockpitPerformanceCaptureRequest request,
  ) async {
    started += 1;
    return CockpitPerformanceCaptureSession(
      request: request,
      startedAt: DateTime.utc(2026, 1, 1),
      buildMode: 'release',
    );
  }

  @override
  Future<CockpitPerformanceReport> stopPerformance() async {
    stopped += 1;
    if (stopError case final error?) throw error;
    final phase = const CockpitPerformancePhaseSummary(
      sampleCount: 0,
      averageUs: 0,
      p50Us: 0,
      p90Us: 0,
      p99Us: 0,
      worstUs: 0,
      budgetUs: 16667,
      missedBudget: 0,
    );
    final summary = CockpitPerformanceSummary(
      frameCount: 0,
      jankCount: 0,
      build: phase,
      raster: phase,
      vsync: phase,
      total: phase,
      layerCacheMax: const <String, int>{'count': 0, 'bytes': 0},
      pictureCacheMax: const <String, int>{'count': 0, 'bytes': 0},
    );
    return CockpitPerformanceReport(
      startedAt: DateTime.utc(2026, 1, 1),
      finishedAt: DateTime.utc(2026, 1, 1),
      durationUs: 0,
      durationMs: 0,
      platform: 'android',
      buildMode: 'release',
      mode: CockpitPerformanceMode.profile,
      summary: summary,
    );
  }
}
