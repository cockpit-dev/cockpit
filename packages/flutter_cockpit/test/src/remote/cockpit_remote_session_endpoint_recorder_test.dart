import 'dart:io';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/remote/cockpit_remote_session_endpoint_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recorder endpoints drive a full session lifecycle', () async {
    final recorder = CockpitInteractionRecorder();
    final handler = _handler(recorderProvider: () => recorder);

    final started = await _post(handler, '/recorder/start', {
      'name': 'demo flow',
    });
    expect(started.statusCode, HttpStatus.ok);
    expect(started.jsonBody, containsPair('phase', 'recording'));
    expect(started.jsonBody, containsPair('sessionId', 'r1'));

    recorder.recordInteractionStep(_tapStep('save'));

    final steps = await _get(handler, '/recorder/steps?after=0');
    expect(steps.statusCode, HttpStatus.ok);
    expect(steps.jsonBody?['total'], 1);
    expect(
      (steps.jsonBody?['steps'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .single['stepId'],
      's1',
    );

    final paused = await _post(handler, '/recorder/pause');
    expect(paused.jsonBody, containsPair('phase', 'paused'));
    expect(paused.jsonBody, containsPair('pausedAt', isNotNull));

    final resumed = await _post(handler, '/recorder/resume');
    expect(resumed.jsonBody, containsPair('phase', 'recording'));

    recorder.recordInteractionStep(_tapStep('submit'));
    final nextSteps = await _get(handler, '/recorder/steps?after=1');
    expect(nextSteps.jsonBody?['total'], 2);
    expect(
      (nextSteps.jsonBody?['steps'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .single['stepId'],
      's2',
    );

    final exported = await _get(handler, '/recorder/export');
    expect(exported.statusCode, HttpStatus.ok);
    expect(exported.jsonBody?['caseYaml'], isNotEmpty);
    expect(
      (exported.jsonBody?['caseDocument'] as Map<String, Object?>)['id'],
      'recorded-r1',
    );

    final stopped = await _post(handler, '/recorder/stop');
    expect(stopped.statusCode, HttpStatus.ok);
    expect(
      (stopped.jsonBody?['session'] as Map<String, Object?>)['phase'],
      'stopped',
    );
    expect(
      stopped.jsonBody?['steps'],
      isA<List<Object?>>().having((steps) => steps.length, 'length', 2),
    );

    final session = await _get(handler, '/recorder/session');
    expect((session.jsonBody as Map<String, Object?>)['phase'], 'stopped');
  });

  test('recorder start accepts an empty body as the default request', () async {
    final recorder = CockpitInteractionRecorder();
    final handler = _handler(recorderProvider: () => recorder);

    final response = await _post(handler, '/recorder/start');

    expect(response.statusCode, HttpStatus.ok);
    expect(response.jsonBody, containsPair('phase', 'recording'));
    expect(recorder.sessionName, isNull);
  });

  test(
    'recorder session answers an idle payload before the first start',
    () async {
      final handler = _handler(
        recorderProvider: () => CockpitInteractionRecorder(),
      );

      final response = await _get(handler, '/recorder/session');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.jsonBody, <String, Object?>{'phase': 'idle'});
    },
  );

  test('recorder endpoints report 404 without a wired recorder', () async {
    for (final handler in <CockpitRemoteSessionEndpointHandler>[
      _handler(),
      _handler(recorderProvider: () => null),
    ]) {
      final started = await _post(handler, '/recorder/start');
      expect(started.statusCode, HttpStatus.notFound);
      expect(started.jsonBody?['error'], 'notFound');

      final session = await _get(handler, '/recorder/session');
      expect(session.statusCode, HttpStatus.notFound);
      expect(session.jsonBody?['error'], 'notFound');

      // Every recorder route answers 404 the same way.
      for (final path in <String>[
        '/recorder/pause',
        '/recorder/resume',
        '/recorder/stop',
      ]) {
        final response = await _post(handler, path);
        expect(response.statusCode, HttpStatus.notFound, reason: path);
        expect(response.jsonBody?['error'], 'notFound', reason: path);
      }
      for (final path in <String>[
        '/recorder/steps',
        '/recorder/steps?after=0',
        '/recorder/export',
      ]) {
        final response = await _get(handler, path);
        expect(response.statusCode, HttpStatus.notFound, reason: path);
        expect(response.jsonBody?['error'], 'notFound', reason: path);
      }
    }
  });

  test('recorder endpoints reject unknown subroutes', () async {
    final handler = _handler(
      recorderProvider: () => CockpitInteractionRecorder(),
    );

    final response = await _post(handler, '/recorder/rewind');

    expect(response.statusCode, HttpStatus.notFound);
    expect(response.jsonBody?['error'], 'notFound');
  });

  test('recorder steps reject malformed and stale cursors', () async {
    final recorder = CockpitInteractionRecorder();
    final handler = _handler(recorderProvider: () => recorder);

    final malformed = await _get(handler, '/recorder/steps?after=soon');
    expect(malformed.statusCode, HttpStatus.badRequest);
    expect(malformed.jsonBody?['error'], 'invalidPayload');

    final fraction = await _get(handler, '/recorder/steps?after=1.5');
    expect(fraction.statusCode, HttpStatus.badRequest);
    expect(fraction.jsonBody?['error'], 'invalidPayload');

    final negative = await _get(handler, '/recorder/steps?after=-1');
    expect(negative.statusCode, HttpStatus.badRequest);

    final stale = await _get(handler, '/recorder/steps?after=3');
    expect(stale.statusCode, HttpStatus.badRequest);
    expect(
      stale.jsonBody?['message'],
      contains('must not exceed the recorded step count'),
    );
  });

  test(
    'recorder steps answer an exhausted cursor with an empty list',
    () async {
      final recorder = CockpitInteractionRecorder();
      final handler = _handler(recorderProvider: () => recorder);
      recorder.start();
      recorder.recordInteractionStep(_tapStep('save'));

      // after == total: the client consumed everything; still 200 with the
      // authoritative total so the cursor stays stateless.
      final response = await _get(handler, '/recorder/steps?after=1');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.jsonBody?['total'], 1);
      expect(
        (response.jsonBody?['steps'] as List<Object?>?) ?? <Object?>[],
        isEmpty,
      );
    },
  );

  test('recorder steps reject a cursor the session shrank below', () async {
    // discardLastStep can shrink the list below a cursor the client already
    // holds; the endpoint must reject it as stale (400), never re-send.
    final recorder = CockpitInteractionRecorder();
    final handler = _handler(recorderProvider: () => recorder);
    recorder.start();
    recorder.recordInteractionStep(_tapStep('save'));
    recorder.recordInteractionStep(_tapStep('submit'));
    recorder.discardLastStep();

    final response = await _get(handler, '/recorder/steps?after=2');

    expect(response.statusCode, HttpStatus.badRequest);
    expect(response.jsonBody?['error'], 'invalidPayload');
    expect(
      response.jsonBody?['message'],
      contains('must not exceed the recorded step count (1)'),
    );
  });

  test(
    'recorder export with nothing exportable answers the error envelope',
    () async {
      final recorder = CockpitInteractionRecorder();
      final handler = _handler(recorderProvider: () => recorder);
      recorder.start();
      // An unresolved step is not exportable: the converter throws
      // ArgumentError, which surfaces through the 500 serverError envelope.
      recorder.recordInteractionStep(_unresolvedStep());

      final response = await _get(handler, '/recorder/export');

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.jsonBody?['error'], 'serverError');
      expect(
        response.jsonBody?['message'],
        isA<String>().having((message) => message.isEmpty, 'isEmpty', isFalse),
      );
    },
  );

  test('recorder double start answers the error envelope', () async {
    final recorder = CockpitInteractionRecorder();
    final handler = _handler(recorderProvider: () => recorder);

    final first = await _post(handler, '/recorder/start');
    expect(first.statusCode, HttpStatus.ok);

    final second = await _post(handler, '/recorder/start');
    expect(second.statusCode, HttpStatus.internalServerError);
    expect(second.jsonBody?['error'], 'serverError');
    expect(second.jsonBody?['message'], contains('Cannot start'));
  });

  test('recorder start rejects invalid request bodies', () async {
    final handler = _handler(
      recorderProvider: () => CockpitInteractionRecorder(),
    );

    final response = await _post(handler, '/recorder/start', {'name': 42});

    expect(response.statusCode, HttpStatus.badRequest);
    expect(response.jsonBody?['error'], 'invalidPayload');
  });

  test('recorder phase violations surface as server errors', () async {
    final recorder = CockpitInteractionRecorder();
    final handler = _handler(recorderProvider: () => recorder);

    final pause = await _post(handler, '/recorder/pause');
    expect(pause.statusCode, HttpStatus.internalServerError);
    expect(pause.jsonBody?['error'], 'serverError');
    expect(pause.jsonBody?['message'], contains('Cannot pause'));

    final export = await _get(handler, '/recorder/export');
    expect(export.statusCode, HttpStatus.internalServerError);
    expect(export.jsonBody?['error'], 'serverError');
  });
}

