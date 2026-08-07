import 'dart:convert';

import '../foundation/cockpit_api_error.dart';
import '../foundation/cockpit_foundation_artifact.dart';
import '../foundation/cockpit_run.dart';
import 'cockpit_test_report_case.dart';
import 'cockpit_test_suite.dart';
import 'cockpit_test_suite_policy.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestReportCounts {
  /// Creates a CockpitTestReportCounts.
  const CockpitTestReportCounts({
    required this.total,
    required this.passed,
    required this.failed,
    required this.blocked,
    required this.skipped,
    required this.cancelled,
    required this.interrupted,
    required this.internalError,
    required this.flaky,
  });

  /// Creates a CockpitTestReportCounts using the named constructor `fromCases`.
  factory CockpitTestReportCounts.fromCases(
    Iterable<CockpitTestCaseReport> cases,
  ) {
    final values = cases.toList(growable: false);
    int count(CockpitRunOutcome outcome) =>
        values.where((item) => item.outcome == outcome).length;
    return CockpitTestReportCounts(
      total: values.length,
      passed: count(CockpitRunOutcome.passed),
      failed: count(CockpitRunOutcome.failed),
      blocked: count(CockpitRunOutcome.blocked),
      skipped: count(CockpitRunOutcome.skipped),
      cancelled: count(CockpitRunOutcome.cancelled),
      interrupted: count(CockpitRunOutcome.interrupted),
      internalError: count(CockpitRunOutcome.internalError),
      flaky: values
          .where((item) => item.stability == CockpitRunStability.flaky)
          .length,
    );
  }

  final int total;
  final int passed;
  final int failed;
  final int blocked;
  final int skipped;
  final int cancelled;
  final int interrupted;
  final int internalError;
  final int flaky;

  /// Encodes this CockpitTestReportCounts as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'total': total,
    'passed': passed,
    'failed': failed,
    'blocked': blocked,
    'skipped': skipped,
    'cancelled': cancelled,
    'interrupted': interrupted,
    'internalError': internalError,
    'flaky': flaky,
  };
}

final class CockpitTestSuiteReport {
  /// Creates a CockpitTestSuiteReport.
  CockpitTestSuiteReport({
    this.schemaVersion = 'cockpit.report/v2',
    required this.projectId,
    required this.workspaceId,
    required this.runId,
    required this.suiteId,
    required this.definition,
    required this.sourceSha256,
    required this.outcome,
    required this.stability,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.execution,
    required this.reportPolicy,
    this.failure,
    Map<String, Object?> environment = const <String, Object?>{},
    Map<String, List<Object?>> matrixAxes = const <String, List<Object?>>{},
    required Iterable<CockpitTestCaseReport> cases,
    Iterable<CockpitArtifactReference> artifacts =
        const <CockpitArtifactReference>[],
    this.complete = true,
  }) : environment = Map<String, Object?>.unmodifiable(
         CockpitTestValueReader.object(
           CockpitTestValueReader.jsonValue(environment, r'$.environment'),
           r'$.environment',
         ),
       ),
       matrixAxes =
           Map<String, List<Object?>>.unmodifiable(<String, List<Object?>>{
             for (final entry in matrixAxes.entries)
               entry.key: List<Object?>.unmodifiable(entry.value),
           }),
       cases = List<CockpitTestCaseReport>.unmodifiable(cases),
       artifacts = List<CockpitArtifactReference>.unmodifiable(artifacts) {
    if (schemaVersion != 'cockpit.report/v2') {
      throw const FormatException('Unsupported report schemaVersion.');
    }
    for (final entry in <String, String>{
      'projectId': projectId,
      'workspaceId': workspaceId,
      'runId': runId,
      'suiteId': suiteId,
    }.entries) {
      CockpitTestValueReader.string(entry.value, '\$.${entry.key}', id: true);
    }
    CockpitTestValueReader.string(sourceSha256, r'$.sourceSha256');
    if (definition.id != suiteId ||
        !_jsonEquals(definition.execution.toJson(), execution.toJson()) ||
        !_jsonEquals(definition.report.toJson(), reportPolicy.toJson())) {
      throw const FormatException(
        'Suite report definition does not match its execution policy.',
      );
    }
    if (!complete || durationMs < 0 || finishedAt.isBefore(startedAt)) {
      throw const FormatException(
        'Final suite report is incomplete or invalid.',
      );
    }
    if (this.cases.isEmpty) {
      throw const FormatException('A suite report requires case results.');
    }
    final entryIds = <String>{};
    for (final item in this.cases) {
      if (!entryIds.add(
        '${item.entryId}\u0000${item.targetId}\u0000${jsonEncode(item.matrix)}',
      )) {
        throw const FormatException(
          'Suite report contains a duplicate case row.',
        );
      }
    }
    for (final artifact in this.artifacts) {
      if (artifact.runId != runId) {
        throw const FormatException('Report artifact belongs to another run.');
      }
    }
    _validateOutcome();
  }

