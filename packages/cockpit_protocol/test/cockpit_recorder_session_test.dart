import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitInteractionRecordingSession', () {
    test('round-trips a full paused session', () {
      final session = CockpitInteractionRecordingSession(
        sessionId: 'session-1',
        phase: CockpitRecorderPhase.paused,
        startedAt: DateTime.utc(2026, 10, 7, 9, 30),
        pausedAt: DateTime.utc(2026, 10, 7, 9, 35),
        endedAt: DateTime.utc(2026, 10, 7, 9, 40),
        stepCount: 12,
        unresolvedCount: 3,
      );
      final decoded = CockpitInteractionRecordingSession.fromJson(
        session.toJson(),
      );
      expect(decoded, session);
      expect(decoded.hashCode, session.hashCode);
      expect(decoded.phase, CockpitRecorderPhase.paused);
      expect(decoded.pausedAt, session.pausedAt);
    });

    test('round-trips a minimal idle session', () {
      final session = CockpitInteractionRecordingSession(
        sessionId: 'session-2',
        phase: CockpitRecorderPhase.idle,
        startedAt: DateTime.utc(2026, 10, 7, 9, 30),
      );
      expect(session.toJson(), <String, Object?>{
        'sessionId': 'session-2',
        'phase': 'idle',
        'startedAt': '2026-10-07T09:30:00.000Z',
        'stepCount': 0,
        'unresolvedCount': 0,
      });
      final decoded = CockpitInteractionRecordingSession.fromJson(
        session.toJson(),
      );
      expect(decoded, session);
      expect(decoded.pausedAt, isNull);
      expect(decoded.endedAt, isNull);
    });

    test('constructor rejects negative and inconsistent counts', () {
      DateTime startedAt() => DateTime.utc(2026, 10, 7, 9, 30);
      expect(
        () => CockpitInteractionRecordingSession(
          sessionId: 'session-1',
          phase: CockpitRecorderPhase.recording,
          startedAt: startedAt(),
          stepCount: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => CockpitInteractionRecordingSession(
          sessionId: 'session-1',
          phase: CockpitRecorderPhase.recording,
          startedAt: startedAt(),
          unresolvedCount: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => CockpitInteractionRecordingSession(
          sessionId: 'session-1',
          phase: CockpitRecorderPhase.recording,
          startedAt: startedAt(),
          stepCount: 2,
          unresolvedCount: 3,
        ),
        throwsArgumentError,
      );
    });

    test('fromJson reports paths for malformed payloads', () {
      expect(
        () => CockpitInteractionRecordingSession.fromJson(<String, Object?>{
          'sessionId': 'session-1',
          'startedAt': '2026-10-07T09:30:00.000Z',
          'stepCount': 0,
          'unresolvedCount': 0,
        }),
        throwsA(_formatExceptionAt(r'$.phase')),
      );
      expect(
        () => CockpitInteractionRecordingSession.fromJson(<String, Object?>{
          'sessionId': 'session-1',
          'phase': 'fastForward',
          'startedAt': '2026-10-07T09:30:00.000Z',
          'stepCount': 0,
          'unresolvedCount': 0,
        }),
        throwsA(_formatExceptionAt(r'$.phase')),
      );
      expect(
        () => CockpitInteractionRecordingSession.fromJson(<String, Object?>{
          'sessionId': 7,
          'phase': 'recording',
          'startedAt': '2026-10-07T09:30:00.000Z',
          'stepCount': 0,
          'unresolvedCount': 0,
        }),
        throwsA(_formatExceptionAt(r'$.sessionId')),
      );
      expect(
        () => CockpitInteractionRecordingSession.fromJson(<String, Object?>{
          'sessionId': 'session-1',
          'phase': 'recording',
          'startedAt': '2026-10-07T09:30:00.000Z',
          'stepCount': -2,
          'unresolvedCount': 0,
        }),
        throwsA(_formatExceptionAt(r'$.stepCount')),
      );
      expect(
        () => CockpitInteractionRecordingSession.fromJson(<String, Object?>{
          'sessionId': 'session-1',
          'phase': 'recording',
          'startedAt': '2026-10-07T09:30:00.000Z',
          'stepCount': 4,
          'unresolvedCount': 5,
        }),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CockpitInteractionRecordingSession.fromJson(<String, Object?>{
          'sessionId': 'session-1',
          'phase': 'recording',
          'startedAt': '2026-10-07T09:30:00.000',
          'stepCount': 0,
          'unresolvedCount': 0,
        }),
        throwsA(_formatExceptionAt(r'$.startedAt')),
      );
      expect(
        () => CockpitInteractionRecordingSession.fromJson('session-1'),
        throwsA(_formatExceptionAt(r'$')),
      );
    });

    test('equality distinguishes counts and phases', () {
      final base = CockpitInteractionRecordingSession(
        sessionId: 'session-1',
        phase: CockpitRecorderPhase.recording,
        startedAt: DateTime.utc(2026, 10, 7, 9, 30),
        stepCount: 4,
        unresolvedCount: 1,
      );
      expect(
        CockpitInteractionRecordingSession(
              sessionId: 'session-1',
              phase: CockpitRecorderPhase.recording,
              startedAt: DateTime.utc(2026, 10, 7, 9, 30),
              stepCount: 5,
              unresolvedCount: 1,
            ) ==
            base,
        isFalse,
      );
      expect(
        CockpitInteractionRecordingSession(
              sessionId: 'session-1',
              phase: CockpitRecorderPhase.paused,
              startedAt: DateTime.utc(2026, 10, 7, 9, 30),
              stepCount: 4,
              unresolvedCount: 1,
            ) ==
            base,
        isFalse,
      );
    });
  });

  group('CockpitInteractionRecordingRequest', () {
    test('round-trips a full request and an empty one', () {
      final full = CockpitInteractionRecordingRequest(
        name: 'checkout-flow',
        attachToStep: 's12',
      );
      final decodedFull = CockpitInteractionRecordingRequest.fromJson(
        full.toJson(),
      );
      expect(decodedFull, full);
      expect(decodedFull.hashCode, full.hashCode);
      expect(full.toJson(), <String, Object?>{
        'name': 'checkout-flow',
        'attachToStep': 's12',
      });

      const empty = CockpitInteractionRecordingRequest();
      expect(empty.toJson(), isEmpty);
      expect(
        CockpitInteractionRecordingRequest.fromJson(empty.toJson()),
        empty,
      );
    });

    test('equality distinguishes name and attachToStep', () {
      const base = CockpitInteractionRecordingRequest(name: 'flow');
      expect(
        const CockpitInteractionRecordingRequest(name: 'other') == base,
        isFalse,
      );
      expect(
        const CockpitInteractionRecordingRequest(
              name: 'flow',
              attachToStep: 's1',
            ) ==
            base,
        isFalse,
      );
    });
  });

  group('CockpitInteractionRecordingResult', () {
    test('round-trips a full result with steps', () {
      final result = CockpitInteractionRecordingResult(
        session: _session(),
        steps: <CockpitInteractionStep>[_step('s1'), _step('s2')],
      );
      final decoded = CockpitInteractionRecordingResult.fromJson(
        result.toJson(),
      );
      expect(decoded, result);
      expect(decoded.hashCode, result.hashCode);
      expect(decoded.steps, hasLength(2));
      expect(() => decoded.steps.add(_step('s3')), throwsUnsupportedError);
    });

    test('round-trips a minimal result with no steps', () {
      final result = CockpitInteractionRecordingResult(session: _session());
      final decoded = CockpitInteractionRecordingResult.fromJson(
        result.toJson(),
      );
      expect(decoded, result);
      expect(decoded.steps, isEmpty);
    });

    test('fromJson reports nested step paths for malformed payloads', () {
      final json = CockpitInteractionRecordingResult(
        session: _session(),
        steps: <CockpitInteractionStep>[_step('s1'), _step('s2')],
      ).toJson();
      (json['steps']! as List<Object?>)[1] = <String, Object?>{
        'stepId': 's2',
        'kind': 'doubleTap',
        'phase': 'stopped',
        'recordedAt': '2026-10-07T09:30:00.000Z',
      };
      expect(
        () => CockpitInteractionRecordingResult.fromJson(json),
        throwsA(_formatExceptionAt(r'$.steps[1].kind')),
      );

      final missingSteps = <String, Object?>{'session': _session().toJson()};
      expect(
        () => CockpitInteractionRecordingResult.fromJson(missingSteps),
        throwsA(_formatExceptionAt(r'$.steps')),
      );
    });
  });

  group('CockpitRecordedFlowBundle', () {
    test('round-trips a full bundle with a nested case document', () {
      final bundle = CockpitRecordedFlowBundle(
        session: _session(),
        steps: <CockpitInteractionStep>[_step('s1'), _step('s2')],
        caseDocument: _caseDocument(),
        caseYaml: 'schemaVersion: cockpit.test/v2\nsteps:\n  - tap Save\n',
      );
      final decoded = CockpitRecordedFlowBundle.fromJson(bundle.toJson());
      expect(decoded, bundle);
      expect(decoded.hashCode, bundle.hashCode);
      expect(decoded.caseDocument['steps'], isA<List<Object?>>());
      expect(
        () => decoded.caseDocument['extra'] = 'value',
        throwsUnsupportedError,
      );
    });

    test('round-trips a minimal bundle with one step', () {
      final bundle = CockpitRecordedFlowBundle(
        session: _session(),
        caseDocument: <String, Object?>{'schemaVersion': 'cockpit.test/v2'},
        caseYaml: 'schemaVersion: cockpit.test/v2\n',
      );
      final decoded = CockpitRecordedFlowBundle.fromJson(bundle.toJson());
      expect(decoded, bundle);
      expect(decoded.steps, isEmpty);
    });

    test('constructor rejects an empty case document and empty YAML', () {
      expect(
        () => CockpitRecordedFlowBundle(
          session: _session(),
          caseDocument: const <String, Object?>{},
          caseYaml: 'schemaVersion: cockpit.test/v2\n',
        ),
        throwsArgumentError,
      );
      expect(
        () => CockpitRecordedFlowBundle(
          session: _session(),
          caseDocument: _caseDocument(),
          caseYaml: '',
        ),
        throwsArgumentError,
      );
    });

    test('fromJson reports paths for malformed payloads', () {
      expect(
        () => CockpitRecordedFlowBundle.fromJson(<String, Object?>{
          'session': _session().toJson(),
          'steps': const <Object?>[],
          'caseDocument': _caseDocument(),
        }),
        throwsA(_formatExceptionAt(r'$.caseYaml')),
      );
      expect(
        () => CockpitRecordedFlowBundle.fromJson(<String, Object?>{
          'session': _session().toJson(),
          'steps': const <Object?>[],
          'caseDocument': _caseDocument(),
          'caseYaml': '',
        }),
        throwsA(_formatExceptionAt(r'$.caseYaml')),
      );
      expect(
        () => CockpitRecordedFlowBundle.fromJson(<String, Object?>{
          'session': _session().toJson(),
          'steps': const <Object?>[],
          'caseDocument': const <Object?>['step'],
          'caseYaml': 'schemaVersion: cockpit.test/v2\n',
        }),
        throwsA(_formatExceptionAt(r'$.caseDocument')),
      );
      expect(
        () => CockpitRecordedFlowBundle.fromJson(<String, Object?>{
          'session': _session().toJson(),
          'steps': 'none',
          'caseDocument': _caseDocument(),
          'caseYaml': 'schemaVersion: cockpit.test/v2\n',
        }),
        throwsA(_formatExceptionAt(r'$.steps')),
      );
      expect(
        () => CockpitRecordedFlowBundle.fromJson(<String, Object?>{
          'steps': const <Object?>[],
          'caseDocument': _caseDocument(),
          'caseYaml': 'schemaVersion: cockpit.test/v2\n',
        }),
        throwsA(_formatExceptionAt(r'$.session')),
      );
    });

    test('equality distinguishes every field', () {
      final base = CockpitRecordedFlowBundle(
        session: _session(),
        steps: <CockpitInteractionStep>[_step('s1')],
        caseDocument: _caseDocument(),
        caseYaml: 'schemaVersion: cockpit.test/v2\n',
      );
      final mutations = <String, void Function(Map<String, Object?> json)>{
        'session': (json) => json['session'] = <String, Object?>{
          ...(_session().toJson()),
          'stepCount': 9,
        },
        'steps': (json) => json['steps'] = const <Object?>[],
        'caseDocument': (json) =>
            json['caseDocument'] = _caseDocument()..['id'] = 'other-case',
        'caseYaml': (json) => json['caseYaml'] = 'id: other\n',
      };
      mutations.forEach((field, mutate) {
        final json = base.toJson();
        mutate(json);
        expect(
          CockpitRecordedFlowBundle.fromJson(json) == base,
          isFalse,
          reason: 'field "$field" should affect equality',
        );
      });
      final twin = CockpitRecordedFlowBundle.fromJson(base.toJson());
      expect(twin, base);
      expect(twin.hashCode, base.hashCode);
    });
  });
}

