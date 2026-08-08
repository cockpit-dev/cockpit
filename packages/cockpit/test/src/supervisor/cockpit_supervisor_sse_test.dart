import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/supervisor/cockpit_supervisor_run_event_source.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_run_projection.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_sse.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'SSE refreshes replay when a run completes after the first read',
    () async {
      final source = _CompletingRunEventSource();
      final sse = CockpitSupervisorSse(
        source,
        pollInterval: const Duration(milliseconds: 1),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final served = Completer<void>();
      final subscription = server.listen((request) {
        unawaited(
          sse
              .stream(request, 'runA')
              .then((_) => served.complete(), onError: served.completeError),
        );
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/events?afterSequence=0'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      await served.future;

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(body, contains('event: run.completed'));
      expect(body, contains('"sequence":1'));
      expect(source.eventReads, 2);
    },
  );
}

final class _CompletingRunEventSource
    implements CockpitSupervisorRunEventSource {
  final terminalEvent = CockpitRunEvent(
    eventId: 'eventA',
    sequence: 1,
    timestamp: DateTime.utc(2026, 8, 7),
    kind: 'run.completed',
    entityKind: CockpitRunEventEntityKind.run,
    projectId: 'projectA',
    workspaceId: 'workspaceA',
    runId: 'runA',
    lifecycle: CockpitRunLifecycle.completed,
    outcome: CockpitRunOutcome.passed,
    stability: CockpitRunStability.stable,
  );

  int eventReads = 0;

  @override
  Future<CockpitSupervisorEventReplay> events(
    String runId,
    int afterSequence,
  ) async {
    eventReads += 1;
    return CockpitSupervisorEventReplay(
      boundary: null,
      events: eventReads == 1
          ? const <CockpitRunEvent>[]
          : <CockpitRunEvent>[terminalEvent],
    );
  }

  @override
  Future<CockpitRunResource> run(String runId) async => CockpitRunResource(
    projectId: 'projectA',
    workspaceId: 'workspaceA',
    runId: 'runA',
    documentKind: CockpitRunDocumentKind.testCase,
    documentId: 'caseA',
    sourceSha256:
        '0000000000000000000000000000000000000000000000000000000000000000',
    lifecycle: CockpitRunLifecycle.completed,
    outcome: CockpitRunOutcome.passed,
    stability: CockpitRunStability.stable,
    submittedAt: DateTime.utc(2026, 8, 7),
    startedAt: DateTime.utc(2026, 8, 7, 0, 0, 1),
    finishedAt: DateTime.utc(2026, 8, 7, 0, 0, 2),
    caseIds: const <String>['caseA'],
  );

  @override
  Future<int> sequenceForEventId(String runId, String eventId) async => 1;
}
