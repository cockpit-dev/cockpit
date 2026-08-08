import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/foundation/cockpit_internal_process.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_runtime.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime.dart';

Future<void> main(List<String> args) async {
  final command = args.firstOrNull;
  final internalProcess =
      command == cockpitInternalDaemonCommand ||
      command == cockpitInternalWorkerCommand;
  final code = switch (command) {
    cockpitInternalDaemonCommand => await runCockpitDaemon(
      args.skip(1).toList(growable: false),
      selfContained: true,
    ),
    cockpitInternalWorkerCommand => await runCockpitWorker(
      args.skip(1).toList(growable: false),
    ),
    _ => await CockpitCommandRunner().run(args),
  };
  if (internalProcess || code != cockpitSuccessExitCode) {
    exit(code);
  }
}
