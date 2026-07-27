import 'dart:convert';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  const importer = CockpitControlWorkflowImporter();
  const compiler = CockpitTestDocumentCompiler();

  test('import is deterministic and emits canonical compilable V2', () {
    final source = '${jsonEncode(_legacyScript())}\n';
    final first = importer.import(_request(source));
    final second = importer.import(_request(source));

    expect(first.toJson(), second.toJson());
    expect(
      first.manifest.sourceSha256,
      sha256.convert(utf8.encode(source)).toString(),
    );
    expect(first.testCase.target.targetKind, 'flutterApp');
    expect(first.testCase.defaults.failFast, isFalse);
    expect(first.manifest.mappings, hasLength(2));

    final compiled = compiler.compile(jsonEncode(first.testCase.toJson()));
    expect(compiled.isSuccess, isTrue, reason: _diagnostics(compiled));
  });

  test('YAML legacy input preserves exact source hash and V2 semantics', () {
    const source = '''
schemaVersion: 1
sessionId: legacy-session
taskId: legacy-task
platform: android
failFast: false
recording:
  purpose: acceptance
  name: acceptanceRun
  mode: auto
  allowFallback: false
  attachToStep: true
  tailStabilizationMs: 300
steps:
  - stepId: captureFailure
    stepType: command
    command:
      commandId: capture-failure
      commandType: captureScreenshot
      parameters: {}
      screenshotRequest:
        reason: assertion_failure
        name: failureState
        includeSnapshot: true
        attachToStep: true
        profile: diagnostic
        allowFallback: false
''';
    final yamlResult = importer.import(_request(source));
    final jsonResult = importer.import(_request(jsonEncode(_legacyScript())));

    expect(yamlResult.testCase.toJson(), jsonResult.testCase.toJson());
    expect(
      yamlResult.manifest.sourceSha256,
      sha256.convert(utf8.encode(source)).toString(),
    );
    final compiled = compiler.compile(jsonEncode(yamlResult.testCase.toJson()));
    expect(compiled.isSuccess, isTrue, reason: _diagnostics(compiled));
  });

  test('capture and recording options retain authored semantics', () {
    final result = importer.import(_request(jsonEncode(_legacyScript())));
    final recording =
        result.testCase.setup.single.operation
            as CockpitTestStartRecordingOperationTemplate;
    expect(recording.allowFallback, isFalse);
    expect(recording.attachToStep, isTrue);

    final operation =
        result.testCase.steps.single.operation
            as CockpitTestActionOperationTemplate;
    final options =
        operation.action.values[CockpitTestActionField.captureOptions]!.value
            as Map<Object?, Object?>;
    expect(options, <String, Object?>{
      'reason': 'assertion_failure',
      'includeSnapshot': true,
      'profile': 'diagnostic',
      'allowFallback': false,
    });
  });

  test('normalized step id collisions fail with an actionable error', () {
    final source = _legacyScript()
      ..remove('recording')
      ..['steps'] = <Object?>[
        _commandStep('pay now', 'back-one'),
        _commandStep('pay_now', 'back-two'),
      ];

    expect(
      () => importer.import(_request(jsonEncode(source))),
      throwsA(
        isA<CockpitControlWorkflowImportException>().having(
          (error) => error.error.message,
          'message',
          allOf(contains('both normalize'), contains('Rename one')),
        ),
      ),
    );
  });

  test('unsupported behavior is rejected instead of being discarded', () {
    final source = _legacyScript()
      ..remove('recording')
      ..['steps'] = <Object?>[
        <String, Object?>{
          'stepId': 'submitInput',
          'stepType': 'command',
          'command': <String, Object?>{
            'commandId': 'submit-input',
            'commandType': 'sendTextInputAction',
            'parameters': <String, Object?>{
              'inputAction': 'done',
              'requestFocus': false,
            },
          },
        },
      ];

    expect(
      () => importer.import(_request(jsonEncode(source))),
      throwsA(
        isA<CockpitControlWorkflowImportException>().having(
          (error) => error.error.message,
          'message',
          contains('requestFocus=false'),
        ),
      ),
    );
  });

  test('ambiguous or unknown legacy fields are rejected before conversion', () {
    final unknown = _legacyScript()..['unknownBehavior'] = true;
    expect(
      () => importer.import(_request(jsonEncode(unknown))),
      throwsA(isA<CockpitControlWorkflowImportException>()),
    );

    final ambiguous = _legacyScript()
      ..['commands'] = <Object?>[
        <String, Object?>{
          'commandId': 'ignored-command',
          'commandType': 'back',
          'parameters': const <String, Object?>{},
        },
      ];
    expect(
      () => importer.import(_request(jsonEncode(ambiguous))),
      throwsA(isA<CockpitControlWorkflowImportException>()),
    );
  });

  test('unknown fields in nested legacy value objects are rejected', () {
    final sources = <Map<String, Object?>>[
      _legacyScript()
        ..['environment'] = <String, Object?>{
          'platform': 'android',
          'unknownEnvironmentField': true,
        },
      _legacyScript()..update(
        'recording',
        (value) =>
            (value! as Map<String, Object?>)..['unknownRecordingField'] = true,
      ),
      _legacyScript()
        ..remove('recording')
        ..['steps'] = <Object?>[
          <String, Object?>{
            'stepId': 'startRecording',
            'stepType': 'startRecording',
            'recording': <String, Object?>{
              'purpose': 'acceptance',
              'name': 'run',
              'unknownRecordingField': true,
            },
          },
        ],
      _legacyScript()..update('steps', (value) {
        final command =
            ((value! as List<Object?>).single
                    as Map<String, Object?>)['command']
                as Map<String, Object?>;
        final screenshot =
            command['screenshotRequest']! as Map<String, Object?>;
        screenshot['unknownScreenshotField'] = true;
        return value;
      }),
      _legacyScript()..update('steps', (value) {
        final command =
            ((value! as List<Object?>).single
                    as Map<String, Object?>)['command']
                as Map<String, Object?>;
        command['snapshotOptions'] = <String, Object?>{
          'profile': 'live',
          'unknownSnapshotField': true,
        };
        return value;
      }),
      _legacyScript()..update('steps', (value) {
        final command =
            ((value! as List<Object?>).single
                    as Map<String, Object?>)['command']
                as Map<String, Object?>;
        command['snapshotOptions'] = <String, Object?>{
          'networkQuery': <String, Object?>{
            'onlyFailures': true,
            'unknownNetworkQueryField': true,
          },
        };
        return value;
      }),
    ];

    for (final source in sources) {
      expect(
        () => importer.import(_request(jsonEncode(source))),
        throwsA(isA<CockpitControlWorkflowImportException>()),
      );
    }
  });

  test('multi-signal locators migrate as conjunctive V2 signals', () {
    final source = _legacyScript()
      ..remove('recording')
      ..['steps'] = <Object?>[
        <String, Object?>{
          'stepId': 'tapPayment',
          'stepType': 'command',
          'command': <String, Object?>{
            'commandId': 'tap-payment',
            'commandType': 'tap',
            'locator': <String, Object?>{
              'cockpitId': 'paymentButton',
              'text': 'Pay now',
              'fallbacks': const <Object?>[],
            },
            'parameters': const <String, Object?>{},
          },
        },
      ];

    final result = importer.import(_request(jsonEncode(source)));
    final operation =
        result.testCase.steps.single.operation
            as CockpitTestActionOperationTemplate;
    final locator = operation.action.locator!;

    expect(locator.testId!.value, 'paymentButton');
    expect(locator.text!.value, 'Pay now');
    expect(locator.fallbacks, isEmpty);
    final compiled = compiler.compile(jsonEncode(result.testCase.toJson()));
    expect(compiled.isSuccess, isTrue, reason: _diagnostics(compiled));
  });

  test('waitFor minVisibleTargets is rejected instead of discarded', () {
    final source = _legacyScript()
      ..remove('recording')
      ..['steps'] = <Object?>[
        <String, Object?>{
          'stepId': 'waitForReadyTargets',
          'stepType': 'command',
          'command': <String, Object?>{
            'commandId': 'wait-ready-targets',
            'commandType': 'waitFor',
            'parameters': <String, Object?>{
              'text': 'Ready',
              'minVisibleTargets': 2,
            },
          },
        },
      ];

    expect(
      () => importer.import(_request(jsonEncode(source))),
      throwsA(
        isA<CockpitControlWorkflowImportException>().having(
          (error) => error.error.message,
          'message',
          contains('minVisibleTargets'),
        ),
      ),
    );
  });

  test('waitFor locators migrate inside the V2 condition', () {
    final source = _legacyScript()
      ..remove('recording')
      ..['steps'] = <Object?>[
        <String, Object?>{
          'stepId': 'waitForReadyTarget',
          'stepType': 'command',
          'command': <String, Object?>{
            'commandId': 'wait-ready-target',
            'commandType': 'waitFor',
            'locator': <String, Object?>{
              'cockpitId': 'readyTarget',
              'fallbacks': const <Object?>[],
            },
            'parameters': const <String, Object?>{},
          },
        },
      ];

    final result = importer.import(_request(jsonEncode(source)));
    final action =
        (result.testCase.steps.single.operation
                as CockpitTestActionOperationTemplate)
            .action;
    expect(action.locator, isNull);
    expect(
      action.condition?.locator?.strategy,
      CockpitTestLocatorStrategy.testId,
    );
  });
}

