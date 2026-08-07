import 'dart:convert';

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
      '--verbosity',
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
}
