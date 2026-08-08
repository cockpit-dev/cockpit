import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import 'cockpit_worker_case_completion.dart';
import 'cockpit_worker_case_run_store.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_protocol_request.dart';
import 'cockpit_worker_protocol_result.dart';
import 'cockpit_worker_server.dart';
import 'cockpit_worker_value_reader.dart';

typedef CockpitWorkerEventRedactor = Object? Function(Object? value);

final class CockpitWorkerEventDraft {
  const CockpitWorkerEventDraft({
    required this.kind,
    required this.entityKind,
    this.caseId,
    this.attemptId,
    this.stepExecutionId,
    this.stepStatus,
    this.lifecycle,
    this.outcome,
    this.stability,
    this.sourceLocation,
    this.targetId,
    this.requestedPlane,
    this.actualPlane,
    this.driverId,
    this.degradation,
    this.locatorSummary = const <String, Object?>{},
    this.failure,
    this.artifacts = const <CockpitArtifactReference>[],
  });

  final String kind;
  final CockpitRunEventEntityKind entityKind;
  final String? caseId;
  final String? attemptId;
  final String? stepExecutionId;
  final CockpitTestStepStatus? stepStatus;
  final CockpitRunLifecycle? lifecycle;
  final CockpitRunOutcome? outcome;
  final CockpitRunStability? stability;
  final CockpitTestSourceLocation? sourceLocation;
  final String? targetId;
  final CockpitTestPlane? requestedPlane;
  final CockpitTestPlane? actualPlane;
  final String? driverId;
  final String? degradation;
  final Map<String, Object?> locatorSummary;
  final CockpitFailure? failure;
  final List<CockpitArtifactReference> artifacts;
}

abstract interface class CockpitWorkerEventPublisher {
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  );
}

final class CockpitRpcWorkerEventPublisher
    implements CockpitWorkerEventPublisher {
  CockpitRpcWorkerEventPublisher({
    required this.workspaceId,
    required CockpitJsonRpcPeer peer,
    DateTime Function()? utcNow,
  }) : _peer = peer,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
  }

  final String workspaceId;
  final CockpitJsonRpcPeer _peer;
  final DateTime Function() _utcNow;
  var _sequence = 0;

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    if (request.workspaceId != workspaceId) {
      throw const FormatException(
        'Published events cross workspace authority.',
      );
    }
    final raw = await _peer.call(
      method: request.method,
      params: <String, Object?>{
        'protocolVersion': cockpitWorkerProtocolVersion,
        'workspaceId': workspaceId,
        'idempotencyKey':
            'event-${request.runId}-${request.afterSequence}-${++_sequence}',
        'runId': request.runId,
        'afterSequence': request.afterSequence,
        'events': request.events.map((event) => event.toJson()).toList(),
      },
      deadline: _utcNow().add(const Duration(seconds: 10)),
    );
    return CockpitWorkerPublishEventBatchResult.fromJson(raw);
  }
}

final class CockpitWorkerRunEventStore implements CockpitWorkerEventExchange {
  CockpitWorkerRunEventStore({
    required this.projectId,
    required this.workspaceId,
    required String stateRoot,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    required CockpitWorkerEventRedactor redactor,
    CockpitWorkerEventPublisher? publisher,
    CockpitTokenGenerator? tokenGenerator,
    DateTime Function()? utcNow,
    CockpitWorkerCaseCompletionObserver? completionObserver,
    this.maximumEventsPerRun = 100000,
    this.maximumLogBytes = 64 * 1024 * 1024,
  }) : stateRoot = p.normalize(stateRoot),
       _permissionHardener = permissionHardener,
       _directorySyncer = directorySyncer,
       _redactor = redactor,
       _publisher = publisher,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _completionObserver = completionObserver {
    workerId(projectId, r'$.projectId');
    workerId(workspaceId, r'$.workspaceId');
    if (!p.isAbsolute(stateRoot) || p.normalize(stateRoot) != stateRoot) {
      throw const FormatException('Worker event state root is invalid.');
    }
    if (maximumEventsPerRun < 256 ||
        maximumEventsPerRun > 1000000 ||
        maximumLogBytes < 1024 * 1024 ||
        maximumLogBytes > 1024 * 1024 * 1024) {
      throw ArgumentError('Worker event store bounds are invalid.');
    }
  }

