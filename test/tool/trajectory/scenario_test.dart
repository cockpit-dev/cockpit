import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/src/trajectory/scenario.dart';

const String _validScenario = '''
schema: cockpit.training/scenario-v1
id: sample_flow
app:
  name: cockpit_demo
  directory: examples/cockpit_demo/cockpit
  platform: macos
goal: 把深色模式打开
paraphrases:
  - 帮我切到暗色主题
  - switch to dark theme
completion: 深色模式已开启并验证。
includeSetup: false
steps:
  - action: tap
    selector: Settings
    expect: {ok: true}
  - action: type
    text: hello world
    into: Message
  - action: screenshot
  - command: cockpit dev status
    timeoutMs: 5000
''';

void main() {
  group('parseScenario', () {
    test('parses a valid scenario', () {
      final scenario = parseScenario(_validScenario, sourceName: 'sample');
      expect(scenario.id, 'sample_flow');
      expect(scenario.app.name, 'cockpit_demo');
      expect(scenario.app.platform, 'macos');
      expect(scenario.goal, '把深色模式打开');
      expect(scenario.paraphrases, <String>[
        '帮我切到暗色主题',
        'switch to dark theme',
      ]);
      expect(scenario.steps, hasLength(4));
      expect(scenario.steps.first.selector, 'Settings');
      expect(scenario.steps[1].text, 'hello world');
      expect(scenario.steps[1].into, 'Message');
      expect(scenario.steps[2].isScreenshot, isTrue);
      expect(scenario.steps[3].command, 'cockpit dev status');
      expect(scenario.steps[3].timeoutMs, 5000);
      expect(scenario.steps[3].onFailure, ScenarioFailurePolicy.abort);
    });

    test('rejects steps with both action and command', () {
      final error = _captureFormatError('''
schema: cockpit.training/scenario-v1
id: bad
app: {name: a, directory: b, platform: macos}
goal: g
completion: c
steps:
  - action: tap
    command: cockpit dev status
    selector: Settings
''');
      expect(error.message, contains("exactly one of 'action' or 'command'"));
    });

    test('rejects steps with neither action nor command', () {
      final error = _captureFormatError('''
schema: cockpit.training/scenario-v1
id: bad
app: {name: a, directory: b, platform: macos}
goal: g
completion: c
steps:
  - selector: Settings
''');
      expect(error.message, contains("exactly one of 'action' or 'command'"));
    });

    test('reports wrong schema and bad onFailure together', () {
      final error = _captureFormatError('''
schema: cockpit.training/other-v9
id: bad
app: {name: a, directory: b, platform: macos}
goal: g
completion: c
steps:
  - action: tap
    selector: Settings
    onFailure: explode
''');
      expect(error.message, contains("unsupported schema"));
      expect(
        error.message,
        contains("'onFailure' must be 'abort' or 'continue'"),
      );
    });

    test('rejects empty step lists', () {
      final error = _captureFormatError('''
schema: cockpit.training/scenario-v1
id: bad
app: {name: a, directory: b, platform: macos}
goal: g
completion: c
steps: []
''');
      expect(error.message, contains("'steps' must be a non-empty list"));
    });

    test('rejects non-mapping documents', () {
      final error = _captureFormatError('- just\n- a\n- list\n');
      expect(error.message, contains('document must be a mapping'));
    });
  });

  group('buildArgv', () {
    test('appends session to tap selectors', () {
      const step = ScenarioStep(action: 'tap', selector: 'Settings');
      expect(
        step.buildArgv(sessionHandle: 'x1', screenshotPath: '/tmp/x.png'),
        <String>['dev', 'tap', 'Settings', '--session', 'x1'],
      );
    });

    test('maps type with --into', () {
      const step = ScenarioStep(
        action: 'type',
        text: 'hello world',
        into: 'Task title',
      );
      expect(
        step.buildArgv(sessionHandle: 'h', screenshotPath: '/tmp/x.png'),
        <String>[
          'dev',
          'type',
          'hello world',
          '--into',
          'Task title',
          '--session',
          'h',
        ],
      );
    });

    test('maps screenshot to --save with the prepared path', () {
      const step = ScenarioStep(action: 'screenshot');
      expect(
        step.buildArgv(sessionHandle: 'h', screenshotPath: '/tmp/step-00.png'),
        <String>[
          'dev',
          'screenshot',
          '--save',
          '/tmp/step-00.png',
          '--session',
          'h',
        ],
      );
    });

    test('raw commands drop the leading cockpit token', () {
      const step = ScenarioStep(command: 'cockpit dev status');
      expect(
        step.buildArgv(sessionHandle: 'h', screenshotPath: '/tmp/x.png'),
        <String>['dev', 'status', '--session', 'h'],
      );
    });

    test('extra args are appended before the session flag', () {
      const step = ScenarioStep(
        action: 'scroll',
        selector: 'Activity',
        args: <String>['--down', '3'],
      );
      expect(
        step.buildArgv(sessionHandle: 'h', screenshotPath: '/tmp/x.png'),
        <String>['dev', 'scroll', 'Activity', '--down', '3', '--session', 'h'],
      );
    });
  });

  group('displayCommand', () {
    test('quotes selectors containing whitespace', () {
      const step = ScenarioStep(action: 'tap', selector: 'Dark mode');
      expect(
        step.displayCommand(sessionHandle: 'h', screenshotName: 'step-00.png'),
        "cockpit dev tap 'Dark mode' --session h",
      );
    });

    test('screenshot commands show the bare file name', () {
      const step = ScenarioStep(action: 'screenshot');
      expect(
        step.displayCommand(sessionHandle: 'h', screenshotName: 'step-02.png'),
        'cockpit dev screenshot --save step-02.png --session h',
      );
    });
  });

  group('evaluate', () {
    test('ok expectation matches exit code 0 only', () {
      const step = ScenarioStep(action: 'tap', selector: 'x');
      expect(
        step.evaluate(
          exitCode: 0,
          stdout: 'ok: true',
          stderr: '',
          timedOut: false,
        ),
        isTrue,
      );
      expect(
        step.evaluate(exitCode: 65, stdout: '', stderr: '', timedOut: false),
        isFalse,
      );
    });

    test('failure expectations require a nonzero exit or timeout', () {
      const step = ScenarioStep(
        action: 'tap',
        selector: 'x',
        expect: ScenarioExpectation(ok: false),
      );
      expect(
        step.evaluate(exitCode: 65, stdout: '', stderr: '', timedOut: false),
        isTrue,
      );
      expect(
        step.evaluate(exitCode: 0, stdout: '', stderr: '', timedOut: false),
        isFalse,
      );
      expect(
        step.evaluate(exitCode: 0, stdout: '', stderr: '', timedOut: true),
        isTrue,
      );
    });

    test('failure code must appear in the observation or stderr', () {
      const step = ScenarioStep(
        action: 'tap',
        selector: 'x',
        expect: ScenarioExpectation(ok: false, code: 'ambiguousTarget'),
      );
      expect(
        step.evaluate(
          exitCode: 65,
          stdout: 'error: {code: ambiguousTarget}',
          stderr: '',
          timedOut: false,
        ),
        isTrue,
      );
      expect(
        step.evaluate(
          exitCode: 65,
          stdout: 'error: {code: targetNotFound}',
          stderr: '',
          timedOut: false,
        ),
        isFalse,
      );
      expect(
        step.evaluate(
          exitCode: 64,
          stdout: '',
          stderr: '{"error":{"code":"ambiguousTarget"}}',
          timedOut: false,
        ),
        isTrue,
      );
    });
  });

  group('round trips through the shipped scenario files', () {
    test('every committed scenario parses', () {
      final directory = Directory('tool/trajectory/scenarios');
      final files = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        final scenario = parseScenario(
          file.readAsStringSync(),
          sourceName: file.path,
        );
        expect(scenario.steps, isNotEmpty, reason: file.path);
      }
    });
  });
}

ScenarioFormatException _captureFormatError(String source) {
  try {
    parseScenario(source, sourceName: 'test');
  } on ScenarioFormatException catch (error) {
    return error;
  }
  fail('parseScenario did not reject the input.');
}