CockpitInteractionRecordingSession _session() {
  return CockpitInteractionRecordingSession(
    sessionId: 'session-1',
    phase: CockpitRecorderPhase.stopped,
    startedAt: DateTime.utc(2026, 10, 7, 9, 30),
    endedAt: DateTime.utc(2026, 10, 7, 9, 40),
    stepCount: 2,
    unresolvedCount: 1,
  );
}

CockpitInteractionStep _step(String stepId) {
  return CockpitInteractionStep(
    stepId: stepId,
    kind: CockpitInteractionStepKind.tap,
    locatorCandidates: <CockpitLocatorCandidate>[
      CockpitLocatorCandidate(kind: 'key', selector: '@save', score: 4),
    ],
    routeName: '/settings',
    phase: CockpitRecorderPhase.recording,
    recordedAt: DateTime.utc(2026, 10, 7, 9, 31),
  );
}

Map<String, Object?> _caseDocument() {
  return <String, Object?>{
    'schemaVersion': 'cockpit.test/v2',
    'id': 'recorded-checkout',
    'steps': <Object?>[
      <String, Object?>{
        'action': 'tap',
        'locator': <String, Object?>{'text': 'Save'},
      },
    ],
  };
}

Matcher _formatExceptionAt(String path) => isA<FormatException>().having(
  (error) => error.message.toString(),
  'message',
  contains(path),
);