  final String projectId;
  final String workspaceId;
  final String stateRoot;
  final int maximumEventsPerRun;
  final int maximumLogBytes;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final CockpitWorkerEventRedactor _redactor;
  final CockpitWorkerEventPublisher? _publisher;
  final CockpitTokenGenerator _tokenGenerator;
  final DateTime Function() _utcNow;
  final CockpitWorkerCaseCompletionObserver? _completionObserver;
  final Map<String, List<CockpitRunEvent>> _events =
      <String, List<CockpitRunEvent>>{};
  final Set<String> _eventIds = <String>{};
  final Map<String, int> _acknowledged = <String, int>{};
  final Set<String> _probedSupervisorCursors = <String>{};
  final Map<String, Future<void>> _runLocks = <String, Future<void>>{};
  var _initialized = false;
  Future<void>? _initialization;

  Future<void> initialize() async {
    if (_initialized) return;
    final active = _initialization;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _initialize().whenComplete(() {
      if (identical(_initialization, operation)) _initialization = null;
    });
    _initialization = operation;
    return operation;
  }

  Future<List<CockpitRunEvent>> eventsForRun(String runId) async {
    workerId(runId, r'$.runId');
    await initialize();
    return List<CockpitRunEvent>.unmodifiable(
      _events[runId] ?? const <CockpitRunEvent>[],
    );
  }

  Future<void> _initialize() async {
    await _validateStateRoot();
    final runsRoot = Directory(p.join(stateRoot, 'runs'));
    await runsRoot.create(recursive: true);
    await _permissionHardener.hardenDirectory(runsRoot);
    await _directorySyncer.sync(runsRoot.parent.path);
    await for (final entity in runsRoot.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Worker run root contains an invalid entry.',
          entity.path,
        );
      }
      final runId = p.basename(entity.path);
      workerId(runId, r'$.runId');
      await _validateCanonicalDirectory(entity.path, runsRoot.path);
      final eventPath = p.join(entity.path, 'events.ndjson');
      if (await FileSystemEntity.type(eventPath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      _events[runId] = await _readAndRepair(runId, eventPath);
      _acknowledged[runId] = await _readAcknowledgement(runId);
    }
    _initialized = true;
  }

  Future<CockpitRunEvent> append(
    String runId,
    CockpitWorkerEventDraft draft, {
    bool publishImmediately = true,
  }) async {
    await initialize();
    return _locked(
      runId,
      () => _appendInitialized(
        runId,
        draft,
        publishImmediately: publishImmediately,
      ),
    );
  }

  Future<List<CockpitRunEvent>> appendBatch(
    String runId,
    List<CockpitWorkerEventDraft> drafts, {
    bool publishImmediately = true,
  }) async {
    await initialize();
    return _locked(
      runId,
      () => _appendBatchInitialized(
        runId,
        drafts,
        publishImmediately: publishImmediately,
      ),
    );
  }

  Future<CockpitRunEvent> _appendInitialized(
    String runId,
    CockpitWorkerEventDraft draft, {
    required bool publishImmediately,
  }) async {
    if (!_initialized) {
      throw StateError('Worker event store is not initialized.');
    }
    workerId(runId, r'$.runId');
    final events = _events.putIfAbsent(runId, () => <CockpitRunEvent>[]);
    final safeEvent = _buildEvent(runId, draft, events.length + 1);
    await _appendExactInitialized(safeEvent);
    if (publishImmediately) await _publishPending(runId);
    return safeEvent;
  }

  Future<List<CockpitRunEvent>> _appendBatchInitialized(
    String runId,
    List<CockpitWorkerEventDraft> drafts, {
    required bool publishImmediately,
  }) async {
    if (!_initialized) {
      throw StateError('Worker event store is not initialized.');
    }
    workerId(runId, r'$.runId');
    if (drafts.isEmpty) return const <CockpitRunEvent>[];
    final current = _events.putIfAbsent(runId, () => <CockpitRunEvent>[]);
    final exact = <CockpitRunEvent>[
      for (var index = 0; index < drafts.length; index += 1)
        _buildEvent(runId, drafts[index], current.length + index + 1),
    ];
    await _preflightExactEvents(runId, exact);
    await _appendExactBatchInitialized(exact);
    if (publishImmediately) await _publishPending(runId);
    return List<CockpitRunEvent>.unmodifiable(exact);
  }

