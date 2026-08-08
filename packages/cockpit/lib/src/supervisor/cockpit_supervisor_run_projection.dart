import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../artifacts/cockpit_test_attempt_bundle_writer.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../registry/cockpit_registry_models.dart';
import '../registry/cockpit_scoped_reference_index.dart';
import '../worker/cockpit_worker_protocol_request.dart';
import '../worker/cockpit_worker_protocol_result.dart';
import '../worker/cockpit_worker_server.dart';
import '../worker/cockpit_worker_value_reader.dart';

const int _maximumCanonicalReportBytes = 64 * 1024 * 1024;

abstract interface class CockpitSupervisorRunRetentionIndex {
  Future<void> retainRun({
    required String workspaceId,
    required String runId,
    required bool active,
    required int artifactCount,
  });

  Future<void> releaseRun({required String workspaceId, required String runId});
}

final class CockpitScopedSupervisorRunRetentionIndex
    implements CockpitSupervisorRunRetentionIndex {
  const CockpitScopedSupervisorRunRetentionIndex(this._index);

  final CockpitScopedReferenceIndex _index;

  @override
  Future<void> retainRun({
    required String workspaceId,
    required String runId,
    required bool active,
    required int artifactCount,
  }) => _index.setRun(
    workspaceId: workspaceId,
    runId: runId,
    active: active,
    retained: true,
    artifactCount: artifactCount,
  );

  @override
  Future<void> releaseRun({
    required String workspaceId,
    required String runId,
  }) async {
    try {
      await _index.releaseRunRetention(workspaceId, runId);
    } on CockpitRegistryException catch (error) {
      if (error.code != 'referenceNotFound') rethrow;
    }
  }
}

final class CockpitSupervisorEventReplay {
  const CockpitSupervisorEventReplay({
    required this.boundary,
    required this.events,
  });

  final CockpitEventReplayBoundary? boundary;
  final List<CockpitRunEvent> events;

  bool get hasGap => boundary?.hasGap ?? false;
}

final class CockpitSupervisorEventGapException implements Exception {
  const CockpitSupervisorEventGapException(this.boundary);

  final CockpitEventReplayBoundary boundary;

  @override
  String toString() =>
      'CockpitSupervisorEventGapException(${boundary.toJson()})';
}

typedef CockpitSupervisorMetadataRedactor = Object? Function(Object? value);
typedef CockpitSupervisorRunAdmissionValidator =
    Future<void> Function({
      required String runId,
      required String projectId,
      required String? caseId,
    });

abstract interface class CockpitSupervisorRunTruthProjection
    implements CockpitWorkerEventExchange {
  Future<void> rebuildRunFromWorkerTruth({
    required String runId,
    required List<CockpitRunEvent> events,
  });
}

