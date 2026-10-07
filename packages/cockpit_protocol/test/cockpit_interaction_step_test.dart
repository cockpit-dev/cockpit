import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitRecorderPhase', () {
    test('decodes every phase and marks only stopped terminal', () {
      for (final phase in CockpitRecorderPhase.values) {
        expect(CockpitRecorderPhase.fromJson(phase.name), phase);
      }
      expect(CockpitRecorderPhase.idle.isTerminal, isFalse);
      expect(CockpitRecorderPhase.recording.isTerminal, isFalse);
      expect(CockpitRecorderPhase.paused.isTerminal, isFalse);
      expect(CockpitRecorderPhase.stopped.isTerminal, isTrue);
    });

    test('rejects unknown and malformed values with paths', () {
      expect(
        () => CockpitRecorderPhase.fromJson('fastForward'),
        throwsA(_formatExceptionAt(r'$.phase')),
      );
      expect(
        () => CockpitRecorderPhase.fromJson(3, path: r'$.session.phase'),
        throwsA(_formatExceptionAt(r'$.session.phase')),
      );
      expect(
        () => CockpitRecorderPhase.fromJson(null),
        throwsA(_formatExceptionAt(r'$.phase')),
      );
      expect(
        () => CockpitRecorderPhase.fromJson(''),
        throwsA(_formatExceptionAt(r'$.phase')),
      );
    });
  });

  group('CockpitInteractionStepKind', () {
    test('decodes every kind and rejects unknown values with paths', () {
      for (final kind in CockpitInteractionStepKind.values) {
        expect(CockpitInteractionStepKind.fromJson(kind.name), kind);
      }
      expect(
        () => CockpitInteractionStepKind.fromJson(
          'doubleTap',
          path: r'$.steps[0].kind',
        ),
        throwsA(_formatExceptionAt(r'$.steps[0].kind')),
      );
    });
  });

  group('CockpitInteractionScrollDirection', () {
    test('decodes every direction and rejects unknown values with paths', () {
      for (final direction in CockpitInteractionScrollDirection.values) {
        expect(
          CockpitInteractionScrollDirection.fromJson(direction.name),
          direction,
        );
      }
      expect(
        () => CockpitInteractionScrollDirection.fromJson('diagonally'),
        throwsA(_formatExceptionAt(r'$.scrollDirection')),
      );
    });
  });

  group('CockpitLocatorCandidate', () {
    test('round-trips key and type candidates', () {
      final candidates = <CockpitLocatorCandidate>[
        CockpitLocatorCandidate(kind: 'key', selector: '@save', score: 4),
        CockpitLocatorCandidate(kind: 'type', selector: 'TextButton', score: 0),
      ];
      for (final candidate in candidates) {
        final decoded = CockpitLocatorCandidate.fromJson(candidate.toJson());
        expect(decoded, candidate);
        expect(decoded.hashCode, candidate.hashCode);
      }
      expect(candidates[0], isNot(candidates[1]));
    });

    test('emits the exact key set in template order', () {
      final candidate = CockpitLocatorCandidate(
        kind: 'text',
        selector: 'Save',
        score: 2,
      );
      expect(candidate.toJson().keys.toList(), const <String>[
        'kind',
        'selector',
        'score',
      ]);
    });

    test('keeps long candidate lists in order across round trips', () {
      final candidates = <CockpitLocatorCandidate>[
        for (var index = 0; index < 12; index += 1)
          CockpitLocatorCandidate(
            kind: switch (index % 3) {
              0 => 'key',
              1 => 'text',
              _ => 'type',
            },
            selector: 'signal-$index',
            score: 12 - index,
          ),
      ];
      final step = CockpitInteractionStep(
        stepId: 's1',
        kind: CockpitInteractionStepKind.tap,
        locatorCandidates: candidates,
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.utc(2026, 10, 7, 9, 30),
      );
      final decoded = CockpitInteractionStep.fromJson(step.toJson());
      expect(decoded, step);
      expect(
        decoded.locatorCandidates.map((candidate) => candidate.selector),
        <String>[for (var index = 0; index < 12; index += 1) 'signal-$index'],
      );
      // Order is part of equality: the same candidates shuffled differ.
      final reordered = CockpitInteractionStep(
        stepId: 's1',
        kind: CockpitInteractionStepKind.tap,
        locatorCandidates: candidates.reversed.toList(),
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.utc(2026, 10, 7, 9, 30),
      );
      expect(reordered == step, isFalse);
    });

    test('constructor rejects empty selector and unknown kind', () {
      expect(
        () => CockpitLocatorCandidate(kind: 'text', selector: '', score: 2),
        throwsArgumentError,
      );
      expect(
        () => CockpitLocatorCandidate(kind: 'role', selector: 'Save', score: 2),
        throwsArgumentError,
      );
    });

    test('fromJson reports paths for malformed payloads', () {
      expect(
        () =>
            CockpitLocatorCandidate.fromJson('save', path: r'$.candidates[0]'),
        throwsA(_formatExceptionAt(r'$.candidates[0]')),
      );
      expect(
        () => CockpitLocatorCandidate.fromJson(<String, Object?>{
          'kind': 'text',
          'selector': 'Save',
        }, path: r'$.candidates[0]'),
        throwsA(_formatExceptionAt(r'$.candidates[0].score')),
      );
      expect(
        () => CockpitLocatorCandidate.fromJson(<String, Object?>{
          'kind': 'role',
          'selector': 'Save',
          'score': 2,
        }, path: r'$.candidates[0]'),
        throwsA(_formatExceptionAt(r'$.candidates[0].kind')),
      );
      expect(
        () => CockpitLocatorCandidate.fromJson(<String, Object?>{
          'kind': 'text',
          'selector': '',
          'score': 2,
        }, path: r'$.candidates[0]'),
        throwsA(_formatExceptionAt(r'$.candidates[0].selector')),
      );
      expect(
        () => CockpitLocatorCandidate.fromJson(<String, Object?>{
          'kind': 'text',
          'selector': 'Save',
          'score': '2',
        }, path: r'$.candidates[0]'),
        throwsA(_formatExceptionAt(r'$.candidates[0].score')),
      );
    });

    test('equality distinguishes kind, selector, and score', () {
      final base = CockpitLocatorCandidate(
        kind: 'text',
        selector: 'Save',
        score: 2,
      );
      final variants = <CockpitLocatorCandidate>[
        CockpitLocatorCandidate(kind: 'tooltip', selector: 'Save', score: 2),
        CockpitLocatorCandidate(kind: 'text', selector: 'Cancel', score: 2),
        CockpitLocatorCandidate(kind: 'text', selector: 'Save', score: 1),
      ];
      for (final variant in variants) {
        expect(variant == base, isFalse);
      }
    });
  });

  group('CockpitInteractionStep', () {
    test('round-trips a full step with every field set', () {
      final step = _fullStep();
      final decoded = CockpitInteractionStep.fromJson(step.toJson());
      expect(decoded, step);
      expect(decoded.hashCode, step.hashCode);
      expect(decoded.locatorCandidates.map((c) => c.selector), [
        '@save',
        'Save',
      ]);
      expect(decoded.scrollDirection, CockpitInteractionScrollDirection.up);
      expect(decoded.resolvedValue, 'Save');
      expect(decoded.fromRouteName, 'splash');
      expect(decoded.segments, <String>['setup', 'checkout']);
      expect(decoded.annotation, 'first save');
      expect(decoded.settledAfterMs, 240);
    });

    test('round-trips a minimal note step with defaults', () {
      final step = CockpitInteractionStep(
        stepId: 's2',
        kind: CockpitInteractionStepKind.note,
        phase: CockpitRecorderPhase.paused,
        recordedAt: DateTime.utc(2026, 10, 7, 9, 31),
      );
      expect(step.toJson(), <String, Object?>{
        'stepId': 's2',
        'kind': 'note',
        'phase': 'paused',
        'recordedAt': '2026-10-07T09:31:00.000Z',
      });
      final decoded = CockpitInteractionStep.fromJson(step.toJson());
      expect(decoded, step);
      expect(decoded.locatorCandidates, isEmpty);
      expect(decoded.segments, isEmpty);
      expect(decoded.unresolved, isFalse);
    });

    test('round-trips an unresolved noise step', () {
      final step = CockpitInteractionStep(
        stepId: 's3',
        kind: CockpitInteractionStepKind.tap,
        phase: CockpitRecorderPhase.recording,
        unresolved: true,
        positionDx: 12,
        positionDy: 34.5,
        recordedAt: DateTime.utc(2026, 10, 7, 9, 32),
      );
      final decoded = CockpitInteractionStep.fromJson(step.toJson());
      expect(decoded, step);
      expect(decoded.unresolved, isTrue);
      expect(decoded.positionDx, 12);
      expect(decoded.positionDy, 34.5);
      expect(decoded.locatorCandidates, isEmpty);
    });

    test('dedupes locator candidates by selector keeping first occurrence', () {
      final step = CockpitInteractionStep(
        stepId: 's1',
        kind: CockpitInteractionStepKind.tap,
        locatorCandidates: <CockpitLocatorCandidate>[
          CockpitLocatorCandidate(kind: 'text', selector: 'Save', score: 2),
          CockpitLocatorCandidate(kind: 'key', selector: '@save', score: 4),
          CockpitLocatorCandidate(kind: 'tooltip', selector: 'Save', score: 1),
        ],
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.utc(2026, 10, 7, 9, 30),
      );
      expect(step.locatorCandidates.map((c) => c.selector), <String>[
        'Save',
        '@save',
      ]);
      expect(step.locatorCandidates.first.kind, 'text');
      expect(
        () => step.locatorCandidates.add(
          CockpitLocatorCandidate(kind: 'key', selector: '@x', score: 4),
        ),
        throwsUnsupportedError,
      );
      expect(() => step.segments.add('late'), throwsUnsupportedError);
    });

    test('constructor rejects an empty step id', () {
      expect(
        () => CockpitInteractionStep(
          stepId: '',
          kind: CockpitInteractionStepKind.tap,
          phase: CockpitRecorderPhase.recording,
          recordedAt: DateTime.utc(2026, 10, 7, 9, 30),
        ),
        throwsArgumentError,
      );
    });

    test('fromJson reports paths for malformed payloads', () {
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          'kind': 'tap',
          'phase': 'recording',
          'recordedAt': '2026-10-07T09:30:00.000Z',
        }, path: r'$.steps[0]'),
        throwsA(_formatExceptionAt(r'$.steps[0].stepId')),
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'doubleTap',
          'phase': 'recording',
          'recordedAt': '2026-10-07T09:30:00.000Z',
        }, path: r'$.steps[0]'),
        throwsA(_formatExceptionAt(r'$.steps[0].kind')),
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
          'phase': 'recording',
          'positionDx': 'left',
          'recordedAt': '2026-10-07T09:30:00.000Z',
        }, path: r'$.steps[0]'),
        throwsA(_formatExceptionAt(r'$.steps[0].positionDx')),
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
          'phase': 'recording',
          'recordedAt': '2026-10-07T09:30:00.000',
        }, path: r'$.steps[0]'),
        throwsA(_formatExceptionAt(r'$.steps[0].recordedAt')),
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
          'phase': 'recording',
          'segments': 'setup',
          'recordedAt': '2026-10-07T09:30:00.000Z',
        }, path: r'$.steps[0]'),
        throwsA(_formatExceptionAt(r'$.steps[0].segments')),
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
          'phase': 'recording',
          'locatorCandidates': <Object?>[
            <String, Object?>{'kind': 'key', 'selector': '@save', 'score': 4},
            <String, Object?>{'kind': 'text', 'selector': '', 'score': 2},
          ],
          'recordedAt': '2026-10-07T09:30:00.000Z',
        }, path: r'$.steps[0]'),
        throwsA(
          _formatExceptionAt(r'$.steps[0].locatorCandidates[1].selector'),
        ),
      );
    });

    test('equality distinguishes every field', () {
      final base = _fullStep();
      final mutations = <String, void Function(Map<String, Object?> json)>{
        'stepId': (json) => json['stepId'] = 's9',
        'kind': (json) => json['kind'] = 'longPress',
        'locatorCandidates': (json) => json.remove('locatorCandidates'),
        'resolvedValue': (json) => json['resolvedValue'] = 'Cancel',
        'scrollDirection': (json) => json['scrollDirection'] = 'down',
        'routeName': (json) => json['routeName'] = '/home',
        'fromRouteName': (json) => json['fromRouteName'] = 'onboarding',
        'positionDx': (json) => json['positionDx'] = 99,
        'positionDy': (json) => json['positionDy'] = 99,
        'phase': (json) => json['phase'] = 'paused',
        'unresolved': (json) => json['unresolved'] = true,
        'segments': (json) => json['segments'] = <String>['main'],
        'annotation': (json) => json['annotation'] = 'other note',
        'settledAfterMs': (json) => json['settledAfterMs'] = 999,
        'recordedAt': (json) => json['recordedAt'] = '2026-10-07T09:30:00.001Z',
      };
      mutations.forEach((field, mutate) {
        final json = base.toJson();
        mutate(json);
        expect(
          CockpitInteractionStep.fromJson(json) == base,
          isFalse,
          reason: 'field "$field" should affect equality',
        );
      });
      final twin = CockpitInteractionStep.fromJson(base.toJson());
      expect(twin, base);
      expect(twin.hashCode, base.hashCode);
    });

    test('emits the exact full key set in template order', () {
      expect(_fullStep().toJson().keys.toList(), const <String>[
        'stepId',
        'kind',
        'locatorCandidates',
        'resolvedValue',
        'scrollDirection',
        'routeName',
        'fromRouteName',
        'positionDx',
        'positionDy',
        'phase',
        'segments',
        'annotation',
        'settledAfterMs',
        'recordedAt',
      ]);
    });

    test('fromJson rejects a non-object payload with the path', () {
      expect(
        () => CockpitInteractionStep.fromJson('s1', path: r'$.steps[2]'),
        throwsA(_formatExceptionAt(r'$.steps[2]')),
      );
    });

    test('fromJson tolerates unknown extra keys', () {
      final json = _fullStep().toJson()
        ..['unknownField'] = 'ignored'
        ..['nested'] = <String, Object?>{'surprise': 1};
      final decoded = CockpitInteractionStep.fromJson(json);
      expect(decoded, _fullStep());
    });

    test(
      'fromJson rejects negative settledAfterMs and non-boolean unresolved',
      () {
        expect(
          () => CockpitInteractionStep.fromJson(<String, Object?>{
            'stepId': 's1',
            'kind': 'tap',
            'phase': 'recording',
            'settledAfterMs': -1,
            'recordedAt': '2026-10-07T09:30:00.000Z',
          }),
          throwsA(_formatExceptionAt(r'$.settledAfterMs')),
        );
        expect(
          () => CockpitInteractionStep.fromJson(<String, Object?>{
            'stepId': 's1',
            'kind': 'tap',
            'phase': 'recording',
            'unresolved': 'yes',
            'recordedAt': '2026-10-07T09:30:00.000Z',
          }),
          throwsA(_formatExceptionAt(r'$.unresolved')),
        );
      },
    );

    test('fromJson bounds recorded text fields at 4096 characters', () {
      final base = <String, Object?>{
        'stepId': 's1',
        'kind': 'text',
        'phase': 'recording',
        'recordedAt': '2026-10-07T09:30:00.000Z',
      };
      final atLimit = <String, Object?>{...base, 'resolvedValue': 'x' * 4096};
      expect(
        CockpitInteractionStep.fromJson(atLimit).resolvedValue!.length,
        4096,
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          ...base,
          'resolvedValue': 'x' * 4097,
        }),
        throwsA(_formatExceptionAt(r'$.resolvedValue')),
      );
      expect(
        () => CockpitInteractionStep.fromJson(<String, Object?>{
          ...base,
          'annotation': 'x' * 4097,
        }),
        throwsA(_formatExceptionAt(r'$.annotation')),
      );
    });

    test('accepts empty bounded strings and preserves duplicate segments', () {
      final json = <String, Object?>{
        'stepId': 's1',
        'kind': 'routeChange',
        'routeName': '',
        'fromRouteName': '',
        'phase': 'recording',
        'segments': <Object?>['', 'setup', 'setup'],
        'recordedAt': '2026-10-07T09:30:00.000Z',
      };
      final decoded = CockpitInteractionStep.fromJson(json);
      expect(decoded.routeName, '');
      expect(decoded.fromRouteName, '');
      // Segments are marks, not identifiers: duplicates pass through.
      expect(decoded.segments, const <String>['', 'setup', 'setup']);
      expect(decoded.toJson()['segments'], const <String>[
        '',
        'setup',
        'setup',
      ]);
    });

    test('serializes a local recordedAt as its UTC instant', () {
      final local = DateTime(2026, 10, 7, 11, 30); // Local zone, not UTC.
      final step = CockpitInteractionStep(
        stepId: 's1',
        kind: CockpitInteractionStepKind.tap,
        phase: CockpitRecorderPhase.recording,
        recordedAt: local,
      );
      expect(step.toJson()['recordedAt'], local.toUtc().toIso8601String());
      final decoded = CockpitInteractionStep.fromJson(step.toJson());
      expect(decoded.recordedAt.isUtc, isTrue);
      expect(decoded.recordedAt.isAtSameMomentAs(local), isTrue);
      // DateTime equality demands the same zone flag, so the round trip
      // normalizes local captures to UTC instead of claiming equality.
      expect(decoded.recordedAt == local, isFalse);
    });
  });
}

CockpitInteractionStep _fullStep() {
  return CockpitInteractionStep(
    stepId: 's1',
    kind: CockpitInteractionStepKind.text,
    locatorCandidates: <CockpitLocatorCandidate>[
      CockpitLocatorCandidate(kind: 'key', selector: '@save', score: 4),
      CockpitLocatorCandidate(kind: 'text', selector: 'Save', score: 2),
    ],
    resolvedValue: 'Save',
    scrollDirection: CockpitInteractionScrollDirection.up,
    routeName: '/settings',
    fromRouteName: 'splash',
    positionDx: 120.5,
    positionDy: 640,
    phase: CockpitRecorderPhase.recording,
    segments: <String>['setup', 'checkout'],
    annotation: 'first save',
    settledAfterMs: 240,
    recordedAt: DateTime.utc(2026, 10, 7, 9, 30),
  );
}

Matcher _formatExceptionAt(String path) => isA<FormatException>().having(
  (error) => error.message.toString(),
  'message',
  contains(path),
);
