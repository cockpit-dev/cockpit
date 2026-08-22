import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/foundation/cockpit_internal_process.dart';
import 'package:cockpit/src/infrastructure/cockpit_installed_runtime_cleanup.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_runtime.dart';
import 'package:cockpit/src/cli/cockpit_update_installation.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime.dart';

Future<void> main(List<String> args) async {
  final command = args.firstOrNull;
  if (command != cockpitInternalRuntimeCleanupCommand) {
    try {
      await cockpitPrepareInstalledRuntime(version: cockpitVersion);
    } on Object catch (error) {
      stderr.writeln('Cockpit installation repair failed: $error');
      exit(1);
    }
  }
  final internalProcess =
      command == cockpitInternalDaemonCommand ||
      command == cockpitInternalWorkerCommand ||
      command == cockpitInternalUpdateCleanupCommand ||
      command == cockpitInternalRuntimeCleanupCommand;
  final code = switch (command) {
    cockpitInternalDaemonCommand => await runCockpitDaemon(
      args.skip(1).toList(growable: false),
      selfContained: true,
    ),
    cockpitInternalWorkerCommand => await runCockpitWorker(
      args.skip(1).toList(growable: false),
    ),
    cockpitInternalUpdateCleanupCommand => await runCockpitUpdateCleanup(
      args.skip(1).toList(growable: false),
    ),
    cockpitInternalRuntimeCleanupCommand =>
      await runCockpitInstalledRuntimeCleanup(
        args.skip(1).toList(growable: false),
      ),
    _ => await CockpitCommandRunner().run(args),
  };
  if (internalProcess || code != cockpitSuccessExitCode) {
    exit(code);
  }
}