final class CockpitSupervisorRunProjection
    implements
        CockpitSupervisorRunTruthProjection,
        CockpitWorkerArtifactExchange {
  CockpitSupervisorRunProjection({
    required this.workspaceId,
    required String stateRoot,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    required CockpitSupervisorRunRetentionIndex retentionIndex,
    CockpitSupervisorMetadataRedactor? redactor,
    CockpitSupervisorRunAdmissionValidator? admissionValidator,
    this.maximumRetainedEventsPerRun = 4096,
    this.maximumRuns = 10000,
    this.maximumEventOwners = 100000,
    this.maximumArtifacts = 100000,
    this.retentionRecoveryTimeout = const Duration(seconds: 30),
    DateTime Function()? utcNow,
  }) : stateRoot = p.normalize(stateRoot),
       _store = CockpitLockedJsonStore<Map<String, Object?>>(
         path: p.join(stateRoot, 'supervisor_projection', 'projection.json'),
         codec: const _ProjectionCodec(),
         createInitial: () => _emptyProjection(workspaceId),
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
         maximumBytes: 64 * 1024 * 1024,
       ),
       _retentionIndex = retentionIndex,
       _redactor = redactor ?? ((value) => value),
       _admissionValidator = admissionValidator,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
    if (!p.isAbsolute(stateRoot) || p.normalize(stateRoot) != stateRoot) {
      throw const FormatException(
        'Supervisor projection state root is invalid.',
      );
    }
    if (maximumRetainedEventsPerRun < 256 ||
        maximumRetainedEventsPerRun > 65536 ||
        maximumRuns < 1 ||
        maximumRuns > 100000 ||
        maximumEventOwners < 1 ||
        maximumEventOwners > 1000000 ||
        maximumArtifacts < 1 ||
        maximumArtifacts > 1000000 ||
        retentionRecoveryTimeout < const Duration(seconds: 1) ||
        retentionRecoveryTimeout > const Duration(minutes: 5)) {
      throw ArgumentError('Supervisor projection bounds are invalid.');
    }
  }

  final String workspaceId;
  final String stateRoot;
  final int maximumRetainedEventsPerRun;
  final int maximumRuns;
  final int maximumEventOwners;
  final int maximumArtifacts;
  final Duration retentionRecoveryTimeout;
  final CockpitLockedJsonStore<Map<String, Object?>> _store;
  final CockpitSupervisorRunRetentionIndex _retentionIndex;
  final CockpitSupervisorMetadataRedactor _redactor;
  final CockpitSupervisorRunAdmissionValidator? _admissionValidator;
  final DateTime Function() _utcNow;

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    _validateRequestIdentity(request.workspaceId, request.runId);
    await _validateAdmission(
      runId: request.runId,
      projectId: request.events.first.projectId,
      caseIds: request.events.map((event) => event.caseId),
    );
    final result = await _store.transact<CockpitWorkerPublishEventBatchResult>((
      raw,
    ) {
      final projection = _decodeProjection(
        raw,
        expectedWorkspaceId: workspaceId,
        maximumRuns: maximumRuns,
        maximumEventOwners: maximumEventOwners,
        maximumArtifacts: maximumArtifacts,
      );
      final current = projection.runs[request.runId];
      final highest = current?.highestSequence ?? 0;
      if (current != null && _isTerminalRun(current)) {
        return CockpitLockedJsonUpdate.readOnly(
          raw,
          CockpitWorkerPublishEventBatchResult(
            runId: request.runId,
            highestContiguousSequence: highest,
            terminal: true,
          ),
        );
      }
      if (current?.phase == _ProjectedRunPhase.releasing) {
        throw const FormatException(
          'Published events cannot mutate a releasing run.',
        );
      }
      if (request.afterSequence > highest) {
        return CockpitLockedJsonUpdate.readOnly(
          raw,
          CockpitWorkerPublishEventBatchResult(
            runId: request.runId,
            highestContiguousSequence: highest,
            terminal: false,
            replayAfterSequence: highest,
          ),
        );
      }
      if (current == null && projection.runs.length >= maximumRuns) {
        throw const FormatException('Supervisor run bound was exceeded.');
      }
      final run = current ?? _ProjectedRun.fromFirst(request.events.first);
      var nextHighest = highest;
      final pending =
          <
            ({CockpitRunEvent event, CockpitRunEvent redacted, String digest})
          >[];
      final pendingOwners = <String, String>{};
      for (final event in request.events) {
        _validateProjectedEvent(event, run);
        if (event.sequence <= nextHighest) {
          final indexed = run.eventIndex[event.sequence];
          if (indexed == null ||
              indexed.eventId != event.eventId ||
              indexed.sha256 != _eventDigest(event)) {
            throw const FormatException(
              'Published event conflicts with its durable sequence index.',
            );
          }
          continue;
        }
        if (event.sequence != nextHighest + 1) {
          return CockpitLockedJsonUpdate.readOnly(
            raw,
            CockpitWorkerPublishEventBatchResult(
              runId: request.runId,
              highestContiguousSequence: nextHighest,
              terminal: false,
              replayAfterSequence: nextHighest,
            ),
          );
        }
        final duplicateId = projection.eventOwners[event.eventId];
        final expectedOwner = '${event.runId}:${event.sequence}';
        final pendingDuplicate = pendingOwners[event.eventId];
        if ((duplicateId != null && duplicateId != expectedOwner) ||
            (pendingDuplicate != null && pendingDuplicate != expectedOwner)) {
          throw const FormatException('Global event id is not unique.');
        }
        if (duplicateId == null && pendingDuplicate == null) {
          pendingOwners[event.eventId] = expectedOwner;
        }
        pending.add((
          event: event,
          redacted: _redactedEvent(event),
          digest: _eventDigest(event),
        ));
        nextHighest = event.sequence;
      }
      if (projection.eventOwners.length + pendingOwners.length >
          maximumEventOwners) {
        throw const FormatException(
          'Supervisor event owner bound was exceeded.',
        );
      }
      for (final entry in pending) {
        run.events.add(entry.redacted);
        run.eventIndex[entry.event.sequence] = _ProjectedEventIndexRecord(
          eventId: entry.event.eventId,
          sha256: entry.digest,
        );
        projection.eventOwners[entry.event.eventId] =
            '${entry.event.runId}:${entry.event.sequence}';
      }
      run.highestSequence = nextHighest;
      while (run.events.length > maximumRetainedEventsPerRun) {
        run.events.removeAt(0);
      }
      projection.runs[request.runId] = run;
      final response = CockpitWorkerPublishEventBatchResult(
        runId: request.runId,
        highestContiguousSequence: nextHighest,
        terminal: false,
      );
      return pending.isNotEmpty
          ? CockpitLockedJsonUpdate.write(projection.toJson(), response)
          : CockpitLockedJsonUpdate.readOnly(raw, response);
    });
    await _updateRetention(request.runId);
    return result;
  }

  @override
  Future<CockpitWorkerReplayEventsResult> replay(
    CockpitWorkerReplayEventsRequest request,
  ) async {
    final replay = await readEvents(
      request.runId,
      afterSequence: request.afterSequence,
      maximumEvents: 256,
    );
    if (replay.boundary case final boundary? when boundary.hasGap) {
      throw CockpitSupervisorEventGapException(boundary);
    }
    return CockpitWorkerReplayEventsResult(
      runId: request.runId,
      afterSequence: request.afterSequence,
      events: replay.events,
    );
  }

  Future<CockpitSupervisorEventReplay> readEvents(
    String runId, {
    required int afterSequence,
    int maximumEvents = 256,
  }) async {
    _validateRequestIdentity(workspaceId, runId);
    workerInteger(afterSequence, r'$.afterSequence', minimum: 0);
    if (maximumEvents < 1 || maximumEvents > 4096) {
      throw const FormatException('Supervisor replay page bound is invalid.');
    }
    final projection = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final run = projection.runs[runId];
    if (run == null || run.highestSequence == 0) {
      return const CockpitSupervisorEventReplay(
        boundary: null,
        events: <CockpitRunEvent>[],
      );
    }
    final earliest = run.events.isEmpty
        ? run.highestSequence + 1
        : run.events.first.sequence;
    if (earliest > run.highestSequence) {
      throw const FormatException(
        'Supervisor event projection has no replay buffer.',
      );
    }
    final boundary = CockpitEventReplayBoundary(
      requestedAfterSequence: afterSequence,
      earliestAvailableSequence: earliest,
      latestAvailableSequence: run.highestSequence,
    );
    if (boundary.hasGap) {
      return CockpitSupervisorEventReplay(
        boundary: boundary,
        events: const <CockpitRunEvent>[],
      );
    }
    final events = run.events
        .where((event) => event.sequence > afterSequence)
        .take(maximumEvents)
        .toList(growable: false);
    return CockpitSupervisorEventReplay(boundary: boundary, events: events);
  }

  @override
  Future<CockpitWorkerPublishArtifactBatchResult> publishArtifacts(
    CockpitWorkerPublishArtifactBatchRequest request,
  ) async {
    _validateRequestIdentity(request.workspaceId, request.runId);
    await _validateAdmission(
      runId: request.runId,
      projectId: request.projectId,
      caseIds: <String?>[request.caseId],
    );
    final initial = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final initialRun = initial.runs[request.runId];
    if (initialRun?.phase == _ProjectedRunPhase.releasing) {
      throw const FormatException(
        'Published artifacts cannot mutate a releasing run.',
      );
    }
    final owner = (
      projectId: request.projectId,
      caseIds: <String>{?request.caseId},
    );
    if (initialRun != null && initialRun.projectId != owner.projectId) {
      throw const FormatException(
        'Artifact publication changes projected run ownership.',
      );
    }
    final verified = <CockpitArtifactResource>[];
    for (final artifact in request.artifacts) {
      verified.add(
        await _verifyArtifact(
          artifact,
          expectedRunId: request.runId,
          owner: owner,
        ),
      );
    }
    final result = await _store
        .transact<CockpitWorkerPublishArtifactBatchResult>((raw) {
          final projection = _decodeProjection(
            raw,
            expectedWorkspaceId: workspaceId,
            maximumRuns: maximumRuns,
            maximumEventOwners: maximumEventOwners,
            maximumArtifacts: maximumArtifacts,
          );
          var run = projection.runs[request.runId];
          if (run != null &&
              (run.phase != _ProjectedRunPhase.active ||
                  run.projectId != owner.projectId)) {
            throw const FormatException(
              'Artifact projected owner changed during publication.',
            );
          }
          if (run == null) {
            if (projection.runs.length >= maximumRuns) {
              throw const FormatException('Supervisor run bound was exceeded.');
            }
            run = _ProjectedRun.empty(
              projectId: request.projectId,
              caseId: request.caseId,
            );
            projection.runs[request.runId] = run;
          }
          if (request.caseId case final caseId?) run.caseIds.add(caseId);
          var changed = false;
          for (final artifact in verified) {
            final owner = projection.artifactOwners[artifact.artifactId];
            if (owner != null && owner != request.runId) {
              throw const FormatException('Global artifact id is not unique.');
            }
            final existing = run.artifacts[artifact.artifactId];
            if (existing != null) {
              if (!_sameJson(existing.toJson(), artifact.toJson())) {
                throw const FormatException(
                  'Published artifact conflicts with its existing id.',
                );
              }
              continue;
            }
            if (projection.artifactOwners.length >= maximumArtifacts) {
              throw const FormatException(
                'Supervisor artifact bound was exceeded.',
              );
            }
            run.artifacts[artifact.artifactId] = artifact;
            projection.artifactOwners[artifact.artifactId] = request.runId;
            changed = true;
          }
          final response = CockpitWorkerPublishArtifactBatchResult(
            runId: request.runId,
            artifactIds: verified.map((artifact) => artifact.artifactId),
          );
          return changed
              ? CockpitLockedJsonUpdate.write(projection.toJson(), response)
              : CockpitLockedJsonUpdate.readOnly(raw, response);
        });
    await _updateRetention(request.runId);
    return result;
  }

  Future<CockpitArtifactResource> requireArtifact(
    String runId,
    String artifactId,
  ) async {
    _validateRequestIdentity(workspaceId, runId);
    workerId(artifactId, r'$.artifactId');
    final projection = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final run = projection.runs[runId];
    final resource = run?.artifacts[artifactId];
    if (resource == null) {
      throw const FormatException('Artifact is not indexed for this run.');
    }
    return _verifyArtifact(
      resource,
      expectedRunId: runId,
      owner: (projectId: run!.projectId, caseIds: run.caseIds),
    );
  }

  Future<List<CockpitArtifactResource>> artifacts(String runId) async {
    _validateRequestIdentity(workspaceId, runId);
    final projection = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final run = projection.runs[runId];
    if (run == null) {
      throw const FormatException('Run is not projected.');
    }
    return run.artifacts.values.toList(growable: false)..sort((left, right) {
      final byPath = left.relativePath.compareTo(right.relativePath);
      return byPath != 0 ? byPath : left.artifactId.compareTo(right.artifactId);
    });
  }

  Future<CockpitTestSuiteReport> requireSuiteReport(String runId) async {
    _validateRequestIdentity(workspaceId, runId);
    final projection = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final run = projection.runs[runId];
    if (run == null) {
      throw const FormatException('Run is not projected.');
    }
    final resource = run.artifacts.values
        .where((artifact) => artifact.kind == 'report.json')
        .singleOrNull;
    if (resource == null) {
      throw const FormatException('Suite report is not available.');
    }
    final verified = await _verifyArtifact(
      resource,
      expectedRunId: runId,
      owner: (projectId: run.projectId, caseIds: run.caseIds),
    );
    final file = File(p.join(stateRoot, 'runs', runId, verified.relativePath));
    if (await file.length() > _maximumCanonicalReportBytes) {
      throw const FormatException('Suite report is too large.');
    }
    return CockpitTestReportBundle.fromJson(
      jsonDecode(await file.readAsString()),
    ).report;
  }

  Future<({CockpitArtifactResource resource, File file})> requireArtifactFile(
    String runId,
    String artifactId,
  ) async {
    final resource = await requireArtifact(runId, artifactId);
    return (
      resource: resource,
      file: File(p.join(stateRoot, 'runs', runId, resource.relativePath)),
    );
  }

  Future<bool> containsRun(String runId) async {
    _validateRequestIdentity(workspaceId, runId);
    final projection = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    return projection.runs.containsKey(runId);
  }

  @override
  Future<void> rebuildRunFromWorkerTruth({
    required String runId,
    required List<CockpitRunEvent> events,
  }) async {
    _validateRequestIdentity(workspaceId, runId);
    if (events.isEmpty) {
      throw const FormatException('Run rebuild requires worker events.');
    }
    CockpitRunEvent.validateSequence(events);
    if (events.any(
      (event) => event.workspaceId != workspaceId || event.runId != runId,
    )) {
      throw const FormatException('Run rebuild crosses projection authority.');
    }
    await _validateAdmission(
      runId: runId,
      projectId: events.first.projectId,
      caseIds: events.map((event) => event.caseId),
    );
    final owner = (projectId: events.first.projectId);
    final replacementEventOwners = <String, String>{};
    final replacementEventIndex = <int, _ProjectedEventIndexRecord>{};
    for (final event in events) {
      if (replacementEventOwners.putIfAbsent(
            event.eventId,
            () => '$runId:${event.sequence}',
          ) !=
          '$runId:${event.sequence}') {
        throw const FormatException('Global event id conflict.');
      }
      replacementEventIndex[event.sequence] = _ProjectedEventIndexRecord(
        eventId: event.eventId,
        sha256: _eventDigest(event),
      );
    }
    final retainedEvents = events
        .skip(
          events.length > maximumRetainedEventsPerRun
              ? events.length - maximumRetainedEventsPerRun
              : 0,
        )
        .map(_redactedEvent)
        .toList(growable: false);
    await _store.transact<void>((raw) {
      final projection = _decodeProjection(
        raw,
        expectedWorkspaceId: workspaceId,
        maximumRuns: maximumRuns,
        maximumEventOwners: maximumEventOwners,
        maximumArtifacts: maximumArtifacts,
      );
      final previous = projection.runs[runId];
      if (previous?.phase == _ProjectedRunPhase.releasing) {
        throw const FormatException('Cannot rebuild a releasing run.');
      }
      if (previous != null && _projectedRunOwner(previous) != owner) {
        throw const FormatException('Run rebuild changes projected ownership.');
      }
      if (previous == null && projection.runs.length >= maximumRuns) {
        throw const FormatException('Supervisor run bound was exceeded.');
      }
      final retainedOwnerCount = projection.eventOwners.values
          .where((owner) => !_eventOwnerBelongsToRun(owner, runId))
          .length;
      if (retainedOwnerCount + replacementEventOwners.length >
          maximumEventOwners) {
        throw const FormatException(
          'Supervisor event owner bound was exceeded.',
        );
      }
      for (final entry in replacementEventOwners.entries) {
        final owner = projection.eventOwners[entry.key];
        if (owner != null && !_eventOwnerBelongsToRun(owner, runId)) {
          throw const FormatException('Global event id conflict.');
        }
      }
      final run = _ProjectedRun.fromFirst(events.first);
      run.caseIds.addAll(
        events.map((event) => event.caseId).whereType<String>(),
      );
      run.highestSequence = events.last.sequence;
      run.events.addAll(retainedEvents);
      run.eventIndex.addAll(replacementEventIndex);
      if (previous != null) {
        run.caseIds.addAll(previous.caseIds);
        run.artifacts.addAll(previous.artifacts);
      }
      projection.runs[runId] = run;
      projection.eventOwners.removeWhere(
        (_, owner) => _eventOwnerBelongsToRun(owner, runId),
      );
      projection.eventOwners.addAll(replacementEventOwners);
      return CockpitLockedJsonUpdate.write(projection.toJson(), null);
    });
    await _updateRetention(runId);
  }

  Future<void> releaseRetainedRun(String runId) async {
    _validateRequestIdentity(workspaceId, runId);
    final intent = await _markRunReleasing(runId);
    if (intent == null) return;
    await _completeRetentionRelease(intent);
  }

  Future<void> resumePendingRetentionReleases() async {
    final deadline = _utcNow().toUtc().add(retentionRecoveryTimeout);
    final projection = _decodeProjection(
      await _store.read().timeout(_remainingRetentionTime(deadline)),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final pending =
        projection.runs.entries
            .where((entry) => entry.value.phase == _ProjectedRunPhase.releasing)
            .map(
              (entry) => _RetentionReleaseIntent(
                runId: entry.key,
                owner: _projectedRunOwner(entry.value),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.runId.compareTo(right.runId));
    for (final intent in pending) {
      await _completeRetentionRelease(intent, deadline: deadline);
    }
  }

  Future<void> _validateAdmission({
    required String runId,
    required String projectId,
    required Iterable<String?> caseIds,
  }) async {
    final validator = _admissionValidator;
    if (validator == null) return;
    final authoredCaseIds = caseIds.whereType<String>().toSet();
    if (authoredCaseIds.isEmpty) {
      await validator(runId: runId, projectId: projectId, caseId: null);
      return;
    }
    for (final caseId in authoredCaseIds) {
      await validator(runId: runId, projectId: projectId, caseId: caseId);
    }
  }

  Future<_RetentionReleaseIntent?> _markRunReleasing(String runId) =>
      _store.transact<_RetentionReleaseIntent?>((raw) {
        final projection = _decodeProjection(
          raw,
          expectedWorkspaceId: workspaceId,
          maximumRuns: maximumRuns,
          maximumEventOwners: maximumEventOwners,
          maximumArtifacts: maximumArtifacts,
        );
        final run = projection.runs[runId];
        if (run == null) {
          return CockpitLockedJsonUpdate.readOnly(raw, null);
        }
        final intent = _RetentionReleaseIntent(
          runId: runId,
          owner: _projectedRunOwner(run),
        );
        if (run.phase == _ProjectedRunPhase.releasing) {
          return CockpitLockedJsonUpdate.readOnly(raw, intent);
        }
        run.phase = _ProjectedRunPhase.releasing;
        return CockpitLockedJsonUpdate.write(projection.toJson(), intent);
      });

  Future<void> _completeRetentionRelease(
    _RetentionReleaseIntent intent, {
    DateTime? deadline,
  }) async {
    final release = _retentionIndex.releaseRun(
      workspaceId: workspaceId,
      runId: intent.runId,
    );
    if (deadline == null) {
      await release;
    } else {
      await release.timeout(_remainingRetentionTime(deadline));
    }
    final finalize = _store.transact<void>((raw) {
      final projection = _decodeProjection(
        raw,
        expectedWorkspaceId: workspaceId,
        maximumRuns: maximumRuns,
        maximumEventOwners: maximumEventOwners,
        maximumArtifacts: maximumArtifacts,
      );
      final run = projection.runs[intent.runId];
      if (run == null) {
        return CockpitLockedJsonUpdate.readOnly(raw, null);
      }
      if (run.phase != _ProjectedRunPhase.releasing ||
          _projectedRunOwner(run) != intent.owner) {
        throw const FormatException(
          'Retention release intent no longer matches its projected owner.',
        );
      }
      projection.runs.remove(intent.runId);
      projection.eventOwners.removeWhere(
        (_, owner) => _eventOwnerBelongsToRun(owner, intent.runId),
      );
      projection.artifactOwners.removeWhere(
        (_, owner) => owner == intent.runId,
      );
      return CockpitLockedJsonUpdate.write(projection.toJson(), null);
    });
    if (deadline == null) {
      await finalize;
    } else {
      await finalize.timeout(_remainingRetentionTime(deadline));
    }
  }

  Duration _remainingRetentionTime(DateTime deadline) {
    final remaining = deadline.toUtc().difference(_utcNow().toUtc());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Supervisor retention recovery timed out.');
    }
    return remaining;
  }

  Future<CockpitArtifactResource> _verifyArtifact(
    CockpitArtifactResource artifact, {
    required String expectedRunId,
    required _ArtifactOwner owner,
  }) async {
    if (artifact.workspaceId != workspaceId ||
        artifact.runId != expectedRunId) {
      throw const FormatException('Artifact crosses projected run authority.');
    }
    if (artifact.downloadUrl !=
        '/api/v2/runs/${artifact.runId}/artifacts/${artifact.artifactId}') {
      throw const FormatException('Artifact ownership metadata is incomplete.');
    }
    final relative = artifact.relativePath.replaceAll('\\', '/');
    if (relative != artifact.relativePath ||
        p.posix.normalize(relative) != relative ||
        p.posix.isAbsolute(relative) ||
        relative == '..' ||
        relative.startsWith('../')) {
      throw const FormatException('Artifact relative path is not confined.');
    }
    final components = p.posix.split(relative);
    if (components.length < 3 ||
        components.first != 'artifacts' ||
        !_validRetainedBundleName(components[1])) {
      throw const FormatException(
        'Artifact path has no retained bundle authority.',
      );
    }
    final runRoot = p.join(stateRoot, 'runs', expectedRunId);
    final artifactRoot = p.join(runRoot, 'artifacts');
    await _validateCanonicalArtifactDirectory(
      artifactRoot,
      authority: runRoot,
      diagnostic: 'Run artifact root is not canonical.',
    );
    final bundleRoot = p.join(artifactRoot, components[1]);
    if (!p.equals(p.dirname(bundleRoot), artifactRoot)) {
      throw const FormatException(
        'Retained bundle is not a direct child of its artifact root.',
      );
    }
    await _validateCanonicalArtifactDirectory(
      bundleRoot,
      authority: artifactRoot,
      diagnostic: 'Retained bundle root is not canonical.',
    );
    final candidate = p.normalize(
      p.joinAll(<String>[bundleRoot, ...components.skip(2)]),
    );
    if (!p.isWithin(bundleRoot, candidate) ||
        await FileSystemEntity.type(candidate, followLinks: false) !=
            FileSystemEntityType.file) {
      throw FileSystemException(
        'Artifact is outside its retained bundle authority.',
        candidate,
      );
    }
    final canonical = p.normalize(await File(candidate).resolveSymbolicLinks());
    if (!p.equals(canonical, candidate) || !p.isWithin(bundleRoot, canonical)) {
      throw FileSystemException(
        'Artifact resolves outside its retained bundle authority.',
        candidate,
      );
    }
    final size = await File(candidate).length();
    final digest = (await sha256.bind(File(candidate).openRead()).first)
        .toString();
    if (size != artifact.sizeBytes || digest != artifact.sha256) {
      throw const FormatException(
        'Artifact byte integrity verification failed.',
      );
    }
    final relativeToBundle = p
        .relative(candidate, from: bundleRoot)
        .replaceAll('\\', '/');
    final declared = artifact.attemptId == null
        ? await _verifyReportArtifact(
            artifact,
            owner: owner,
            bundleRoot: bundleRoot,
            relativeToBundle: relativeToBundle,
          )
        : await _verifyAttemptArtifact(
            artifact,
            owner: owner,
            bundleRoot: bundleRoot,
            relativeToBundle: relativeToBundle,
            size: size,
            digest: digest,
          );
    if (!declared) {
      throw const FormatException('Artifact is not declared by its bundle.');
    }
    final safe = _redactor(artifact.toJson());
    if (safe is! Map<Object?, Object?>) {
      throw const FormatException('Supervisor artifact redaction failed.');
    }
    final redacted = CockpitArtifactResource.fromJson(
      Map<String, Object?>.from(safe),
    );
    if (!_sameJson(redacted.toJson(), artifact.toJson())) {
      throw const FormatException(
        'Supervisor artifact redaction changed immutable metadata.',
      );
    }
    return redacted;
  }

  Future<bool> _verifyAttemptArtifact(
    CockpitArtifactResource artifact, {
    required _ArtifactOwner owner,
    required String bundleRoot,
    required String relativeToBundle,
    required int size,
    required String digest,
  }) async {
    if (owner.caseIds.isEmpty) return false;
    final manifest = await const CockpitTestAttemptBundleReader().readAndVerify(
      path: bundleRoot,
    );
    if (manifest.context.projectId != owner.projectId ||
        manifest.context.workspaceId != workspaceId ||
        manifest.context.runId != artifact.runId ||
        !owner.caseIds.contains(manifest.context.caseId) ||
        manifest.context.attemptId != artifact.attemptId) {
      throw const FormatException('Artifact attempt ownership is invalid.');
    }
    if (relativeToBundle == 'manifest.json') {
      return artifact.kind == 'attempt.manifest' &&
          artifact.mediaType == 'application/json' &&
          artifact.stepExecutionId == null &&
          artifact.createdAt == manifest.createdAt;
    }
    final entry = manifest.artifacts
        .where((item) => item.relativePath == relativeToBundle)
        .firstOrNull;
    return entry != null &&
        entry.sizeBytes == size &&
        entry.sha256 == digest &&
        entry.mediaType == artifact.mediaType &&
        entry.stepExecutionId == artifact.stepExecutionId &&
        artifact.kind == _artifactKind(entry.kind) &&
        artifact.createdAt == manifest.createdAt;
  }

  Future<bool> _verifyReportArtifact(
    CockpitArtifactResource artifact, {
    required _ArtifactOwner owner,
    required String bundleRoot,
    required String relativeToBundle,
  }) async {
    if (artifact.stepExecutionId != null) return false;
    final reportFile = File(p.join(bundleRoot, 'report.json'));
    final manifestFile = File(p.join(bundleRoot, 'manifest.json'));
    if (await FileSystemEntity.type(reportFile.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.type(manifestFile.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await reportFile.length() > _maximumCanonicalReportBytes ||
        await manifestFile.length() > _maximumCanonicalReportBytes) {
      throw const FormatException(
        'Canonical suite report is unavailable or too large.',
      );
    }
    final canonical = p.normalize(await reportFile.resolveSymbolicLinks());
    if (!p.equals(canonical, reportFile.path) ||
        !p.isWithin(bundleRoot, canonical)) {
      throw const FormatException('Canonical suite report is not confined.');
    }
    final report = CockpitTestReportBundle.fromJson(
      jsonDecode(await reportFile.readAsString()),
    ).report;
    if (report.projectId != owner.projectId ||
        report.workspaceId != workspaceId ||
        report.runId != artifact.runId) {
      throw const FormatException('Report artifact ownership is invalid.');
    }
    if (relativeToBundle == 'manifest.json') {
      return artifact.kind == 'report.manifest' &&
          artifact.mediaType == 'application/json' &&
          artifact.createdAt == report.finishedAt.toUtc();
    }
    final manifest = CockpitTestReportBundleManifest.fromJson(
      jsonDecode(await manifestFile.readAsString()),
    );
    if (manifest.runId != report.runId) return false;
    final declaration = manifest.files
        .where((file) => file.relativePath == relativeToBundle)
        .firstOrNull;
    return declaration != null &&
        declaration.sizeBytes == artifact.sizeBytes &&
        declaration.sha256 == artifact.sha256 &&
        declaration.kind == artifact.kind &&
        declaration.mediaType == artifact.mediaType &&
        artifact.createdAt == report.finishedAt.toUtc();
  }

  Future<void> _validateCanonicalArtifactDirectory(
    String path, {
    required String authority,
    required String diagnostic,
  }) async {
    if (!p.isWithin(authority, path) ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw FileSystemException(diagnostic, path);
    }
    final canonical = p.normalize(await Directory(path).resolveSymbolicLinks());
    if (!p.equals(canonical, p.normalize(path)) ||
        !p.isWithin(authority, canonical)) {
      throw FileSystemException(diagnostic, path);
    }
  }

  CockpitRunEvent _redactedEvent(CockpitRunEvent event) {
    final value = _redactor(event.toJson());
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Supervisor event redaction failed.');
    }
    final redacted = CockpitRunEvent.fromJson(Map<String, Object?>.from(value));
    if (!_sameJson(redacted.toJson(), event.toJson())) {
      throw const FormatException(
        'Supervisor event redaction changed already-redacted metadata.',
      );
    }
    return redacted;
  }

  Future<void> _updateRetention(String runId) async {
    final projection = _decodeProjection(
      await _store.read(),
      expectedWorkspaceId: workspaceId,
      maximumRuns: maximumRuns,
      maximumEventOwners: maximumEventOwners,
      maximumArtifacts: maximumArtifacts,
    );
    final run = projection.runs[runId];
    if (run == null) return;
    final terminal = _isTerminalRun(run);
    await _retentionIndex.retainRun(
      workspaceId: workspaceId,
      runId: runId,
      active: !terminal,
      artifactCount: run.artifacts.length,
    );
  }

  void _validateRequestIdentity(String requestWorkspaceId, String runId) {
    if (requestWorkspaceId != workspaceId) {
      throw const FormatException(
        'Projection request crosses workspace authority.',
      );
    }
    workerId(runId, r'$.runId');
  }
}

bool _isTerminalRun(_ProjectedRun run) => run.events.any(
  (event) =>
      event.entityKind == CockpitRunEventEntityKind.run &&
      event.lifecycle == CockpitRunLifecycle.completed,
);

final class _ProjectionCodec implements CockpitJsonCodec<Map<String, Object?>> {
  const _ProjectionCodec();

  @override
  Map<String, Object?> decode(Object? json) => workerObject(json, r'$');

  @override
  Object? encode(Map<String, Object?> value) => value;
}

final class _ProjectionState {
  _ProjectionState({
    required this.workspaceId,
    required this.runs,
    required this.eventOwners,
    required this.artifactOwners,
  });

  final String workspaceId;
  final Map<String, _ProjectedRun> runs;
  final Map<String, String> eventOwners;
  final Map<String, String> artifactOwners;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 'cockpit.supervisor.run-projection/v3',
    'workspaceId': workspaceId,
    'runs': <String, Object?>{
      for (final entry in runs.entries) entry.key: entry.value.toJson(),
    },
    'eventOwners': eventOwners,
    'artifactOwners': artifactOwners,
  };
}

