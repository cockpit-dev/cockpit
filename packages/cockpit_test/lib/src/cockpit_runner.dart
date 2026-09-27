import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_errors.dart';
import 'cockpit_json.dart';
import 'cockpit_locale.dart';
import 'cockpit_requirements.dart';
import 'cockpit_scenario.dart';
import 'cockpit_suite.dart';
import 'cockpit_test_feature.dart';
import 'cockpit_tester.dart';

enum CockpitTestRunStatus { passed, failed, blocked }

final class CockpitTestRunResult {
  CockpitTestRunResult({
    required this.status,
    required String scenarioId,
    required this.locale,
    this.error,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : scenarioId = _validatedId(scenarioId, 'scenarioId'),
       metadata = freezeCockpitJson(metadata, path: r'$.metadata') {
    if (status == CockpitTestRunStatus.passed && error != null) {
      throw ArgumentError.value(
        error,
        'error',
        'A passed run cannot have an error.',
      );
    }
    if (status != CockpitTestRunStatus.passed && error == null) {
      throw ArgumentError.value(
        error,
        'error',
        'A non-passed run requires an error.',
      );
    }
  }

  final CockpitTestRunStatus status;
  final String scenarioId;
  final CockpitLocaleProfile locale;
  final CockpitTestError? error;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'scenarioId': scenarioId,
    'locale': locale.toJson(),
    if (error != null) 'error': error!.toJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

final class CockpitSuiteRunResult {
  CockpitSuiteRunResult({
    required String suiteId,
    required Iterable<CockpitTestRunResult> attempts,
  }) : suiteId = _validatedId(suiteId, 'suiteId'),
       attempts = List<CockpitTestRunResult>.unmodifiable(attempts);

  final String suiteId;
  final List<CockpitTestRunResult> attempts;

  bool get passed =>
      attempts.isNotEmpty &&
      attempts.every(
        (attempt) => attempt.status == CockpitTestRunStatus.passed,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'suiteId': suiteId,
    'passed': passed,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };
}

/// Runner lifecycle boundary used by local, integrated-release, and native
/// black-box hosts.
abstract interface class CockpitTestRunner {
  Future<CockpitTestRunResult> run(
    CockpitTestScenario scenario, {
    required CockpitLocaleProfile locale,
    required Future<CockpitTester> Function(CockpitLocaleProfile locale)
    createTester,
  });
}

/// Default lifecycle runner shared by every programmatic Cockpit tester.
final class CockpitProgrammaticTestRunner implements CockpitTestRunner {
  const CockpitProgrammaticTestRunner();

  @override
  Future<CockpitTestRunResult> run(
    CockpitTestScenario scenario, {
    required CockpitLocaleProfile locale,
    required Future<CockpitTester> Function(CockpitLocaleProfile locale)
    createTester,
  }) async {
    try {
      final tester = await createTester(locale);
      final missing = await _missingRequirements(scenario.requirements, tester);
      if (missing.isNotEmpty) {
        final names = missing
            .map((item) => '${item['kind']}:${item['value']}')
            .join(', ');
        return CockpitTestRunResult(
          status: CockpitTestRunStatus.blocked,
          scenarioId: scenario.id,
          locale: locale,
          error: CockpitTestError(
            code: CockpitTestErrorCode.targetMismatch,
            message: 'The target does not support: $names.',
            details: <String, Object?>{'missingRequirements': missing},
          ),
          metadata: scenario.metadata,
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
        error: CockpitTestError(
          code: CockpitTestErrorCode.targetMismatch,
          message: _safeMessage(error),
          details: <String, Object?>{'capability': error.capability},
        ),
        metadata: scenario.metadata,
      );
    } on CockpitTestCommandException catch (error) {
      return CockpitTestRunResult(
        status: CockpitTestRunStatus.failed,
        scenarioId: scenario.id,
        locale: locale,
        error: _commandError(error),
        metadata: scenario.metadata,
      );
    } on Object catch (error) {
      return CockpitTestRunResult(
        status: CockpitTestRunStatus.failed,
        scenarioId: scenario.id,
        locale: locale,
        error: CockpitTestError(
          code: error is CockpitTestException
              ? CockpitTestErrorCode.assertionFailed
              : CockpitTestErrorCode.internalFailure,
          message: _safeMessage(error),
        ),
        metadata: scenario.metadata,
      );
    }
  }

  /// Executes every case for every locale in deterministic matrix order.
  Future<CockpitSuiteRunResult> runSuite(
    CockpitTestSuiteProgram suite, {
    required Future<CockpitTester> Function(CockpitLocaleProfile locale)
    createTester,
    CockpitLocaleProfile? defaultLocale,
  }) async {
    final locales = suite.locales.isEmpty
        ? <CockpitLocaleProfile>[defaultLocale ?? CockpitLocaleProfile('en-US')]
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
              ...testCase.metadata,
              ...result.metadata,
            },
          ),
        );
      }
    }
    return CockpitSuiteRunResult(suiteId: suite.id, attempts: attempts);
  }
}

Future<List<Map<String, Object?>>> _missingRequirements(
  CockpitTestRequirements requirements,
  CockpitTester tester,
) async {
  if (requirements.isEmpty) return const <Map<String, Object?>>[];

  final needsProtocolCapabilities =
      requirements.commands.isNotEmpty || requirements.locators.isNotEmpty;
  final capabilities = needsProtocolCapabilities
      ? await tester.describeCapabilities()
      : null;
  final featureProvider = tester is CockpitTestFeatureProvider
      ? tester as CockpitTestFeatureProvider
      : null;
  final features = requirements.features.isEmpty || featureProvider == null
      ? const <CockpitTestFeature>{}
      : await featureProvider.describeFeatures();
  final missing = <Map<String, Object?>>[];
  final commands = requirements.commands.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  for (final command in commands) {
    if (!capabilities!.supportedCommands.contains(command)) {
      missing.add(<String, Object?>{'kind': 'command', 'value': command.name});
    }
  }
  final locators = requirements.locators.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  for (final locator in locators) {
    if (!capabilities!.supportedLocatorStrategies.contains(locator)) {
      missing.add(<String, Object?>{'kind': 'locator', 'value': locator.name});
    }
  }
  final requiredFeatures = requirements.features.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  for (final feature in requiredFeatures) {
    if (!features.contains(feature)) {
      missing.add(<String, Object?>{'kind': 'feature', 'value': feature.name});
    }
  }
  return missing;
}

CockpitTestError _commandError(CockpitTestCommandException failure) {
  final error = failure.execution.result.error;
  final code = switch (error?.code) {
    CockpitCommandError.timeoutCode => CockpitTestErrorCode.timeout,
    CockpitCommandError.assertionFailedCode =>
      CockpitTestErrorCode.assertionFailed,
    CockpitCommandError.unsupportedCapabilityCode =>
      CockpitTestErrorCode.unsupportedAction,
    CockpitCommandError.targetNotFoundCode ||
    CockpitCommandError.ambiguousTargetCode ||
    CockpitCommandError.targetNotHittableCode =>
      CockpitTestErrorCode.assertionFailed,
    _ => CockpitTestErrorCode.driverFailed,
  };
  return CockpitTestError(
    code: code,
    message: _safeMessage(error?.message ?? failure),
    details: <String, Object?>{
      'commandType': failure.command.commandType.name,
      if (error != null) 'commandErrorCode': error.code,
    },
  );
}

String _validatedId(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}

String _safeMessage(Object value) {
  final redacted = const CockpitNetworkRedactor().text('$value');
  if (redacted.length <= 4096) return redacted;
  return '${redacted.substring(0, 4093)}...';
}