CockpitTestImportRequest _request(String source) => CockpitTestImportRequest(
  sourceVersion: 1,
  sourceText: source,
  projectId: 'projectOne',
  workspaceId: 'workspaceOne',
  caseId: 'importedCase',
  engineVersion: '2.0.0',
);

Map<String, Object?> _legacyScript() => <String, Object?>{
  'schemaVersion': 1,
  'sessionId': 'legacy-session',
  'taskId': 'legacy-task',
  'platform': 'android',
  'failFast': false,
  'recording': <String, Object?>{
    'purpose': 'acceptance',
    'name': 'acceptanceRun',
    'mode': 'auto',
    'allowFallback': false,
    'attachToStep': true,
    'tailStabilizationMs': 300,
  },
  'steps': <Object?>[
    <String, Object?>{
      'stepId': 'captureFailure',
      'stepType': 'command',
      'command': <String, Object?>{
        'commandId': 'capture-failure',
        'commandType': 'captureScreenshot',
        'parameters': const <String, Object?>{},
        'screenshotRequest': <String, Object?>{
          'reason': 'assertion_failure',
          'name': 'failureState',
          'includeSnapshot': true,
          'attachToStep': true,
          'profile': 'diagnostic',
          'allowFallback': false,
        },
      },
    },
  ],
};

Map<String, Object?> _commandStep(String stepId, String commandId) =>
    <String, Object?>{
      'stepId': stepId,
      'stepType': 'command',
      'command': <String, Object?>{
        'commandId': commandId,
        'commandType': 'back',
        'parameters': const <String, Object?>{},
      },
    };

String _diagnostics(CockpitTestCompilationResult result) => result.diagnostics
    .map((diagnostic) => '${diagnostic.code}: ${diagnostic.message}')
    .join('\n');
