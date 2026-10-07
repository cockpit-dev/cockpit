import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

final DateTime _at = DateTime.utc(2026, 10, 7, 9);

CockpitLocatorCandidate _candidate(
  String kind,
  CockpitLocator locator,
  int score,
) => CockpitLocatorCandidate(
  kind: kind,
  selector: CockpitSelector.format(locator),
  score: score,
);

CockpitInteractionStep _step(
  String id,
  CockpitInteractionStepKind kind, {
  List<CockpitLocatorCandidate> candidates = const <CockpitLocatorCandidate>[],
  String? value,
  CockpitInteractionScrollDirection? direction,
  String? routeName,
  String? fromRouteName,
  bool unresolved = false,
  List<String> segments = const <String>[],
}) => CockpitInteractionStep(
  stepId: id,
  kind: kind,
  locatorCandidates: candidates,
  resolvedValue: value,
  scrollDirection: direction,
  routeName: routeName,
  fromRouteName: fromRouteName,
  unresolved: unresolved,
  segments: segments,
  phase: CockpitRecorderPhase.recording,
  recordedAt: _at,
);

CockpitTestActionTemplate _action(CockpitTestStepTemplate step) {
  final operation = step.operation;
  if (operation is! CockpitTestActionOperationTemplate) {
    throw StateError('Expected an action operation on ${step.stepId}.');
  }
  return operation.action;
}