Future<CockpitRemoteSessionEndpointResponse> _post(
  CockpitRemoteSessionEndpointHandler handler,
  String path, [
  Map<String, Object?>? body,
]) {
  return handler.handle(
    CockpitRemoteSessionEndpointRequest(
      method: 'POST',
      uri: Uri.parse(path),
      jsonBody: body ?? const <String, Object?>{},
    ),
  );
}

Future<CockpitRemoteSessionEndpointResponse> _get(
  CockpitRemoteSessionEndpointHandler handler,
  String path,
) {
  return handler.handle(
    CockpitRemoteSessionEndpointRequest(method: 'GET', uri: Uri.parse(path)),
  );
}

CockpitRemoteSessionEndpointHandler _handler({
  CockpitRemoteInteractionRecorderProvider? recorderProvider,
}) => CockpitRemoteSessionEndpointHandler(
  configuration: const CockpitRemoteSessionConfiguration(
    enabled: true,
    autoStart: false,
    port: 0,
  ),
  statusProvider: () async => throw StateError('unused'),
  snapshotProvider: ({required options}) async => throw StateError('unused'),
  commandExecutor: (_) async => throw StateError('unused'),
  startRecording: (_) async => throw StateError('unused'),
  stopRecording: () async => throw StateError('unused'),
  recorderProvider: recorderProvider,
);

CockpitInteractionStep _tapStep(String key) => CockpitInteractionStep(
  stepId: 'pending',
  kind: CockpitInteractionStepKind.tap,
  locatorCandidates: <CockpitLocatorCandidate>[
    CockpitLocatorCandidate(
      kind: 'key',
      selector: CockpitSelector.format(CockpitLocator(key: key)),
      score: 4,
    ),
  ],
  phase: CockpitRecorderPhase.recording,
  recordedAt: DateTime.utc(2026, 10, 7, 9),
);

CockpitInteractionStep _unresolvedStep() => CockpitInteractionStep(
  stepId: 'pending',
  kind: CockpitInteractionStepKind.tap,
  unresolved: true,
  phase: CockpitRecorderPhase.recording,
  recordedAt: DateTime.utc(2026, 10, 7, 9),
);
