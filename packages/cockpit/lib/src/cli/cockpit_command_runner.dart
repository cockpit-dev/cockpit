import 'dart:io';

import 'package:args/command_runner.dart';

import '../supervisor/cockpit_daemon_client.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_cli_output.dart';
import 'cockpit_cli_runtime.dart';
import 'commands/daemon_commands.dart';
import 'commands/resource_commands.dart';
import 'commands/run_commands.dart';
import 'commands/serve_mcp_command.dart';

export 'cockpit_cli_runtime.dart'
    show
        cockpitDataExitCode,
        cockpitNoInputExitCode,
        cockpitPermissionExitCode,
        cockpitSuccessExitCode,
        cockpitTemporaryExitCode,
        cockpitUnavailableExitCode,
        cockpitUsageExitCode;

final class CockpitCommandRunner {
  CockpitCommandRunner({CockpitCliRuntime? runtime})
    : runtime = runtime ?? CockpitCliRuntime(),
      _runner = CommandRunner<int>(
        'cockpit',
        'Authenticated Cockpit Supervisor 2.0 client.',
      ) {
    _runner
      ..addCommand(CockpitDaemonCommand(this.runtime))
      ..addCommand(CockpitServerCommand(this.runtime))
      ..addCommand(CockpitRootCommand(this.runtime))
      ..addCommand(CockpitWorkspaceCommand(this.runtime))
      ..addCommand(CockpitOperationCommand(this.runtime))
      ..addCommand(CockpitTargetCommand(this.runtime))
      ..addCommand(CockpitCaseCommand(this.runtime))
      ..addCommand(CockpitSuiteCommand(this.runtime))
      ..addCommand(CockpitRunCommand(this.runtime))
      ..addCommand(CockpitArtifactCommand(this.runtime));
    _runner.addCommand(CockpitServeMcpCommand());
  }

  final CockpitCliRuntime runtime;
  final CommandRunner<int> _runner;

  String get usage => _runner.usage;

  Map<String, Command<int>> get commands => _runner.commands;

  Future<int> run(List<String> arguments) async {
    runtime.configureOutput(
      command: _commandPath(arguments),
      selection: CockpitCliOutputSelection.fromRawArguments(arguments),
    );
    try {
      return await _runner.run(arguments) ?? cockpitSuccessExitCode;
    } on UsageException catch (error) {
      runtime.error(code: 'usage', message: error.message);
      return cockpitUsageExitCode;
    } on CockpitSupervisorClientException catch (error) {
      final api = error.apiError;
      runtime.error(
        code: error.code,
        message: error.message,
        retryable: api?.retryable ?? false,
        category: api?.category.name,
        responsibleLayer: api?.responsibleLayer.name,
        details: api?.redactedDetails ?? const <String, Object?>{},
      );
      return api == null
          ? _clientExitCode(error.code)
          : cockpitExitCodeFor(api);
    } on CockpitDaemonException catch (error) {
      runtime.error(code: error.code, message: error.message);
      return cockpitUnavailableExitCode;
    } on FileSystemException catch (error) {
      runtime.error(
        code: 'fileSystemError',
        message: error.message,
        details: <String, Object?>{'path': ?error.path},
      );
      return cockpitNoInputExitCode;
    } on FormatException catch (error) {
      runtime.error(code: 'invalidInput', message: error.message);
      return cockpitDataExitCode;
    } on ArgumentError catch (error) {
      runtime.error(
        code: 'invalidArgument',
        message: error.message?.toString() ?? error.toString(),
      );
      return cockpitDataExitCode;
    } on Object {
      runtime.error(
        code: 'internalError',
        message: 'Cockpit client failed unexpectedly.',
      );
      return cockpitUnavailableExitCode;
    }
  }
}

String _commandPath(List<String> arguments) {
  final commands = arguments
      .takeWhile((argument) => !argument.startsWith('-'))
      .take(2)
      .toList(growable: false);
  return commands.isEmpty ? 'cockpit' : commands.join('.');
}

int _clientExitCode(String code) => switch (code) {
  'workspaceNotFound' || 'caseNotFound' => cockpitNoInputExitCode,
  'transportFailed' || 'serverIdentityMismatch' => cockpitUnavailableExitCode,
  _ => cockpitDataExitCode,
};