  CockpitRunEvent _buildEvent(
    String runId,
    CockpitWorkerEventDraft draft,
    int sequence,
  ) {
    final event = CockpitRunEvent(
      eventId: 'ev-${_tokenGenerator.nextResourceIdToken()}',
      sequence: sequence,
      timestamp: _utcNow().toUtc(),
      kind: draft.kind,
      entityKind: draft.entityKind,
      projectId: projectId,
      workspaceId: workspaceId,
      runId: runId,
      caseId: draft.caseId,
      attemptId: draft.attemptId,
      stepExecutionId: draft.stepExecutionId,
      stepStatus: draft.stepStatus,
      lifecycle: draft.lifecycle,
      outcome: draft.outcome,
      stability: draft.stability,
      sourceLocation: draft.sourceLocation,
      targetId: draft.targetId,
      requestedPlane: draft.requestedPlane,
      actualPlane: draft.actualPlane,
      driverId: draft.driverId,
      degradation: draft.degradation,
      locatorSummary: draft.locatorSummary,
      failure: draft.failure,
      artifacts: draft.artifacts,
    );
    return _redactedEvent(event);
  }

  Future<void> _appendExactInitialized(CockpitRunEvent event) async {
    await _preflightExactEvents(event.runId, <CockpitRunEvent>[event]);
    await _appendExactBatchInitialized(<CockpitRunEvent>[event]);
  }

  Future<CockpitWorkerCaseCompletionIntent> appendCompletionBatch({
    required String runId,
    required List<CockpitWorkerEventDraft> drafts,
    required Future<CockpitWorkerCaseCompletionIntent> Function(
      List<CockpitRunEvent> events,
    )
    persistIntent,
  }) async {
    await initialize();
    return _locked(runId, () async {
      if (drafts.isEmpty) {
        throw const FormatException('Case completion event batch is empty.');
      }
      final current = _events.putIfAbsent(runId, () => <CockpitRunEvent>[]);
      final exact = <CockpitRunEvent>[];
      final generatedIds = <String>{};
      for (var index = 0; index < drafts.length; index += 1) {
        final event = _buildEvent(
          runId,
          drafts[index],
          current.length + index + 1,
        );
        if (_eventIds.contains(event.eventId) ||
            !generatedIds.add(event.eventId)) {
          throw const FormatException(
            'Worker generated a duplicate completion event id.',
          );
        }
        exact.add(event);
      }
      await _preflightExactEvents(runId, exact);
      final intent = await persistIntent(
        List<CockpitRunEvent>.unmodifiable(exact),
      );
      _requireIntentEvents(intent, exact);
      await _reconcileExactEventsInitialized(runId, exact);
      await _observeCompletion(intent, recovering: false);
      return intent;
    });
  }

  Future<void> reconcileCompletionIntent(
    CockpitWorkerCaseCompletionIntent intent,
  ) async {
    await initialize();
    await _locked(intent.runId, () async {
      _requireIntentEvents(intent, intent.events);
      await _reconcileExactEventsInitialized(intent.runId, intent.events);
      await _observeCompletion(intent, recovering: true);
    });
  }

  Future<void> publishRun(String runId) async {
    await initialize();
    await _locked(runId, () => _publishPending(runId));
  }

  Future<void> _reconcileExactEventsInitialized(
    String runId,
    List<CockpitRunEvent> exact,
  ) async {
    final current = _events.putIfAbsent(runId, () => <CockpitRunEvent>[]);
    if (exact.isEmpty ||
        exact.first.sequence > current.length + 1 ||
        current.length > exact.last.sequence) {
      throw const FormatException(
        'Case completion event batch does not meet worker truth.',
      );
    }
    CockpitRunEvent.validateSequence(
      exact,
      afterSequence: exact.first.sequence - 1,
    );
    for (final event in exact) {
      if (event.runId != runId ||
          event.projectId != projectId ||
          event.workspaceId != workspaceId) {
        throw const FormatException(
          'Case completion events cross worker authority.',
        );
      }
      if (event.sequence <= current.length &&
          _canonicalEvent(current[event.sequence - 1]) !=
              _canonicalEvent(event)) {
        throw const FormatException(
          'Case completion event conflicts with worker truth.',
        );
      }
    }
    final missing = exact
        .where((event) => event.sequence > current.length)
        .toList(growable: false);
    await _preflightExactEvents(runId, missing);
    await _appendExactBatchInitialized(missing);
  }