  final String schemaVersion;
  final String projectId;
  final String workspaceId;
  final String runId;
  final String suiteId;
  final CockpitTestSuite definition;
  final String sourceSha256;
  final CockpitRunOutcome outcome;
  final CockpitRunStability stability;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;
  final CockpitTestSuiteExecutionPolicy execution;
  final CockpitTestSuiteReportPolicy reportPolicy;
  final CockpitFailure? failure;
  final Map<String, Object?> environment;
  final Map<String, List<Object?>> matrixAxes;
  final List<CockpitTestCaseReport> cases;
  final List<CockpitArtifactReference> artifacts;
  final bool complete;

  CockpitTestReportCounts get counts =>
      CockpitTestReportCounts.fromCases(cases);

  /// Encodes this CockpitTestSuiteReport as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'projectId': projectId,
    'workspaceId': workspaceId,
    'runId': runId,
    'suiteId': suiteId,
    'definition': definition.toJson(),
    'sourceSha256': sourceSha256,
    'lifecycle': CockpitRunLifecycle.completed.name,
    'outcome': outcome.name,
    'stability': stability.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'execution': execution.toJson(),
    'reportPolicy': reportPolicy.toJson(),
    if (failure != null) 'failure': failure!.toJson(),
    'environment': environment,
    'matrix': <String, Object?>{'axes': matrixAxes},
    'counts': counts.toJson(),
    'cases': cases.map((item) => item.toJson()).toList(),
    if (artifacts.isNotEmpty)
      'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'complete': complete,
  };

  /// Decodes a CockpitTestSuiteReport from a JSON object.
  factory CockpitTestSuiteReport.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'schemaVersion',
        'projectId',
        'workspaceId',
        'runId',
        'suiteId',
        'definition',
        'sourceSha256',
        'lifecycle',
        'outcome',
        'stability',
        'startedAt',
        'finishedAt',
        'durationMs',
        'execution',
        'reportPolicy',
        'failure',
        'environment',
        'matrix',
        'counts',
        'cases',
        'artifacts',
        'complete',
      },
      path,
      required: const <String>{
        'schemaVersion',
        'projectId',
        'workspaceId',
        'runId',
        'suiteId',
        'definition',
        'sourceSha256',
        'lifecycle',
        'outcome',
        'stability',
        'startedAt',
        'finishedAt',
        'durationMs',
        'execution',
        'reportPolicy',
        'environment',
        'matrix',
        'counts',
        'cases',
        'complete',
      },
    );
    if (json['lifecycle'] != CockpitRunLifecycle.completed.name) {
      throw FormatException('Expected a completed report at $path.lifecycle.');
    }
    final rawCases = CockpitTestValueReader.list(json['cases'], '$path.cases');
    final rawArtifacts = json['artifacts'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['artifacts'], '$path.artifacts');
    final matrix = CockpitTestValueReader.object(
      json['matrix'],
      '$path.matrix',
    );
    CockpitTestValueReader.keys(
      matrix,
      const <String>{'axes'},
      '$path.matrix',
      required: const <String>{'axes'},
    );
    final rawAxes = CockpitTestValueReader.object(
      matrix['axes'],
      '$path.matrix.axes',
    );
    final result = CockpitTestSuiteReport(
      schemaVersion: CockpitTestValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      projectId: CockpitTestValueReader.string(
        json['projectId'],
        '$path.projectId',
        id: true,
      ),
      workspaceId: CockpitTestValueReader.string(
        json['workspaceId'],
        '$path.workspaceId',
        id: true,
      ),
      runId: CockpitTestValueReader.string(
        json['runId'],
        '$path.runId',
        id: true,
      ),
      suiteId: CockpitTestValueReader.string(
        json['suiteId'],
        '$path.suiteId',
        id: true,
      ),
      definition: CockpitTestSuite.fromJson(
        json['definition'],
        path: '$path.definition',
      ),
      sourceSha256: CockpitTestValueReader.string(
        json['sourceSha256'],
        '$path.sourceSha256',
      ),
      outcome: CockpitTestValueReader.enumeration(
        json['outcome'],
        CockpitRunOutcome.values,
        '$path.outcome',
      ),
      stability: CockpitTestValueReader.enumeration(
        json['stability'],
        CockpitRunStability.values,
        '$path.stability',
      ),
      startedAt: CockpitTestValueReader.dateTime(
        json['startedAt'],
        '$path.startedAt',
      ),
      finishedAt: CockpitTestValueReader.dateTime(
        json['finishedAt'],
        '$path.finishedAt',
      ),
      durationMs: CockpitTestValueReader.integer(
        json['durationMs'],
        '$path.durationMs',
        minimum: 0,
      ),
      execution: CockpitTestSuiteExecutionPolicy.fromJson(
        json['execution'],
        path: '$path.execution',
      ),
      reportPolicy: CockpitTestSuiteReportPolicy.fromJson(
        json['reportPolicy'],
        path: '$path.reportPolicy',
      ),
      failure: json['failure'] == null
          ? null
          : CockpitFailure.fromJson(json['failure'], path: '$path.failure'),
      environment: CockpitTestValueReader.object(
        CockpitTestValueReader.jsonValue(
          json['environment'],
          '$path.environment',
        ),
        '$path.environment',
      ),
      matrixAxes: <String, List<Object?>>{
        for (final entry in rawAxes.entries)
          entry.key: CockpitTestValueReader.list(
            entry.value,
            '$path.matrix.axes.${entry.key}',
          ),
      },
      cases: <CockpitTestCaseReport>[
        for (var index = 0; index < rawCases.length; index += 1)
          CockpitTestCaseReport.fromJson(
            rawCases[index],
            path: '$path.cases[$index]',
          ),
      ],
      artifacts: <CockpitArtifactReference>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          CockpitArtifactReference.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
          ),
      ],
      complete: CockpitTestValueReader.boolean(
        json['complete'],
        '$path.complete',
      ),
    );
    final encodedCounts = CockpitTestValueReader.canonicalJson(json['counts']);
    if (encodedCounts !=
        CockpitTestValueReader.canonicalJson(result.counts.toJson())) {
      throw FormatException(
        'Report counts disagree with cases at $path.counts.',
      );
    }
    return result;
  }

  void _validateOutcome() {
    final expected = _aggregateOutcome(cases.map((item) => item.outcome));
    if (failure == null && outcome != expected) {
      throw const FormatException(
        'Suite report outcome is not aggregate truth.',
      );
    }
    if (failure != null &&
        (_outcomeSeverity(outcome) == 0 ||
            _outcomeSeverity(outcome) < _outcomeSeverity(expected))) {
      throw const FormatException(
        'Suite failure and aggregate outcome are inconsistent.',
      );
    }
    final expectedStability =
        cases.any((item) => item.stability == CockpitRunStability.flaky)
        ? CockpitRunStability.flaky
        : CockpitRunStability.stable;
    if (stability != expectedStability) {
      throw const FormatException('Suite report stability is inconsistent.');
    }
  }
}

bool _jsonEquals(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

int _outcomeSeverity(CockpitRunOutcome outcome) => switch (outcome) {
  CockpitRunOutcome.passed || CockpitRunOutcome.skipped => 0,
  CockpitRunOutcome.blocked => 1,
  CockpitRunOutcome.failed => 2,
  CockpitRunOutcome.cancelled => 3,
  CockpitRunOutcome.interrupted => 4,
  CockpitRunOutcome.internalError => 5,
};

CockpitRunOutcome _aggregateOutcome(Iterable<CockpitRunOutcome> outcomes) {
  final values = outcomes.toSet();
  for (final outcome in const <CockpitRunOutcome>[
    CockpitRunOutcome.internalError,
    CockpitRunOutcome.interrupted,
    CockpitRunOutcome.cancelled,
    CockpitRunOutcome.failed,
    CockpitRunOutcome.blocked,
  ]) {
    if (values.contains(outcome)) return outcome;
  }
  return values.every(
        (outcome) =>
            outcome == CockpitRunOutcome.passed ||
            outcome == CockpitRunOutcome.skipped,
      )
      ? CockpitRunOutcome.passed
      : CockpitRunOutcome.internalError;
}
