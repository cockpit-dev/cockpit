import 'dart:math' as math;

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
  description: 'Find, reveal, and tap one exact Flutter target.',
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

CockpitLeafCommand cockpitDevHoldCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'hold',
  description: 'Find, reveal, and long-press one exact Flutter target.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev hold ":a" --duration 900ms',
  configure: (parser) {
    _targetOptions(parser);
    parser.addOption(
      'duration',
      defaultsTo: '600ms',
      help: 'How long the pointer remains down.',
    );
  },
  action: (arguments) async {
    final duration = _positiveDuration(arguments, 'duration');
    return _targetAction(
      runtime,
      dev,
      arguments,
      action: 'hold',
      type: CockpitCommandType.longPress,
      parameters: <String, Object?>{'durationMs': duration.inMilliseconds},
    );
  },
);

CockpitLeafCommand cockpitDevDoubleCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'double',
  description: 'Find, reveal, and double-tap one exact Flutter target.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev double ":a"',
  configure: (parser) {
    _targetOptions(parser);
    parser.addOption(
      'interval',
      defaultsTo: '90ms',
      help: 'Delay between the two taps.',
    );
  },
  action: (arguments) => _targetAction(
    runtime,
    dev,
    arguments,
    action: 'double',
    type: CockpitCommandType.doubleTap,
    parameters: <String, Object?>{
      'intervalMs': _positiveDuration(arguments, 'interval').inMilliseconds,
    },
  ),
);

CockpitLeafCommand cockpitDevDragCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'drag',
  description: 'Drag one Flutter target by a real pointer path.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev drag "Canvas" --dx 120 --dy 0',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('dx', help: 'Horizontal movement in logical pixels.')
      ..addOption('dy', help: 'Vertical movement in logical pixels.')
      ..addOption('duration', defaultsTo: '220ms')
      ..addOption('hold', help: 'Optional hold before moving.')
      ..addOption('moves', help: 'Optional number of move events.')
      ..addOption('at', help: 'Optional start point as X,Y.');
  },
  action: (arguments) async {
    final dx = _finiteDouble(arguments, 'dx');
    final dy = _finiteDouble(arguments, 'dy');
    if (dx == 0 && dy == 0) {
      throw const FormatException('dev drag requires non-zero movement.');
    }
    final parameters = <String, Object?>{
      'dx': dx,
      'dy': dy,
      'durationMs': _positiveDuration(arguments, 'duration').inMilliseconds,
      ..._optionalGestureTiming(arguments),
      ..._optionalPoint(arguments),
    };
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'drag',
      type: CockpitCommandType.drag,
      parameters: parameters,
    );
  },
);

CockpitLeafCommand cockpitDevFlingCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'fling',
  description: 'Fling one Flutter target with a velocity profile.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev fling "List" --dx 0 --dy -400 --velocity 1600',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('dx', help: 'Horizontal movement in logical pixels.')
      ..addOption('dy', help: 'Vertical movement in logical pixels.')
      ..addOption('velocity', help: 'Fling velocity in logical pixels/second.')
      ..addOption('duration', help: 'Optional gesture duration.')
      ..addOption('moves', help: 'Optional number of move events.')
      ..addOption('at', help: 'Optional start point as X,Y.');
  },
  action: (arguments) async {
    final dx = _finiteDouble(arguments, 'dx');
    final dy = _finiteDouble(arguments, 'dy');
    if (dx == 0 && dy == 0) {
      throw const FormatException('dev fling requires non-zero movement.');
    }
    final velocity = _finiteDouble(arguments, 'velocity');
    if (velocity <= 0) {
      throw const FormatException('--velocity must be positive.');
    }
    final distance = math.sqrt(dx * dx + dy * dy);
    final duration = arguments.option('duration') == null
        ? Duration(
            milliseconds: (distance / velocity * 1000).round().clamp(16, 1200),
          )
        : _positiveDuration(arguments, 'duration');
    final parameters = <String, Object?>{
      'dx': dx,
      'dy': dy,
      'velocity': velocity,
      'durationMs': duration.inMilliseconds,
      ..._optionalMoveCount(arguments),
      ..._optionalPoint(arguments),
    };
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'fling',
      type: CockpitCommandType.fling,
      parameters: parameters,
    );
  },
);