  Future<void> _appendExactBatchInitialized(List<CockpitRunEvent> exact) async {
    if (exact.isEmpty) return;
    final runId = exact.first.runId;
    final events = _events.putIfAbsent(runId, () => <CockpitRunEvent>[]);
    final generatedIds = <String>{};
    for (var index = 0; index < exact.length; index += 1) {
      final event = exact[index];
      if (event.runId != runId || event.sequence != events.length + index + 1) {
        throw const FormatException(
          'Worker exact event batch sequence has a gap.',
        );
      }
      if (_eventIds.contains(event.eventId) ||
          !generatedIds.add(event.eventId)) {
        throw const FormatException('Worker generated a duplicate event id.');
      }
    }
    await _appendDurablyBatch(exact);
    for (final event in exact) {
      _eventIds.add(event.eventId);
      events.add(event);
    }
  }

  Future<void> _preflightExactEvents(
    String runId,
    List<CockpitRunEvent> events,
  ) async {
    if (events.isEmpty) return;
    final current = _events[runId] ?? const <CockpitRunEvent>[];
    if (current.length + events.length > maximumEventsPerRun) {
      throw const FormatException('Worker event count bound was exceeded.');
    }
    final existingIds = <String>{};
    var additionalBytes = 0;
    for (final event in events) {
      if ((_eventIds.contains(event.eventId) &&
              event.sequence > current.length) ||
          !existingIds.add(event.eventId)) {
        throw const FormatException('Completion event id is not unique.');
      }
      additionalBytes += utf8.encode('${jsonEncode(event.toJson())}\n').length;
    }
    final directory = await _prepareRunDirectory(runId);
    final file = File(p.join(directory.path, 'events.ndjson'));
    final existingLength = await file.exists() ? await file.length() : 0;
    if (existingLength + additionalBytes > maximumLogBytes) {
      throw const FormatException('Worker event log byte bound was exceeded.');
    }
  }

  void _requireIntentEvents(
    CockpitWorkerCaseCompletionIntent intent,
    List<CockpitRunEvent> events,
  ) {
    if (intent.runId != events.first.runId ||
        intent.caseId != events.first.caseId ||
        intent.attemptId != events.first.attemptId ||
        intent.events.length != events.length) {
      throw const FormatException(
        'Case completion intent identity is inconsistent.',
      );
    }
    for (var index = 0; index < events.length; index += 1) {
      if (_canonicalEvent(intent.events[index]) !=
          _canonicalEvent(events[index])) {
        throw const FormatException(
          'Case completion intent changed its exact event batch.',
        );
      }
    }
  }

  Future<void> _observeCompletion(
    CockpitWorkerCaseCompletionIntent intent, {
    required bool recovering,
  }) => notifyCockpitWorkerCaseCompletion(
    _completionObserver,
    CockpitWorkerCaseCompletionObservation(
      phase: CockpitWorkerCaseCompletionPhase.eventsReconciled,
      idempotencyKey: intent.idempotencyKey,
      runId: intent.runId,
      caseId: intent.caseId,
      attemptId: intent.attemptId,
      intentId: intent.intentId,
      recovering: recovering,
    ),
  );

  Future<void> resume() async {
    await initialize();
    for (final runId in _events.keys.toList(growable: false)..sort()) {
      await _locked(runId, () => _publishPending(runId));
    }
  }

  Future<bool> containsArtifact(String runId, String artifactId) async {
    await initialize();
    workerId(runId, r'$.runId');
    workerId(artifactId, r'$.artifactId');
    return (_events[runId] ?? const <CockpitRunEvent>[]).any(
      (event) =>
          event.artifacts.any((artifact) => artifact.artifactId == artifactId),
    );
  }

