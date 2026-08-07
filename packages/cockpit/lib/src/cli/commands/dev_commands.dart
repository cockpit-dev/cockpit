import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../cockpit_cli_runtime.dart';
import '../cockpit_cli_output.dart';
import '../cockpit_dev_network.dart';
import '../cockpit_dev_runtime.dart';
import '../cockpit_dev_start.dart';
import '../cockpit_flutter_launch_configuration_cli.dart';
import 'dev_interaction_commands.dart';
import 'dev_screenshot_command.dart';

final class CockpitDevCommand extends Command<int> {
  CockpitDevCommand(this.runtime) {
    final dev = CockpitDevRuntime(runtime);
    addSubcommand(_start(runtime));
    addSubcommand(_use(runtime, dev));
    addSubcommand(_read(runtime, dev, name: 'status'));
    addSubcommand(_inspect(runtime, dev));
    addSubcommand(cockpitDevTapCommand(runtime, dev));
    addSubcommand(cockpitDevTypeCommand(runtime, dev));
    addSubcommand(cockpitDevPressCommand(runtime, dev));
    addSubcommand(cockpitDevBackCommand(runtime, dev));
    addSubcommand(cockpitDevDismissCommand(runtime, dev));
    addSubcommand(cockpitDevScrollCommand(runtime, dev));
    addSubcommand(cockpitDevWaitCommand(runtime, dev));
    addSubcommand(_viewport(runtime, dev));
    addSubcommand(cockpitDevScreenshotCommand(runtime, dev));
    addSubcommand(_network(runtime, dev));
    for (final action in const <String>['reload', 'restart', 'stop']) {
      addSubcommand(_lifecycle(runtime, dev, action));
    }
    addSubcommand(_read(runtime, dev, name: 'diagnose'));
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'dev';

  @override
  String get description =>
      'Develop and debug the current Flutter checkout with one session handle.';
}

CockpitLeafCommand _start(CockpitCliRuntime runtime) => CockpitLeafCommand(
  runtime: runtime,
  name: 'start',
  description: 'Start or reconnect the current Flutter development app.',
  invocationSuffix: '[ENTRYPOINT] [arguments]',
  example: 'cockpit dev start',
  defaultTimeout: const Duration(minutes: 20),
  maximumTimeout: const Duration(minutes: 31),
  configure: (parser) {
    _sessionOption(parser);
    parser
      ..addOption('platform')
      ..addOption('device')
      ..addOption('flavor');
    cockpitAddFlutterLaunchConfigurationOptions(parser);
  },
  action: (arguments) async {
    if (arguments.rest.length > 1) {
      throw const FormatException(
        'dev start accepts at most one Flutter entrypoint.',
      );
    }
    return CockpitDevStartService(runtime).start(
      CockpitDevStartRequest(
        sessionReference: arguments.option('session'),
        entrypoint: arguments.rest.firstOrNull,
        platform: arguments.option('platform'),
        deviceId: arguments.option('device'),
        flavor: arguments.option('flavor'),
        launchConfiguration: cockpitReadFlutterLaunchConfiguration(arguments),
        launchTimeoutMilliseconds: runtime.operationTimeout.inMilliseconds,
      ),
    );
  },
);

CockpitLeafCommand _use(CockpitCliRuntime runtime, CockpitDevRuntime dev) =>
    CockpitLeafCommand(
      runtime: runtime,
      name: 'use',
      description: 'Select a development session for the current checkout.',
      invocationSuffix: 'HANDLE [arguments]',
      example: 'cockpit dev use 2',
      action: (arguments) async {
        if (arguments.rest.length != 1) {
          throw const FormatException('dev use requires one session handle.');
        }
        final session = await runtime.resolveDevelopmentSession(
          arguments.rest.single,
        );
        return dev.writeEnvelope(
          action: 'use',
          session: session,
          ok: true,
          state: <String, Object?>{'lifecycle': session.lifecycle},
          changed: 'selected',
        );
      },
    );

CockpitLeafCommand _read(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev, {
  required String name,
}) => CockpitLeafCommand(
  runtime: runtime,
  name: name,
  description: name == 'status'
      ? 'Read the current Flutter development session state.'
      : 'Collect bounded Flutter UI, log, error, and network diagnostics.',
  example: 'cockpit dev $name',
  configure: _sessionOption,
  action: (arguments) async => dev.status(
    await runtime.resolveDevelopmentSession(arguments.option('session')),
    diagnose: name == 'diagnose',
  ),
);

CockpitLeafCommand _inspect(CockpitCliRuntime runtime, CockpitDevRuntime dev) =>
    CockpitLeafCommand(
      runtime: runtime,
      name: 'inspect',
      description:
          'Inspect the Flutter UI or search its current semantic state.',
      invocationSuffix: '[QUERY] [arguments]',
      example: 'cockpit dev inspect "Save changes"',
      configure: _sessionOption,
      action: (arguments) async {
        if (arguments.rest.length > 1) {
          throw const FormatException('dev inspect accepts at most one query.');
        }
        return dev.inspect(
          await runtime.resolveDevelopmentSession(arguments.option('session')),
          query: arguments.rest.firstOrNull,
        );
      },
    );

CockpitLeafCommand _lifecycle(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
  String action,
) => CockpitLeafCommand(
  runtime: runtime,
  name: action,
  description: switch (action) {
    'reload' => 'Hot reload the current Flutter development app.',
    'restart' => 'Hot restart the current Flutter development app.',
    _ => 'Stop the current Flutter development app.',
  },
  example: 'cockpit dev $action',
  defaultTimeout: action == 'restart'
      ? const Duration(minutes: 5)
      : const Duration(minutes: 2),
  maximumTimeout: const Duration(minutes: 10),
  configure: _sessionOption,
  action: (arguments) async => dev.lifecycle(
    await runtime.resolveDevelopmentSession(arguments.option('session')),
    action,
  ),
);

CockpitLeafCommand _viewport(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'viewport',
  description: 'Resize the Flutter viewport in logical pixels.',
  invocationSuffix: 'WIDTHxHEIGHT [arguments]',
  example: 'cockpit dev viewport 800x600',
  configure: _sessionOption,
  action: (arguments) async {
    if (arguments.rest.length != 1) {
      throw const FormatException('dev viewport requires WIDTHxHEIGHT.');
    }
    final match = RegExp(
      r'^(\d{1,4})x(\d{1,4})$',
      caseSensitive: false,
    ).firstMatch(arguments.rest.single);
    if (match == null) {
      throw const FormatException('Viewport must use WIDTHxHEIGHT syntax.');
    }
    final width = _integer(match.group(1)!);
    final height = _integer(match.group(2)!);
    if (width < 200 || width > 8192 || height < 200 || height > 8192) {
      throw const FormatException(
        'Viewport width and height must be between 200 and 8192.',
      );
    }
    return dev.resizeViewport(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      width: width,
      height: height,
    );
  },
);

CockpitLeafCommand _network(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'network',
  description: 'Read bounded HTTP and WebSocket activity or save HTTP bodies.',
  invocationSuffix: '[REQUEST] [arguments]',
  example: 'cockpit dev network 37 --body response',
  defaultTimeout: const Duration(minutes: 2),
  maximumTimeout: const Duration(minutes: 10),
  configure: (parser) => parser
    ..addOption('session', abbr: 's', help: 'Select another checkout session.')
    ..addOption('before', help: 'Read requests older than this numeric ID.')
    ..addOption('limit', defaultsTo: '12', help: 'Maximum recent rows.')
    ..addFlag('failures', negatable: false, help: 'Show failed requests only.')
    ..addOption('method', help: 'Filter by HTTP method.')
    ..addOption('uri', help: 'Filter by URI substring.')
    ..addOption(
      'body',
      allowed: const <String>['request', 'response', 'both'],
      help: 'Save complete/current HTTP body files.',
    )
    ..addFlag(
      'raw',
      negatable: false,
      help: 'Keep sensitive text and binary bytes in saved body files.',
    ),
  action: (arguments) async {
    if (arguments.rest.length > 1) {
      throw const FormatException(
        'dev network accepts at most one request ID.',
      );
    }
    final requestId = arguments.rest.firstOrNull;
    final body = arguments.option('body');
    final before = arguments.option('before');
    _validateNetworkId(requestId, 'request ID');
    _validateNetworkId(before, '--before');
    final limit = _integer(arguments.option('limit')!);
    if (limit < 1 || limit > 100) {
      throw const FormatException('--limit must be between 1 and 100.');
    }
    if (requestId != null && before != null) {
      throw const FormatException(
        'A request ID cannot be combined with --before.',
      );
    }
    if (body != null && requestId == null) {
      throw const FormatException('--body requires a request ID.');
    }
    if (arguments.flag('raw') && body == null) {
      throw const FormatException('--raw requires --body.');
    }
    final pathOutput = runtime.outputSelection.format == CockpitCliFormat.path;
    if (pathOutput && (body == null || body == 'both')) {
      throw const FormatException(
        '--format path requires one request or response body.',
      );
    }
    return CockpitDevNetworkService(runtime, dev).read(
      sessionReference: arguments.option('session'),
      requestId: requestId,
      before: before,
      limit: limit,
      failuresOnly: arguments.flag('failures'),
      method: arguments.option('method'),
      uriContains: arguments.option('uri'),
      body: body,
      raw: arguments.flag('raw'),
    );
  },
);

void _validateNetworkId(String? value, String name) {
  if (value != null && !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value)) {
    throw FormatException('$name must be a positive numeric request ID.');
  }
}

void _sessionOption(ArgParser parser) => parser.addOption(
  'session',
  abbr: 's',
  help: 'Select another session owned by this checkout.',
);

int _integer(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null) throw FormatException('Invalid integer: $value');
  return parsed;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
