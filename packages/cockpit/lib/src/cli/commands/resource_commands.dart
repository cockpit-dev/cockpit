import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../../supervisor/cockpit_supervisor_api_client.dart';
import '../cockpit_cli_output.dart';
import '../cockpit_cli_runtime.dart';

final class CockpitServerCommand extends Command<int> {
  CockpitServerCommand(this.runtime) {
    cockpitAddCliOutputOptions(argParser);
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
    await runtime.success((await (await runtime.client()).server()).toJson());
    return cockpitSuccessExitCode;
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
        configure: (parser) => parser
          ..addOption('root-id', mandatory: true)
          ..addFlag('force', negatable: false)
          ..addOption('drain-timeout-ms', defaultsTo: '30000'),
        action: (arguments) async {
          final timeout = _integer(arguments, 'drain-timeout-ms');
          final result = await (await runtime.client()).removeRoot(
            arguments.option('root-id')!,
            CockpitRootRemoval(
              force: arguments.flag('force'),
              drainTimeoutMs: timeout,
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
        configure: (parser) => parser
          ..addOption('workspace-id', mandatory: true)
          ..addFlag('force', negatable: false)
          ..addOption('drain-timeout-ms', defaultsTo: '30000'),
        action: (arguments) async {
          final result = await (await runtime.client()).removeWorkspace(
            arguments.option('workspace-id')!,
            CockpitWorkspaceRemoval(
              force: arguments.flag('force'),
              drainTimeoutMs: _integer(arguments, 'drain-timeout-ms'),
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

final class CockpitOperationCommand extends Command<int> {
  CockpitOperationCommand(this.runtime) {
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
          )
          ..addOption('workspace-id'),
        action: (arguments) async {
          final workspaceId = arguments.option('scope') == 'workspace'
              ? await runtime.workspaceId(arguments.option('workspace-id'))
              : null;
          final operations = await (await runtime.client()).operations(
            workspaceId: workspaceId,
          );
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
        description: 'Execute an advertised typed operation.',
        configure: (parser) => parser
          ..addOption('kind', mandatory: true)
          ..addOption('workspace-id')
          ..addOption('root-id')
          ..addOption('input-json')
          ..addOption('input-file')
          ..addOption('idempotency-key')
          ..addOption('deadline'),
        action: (arguments) async {
          final client = await runtime.client();
          final kind = arguments.option('kind')!;
          final global = await client.operations();
          final globalMatch = global
              .where((item) => item.kind == kind)
              .firstOrNull;
          final CockpitOperationDescriptor descriptor;
          String? workspaceId;
          if (globalMatch != null) {
            descriptor = globalMatch;
          } else {
            workspaceId = await runtime.workspaceId(
              arguments.option('workspace-id'),
            );
            final matches = (await client.operations(
              workspaceId: workspaceId,
            )).where((item) => item.kind == kind);
            if (matches.length != 1) {
              throw CockpitSupervisorClientException(
                code: CockpitErrorCode.unsupportedOperation,
                message: 'Operation $kind is not advertised.',
              );
            }
            descriptor = matches.single;
          }
          if (descriptor.scope == CockpitOperationScope.root &&
              arguments.option('root-id') == null) {
            throw const FormatException(
              '--root-id is required for this operation.',
            );
          }
          final result = await client.executeOperation(
            CockpitOperationInvocation(
              kind: kind,
              input: runtime.jsonObject(
                arguments.option('input-json'),
                arguments.option('input-file'),
              ),
              rootId: descriptor.scope == CockpitOperationScope.root
                  ? arguments.option('root-id')
                  : null,
              workspaceId: descriptor.scope == CockpitOperationScope.workspace
                  ? workspaceId
                  : null,
              idempotencyKey: arguments.option('idempotency-key') == null
                  ? null
                  : CockpitIdempotencyKey(arguments.option('idempotency-key')!),
              deadline: arguments.option('deadline') == null
                  ? null
                  : DateTime.parse(arguments.option('deadline')!).toUtc(),
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
  String get name => 'operation';

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
        configure: (parser) => parser.addOption('timeout-ms'),
        action: (arguments) async {
          final timeoutMs = _optionalInteger(arguments, 'timeout-ms');
          final result = await (await runtime.client()).executeOperation(
            CockpitOperationInvocation(
              kind: 'target.discover',
              input: <String, Object?>{'timeoutMs': ?timeoutMs},
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
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('target-id', mandatory: true)
          ..addOption(
            'mode',
            allowed: const <String>['development', 'automation'],
          )
          ..addOption('launch-timeout-ms', defaultsTo: '600000')
          ..addOption('idempotency-key', mandatory: true),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final timeoutMs = _integer(arguments, 'launch-timeout-ms');
          if (timeoutMs < 1000 || timeoutMs > 1800000) {
            throw const FormatException(
              '--launch-timeout-ms must be between 1000 and 1800000.',
            );
          }
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
              },
              deadline: DateTime.now().toUtc().add(
                Duration(milliseconds: timeoutMs) + const Duration(seconds: 30),
              ),
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

int _integer(ArgResults arguments, String name) {
  final value = int.tryParse(arguments.option(name)!);
  if (value == null) throw FormatException('--$name is invalid.');
  return value;
}

int? _optionalInteger(ArgResults arguments, String name) {
  final source = arguments.option(name);
  if (source == null) return null;
  final value = int.tryParse(source);
  if (value == null) throw FormatException('--$name is invalid.');
  return value;
}
