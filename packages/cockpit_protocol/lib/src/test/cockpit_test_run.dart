import '../foundation/cockpit_authorization_mode.dart';
import '../control/cockpit_locator_resolution.dart';
import 'cockpit_test_error.dart';
import 'cockpit_test_diagnostic.dart';
import 'cockpit_test_policy.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestLifecycle { queued, running, finalizing, completed }

enum CockpitTestOutcome {
  passed,
  failed,
  blocked,
  skipped,
  cancelled,
  interrupted,
  internalError,
}

enum CockpitTestStability { stable, flaky, unknown }

enum CockpitTestStepStatus {
  pending,
  running,
  passed,
  failed,
  blocked,
  cancelled,
  skipped,
}

final class CockpitTestRunContext {
  CockpitTestRunContext({
    required this.projectId,
    required this.workspaceId,
    required this.runId,
    required this.caseId,
    required this.attemptId,
    required this.engineVersion,
    this.authorizationMode = CockpitAuthorizationMode.restricted,
  }) {
    for (final entry in <String, String>{
      'projectId': projectId,
      'workspaceId': workspaceId,
      'runId': runId,
      'caseId': caseId,
      'attemptId': attemptId,
    }.entries) {
      CockpitTestValueReader.string(entry.value, r'$.' + entry.key, id: true);
    }
    CockpitTestValueReader.string(engineVersion, r'$.engineVersion');
  }

  final String projectId;
  final String workspaceId;
  final String runId;
  final String caseId;
  final String attemptId;
  final String engineVersion;
  final CockpitAuthorizationMode authorizationMode;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    'workspaceId': workspaceId,
    'runId': runId,
    'caseId': caseId,
    'attemptId': attemptId,
    'engineVersion': engineVersion,
    'authorizationMode': authorizationMode.name,
  };

  factory CockpitTestRunContext.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    const fields = <String>{
      'projectId',
      'workspaceId',
      'runId',
      'caseId',
      'attemptId',
      'engineVersion',
      'authorizationMode',
    };
    CockpitTestValueReader.keys(json, fields, path, required: fields);
    String id(String key) =>
        CockpitTestValueReader.string(json[key], '$path.$key', id: true);
    return CockpitTestRunContext(
      projectId: id('projectId'),
      workspaceId: id('workspaceId'),
      runId: id('runId'),
      caseId: id('caseId'),
      attemptId: id('attemptId'),
      engineVersion: CockpitTestValueReader.string(
        json['engineVersion'],
        '$path.engineVersion',
      ),
      authorizationMode: CockpitTestValueReader.enumeration(
        json['authorizationMode'],
        CockpitAuthorizationMode.values,
        '$path.authorizationMode',
      ),
    );
  }
}

final class CockpitTestStepOccurrence {
  CockpitTestStepOccurrence({
    this.retryAttempt,
    this.loopIteration,
    Iterable<String> callPath = const <String>[],
  }) : callPath = List<String>.unmodifiable(callPath) {
    if (retryAttempt != null && retryAttempt! <= 0) {
      throw const FormatException('retryAttempt must be positive.');
    }
    if (loopIteration != null && loopIteration! <= 0) {
      throw const FormatException('loopIteration must be positive.');
    }
    for (var index = 0; index < this.callPath.length; index += 1) {
      CockpitTestValueReader.string(
        this.callPath[index],
        '\$.callPath[$index]',
        id: true,
      );
    }
  }

  final int? retryAttempt;
  final int? loopIteration;
  final List<String> callPath;

  Map<String, Object?> toJson() => <String, Object?>{
    if (retryAttempt != null) 'retryAttempt': retryAttempt,
    if (loopIteration != null) 'loopIteration': loopIteration,
    if (callPath.isNotEmpty) 'callPath': callPath,
  };

  factory CockpitTestStepOccurrence.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'retryAttempt',
      'loopIteration',
      'callPath',
    }, path);
    return CockpitTestStepOccurrence(
      retryAttempt: json['retryAttempt'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['retryAttempt'],
              '$path.retryAttempt',
              minimum: 1,
            ),
      loopIteration: json['loopIteration'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['loopIteration'],
              '$path.loopIteration',
              minimum: 1,
            ),
      callPath: json['callPath'] == null
          ? const <String>[]
          : CockpitTestValueReader.strings(
              json['callPath'],
              '$path.callPath',
              id: true,
            ),
    );
  }
}

