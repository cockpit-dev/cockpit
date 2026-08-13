import 'package:args/command_runner.dart';

import '../cockpit_cli_runtime.dart';
import '../cockpit_cli_session_handles.dart';
import '../cockpit_dev_runtime.dart';

final class CockpitSessionCommand extends Command<int> {
  CockpitSessionCommand(CockpitCliRuntime runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List saved local session handles without reconnecting.',
        action: (_) async {
          final handles = await runtime.sessionHandles();
          final items = handles.map(_sessionListItem).toList(growable: false);
          await runtime.success(<String, Object?>{
            'totalCount': items.length,
            'items': items,
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'show',
        description: 'Show the current identity and live state of one session.',
        invocationSuffix: '[HANDLE] [arguments]',
        example: 'cockpit session show 1',
        action: (arguments) async {
          if (arguments.rest.length > 1) {
            throw const FormatException(
              'session show accepts at most one short session.',
            );
          }
          var handle = await runtime.sessionHandle(
            arguments.rest.isEmpty ? null : arguments.rest.single,
          );
          Object? liveState;
          var ready = false;
          var errors = const <Object?>[];
          if (handle.isDevelopment && handle.lifecycle != 'stopped') {
            final resolution = await CockpitDevRuntime(
              runtime,
            ).reconcile(handle, allowRelaunch: false);
            handle = resolution.session;
            liveState = resolution.state;
            ready = resolution.ready;
            errors = resolution.errors;
          }
          await runtime.success(<String, Object?>{
            ...handle.toJson(),
            'ready': ready,
            'live': ?liveState,
            if (errors.isNotEmpty) 'errors': errors,
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'bind',
        description: 'Bind a canonical session ID to a short local handle.',
        configure: (parser) => parser
          ..addOption('session-id', mandatory: true)
          ..addOption('workspace-id'),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final handle = await runtime.bindSessionHandle(
            workspaceId: workspaceId,
            sessionId: arguments.option('session-id')!,
          );
          await runtime.success(handle.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'remove',
        description: 'Remove a local CLI session handle.',
        configure: (parser) =>
            parser.addOption('session', abbr: 's', mandatory: true),
        action: (arguments) async {
          final reference = arguments.option('session')!;
          final removed = await runtime.removeSessionHandle(reference);
          await runtime.success(<String, Object?>{
            'session': reference,
            'removed': removed,
          });
          return removed ? cockpitSuccessExitCode : cockpitNoInputExitCode;
        },
      ),
    );
  }

  @override
  String get name => 'session';

  @override
  String get description => 'Manage short local references to app sessions.';
}

Map<String, Object?> _sessionListItem(CockpitCliSessionHandle handle) {
  final stored = handle.toJson()..remove('lifecycle');
  return <String, Object?>{...stored, 'lastState': handle.lifecycle};
}
