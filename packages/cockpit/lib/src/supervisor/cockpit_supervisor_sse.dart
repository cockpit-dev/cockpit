import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_supervisor_run_event_source.dart';

final class CockpitSupervisorSse {
  const CockpitSupervisorSse(
    this.runtime, {
    this.heartbeatInterval = const Duration(seconds: 15),
    this.pollInterval = const Duration(milliseconds: 100),
  });

  final CockpitSupervisorRunEventSource runtime;
  final Duration heartbeatInterval;
  final Duration pollInterval;

  Future<void> stream(HttpRequest request, String runId) async {
    final after = await _resumeSequence(request, runId);
    var replay = await runtime.events(runId, after);
    if (replay.hasGap) throw _gap(replay.boundary!);

    request.response.statusCode = HttpStatus.ok;
    request.response.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform')
      ..set(HttpHeaders.connectionHeader, 'keep-alive')
      ..set('X-Accel-Buffering', 'no');

    var sequence = after;
    var heartbeatAt = DateTime.now().add(heartbeatInterval);
    try {
      while (true) {
        if (replay.hasGap) {
          request.response.write(
            'event: gap\ndata: ${jsonEncode(replay.boundary!.toJson())}\n\n',
          );
          await request.response.flush();
          return;
        }
        var terminal = false;
        for (final event in replay.events) {
          request.response.write(
            'id: ${event.eventId}\n'
            'event: ${event.kind}\n'
            'data: ${jsonEncode(event.toJson())}\n\n',
          );
          sequence = event.sequence;
          terminal =
              terminal ||
              event.entityKind == CockpitRunEventEntityKind.run &&
                  event.lifecycle == CockpitRunLifecycle.completed;
        }
        if (replay.events.isNotEmpty) {
          await request.response.flush();
          heartbeatAt = DateTime.now().add(heartbeatInterval);
        }
        if (terminal) return;
        if (replay.events.isEmpty) {
          final run = await runtime.run(runId);
          if (run.lifecycle == CockpitRunLifecycle.completed) {
            replay = await runtime.events(runId, sequence);
            if (replay.hasGap) throw _gap(replay.boundary!);
            if (replay.events.isEmpty) return;
            continue;
          }
        }
        if (!DateTime.now().isBefore(heartbeatAt)) {
          request.response.write(': heartbeat\n\n');
          await request.response.flush();
          heartbeatAt = DateTime.now().add(heartbeatInterval);
        }
        await Future<void>.delayed(pollInterval);
        replay = await runtime.events(runId, sequence);
      }
    } on HttpException {
      return;
    } on SocketException {
      return;
    } finally {
      await request.response.close();
    }
  }

  Future<int> _resumeSequence(HttpRequest request, String runId) async {
    final unknown = request.uri.queryParameters.keys.toSet().difference(
      const <String>{'afterSequence'},
    );
    if (unknown.isNotEmpty) {
      throw const FormatException('Unknown event stream query parameter.');
    }
    final rawAfter = request.uri.queryParameters['afterSequence'];
    final after = rawAfter == null ? 0 : int.tryParse(rawAfter);
    if (after == null || after < 0) {
      throw const FormatException('afterSequence is invalid.');
    }
    final lastEventId = request.headers.value('Last-Event-ID');
    if (lastEventId == null) return after;
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(lastEventId)) {
      throw const FormatException('Last-Event-ID is invalid.');
    }
    final eventSequence = await runtime.sequenceForEventId(runId, lastEventId);
    if (rawAfter != null && after != eventSequence) {
      throw const FormatException(
        'Last-Event-ID and afterSequence identify different boundaries.',
      );
    }
    return eventSequence;
  }

  CockpitApiException _gap(CockpitEventReplayBoundary boundary) =>
      CockpitApiException(
        CockpitApiError(
          code: CockpitErrorCode.staleReference,
          category: CockpitErrorCategory.invalidInput,
          message: 'Requested event sequence is outside retained history.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
          redactedDetails: <String, Object?>{
            'replayBoundary': boundary.toJson(),
          },
        ),
      );
}