  Future<void> recoverInterruptedAttempt({
    required String runId,
    required String caseId,
    required String attemptId,
  }) async {
    await initialize();
    final events = _events[runId] ?? const <CockpitRunEvent>[];
    final terminal = events.any(
      (event) =>
          event.entityKind == CockpitRunEventEntityKind.run &&
          event.lifecycle == CockpitRunLifecycle.completed,
    );
    if (terminal) return;
    final failure = _interruptedFailure();
    final attemptTerminal = events.any(
      (event) =>
          event.attemptId == attemptId &&
          event.entityKind == CockpitRunEventEntityKind.attempt &&
          event.outcome != null,
    );
    if (!attemptTerminal) {
      await append(
        runId,
        CockpitWorkerEventDraft(
          kind: 'recovery.attempt.interrupted',
          entityKind: CockpitRunEventEntityKind.attempt,
          caseId: caseId,
          attemptId: attemptId,
          outcome: CockpitRunOutcome.interrupted,
          failure: failure,
        ),
        publishImmediately: false,
      );
    }
    await append(
      runId,
      CockpitWorkerEventDraft(
        kind: 'recovery.run.interrupted',
        entityKind: CockpitRunEventEntityKind.run,
        lifecycle: CockpitRunLifecycle.completed,
        outcome: CockpitRunOutcome.interrupted,
        stability: CockpitRunStability.unknown,
        failure: failure,
      ),
      publishImmediately: false,
    );
  }

