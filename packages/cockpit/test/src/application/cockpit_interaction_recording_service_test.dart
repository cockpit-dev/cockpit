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
