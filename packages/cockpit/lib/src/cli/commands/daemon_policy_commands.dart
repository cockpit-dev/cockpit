import 'package:args/command_runner.dart';

import '../../supervisor/cockpit_daemon_client.dart';
import '../../supervisor/cockpit_daemon_host.dart';
import '../cockpit_cli_runtime.dart';

final class CockpitDaemonPolicyCommand extends Command<int> {
  CockpitDaemonPolicyCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'show',
        description: 'Read the persisted Supervisor authorization policy.',
        action: (_) async {
          final policy = await (await runtime.authorizationPolicyStore())
              .read();
          await runtime.success(policy.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'validate',
        description: 'Validate an authorization policy file.',
        configure: (parser) => parser.addOption('file', mandatory: true),
        action: (arguments) async {
          final policy = runtime.authorizationPolicyFile(
            arguments.option('file')!,
          );
          await runtime.success(policy.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'apply',
        description: 'Atomically replace the Supervisor authorization policy.',
        configure: (parser) {
          parser
            ..addOption('file', mandatory: true)
            ..addFlag(
              'restart',
              negatable: false,
              help: 'Restart or start the daemon with the new policy.',
            );
        },
        action: (arguments) async {
          final policy = runtime.authorizationPolicyFile(
            arguments.option('file')!,
          );
          final restart = arguments.flag('restart');
          final lifecycle = (await runtime.client()).lifecycle;
          final before = await lifecycle.status();
          if (before.running && !restart) {
            throw const CockpitDaemonException(
              'daemonRunning',
              'Stop the daemon or pass --restart before replacing its authorization policy.',
            );
          }
          if (before.running) {
            await lifecycle.stop(mode: CockpitDaemonShutdownMode.drain);
          }
          await (await runtime.authorizationPolicyStore()).replace(policy);
          if (restart) await lifecycle.start();
          await runtime.success(<String, Object?>{
            'policy': policy.toJson(),
            'daemon': (await lifecycle.status()).toJson(),
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'policy';

  @override
  String get description => 'Manage Supervisor authorization policy.';
}
