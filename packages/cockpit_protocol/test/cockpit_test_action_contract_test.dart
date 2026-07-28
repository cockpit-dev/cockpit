import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'all authored and bound action discriminators round-trip through v2',
    () {
      final schema = JsonSchema.create(
        jsonDecode(_schemaFile().readAsStringSync()),
      );
      expect(
        cockpitTestActionSpecs.keys.toSet(),
        CockpitTestActionKind.values.toSet(),
      );

      for (final kind in CockpitTestActionKind.values) {
        final actionJson = _actionJson(kind);
        final template = CockpitTestActionTemplate.fromJson(
          actionJson,
          path: r'$.steps[0].action',
        );
        final bound = CockpitTestAction.fromJson(
          actionJson,
          path: r'$.steps[0].action',
        );
        expect(template.kind, kind, reason: kind.name);
        expect(template.toJson(), actionJson, reason: kind.name);
        expect(bound.kind, kind, reason: kind.name);
        expect(bound.toJson(), actionJson, reason: kind.name);

        final document = <String, Object?>{
          'schemaVersion': 'cockpit.test/v2',
          'kind': 'case',
          'id': 'action${kind.name}',
          'target': <String, Object?>{
            'platform': 'android',
            'targetKind': 'flutterApp',
            'plane': 'semantic',
          },
          'steps': <Object?>[
            <String, Object?>{
              'stepId': 'execute${kind.name}',
              'action': actionJson,
            },
          ],
        };
        expect(schema.validate(document).isValid, isTrue, reason: kind.name);
        expect(CockpitTestCase.fromJson(document).id, 'action${kind.name}');
      }
    },
  );

  test('secret tokens are accepted only by credential input fields', () {
    final token = CockpitTestSecretToken('opaque-secret-token');
    final input = CockpitTestAction(
      kind: CockpitTestActionKind.enterText,
      values: <CockpitTestActionField, Object?>{
        CockpitTestActionField.text: token,
      },
    );
    expect(input.containsSecret, isTrue);
    expect(input.toJson()['text'], '<secret>');

    expect(
      () => CockpitTestAction(
        kind: CockpitTestActionKind.captureScreenshot,
        values: <CockpitTestActionField, Object?>{
          CockpitTestActionField.artifactName: token,
        },
      ),
      throwsFormatException,
    );
    expect(
      () => CockpitTestAction(
        kind: CockpitTestActionKind.assertText,
        values: <CockpitTestActionField, Object?>{
          CockpitTestActionField.text: token,
        },
      ),
      throwsFormatException,
    );
  });

  test('whole-field variables defer validation until binding', () {
    final schema = JsonSchema.create(
      jsonDecode(_schemaFile().readAsStringSync()),
    );
    final actions = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'setTextEditingValue',
        'text': <String, Object?>{r'$var': 'editedText'},
      },
      <String, Object?>{
        'type': 'setTextEditingValue',
        'selectionStart': <String, Object?>{r'$var': 'selectionStart'},
        'selectionEnd': <String, Object?>{r'$var': 'selectionEnd'},
      },
      <String, Object?>{
        'type': 'panZoom',
        'scale': <String, Object?>{r'$var': 'zoomScale'},
      },
      <String, Object?>{
        'type': 'multiTouch',
        'sequence': <String, Object?>{r'$var': 'touchSequence'},
      },
      <String, Object?>{
        'type': 'sendKeyEvent',
        'keyRequest': <String, Object?>{r'$var': 'keyRequest'},
      },
    ];

    for (final action in actions) {
      final document = _documentFor(action);
      expect(schema.validate(document).isValid, isTrue, reason: '$action');
      expect(
        () => CockpitTestCase.fromJson(document),
        returnsNormally,
        reason: '$action',
      );
    }
  });

  test('key requests reject unknown fields in the model and schema', () {
    final schema = JsonSchema.create(
      jsonDecode(_schemaFile().readAsStringSync()),
    );
    final action = <String, Object?>{
      'type': 'sendKeyEvent',
      'keyRequest': <String, Object?>{
        'logicalKey': 'Enter',
        'physicalKey': 'Enter',
        'character': '\n',
        'unknownKeyField': true,
      },
    };
    final document = _documentFor(action);

    expect(schema.validate(document).isValid, isFalse);
    expect(() => CockpitTestCase.fromJson(document), throwsFormatException);
  });
}

Map<String, Object?> _documentFor(Map<String, Object?> action) =>
    <String, Object?>{
      'schemaVersion': 'cockpit.test/v2',
      'kind': 'case',
      'id': 'actionCase',
      'target': <String, Object?>{
        'platform': 'android',
        'targetKind': 'flutterApp',
        'plane': 'semantic',
      },
      'variables': <String, Object?>{
        'editedText': <String, Object?>{
          'source': 'input',
          'type': 'string',
          'required': true,
        },
        'selectionStart': <String, Object?>{
          'source': 'input',
          'type': 'integer',
          'required': true,
        },
        'selectionEnd': <String, Object?>{
          'source': 'input',
          'type': 'integer',
          'required': true,
        },
        'zoomScale': <String, Object?>{
          'source': 'input',
          'type': 'number',
          'required': true,
        },
        'touchSequence': <String, Object?>{
          'source': 'input',
          'type': 'json',
          'required': true,
        },
        'keyRequest': <String, Object?>{
          'source': 'input',
          'type': 'json',
          'required': true,
        },
      },
      'steps': <Object?>[
        <String, Object?>{'stepId': 'executeAction', 'action': action},
      ],
    };