final class CockpitTestStepResult {
  CockpitTestStepResult({
    required this.stepId,
    required this.executionId,
    required this.section,
    this.description,
    this.operation,
    this.timeoutMs,
    this.definitionPath,
    required this.status,
    required this.startedAt,
    required this.durationMs,
    CockpitTestStepOccurrence? occurrence,
    this.sourceLocation,
    this.requestedPlane,
    this.actualPlane,
    this.driverId,
    this.locatorResolution,
    this.degradationReason,
    this.error,
    Iterable<String> evidence = const <String>[],
  }) : occurrence = occurrence ?? CockpitTestStepOccurrence(),
       evidence = List<String>.unmodifiable(evidence) {
    CockpitTestValueReader.string(stepId, r'$.stepId', id: true);
    CockpitTestValueReader.string(executionId, r'$.executionId');
    if (description != null) {
      CockpitTestValueReader.string(description, r'$.description');
    }
    if (operation != null) {
      CockpitTestValueReader.string(operation, r'$.operation');
    }
    if (timeoutMs != null && timeoutMs! <= 0) {
      throw const FormatException('Step result timeoutMs must be positive.');
    }
    if (definitionPath != null) {
      CockpitTestValueReader.string(definitionPath, r'$.definitionPath');
    }
    if (!const <String>{'setup', 'main', 'finally'}.contains(section)) {
      throw const FormatException(
        'Step section must be setup, main, or finally.',
      );
    }
    if (durationMs < 0) {
      throw const FormatException('Step durationMs cannot be negative.');
    }
    if (driverId != null) {
      CockpitTestValueReader.string(driverId, r'$.driverId', id: true);
    }
    if (degradationReason != null) {
      CockpitTestValueReader.string(
        degradationReason,
        r'$.degradationReason',
        maximum: 512,
      );
    }
    final requiresError = switch (status) {
      CockpitTestStepStatus.failed ||
      CockpitTestStepStatus.blocked ||
      CockpitTestStepStatus.cancelled => true,
      CockpitTestStepStatus.pending ||
      CockpitTestStepStatus.running ||
      CockpitTestStepStatus.passed ||
      CockpitTestStepStatus.skipped => false,
    };
    if (requiresError != (error != null)) {
      throw const FormatException(
        'Step status and error presence are inconsistent.',
      );
    }
    for (var index = 0; index < this.evidence.length; index += 1) {
      CockpitTestValueReader.string(
        this.evidence[index],
        '\$.evidence[$index]',
        id: true,
      );
    }
  }

