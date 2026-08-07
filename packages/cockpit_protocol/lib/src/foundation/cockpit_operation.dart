import 'cockpit_api_error.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';
import 'cockpit_idempotency.dart';

enum CockpitOperationLifecycle { queued, running, completed }

enum CockpitOperationOutcome {
  succeeded,
  failed,
  blocked,
  cancelled,
  interrupted,
}

final class CockpitOperationInvocation {
  /// Creates a CockpitOperationInvocation.
  CockpitOperationInvocation({
    required this.kind,
    Map<String, Object?> input = const <String, Object?>{},
    this.rootId,
    this.workspaceId,
    this.idempotencyKey,
    this.deadline,
    Iterable<String> requiredFeatures = const <String>[],
  }) : input = CockpitFoundationValueReader.jsonObject(input, r'$.input'),
       requiredFeatures = List<String>.unmodifiable(requiredFeatures) {
    CockpitFoundationValueReader.kind(kind, r'$.kind');
    if (rootId != null) {
      CockpitFoundationValueReader.id(rootId, r'$.rootId');
    }
    if (workspaceId != null) {
      CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    }
    if (deadline != null) {
      CockpitFoundationValueReader.utcDateTime(deadline!, r'$.deadline');
      if (!deadline!.isAfter(
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      )) {
        throw const FormatException('Operation deadline is invalid.');
      }
    }
    final features = <String>{};
    for (final feature in this.requiredFeatures) {
      CockpitFoundationValueReader.id(feature, r'$.requiredFeatures[]');
      if (!features.add(feature)) {
        throw FormatException('Duplicate required feature $feature.');
      }
    }
  }

  final String kind;
  final Map<String, Object?> input;
  final String? rootId;
  final String? workspaceId;
  final CockpitIdempotencyKey? idempotencyKey;
  final DateTime? deadline;
  final List<String> requiredFeatures;

  /// Encodes this CockpitOperationInvocation as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'input': input,
    if (rootId != null) 'rootId': rootId,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey!.toJson(),
    if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
    'requiredFeatures': requiredFeatures,
  };

  /// Decodes a CockpitOperationInvocation from a JSON object.
  factory CockpitOperationInvocation.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'kind',
        'input',
        'rootId',
        'workspaceId',
        'idempotencyKey',
        'deadline',
        'requiredFeatures',
      },
      path,
      required: const <String>{'kind', 'input', 'requiredFeatures'},
    );
    return CockpitOperationInvocation(
      kind: CockpitFoundationValueReader.kind(json['kind'], '$path.kind'),
      input: CockpitFoundationValueReader.jsonObject(
        json['input'],
        '$path.input',
      ),
      rootId: json['rootId'] == null
          ? null
          : CockpitFoundationValueReader.id(json['rootId'], '$path.rootId'),
      workspaceId: json['workspaceId'] == null
          ? null
          : CockpitFoundationValueReader.id(
              json['workspaceId'],
              '$path.workspaceId',
            ),
      idempotencyKey: json['idempotencyKey'] == null
          ? null
          : CockpitIdempotencyKey.fromJson(
              json['idempotencyKey'],
              path: '$path.idempotencyKey',
            ),
      deadline: json['deadline'] == null
          ? null
          : CockpitFoundationValueReader.dateTime(
              json['deadline'],
              '$path.deadline',
            ),
      requiredFeatures: CockpitFoundationValueReader.ids(
        json['requiredFeatures'],
        '$path.requiredFeatures',
      ),
    );
  }
}

final class CockpitOperationResult {
  /// Creates a CockpitOperationResult.
  CockpitOperationResult({
    required this.operationId,
    required this.kind,
    required this.lifecycle,
    required this.submittedAt,
    this.rootId,
    this.workspaceId,
    this.outcome,
    this.startedAt,
    this.finishedAt,
    Map<String, Object?>? output,
    this.failure,
  }) : output = output == null
           ? null
           : CockpitFoundationValueReader.jsonObject(output, r'$.output') {
    CockpitFoundationValueReader.id(operationId, r'$.operationId');
    CockpitFoundationValueReader.kind(kind, r'$.kind');
    if (rootId != null) {
      CockpitFoundationValueReader.id(rootId, r'$.rootId');
    }
    if (workspaceId != null) {
      CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    }
    if (rootId != null && workspaceId != null) {
      throw const FormatException('Operation result has ambiguous scope.');
    }
    CockpitFoundationValueReader.utcDateTime(submittedAt, r'$.submittedAt');
    if (startedAt != null) {
      CockpitFoundationValueReader.utcDateTime(startedAt!, r'$.startedAt');
    }
    if (finishedAt != null) {
      CockpitFoundationValueReader.utcDateTime(finishedAt!, r'$.finishedAt');
    }
    _validateExecutionState(
      lifecycle: lifecycle,
      outcome: outcome,
      submittedAt: submittedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      output: this.output,
      failure: failure,
    );
  }

