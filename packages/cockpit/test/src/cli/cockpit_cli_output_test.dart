import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitCliOutputSelection', () {
    test('defaults to AI standard output', () {
      final parser = ArgParser();
      cockpitAddCliOutputOptions(parser);

      final selection = CockpitCliOutputSelection.fromArguments(
        parser.parse(const <String>[]),
      );

      expect(selection.stdoutFormat, CockpitCliStdoutFormat.auto);
      expect(selection.detail, CockpitCliOutputDetail.standard);
      expect(selection.outputPath, isNull);
    });

    test('reads explicit output controls', () {
      final parser = ArgParser();
      cockpitAddCliOutputOptions(parser);

      final selection = CockpitCliOutputSelection.fromArguments(
        parser.parse(const <String>[
          '--stdout-format',
          'none',
          '--detail',
          'minimal',
          '--output',
          'result.json',
        ]),
      );

      expect(selection.stdoutFormat, CockpitCliStdoutFormat.none);
      expect(selection.detail, CockpitCliOutputDetail.minimal);
      expect(selection.outputPath, 'result.json');
    });

    test('pre-scans output controls before command parsing', () {
      final selection = CockpitCliOutputSelection.fromRawArguments(
        const <String>[
          'daemon',
          'stop',
          '--stdout-format=json',
          '--detail',
          'minimal',
        ],
      );

      expect(selection.stdoutFormat, CockpitCliStdoutFormat.json);
      expect(selection.detail, CockpitCliOutputDetail.minimal);
    });
  });

  test('usage errors honor an explicitly requested JSON format', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'daemon',
      'stop',
      '--mode',
      'immediate',
      '--stdout-format',
      'json',
    ]);

    expect(exitCode, cockpitUsageExitCode);
    final envelope = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect(envelope['ok'], isFalse);
    expect((envelope['error']! as Map<String, Object?>)['code'], 'usage');
  });

  test('workspace exposes indexed documents to CLI-only clients', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final workspace = runner.commands['workspace'];
    expect(workspace, isNotNull);
    expect(workspace!.subcommands, contains('documents'));
    final documents = workspace.subcommands['documents'];
    expect(documents, isNotNull);
    expect(documents!.argParser.options, contains('workspace-id'));
    expect(documents.argParser.options, contains('kind'));
    expect(documents.argParser.options, contains('relative-path'));
  });

  group('CockpitCliOutputRenderer', () {
    test('renders default AI output as compact semantic text', () {
      const renderer = CockpitCliOutputRenderer();

      final text = renderer.renderAi(
        command: 'daemon.status',
        data: const <String, Object?>{
          'running': true,
          'healthy': true,
          'unused': null,
        },
        detail: CockpitCliOutputDetail.standard,
      );

      expect(
        text,
        startsWith('cockpit.v=2 command=daemon.status status=healthy'),
      );
      expect(text, contains('running=true'));
      expect(text, contains('healthy=true'));
      expect(text, isNot(contains('unused')));
      expect(() => jsonDecode(text), throwsFormatException);
    });

    test('prioritizes failing report rows and reports omissions', () {
      const renderer = CockpitCliOutputRenderer(standardMaximumBytes: 2400);
      final cases = <Map<String, Object?>>[
        <String, Object?>{
          'entryId': 'failed-entry',
          'caseId': 'failed-case',
          'outcome': 'failed',
          'stability': 'stable',
          'targetId': 'android',
          'attempts': <Object?>[
            <String, Object?>{
              'attemptId': 'attempt-failed',
              'number': 1,
              'outcome': 'failed',
              'targetId': 'android',
              'failure': <String, Object?>{
                'code': 'assertionFailed',
                'message': 'Expected Save to be visible.',
              },
            },
          ],
        },
        for (var index = 0; index < 80; index += 1)
          <String, Object?>{
            'entryId': 'passed-entry-$index',
            'caseId': 'passed-case-$index',
            'outcome': 'passed',
            'stability': 'stable',
            'targetId': 'android',
            'attempts': <Object?>[
              <String, Object?>{
                'attemptId': 'attempt-passed-$index',
                'number': 1,
                'outcome': 'passed',
                'targetId': 'android',
              },
            ],
          },
      ];

      final text = renderer.renderAi(
        command: 'suite.report',
        data: <String, Object?>{
          'schemaVersion': 'cockpit.report/v2',
          'projectId': 'project',
          'workspaceId': 'workspace',
          'runId': 'run-1',
          'suiteId': 'regression',
          'lifecycle': 'completed',
          'outcome': 'failed',
          'stability': 'stable',
          'durationMs': 4200,
          'counts': const <String, Object?>{
            'total': 81,
            'passed': 80,
            'failed': 1,
          },
          'cases': cases,
        },
        detail: CockpitCliOutputDetail.standard,
      );

      expect(text.length, lessThanOrEqualTo(2400));
      expect(text, contains('status=failed'));
      expect(text, contains('[0] entryId=failed-entry caseId=failed-case'));
      expect(text, contains('truncated=true'));
      expect(text, contains('omitted'));
    });

    test('renders exact JSON without AI projection', () {
      const renderer = CockpitCliOutputRenderer();
      final data = <String, Object?>{
        'items': <Object?>[
          for (var index = 0; index < 100; index += 1)
            <String, Object?>{'id': 'item-$index', 'value': index},
        ],
      };

      final text = renderer.renderJson(data: data);
      final envelope = jsonDecode(text) as Map<String, Object?>;

      expect(envelope['ok'], isTrue);
      expect(
        ((envelope['data']! as Map<String, Object?>)['items']!
            as List<Object?>),
        hasLength(100),
      );
      expect(envelope, isNot(contains('truncated')));
    });
  });

  test(
    'writer atomically persists full JSON and emits a bounded receipt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit-cli-output-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final stdout = StringBuffer();
      final destination = File('${directory.path}/nested/result.json');
      final writer = CockpitCliOutputWriter(
        stdoutSink: stdout,
        workingDirectory: directory.path,
      );

      await writer.writeSuccess(
        command: 'run.get',
        data: const <String, Object?>{
          'runId': 'run-1',
          'lifecycle': 'completed',
          'outcome': 'passed',
        },
        selection: CockpitCliOutputSelection(outputPath: destination.path),
      );

      final persisted =
          jsonDecode(await destination.readAsString()) as Map<String, Object?>;
      expect(persisted['ok'], isTrue);
      expect((persisted['data']! as Map<String, Object?>)['runId'], 'run-1');
      expect(stdout.toString(), startsWith('output=${destination.path} '));
      expect(stdout.toString(), contains('sizeBytes='));
      expect(stdout.toString(), matches(RegExp(r'sha256=[0-9a-f]{64}')));
    },
  );
}
