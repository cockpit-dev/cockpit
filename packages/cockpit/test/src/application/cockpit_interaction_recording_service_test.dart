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

  test('recorder base-uri resolution rejects every malformed output shape', () {
    // A ready status so only the shape under test can flip the verdict.
    Map<String, Object?> readyStatus({
      Object? state = 'ready',
      Object? appReachable = true,
      Object? remoteSessionReachable = true,
    }) => <String, Object?>{
      'state': state,
      'appReachable': appReachable,
      'remoteSessionReachable': remoteSessionReachable,
    };
    Map<String, Object?> output({
      Object? status,
      Object? runtime,
      Object? bridge,
      Object? baseUrl,
    }) => <String, Object?>{
      'status': ?status,
      'runtime': ?runtime,
      if (bridge != null)
        'runtime': <String, Object?>{'bridge': bridge}
      else if (baseUrl != null)
        'runtime': <String, Object?>{
          'bridge': <String, Object?>{'baseUrl': baseUrl},
        },
    };

    Matcher unavailableWith(Map<String, Object?> details) =>
        isA<CockpitApplicationServiceException>()
            .having(
              (error) => error.code,
              'code',
              'developmentSessionBridgeUnavailable',
            )
            .having((error) => error.details, 'details', details);

    // The status block itself is malformed or reports an unusable session.
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(status: 'ready', baseUrl: 'http://127.0.0.1:43117'),
      ),
      throwsA(unavailableWith(const <String, Object?>{})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(status: <Object?>[readyStatus()], baseUrl: 'http://127.0.0.1'),
      ),
      throwsA(unavailableWith(const <String, Object?>{})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(
          status: <String, Object?>{
            'state': 7,
            'appReachable': true,
            'remoteSessionReachable': true,
          },
          baseUrl: 'http://127.0.0.1:43117',
        ),
      ),
      throwsA(
        unavailableWith(const <String, Object?>{}),
      ), // non-string state never leaks into details
    );

    // Ready-but-unreachable combinations, one flag at a time.
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(
          status: readyStatus(appReachable: false),
          baseUrl: 'http://127.0.0.1:43117',
        ),
      ),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(
          status: readyStatus(remoteSessionReachable: false),
          baseUrl: 'http://127.0.0.1:43117',
        ),
      ),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );

    // The runtime/bridge/baseUrl chain is malformed at each link.
    expect(
      () => cockpitInteractionRecorderBaseUri(output(status: readyStatus())),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(status: readyStatus(), runtime: 'flutter'),
      ),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(status: readyStatus(), bridge: 'http://127.0.0.1:43117'),
      ),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(status: readyStatus(), baseUrl: 43117),
      ),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );
    expect(
      () => cockpitInteractionRecorderBaseUri(
        output(status: readyStatus(), baseUrl: <String, Object?>{}),
      ),
      throwsA(unavailableWith(const <String, Object?>{'state': 'ready'})),
    );
  });

  test(
    'recorder base-uri resolution reports a malformed bridge URL as unusable',
    () {
      // Regression: a bridge base URL that does not parse, or parses to
      // something that is not an absolute http(s) URL, must surface the
      // documented developmentSessionBridgeUnavailable failure instead of a
      // raw FormatException (which the CLI misreports as invalidInput and the
      // MCP tools as invalidArguments).
      Matcher unavailableFor(String baseUrl) =>
          isA<CockpitApplicationServiceException>()
              .having(
                (error) => error.code,
                'code',
                'developmentSessionBridgeUnavailable',
              )
              .having(
                (error) => error.message,
                'message',
                contains('dev start'),
              )
              .having(
                (error) => error.details,
                'details',
                containsPair('baseUrl', baseUrl),
              );

      Map<String, Object?> output(String baseUrl) => <String, Object?>{
        'status': <String, Object?>{
          'state': 'ready',
          'appReachable': true,
          'remoteSessionReachable': true,
        },
        'runtime': <String, Object?>{
          'bridge': <String, Object?>{'baseUrl': baseUrl},
        },
      };

      for (final baseUrl in const <String>[
        'http://[::1', // Uri.parse itself fails.
        ':::', // Uri.parse itself fails.
        '127.0.0.1:43117', // Parses to a scheme-less relative URI.
        '/bridge/127.0.0.1:43117', // Parses to a path-only URI.
        'ftp://127.0.0.1:43117', // Parses, but not an http(s) bridge.
      ]) {
        expect(
          () => cockpitInteractionRecorderBaseUri(output(baseUrl)),
          throwsA(unavailableFor(baseUrl)),
          reason: baseUrl,
        );
      }
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
}