final class _ProjectedRun {
  _ProjectedRun({
    required this.projectId,
    required Iterable<String> caseIds,
    required this.phase,
    required this.highestSequence,
    required this.events,
    required this.eventIndex,
    required this.artifacts,
  }) : caseIds = caseIds.toSet();

  factory _ProjectedRun.fromFirst(CockpitRunEvent event) => _ProjectedRun(
    projectId: event.projectId,
    caseIds: <String>[?event.caseId],
    phase: _ProjectedRunPhase.active,
    highestSequence: 0,
    events: <CockpitRunEvent>[],
    eventIndex: <int, _ProjectedEventIndexRecord>{},
    artifacts: <String, CockpitArtifactResource>{},
  );

  factory _ProjectedRun.empty({
    required String projectId,
    required String? caseId,
  }) => _ProjectedRun(
    projectId: projectId,
    caseIds: <String>[?caseId],
    phase: _ProjectedRunPhase.active,
    highestSequence: 0,
    events: <CockpitRunEvent>[],
    eventIndex: <int, _ProjectedEventIndexRecord>{},
    artifacts: <String, CockpitArtifactResource>{},
  );

  final String projectId;
  final Set<String> caseIds;
  _ProjectedRunPhase phase;
  int highestSequence;
  final List<CockpitRunEvent> events;
  final Map<int, _ProjectedEventIndexRecord> eventIndex;
  final Map<String, CockpitArtifactResource> artifacts;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    'caseIds': caseIds.toList(growable: false)..sort(),
    'phase': phase.name,
    'highestSequence': highestSequence,
    'events': events.map((event) => event.toJson()).toList(),
    'eventIndex': <String, Object?>{
      for (final entry in eventIndex.entries)
        '${entry.key}': entry.value.toJson(),
    },
    'artifacts': <String, Object?>{
      for (final entry in artifacts.entries) entry.key: entry.value.toJson(),
    },
  };
}

