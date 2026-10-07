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
    });
  });
}
