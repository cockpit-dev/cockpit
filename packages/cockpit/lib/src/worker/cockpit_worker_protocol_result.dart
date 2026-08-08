import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_worker_value_reader.dart';

sealed class CockpitWorkerProtocolResult {
  const CockpitWorkerProtocolResult();

  String get method;

  Map<String, Object?> toJson();

  static CockpitWorkerProtocolResult fromJson(String method, Object? value) {
    workerMethod(method, r'$.method');
    return switch (method) {
      'initialize' => CockpitWorkerInitializeResult.fromJson(value),
      'capabilities' => CockpitWorkerCapabilitiesResult.fromJson(value),
      'operation' => CockpitWorkerOperationResult.fromJson(value),
      'cancel' => CockpitWorkerCancelResult.fromJson(value),
      'drain' => CockpitWorkerDrainResult.fromJson(value),
      'health' => CockpitWorkerHealthResult.fromJson(value),
      'shutdown' => CockpitWorkerShutdownResult.fromJson(value),
      'replayEvents' => CockpitWorkerReplayEventsResult.fromJson(value),
      'publishEventBatch' => CockpitWorkerPublishEventBatchResult.fromJson(
        value,
      ),
      'publishArtifactBatch' =>
        CockpitWorkerPublishArtifactBatchResult.fromJson(value),
      'readSessionArtifact' => CockpitWorkerReadSessionArtifactResult.fromJson(
        value,
      ),
      _ => throw const FormatException('Unsupported worker method.'),
    };
  }
}

final class CockpitWorkerInitializeResult extends CockpitWorkerProtocolResult {
  CockpitWorkerInitializeResult({
    required this.protocolVersion,
    required this.workspaceId,
    required this.engineVersion,
    required Iterable<String> negotiatedFeatures,
  }) : negotiatedFeatures = List<String>.unmodifiable(negotiatedFeatures) {
    if (protocolVersion != cockpitWorkerProtocolVersion) {
      throw const FormatException('Incompatible worker protocol version.');
    }
    workerId(workspaceId, r'$.workspaceId');
    workerId(engineVersion, r'$.engineVersion');
    _validateIds(this.negotiatedFeatures, r'$.negotiatedFeatures');
  }

  final String protocolVersion;
  final String workspaceId;
  final String engineVersion;
  final List<String> negotiatedFeatures;

  @override
  String get method => 'initialize';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': protocolVersion,
    'workspaceId': workspaceId,
    'engineVersion': engineVersion,
    'negotiatedFeatures': negotiatedFeatures,
  };

  factory CockpitWorkerInitializeResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'protocolVersion',
      'workspaceId',
      'engineVersion',
      'negotiatedFeatures',
    });
    return CockpitWorkerInitializeResult(
      protocolVersion: workerString(
        json['protocolVersion'],
        r'$.protocolVersion',
        maximum: 64,
      ),
      workspaceId: workerId(json['workspaceId'], r'$.workspaceId'),
      engineVersion: workerId(json['engineVersion'], r'$.engineVersion'),
      negotiatedFeatures: _ids(
        json['negotiatedFeatures'],
        r'$.negotiatedFeatures',
      ),
    );
  }
}

final class CockpitWorkerCapabilitiesResult
    extends CockpitWorkerProtocolResult {
  CockpitWorkerCapabilitiesResult({
    required this.workspaceId,
    required Iterable<String> operationKinds,
    required Iterable<String> resourceKinds,
    required Iterable<String> features,
  }) : operationKinds = List<String>.unmodifiable(operationKinds),
       resourceKinds = List<String>.unmodifiable(resourceKinds),
       features = List<String>.unmodifiable(features) {
    workerId(workspaceId, r'$.workspaceId');
    _validateKinds(this.operationKinds, r'$.operationKinds');
    _validateKinds(this.resourceKinds, r'$.resourceKinds');
    _validateIds(this.features, r'$.features');
  }

  final String workspaceId;
  final List<String> operationKinds;
  final List<String> resourceKinds;
  final List<String> features;

  @override
  String get method => 'capabilities';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'operationKinds': operationKinds,
    'resourceKinds': resourceKinds,
    'features': features,
  };

  factory CockpitWorkerCapabilitiesResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'workspaceId',
      'operationKinds',
      'resourceKinds',
      'features',
    });
    return CockpitWorkerCapabilitiesResult(
      workspaceId: workerId(json['workspaceId'], r'$.workspaceId'),
      operationKinds: _kinds(json['operationKinds'], r'$.operationKinds'),
      resourceKinds: _kinds(json['resourceKinds'], r'$.resourceKinds'),
      features: _ids(json['features'], r'$.features'),
    );
  }
}