enum _ProjectedRunPhase { active, releasing }

final class _ProjectedEventIndexRecord {
  const _ProjectedEventIndexRecord({
    required this.eventId,
    required this.sha256,
  });

  final String eventId;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'eventId': eventId,
    'sha256': sha256,
  };
}

final class _RetentionReleaseIntent {
  const _RetentionReleaseIntent({required this.runId, required this.owner});

  final String runId;
  final _ProjectedRunOwner owner;
}

typedef _ProjectedRunOwner = ({String projectId});
typedef _ArtifactOwner = ({String projectId, Set<String> caseIds});

_ProjectedRunOwner _projectedRunOwner(_ProjectedRun run) =>
    (projectId: run.projectId);

bool _validRetainedBundleName(String value) =>
    RegExp(r'^bundle_[A-Za-z0-9_-]{32}$').hasMatch(value);

Map<String, Object?> _emptyProjection(String workspaceId) => _ProjectionState(
  workspaceId: workspaceId,
  runs: <String, _ProjectedRun>{},
  eventOwners: <String, String>{},
  artifactOwners: <String, String>{},
).toJson();

_ProjectionState _decodeProjection(
  Map<String, Object?> raw, {
  required String expectedWorkspaceId,
  required int maximumRuns,
  required int maximumEventOwners,
  required int maximumArtifacts,
}) {
  final json = workerObject(raw, r'$');
  workerKeys(
    json,
    const <String>{
      'schemaVersion',
      'workspaceId',
      'runs',
      'eventOwners',
      'artifactOwners',
    },
    r'$',
    required: const <String>{
      'schemaVersion',
      'workspaceId',
      'runs',
      'eventOwners',
      'artifactOwners',
    },
  );
  if (json['schemaVersion'] != 'cockpit.supervisor.run-projection/v3' ||
      json['workspaceId'] != expectedWorkspaceId) {
    throw const FormatException('Supervisor projection identity is invalid.');
  }
  final rawRuns = workerObject(json['runs'], r'$.runs');
  if (rawRuns.length > maximumRuns) {
    throw const FormatException(
      'Supervisor run projection bound was exceeded.',
    );
  }
  final runs = <String, _ProjectedRun>{};
  final derivedEventOwners = <String, String>{};
  final derivedArtifactOwners = <String, String>{};
  for (final entry in rawRuns.entries) {
    final runId = workerId(entry.key, r'$.runs.key');
    final value = workerObject(entry.value, '\$.runs.$runId');
    workerKeys(
      value,
      const <String>{
        'projectId',
        'caseIds',
        'phase',
        'highestSequence',
        'events',
        'eventIndex',
        'artifacts',
      },
      '\$.runs.$runId',
      required: const <String>{
        'projectId',
        'caseIds',
        'phase',
        'highestSequence',
        'events',
        'eventIndex',
        'artifacts',
      },
    );
    final projectId = workerId(value['projectId'], '\$.runs.$runId.projectId');
    final caseIds = workerList(
      value['caseIds'],
      '\$.runs.$runId.caseIds',
      maximum: 10000,
    ).map((value) => workerId(value, '\$.runs.$runId.caseIds[]')).toSet();
    final phase = switch (workerString(
      value['phase'],
      '\$.runs.$runId.phase',
      maximum: 32,
    )) {
      'active' => _ProjectedRunPhase.active,
      'releasing' => _ProjectedRunPhase.releasing,
      _ => throw const FormatException(
        'Supervisor projected run phase is invalid.',
      ),
    };
    final highest = workerInteger(
      value['highestSequence'],
      '\$.runs.$runId.highestSequence',
      minimum: 0,
    );
    final rawEvents = workerList(
      value['events'],
      '\$.runs.$runId.events',
      maximum: 65536,
    );
    final events = <CockpitRunEvent>[
      for (var index = 0; index < rawEvents.length; index += 1)
        CockpitRunEvent.fromJson(
          rawEvents[index],
          path: '\$.runs.$runId.events[$index]',
        ),
    ];
    if (events.isNotEmpty) {
      CockpitRunEvent.validateSequence(
        events,
        afterSequence: events.first.sequence - 1,
      );
      if (events.last.sequence != highest ||
          events.any(
            (event) =>
                event.runId != runId ||
                event.workspaceId != expectedWorkspaceId,
          )) {
        throw const FormatException('Supervisor event projection is corrupt.');
      }
    } else if (highest != 0) {
      throw const FormatException(
        'Supervisor event projection lost its buffer.',
      );
    }
    final rawEventIndex = workerObject(
      value['eventIndex'],
      '\$.runs.$runId.eventIndex',
    );
    if (rawEventIndex.length != highest ||
        derivedEventOwners.length + rawEventIndex.length > maximumEventOwners) {
      throw const FormatException(
        'Supervisor durable event index bound is invalid.',
      );
    }
    final eventIndex = <int, _ProjectedEventIndexRecord>{};
    for (final indexEntry in rawEventIndex.entries) {
      final sequence = int.tryParse(indexEntry.key);
      if (sequence == null ||
          sequence < 1 ||
          sequence > highest ||
          indexEntry.key != '$sequence') {
        throw const FormatException(
          'Supervisor durable event sequence index is invalid.',
        );
      }
      final indexValue = workerObject(
        indexEntry.value,
        '\$.runs.$runId.eventIndex.${indexEntry.key}',
      );
      workerKeys(
        indexValue,
        const <String>{'eventId', 'sha256'},
        '\$.runs.$runId.eventIndex.${indexEntry.key}',
        required: const <String>{'eventId', 'sha256'},
      );
      final eventId = workerId(
        indexValue['eventId'],
        '\$.runs.$runId.eventIndex.${indexEntry.key}.eventId',
      );
      final digest = workerString(
        indexValue['sha256'],
        '\$.runs.$runId.eventIndex.${indexEntry.key}.sha256',
        maximum: 64,
      );
      if (!_validSha256(digest) ||
          derivedEventOwners.putIfAbsent(eventId, () => '$runId:$sequence') !=
              '$runId:$sequence') {
        throw const FormatException(
          'Supervisor durable event index is corrupt.',
        );
      }
      eventIndex[sequence] = _ProjectedEventIndexRecord(
        eventId: eventId,
        sha256: digest,
      );
    }
    for (var sequence = 1; sequence <= highest; sequence += 1) {
      if (!eventIndex.containsKey(sequence)) {
        throw const FormatException(
          'Supervisor durable event index is not contiguous.',
        );
      }
    }
    for (final event in events) {
      final indexed = eventIndex[event.sequence];
      if (event.projectId != projectId ||
          event.caseId != null && !caseIds.contains(event.caseId) ||
          indexed?.eventId != event.eventId ||
          indexed?.sha256 != _eventDigest(event)) {
        throw const FormatException(
          'Supervisor retained event conflicts with its durable index.',
        );
      }
    }
    final rawArtifacts = workerObject(
      value['artifacts'],
      '\$.runs.$runId.artifacts',
    );
    final artifacts = <String, CockpitArtifactResource>{};
    for (final artifactEntry in rawArtifacts.entries) {
      final artifact = CockpitArtifactResource.fromJson(
        artifactEntry.value,
        path: '\$.runs.$runId.artifacts.${artifactEntry.key}',
      );
      if (artifactEntry.key != artifact.artifactId ||
          artifact.runId != runId ||
          artifact.workspaceId != expectedWorkspaceId ||
          derivedArtifactOwners.putIfAbsent(artifact.artifactId, () => runId) !=
              runId) {
        throw const FormatException(
          'Supervisor artifact projection is corrupt.',
        );
      }
      artifacts[artifact.artifactId] = artifact;
    }
    runs[runId] = _ProjectedRun(
      projectId: projectId,
      caseIds: caseIds,
      phase: phase,
      highestSequence: highest,
      events: events,
      eventIndex: eventIndex,
      artifacts: artifacts,
    );
  }
  if (derivedArtifactOwners.length > maximumArtifacts) {
    throw const FormatException(
      'Supervisor artifact projection bound was exceeded.',
    );
  }
  final eventOwners = _stringMap(json['eventOwners'], r'$.eventOwners');
  if (eventOwners.length > maximumEventOwners) {
    throw const FormatException('Supervisor event owner bound was exceeded.');
  }
  final artifactOwners = _stringMap(
    json['artifactOwners'],
    r'$.artifactOwners',
  );
  if (!_sameStringMap(eventOwners, derivedEventOwners) ||
      !_sameStringMap(artifactOwners, derivedArtifactOwners)) {
    throw const FormatException(
      'Supervisor projection owner index is corrupt.',
    );
  }
  return _ProjectionState(
    workspaceId: expectedWorkspaceId,
    runs: runs,
    eventOwners: eventOwners,
    artifactOwners: artifactOwners,
  );
}