Map<String, Object?> _actionJson(CockpitTestActionKind kind) {
  final locator = <String, Object?>{'testId': 'target'};
  return switch (kind) {
    CockpitTestActionKind.tap => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'activation': 'semantic',
    },
    CockpitTestActionKind.longPress => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'durationMs': 500,
    },
    CockpitTestActionKind.doubleTap ||
    CockpitTestActionKind.focusTextInput ||
    CockpitTestActionKind.increase ||
    CockpitTestActionKind.decrease ||
    CockpitTestActionKind.dismiss => <String, Object?>{
      'type': kind.name,
      'locator': locator,
    },
    CockpitTestActionKind.enterText => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'text': '  preserved text  ',
    },
    CockpitTestActionKind.eraseText => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'characters': 4,
    },
    CockpitTestActionKind.copyText => <String, Object?>{
      'type': kind.name,
      'locator': locator,
    },
    CockpitTestActionKind.pasteText => <String, Object?>{
      'type': kind.name,
      'locator': locator,
    },
    CockpitTestActionKind.setTextEditingValue => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'text': 'edited',
      'selectionStart': 0,
      'selectionEnd': 6,
    },
    CockpitTestActionKind.sendTextInputAction => <String, Object?>{
      'type': kind.name,
      'inputAction': 'done',
    },
    CockpitTestActionKind.sendKeyEvent ||
    CockpitTestActionKind.sendKeyDownEvent ||
    CockpitTestActionKind.sendKeyUpEvent => <String, Object?>{
      'type': kind.name,
      'keyRequest': <String, Object?>{'logicalKey': 'Enter'},
    },
    CockpitTestActionKind.drag => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'dx': 0,
      'dy': 120,
      'durationMs': 300,
    },
    CockpitTestActionKind.fling => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'dx': 0,
      'dy': -200,
      'velocity': 1200,
    },
    CockpitTestActionKind.swipe => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'direction': 'up',
      'distance': 0.5,
      'durationMs': 250,
    },
    CockpitTestActionKind.pinchZoom => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'scale': 2,
    },
    CockpitTestActionKind.rotate => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'rotationRadians': 0.5,
    },
    CockpitTestActionKind.panZoom => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'panDx': 20,
      'panDy': -10,
      'scale': 1.2,
    },
    CockpitTestActionKind.multiTouch => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'sequence': <String, Object?>{
        'steps': <Object?>[
          <String, Object?>{
            'pointer': 0,
            'phase': 'down',
            'atMs': 0,
            'dx': 0,
            'dy': 0,
          },
          <String, Object?>{
            'pointer': 0,
            'phase': 'up',
            'atMs': 100,
            'dx': 10,
            'dy': 10,
          },
        ],
      },
    },
    CockpitTestActionKind.scrollUntilVisible => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'direction': 'down',
      'maxScrolls': 10,
      'durationMs': 200,
      'revealAlignment': 'nearest',
    },
    CockpitTestActionKind.back ||
    CockpitTestActionKind.dismissKeyboard ||
    CockpitTestActionKind.clearNetworkActivity => <String, Object?>{
      'type': kind.name,
    },
    CockpitTestActionKind.showOnScreen => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'revealAlignment': 'center',
    },
    CockpitTestActionKind.waitForNetworkIdle ||
    CockpitTestActionKind.waitForUiIdle => <String, Object?>{
      'type': kind.name,
      'quietMs': 400,
    },
    CockpitTestActionKind.waitFor => <String, Object?>{
      'type': kind.name,
      'condition': <String, Object?>{
        'type': 'visible',
        'locator': locator,
        'expected': true,
      },
    },
    CockpitTestActionKind.assertVisible => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'expected': true,
    },
    CockpitTestActionKind.assertText => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'text': '^Ready',
      'matchMode': 'regex',
    },
    CockpitTestActionKind.assertScreenshot => <String, Object?>{
      'type': kind.name,
      'locator': locator,
      'baseline': 'baselines/home.png',
      'pixelTolerance': 0.1,
      'maxDifferingPixelRatio': 0.01,
      'artifactName': 'home',
      'captureOptions': <String, Object?>{
        'profile': 'flutterPreferred',
        'allowFallback': false,
      },
    },
    CockpitTestActionKind.travel => <String, Object?>{
      'type': kind.name,
      'route': <Object?>[
        <String, Object?>{'latitude': 31.2304, 'longitude': 121.4737},
        <String, Object?>{'latitude': 31.231, 'longitude': 121.474},
      ],
      'intervalMs': 100,
    },
    CockpitTestActionKind.system => <String, Object?>{
      'type': kind.name,
      'name': 'activateWindow',
      'parameters': const <String, Object?>{},
    },
    CockpitTestActionKind.captureScreenshot => <String, Object?>{
      'type': kind.name,
      'artifactName': 'acceptanceScreenshot',
      'captureOptions': <String, Object?>{
        'includeSnapshot': true,
        'allowFallback': false,
      },
    },
    CockpitTestActionKind.collectSnapshot => <String, Object?>{
      'type': kind.name,
      'snapshotOptions': <String, Object?>{'profile': 'live', 'maxTargets': 20},
    },
  };
}

File _schemaFile() {
  final direct = File(p.join('schema', 'cockpit.test.v2.schema.json'));
  if (direct.existsSync()) return direct;
  return File(
    p.join(
      'packages',
      'cockpit_protocol',
      'schema',
      'cockpit.test.v2.schema.json',
    ),
  );
}
