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

  group('drop rules per kind', () {
    test('text steps without a usable value are dropped', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.text,
          value: null,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'a'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.text,
          value: '',
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'b'), 4),
          ],
        ),
        _step(
          's3',
          CockpitInteractionStepKind.text,
          value: 'kept',
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'c'), 4),
          ],
        ),
      ]);
      expect(testCase.steps.map((step) => step.stepId), const <String>[
        'st1',
        'st2',
      ]);
      final action = _action(testCase.steps.first);
      expect(action.values[CockpitTestActionField.text]!.value, 'kept');
    });

    test(
      'a text step with only unrepresentable candidates keeps a locator-less '
      'enterText',
      () {
        // enterText's locator is optional in the action contract, so the
        // drop rule for locator-requiring actions (tap/longPress/scroll)
        // does not apply: the step replays as "type into the focused field".
        final testCase = convert(<CockpitInteractionStep>[
          _step(
            's1',
            CockpitInteractionStepKind.text,
            value: 'typed',
            candidates: <CockpitLocatorCandidate>[
              _candidate(
                'semanticId',
                const CockpitLocator(semanticId: 'email'),
                3,
              ),
            ],
          ),
          _step(
            's2',
            CockpitInteractionStepKind.text,
            value: 'kept',
            candidates: <CockpitLocatorCandidate>[
              _candidate('key', const CockpitLocator(key: 'email'), 4),
            ],
          ),
        ]);
        final first = _action(testCase.steps.first);
        expect(first.kind, CockpitTestActionKind.enterText);
        expect(first.locator, isNull);
        expect(first.values[CockpitTestActionField.text]!.value, 'typed');
        final third = _action(testCase.steps[2]);
        expect(third.locator!.testId!.value, 'email');
      },
    );

    test('scroll steps without a direction are dropped', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.scroll,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'list'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.scroll,
          direction: CockpitInteractionScrollDirection.down,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'list'), 4),
          ],
        ),
      ]);
      expect(testCase.steps, hasLength(2));
      expect(
        _action(
          testCase.steps.first,
        ).values[CockpitTestActionField.direction]!.value,
        'down',
      );
    });

    test(
      'a scroll step whose candidates are all unrepresentable is dropped',
      () {
        final testCase = convert(<CockpitInteractionStep>[
          _step(
            's1',
            CockpitInteractionStepKind.scroll,
            direction: CockpitInteractionScrollDirection.down,
            candidates: <CockpitLocatorCandidate>[
              _candidate(
                'semanticId',
                const CockpitLocator(semanticId: 'list'),
                3,
              ),
            ],
          ),
          _step('s2', CockpitInteractionStepKind.back),
        ]);
        expect(
          testCase.steps.map((step) => _action(step).kind),
          const <CockpitTestActionKind>[CockpitTestActionKind.back],
        );
      },
    );

    test('routeChange steps without a route name are dropped', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step('s1', CockpitInteractionStepKind.routeChange),
        _step(
          's2',
          CockpitInteractionStepKind.routeChange,
          routeName: '/details',
          fromRouteName: '/',
        ),
      ]);
      expect(
        testCase.steps.map((step) => _action(step).kind),
        const <CockpitTestActionKind>[CockpitTestActionKind.waitFor],
      );
      expect(
        _action(testCase.steps.single).condition!.route!.value,
        '/details',
      );
    });

    test(
      'routeChange steps with an empty route name are dropped, not thrown',
      () {
        // The step model round-trips an empty route name, so the converter
        // applies the same drop rule as a missing one instead of crashing on
        // an empty template value.
        final testCase = convert(<CockpitInteractionStep>[
          _step(
            's2',
            CockpitInteractionStepKind.routeChange,
            routeName: '',
            fromRouteName: '/',
          ),
          _step(
            's3',
            CockpitInteractionStepKind.routeChange,
            routeName: '/details',
          ),
        ]);
        expect(
          testCase.steps.map((step) => _action(step).kind),
          const <CockpitTestActionKind>[CockpitTestActionKind.waitFor],
        );
        expect(
          _action(testCase.steps.single).condition!.route!.value,
          '/details',
        );
      },
    );

    test('resolved taps without any candidate are dropped', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step('s1', CockpitInteractionStepKind.tap),
        _step(
          's2',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'keep'), 4),
          ],
        ),
      ]);
      expect(testCase.steps, hasLength(2));
      expect(_action(testCase.steps.first).locator!.testId!.value, 'keep');
    });

    test('every drop rule together still refuses an empty main block', () {
      expect(
        () => convert(<CockpitInteractionStep>[
          _step('s1', CockpitInteractionStepKind.tap),
          _step('s2', CockpitInteractionStepKind.tap, unresolved: true),
          _step('s3', CockpitInteractionStepKind.note),
          _step('s4', CockpitInteractionStepKind.marker),
          _step(
            's5',
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[
              _candidate(
                'semanticId',
                const CockpitLocator(semanticId: 'ghost'),
                3,
              ),
            ],
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('locator mapping edges', () {
    test('cockpitId and path selectors find their document slots', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(cockpitId: 'ck-save'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(path: '/root[0]/row[3]'), 4),
          ],
        ),
      ]);
      expect(_action(testCase.steps.first).locator!.testId!.value, 'ck-save');
      expect(
        _action(testCase.steps.last).condition!.locator!.path!.value,
        '/root[0]/row[3]',
      );
    });

    test('unrepresentable candidates are skipped, order otherwise kept', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate(
              'semanticId',
              const CockpitLocator(semanticId: 'primary-ghost'),
              3,
            ),
            _candidate('key', const CockpitLocator(key: 'first-real'), 4),
            _candidate(
              'semanticId',
              const CockpitLocator(semanticId: 'ghost-2'),
              3,
            ),
            _candidate('text', const CockpitLocator(text: 'Second'), 2),
            _candidate('type', const CockpitLocator(type: 'CustomZone'), 0),
          ],
        ),
      ]);
      final locator = _action(testCase.steps.first).locator!;
      expect(locator.testId!.value, 'first-real');
      expect(locator.fallbacks, hasLength(2));
      expect(locator.fallbacks[0].text!.value, 'Second');
      expect(locator.fallbacks[1].type!.value, 'CustomZone');
    });

    test('route-only selectors never contribute a locator slot', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('text', const CockpitLocator(route: '/details'), 3),
            _candidate('text', const CockpitLocator(text: 'Save'), 2),
          ],
        ),
      ]);
      final locator = _action(testCase.steps.first).locator!;
      expect(locator.text!.value, 'Save');
      expect(locator.fallbacks, isEmpty);
    });

    test('duplicate candidate sets across steps stay independent', () {
      final candidates = <CockpitLocatorCandidate>[
        _candidate('key', const CockpitLocator(key: 'save'), 4),
        _candidate('text', const CockpitLocator(text: 'Save'), 2),
      ];
      final testCase = convert(<CockpitInteractionStep>[
        _step('s1', CockpitInteractionStepKind.tap, candidates: candidates),
        _step(
          's2',
          CockpitInteractionStepKind.longPress,
          candidates: candidates,
        ),
      ]);
      final actions = testCase.steps
          .map(_action)
          .where((action) => action.kind != CockpitTestActionKind.waitFor)
          .toList();
      expect(actions, hasLength(2));
      for (final action in actions) {
        expect(action.locator!.testId!.value, 'save');
        expect(action.locator!.fallbacks, hasLength(1));
      }
      expect(testCase.steps, hasLength(4));
    });
  });

  group('setup interleaving and id density', () {
    test('multiple setup stretches merge in order with dense st<n> ids', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          segments: const <String>['setup'],
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'seed-1'), 4),
          ],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'main-1'), 4),
          ],
        ),
        _step(
          's3',
          CockpitInteractionStepKind.text,
          value: 'login',
          segments: const <String>['setup'],
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'seed-2'), 4),
          ],
        ),
        _step(
          's4',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'main-2'), 4),
          ],
        ),
      ]);

      // Emission order assigns ids densely across both blocks; dropped or
      // interleaved steps never leave a gap.
      expect(testCase.setup.map((step) => step.stepId), const <String>[
        'st1',
        'st2',
        'st5',
        'st6',
      ]);
      expect(testCase.steps.map((step) => step.stepId), const <String>[
        'st3',
        'st4',
        'st7',
        'st8',
      ]);
      // The setup wait after the second stretch targets the next main step.
      final secondSetupWait = _action(testCase.setup.last);
      expect(secondSetupWait.condition!.kind, CockpitTestConditionKind.visible);
      expect(secondSetupWait.condition!.locator!.testId!.value, 'main-2');
    });

    test('dropped noise between actions does not break the id sequence', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'a'), 4),
          ],
        ),
        _step('s2', CockpitInteractionStepKind.tap, unresolved: true),
        _step('s3', CockpitInteractionStepKind.note),
        _step('s4', CockpitInteractionStepKind.tap),
        _step(
          's5',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'b'), 4),
          ],
        ),
      ]);
      expect(testCase.steps.map((step) => step.stepId), const <String>[
        'st1',
        'st2',
        'st3',
        'st4',
      ]);
      // The wait after the first tap skips the dropped noise and targets the
      // next exportable step's locator — never an empty one.
      expect(_action(testCase.steps[1]).condition!.locator!.testId!.value, 'b');
    });

    test('routeChange and back land in the setup block when marked', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.routeChange,
          routeName: '/onboarding',
          segments: const <String>['setup'],
        ),
        _step(
          's2',
          CockpitInteractionStepKind.back,
          segments: const <String>['setup'],
        ),
        _step(
          's3',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'main'), 4),
          ],
        ),
      ]);
      // The wait after the setup back targets the first main action and stays
      // in the setup block, acting as the setup-to-main handoff barrier.
      expect(testCase.setup, hasLength(3));
      expect(
        _action(testCase.setup.first).condition!.kind,
        CockpitTestConditionKind.route,
      );
      expect(_action(testCase.setup[1]).kind, CockpitTestActionKind.back);
      expect(
        _action(testCase.setup.last).condition!.locator!.testId!.value,
        'main',
      );
      expect(testCase.steps.map((step) => step.stepId), const <String>[
        'st4',
        'st5',
      ]);
    });
  });

  group('unicode and scale', () {
    test('CJK and emoji values survive the conversion', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.text,
          value: '用户@example.com',
          candidates: <CockpitLocatorCandidate>[
            _candidate('text', const CockpitLocator(text: '邮箱'), 2),
            _candidate('tooltip', const CockpitLocator(tooltip: '保存表单'), 1),
          ],
        ),
      ]);
      final action = _action(testCase.steps.first);
      expect(action.locator!.text!.value, '邮箱');
      expect(action.locator!.fallbacks.single.label!.value, '保存表单');
      expect(
        action.values[CockpitTestActionField.text]!.value,
        '用户@example.com',
      );
    });

    test('very long text values are carried in full', () {
      final long = 'z' * 3000;
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.text,
          value: long,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'notes'), 4),
          ],
        ),
      ]);
      expect(
        _action(
          testCase.steps.first,
        ).values[CockpitTestActionField.text]!.value,
        long,
      );
      expect(testCase.toJson()['steps'].toString().contains(long), isTrue);
    });
  });

  group('weak assertion edges', () {
    test('a tap followed only by back emits no wait between them', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'open'), 4),
          ],
        ),
        _step('s2', CockpitInteractionStepKind.back, routeName: '/'),
      ]);
      // The back is itself the transition wait; the last step is a back, so
      // there is no terminal locator wait either.
      expect(
        testCase.steps.map((step) => _action(step).kind),
        const <CockpitTestActionKind>[
          CockpitTestActionKind.tap,
          CockpitTestActionKind.back,
        ],
      );
    });

    test('a back between two taps waits for the next tap target', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'details'), 4),
          ],
        ),
        _step('s2', CockpitInteractionStepKind.back, routeName: '/'),
        _step(
          's3',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('text', const CockpitLocator(text: 'Home'), 2),
          ],
        ),
      ]);
      expect(
        testCase.steps.map((step) => _action(step).kind),
        const <CockpitTestActionKind>[
          CockpitTestActionKind.tap,
          CockpitTestActionKind.back,
          CockpitTestActionKind.waitFor,
          CockpitTestActionKind.tap,
          CockpitTestActionKind.waitFor,
        ],
      );
      expect(
        _action(testCase.steps[2]).condition!.locator!.text!.value,
        'Home',
      );
    });

    test('consecutive routeChange steps stay separate route waits', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.routeChange,
          routeName: '/splash',
          fromRouteName: '/',
        ),
        _step(
          's2',
          CockpitInteractionStepKind.routeChange,
          routeName: '/home',
          fromRouteName: '/splash',
        ),
        _step(
          's3',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'start'), 4),
          ],
        ),
      ]);
      final routes = testCase.steps
          .map((step) => _action(step))
          .where(
            (action) =>
                action.condition?.kind == CockpitTestConditionKind.route,
          )
          .map((action) => action.condition!.route!.value)
          .toList();
      expect(routes, const <String>['/splash', '/home']);
      // The trailing tap still gets its terminal visible wait.
      expect(testCase.steps, hasLength(4));
      expect(_action(testCase.steps.last).kind, CockpitTestActionKind.waitFor);
    });

    test('annotations and diagnostics never reach the document', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'a'), 4),
          ],
          routeName: '/current',
          fromRouteName: '/previous',
        ),
      ]);
      final json = testCase.toJson();
      expect(json.containsKey('annotation'), isFalse);
      expect(json['steps'].toString().contains('previous'), isFalse);
      expect(json['steps'].toString().contains('current'), isFalse);
    });
  });

  group('document metadata', () {
    test('the case id, name, and target come from the conversion input', () {
      final testCase = convert(<CockpitInteractionStep>[
        _step(
          's1',
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[
            _candidate('key', const CockpitLocator(key: 'a'), 4),
          ],
        ),
      ]);
      expect(testCase.id, 'recorded-r1');
      expect(testCase.name, 'recorded flow');
      expect(testCase.target.platform, 'flutter');
      expect(testCase.target.targetKind, 'flutterApp');
      expect(testCase.target.plane, CockpitTestPlane.semantic);
    });
  });
}
