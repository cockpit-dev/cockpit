import 'package:args/args.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../cockpit_cli_runtime.dart';
import '../cockpit_cli_timeout.dart';
import '../cockpit_dev_runtime.dart';
import 'dev_command_options.dart';

CockpitLeafCommand cockpitDevTapCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'tap',
  description: 'Tap one exact mounted Flutter target.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev tap \'Dialog >> FilledButton["Continue"]\'',
  configure: _targetOptions,
  action: (arguments) => _targetAction(
    runtime,
    dev,
    arguments,
    action: 'tap',
    type: CockpitCommandType.tap,
  ),
);

CockpitLeafCommand cockpitDevTypeCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'type',
  description: 'Replace text in the focused or selected Flutter input.',
  invocationSuffix: 'TEXT [arguments]',
  example: 'cockpit dev type "hello" --into "Message"',
  configure: (parser) {
    parser.addOption('into', help: 'Target selector.');
    _targetOptions(parser);
  },
  action: (arguments) async {
    if (arguments.rest.length != 1) {
      throw const FormatException('dev type requires exactly one text value.');
    }
    final target = arguments.option('into');
    return dev.runCommand(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      action: 'type',
      command: dev.command(
        type: CockpitCommandType.enterText,
        timeout: runtime.operationTimeout,
        locator: cockpitReadDevLocator(
          arguments,
          selector: target,
          targetRequired: false,
        ),
        parameters: <String, Object?>{'text': arguments.rest.single},
      ),
    );
  },
);

CockpitLeafCommand cockpitDevPressCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'press',
  description: 'Send one named Flutter logical key to the focused control.',
  invocationSuffix: 'KEY [arguments]',
  example: 'cockpit dev press enter',
  configure: cockpitAddDevSessionOption,
  action: (arguments) async {
    if (arguments.rest.length != 1) {
      throw const FormatException('dev press requires exactly one key name.');
    }
    final key = arguments.rest.single.trim();
    final normalizedKey = key.toLowerCase();
    final isEscape = normalizedKey == 'escape' || normalizedKey == 'esc';
    return dev.runCommand(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      action: 'press',
      command: dev.command(
        type: isEscape
            ? CockpitCommandType.back
            : CockpitCommandType.sendKeyEvent,
        timeout: runtime.operationTimeout,
        parameters: isEscape
            ? const <String, Object?>{}
            : <String, Object?>{'logicalKey': key},
      ),
    );
  },
);

CockpitLeafCommand cockpitDevBackCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'back',
  description: 'Go back through the current Flutter navigator.',
  example: 'cockpit dev back',
  configure: cockpitAddDevSessionOption,
  action: (arguments) async => dev.runCommand(
    await runtime.resolveDevelopmentSession(arguments.option('session')),
    action: 'back',
    command: dev.command(
      type: CockpitCommandType.back,
      timeout: runtime.operationTimeout,
    ),
  ),
);

CockpitLeafCommand cockpitDevDismissCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'dismiss',
  description: 'Dismiss the current Flutter dialog, sheet, or barrier.',
  example: 'cockpit dev dismiss',
  configure: cockpitAddDevSessionOption,
  action: (arguments) async => dev.runCommand(
    await runtime.resolveDevelopmentSession(arguments.option('session')),
    action: 'dismiss',
    command: dev.command(
      type: CockpitCommandType.dismiss,
      timeout: runtime.operationTimeout,
    ),
  ),
);

CockpitLeafCommand cockpitDevScrollCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'scroll',
  description: 'Find, fully reveal, and align one mounted Flutter target.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev scroll "Operations" --align center --offset 12',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption(
        'direction',
        allowed: const <String>['up', 'down'],
        defaultsTo: 'down',
      )
      ..addOption(
        'align',
        allowed: const <String>['nearest', 'start', 'center', 'end'],
        defaultsTo: 'nearest',
        help: 'Place the target within its nearest scrollable viewport.',
      )
      ..addOption(
        'offset',
        defaultsTo: '0',
        help: 'Move the aligned target toward the viewport end in pixels.',
      )
      ..addOption('max-scrolls', defaultsTo: '12');
  },
  defaultTimeout: const Duration(minutes: 3),
  maximumTimeout: const Duration(minutes: 15),
  action: (arguments) async {
    final maxScrolls = _integer(arguments, 'max-scrolls');
    if (maxScrolls < 1 || maxScrolls > 100) {
      throw const FormatException('--max-scrolls must be between 1 and 100.');
    }
    final offset = _finiteDouble(arguments, 'offset');
    if (offset < -10000 || offset > 10000) {
      throw const FormatException('--offset must be between -10000 and 10000.');
    }
    return _targetAction(
      runtime,
      dev,
      arguments,
      action: 'scroll',
      type: CockpitCommandType.scrollUntilVisible,
      parameters: <String, Object?>{
        'maxScrolls': maxScrolls,
        'reverse': arguments.option('direction') == 'up',
        'revealAlignment': arguments.option('align'),
        'revealOffsetPx': offset,
      },
    );
  },
);

CockpitLeafCommand cockpitDevWaitCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'wait',
  description: 'Wait for Flutter UI idle, optionally including network idle.',
  example: 'cockpit dev wait --network',
  configure: (parser) {
    cockpitAddDevSessionOption(parser);
    parser
      ..addFlag('network', negatable: false)
      ..addOption('quiet', defaultsTo: '500ms');
  },
  defaultTimeout: const Duration(seconds: 30),
  maximumTimeout: const Duration(minutes: 5),
  action: (arguments) async {
    final quiet = cockpitParseDuration(arguments.option('quiet')!);
    if (quiet < const Duration(milliseconds: 50) ||
        quiet > const Duration(minutes: 1)) {
      throw const FormatException('--quiet must be between 50ms and 1m.');
    }
    final operationTimeout = runtime.operationTimeout;
    if (operationTimeout < quiet) {
      throw const FormatException('--timeout must be at least --quiet.');
    }
    return dev.waitIdle(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      includeNetwork: arguments.flag('network'),
      quietMilliseconds: quiet.inMilliseconds,
      timeoutMilliseconds: operationTimeout.inMilliseconds,
    );
  },
);

Future<int> _targetAction(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
  ArgResults arguments, {
  required String action,
  required CockpitCommandType type,
  Map<String, Object?> parameters = const <String, Object?>{},
}) async {
  final text = arguments.rest.length == 1 ? arguments.rest.single : null;
  if (arguments.rest.length > 1) {
    throw FormatException('dev $action accepts exactly one target.');
  }
  return dev.runCommand(
    await runtime.resolveDevelopmentSession(arguments.option('session')),
    action: action,
    command: dev.command(
      type: type,
      timeout: runtime.operationTimeout,
      locator: cockpitReadDevLocator(arguments, selector: text),
      parameters: parameters,
    ),
  );
}

CockpitLocator? cockpitReadDevLocator(
  ArgResults arguments, {
  required String? selector,
  bool targetRequired = true,
}) {
  final normalized = selector?.trim();
  if (normalized == null || normalized.isEmpty) {
    if (targetRequired) throw const FormatException('Target is required.');
    return null;
  }
  return CockpitSelector.parse(normalized);
}

void _targetOptions(ArgParser parser) {
  cockpitAddDevSessionOption(parser);
}

int _integer(ArgResults arguments, String name) {
  final parsed = int.tryParse(arguments.option(name)!);
  if (parsed == null) throw FormatException('--$name is invalid.');
  return parsed;
}

double _finiteDouble(ArgResults arguments, String name) {
  final parsed = double.tryParse(arguments.option(name)!);
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('--$name is invalid.');
  }
  return parsed;
}
