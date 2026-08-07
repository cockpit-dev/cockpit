import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_worker_value_reader.dart';

sealed class CockpitWorkerProtocolRequest {
  CockpitWorkerProtocolRequest({
    required this.protocolVersion,
    required this.workspaceId,
    required this.requestId,
    required this.deadline,
    required this.idempotencyKey,
  }) {
    if (protocolVersion != cockpitWorkerProtocolVersion) {
      throw const FormatException('Incompatible worker protocol version.');
    }
    workerId(workspaceId, r'$.workspaceId');
    workerId(requestId, r'$.requestId');
    workerUtcDateTimeValue(deadline, r'$.deadline');
    workerId(idempotencyKey, r'$.idempotencyKey');
  }

  final String protocolVersion;
  final String workspaceId;
  final String requestId;
  final DateTime deadline;
  final String idempotencyKey;

  String get method;

  Map<String, Object?> toJson();

  Map<String, Object?> metadataJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'workspaceId': workspaceId,
    'requestId': requestId,
    'deadline': deadline.toUtc().toIso8601String(),
    'idempotencyKey': idempotencyKey,
  };

  static CockpitWorkerProtocolRequest fromJson(String method, Object? value) {
    workerMethod(method, r'$.method');
    return switch (method) {
      'initialize' => CockpitWorkerInitializeRequest.fromJson(value),
      'capabilities' => CockpitWorkerCapabilitiesRequest.fromJson(value),
      'operation' => CockpitWorkerOperationRequest.fromJson(value),
      'cancel' => CockpitWorkerCancelRequest.fromJson(value),
      'drain' => CockpitWorkerDrainRequest.fromJson(value),
      'health' => CockpitWorkerHealthRequest.fromJson(value),
      'shutdown' => CockpitWorkerShutdownRequest.fromJson(value),
      'replayEvents' => CockpitWorkerReplayEventsRequest.fromJson(value),
      'publishEventBatch' => CockpitWorkerPublishEventBatchRequest.fromJson(
        value,
      ),
      'publishArtifactBatch' =>
        CockpitWorkerPublishArtifactBatchRequest.fromJson(value),
      'readSessionArtifact' => CockpitWorkerReadSessionArtifactRequest.fromJson(
        value,
      ),
      _ => throw const FormatException('Unsupported worker method.'),
    };
  }
}

final class CockpitWorkerInitializeRequest
    extends CockpitWorkerProtocolRequest {
  CockpitWorkerInitializeRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.engineVersion,
    required this.workspaceRoot,
    required Iterable<String> supportedFeatures,
  }) : supportedFeatures = List<String>.unmodifiable(supportedFeatures) {
    workerId(engineVersion, r'$.engineVersion');
    workerString(workspaceRoot, r'$.workspaceRoot', maximum: 32768);
    _uniqueIds(this.supportedFeatures, r'$.supportedFeatures');
  }

  final String engineVersion;
  final String workspaceRoot;
  final List<String> supportedFeatures;

  @override
  String get method => 'initialize';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'engineVersion': engineVersion,
    'workspaceRoot': workspaceRoot,
    'supportedFeatures': supportedFeatures,
  };

  factory CockpitWorkerInitializeRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{
      'engineVersion',
      'workspaceRoot',
      'supportedFeatures',
    });
    final metadata = _metadata(json);
    return CockpitWorkerInitializeRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      engineVersion: workerId(json['engineVersion'], r'$.engineVersion'),
      workspaceRoot: workerString(
        json['workspaceRoot'],
        r'$.workspaceRoot',
        maximum: 32768,
      ),
      supportedFeatures: _ids(
        json['supportedFeatures'],
        r'$.supportedFeatures',
      ),
    );
  }
}

final class CockpitWorkerCapabilitiesRequest
    extends CockpitWorkerProtocolRequest {
  CockpitWorkerCapabilitiesRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
  });

  @override
  String get method => 'capabilities';

  @override
  Map<String, Object?> toJson() => metadataJson();

  factory CockpitWorkerCapabilitiesRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{});
    final metadata = _metadata(json);
    return CockpitWorkerCapabilitiesRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
    );
  }
}

final class CockpitWorkerOperationRequest extends CockpitWorkerProtocolRequest {
  CockpitWorkerOperationRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.invocation,
  }) {
    if (invocation.workspaceId != workspaceId ||
        invocation.rootId != null ||
        invocation.deadline != deadline ||
        invocation.idempotencyKey?.value != idempotencyKey) {
      throw const FormatException(
        'Operation invocation metadata does not match its worker envelope.',
      );
    }
  }

  final CockpitOperationInvocation invocation;

  @override
  String get method => 'operation';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'invocation': invocation.toJson(),
  };

  factory CockpitWorkerOperationRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{'invocation'});
    final metadata = _metadata(json);
    return CockpitWorkerOperationRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      invocation: CockpitOperationInvocation.fromJson(json['invocation']),
    );
  }
}

