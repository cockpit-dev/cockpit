import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../../supervisor/cockpit_supervisor_api_client.dart';
import '../cockpit_cli_output.dart';
import '../cockpit_cli_timeout.dart';
import '../cockpit_flutter_launch_configuration_cli.dart';
import '../cockpit_cli_runtime.dart';
import 'operation_execution.dart';

final class CockpitServerCommand extends Command<int> {
  CockpitServerCommand(this.runtime) {
    cockpitAddCliOutputOptions(argParser);
    cockpitAddCliTimeoutOption(argParser);
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'server';

  @override
  String get description => 'Read Supervisor server discovery metadata.';

  @override
  Future<int> run() async {
    runtime.configureOutput(
      command: name,
      selection: CockpitCliOutputSelection.fromArguments(argResults!),
    );
    runtime.configureTimeout(
      cockpitReadCliTimeout(argResults!),
      explicit: argResults!.wasParsed('timeout'),
    );
    return runtime.runTimed(() async {
      await runtime.success((await (await runtime.client()).server()).toJson());
      return cockpitSuccessExitCode;
    });
  }
}

final class CockpitRootCommand extends Command<int> {
  CockpitRootCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List registered roots.',
        action: (_) async {
          await runtime.success(
            (await (await runtime.client()).roots())
                .map((root) => root.toJson())
                .toList(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'add',
        description: 'Register a root.',
        configure: (parser) => parser
          ..addOption('path', mandatory: true)
          ..addOption('label'),
        action: (arguments) async {
          final path = p.normalize(p.absolute(arguments.option('path')!));
          final root = await (await runtime.client()).registerRoot(
            CockpitRootRegistration(
              path: await Directory(path).resolveSymbolicLinks(),
              label: arguments.option('label'),
            ),
          );
          await runtime.success(root.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'remove',
        description: 'Unregister a root.',
        defaultTimeout: const Duration(minutes: 2),
        maximumTimeout: const Duration(minutes: 10),
        configure: (parser) => parser
          ..addOption('root-id', mandatory: true)
          ..addFlag('force', negatable: false),
        action: (arguments) async {
          final result = await (await runtime.client()).removeRoot(
            arguments.option('root-id')!,
            CockpitRootRemoval(
              force: arguments.flag('force'),
              drainTimeoutMs: runtime.operationBudget().inMilliseconds,
            ),
          );
          await runtime.success(result.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'root';

  @override
  String get description => 'Manage registered project roots.';
}

final class CockpitWorkspaceCommand extends Command<int> {
  CockpitWorkspaceCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List registered workspaces.',
        action: (_) async {
          await runtime.success(
            (await (await runtime.client()).workspaces())
                .map((workspace) => workspace.toJson())
                .toList(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'documents',
        description: 'List indexed documents for a workspace.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption(
            'kind',
            allowed: const <String>['source', 'case', 'suite', 'project'],
          )
          ..addOption(
            'relative-path',
            help: 'Return only the exact workspace-relative path.',
          ),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final requestedKind = switch (arguments.option('kind')) {
            'source' => CockpitIndexedDocumentKind.source,
            'case' => CockpitIndexedDocumentKind.testCase,
            'suite' => CockpitIndexedDocumentKind.suite,
            'project' => CockpitIndexedDocumentKind.project,
            _ => null,
          };
          final requestedPath = arguments.option('relative-path');
          final client = await runtime.client();
          final documents = await client.documents(
            workspaceId,
            kind: requestedKind,
            relativePath: requestedPath,
          );
          String? workspaceRoot;
          if (documents.isEmpty && requestedPath != null) {
            for (final workspace in await client.workspaces()) {
              if (workspace.workspaceId == workspaceId) {
                workspaceRoot = workspace.canonicalPath;
                break;
              }
            }
          }
          await runtime.success(<String, Object?>{
            'items': documents
                .map((document) => document.toJson())
                .toList(growable: false),
            if (documents.isEmpty &&
                requestedPath != null) ...<String, Object?>{
              'requestedRelativePath': requestedPath,
              'workspaceRoot': ?workspaceRoot,
              'hint': 'No exact document match under the registered workspace.',
            },
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'register',
        description: 'Register a workspace checkout.',
        configure: (parser) => parser
          ..addOption('root-id', mandatory: true)
          ..addOption('path'),
        action: (arguments) async {
          final requested =
              arguments.option('path') ?? runtime.workingDirectory;
          final canonical = await Directory(
            p.normalize(p.absolute(requested)),
          ).resolveSymbolicLinks();
          final workspace = await (await runtime.client()).registerWorkspace(
            CockpitWorkspaceRegistration(
              rootId: arguments.option('root-id')!,
              path: canonical,
            ),
          );
          await runtime.success(workspace.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'rebind',
        description: 'Rebind a workspace to a checkout.',
        configure: (parser) => parser
          ..addOption('workspace-id', mandatory: true)
          ..addOption('path', mandatory: true)
          ..addOption('expected-checkout-id', mandatory: true),
        action: (arguments) async {
          final path = await Directory(
            p.normalize(p.absolute(arguments.option('path')!)),
          ).resolveSymbolicLinks();
          final workspace = await (await runtime.client()).rebindWorkspace(
            arguments.option('workspace-id')!,
            CockpitWorkspaceRebind(
              path: path,
              expectedCheckoutId: arguments.option('expected-checkout-id')!,
            ),
          );
          await runtime.success(workspace.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'unregister',
        description: 'Unregister a workspace.',
        defaultTimeout: const Duration(minutes: 2),
        maximumTimeout: const Duration(minutes: 10),
        configure: (parser) => parser
          ..addOption('workspace-id', mandatory: true)
          ..addFlag('force', negatable: false),
        action: (arguments) async {
          final result = await (await runtime.client()).removeWorkspace(
            arguments.option('workspace-id')!,
            CockpitWorkspaceRemoval(
              force: arguments.flag('force'),
              drainTimeoutMs: runtime.operationBudget().inMilliseconds,
            ),
          );
          await runtime.success(result.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'workspace';

  @override
  String get description => 'Manage registered workspace checkouts.';
}

final class CockpitOpCommand extends Command<int> {
  CockpitOpCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List advertised operations.',
        configure: (parser) => parser
          ..addOption(
            'scope',
            allowed: const <String>['supervisor', 'workspace'],
            defaultsTo: 'workspace',
            help: 'Read workspace operations or Supervisor operations.',
          )
          ..addOption(
            'workspace-id',
            help: 'Select a registered workspace; current checkout by default.',
          )
          ..addOption('kind', help: 'Return one exact operation descriptor.'),
        action: (arguments) async {
          final workspaceId = arguments.option('scope') == 'workspace'
              ? await runtime.workspaceId(arguments.option('workspace-id'))
              : null;
          var operations = await (await runtime.client()).operations(
            workspaceId: workspaceId,
          );
          final kind = arguments.option('kind');
          if (kind != null) {
            operations = operations
                .where((operation) => operation.kind == kind)
                .toList(growable: false);
            if (operations.isEmpty) {
              throw CockpitSupervisorClientException(
                code: CockpitErrorCode.unsupportedOperation,
                message: 'Operation $kind is not advertised.',
              );
            }
          }
          await runtime.success(
            operations.map((operation) => operation.toJson()).toList(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'run',
        description: 'Execute one advertised operation.',
        invocationSuffix: 'KIND [arguments]',
        example:
            'cockpit op run viewport.set --input '
            '\'{width:800 height:600}\'',
        configure: cockpitConfigureOperationExecution,
        defaultTimeout: const Duration(minutes: 2),
        timeoutDefaultDescription:
            'Defaults to the advertised budget after discovery and cannot '
            'exceed its advertised maximum.',
        actionManagesTimeout: true,
        action: (arguments) {
          if (arguments.rest.length != 1) {
            throw const FormatException(
              'op run requires exactly one operation kind.',
            );
          }
          return cockpitExecuteOperation(
            runtime,
            arguments,
            kind: arguments.rest.single,
          );
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'op';

  @override
  String get description => 'Inspect and execute advertised operations.';
}

final class CockpitTargetCommand extends Command<int> {
  CockpitTargetCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'discover',
        description: 'Discover locally available launch targets.',
        defaultTimeout: const Duration(minutes: 2),
        maximumTimeout: const Duration(minutes: 10),
        action: (arguments) async {
          final timeoutMs = runtime.operationBudget().inMilliseconds;
          final result = await (await runtime.client()).executeOperation(
            CockpitOperationInvocation(
              kind: 'target.discover',
              input: <String, Object?>{'timeoutMs': timeoutMs},
              deadline: runtime.commandDeadline,
            ),
          );
          await runtime.success(result.toJson());
          return cockpitExitCodeForOperation(result);
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List registered workspace automation targets.',
        configure: (parser) => parser.addOption('workspace-id'),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          await runtime.success(<String, Object?>{
            'items': (await (await runtime.client()).targets(
              workspaceId,
            )).map((target) => target.toJson()).toList(),
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'get',
        description: 'Read one registered workspace automation target.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('target-id', mandatory: true),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          await runtime.success(
            (await (await runtime.client()).target(
              workspaceId,
              arguments.option('target-id')!,
            )).toJson(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'register',
        description: 'Register a workspace-owned automation target.',
        defaultTimeout: const Duration(minutes: 5),
        maximumTimeout: const Duration(minutes: 15),
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('platform', mandatory: true)
          ..addOption('device-id', mandatory: true)
          ..addOption(
            'target-kind',
            allowed: CockpitTargetKind.values
                .map((kind) => kind.name)
                .toList(growable: false),
            defaultsTo: CockpitTargetKind.nativeApp.name,
          )
          ..addOption(
            'environment',
            allowed: const <String>[
              'development',
              'test',
              'staging',
              'production',
              'unknown',
            ],
            defaultsTo: 'unknown',
          )
          ..addOption(
            'mode',
            allowed: const <String>['development', 'automation'],
            defaultsTo: 'automation',
          )
          ..addOption('entrypoint-document-id')
          ..addOption('flavor')
          ..addOption(
            'app-id',
            help: 'Installed application or platform bundle identifier.',
          )
          ..addOption(
            'wda-url',
            help: 'WebDriverAgent endpoint assigned to this iOS target.',
          )
          ..addOption('idempotency-key', mandatory: true),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final result = await (await runtime.client()).executeOperation(
            CockpitOperationInvocation(
              kind: 'target.register',
              workspaceId: workspaceId,
              idempotencyKey: CockpitIdempotencyKey(
                arguments.option('idempotency-key')!,
              ),
              input: <String, Object?>{
                'platform': arguments.option('platform'),
                'deviceId': arguments.option('device-id'),
                'targetKind': arguments.option('target-kind'),
                'environment': arguments.option('environment'),
                'mode': arguments.option('mode'),
                if (arguments.option('entrypoint-document-id') != null)
                  'entrypointDocumentId': arguments.option(
                    'entrypoint-document-id',
                  ),
                if (arguments.option('flavor') != null)
                  'flavor': arguments.option('flavor'),
                if (arguments.option('app-id') != null)
                  'appId': arguments.option('app-id'),
                if (arguments.option('wda-url') != null)
                  'wdaUrl': arguments.option('wda-url'),
              },
              deadline: runtime.commandDeadline,
            ),
          );
          await runtime.success(result.toJson());
          return cockpitExitCodeForOperation(result);
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'launch',
        description: 'Launch or activate a registered automation target.',
        defaultTimeout: const Duration(minutes: 20),
        maximumTimeout: const Duration(minutes: 31),
        configure: (parser) {
          parser
            ..addOption('workspace-id')
            ..addOption('target-id', mandatory: true)
            ..addOption(
              'mode',
              allowed: const <String>['development', 'automation'],
            )
            ..addOption('idempotency-key', mandatory: true);
          cockpitAddFlutterLaunchConfigurationOptions(parser);
        },
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final timeoutMs = runtime
              .operationBudget(maximum: const Duration(minutes: 30))
              .inMilliseconds;
          final launchConfiguration = cockpitReadFlutterLaunchConfiguration(
            arguments,
          );
          final result = await (await runtime.client()).executeOperation(
            CockpitOperationInvocation(
              kind: 'target.launch',
              workspaceId: workspaceId,
              idempotencyKey: CockpitIdempotencyKey(
                arguments.option('idempotency-key')!,
              ),
              input: <String, Object?>{
                'targetId': arguments.option('target-id'),
                if (arguments.option('mode') != null)
                  'mode': arguments.option('mode'),
                'launchTimeoutMs': timeoutMs,
                'launchConfiguration': ?launchConfiguration,
              },
              deadline: runtime.commandDeadline,
            ),
          );
          await runtime.success(result.toJson());
          return cockpitExitCodeForOperation(result);
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'inspect',
        description: 'Inspect the live state of a registered target.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('target-id', mandatory: true)
          ..addOption(
            'profile',
            allowed: const <String>[
              'minimal',
              'standard',
              'inspect',
              'evidence',
            ],
          ),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final result = await (await runtime.client()).executeOperation(
            CockpitOperationInvocation(
              kind: 'target.inspect',
              workspaceId: workspaceId,
              input: <String, Object?>{
                'targetId': arguments.option('target-id'),
                if (arguments.option('profile') != null)
                  'profile': arguments.option('profile'),
              },
              deadline: runtime.commandDeadline,
            ),
          );
          await runtime.success(result.toJson());
          return cockpitExitCodeForOperation(result);
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'target';

  @override
  String get description => 'Discover and manage automation targets.';
}
