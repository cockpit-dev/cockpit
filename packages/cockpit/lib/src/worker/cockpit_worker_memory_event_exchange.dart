import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_worker_protocol_request.dart';
import 'cockpit_worker_protocol_result.dart';
import 'cockpit_worker_server.dart';

final class CockpitWorkerMemoryEventExchange
    implements CockpitWorkerEventExchange, CockpitWorkerArtifactExchange {
  CockpitWorkerMemoryEventExchange({
    this.maximumRuns = 1024,
    this.maximumEventsPerRun = 4096,
    this.maximumArtifactsPerRun = 4096,
  }) {
    if (maximumRuns < 1 ||
        maximumRuns > 16384 ||
        maximumEventsPerRun < 256 ||
        maximumEventsPerRun > 65536 ||
        maximumArtifactsPerRun < 1 ||
        maximumArtifactsPerRun > 65536) {
      throw ArgumentError('Worker event memory bounds are invalid.');
    }
  }

  final int maximumRuns;
  final int maximumEventsPerRun;
  final int maximumArtifactsPerRun;
  final Map<String, List<CockpitRunEvent>> _events =
      <String, List<CockpitRunEvent>>{};
  final Map<String, Map<String, CockpitArtifactResource>> _artifacts =
      <String, Map<String, CockpitArtifactResource>>{};
  final Map<String, String> _artifactOwners = <String, String>{};

  @override
  Future<CockpitWorkerPublishEventBatchResult> publish(
    CockpitWorkerPublishEventBatchRequest request,
  ) async {
    final existing = _events[request.runId];
    if (existing == null && _events.length >= maximumRuns) {
      throw const FormatException('Worker event run bound was exceeded.');
    }
    final events = existing ?? <CockpitRunEvent>[];
    final highest = events.isEmpty ? 0 : events.last.sequence;
    if (request.afterSequence > highest) {
      return CockpitWorkerPublishEventBatchResult(
        runId: request.runId,
        highestContiguousSequence: highest,
        terminal: false,
        replayAfterSequence: highest,
      );
    }
    for (final event in request.events) {
      if (event.sequence <= events.length) {
        final persisted = events[event.sequence - 1];
        if (jsonEncode(persisted.toJson()) != jsonEncode(event.toJson())) {
          throw const FormatException(
            'Published event conflicts with an existing sequence.',
          );
        }
        continue;
      }
      final expected = events.length + 1;
      if (event.sequence != expected) {
        return CockpitWorkerPublishEventBatchResult(
          runId: request.runId,
          highestContiguousSequence: events.length,
          terminal: false,
          replayAfterSequence: events.length,
        );
      }
      if (events.length >= maximumEventsPerRun) {
        throw const FormatException('Worker event run bound was exceeded.');
      }
      events.add(event);
    }
    _events[request.runId] = events;
    return CockpitWorkerPublishEventBatchResult(
      runId: request.runId,
      highestContiguousSequence: events.length,
      terminal: false,
    );
  }

  @override
  Future<CockpitWorkerReplayEventsResult> replay(
    CockpitWorkerReplayEventsRequest request,
  ) async {
    final events = _events[request.runId] ?? const <CockpitRunEvent>[];
    final start = request.afterSequence.clamp(0, events.length);
    final end = (start + 256).clamp(start, events.length);
    return CockpitWorkerReplayEventsResult(
      runId: request.runId,
      afterSequence: request.afterSequence,
      events: events.sublist(start, end),
    );
  }

  @override
  Future<CockpitWorkerPublishArtifactBatchResult> publishArtifacts(
    CockpitWorkerPublishArtifactBatchRequest request,
  ) async {
    final existing = _artifacts[request.runId];
    if (existing == null && _artifacts.length >= maximumRuns) {
      throw const FormatException('Worker artifact run bound was exceeded.');
    }
    final artifacts = existing ?? <String, CockpitArtifactResource>{};
    for (final artifact in request.artifacts) {
      final owner = _artifactOwners[artifact.artifactId];
      if (owner != null && owner != request.runId) {
        throw const FormatException('Global artifact id is not unique.');
      }
      final persisted = artifacts[artifact.artifactId];
      if (persisted != null) {
        if (jsonEncode(persisted.toJson()) != jsonEncode(artifact.toJson())) {
          throw const FormatException(
            'Published artifact conflicts with its existing id.',
          );
        }
        continue;
      }
      if (artifacts.length >= maximumArtifactsPerRun) {
        throw const FormatException('Worker artifact run bound was exceeded.');
      }
      artifacts[artifact.artifactId] = artifact;
      _artifactOwners[artifact.artifactId] = request.runId;
    }
    _artifacts[request.runId] = artifacts;
    return CockpitWorkerPublishArtifactBatchResult(
      runId: request.runId,
      artifactIds: request.artifacts.map((artifact) => artifact.artifactId),
    );
  }
}
