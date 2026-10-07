import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Type-preservation proof for the recorder export pipeline: strings that
/// [CockpitTestDocumentYamlWriter] leaves plain must stay strings under the
/// exact YAML parser the compiler uses (`package:yaml`), and strings it
/// quotes must decode back to the identical text. A missing quote here would
/// silently turn a recorded value into an int/double/bool in the compiled
/// case.
void main() {
  const writer = CockpitTestDocumentYamlWriter();

  Map<String, Object?> documentWith(List<String> values) => <String, Object?>{
    'values': <Object?>[...values],
  };

  Map<String, Object?> loadWritten(Map<String, Object?> document) {
    final loaded = loadYaml(writer.write(document)) as YamlMap;
    return <String, Object?>{
      for (final entry in loaded.entries)
        (entry.key as Object).toString(): entry.value is YamlList
            ? (entry.value as YamlList).toList()
            : entry.value,
    };
  }

  test('coercion-prone recorded strings survive as strings', () {
    const values = <String>[
      // Number-shaped strings the Dart yaml resolver coerces when plain.
      '018',
      '008',
      '0o17',
      '0x1F',
      '9',
      '+5',
      '.5',
      '+.5',
      '-.5',
      '1e3',
      '5.',
      '-0',
      '.inf',
      '.nan',
      // Boolean- and null-shaped strings.
      'true',
      'TRUE',
      'False',
      'null',
      '~',
      // Structural edge strings.
      'a: b',
      'a #comment',
      '#lead',
      '- item',
      ' padded ',
      '',
      'say "hi"',
      'back\\slash',
      'line1\nline2',
      'tab\there',
      'del\u007flete',
      // Unicode text values.
      '保存',
      'héllo ☃',
      '👍🏽',
    ];
    final loaded = loadWritten(documentWith(values));
    final decoded = loaded['values']! as List<Object?>;
    expect(decoded, hasLength(values.length));
    for (var index = 0; index < values.length; index += 1) {
      expect(decoded[index], values[index], reason: 'value "$values[index]"');
      expect(decoded[index], isA<String>(), reason: 'value "$values[index]"');
    }
  });

  test('plain-safe recorded strings stay identical and unquoted', () {
    const values = <String>[
      'plain',
      'cockpit.test/v2',
      '-x',
      'a:b',
      'a#b',
      'Infinity',
      'NaN',
      '1_000',
      '1:30',
      'user@example.com',
    ];
    final yaml = writer.write(documentWith(values));
    expect(yaml, isNot(contains('"')));
    final decoded = (loadWritten(documentWith(values))['values']!) as List;
    for (var index = 0; index < values.length; index += 1) {
      expect(decoded[index], values[index]);
    }
  });

  test('a converted case with hostile values compiles back identically', () {
    final recordedAt = DateTime.utc(2026, 10, 7, 9);
    String selector(CockpitLocator locator) => CockpitSelector.format(locator);
    final testCase = const CockpitRecordedFlowConverter().convert(
      caseId: 'recorded-018',
      name: '018 yes: .5',
      steps: <CockpitInteractionStep>[
        CockpitInteractionStep(
          stepId: 's1',
          kind: CockpitInteractionStepKind.text,
          resolvedValue: '018',
          locatorCandidates: <CockpitLocatorCandidate>[
            CockpitLocatorCandidate(
              kind: 'text',
              selector: selector(const CockpitLocator(text: '保存')),
              score: 2,
            ),
          ],
          phase: CockpitRecorderPhase.recording,
          recordedAt: recordedAt,
        ),
      ],
    );

    final loaded = loadYaml(writer.write(testCase.toJson())) as YamlMap;

    expect(loaded['id'], 'recorded-018');
    expect(loaded['name'], '018 yes: .5');
    final steps = loaded['steps']! as YamlList;
    final action = (steps[0]! as YamlMap)['action']! as YamlMap;
    expect(action['text'], '018');
    expect(action['text'], isA<String>());
    final locator = action['locator']! as YamlMap;
    expect(locator['text'], '保存');
  });
}
