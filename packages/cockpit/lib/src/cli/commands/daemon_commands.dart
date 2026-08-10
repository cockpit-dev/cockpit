import 'package:args/command_runner.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../../supervisor/cockpit_daemon_host.dart';
import '../cockpit_cli_runtime.dart';
import 'daemon_policy_commands.dart';

final class CockpitDaemonCommand extends Command<int> {
  CockpitDaemonCommand(this.runtime) {
    addSubcommand(CockpitDaemonPolicyCommand(runtime));
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'start',
        description: 'Start the Cockpit Supervisor daemon.',
        defaultTimeout: const Duration(minutes: 3),
        maximumTimeout: const Duration(minutes: 10),
        configure: (parser) => parser.addFlag(
          'yolo',
          negatable: false,
          help:
              'Require unrestricted authorization; otherwise preserve a running daemon mode.',
        ),
        action: (arguments) async {
          final client = await runtime.client();
          await client.lifecycle.start(
            authorizationMode: arguments.flag('yolo')
                ? CockpitAuthorizationMode.yolo
                : null,
            timeout: runtime.remainingTimeout,
          );
          await runtime.success((await client.lifecycle.status()).toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'status',
        description: 'Read Supervisor daemon status.',
        action: (_) async {
          await runtime.success(
            (await (await runtime.client()).lifecycle.status()).toJson(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'stop',
        description: 'Stop the Supervisor daemon.',
        defaultTimeout: const Duration(minutes: 2),
        maximumTimeout: const Duration(minutes: 10),
        configure: (parser) => parser.addOption(
          'mode',
          allowed: CockpitDaemonShutdownMode.values.map((value) => value.name),
          defaultsTo: CockpitDaemonShutdownMode.drain.name,
        ),
        action: (arguments) async {
          final mode = CockpitDaemonShutdownMode.values.byName(
            arguments.option('mode')!,
          );
          await (await runtime.client()).lifecycle.stop(
            mode: mode,
            timeout: runtime.remainingTimeout,
          );
          await runtime.success(<String, Object?>{
            'stopped': true,
            'mode': mode.name,
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'restart',
        description: 'Restart the Supervisor daemon.',
        defaultTimeout: const Duration(minutes: 5),
        maximumTimeout: const Duration(minutes: 15),
        configure: (parser) => parser.addFlag(
          'yolo',
          negatable: false,
          help: 'Restart this daemon process with unrestricted authorization.',
        ),
        action: (arguments) async {
          final client = await runtime.client();
          await client.lifecycle.restart(
            authorizationMode: arguments.flag('yolo')
                ? CockpitAuthorizationMode.yolo
                : null,
            timeout: runtime.remainingTimeout,
          );
          await runtime.success((await client.lifecycle.status()).toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'logs',
        description: 'Read bounded Supervisor daemon logs.',
        configure: (parser) => parser.addOption(
          'lines',
          defaultsTo: '50',
          help: 'Maximum number of trailing log lines (1-2000).',
        ),
        action: (arguments) async {
          final count = int.tryParse(arguments.option('lines')!);
          if (count == null) throw const FormatException('--lines is invalid.');
          await runtime.success(<String, Object?>{
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
        runtime: runtime,
        name: 'doctor',
        description: 'Inspect Supervisor daemon installation health.',
        action: (_) async {
          await runtime.success(
            await (await runtime.client()).lifecycle.doctor(),
          );
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