  final String stepId;
  final String executionId;
  final String section;
  final String? description;
  final String? operation;
  final int? timeoutMs;
  final String? definitionPath;
  final CockpitTestStepStatus status;
  final DateTime startedAt;
  final int durationMs;
  final CockpitTestStepOccurrence occurrence;
  final CockpitTestSourceLocation? sourceLocation;
  final CockpitTestPlane? requestedPlane;
  final CockpitTestPlane? actualPlane;
  final String? driverId;
  final CockpitLocatorResolution? locatorResolution;
  final String? degradationReason;
  final CockpitTestError? error;
  final List<String> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'stepId': stepId,
    'executionId': executionId,
    'section': section,
    if (description != null) 'description': description,
    if (operation != null) 'operation': operation,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
    if (definitionPath != null) 'definitionPath': definitionPath,
    'status': status.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'occurrence': occurrence.toJson(),
    if (sourceLocation != null) 'sourceLocation': sourceLocation!.toJson(),
    if (requestedPlane != null) 'requestedPlane': requestedPlane!.name,
    if (actualPlane != null) 'actualPlane': actualPlane!.name,
    if (driverId != null) 'driverId': driverId,
    if (locatorResolution != null)
      'locatorResolution': locatorResolution!.toJson(),
    if (degradationReason != null) 'degradationReason': degradationReason,
    if (error != null) 'error': error!.toJson(),
    if (evidence.isNotEmpty) 'evidence': evidence,
  };

  factory CockpitTestStepResult.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'stepId',
        'executionId',
        'section',
        'description',
        'operation',
        'timeoutMs',
        'definitionPath',
        'status',
        'startedAt',
        'durationMs',
        'occurrence',
        'sourceLocation',
        'requestedPlane',
        'actualPlane',
        'driverId',
        'locatorResolution',
        'degradationReason',
        'error',
        'evidence',
      },
      path,
      required: const <String>{
        'stepId',
        'executionId',
        'section',
        'status',
        'startedAt',
        'durationMs',
        'occurrence',
      },
    );
    return CockpitTestStepResult(
      stepId: CockpitTestValueReader.string(
        json['stepId'],
        '$path.stepId',
        id: true,
      ),
      executionId: CockpitTestValueReader.string(
        json['executionId'],
        '$path.executionId',
      ),
      section: CockpitTestValueReader.string(json['section'], '$path.section'),
      description: CockpitTestValueReader.optionalString(
        json['description'],
        '$path.description',
      ),
      operation: CockpitTestValueReader.optionalString(
        json['operation'],
        '$path.operation',
      ),
      timeoutMs: json['timeoutMs'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['timeoutMs'],
              '$path.timeoutMs',
              minimum: 1,
            ),
      definitionPath: CockpitTestValueReader.optionalString(
        json['definitionPath'],
        '$path.definitionPath',
      ),
      status: CockpitTestValueReader.enumeration(
        json['status'],
        CockpitTestStepStatus.values,
        '$path.status',
      ),
      startedAt: CockpitTestValueReader.dateTime(
        json['startedAt'],
        '$path.startedAt',
      ),
      durationMs: CockpitTestValueReader.integer(
        json['durationMs'],
        '$path.durationMs',
        minimum: 0,
      ),
      occurrence: CockpitTestStepOccurrence.fromJson(
        json['occurrence'],
        path: '$path.occurrence',
      ),
      sourceLocation: json['sourceLocation'] == null
          ? null
          : CockpitTestSourceLocation.fromJson(
              json['sourceLocation'],
              path: '$path.sourceLocation',
            ),
      requestedPlane: json['requestedPlane'] == null
          ? null
          : CockpitTestValueReader.enumeration(
              json['requestedPlane'],
              CockpitTestPlane.values,
              '$path.requestedPlane',
            ),
      actualPlane: json['actualPlane'] == null
          ? null
          : CockpitTestValueReader.enumeration(
              json['actualPlane'],
              CockpitTestPlane.values,
              '$path.actualPlane',
            ),
      driverId: json['driverId'] == null
          ? null
          : CockpitTestValueReader.string(
              json['driverId'],
              '$path.driverId',
              id: true,
            ),
      locatorResolution: json['locatorResolution'] == null
          ? null
          : CockpitLocatorResolution.fromJson(
              Map<String, Object?>.from(
                CockpitTestValueReader.object(
                  json['locatorResolution'],
                  '$path.locatorResolution',
                ),
              ),
            ),
      degradationReason: json['degradationReason'] == null
          ? null
          : CockpitTestValueReader.string(
              json['degradationReason'],
              '$path.degradationReason',
              maximum: 512,
            ),
      error: json['error'] == null
          ? null
          : CockpitTestError.fromJson(json['error'], path: '$path.error'),
      evidence: json['evidence'] == null
          ? const <String>[]
          : CockpitTestValueReader.strings(
              json['evidence'],
              '$path.evidence',
              id: true,
              unique: true,
            ),
    );
  }
}

final class CockpitTestAttemptResult {
  CockpitTestAttemptResult({
    required this.context,
    required this.lifecycle,
    required this.outcome,
    required this.stability,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.targetId,
    required this.platform,
    required this.requestedPlane,
    this.actualPlane,
    Iterable<CockpitTestStepResult> steps = const <CockpitTestStepResult>[],
    this.primaryError,
    Iterable<CockpitTestError> cleanupErrors = const <CockpitTestError>[],
    this.bundlePath,
  }) : steps = List<CockpitTestStepResult>.unmodifiable(steps),
       cleanupErrors = List<CockpitTestError>.unmodifiable(cleanupErrors) {
    if (lifecycle != CockpitTestLifecycle.completed) {
      throw const FormatException(
        'A returned attempt result must be completed.',
      );
    }
    if (durationMs < 0 || finishedAt.isBefore(startedAt)) {
      throw const FormatException(
        'Attempt timestamps or duration are invalid.',
      );
    }
    if (outcome == CockpitTestOutcome.passed && primaryError != null) {
      throw const FormatException(
        'A passed attempt cannot have a primary error.',
      );
    }
    if (outcome != CockpitTestOutcome.passed && primaryError == null) {
      throw const FormatException(
        'A non-passed attempt requires a primary error.',
      );
    }
    CockpitTestValueReader.string(targetId, r'$.targetId');
    CockpitTestValueReader.string(platform, r'$.platform');
  }