final class CockpitWorkerOperationResult extends CockpitWorkerProtocolResult {
  const CockpitWorkerOperationResult(this.result);

  final CockpitOperationResult result;

  @override
  String get method => 'operation';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'operation': result.toJson(),
  };

  factory CockpitWorkerOperationResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{'operation'});
    return CockpitWorkerOperationResult(
      CockpitOperationResult.fromJson(json['operation']),
    );
  }
}

final class CockpitWorkerCancelResult extends CockpitWorkerProtocolResult {
  CockpitWorkerCancelResult({
    required this.targetRequestId,
    required this.cancelled,
    required this.alreadyTerminal,
  }) {
    workerId(targetRequestId, r'$.targetRequestId');
    if (cancelled && alreadyTerminal) {
      throw const FormatException('Cancel result is inconsistent.');
    }
  }

  final String targetRequestId;
  final bool cancelled;
  final bool alreadyTerminal;

  @override
  String get method => 'cancel';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'targetRequestId': targetRequestId,
    'cancelled': cancelled,
    'alreadyTerminal': alreadyTerminal,
  };

  factory CockpitWorkerCancelResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'targetRequestId',
      'cancelled',
      'alreadyTerminal',
    });
    return CockpitWorkerCancelResult(
      targetRequestId: workerId(json['targetRequestId'], r'$.targetRequestId'),
      cancelled: workerBoolean(json['cancelled'], r'$.cancelled'),
      alreadyTerminal: workerBoolean(
        json['alreadyTerminal'],
        r'$.alreadyTerminal',
      ),
    );
  }
}

final class CockpitWorkerDrainResult extends CockpitWorkerProtocolResult {
  CockpitWorkerDrainResult({
    required this.draining,
    required this.activeRequestCount,
  }) {
    workerInteger(activeRequestCount, r'$.activeRequestCount', maximum: 10000);
    if (!draining) throw const FormatException('Drain result is inconsistent.');
  }

  final bool draining;
  final int activeRequestCount;

  @override
  String get method => 'drain';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'draining': draining,
    'activeRequestCount': activeRequestCount,
  };

  factory CockpitWorkerDrainResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'draining',
      'activeRequestCount',
    });
    return CockpitWorkerDrainResult(
      draining: workerBoolean(json['draining'], r'$.draining'),
      activeRequestCount: workerInteger(
        json['activeRequestCount'],
        r'$.activeRequestCount',
        maximum: 10000,
      ),
    );
  }
}

final class CockpitWorkerHealthResult extends CockpitWorkerProtocolResult {
  CockpitWorkerHealthResult({
    required this.workspaceId,
    required this.healthy,
    required this.draining,
    required this.activeRequestCount,
    required this.checkedAt,
  }) {
    workerId(workspaceId, r'$.workspaceId');
    workerInteger(activeRequestCount, r'$.activeRequestCount', maximum: 10000);
    workerUtcDateTimeValue(checkedAt, r'$.checkedAt');
  }

  final String workspaceId;
  final bool healthy;
  final bool draining;
  final int activeRequestCount;
  final DateTime checkedAt;

  @override
  String get method => 'health';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'healthy': healthy,
    'draining': draining,
    'activeRequestCount': activeRequestCount,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
  };

  factory CockpitWorkerHealthResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'workspaceId',
      'healthy',
      'draining',
      'activeRequestCount',
      'checkedAt',
    });
    return CockpitWorkerHealthResult(
      workspaceId: workerId(json['workspaceId'], r'$.workspaceId'),
      healthy: workerBoolean(json['healthy'], r'$.healthy'),
      draining: workerBoolean(json['draining'], r'$.draining'),
      activeRequestCount: workerInteger(
        json['activeRequestCount'],
        r'$.activeRequestCount',
        maximum: 10000,
      ),
      checkedAt: workerUtcDateTime(json['checkedAt'], r'$.checkedAt'),
    );
  }
}

