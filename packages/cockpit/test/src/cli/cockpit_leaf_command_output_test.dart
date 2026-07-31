import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
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
      '--stdout-format',
      'json',
      '--detail',
      'full',
    ]);

    expect(exitCode, cockpitSuccessExitCode);
    expect(jsonDecode(stdout.toString()), <String, Object?>{'value': 1});
  });
}
