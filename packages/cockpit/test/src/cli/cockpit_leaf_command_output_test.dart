import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:test/test.dart';

void main() {
  test('leaf commands expose and apply output options', () async {
    final stdout = StringBuffer();
    final runtime = CockpitCliRuntime(stdoutSink: stdout);
    final runner = CommandRunner<int>('cockpit', 'test')
      ..addCommand(
        CockpitLeafCommand(
          runtime: runtime,
          name: 'probe',
          description: 'Probe output.',
          action: (_) async {
            await runtime.success(const <String, Object?>{'value': 1});
            return cockpitSuccessExitCode;
          },
        ),
      );

    final exitCode = await runner.run(const <String>[
      'probe',
      '--format',
      'json',
      '--view',
      'full',
    ]);

    expect(exitCode, cockpitSuccessExitCode);
    expect(jsonDecode(stdout.toString()), <String, Object?>{'value': 1});
  });

  test('every bounded executable command exposes one duration timeout', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final missing = <String>[];

    void visit(String path, Command<int> command) {
      if (command.subcommands.isEmpty) {
        if (path != 'help' &&
            path != 'serve-mcp' &&
            !command.argParser.options.containsKey('timeout')) {
          missing.add(path);
        }
        return;
      }
      for (final entry in command.subcommands.entries) {
        visit('$path ${entry.key}', entry.value);
      }
    }

    for (final entry in runner.commands.entries) {
      visit(entry.key, entry.value);
    }
    expect(missing, isEmpty);
  });

  test('cli failure envelopes keep the underlying cause', () {
    final stderr = StringBuffer();
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: stderr,
    );
    final runner = CockpitCommandRunner(runtime: runtime);

    expect(
      runner.reportFailure(StateError('boom')),
      cockpitUnavailableExitCode,
    );
    expect(stderr.toString(), contains('internalError'));
    expect(stderr.toString(), contains('Cockpit client failed unexpectedly'));
    expect(stderr.toString(), contains('StateError'));
    expect(stderr.toString(), contains('Bad state: boom'));

    stderr.clear();
    expect(
      runner.reportFailure(
        FileSystemException(
          'Directory listing failed',
          '/tmp/cockpit-missing',
          OSError('No such file or directory', 2),
        ),
      ),
      cockpitNoInputExitCode,
    );
    expect(stderr.toString(), contains('No such file or directory'));
    expect(stderr.toString(), contains('errno 2'));
    expect(stderr.toString(), contains('/tmp/cockpit-missing'));

    stderr.clear();
    expect(
      runner.reportFailure(
        const FormatException('Unexpected character', '{bad', 1),
      ),
      cockpitDataExitCode,
    );
    expect(stderr.toString(), contains('Unexpected character'));
    expect(stderr.toString(), contains('offset 1'));
  });
}
