import 'cockpit_api_error.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitRunLifecycle { queued, running, finalizing, completed }

enum CockpitRunOutcome {
  passed,
  failed,
  blocked,
  skipped,
  cancelled,
  interrupted,
  internalError,
}

enum CockpitRunStability { stable, flaky, unknown }

enum CockpitRunDocumentKind { testCase, suite }

abstract final class CockpitRunStateMachine {
  static bool canTransition(CockpitRunLifecycle from, CockpitRunLifecycle to) {
    if (from == to) {
      return true;
    }
    return switch (from) {
      CockpitRunLifecycle.queued =>
        to == CockpitRunLifecycle.running ||
            to == CockpitRunLifecycle.completed,
      CockpitRunLifecycle.running =>
        to == CockpitRunLifecycle.finalizing ||
            to == CockpitRunLifecycle.completed,
      CockpitRunLifecycle.finalizing => to == CockpitRunLifecycle.completed,
      CockpitRunLifecycle.completed => false,
    };
  }
}

final class CockpitRunResource {
  /// Creates a CockpitRunResource.
  CockpitRunResource({
    required this.projectId,
    required this.workspaceId,
    required this.runId,
    required this.documentKind,
    required this.documentId,
    required this.sourceSha256,
    required this.lifecycle,
    required this.submittedAt,
    this.outcome,
    this.stability,
    this.startedAt,
    this.finishedAt,
    Iterable<String> caseIds = const <String>[],
    Iterable<String> activeAttemptIds = const <String>[],
    this.failure,
  }) : caseIds = List<String>.unmodifiable(caseIds),
       activeAttemptIds = List<String>.unmodifiable(activeAttemptIds) {
    for (final entry in <String, String>{
      'projectId': projectId,
      'workspaceId': workspaceId,
      'runId': runId,
      'documentId': documentId,
    }.entries) {
      CockpitFoundationValueReader.id(entry.value, '\$.${entry.key}');
    }
    CockpitFoundationValueReader.sha256(sourceSha256, r'$.sourceSha256');
    CockpitFoundationValueReader.utcDateTime(submittedAt, r'$.submittedAt');
    if (startedAt != null) {
      CockpitFoundationValueReader.utcDateTime(startedAt!, r'$.startedAt');
    }
    if (finishedAt != null) {
      CockpitFoundationValueReader.utcDateTime(finishedAt!, r'$.finishedAt');
    }
    final cases = <String>{};
    for (final caseId in this.caseIds) {
      CockpitFoundationValueReader.id(caseId, r'$.caseIds[]');
      if (!cases.add(caseId)) {
        throw FormatException('Duplicate case $caseId.');
      }
    }
    final attempts = <String>{};
    for (final attemptId in this.activeAttemptIds) {
      CockpitFoundationValueReader.id(attemptId, r'$.activeAttemptIds[]');
      if (!attempts.add(attemptId)) {
        throw FormatException('Duplicate active attempt $attemptId.');
      }
    }
    if (documentKind == CockpitRunDocumentKind.testCase &&
        (this.caseIds.length != 1 || this.caseIds.single != documentId)) {
      throw const FormatException('Standalone run case identity is invalid.');
    }
    _validateRunState(this);
    if (failure != null &&
        failure!.artifacts.any((artifact) => artifact.runId != runId)) {
      throw const FormatException(
        'Run failure artifact belongs to another run.',
      );
    }
  }

  final String projectId;
  final String workspaceId;
  final String runId;
  final CockpitRunDocumentKind documentKind;
  final String documentId;
  final String sourceSha256;
  final CockpitRunLifecycle lifecycle;
  final CockpitRunOutcome? outcome;
  final CockpitRunStability? stability;
  final DateTime submittedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<String> caseIds;
  final List<String> activeAttemptIds;
  final CockpitFailure? failure;

  /// Encodes this CockpitRunResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    'workspaceId': workspaceId,
    'runId': runId,
    'documentKind': documentKind == CockpitRunDocumentKind.testCase
        ? 'case'
        : documentKind.name,
    'documentId': documentId,
    'sourceSha256': sourceSha256,
    'lifecycle': lifecycle.name,
    if (outcome != null) 'outcome': outcome!.name,
    if (stability != null) 'stability': stability!.name,
    'submittedAt': submittedAt.toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    'caseIds': caseIds,
    'activeAttemptIds': activeAttemptIds,
    if (failure != null) 'failure': failure!.toJson(),
  };

  /// Decodes a CockpitRunResource from a JSON object.
  factory CockpitRunResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'projectId',
        'workspaceId',
        'runId',
        'documentKind',
        'documentId',
        'sourceSha256',
        'lifecycle',
        'outcome',
        'stability',
        'submittedAt',
        'startedAt',
        'finishedAt',
        'caseIds',
        'activeAttemptIds',
        'failure',
      },
      path,
      required: const <String>{
        'projectId',
        'workspaceId',
        'runId',
        'documentKind',
        'documentId',
        'sourceSha256',
        'lifecycle',
        'submittedAt',
        'caseIds',
        'activeAttemptIds',
      },
      policy: decodePolicy,
    );
    return CockpitRunResource(
      projectId: CockpitFoundationValueReader.id(
        json['projectId'],
        '$path.projectId',
      ),
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      runId: CockpitFoundationValueReader.id(json['runId'], '$path.runId'),
      documentKind: _runDocumentKind(
        json['documentKind'],
        '$path.documentKind',
      ),
      documentId: CockpitFoundationValueReader.id(
        json['documentId'],
        '$path.documentId',
      ),
      sourceSha256: CockpitFoundationValueReader.sha256(
        json['sourceSha256'],
        '$path.sourceSha256',
      ),
      lifecycle: _enum(
        json['lifecycle'],
        CockpitRunLifecycle.values,
        '$path.lifecycle',
      ),
      outcome: json['outcome'] == null
          ? null
          : _enum(json['outcome'], CockpitRunOutcome.values, '$path.outcome'),
      stability: json['stability'] == null
          ? null
          : _enum(
              json['stability'],
              CockpitRunStability.values,
              '$path.stability',
            ),
      submittedAt: CockpitFoundationValueReader.dateTime(
        json['submittedAt'],
        '$path.submittedAt',
      ),
      startedAt: json['startedAt'] == null
          ? null
          : CockpitFoundationValueReader.dateTime(
              json['startedAt'],
              '$path.startedAt',
            ),
      finishedAt: json['finishedAt'] == null
          ? null
          : CockpitFoundationValueReader.dateTime(
              json['finishedAt'],
              '$path.finishedAt',
            ),
      caseIds: CockpitFoundationValueReader.ids(
        json['caseIds'],
        '$path.caseIds',
      ),
      activeAttemptIds: CockpitFoundationValueReader.ids(
        json['activeAttemptIds'],
        '$path.activeAttemptIds',
      ),
      failure: json['failure'] == null
          ? null
          : CockpitFailure.fromJson(
              json['failure'],
              path: '$path.failure',
              decodePolicy: decodePolicy,
            ),
    );
  }
}