  final CockpitTestRunContext context;
  final CockpitTestLifecycle lifecycle;
  final CockpitTestOutcome outcome;
  final CockpitTestStability stability;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int durationMs;
  final String targetId;
  final String platform;
  final CockpitTestPlane requestedPlane;
  final CockpitTestPlane? actualPlane;
  final List<CockpitTestStepResult> steps;
  final CockpitTestError? primaryError;
  final List<CockpitTestError> cleanupErrors;
  final String? bundlePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'context': context.toJson(),
    'lifecycle': lifecycle.name,
    'outcome': outcome.name,
    'stability': stability.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'targetId': targetId,
    'platform': platform,
    'requestedPlane': requestedPlane.name,
    if (actualPlane != null) 'actualPlane': actualPlane!.name,
    'steps': steps.map((step) => step.toJson()).toList(),
    if (primaryError != null) 'primaryError': primaryError!.toJson(),
    if (cleanupErrors.isNotEmpty)
      'cleanupErrors': cleanupErrors.map((error) => error.toJson()).toList(),
    if (bundlePath != null) 'bundlePath': bundlePath,
  };

  factory CockpitTestAttemptResult.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'context',
        'lifecycle',
        'outcome',
        'stability',
        'startedAt',
        'finishedAt',
        'durationMs',
        'targetId',
        'platform',
        'requestedPlane',
        'actualPlane',
        'steps',
        'primaryError',
        'cleanupErrors',
        'bundlePath',
      },
      path,
      required: const <String>{
        'context',
        'lifecycle',
        'outcome',
        'stability',
        'startedAt',
        'finishedAt',
        'durationMs',
        'targetId',
        'platform',
        'requestedPlane',
        'steps',
      },
    );
    final rawSteps = CockpitTestValueReader.list(json['steps'], '$path.steps');
    final rawCleanupErrors = json['cleanupErrors'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(
            json['cleanupErrors'],
            '$path.cleanupErrors',
          );
    return CockpitTestAttemptResult(
      context: CockpitTestRunContext.fromJson(
        json['context'],
        path: '$path.context',
      ),
      lifecycle: CockpitTestValueReader.enumeration(
        json['lifecycle'],
        CockpitTestLifecycle.values,
        '$path.lifecycle',
      ),
      outcome: CockpitTestValueReader.enumeration(
        json['outcome'],
        CockpitTestOutcome.values,
        '$path.outcome',
      ),
      stability: CockpitTestValueReader.enumeration(
        json['stability'],
        CockpitTestStability.values,
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
      targetId: CockpitTestValueReader.string(
        json['targetId'],
        '$path.targetId',
      ),
      platform: CockpitTestValueReader.string(
        json['platform'],
        '$path.platform',
      ),
      requestedPlane: CockpitTestValueReader.enumeration(
        json['requestedPlane'],
        CockpitTestPlane.values,
        '$path.requestedPlane',
      ),
      actualPlane: json['actualPlane'] == null
          ? null
          : CockpitTestValueReader.enumeration(
              json['actualPlane'],
              CockpitTestPlane.values,
              '$path.actualPlane',
            ),
      steps: <CockpitTestStepResult>[
        for (var index = 0; index < rawSteps.length; index += 1)
          CockpitTestStepResult.fromJson(
            rawSteps[index],
            path: '$path.steps[$index]',
          ),
      ],
      primaryError: json['primaryError'] == null
          ? null
          : CockpitTestError.fromJson(
              json['primaryError'],
              path: '$path.primaryError',
            ),
      cleanupErrors: <CockpitTestError>[
        for (var index = 0; index < rawCleanupErrors.length; index += 1)
          CockpitTestError.fromJson(
            rawCleanupErrors[index],
            path: '$path.cleanupErrors[$index]',
          ),
      ],
      bundlePath: CockpitTestValueReader.optionalString(
        json['bundlePath'],
        '$path.bundlePath',
      ),
    );
  }
}
