import 'package:args/command_runner.dart';

import '../../supervisor/cockpit_daemon_host.dart';
import '../cockpit_cli_runtime.dart';
import 'daemon_policy_commands.dart';

final class CockpitDaemonCommand extends Command<int> {
  CockpitDaemonCommand(this.runtime) {
    addSubcommand(CockpitDaemonPolicyCommand(runtime));
    addSubcommand(
      CockpitLeafCommand(
        name: 'start',
        description: 'Start the Cockpit Supervisor daemon.',
        action: (_) async {
          final client = await runtime.client();
          await client.lifecycle.start();
          runtime.success((await client.lifecycle.status()).toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        name: 'status',
        description: 'Read Supervisor daemon status.',
        action: (_) async {
          runtime.success(
            (await (await runtime.client()).lifecycle.status()).toJson(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        name: 'stop',
        description: 'Stop the Supervisor daemon.',
        configure: (parser) => parser.addOption(
          'mode',
          allowed: CockpitDaemonShutdownMode.values.map((value) => value.name),
          defaultsTo: CockpitDaemonShutdownMode.drain.name,
        ),
        action: (arguments) async {
          final mode = CockpitDaemonShutdownMode.values.byName(
            arguments.option('mode')!,
          );
          await (await runtime.client()).lifecycle.stop(mode: mode);
          runtime.success(<String, Object?>{
            'stopped': true,
            'mode': mode.name,
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        name: 'restart',
        description: 'Restart the Supervisor daemon.',
        action: (_) async {
          final client = await runtime.client();
          await client.lifecycle.restart();
          runtime.success((await client.lifecycle.status()).toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        name: 'logs',
        description: 'Read bounded Supervisor daemon logs.',
        configure: (parser) => parser.addOption(
          'lines',
          defaultsTo: '200',
          help: 'Maximum number of trailing log lines (1-2000).',
        ),
        action: (arguments) async {
          final count = int.tryParse(arguments.option('lines')!);
          if (count == null) throw const FormatException('--lines is invalid.');
          runtime.success(<String, Object?>{
            'lines': await (await runtime.client()).lifecycle.logs(
              maximumLines: count,
            ),
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        name: 'doctor',
        description: 'Inspect Supervisor daemon installation health.',
        action: (_) async {
          runtime.success(await (await runtime.client()).lifecycle.doctor());
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'daemon';

  @override
  String get description => 'Manage the Cockpit Supervisor daemon.';
}