final class CockpitRunCaseResource {
  /// Creates a CockpitRunCaseResource.
  CockpitRunCaseResource({
    required this.runId,
    required this.caseId,
    required this.sourceSha256,
    required Iterable<String> attemptIds,
    this.outcome,
    this.stability,
  }) : attemptIds = List<String>.unmodifiable(attemptIds) {
    CockpitFoundationValueReader.id(runId, r'$.runId');
    CockpitFoundationValueReader.id(caseId, r'$.caseId');
    CockpitFoundationValueReader.sha256(sourceSha256, r'$.sourceSha256');
    CockpitFoundationValueReader.ids(this.attemptIds, r'$.attemptIds');
    if ((outcome == null) != (stability == null)) {
      throw const FormatException('Run case outcome and stability disagree.');
    }
  }

  final String runId;
  final String caseId;
  final String sourceSha256;
  final List<String> attemptIds;
  final CockpitRunOutcome? outcome;
  final CockpitRunStability? stability;

  /// Encodes this CockpitRunCaseResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'caseId': caseId,
    'sourceSha256': sourceSha256,
    'attemptIds': attemptIds,
    if (outcome != null) 'outcome': outcome!.name,
    if (stability != null) 'stability': stability!.name,
  };

  /// Decodes a CockpitRunCaseResource from a JSON object.
  factory CockpitRunCaseResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'runId',
        'caseId',
        'sourceSha256',
        'attemptIds',
        'outcome',
        'stability',
      },
      path,
      required: const <String>{'runId', 'caseId', 'sourceSha256', 'attemptIds'},
      policy: decodePolicy,
    );
    return CockpitRunCaseResource(
      runId: CockpitFoundationValueReader.id(json['runId'], '$path.runId'),
      caseId: CockpitFoundationValueReader.id(json['caseId'], '$path.caseId'),
      sourceSha256: CockpitFoundationValueReader.sha256(
        json['sourceSha256'],
        '$path.sourceSha256',
      ),
      attemptIds: CockpitFoundationValueReader.ids(
        json['attemptIds'],
        '$path.attemptIds',
      ),
      outcome: json['outcome'] == null
          ? null
          : _enum(json['outcome'], CockpitRunOutcome.values, '$path.outcome'),
      stability: json['stability'] == null
          ? null
          : _enum(
              json['stability'],
              CockpitRunStability.values,
              '$path.stability',
            ),
    );
  }
}

void _validateRunState(CockpitRunResource run) {
  if (run.startedAt != null && run.startedAt!.isBefore(run.submittedAt) ||
      run.finishedAt != null &&
          run.finishedAt!.isBefore(run.startedAt ?? run.submittedAt)) {
    throw const FormatException('Run timestamps are inconsistent.');
  }
  final completed = run.lifecycle == CockpitRunLifecycle.completed;
  if (completed !=
          (run.outcome != null &&
              run.stability != null &&
              run.finishedAt != null) ||
      (!completed &&
          (run.outcome != null ||
              run.stability != null ||
              run.finishedAt != null))) {
    throw const FormatException('Run lifecycle is inconsistent.');
  }
  if (run.lifecycle == CockpitRunLifecycle.queued && run.startedAt != null ||
      (run.lifecycle == CockpitRunLifecycle.running ||
              run.lifecycle == CockpitRunLifecycle.finalizing) &&
          run.startedAt == null ||
      completed && run.activeAttemptIds.isNotEmpty) {
    throw const FormatException('Run active state is inconsistent.');
  }
  final passed = run.outcome == CockpitRunOutcome.passed;
  if ((completed && !passed) != (run.failure != null) ||
      (passed && run.failure != null)) {
    throw const FormatException('Run outcome and failure disagree.');
  }
  if (passed && run.caseIds.isEmpty) {
    throw const FormatException('A passed run requires a completed case.');
  }
  if (passed && run.startedAt == null) {
    throw const FormatException('A passed run requires a start timestamp.');
  }
}

CockpitRunDocumentKind _runDocumentKind(Object? value, String path) {
  final name = CockpitFoundationValueReader.string(value, path);
  if (name == 'case') return CockpitRunDocumentKind.testCase;
  return _enum(name, CockpitRunDocumentKind.values, path);
}

T _enum<T extends Enum>(Object? value, List<T> values, String path) {
  return CockpitEnumValue<T>.parse(
    value,
    values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}