CockpitLeafCommand cockpitDevSwipeCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'swipe',
  description: 'Swipe one Flutter target in a direction.',
  invocationSuffix: 'SELECTOR DIRECTION [arguments]',
  example: 'cockpit dev swipe "List" up',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('distance', defaultsTo: '0.82')
      ..addOption('duration', defaultsTo: '200ms')
      ..addOption('moves', help: 'Optional number of move events.')
      ..addOption('at', help: 'Optional start point as X,Y.');
  },
  action: (arguments) async {
    if (arguments.rest.length != 2) {
      throw const FormatException('dev swipe requires SELECTOR and DIRECTION.');
    }
    final direction = arguments.rest[1].toLowerCase();
    if (!const <String>{'up', 'down', 'left', 'right'}.contains(direction)) {
      throw const FormatException(
        'DIRECTION must be up, down, left, or right.',
      );
    }
    final distance = _finiteDouble(arguments, 'distance');
    if (distance < 0.15 || distance > 0.95) {
      throw const FormatException('--distance must be between 0.15 and 0.95.');
    }
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'swipe',
      type: CockpitCommandType.swipe,
      selector: arguments.rest.first,
      parameters: <String, Object?>{
        'direction': direction,
        'distanceFactor': distance,
        'durationMs': _positiveDuration(arguments, 'duration').inMilliseconds,
        ..._optionalMoveCount(arguments),
        ..._optionalPoint(arguments),
      },
    );
  },
);

CockpitLeafCommand cockpitDevPinchCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'pinch',
  description: 'Pinch or spread one Flutter target with two pointers.',
  invocationSuffix: 'SELECTOR SCALE [arguments]',
  example: 'cockpit dev pinch "Map" 1.5',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('span', defaultsTo: '56')
      ..addOption('duration', defaultsTo: '220ms')
      ..addOption('moves', help: 'Optional number of move events.')
      ..addOption('at', help: 'Optional focal point as X,Y.');
  },
  action: (arguments) async {
    if (arguments.rest.length != 2) {
      throw const FormatException('dev pinch requires SELECTOR and SCALE.');
    }
    final scale = double.tryParse(arguments.rest[1]);
    if (scale == null || !scale.isFinite || scale <= 0 || scale == 1) {
      throw const FormatException(
        'SCALE must be positive and different from 1.',
      );
    }
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'pinch',
      type: CockpitCommandType.pinchZoom,
      selector: arguments.rest.first,
      parameters: <String, Object?>{
        'scale': scale,
        'startSpan': _positiveDouble(arguments, 'span'),
        'durationMs': _positiveDuration(arguments, 'duration').inMilliseconds,
        ..._optionalMoveCount(arguments),
        ..._optionalPoint(arguments),
      },
    );
  },
);

CockpitLeafCommand cockpitDevRotateCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'rotate',
  description: 'Rotate one Flutter target by radians with two pointers.',
  invocationSuffix: 'SELECTOR RADIANS [arguments]',
  example: 'cockpit dev rotate "Canvas" 1.5708',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('span', defaultsTo: '56')
      ..addOption('duration', defaultsTo: '220ms')
      ..addOption('moves', help: 'Optional number of move events.')
      ..addOption('at', help: 'Optional focal point as X,Y.');
  },
  action: (arguments) async {
    if (arguments.rest.length != 2) {
      throw const FormatException('dev rotate requires SELECTOR and RADIANS.');
    }
    final radians = double.tryParse(arguments.rest[1]);
    if (radians == null || !radians.isFinite || radians == 0) {
      throw const FormatException('RADIANS must be a non-zero finite number.');
    }
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'rotate',
      type: CockpitCommandType.rotate,
      selector: arguments.rest.first,
      parameters: <String, Object?>{
        'rotationRadians': radians,
        'startSpan': _positiveDouble(arguments, 'span'),
        'durationMs': _positiveDuration(arguments, 'duration').inMilliseconds,
        ..._optionalMoveCount(arguments),
        ..._optionalPoint(arguments),
      },
    );
  },
);

CockpitLeafCommand cockpitDevPanCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'pan',
  description: 'Pan one Flutter target with a trackpad-like gesture.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev pan "Canvas" --dx 80 --dy 20',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('dx', help: 'Horizontal movement in logical pixels.')
      ..addOption('dy', help: 'Vertical movement in logical pixels.')
      ..addOption('scale', defaultsTo: '1')
      ..addOption('rotate', defaultsTo: '0')
      ..addOption('duration', defaultsTo: '180ms')
      ..addOption('moves', help: 'Optional number of move events.')
      ..addOption('at', help: 'Optional start point as X,Y.');
  },
  action: (arguments) async {
    final dx = _finiteDouble(arguments, 'dx');
    final dy = _finiteDouble(arguments, 'dy');
    final scale = _finiteDouble(arguments, 'scale');
    final rotation = _finiteDouble(arguments, 'rotate');
    if (scale <= 0 || (dx == 0 && dy == 0 && scale == 1 && rotation == 0)) {
      throw const FormatException('pan requires movement, scale, or rotation.');
    }
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'pan',
      type: CockpitCommandType.panZoom,
      parameters: <String, Object?>{
        'panDx': dx,
        'panDy': dy,
        'scale': scale,
        'rotationRadians': rotation,
        'durationMs': _positiveDuration(arguments, 'duration').inMilliseconds,
        ..._optionalMoveCount(arguments),
        ..._optionalPoint(arguments),
      },
    );
  },
);

