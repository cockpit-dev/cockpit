import 'cockpit_locale.dart';
import 'cockpit_scenario.dart';
import 'cockpit_tester.dart';

enum CockpitTestRunStatus { passed, failed, blocked }

final class CockpitTestRunResult {
  const CockpitTestRunResult({
    required this.status,
    required this.scenarioId,
    required this.locale,
    this.error,
    this.metadata = const <String, Object?>{},
  });

  final CockpitTestRunStatus status;
  final String scenarioId;
  final CockpitLocaleProfile locale;
  final Object? error;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'scenarioId': scenarioId,
    'locale': locale.toJson(),
    if (error != null) 'error': '$error',
    if (metadata.isNotEmpty) 'metadata': metadata,
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
