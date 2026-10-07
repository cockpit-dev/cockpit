import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_interaction_recording_service.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('recorder base-uri resolution reads the ready bridge', () {
    final uri = cockpitInteractionRecorderBaseUri(const <String, Object?>{
      'sessionId': 'session-1',
      'status': <String, Object?>{
        'state': 'ready',
        'appReachable': true,
        'remoteSessionReachable': true,
      },
      'runtime': <String, Object?>{
        'bridge': <String, Object?>{'baseUrl': 'http://127.0.0.1:43117'},
      },
    });

    expect(uri, Uri.parse('http://127.0.0.1:43117'));
  });

  test('recorder base-uri resolution rejects unusable sessions', () {
    Matcher unavailable() => isA<CockpitApplicationServiceException>()
        .having(
          (error) => error.code,
          'code',
          'developmentSessionBridgeUnavailable',
        )
        .having((error) => error.message, 'message', contains('dev start'));

    expect(
      () => cockpitInteractionRecorderBaseUri(null),
      throwsA(unavailable()),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(<String, Object?>{
        'status': <String, Object?>{
          'state': 'connecting',
          'appReachable': true,
          'remoteSessionReachable': false,
        },
        'runtime': <String, Object?>{
          'bridge': <String, Object?>{'baseUrl': 'http://127.0.0.1:43117'},
        },
      }),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having(
              (error) => error.code,
              'code',
              'developmentSessionBridgeUnavailable',
            )
            .having(
              (error) => error.details,
              'details',
              containsPair('state', 'connecting'),
            ),
      ),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(<String, Object?>{
        'status': <String, Object?>{
          'state': 'ready',
          'appReachable': true,
          'remoteSessionReachable': true,
        },
      }),
      throwsA(unavailable()),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(<String, Object?>{
        'status': <String, Object?>{
          'state': 'ready',
          'appReachable': true,
          'remoteSessionReachable': true,
        },
        'runtime': <String, Object?>{
          'bridge': <String, Object?>{'baseUrl': ''},
        },
      }),
      throwsA(unavailable()),
    );
  });

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
}