CockpitLeafCommand cockpitDevMultiTouchCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'multi',
  description: 'Run an explicit multi-pointer sequence on one Flutter target.',
  invocationSuffix: '[SELECTOR] [arguments]',
  example: 'cockpit dev multi "Canvas" --sequence-file gesture.yaml',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption('sequence', help: 'Sequence as LON, JSON, or YAML.')
      ..addOption(
        'sequence-file',
        help: 'Read sequence from a LON/JSON/YAML file.',
      )
      ..addOption('at', help: 'Optional origin as X,Y.');
  },
  action: (arguments) async {
    final sequence = runtime.structuredObject(
      arguments.option('sequence'),
      arguments.option('sequence-file'),
      option: 'sequence',
    );
    if (!sequence.containsKey('steps')) {
      throw const FormatException('Sequence must contain steps.');
    }
    final selector = arguments.rest.isEmpty ? null : arguments.rest.single;
    if (arguments.rest.length > 1) {
      throw const FormatException('dev multi accepts at most one selector.');
    }
    return _targetGestureAction(
      runtime,
      dev,
      arguments,
      action: 'multi',
      type: CockpitCommandType.multiTouch,
      selector: selector,
      targetRequired: false,
      parameters: <String, Object?>{
        'sequence': sequence,
        ..._optionalPoint(arguments),
      },
    );
  },
);

CockpitLeafCommand cockpitDevIncreaseCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => _directTargetCommand(
  runtime,
  dev,
  name: 'inc',
  description: 'Find, reveal, and increase one exact Flutter control.',
  example: 'cockpit dev inc ":a"',
  type: CockpitCommandType.increase,
);

CockpitLeafCommand cockpitDevDecreaseCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => _directTargetCommand(
  runtime,
  dev,
  name: 'dec',
  description: 'Find, reveal, and decrease one exact Flutter control.',
  example: 'cockpit dev dec ":a"',
  type: CockpitCommandType.decrease,
);

CockpitLeafCommand cockpitDevTypeCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'type',
  description:
      'Replace text in the focused or selected Flutter input, revealing it when needed.',
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
  description:
      'Dismiss the current Flutter menu, popup, dialog, sheet, or barrier.',
  example: 'cockpit dev dismiss',
  configure: _targetOptions,
  action: (arguments) async {
    final target = arguments.rest.length == 1 ? arguments.rest.single : null;
    if (arguments.rest.length > 1) {
      throw const FormatException('dev dismiss accepts at most one target.');
    }
    return dev.runCommand(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      action: 'dismiss',
      command: dev.command(
        type: CockpitCommandType.dismiss,
        timeout: runtime.operationTimeout,
        locator: cockpitReadDevLocator(
          arguments,
          selector: target,
          targetRequired: false,
        ),
      ),
    );
  },
);

CockpitLeafCommand cockpitDevRecoverCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'recover',
  description: 'Dismiss incidental system blockers and return to the app.',
  example: 'cockpit dev recover',
  configure: (parser) {
    cockpitAddDevSessionOption(parser);
    parser.addOption(
      'dialog',
      allowed: const <String>['dismiss', 'accept'],
      help:
          'Handle a proven native dialog; accept only when the scenario requires it.',
    );
    parser.addFlag(
      'keyboard',
      negatable: false,
      help: 'Also dismiss a system keyboard proven to block the app.',
    );
  },
  defaultTimeout: const Duration(minutes: 2),
  maximumTimeout: const Duration(minutes: 10),
  action: (arguments) => dev.recoverSystemBlockers(
    runtime.resolveDevelopmentSession(arguments.option('session')),
    dialog: arguments.option('dialog'),
    dismissKeyboard: arguments.flag('keyboard'),
    timeoutMilliseconds: runtime.operationTimeout.inMilliseconds,
  ),
);