final class CockpitWorkerShutdownResult extends CockpitWorkerProtocolResult {
  const CockpitWorkerShutdownResult({required this.accepted});

  final bool accepted;

  @override
  String get method => 'shutdown';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'accepted': accepted};

  factory CockpitWorkerShutdownResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{'accepted'});
    return CockpitWorkerShutdownResult(
      accepted: workerBoolean(json['accepted'], r'$.accepted'),
    );
  }
}

final class CockpitWorkerReplayEventsResult
    extends CockpitWorkerProtocolResult {
  CockpitWorkerReplayEventsResult({
    required this.runId,
    required this.afterSequence,
    required Iterable<CockpitRunEvent> events,
  }) : events = List<CockpitRunEvent>.unmodifiable(events) {
    workerId(runId, r'$.runId');
    workerInteger(afterSequence, r'$.afterSequence', minimum: 0);
    if (this.events.length > 256) {
      throw const FormatException('Replay event batch is too large.');
    }
    CockpitRunEvent.validateSequence(this.events, afterSequence: afterSequence);
    if (this.events.any((event) => event.runId != runId)) {
      throw const FormatException('Replay event ownership is inconsistent.');
    }
  }

  final String runId;
  final int afterSequence;
  final List<CockpitRunEvent> events;

  @override
  String get method => 'replayEvents';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'afterSequence': afterSequence,
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory CockpitWorkerReplayEventsResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'runId',
      'afterSequence',
      'events',
    });
    final rawEvents = workerList(json['events'], r'$.events', maximum: 256);
    return CockpitWorkerReplayEventsResult(
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

final class CockpitWorkerPublishEventBatchResult
    extends CockpitWorkerProtocolResult {
  CockpitWorkerPublishEventBatchResult({
    required this.runId,
    required this.highestContiguousSequence,
    required this.terminal,
    this.replayAfterSequence,
  }) {
    workerId(runId, r'$.runId');
    workerInteger(
      highestContiguousSequence,
      r'$.highestContiguousSequence',
      minimum: 0,
    );
    if (replayAfterSequence != null) {
      workerInteger(replayAfterSequence, r'$.replayAfterSequence', minimum: 0);
      if (replayAfterSequence != highestContiguousSequence) {
        throw const FormatException('Event replay cursor is inconsistent.');
      }
    }
  }

  final String runId;
  final int highestContiguousSequence;
  final bool terminal;
  final int? replayAfterSequence;

  bool get hasGap => replayAfterSequence != null;

  @override
  String get method => 'publishEventBatch';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'highestContiguousSequence': highestContiguousSequence,
    'terminal': terminal,
    if (replayAfterSequence != null) 'replayAfterSequence': replayAfterSequence,
  };

  factory CockpitWorkerPublishEventBatchResult.fromJson(Object? value) {
    final json = workerObject(value, r'$');
    workerKeys(
      json,
      const <String>{
        'runId',
        'highestContiguousSequence',
        'terminal',
        'replayAfterSequence',
      },
      r'$',
      required: const <String>{
        'runId',
        'highestContiguousSequence',
        'terminal',
      },
    );
    return CockpitWorkerPublishEventBatchResult(
      runId: workerId(json['runId'], r'$.runId'),
      highestContiguousSequence: workerInteger(
        json['highestContiguousSequence'],
        r'$.highestContiguousSequence',
        minimum: 0,
      ),
      terminal: workerBoolean(json['terminal'], r'$.terminal'),
      replayAfterSequence: json['replayAfterSequence'] == null
          ? null
          : workerInteger(
              json['replayAfterSequence'],
              r'$.replayAfterSequence',
              minimum: 0,
            ),
    );
  }
}