void main() {
  const converter = CockpitRecordedFlowConverter();

  CockpitTestCase convert(
    List<CockpitInteractionStep> steps, {
    String? sessionId,
  }) {
    return converter.convert(
      caseId: 'recorded-r1',
      steps: steps,
      name: 'recorded flow',
      sessionId: sessionId,
    );
  }

  group('dropped steps', () {
    test('unresolved, marker, and note steps never reach the document', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step('s1', CockpitInteractionStepKind.tap, unresolved: true),
        _step(
          's2',
          CockpitInteractionStepKind.marker,
          segments: const <String>['setup'],
        ),
        _step('s3', CockpitInteractionStepKind.note),
        _step(
          's4',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'save'), 4),
          ],
        ),
      ]);

      expect(testCase.steps, hasLength(2));
      expect(_action(testCase.steps.first).kind, CockpitTestActionKind.tap);
      expect(_action(testCase.steps.last).kind, CockpitTestActionKind.waitFor);
    });

    test('a step whose candidates are all unrepresentable is dropped', () {
      // semanticId has no test-document locator slot.
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate(
              'semanticId',
              const CockpitLocator(semanticId: 'save'),
              3,
            ),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'save'), 4),
          ],
        ),
      ]);

      expect(testCase.steps, hasLength(2));
      expect(_action(testCase.steps.first).kind, CockpitTestActionKind.tap);
    });
  });

  group('setup segment', () {
    test('steps inside the setup segment land in the setup block', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          segments: const <String>['setup'],
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'seed'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'save'), 4),
          ],
        ),
      ]);

      expect(testCase.setup, hasLength(2));
      expect(_action(testCase.setup.first).locator!.testId!.value, 'seed');
      expect(testCase.setup.map((step) => step.stepId), const <String>[
        'st1',
        'st2',
      ]);
      // Main steps continue the id sequence after setup.
      expect(testCase.steps.map((step) => step.stepId), const <String>[
        'st3',
        'st4',
      ]);
      // The terminal wait after the setup action targets the next step.
      expect(
        _action(testCase.setup.last).condition!.locator!.testId!.value,
        'save',
      );
    });

    test('without a setup segment the setup block is omitted', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'save'), 4),
          ],
        ),
      ]);
      expect(testCase.setup, isEmpty);
      expect(testCase.toJson().containsKey('setup'), isFalse);
    });
  });

  group('locators', () {
    test('the first candidate is primary and the rest form the fallbacks', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'save'), 4),
            _candidate('text', const CockpitLocator(text: 'Save'), 2),
            _candidate('tooltip', const CockpitLocator(tooltip: 'Saves'), 1),
            _candidate('type', const CockpitLocator(type: 'CustomZone'), 0),
          ],
        ),
      ]);

      final locator = _action(testCase.steps.first).locator!;
      expect(locator.testId!.value, 'save');
      expect(locator.fallbacks, hasLength(3));
      expect(locator.fallbacks[0].text!.value, 'Save');
      expect(locator.fallbacks[1].label!.value, 'Saves');
      expect(locator.fallbacks[2].type!.value, 'CustomZone');
    });
  });

  group('action mapping', () {
    test('text steps carry the final value into enterText', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.text,
          value: 'hello@example.com',
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'email'), 4),
          ],
        ),
      ]);

      final action = _action(testCase.steps.first);
      expect(action.kind, CockpitTestActionKind.enterText);
      expect(action.locator!.testId!.value, 'email');
      expect(
        action.values[CockpitTestActionField.text]!.value,
        'hello@example.com',
      );
    });

    test('longPress keeps its own action kind', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.longPress,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'hold'), 4),
          ],
        ),
      ]);
      expect(
        _action(testCase.steps.first).kind,
        CockpitTestActionKind.longPress,
      );
    });

    test('scroll maps to scrollUntilVisible with the recorded direction', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.scroll,
          direction: CockpitInteractionScrollDirection.up,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'item-9'), 4),
          ],
        ),
      ]);

      final action = _action(testCase.steps.first);
      expect(action.kind, CockpitTestActionKind.scrollUntilVisible);
      expect(action.locator!.testId!.value, 'item-9');
      expect(action.values[CockpitTestActionField.direction]!.value, 'up');
    });

    test('routeChange maps to a waitFor route condition and back to back', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'open'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.routeChange,
          routeName: '/details',
          fromRouteName: '/',
        ),
        _step('s3', CockpitInteractionStepKind.back, routeName: '/'),
      ]);

      // tap: no extra wait — the following routeChange is itself one.
      expect(_action(testCase.steps[0]).kind, CockpitTestActionKind.tap);
      final routeAction = _action(testCase.steps[1]);
      expect(routeAction.kind, CockpitTestActionKind.waitFor);
      expect(routeAction.condition!.kind, CockpitTestConditionKind.route);
      expect(routeAction.condition!.route!.value, '/details');
      expect(_action(testCase.steps[2]).kind, CockpitTestActionKind.back);
    });
  });

  group('weak assertions', () {
    test(
      'each action waits for the next locator; the last waits for itself',
      () {
        final testCase = convert(<CockpitInteractionStep>[
          _step(
            's1',
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[
              _candidate('key', const CockpitLocator(key: 'first'), 4),
            ],
          ),
          _step(
            's2',
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[
              _candidate('text', const CockpitLocator(text: 'Second'), 2),
            ],
          ),
        ]);

        expect(
          testCase.steps.map((step) => _action(step).kind),
          const <CockpitTestActionKind>[
            CockpitTestActionKind.tap,
            CockpitTestActionKind.waitFor,
            CockpitTestActionKind.tap,
            CockpitTestActionKind.waitFor,
          ],
        );
        final afterFirst = _action(testCase.steps[1]);
        expect(afterFirst.condition!.kind, CockpitTestConditionKind.visible);
        expect(afterFirst.condition!.locator!.text!.value, 'Second');
        // Terminal wait: the last action's own primary locator.
        final terminal = _action(testCase.steps[3]);
        expect(terminal.condition!.locator!.text!.value, 'Second');
      },
    );

    test('no terminal wait after a final routeChange or back', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.routeChange,
          routeName: '/details',
          fromRouteName: '/',
        ),
      ]);
      expect(testCase.steps, hasLength(1));
      expect(
        _action(testCase.steps.single).kind,
        CockpitTestActionKind.waitFor,
      );
    });
  });

  group('determinism and metadata', () {
    test('identical input produces identical documents and step ids', () {
      final steps = <CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'a'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.text,
          value: 'x',
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'b'), 4),
          ],
        ),
      ];
      final first = convert(steps, sessionId: 'r1');
      final second = convert(steps, sessionId: 'r1');

      expect(first.toJson(), second.toJson());
      expect(
        [...first.setup, ...first.steps].map((step) => step.stepId),
        everyElement(matches(RegExp(r'^st\d+$'))),
      );
    });

    test('extensions record the recorded origin and session id', () {
      final steps = <CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'a'), 4),
          ],
        ),
      ];

      expect(convert(steps, sessionId: 'r7').extensions, <String, Object?>{
        'x-cockpit-origin': 'recorded',
        'x-cockpit-recorder-session': 'r7',
      });
      expect(convert(steps).extensions, <String, Object?>{
        'x-cockpit-origin': 'recorded',
      });
    });

    test('marker and note only input cannot produce a valid case', () {
      // The case template requires at least one main step, so the converter
      // refuses rather than emitting an invalid document.
      expect(
        () => convert(<CockpitInteractionStep>[
          _step('s1', CockpitInteractionStepKind.note),
          _step('s2', CockpitInteractionStepKind.marker),
          _step('s3', CockpitInteractionStepKind.tap, unresolved: true),
        ]),
        throwsArgumentError,
      );
    });

    test('a setup-only recording also refuses an empty main block', () {
      expect(
        () => convert(<CockpitInteractionStep>[
          _step(
            's1',
            CockpitInteractionStepKind.tap,
            segments: const <String>['setup'],
            candidates: <CockpitLocatorCandidate>[
              _candidate('key', const CockpitLocator(key: 'a'), 4),
            ],
          ),
        ]),
        throwsArgumentError,
      );
    });
  });
}
