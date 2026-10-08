import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_interaction_recording_service.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'interaction recording service executes recorder operations for supervised sessions',
    () async {
      final session = CockpitInteractionRecordingSession(
        sessionId: 'r1',
        phase: CockpitRecorderPhase.recording,
        startedAt: DateTime.utc(2026, 10, 7, 9),
        stepCount: 2,
      ).toJson();
      final calls = <(String, Map<String, Object?>)>[];
      final service = CockpitInteractionRecordingService.forOperations(
        sessionId: 'session-1',
        execute: (kind, input) async {
          calls.add((kind, input));
          return _succeeded(kind, switch (kind) {
            'recorder.steps' => const <String, Object?>{
              'steps': <Object?>[],
              'total': 2,
            },
            'recorder.export' => <String, Object?>{
              'session': session,
              'steps': const <Object?>[],
              'caseDocument': const <String, Object?>{
                'id': 'recorded-r1',
                'schemaVersion': 'cockpit.test/v2',
              },
              'caseYaml': 'schemaVersion: cockpit.test/v2\nid: recorded-r1\n',
            },
            _ => session,
          });
        },
      );

      expect((await service.start(name: 'checkout flow'))['sessionId'], 'r1');
      await service.pause();
      await service.resume();
      expect((await service.status())['phase'], 'recording');
      expect((await service.steps(after: 2))['total'], 2);
      expect((await service.export()).caseYaml, contains('id: recorded-r1'));
      await service.stop();

      expect(calls.map((call) => call.$1), const <String>[
        'recorder.start',
        'recorder.pause',
        'recorder.resume',
        'recorder.get',
        'recorder.steps',
        'recorder.export',
        'recorder.stop',
      ]);
      // Every operation is session-scoped; optional inputs only travel when
      // they carry a value.
      for (final call in calls) {
        expect(call.$2['sessionId'], 'session-1', reason: call.$1);
      }
      expect(calls.first.$2, <String, Object?>{
        'sessionId': 'session-1',
        'name': 'checkout flow',
      });
      expect(calls[4].$2, <String, Object?>{
        'sessionId': 'session-1',
        'after': 2,
      });
      await service.start();
      expect(calls.last.$2, const <String, Object?>{
        'sessionId': 'session-1',
      }, reason: 'an unnamed start sends no name key');
    },
  );

  test(
    'interaction recording service surfaces recorder operation failures',
    () async {
      var result = _failed(
        'recorder.pause',
        'serverError',
        'Cannot pause while idle.',
      );
      final service = CockpitInteractionRecordingService.forOperations(
        sessionId: 'session-1',
        execute: (kind, input) async => result,
      );

      await expectLater(
        service.pause(),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'serverError')
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('session-1'),
                  contains('Cannot pause while idle.'),
                ),
              )
              .having(
                (error) => error.details,
                'details',
                containsPair('kind', 'recorder.pause'),
              ),
        ),
      );

      // A result that never completed (still running, no outcome, no failure)
      // fails with the bare did-not-complete message.
      result = CockpitOperationResult(
        operationId: 'operation-recorder-get',
        kind: 'recorder.get',
        lifecycle: CockpitOperationLifecycle.running,
        submittedAt: DateTime.now().toUtc(),
        startedAt: DateTime.now().toUtc(),
        workspaceId: 'workspace-1',
      );
      await expectLater(
        service.status(),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'recorderOperationFailed')
              .having(
                (error) => error.message,
                'message',
                contains('did not complete'),
              ),
        ),
      );
    },
  );

  test(
    'interaction recording service validates the steps cursor before invoking',
    () async {
      var invoked = false;
      final service = CockpitInteractionRecordingService.forOperations(
        sessionId: 'session-1',
        execute: (kind, input) async {
          invoked = true;
          return _succeeded(kind, const <String, Object?>{});
        },
      );

      expect(() => service.steps(after: -1), throwsFormatException);
      expect(() => service.steps(after: 1000001), throwsFormatException);
      expect(invoked, isFalse);
      await service.steps();
      expect(invoked, isTrue);
    },
  );

  test(
    'interaction recording service drives a live recorder endpoint',
    () async {
      Object? startBody;
      final steps = <CockpitInteractionStep>[
        CockpitInteractionStep(
          stepId: 's1',
          kind: CockpitInteractionStepKind.tap,
          locatorCandidates: <CockpitLocatorCandidate>[
            CockpitLocatorCandidate(
              kind: 'key',
              selector: CockpitSelector.format(
                const CockpitLocator(key: 'save'),
              ),
              score: 4,
            ),
          ],
          phase: CockpitRecorderPhase.recording,
          recordedAt: DateTime.utc(2026, 10, 7, 9),
        ),
        CockpitInteractionStep(
          stepId: 's2',
          kind: CockpitInteractionStepKind.tap,
          locatorCandidates: <CockpitLocatorCandidate>[
            CockpitLocatorCandidate(
              kind: 'key',
              selector: CockpitSelector.format(
                const CockpitLocator(key: 'submit'),
              ),
              score: 4,
            ),
          ],
          phase: CockpitRecorderPhase.recording,
          recordedAt: DateTime.utc(2026, 10, 7, 9, 0, 30),
        ),
      ];
      CockpitInteractionRecordingSession session(
        CockpitRecorderPhase phase, {
        String? pausedAt,
      }) => CockpitInteractionRecordingSession(
        sessionId: 'r1',
        phase: phase,
        startedAt: DateTime.utc(2026, 10, 7, 9),
        pausedAt: pausedAt == null ? null : DateTime.utc(2026, 10, 7, 9, 1),
        stepCount: steps.length,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('POST', '/recorder/start'):
            startBody = jsonDecode(await utf8.decoder.bind(request).join());
            request.response.write(
              jsonEncode(session(CockpitRecorderPhase.recording).toJson()),
            );
          case ('POST', '/recorder/pause'):
            request.response.write(
              jsonEncode(
                session(CockpitRecorderPhase.paused, pausedAt: 'x').toJson(),
              ),
            );
          case ('POST', '/recorder/resume'):
            request.response.write(
              jsonEncode(session(CockpitRecorderPhase.recording).toJson()),
            );
          case ('POST', '/recorder/stop'):
            request.response.write(
              jsonEncode(
                CockpitInteractionRecordingResult(
                  session: session(CockpitRecorderPhase.stopped),
                  steps: steps,
                ).toJson(),
              ),
            );
          case ('GET', '/recorder/session'):
            request.response.write(
              jsonEncode(session(CockpitRecorderPhase.recording).toJson()),
            );
          case ('GET', '/recorder/steps'):
            final after = int.parse(
              request.uri.queryParameters['after'] ?? '0',
            );
            request.response.write(
              jsonEncode(<String, Object?>{
                'steps': steps
                    .skip(after)
                    .map((step) => step.toJson())
                    .toList(),
                'total': steps.length,
              }),
            );
          case ('GET', '/recorder/export'):
            request.response.write(
              jsonEncode(
                CockpitRecordedFlowBundle(
                  session: session(CockpitRecorderPhase.recording),
                  steps: steps,
                  caseDocument: const <String, Object?>{
                    'id': 'recorded-r1',
                    'schemaVersion': 'cockpit.test/v2',
                  },
                  caseYaml: 'schemaVersion: cockpit.test/v2\nid: recorded-r1\n',
                ).toJson(),
              ),
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final service = CockpitInteractionRecordingService.forBaseUri(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final started = await service.start(name: 'checkout flow');
      expect(started['sessionId'], 'r1');
      expect(started['phase'], 'recording');
      expect(startBody, <String, Object?>{'name': 'checkout flow'});

      final paused = await service.pause();
      expect(paused['phase'], 'paused');
      final resumed = await service.resume();
      expect(resumed['phase'], 'recording');

      final status = await service.status();
      expect(status['sessionId'], 'r1');
      expect(status['stepCount'], steps.length);

      final page = await service.steps(after: 1);
      expect(page['total'], steps.length);
      expect(
        (page['steps']! as List<Object?>).map(
          (step) => (step as Map<String, Object?>)['stepId'],
        ),
        <String>['s2'],
      );

      final bundle = await service.export();
      final yaml = service.exportDocument(bundle);
      expect(yaml['format'], 'yaml');
      expect(yaml['document'], bundle.caseYaml);
      expect(yaml['document'], contains('id: recorded-r1'));
      final json = service.exportDocument(bundle, format: 'json');
      expect(json['format'], 'json');
      expect(json['document'], bundle.toJson());

      final stopped = await service.stop();
      expect((stopped['session']! as Map<String, Object?>)['phase'], 'stopped');
      expect(stopped['steps'], hasLength(steps.length));
    },
  );

  test('interaction recording service reports the idle session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(const <String, Object?>{'phase': 'idle'}),
      );
      await request.response.close();
    });

    final service = CockpitInteractionRecordingService.forBaseUri(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );

    expect(await service.status(), <String, Object?>{'phase': 'idle'});
  });

  test(
    'interaction recording service shapes every payload it returns',
    () async {
      final requestBodies = <String, Map<String, Object?>>{};
      final tokens = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final token = request.headers.value('x-cockpit-token');
        if (token != null) {
          tokens.add(token);
        }
        switch ((request.method, request.uri.path)) {
          case ('POST', '/recorder/start'):
            requestBodies['start'] = Map<String, Object?>.from(
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<Object?, Object?>,
            );
            request.response.write(
              jsonEncode(
                CockpitInteractionRecordingSession(
                  sessionId: 'r1',
                  phase: CockpitRecorderPhase.recording,
                  startedAt: DateTime.utc(2026, 10, 7, 9),
                  pausedAt: DateTime.utc(2026, 10, 7, 9, 1),
                  stepCount: 2,
                  unresolvedCount: 1,
                ).toJson(),
              ),
            );
          case ('GET', '/recorder/session'):
            request.response.write(
              jsonEncode(
                CockpitInteractionRecordingSession(
                  sessionId: 'r1',
                  phase: CockpitRecorderPhase.recording,
                  startedAt: DateTime.utc(2026, 10, 7, 9),
                  pausedAt: DateTime.utc(2026, 10, 7, 9, 1),
                  stepCount: 2,
                  unresolvedCount: 1,
                ).toJson(),
              ),
            );
          case ('GET', '/recorder/steps'):
            // A cursor at (or beyond) the total drains to an empty page that
            // still reports the full count as the next cursor.
            request.response.write(
              jsonEncode(const <String, Object?>{
                'steps': <Object?>[],
                'total': 2,
              }),
            );
          case ('GET', '/recorder/export'):
            request.response.write(
              jsonEncode(
                CockpitRecordedFlowBundle(
                  session: CockpitInteractionRecordingSession(
                    sessionId: 'r1',
                    phase: CockpitRecorderPhase.recording,
                    startedAt: DateTime.utc(2026, 10, 7, 9),
                    stepCount: 2,
                  ),
                  steps: const <CockpitInteractionStep>[],
                  caseDocument: const <String, Object?>{
                    'id': 'recorded-r1',
                    'schemaVersion': 'cockpit.test/v2',
                  },
                  caseYaml: 'schemaVersion: cockpit.test/v2\nid: recorded-r1\n',
                ).toJson(),
              ),
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final service = CockpitInteractionRecordingService.forBaseUri(
        Uri.parse('http://127.0.0.1:${server.port}'),
        authToken: 'bridge-token-1',
      );

      // An unnamed start sends an empty request body; the wired bridge token
      // travels as the x-cockpit-token header.
      final started = await service.start();
      expect(requestBodies['start'], <String, Object?>{});
      expect(tokens, const <String>['bridge-token-1']);
      expect(started.keys, const <String>{
        'sessionId',
        'phase',
        'startedAt',
        'pausedAt',
        'stepCount',
        'unresolvedCount',
      });

      // The active status mirrors the session payload; the idle status is the
      // minimal phase-only payload.
      expect((await service.status()).keys, started.keys);

      // A drained cursor page reports an empty step list with the total.
      expect(await service.steps(after: 2), const <String, Object?>{
        'steps': <Object?>[],
        'total': 2,
      });

      // The JSON export document is the complete flow bundle, not just the
      // case document.
      final bundle = await service.export();
      final json = service.exportDocument(bundle, format: 'json');
      expect(json['format'], 'json');
      final document = json['document']! as Map<String, Object?>;
      expect(document.keys, const <String>{
        'session',
        'steps',
        'caseDocument',
        'caseYaml',
      });
      expect(document, bundle.toJson());
      expect(
        (document['caseDocument']! as Map<String, Object?>)['id'],
        'recorded-r1',
      );
    },
  );
}

CockpitOperationResult _succeeded(String kind, Map<String, Object?> output) {
  final now = DateTime.now().toUtc();
  return CockpitOperationResult(
    operationId: 'operation-$kind',
    kind: kind,
    lifecycle: CockpitOperationLifecycle.completed,
    outcome: CockpitOperationOutcome.succeeded,
    submittedAt: now,
    startedAt: now,
    finishedAt: now,
    workspaceId: 'workspace-1',
    output: output,
  );
}

CockpitOperationResult _failed(String kind, String code, String message) {
  final now = DateTime.now().toUtc();
  return CockpitOperationResult(
    operationId: 'operation-$kind',
    kind: kind,
    lifecycle: CockpitOperationLifecycle.completed,
    outcome: CockpitOperationOutcome.failed,
    submittedAt: now,
    startedAt: now,
    finishedAt: now,
    workspaceId: 'workspace-1',
    failure: CockpitFailure(
      primary: CockpitApiError(
        code: code,
        category: CockpitErrorCategory.application,
        message: message,
        retryable: false,
        responsibleLayer: CockpitResponsibleLayer.application,
      ),
    ),
  );
}