  final String operationId;
  final String kind;
  final String? rootId;
  final String? workspaceId;
  final CockpitOperationLifecycle lifecycle;
  final CockpitOperationOutcome? outcome;
  final DateTime submittedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final Map<String, Object?>? output;
  final CockpitFailure? failure;

  /// Encodes this CockpitOperationResult as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'kind': kind,
    if (rootId != null) 'rootId': rootId,
    if (workspaceId != null) 'workspaceId': workspaceId,
    'lifecycle': lifecycle.name,
    if (outcome != null) 'outcome': outcome!.name,
    'submittedAt': submittedAt.toUtc().toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    if (output != null) 'output': output,
    if (failure != null) 'failure': failure!.toJson(),
  };

  /// Decodes a CockpitOperationResult from a JSON object.
  factory CockpitOperationResult.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'operationId',
        'kind',
        'rootId',
        'workspaceId',
        'lifecycle',
        'outcome',
        'submittedAt',
        'startedAt',
        'finishedAt',
        'output',
        'failure',
      },
      path,
      required: const <String>{
        'operationId',
        'kind',
        'lifecycle',
        'submittedAt',
      },
      policy: decodePolicy,
    );
    return CockpitOperationResult(
      operationId: CockpitFoundationValueReader.id(
        json['operationId'],
        '$path.operationId',
      ),
      kind: CockpitFoundationValueReader.kind(json['kind'], '$path.kind'),
      rootId: json['rootId'] == null
          ? null
          : CockpitFoundationValueReader.id(json['rootId'], '$path.rootId'),
      workspaceId: json['workspaceId'] == null
          ? null
          : CockpitFoundationValueReader.id(
              json['workspaceId'],
              '$path.workspaceId',
            ),
      lifecycle: _enum(
        json['lifecycle'],
        CockpitOperationLifecycle.values,
        '$path.lifecycle',
      ),
      outcome: json['outcome'] == null
          ? null
          : _enum(
              json['outcome'],
              CockpitOperationOutcome.values,
              '$path.outcome',
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
      output: json['output'] == null
          ? null
          : CockpitFoundationValueReader.jsonObject(
              json['output'],
              '$path.output',
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

void _validateExecutionState({
  required CockpitOperationLifecycle lifecycle,
  required CockpitOperationOutcome? outcome,
  required DateTime submittedAt,
  required DateTime? startedAt,
  required DateTime? finishedAt,
  required Map<String, Object?>? output,
  required CockpitFailure? failure,
}) {
  if (startedAt != null && startedAt.isBefore(submittedAt) ||
      finishedAt != null && (finishedAt.isBefore(startedAt ?? submittedAt))) {
    throw const FormatException('Operation timestamps are inconsistent.');
  }
  final completed = lifecycle == CockpitOperationLifecycle.completed;
  if (completed != (outcome != null && finishedAt != null) ||
      (!completed &&
          (finishedAt != null || outcome != null || output != null))) {
    throw const FormatException('Operation lifecycle is inconsistent.');
  }
  if (lifecycle == CockpitOperationLifecycle.queued && startedAt != null ||
      lifecycle == CockpitOperationLifecycle.running && startedAt == null) {
    throw const FormatException('Operation start state is inconsistent.');
  }
  final succeeded = outcome == CockpitOperationOutcome.succeeded;
  if ((completed && !succeeded) != (failure != null) ||
      (succeeded && failure != null)) {
    throw const FormatException('Operation outcome and failure disagree.');
  }
}

T _enum<T extends Enum>(Object? value, List<T> values, String path) {
  return CockpitEnumValue<T>.parse(
    value,
    values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}