final class CockpitWorkerCancelRequest extends CockpitWorkerProtocolRequest {
  CockpitWorkerCancelRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.targetRequestId,
  }) {
    workerId(targetRequestId, r'$.targetRequestId');
    if (targetRequestId == requestId) {
      throw const FormatException('A cancel request cannot cancel itself.');
    }
  }

  final String targetRequestId;

  @override
  String get method => 'cancel';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'targetRequestId': targetRequestId,
  };

  factory CockpitWorkerCancelRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{'targetRequestId'});
    final metadata = _metadata(json);
    return CockpitWorkerCancelRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      targetRequestId: workerId(json['targetRequestId'], r'$.targetRequestId'),
    );
  }
}

final class CockpitWorkerDrainRequest extends CockpitWorkerProtocolRequest {
  CockpitWorkerDrainRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.cancellationGraceMs,
  }) {
    workerInteger(
      cancellationGraceMs,
      r'$.cancellationGraceMs',
      maximum: 300000,
    );
  }

  final int cancellationGraceMs;

  @override
  String get method => 'drain';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'cancellationGraceMs': cancellationGraceMs,
  };

  factory CockpitWorkerDrainRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{'cancellationGraceMs'});
    final metadata = _metadata(json);
    return CockpitWorkerDrainRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      cancellationGraceMs: workerInteger(
        json['cancellationGraceMs'],
        r'$.cancellationGraceMs',
        maximum: 300000,
      ),
    );
  }
}

final class CockpitWorkerHealthRequest extends CockpitWorkerProtocolRequest {
  CockpitWorkerHealthRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
  });

  @override
  String get method => 'health';

  @override
  Map<String, Object?> toJson() => metadataJson();

  factory CockpitWorkerHealthRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{});
    final metadata = _metadata(json);
    return CockpitWorkerHealthRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
    );
  }
}

final class CockpitWorkerShutdownRequest extends CockpitWorkerProtocolRequest {
  CockpitWorkerShutdownRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.force,
  });

  final bool force;

  @override
  String get method => 'shutdown';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'force': force,
  };

  factory CockpitWorkerShutdownRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{'force'});
    final metadata = _metadata(json);
    return CockpitWorkerShutdownRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      force: workerBoolean(json['force'], r'$.force'),
    );
  }
}

final class CockpitWorkerReplayEventsRequest
    extends CockpitWorkerProtocolRequest {
  CockpitWorkerReplayEventsRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.runId,
    required this.afterSequence,
  }) {
    workerId(runId, r'$.runId');
    workerInteger(afterSequence, r'$.afterSequence', minimum: 0);
  }

  final String runId;
  final int afterSequence;

  @override
  String get method => 'replayEvents';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'runId': runId,
    'afterSequence': afterSequence,
  };

  factory CockpitWorkerReplayEventsRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{
      'runId',
      'afterSequence',
    });
    final metadata = _metadata(json);
    return CockpitWorkerReplayEventsRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      runId: workerId(json['runId'], r'$.runId'),
      afterSequence: workerInteger(
        json['afterSequence'],
        r'$.afterSequence',
        minimum: 0,
      ),
    );
  }
}

final class CockpitWorkerPublishEventBatchRequest
    extends CockpitWorkerProtocolRequest {
  CockpitWorkerPublishEventBatchRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.runId,
    required this.afterSequence,
    required Iterable<CockpitRunEvent> events,
  }) : events = List<CockpitRunEvent>.unmodifiable(events) {
    workerId(runId, r'$.runId');
    workerInteger(afterSequence, r'$.afterSequence', minimum: 0);
    if (this.events.isEmpty || this.events.length > 256) {
      throw const FormatException('Event batch size is invalid.');
    }
    CockpitRunEvent.validateSequence(this.events, afterSequence: afterSequence);
    if (this.events.any(
      (event) => event.workspaceId != workspaceId || event.runId != runId,
    )) {
      throw const FormatException('Event batch ownership is inconsistent.');
    }
  }

  final String runId;
  final int afterSequence;
  final List<CockpitRunEvent> events;

  @override
  String get method => 'publishEventBatch';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'runId': runId,
    'afterSequence': afterSequence,
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory CockpitWorkerPublishEventBatchRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{
      'runId',
      'afterSequence',
      'events',
    });
    final rawEvents = workerList(json['events'], r'$.events', maximum: 256);
    final metadata = _metadata(json);
    return CockpitWorkerPublishEventBatchRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      runId: workerId(json['runId'], r'$.runId'),
      afterSequence: workerInteger(
        json['afterSequence'],
        r'$.afterSequence',
        minimum: 0,
      ),
      events: <CockpitRunEvent>[
        for (var index = 0; index < rawEvents.length; index += 1)
          CockpitRunEvent.fromJson(rawEvents[index], path: '\$.events[$index]'),
      ],
    );
  }
}