Map<String, String> _stringMap(Object? value, String path) {
  final json = workerObject(value, path);
  return <String, String>{
    for (final entry in json.entries)
      workerId(entry.key, '$path.key'): workerString(
        entry.value,
        '$path.${entry.key}',
        maximum: 512,
      ),
  };
}

void _validateProjectedEvent(CockpitRunEvent event, _ProjectedRun run) {
  if (event.projectId != run.projectId) {
    throw const FormatException('Published event changes run ownership.');
  }
  if (event.caseId case final caseId?) run.caseIds.add(caseId);
}

bool _sameJson(Map<String, Object?> left, Map<String, Object?> right) =>
    jsonEncode(left) == jsonEncode(right);

bool _sameStringMap(Map<String, String> left, Map<String, String> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

String _eventDigest(CockpitRunEvent event) =>
    sha256.convert(utf8.encode(jsonEncode(event.toJson()))).toString();

bool _validSha256(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

bool _eventOwnerBelongsToRun(String owner, String runId) {
  final separator = owner.lastIndexOf(':');
  return separator > 0 && owner.substring(0, separator) == runId;
}

String _artifactKind(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r' +'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join();
  if (normalized.isEmpty) return 'attempt.artifact';
  return 'attempt.'
      '${normalized.substring(0, 1).toLowerCase()}${normalized.substring(1)}';
}