  @override
  Future<CockpitWorkerReplayEventsResult> replay(
    CockpitWorkerReplayEventsRequest request,
  ) async {
    if (request.workspaceId != workspaceId) {
      throw const FormatException('Event replay crosses workspace authority.');
    }
    await initialize();
    final events = _events[request.runId] ?? const <CockpitRunEvent>[];
    if (request.afterSequence > events.length) {
      throw const FormatException('Event replay cursor exceeds worker truth.');
    }
    final end = (request.afterSequence + 256).clamp(0, events.length);
    return CockpitWorkerReplayEventsResult(
      runId: request.runId,
      afterSequence: request.afterSequence,
      events: events.sublist(request.afterSequence, end),
    );
  }

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    if (request.workspaceId != workspaceId) {
      throw const FormatException(
        'Event publication crosses workspace authority.',
      );
    }
    await initialize();
    final known = _events[request.runId] ?? const <CockpitRunEvent>[];
    for (final event in request.events) {
      if (event.sequence > known.length) {
        return CockpitWorkerPublishEventBatchResult(
          runId: request.runId,
          highestContiguousSequence: known.length,
          replayAfterSequence: known.length,
        );
      }
      if (jsonEncode(known[event.sequence - 1].toJson()) !=
          jsonEncode(event.toJson())) {
        throw const FormatException(
          'Published event conflicts with worker truth.',
        );
      }
    }
    return CockpitWorkerPublishEventBatchResult(
      runId: request.runId,
      highestContiguousSequence: known.length,
    );
  }

  Future<void> _publishPending(String runId) async {
    final publisher = _publisher;
    if (publisher == null) return;
    final events = _events[runId] ?? const <CockpitRunEvent>[];
    var cursor = _probedSupervisorCursors.contains(runId)
        ? _acknowledged[runId] ?? 0
        : 0;
    while (cursor < events.length) {
      final end = (cursor + 256).clamp(0, events.length);
      final request = CockpitWorkerPublishEventBatchRequest(
        protocolVersion: cockpitWorkerProtocolVersion,
        workspaceId: workspaceId,
        requestId: 'ep-${_tokenGenerator.nextResourceIdToken()}',
        deadline: _utcNow().add(const Duration(seconds: 10)),
        idempotencyKey: 'event_${runId}_$cursor',
        runId: runId,
        afterSequence: cursor,
        events: events.sublist(cursor, end),
      );
      final result = await publisher.publish(request);
      if (result.runId != runId || result.highestContiguousSequence < cursor) {
        throw const FormatException(
          'Supervisor event acknowledgement is invalid.',
        );
      }
      if (result.hasGap) {
        throw const FormatException(
          'Supervisor returned an unresolved event publication gap.',
        );
      }
      final next = result.highestContiguousSequence > events.length
          ? events.length
          : result.highestContiguousSequence;
      if (next == cursor && cursor != events.length) {
        throw const FormatException(
          'Supervisor event replay cursor made no progress.',
        );
      }
      cursor = next;
      _acknowledged[runId] = cursor;
      _probedSupervisorCursors.add(runId);
      await _writeAcknowledgement(runId, cursor);
    }
  }

  Future<int> _readAcknowledgement(String runId) async {
    final json = await _acknowledgementStore(runId).read();
    workerKeys(
      json,
      const <String>{'schemaVersion', 'workspaceId', 'runId', 'sequence'},
      r'$',
      required: const <String>{
        'schemaVersion',
        'workspaceId',
        'runId',
        'sequence',
      },
    );
    if (json['schemaVersion'] != 'cockpit.worker.event-ack/v1' ||
        json['workspaceId'] != workspaceId ||
        json['runId'] != runId) {
      throw const FormatException('Worker event acknowledgement is corrupt.');
    }
    final sequence = workerInteger(json['sequence'], r'$.sequence', minimum: 0);
    if (sequence > (_events[runId]?.length ?? 0)) {
      throw const FormatException(
        'Worker event acknowledgement exceeds durable truth.',
      );
    }
    return sequence;
  }

  Future<void> _writeAcknowledgement(String runId, int sequence) =>
      _acknowledgementStore(runId).transact<void>(
        (_) => CockpitLockedJsonUpdate.write(
          _acknowledgementJson(runId, sequence),
          null,
        ),
      );

  CockpitLockedJsonStore<Map<String, Object?>> _acknowledgementStore(
    String runId,
  ) => CockpitLockedJsonStore<Map<String, Object?>>(
    path: p.join(stateRoot, 'runs', runId, 'relay.json'),
    codec: const _EventAcknowledgementCodec(),
    createInitial: () => _acknowledgementJson(runId, 0),
    permissionHardener: _permissionHardener,
    directorySyncer: _directorySyncer,
    maximumBytes: 16 * 1024,
  );

  Map<String, Object?> _acknowledgementJson(String runId, int sequence) =>
      <String, Object?>{
        'schemaVersion': 'cockpit.worker.event-ack/v1',
        'workspaceId': workspaceId,
        'runId': runId,
        'sequence': sequence,
      };

  CockpitRunEvent _redactedEvent(CockpitRunEvent event) {
    final redacted = _redactor(event.toJson());
    if (redacted is! Map<Object?, Object?>) {
      throw const FormatException('Event redaction did not return metadata.');
    }
    final safe = CockpitRunEvent.fromJson(Map<String, Object?>.from(redacted));
    if (safe.eventId != event.eventId ||
        safe.sequence != event.sequence ||
        safe.projectId != projectId ||
        safe.workspaceId != workspaceId ||
        safe.runId != event.runId ||
        safe.caseId != event.caseId ||
        safe.attemptId != event.attemptId ||
        safe.stepExecutionId != event.stepExecutionId) {
      throw const FormatException(
        'Event redaction changed ownership metadata.',
      );
    }
    return safe;
  }

  Future<void> _appendDurablyBatch(List<CockpitRunEvent> events) async {
    if (events.isEmpty) return;
    final directory = await _prepareRunDirectory(events.first.runId);
    final file = File(p.join(directory.path, 'events.ndjson'));
    final bytes = utf8.encode(
      '${events.map((event) => jsonEncode(event.toJson())).join('\n')}\n',
    );
    final existingLength = await file.exists() ? await file.length() : 0;
    if (existingLength + bytes.length > maximumLogBytes) {
      throw const FormatException('Worker event log byte bound was exceeded.');
    }
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.append);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
      await _permissionHardener.hardenFile(file);
      await _directorySyncer.sync(directory.path);
    } finally {
      await handle?.close();
    }
  }

  Future<List<CockpitRunEvent>> _readAndRepair(
    String runId,
    String eventPath,
  ) async {
    await _validateCanonicalFile(eventPath, p.join(stateRoot, 'runs', runId));
    final file = File(eventPath);
    final length = await file.length();
    if (length > maximumLogBytes) {
      throw const FormatException('Worker event log byte bound was exceeded.');
    }
    final bytes = await file.readAsBytes();
    var validLength = bytes.length;
    if (bytes.isNotEmpty && bytes.last != 0x0a) {
      validLength = bytes.lastIndexOf(0x0a) + 1;
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.truncate(validLength);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _directorySyncer.sync(file.parent.path);
    }
    final events = <CockpitRunEvent>[];
    final prefix = Uint8List.sublistView(bytes, 0, validLength);
    final text = utf8.decode(prefix, allowMalformed: false);
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) {
        throw const FormatException(
          'Worker event log contains an empty record.',
        );
      }
      final decoded = jsonDecode(line);
      final event = CockpitRunEvent.fromJson(decoded);
      if (event.projectId != projectId ||
          event.workspaceId != workspaceId ||
          event.runId != runId ||
          event.sequence != events.length + 1 ||
          !_eventIds.add(event.eventId)) {
        throw const FormatException(
          'Worker event log ownership or sequence is corrupt.',
        );
      }
      events.add(event);
      if (events.length > maximumEventsPerRun) {
        throw const FormatException('Worker event count bound was exceeded.');
      }
    }
    return events;
  }

  CockpitFailure _interruptedFailure() => CockpitFailure(
    primary: CockpitApiError(
      code: CockpitErrorCode.interrupted,
      category: CockpitErrorCategory.interrupted,
      message: 'The worker stopped before the run reached a terminal state.',
      retryable: true,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  );

  Future<Directory> _prepareRunDirectory(String runId) async {
    workerId(runId, r'$.runId');
    final runsRoot = p.join(stateRoot, 'runs');
    final directory = Directory(p.join(runsRoot, runId));
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      await directory.create();
      await _permissionHardener.hardenDirectory(directory);
      await _directorySyncer.sync(runsRoot);
    } else if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker run authority is invalid.',
        directory.path,
      );
    }
    await _validateCanonicalDirectory(directory.path, runsRoot);
    return directory;
  }

  Future<void> _validateStateRoot() async {
    final directory = Directory(stateRoot);
    if (!await directory.exists()) {
      throw FileSystemException('Worker state root is unavailable.', stateRoot);
    }
    final canonical = p.normalize(await directory.resolveSymbolicLinks());
    if (!p.equals(canonical, stateRoot)) {
      throw FileSystemException(
        'Worker state root is not canonical.',
        stateRoot,
      );
    }
  }

  Future<void> _validateCanonicalDirectory(
    String path,
    String authority,
  ) async {
    final canonical = p.normalize(await Directory(path).resolveSymbolicLinks());
    if (!p.equals(canonical, path) || !p.isWithin(authority, canonical)) {
      throw FileSystemException(
        'Worker event directory escapes authority.',
        path,
      );
    }
  }

  Future<void> _validateCanonicalFile(String path, String authority) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException(
        'Worker event log is not a regular file.',
        path,
      );
    }
    final canonical = p.normalize(await File(path).resolveSymbolicLinks());
    if (!p.equals(canonical, path) || !p.isWithin(authority, canonical)) {
      throw FileSystemException('Worker event log escapes authority.', path);
    }
  }

  Future<T> _locked<T>(String runId, Future<T> Function() operation) {
    final previous = _runLocks[runId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> current;
    current = previous
        .catchError((Object _) {})
        .then((_) => operation())
        .then(completer.complete, onError: completer.completeError)
        .whenComplete(() {
          if (identical(_runLocks[runId], current)) _runLocks.remove(runId);
        });
    _runLocks[runId] = current;
    return completer.future;
  }
}

String _canonicalEvent(CockpitRunEvent event) => jsonEncode(event.toJson());

final class _EventAcknowledgementCodec
    implements CockpitJsonCodec<Map<String, Object?>> {
  const _EventAcknowledgementCodec();

  @override
  Map<String, Object?> decode(Object? json) => workerObject(json, r'$');

  @override
  Object? encode(Map<String, Object?> value) => value;
}