final class CockpitWorkerPublishArtifactBatchResult
    extends CockpitWorkerProtocolResult {
  CockpitWorkerPublishArtifactBatchResult({
    required this.runId,
    required Iterable<String> artifactIds,
  }) : artifactIds = List<String>.unmodifiable(artifactIds) {
    workerId(runId, r'$.runId');
    if (this.artifactIds.isEmpty || this.artifactIds.length > 256) {
      throw const FormatException('Published artifact result size is invalid.');
    }
    _validateIds(this.artifactIds, r'$.artifactIds');
  }

  final String runId;
  final List<String> artifactIds;

  @override
  String get method => 'publishArtifactBatch';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'artifactIds': artifactIds,
  };

  factory CockpitWorkerPublishArtifactBatchResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{'runId', 'artifactIds'});
    return CockpitWorkerPublishArtifactBatchResult(
      runId: workerId(json['runId'], r'$.runId'),
      artifactIds: _ids(json['artifactIds'], r'$.artifactIds'),
    );
  }
}

final class CockpitWorkerReadSessionArtifactResult
    extends CockpitWorkerProtocolResult {
  CockpitWorkerReadSessionArtifactResult({
    required this.sessionId,
    required this.artifactId,
    required this.kind,
    required this.name,
    required this.mediaType,
    required this.retainedPath,
    required this.sizeBytes,
    required this.sha256,
  }) {
    workerId(sessionId, r'$.sessionId');
    workerId(artifactId, r'$.artifactId');
    workerId(kind, r'$.kind');
    workerString(name, r'$.name', maximum: 512);
    workerString(mediaType, r'$.mediaType', maximum: 128);
    workerString(retainedPath, r'$.retainedPath', maximum: 32768);
    if (sizeBytes < 1 ||
        sizeBytes > 16 * 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Session artifact metadata is invalid.');
    }
  }

  final String sessionId;
  final String artifactId;
  final String kind;
  final String name;
  final String mediaType;
  final String retainedPath;
  final int sizeBytes;
  final String sha256;

  @override
  String get method => 'readSessionArtifact';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'artifactId': artifactId,
    'kind': kind,
    'name': name,
    'mediaType': mediaType,
    'retainedPath': retainedPath,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };

  factory CockpitWorkerReadSessionArtifactResult.fromJson(Object? value) {
    final json = _resultObject(value, const <String>{
      'sessionId',
      'artifactId',
      'kind',
      'name',
      'mediaType',
      'retainedPath',
      'sizeBytes',
      'sha256',
    });
    return CockpitWorkerReadSessionArtifactResult(
      sessionId: workerId(json['sessionId'], r'$.sessionId'),
      artifactId: workerId(json['artifactId'], r'$.artifactId'),
      kind: workerId(json['kind'], r'$.kind'),
      name: workerString(json['name'], r'$.name', maximum: 512),
      mediaType: workerString(json['mediaType'], r'$.mediaType', maximum: 128),
      retainedPath: workerString(
        json['retainedPath'],
        r'$.retainedPath',
        maximum: 32768,
      ),
      sizeBytes: workerInteger(
        json['sizeBytes'],
        r'$.sizeBytes',
        minimum: 1,
        maximum: 16 * 1024 * 1024 * 1024,
      ),
      sha256: workerString(json['sha256'], r'$.sha256', maximum: 64),
    );
  }
}

Map<String, Object?> _resultObject(Object? value, Set<String> keys) {
  final json = workerObject(value, r'$');
  workerKeys(json, keys, r'$', required: keys);
  return json;
}

List<String> _ids(Object? value, String path) {
  final list = workerList(value, path, maximum: 256);
  final values = <String>[
    for (var index = 0; index < list.length; index += 1)
      workerId(list[index], '$path[$index]'),
  ];
  _validateIds(values, path);
  return values;
}

List<String> _kinds(Object? value, String path) {
  final list = workerList(value, path, maximum: 256);
  final values = <String>[
    for (var index = 0; index < list.length; index += 1)
      workerKind(list[index], '$path[$index]'),
  ];
  _validateKinds(values, path);
  return values;
}

void _validateIds(Iterable<String> values, String path) =>
    _validateUnique(values, path, workerId);

void _validateKinds(Iterable<String> values, String path) =>
    _validateUnique(values, path, workerKind);

void _validateUnique(
  Iterable<String> values,
  String path,
  String Function(Object?, String) validator,
) {
  final seen = <String>{};
  for (final value in values) {
    validator(value, '$path[]');
    if (!seen.add(value)) {
      throw FormatException('Duplicate value at $path.');
    }
  }
}
