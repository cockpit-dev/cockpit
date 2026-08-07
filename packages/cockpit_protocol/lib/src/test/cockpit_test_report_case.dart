import '../foundation/cockpit_api_error.dart';
import '../foundation/cockpit_foundation_artifact.dart';
import '../foundation/cockpit_run.dart';
import 'cockpit_test_case.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestAttemptReport {
  /// Creates a CockpitTestAttemptReport.
  CockpitTestAttemptReport({
    required this.attemptId,
    required this.number,
    required this.outcome,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.targetId,
    this.failure,
    Iterable<CockpitArtifactReference> artifacts =
        const <CockpitArtifactReference>[],
  }) : artifacts = List<CockpitArtifactReference>.unmodifiable(artifacts) {
    CockpitTestValueReader.string(attemptId, r'$.attemptId', id: true);
    if (number < 1 || durationMs < 0 || finishedAt.isBefore(startedAt)) {
      throw const FormatException(
        'Attempt report timing or number is invalid.',
      );
    }
    CockpitTestValueReader.string(targetId, r'$.targetId', id: true);
    if ((outcome == CockpitRunOutcome.passed) == (failure != null)) {
      throw const FormatException(
        'Attempt report outcome and failure disagree.',
      );
    }
  }

  final String attemptId;
  final int number;
  final CockpitRunOutcome outcome;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;
  final String targetId;
  final CockpitFailure? failure;
  final List<CockpitArtifactReference> artifacts;

  /// Encodes this CockpitTestAttemptReport as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'attemptId': attemptId,
    'number': number,
    'outcome': outcome.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'targetId': targetId,
    if (failure != null) 'failure': failure!.toJson(),
    if (artifacts.isNotEmpty)
      'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };

  /// Decodes a CockpitTestAttemptReport from a JSON object.
  factory CockpitTestAttemptReport.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'attemptId',
        'number',
        'outcome',
        'startedAt',
        'finishedAt',
        'durationMs',
        'targetId',
        'failure',
        'artifacts',
      },
      path,
      required: const <String>{
        'attemptId',
        'number',
        'outcome',
        'startedAt',
        'finishedAt',
        'durationMs',
        'targetId',
      },
    );
    final rawArtifacts = json['artifacts'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['artifacts'], '$path.artifacts');
    return CockpitTestAttemptReport(
      attemptId: CockpitTestValueReader.string(
        json['attemptId'],
        '$path.attemptId',
        id: true,
      ),
      number: CockpitTestValueReader.integer(
        json['number'],
        '$path.number',
        minimum: 1,
      ),
      outcome: CockpitTestValueReader.enumeration(
        json['outcome'],
        CockpitRunOutcome.values,
        '$path.outcome',
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
      targetId: CockpitTestValueReader.string(
        json['targetId'],
        '$path.targetId',
        id: true,
      ),
      failure: json['failure'] == null
          ? null
          : CockpitFailure.fromJson(json['failure'], path: '$path.failure'),
      artifacts: <CockpitArtifactReference>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          CockpitArtifactReference.fromJson(
            rawArtifacts[index],
            path: '$path.artifacts[$index]',
          ),
      ],
    );
  }
}

final class CockpitTestCaseReport {
  /// Creates a CockpitTestCaseReport.
  CockpitTestCaseReport({
    required this.entryId,
    required this.caseId,
    required this.definition,
    required this.sourceSha256,
    required this.outcome,
    required this.stability,
    required this.targetId,
    Map<String, Object?> matrix = const <String, Object?>{},
    Iterable<CockpitTestAttemptReport> attempts =
        const <CockpitTestAttemptReport>[],
  }) : matrix = Map<String, Object?>.unmodifiable(
         CockpitTestValueReader.object(
           CockpitTestValueReader.jsonValue(matrix, r'$.matrix'),
           r'$.matrix',
         ),
       ),
       attempts = List<CockpitTestAttemptReport>.unmodifiable(attempts) {
    CockpitTestValueReader.string(entryId, r'$.entryId', id: true);
    CockpitTestValueReader.string(caseId, r'$.caseId', id: true);
    if (definition.id != caseId) {
      throw const FormatException(
        'Case report definition identity does not match the result.',
      );
    }
    CockpitTestValueReader.string(sourceSha256, r'$.sourceSha256');
    CockpitTestValueReader.string(targetId, r'$.targetId', id: true);
    if (outcome == CockpitRunOutcome.passed && this.attempts.isEmpty) {
      throw const FormatException('A passed case report requires an attempt.');
    }
  }

  final String entryId;
  final String caseId;
  final CockpitTestCase definition;
  final String sourceSha256;
  final CockpitRunOutcome outcome;
  final CockpitRunStability stability;
  final String targetId;
  final Map<String, Object?> matrix;
  final List<CockpitTestAttemptReport> attempts;

  /// Encodes this CockpitTestCaseReport as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'entryId': entryId,
    'caseId': caseId,
    'definition': definition.toJson(),
    'sourceSha256': sourceSha256,
    'outcome': outcome.name,
    'stability': stability.name,
    'targetId': targetId,
    if (matrix.isNotEmpty) 'matrix': matrix,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };

  /// Decodes a CockpitTestCaseReport from a JSON object.
  factory CockpitTestCaseReport.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'entryId',
        'caseId',
        'definition',
        'sourceSha256',
        'outcome',
        'stability',
        'targetId',
        'matrix',
        'attempts',
      },
      path,
      required: const <String>{
        'entryId',
        'caseId',
        'definition',
        'sourceSha256',
        'outcome',
        'stability',
        'targetId',
        'attempts',
      },
    );
    final rawAttempts = CockpitTestValueReader.list(
      json['attempts'],
      '$path.attempts',
    );
    return CockpitTestCaseReport(
      entryId: CockpitTestValueReader.string(
        json['entryId'],
        '$path.entryId',
        id: true,
      ),
      caseId: CockpitTestValueReader.string(
        json['caseId'],
        '$path.caseId',
        id: true,
      ),
      definition: CockpitTestCase.fromJson(
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
      targetId: CockpitTestValueReader.string(
        json['targetId'],
        '$path.targetId',
        id: true,
      ),
      matrix: json['matrix'] == null
          ? const <String, Object?>{}
          : CockpitTestValueReader.object(
              CockpitTestValueReader.jsonValue(json['matrix'], '$path.matrix'),
              '$path.matrix',
            ),
      attempts: <CockpitTestAttemptReport>[
        for (var index = 0; index < rawAttempts.length; index += 1)
          CockpitTestAttemptReport.fromJson(
            rawAttempts[index],
            path: '$path.attempts[$index]',
          ),
      ],
    );
  }
}
