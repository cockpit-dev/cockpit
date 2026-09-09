import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_test/cockpit_test.dart';
import 'package:test/test.dart';

void main() {
  test('automation tester maps selectors and localized assertions', () async {
    final adapter = _FakeAutomationAdapter();
    var activeLocale = const CockpitLocaleProfile('en-US');
    final tester = CockpitAutomationTester(
      automation: adapter,
      initialLocale: activeLocale,
      localeProvider: () => activeLocale,
    );

    await tester.tap('#save');
    activeLocale = const CockpitLocaleProfile('zh-CN');
    await tester.expectText(
      '#status',
      const CockpitLocalizedText(
        'status.saved',
        values: <String, String>{'en-US': 'Saved', 'zh-CN': '已保存'},
      ),
    );

    expect(adapter.commands[0].locator?.cockpitId, 'save');
    expect(adapter.commands[1].parameters['text'], '已保存');
  });

  test('programmatic runner blocks unsupported capabilities', () async {
    final runner = const CockpitProgrammaticTestRunner();
    final result = await runner.run(
      CockpitTestScenario(
        id: 'needs-semantic',
        requiredCapabilities: const <String>{'semantic'},
        body: (_) async {},
      ),
      locale: const CockpitLocaleProfile('en-US'),
      createTester: (locale) async => CockpitAutomationTester(
        automation: _FakeAutomationAdapter(
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'system-control',
            supportsInAppControl: false,
            supportsFlutterViewCapture: false,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
            supportedCommands: const <CockpitCommandType>[],
            supportedLocatorStrategies: const <CockpitLocatorKind>[],
          ),
        ),
        initialLocale: locale,
      ),
    );

    expect(result.status, CockpitTestRunStatus.blocked);
    expect(result.error, isA<CockpitTestCapabilityException>());
  });

  test('suite runner executes deterministic locale matrix', () async {
    final runner = const CockpitProgrammaticTestRunner();
    final suite = CockpitTestSuiteProgram(
      id: 'smoke',
      locales: const <CockpitLocaleProfile>[
        CockpitLocaleProfile('en-US'),
        CockpitLocaleProfile('zh-CN'),
      ],
      cases: <CockpitTestCaseProgram>[
        CockpitTestCaseProgram(
          id: 'save',
          scenario: CockpitTestScenario(id: 'save-flow', body: (tester) async {
            await tester.tap('#save');
          }),
        ),
      ],
    );

    final result = await runner.runSuite(
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
    expect(result.passed, isTrue);
  });

  test('profile returns the adapter report and always stops the window', () async {
    final performance = _FakePerformanceAdapter();
    final tester = CockpitAutomationTester(
      automation: _FakeAutomationAdapter(),
      initialLocale: const CockpitLocaleProfile('en-US'),
      performance: performance,
    );

    final report = await tester.profile(() async {}, name: 'smoke');

    expect(report.platform, 'android');
    expect(performance.started, 1);
    expect(performance.stopped, 1);
  });

  test('profile reports an explicit capability failure without an adapter', () async {
    final tester = CockpitAutomationTester(
      automation: _FakeAutomationAdapter(),
      initialLocale: const CockpitLocaleProfile('en-US'),
    );

    await expectLater(
      tester.profile(() async {}),
      throwsA(isA<CockpitTestCapabilityException>()),
    );
  });
}

final class _FakeAutomationAdapter implements CockpitAutomationAdapter {
  _FakeAutomationAdapter({CockpitCapabilities? capabilities})
    : _capabilities =
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
  final commands = <CockpitCommand>[];

  @override
  Future<CockpitCapabilities> describeCapabilities() async => _capabilities;

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
}

final class _FakePerformanceAdapter implements CockpitPerformanceAdapter {
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
