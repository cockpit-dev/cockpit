import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  const writer = CockpitTestDocumentYamlWriter();

  group('CockpitTestDocumentYamlWriter', () {
    test('renders a small case document exactly', () {
      final yaml = writer.write(<String, Object?>{
        'schemaVersion': 'cockpit.test/v2',
        'kind': 'case',
        'id': 'recorded-r1',
        'name': 'Login flow',
        'target': <String, Object?>{
          'platform': 'flutter',
          'targetKind': 'flutterApp',
          'plane': 'semantic',
        },
        'steps': <Object?>[
          <String, Object?>{
            'stepId': 'st1',
            'action': <String, Object?>{
              'type': 'tap',
              'locator': <String, Object?>{'testId': 'save-button'},
            },
          },
        ],
        'x-cockpit-origin': 'recorded',
      });

      expect(yaml, '''
schemaVersion: cockpit.test/v2
kind: case
id: recorded-r1
name: Login flow
target:
  platform: flutter
  targetKind: flutterApp
  plane: semantic
steps:
- stepId: st1
  action:
    type: tap
    locator:
      testId: save-button
x-cockpit-origin: recorded
''');
    });

    test('renders nested lists and fallbacks chains exactly', () {
      final yaml = writer.write(<String, Object?>{
        'id': 'nested',
        'locator': <String, Object?>{
          'text': 'Save',
          'fallbacks': <Object?>[
            <String, Object?>{
              'label': 'Saves the form',
              'fallbacks': <Object?>[
                <String, Object?>{'type': 'CustomZone'},
              ],
            },
          ],
        },
        'steps': <Object?>[
          <String, Object?>{
            'stepId': 'st1',
            'condition': <String, Object?>{
              'type': 'visible',
              'locator': <String, Object?>{'path': '/root[0]'},
            },
          },
        ],
      });

      expect(yaml, '''
id: nested
locator:
  text: Save
  fallbacks:
  - label: Saves the form
    fallbacks:
    - type: CustomZone
steps:
- stepId: st1
  condition:
    type: visible
    locator:
      path: /root[0]
''');
    });

    test('renders scalars and empty collections exactly', () {
      final yaml = writer.write(<String, Object?>{
        'int': 7,
        'double': 0.5,
        'truthy': true,
        'nullish': null,
        'emptyMap': <String, Object?>{},
        'emptyList': <Object?>[],
        'list': <Object?>[1, null, false, 'x'],
      });

      expect(yaml, '''
int: 7
double: 0.5
truthy: true
nullish: null
emptyMap: {}
emptyList: []
list:
- 1
- null
- false
- x
''');
    });

    test('quotes scalars that would not survive a plain round trip', () {
      final yaml = writer.write(<String, Object?>{
        'values': <Object?>[
          '',
          'true',
          '123',
          '1.5',
          'null',
          'yes',
          'on',
          'a: b',
          'trailing:',
          'a #comment',
          '#lead',
          '- item',
          '?',
          ':',
          '@key',
          '[tip="Save"]',
          'say "hi"',
          'back\\slash',
          'line1\nline2',
          'tab\there',
          ' padded ',
          'héllo ☃',
          'plain',
          'cockpit.test/v2',
        ],
      });

      expect(yaml, '''
values:
- ""
- "true"
- "123"
- "1.5"
- "null"
- "yes"
- "on"
- "a: b"
- "trailing:"
- "a #comment"
- "#lead"
- "- item"
- "?"
- ":"
- "@key"
- "[tip=\\"Save\\"]"
- "say \\"hi\\""
- "back\\\\slash"
- "line1\\nline2"
- "tab\\there"
- " padded "
- héllo ☃
- plain
- cockpit.test/v2
''');
    });

    test('keeps keys in insertion order and stays deterministic', () {
      final document = <String, Object?>{
        'zeta': <String, Object?>{'inner': 1},
        'alpha': <Object?>[
          <String, Object?>{'k': 'v'},
        ],
        'mid': 'plain',
      };

      expect(writer.write(document), writer.write(document));
      expect(writer.write(document).split('\n').take(3).toList(), <String>[
        'zeta:',
        '  inner: 1',
        'alpha:',
      ]);
    });

    test('rejects non-JSON values', () {
      expect(
        () =>
            writer.write(<String, Object?>{'when': DateTime.utc(2026, 10, 7)}),
        throwsArgumentError,
      );
      expect(
        () => writer.write(<String, Object?>{'nan': double.infinity}),
        throwsArgumentError,
      );
      expect(
        () => writer.write(<String, Object?>{'nan': double.nan}),
        throwsArgumentError,
      );
    });

    test('quotes strings a YAML resolver would coerce to another type', () {
      final yaml = writer.write(<String, Object?>{
        'values': <Object?>[
          // Ambiguous booleans and nulls, in several cases.
          'true',
          'TRUE',
          'False',
          'null',
          'NULL',
          '~',
          'yes',
          'off',
          // Integers: plain digits, leading zeros (decimal under the Dart
          // yaml parser), hex, and YAML 1.2 octal.
          '9',
          '018',
          '008',
          '007',
          '-0',
          '+5',
          '0x1F',
          '-0x1A',
          '0o17',
          // Floats: exponents, trailing dots, and leading-dot decimals that
          // double.tryParse accepts.
          '1.5',
          '1e3',
          '5.',
          '.5',
          '+.5',
          '-.5',
          '.5e3',
          // Special floats.
          '.inf',
          '-.INF',
          '.nan',
        ],
      });

      final lines = yaml.split('\n').where((line) => line.isNotEmpty).skip(1);
      for (final line in lines) {
        expect(line.startsWith('- "'), isTrue, reason: line);
        expect(line.endsWith('"'), isTrue, reason: line);
      }
      expect(lines, hasLength(27));
      expect(yaml, contains('- "018"'));
      expect(yaml, contains('- "0o17"'));
      expect(yaml, contains('- "-.5"'));
    });

    test('leaves plain strings that no resolver coerces unquoted', () {
      final yaml = writer.write(<String, Object?>{
        'values': <Object?>[
          '-x',
          '?x',
          ':x',
          'a:b',
          'a#b',
          'Infinity',
          'NaN',
          '1_000',
          '1:30',
          'e5',
          '保存',
          '👍🏽',
          'v1.0.0-beta',
          'user@example.com',
          'cockpit.test/v2',
        ],
      });

      expect(yaml, '''
values:
- -x
- ?x
- :x
- a:b
- a#b
- Infinity
- NaN
- 1_000
- 1:30
- e5
- 保存
- 👍🏽
- v1.0.0-beta
- user@example.com
- cockpit.test/v2
''');
    });

    test('quotes keys through the same scalar rules', () {
      final yaml = writer.write(<String, Object?>{
        'a: b': 1,
        '123': 2,
        '': 3,
        '#k': 4,
        ' k ': 5,
        'true': 6,
        'plain': 7,
      });

      expect(yaml, '''
"a: b": 1
"123": 2
"": 3
"#k": 4
" k ": 5
"true": 6
plain: 7
''');
    });

    test('renders doubles with a fraction or exponent and ints bare', () {
      final yaml = writer.write(<String, Object?>{
        'a': 1.0,
        'b': 1,
        'c': -0.0,
        'd': 100.0,
        'e': 1e21,
        'f': 5e-7,
        'g': 9007199254740993,
        'h': -42,
      });

      expect(yaml, '''
a: 1.0
b: 1
c: -0.0
d: 100.0
e: 1e+21
f: 5e-7
g: 9007199254740993
h: -42
''');
    });

    test('renders empty and nested collections inside lists', () {
      final yaml = writer.write(<String, Object?>{
        'list': <Object?>[
          <Object?>[],
          <Object?>[1],
          <String, Object?>{},
          <String, Object?>{'a': 1},
          <Object?>[
            <Object?>[2],
          ],
          <String, Object?>{
            'b': <String, Object?>{'c': 1},
          },
        ],
      });

      expect(yaml, '''
list:
- []
-
  - 1
- {}
- a: 1
-
  -
    - 2
- b:
    c: 1
''');
    });

    test('renders deeply nested structures', () {
      final yaml = writer.write(<String, Object?>{
        'deep': <String, Object?>{
          'l1': <String, Object?>{
            'l2': <String, Object?>{
              'l3': <String, Object?>{
                'l4': <String, Object?>{'l5': 'bottom'},
              },
            },
          },
        },
        'seq': <Object?>[
          <Object?>[
            <Object?>['deep-list'],
          ],
        ],
      });

      expect(yaml, '''
deep:
  l1:
    l2:
      l3:
        l4:
          l5: bottom
seq:
-
  -
    - deep-list
''');
    });

    test('escapes control characters and DEL', () {
      final yaml = writer.write(<String, Object?>{
        'cr': 'a\rb',
        'nul': 'x\u0000y',
        'vt': 'a\u000bb',
        'del': 'a\u007fb',
        'crlf': 'a\r\nb',
      });

      expect(yaml, '''
cr: "a\\rb"
nul: "x\\u0000y"
vt: "a\\u000bb"
del: "a\\u007fb"
crlf: "a\\r\\nb"
''');
    });

    test('renders a 200-step document deterministically', () {
      Map<String, Object?> stepDocument(int index) => <String, Object?>{
        'stepId': 'st$index',
        'action': <String, Object?>{
          'type': 'tap',
          'locator': <String, Object?>{
            'testId': 'button-$index',
            'fallbacks': <Object?>[
              <String, Object?>{'text': 'Button $index'},
            ],
          },
        },
      };
      final document = <String, Object?>{
        'schemaVersion': 'cockpit.test/v2',
        'id': 'recorded-large',
        'steps': <Object?>[
          for (var index = 1; index <= 200; index += 1) stepDocument(index),
        ],
      };

      final first = writer.write(document);
      final second = writer.write(document);
      expect(second, first);
      // 3 header lines (schemaVersion, id, steps), then 7 lines per step
      // (stepId, action, type, locator, testId, fallbacks, fallback item),
      // plus the empty element after the trailing newline.
      expect(first.split('\n').length, 3 + 200 * 7 + 1);
      expect(first.startsWith('schemaVersion: cockpit.test/v2\n'), isTrue);
      expect(first, contains('testId: button-200'));
    });

    test('renders an empty document as empty output', () {
      expect(writer.write(<String, Object?>{}), '');
    });
  });
}
