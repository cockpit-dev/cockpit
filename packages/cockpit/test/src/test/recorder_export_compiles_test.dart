import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

/// Schema-validity proof for the recorder export pipeline: realistic
/// recorded steps → [CockpitRecordedFlowConverter] →
/// [CockpitTestDocumentYamlWriter] → [CockpitTestDocumentCompiler] with the
/// YAML format. If any recorded shape ever produced a document outside the
/// `cockpit.test/v2` schema, this is the test that fails.
void main() {
  final recordedAt = DateTime.utc(2026, 10, 7, 9, 0, 1);

  CockpitLocatorCandidate candidate(
    String kind,
    CockpitLocator locator,
    int score,
  ) => CockpitLocatorCandidate(
    kind: kind,
    selector: CockpitSelector.format(locator),
    score: score,
  );

  CockpitInteractionStep step(
    CockpitInteractionStepKind kind, {
    List<CockpitLocatorCandidate> candidates =
        const <CockpitLocatorCandidate>[],
    String? value,
    CockpitInteractionScrollDirection? direction,
    String? routeName,
    String? fromRouteName,
    bool unresolved = false,
    List<String> segments = const <String>[],
  }) => CockpitInteractionStep(
    stepId: 'pending',
    kind: kind,
    locatorCandidates: candidates,
    resolvedValue: value,
    scrollDirection: direction,
    routeName: routeName,
    fromRouteName: fromRouteName,
    unresolved: unresolved,
    segments: segments,
    phase: CockpitRecorderPhase.recording,
    recordedAt: recordedAt,
  );

  test('a realistic recorded flow compiles as a valid case document', () {
    // A form flow: seeded in the setup segment, then type, scroll to reveal,
    // submit, navigate — plus one unresolved noise tap and a timeline note.
    final steps = <CockpitInteractionStep>[
      step(
        CockpitInteractionStepKind.tap,
        segments: const <String>['setup'],
        candidates: <CockpitLocatorCandidate>[
          candidate('key', const CockpitLocator(key: 'seed-button'), 4),
        ],
      ),
      step(CockpitInteractionStepKind.note, value: 'ignored timeline aid'),
      step(
        CockpitInteractionStepKind.text,
        value: 'Cockpit flight check',
        candidates: <CockpitLocatorCandidate>[
          candidate('key', const CockpitLocator(key: 'title-field'), 4),
          candidate('text', const CockpitLocator(text: 'Title'), 2),
        ],
      ),
      step(
        CockpitInteractionStepKind.scroll,
        direction: CockpitInteractionScrollDirection.up,
        candidates: <CockpitLocatorCandidate>[
          candidate('key', const CockpitLocator(key: 'item-9'), 4),
        ],
      ),
      step(
        CockpitInteractionStepKind.tap,
        candidates: <CockpitLocatorCandidate>[
          candidate('key', const CockpitLocator(key: 'submit-button'), 4),
          candidate('text', const CockpitLocator(text: 'Submit'), 2),
          candidate('type', const CockpitLocator(type: 'ElevatedButton'), 0),
        ],
      ),
      step(
        CockpitInteractionStepKind.routeChange,
        routeName: '/details',
        fromRouteName: '/',
      ),
      step(CockpitInteractionStepKind.tap, unresolved: true),
    ];

    final testCase = const CockpitRecordedFlowConverter().convert(
      caseId: 'recorded-r1',
      steps: steps,
      name: 'form flow',
      sessionId: 'r1',
    );
    final yaml = const CockpitTestDocumentYamlWriter().write(testCase.toJson());

    final result = CockpitTestDocumentCompiler().compile(
      yaml,
      format: CockpitDocumentFormat.yaml,
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostics.toString());
    final compiled = result.requireCompiled();
    expect(compiled, isA<CockpitCompiledTestCase>());
    final compiledCase = compiled as CockpitCompiledTestCase;
    expect(compiledCase.testCase.id, 'recorded-r1');
    // Setup keeps the seeded tap plus its liveness wait on the next target.
    expect(compiledCase.testCase.setup, hasLength(2));
    // Main steps: enterText, wait, scrollUntilVisible, tap, route wait. The
    // scroll borrows the submit tap's locator and carries that wait itself,
    // so no separate wait follows it.
    expect(compiledCase.testCase.steps, hasLength(5));
    expect(
      compiledCase.testCase.steps.map((step) => step.stepId),
      everyElement(matches(RegExp(r'^st\d+$'))),
    );
    expect(compiledCase.testCase.extensions['x-cockpit-origin'], 'recorded');
  });

  test('quoted and unicode values still compile', () {
    final steps = <CockpitInteractionStep>[
      step(
        CockpitInteractionStepKind.text,
        value: 'välue with ünicode and "quotes": yes',
        candidates: <CockpitLocatorCandidate>[
          candidate('key', const CockpitLocator(key: 'note-field'), 4),
        ],
      ),
    ];
    final testCase = const CockpitRecordedFlowConverter().convert(
      caseId: 'recorded-r2',
      steps: steps,
    );
    final yaml = const CockpitTestDocumentYamlWriter().write(testCase.toJson());

    final result = CockpitTestDocumentCompiler().compile(
      yaml,
      format: CockpitDocumentFormat.yaml,
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostics.toString());
    final compiled = result.requireCase();
    final action =
        compiled.testCase.steps.first.operation
            as CockpitTestActionOperationTemplate;
    expect(
      action.action.values[CockpitTestActionField.text]!.value,
      'välue with ünicode and "quotes": yes',
    );
  });
}