CockpitLeafCommand cockpitDevOpenCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'open',
  description: 'Open a deep link, universal link, app link, or URL.',
  invocationSuffix: 'URI [arguments]',
  example: 'cockpit dev open "myapp://tasks/42"',
  configure: cockpitAddDevSessionOption,
  defaultTimeout: const Duration(minutes: 1),
  maximumTimeout: const Duration(minutes: 2),
  action: (arguments) async {
    if (arguments.rest.length != 1) {
      throw const FormatException('dev open requires exactly one URI.');
    }
    final value = arguments.rest.single.trim();
    if (value.length > 8192) {
      throw const FormatException('URI must not exceed 8192 characters.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('URI must be absolute and include a scheme.');
    }
    return dev.openUri(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      uri: value,
      scheme: uri.scheme,
      timeoutMilliseconds: runtime.operationTimeout.inMilliseconds,
    );
  },
);

CockpitLeafCommand cockpitDevScrollCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'scroll',
  description: 'Find, mount, fully reveal, and align one Flutter target.',
  invocationSuffix: 'SELECTOR [arguments]',
  example: 'cockpit dev scroll "Operations" --align center --offset 12',
  configure: (parser) {
    _targetOptions(parser);
    parser
      ..addOption(
        'direction',
        allowed: const <String>['up', 'down'],
        defaultsTo: 'down',
        help:
            'Choose the initial search direction; Cockpit reverses after reaching the boundary.',
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

Future<int> _targetGestureAction(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
  ArgResults arguments, {
  required String action,
  required CockpitCommandType type,
  required Map<String, Object?> parameters,
  String? selector,
  bool targetRequired = true,
}) async {
  final target =
      selector ?? (arguments.rest.length == 1 ? arguments.rest.single : null);
  if (targetRequired && (target == null || target.trim().isEmpty)) {
    throw FormatException('dev $action requires one target selector.');
  }
  if (target != null &&
      target.trim().isNotEmpty &&
      selector == null &&
      arguments.rest.length != 1) {
    throw FormatException('dev $action accepts exactly one target selector.');
  }
  return dev.runCommand(
    await runtime.resolveDevelopmentSession(arguments.option('session')),
    action: action,
    command: dev.command(
      type: type,
      timeout: runtime.operationTimeout,
      locator: cockpitReadDevLocator(
        arguments,
        selector: target,
        targetRequired: targetRequired,
      ),
      parameters: parameters,
    ),
  );
}

Map<String, Object?> _optionalGestureTiming(ArgResults arguments) {
  final rawHold = arguments.option('hold');
  if (rawHold == null) return _optionalMoveCount(arguments);
  return <String, Object?>{
    'holdDurationMs': _positiveDurationValue(rawHold, 'hold').inMilliseconds,
    ..._optionalMoveCount(arguments),
  };
}

Map<String, Object?> _optionalMoveCount(ArgResults arguments) {
  final raw = arguments.option('moves');
  if (raw == null) return const <String, Object?>{};
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0 || parsed > 10000) {
    throw const FormatException('--moves must be between 0 and 10000.');
  }
  return <String, Object?>{'moveEventCount': parsed};
}

Map<String, Object?> _optionalPoint(ArgResults arguments) {
  final raw = arguments.option('at');
  if (raw == null || raw.trim().isEmpty) return const <String, Object?>{};
  final parts = raw
      .split(',')
      .map((part) => double.tryParse(part.trim()))
      .toList();
  if (parts.length != 2 || parts.any((part) => part == null)) {
    throw const FormatException('--at must use X,Y coordinates.');
  }
  if (!parts[0]!.isFinite || !parts[1]!.isFinite) {
    throw const FormatException('--at must use finite X,Y coordinates.');
  }
  return <String, Object?>{'x': parts[0], 'y': parts[1]};
}

CockpitLeafCommand _directTargetCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev, {
  required String name,
  required String description,
  required String example,
  required CockpitCommandType type,
}) => CockpitLeafCommand(
  runtime: runtime,
  name: name,
  description: description,
  invocationSuffix: 'SELECTOR [arguments]',
  example: example,
  configure: _targetOptions,
  action: (arguments) =>
      _targetAction(runtime, dev, arguments, action: name, type: type),
);

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
  final raw = arguments.option(name);
  if (raw == null) {
    throw FormatException('--$name is required.');
  }
  final parsed = double.tryParse(raw);
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('--$name is invalid.');
  }
  return parsed;
}

double _positiveDouble(ArgResults arguments, String name) {
  final value = _finiteDouble(arguments, name);
  if (value <= 0) {
    throw FormatException('--$name must be positive.');
  }
  return value;
}

Duration _positiveDuration(ArgResults arguments, String name) {
  return _positiveDurationValue(arguments.option(name)!, name);
}

Duration _positiveDurationValue(String raw, String name) {
  final duration = cockpitParseDuration(raw);
  if (duration <= Duration.zero) {
    throw FormatException('--$name must be positive.');
  }
  return duration;
}