final class CockpitWorkerPublishArtifactBatchRequest
    extends CockpitWorkerProtocolRequest {
  CockpitWorkerPublishArtifactBatchRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.projectId,
    required this.runId,
    this.caseId,
    required Iterable<CockpitArtifactResource> artifacts,
  }) : artifacts = List<CockpitArtifactResource>.unmodifiable(artifacts) {
    workerId(projectId, r'$.projectId');
    workerId(runId, r'$.runId');
    if (caseId != null) workerId(caseId, r'$.caseId');
    if (this.artifacts.isEmpty || this.artifacts.length > 256) {
      throw const FormatException(
        'Artifact publication batch size is invalid.',
      );
    }
    final ids = <String>{};
    for (final artifact in this.artifacts) {
      if (artifact.workspaceId != workspaceId ||
          artifact.runId != runId ||
          !ids.add(artifact.artifactId)) {
        throw const FormatException(
          'Artifact publication ownership is inconsistent.',
        );
      }
      if ((artifact.attemptId == null) != (caseId == null)) {
        throw const FormatException(
          'Artifact publication case and attempt ownership disagree.',
        );
      }
    }
  }

  final String projectId;
  final String runId;
  final String? caseId;
  final List<CockpitArtifactResource> artifacts;

  @override
  String get method => 'publishArtifactBatch';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'projectId': projectId,
    'runId': runId,
    if (caseId != null) 'caseId': caseId,
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
  };

  factory CockpitWorkerPublishArtifactBatchRequest.fromJson(Object? value) {
    final json = _requestObject(
      value,
      const <String>{'projectId', 'runId', 'caseId', 'artifacts'},
      optional: const <String>{'caseId'},
    );
    final rawArtifacts = workerList(
      json['artifacts'],
      r'$.artifacts',
      maximum: 256,
    );
    final metadata = _metadata(json);
    return CockpitWorkerPublishArtifactBatchRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      projectId: workerId(json['projectId'], r'$.projectId'),
      runId: workerId(json['runId'], r'$.runId'),
      caseId: json['caseId'] == null
          ? null
          : workerId(json['caseId'], r'$.caseId'),
      artifacts: <CockpitArtifactResource>[
        for (var index = 0; index < rawArtifacts.length; index += 1)
          CockpitArtifactResource.fromJson(
            rawArtifacts[index],
            path: '\$.artifacts[$index]',
          ),
      ],
    );
  }
}

final class CockpitWorkerReadSessionArtifactRequest
    extends CockpitWorkerProtocolRequest {
  CockpitWorkerReadSessionArtifactRequest({
    required super.protocolVersion,
    required super.workspaceId,
    required super.requestId,
    required super.deadline,
    required super.idempotencyKey,
    required this.sessionId,
    required this.artifactId,
  }) {
    workerId(sessionId, r'$.sessionId');
    workerId(artifactId, r'$.artifactId');
  }

  final String sessionId;
  final String artifactId;

  @override
  String get method => 'readSessionArtifact';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...metadataJson(),
    'sessionId': sessionId,
    'artifactId': artifactId,
  };

  factory CockpitWorkerReadSessionArtifactRequest.fromJson(Object? value) {
    final json = _requestObject(value, const <String>{
      'sessionId',
      'artifactId',
    });
    final metadata = _metadata(json);
    return CockpitWorkerReadSessionArtifactRequest(
      protocolVersion: metadata.protocolVersion,
      workspaceId: metadata.workspaceId,
      requestId: metadata.requestId,
      deadline: metadata.deadline,
      idempotencyKey: metadata.idempotencyKey,
      sessionId: workerId(json['sessionId'], r'$.sessionId'),
      artifactId: workerId(json['artifactId'], r'$.artifactId'),
    );
  }
}

const Set<String> _metadataKeys = <String>{
  'protocolVersion',
  'workspaceId',
  'requestId',
  'deadline',
  'idempotencyKey',
};

Map<String, Object?> _requestObject(
  Object? value,
  Set<String> methodKeys, {
  Set<String> optional = const <String>{},
}) {
  final json = workerObject(value, r'$');
  final keys = <String>{..._metadataKeys, ...methodKeys};
  if (!methodKeys.containsAll(optional)) {
    throw StateError('Optional worker request keys are not method keys.');
  }
  workerKeys(
    json,
    keys,
    r'$',
    required: <String>{
      ..._metadataKeys,
      ...methodKeys.where((key) => !optional.contains(key)),
    },
  );
  return json;
}

({
  String protocolVersion,
  String workspaceId,
  String requestId,
  DateTime deadline,
  String idempotencyKey,
})
_metadata(Map<String, Object?> json) => (
  protocolVersion: workerString(
    json['protocolVersion'],
    r'$.protocolVersion',
    maximum: 64,
  ),
  workspaceId: workerId(json['workspaceId'], r'$.workspaceId'),
  requestId: workerId(json['requestId'], r'$.requestId'),
  deadline: workerUtcDateTime(json['deadline'], r'$.deadline'),
  idempotencyKey: workerId(json['idempotencyKey'], r'$.idempotencyKey'),
);

List<String> _ids(Object? value, String path) {
  final list = workerList(value, path, maximum: 256);
  final result = <String>[
    for (var index = 0; index < list.length; index += 1)
      workerId(list[index], '$path[$index]'),
  ];
  _uniqueIds(result, path);
  return result;
}

void _uniqueIds(Iterable<String> values, String path) {
  final seen = <String>{};
  for (final value in values) {
    workerId(value, '$path[]');
    if (!seen.add(value)) {
      throw FormatException('Duplicate identifier at $path.');
    }
  }
}
