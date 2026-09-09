import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_test/cockpit_test.dart';

import 'cockpit_automation_tester.dart';

/// Result for every case/locale attempt in a programmatic suite.
final class CockpitSuiteRunResult {
  const CockpitSuiteRunResult({
    required this.suiteId,
    required this.attempts,
  });

  final String suiteId;
  final List<CockpitTestRunResult> attempts;

  bool get passed => attempts.every(
    (attempt) => attempt.status == CockpitTestRunStatus.passed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'suiteId': suiteId,
    'passed': passed,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };
}

/// Default lifecycle runner shared by remote and native programmatic tests.
final class CockpitProgrammaticTestRunner implements CockpitTestRunner {
  const CockpitProgrammaticTestRunner();

  @override
  Future<CockpitTestRunResult> run(
    CockpitTestScenario scenario, {
    required CockpitLocaleProfile locale,
    required Future<CockpitTester> Function(CockpitLocaleProfile locale)
    createTester,
  }) async {
    CockpitTester? tester;
    try {
      tester = await createTester(locale);
      final capabilities = await tester.describeCapabilities();
      final missing = scenario.requiredCapabilities
          .where((capability) => !_supports(capabilities, capability, tester!))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        return CockpitTestRunResult(
          status: CockpitTestRunStatus.blocked,
          scenarioId: scenario.id,
          locale: locale,
          error: CockpitTestCapabilityException(missing.first),
          metadata: <String, Object?>{'missingCapabilities': missing},
        );
      }
      await scenario.body(tester);
      return CockpitTestRunResult(
        status: CockpitTestRunStatus.passed,
        scenarioId: scenario.id,
        locale: locale,
        metadata: scenario.metadata,
      );
    } on CockpitTestCapabilityException catch (error) {
      return CockpitTestRunResult(
        status: CockpitTestRunStatus.blocked,
        scenarioId: scenario.id,
        locale: locale,
        error: error,
        metadata: scenario.metadata,
      );
    } on Object catch (error) {
      return CockpitTestRunResult(
        status: CockpitTestRunStatus.failed,
        scenarioId: scenario.id,
        locale: locale,
        error: error,
        metadata: scenario.metadata,
      );
    }
  }

  /// Executes every case for every locale in deterministic matrix order.
  Future<CockpitSuiteRunResult> runSuite(
    CockpitTestSuiteProgram suite, {
    required Future<CockpitTester> Function(CockpitLocaleProfile locale)
    createTester,
    CockpitLocaleProfile defaultLocale = const CockpitLocaleProfile('en-US'),
  }) async {
    final locales = suite.locales.isEmpty
        ? <CockpitLocaleProfile>[defaultLocale]
        : suite.locales;
    final attempts = <CockpitTestRunResult>[];
    for (final locale in locales) {
      for (final testCase in suite.cases) {
        final result = await run(
          testCase.scenario,
          locale: locale,
          createTester: createTester,
        );
        attempts.add(
          CockpitTestRunResult(
            status: result.status,
            scenarioId: '${testCase.id}/${result.scenarioId}',
            locale: result.locale,
            error: result.error,
            metadata: <String, Object?>{
              ...suite.metadata,
              ...testCase.targetOverrides,
              ...result.metadata,
            },
          ),
        );
      }
    }
    return CockpitSuiteRunResult(
      suiteId: suite.id,
      attempts: List.unmodifiable(attempts),
    );
  }

  bool _supports(
    CockpitCapabilities capabilities,
    String requested,
    CockpitTester tester,
  ) {
    final normalized = requested.trim();
    if (normalized.isEmpty) return false;
    if (normalized.toLowerCase() == 'performance' &&
        tester is CockpitAutomationTester) {
      return tester.supportsPerformance;
    }
    final command = _commandByName(normalized);
    if (command != null) {
      return capabilities.supportedCommands.contains(command);
    }
    final locator = _locatorByName(normalized);
    if (locator != null) {
      return capabilities.supportedLocatorStrategies.contains(locator);
    }
    return switch (normalized.toLowerCase()) {
      'inappcontrol' || 'in-app-control' => capabilities.supportsInAppControl,
      'flutterviewcapture' || 'flutter-view-capture' =>
        capabilities.supportsFlutterViewCapture,
      'nativescreencapture' || 'native-screen-capture' =>
        capabilities.supportsNativeScreenCapture,
      'hostautomation' || 'host-automation' =>
        capabilities.supportsHostAutomation,
      'viewportresize' || 'viewport-resize' =>
        capabilities.supportsViewportResize,
      _ => false,
    };
  }

  CockpitCommandType? _commandByName(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '').replaceAll('_', '');
    for (final command in CockpitCommandType.values) {
      if (command.name.toLowerCase() == normalized) return command;
    }
    return null;
  }

  CockpitLocatorKind? _locatorByName(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '').replaceAll('_', '');
    final alias = switch (normalized) {
      'semantic' || 'semantics' => CockpitLocatorKind.semanticId,
      'testid' => CockpitLocatorKind.testId,
      'native' => CockpitLocatorKind.nativeId,
      _ => null,
    };
    if (alias != null) return alias;
    for (final locator in CockpitLocatorKind.values) {
      if (locator.name.toLowerCase() == normalized) return locator;
    }
    return null;
  }
}
