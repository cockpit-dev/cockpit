import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../cockpit_cli_runtime.dart';
import '../cockpit_dev_runtime.dart';
import 'dev_command_options.dart';

/// Invokes an app-registered action on the development session's app.
///
/// Arguments after the action name are either `key=value` pairs or exactly
/// one JSON object, so complex payloads travel without shell-quoting games:
///
/// ```sh
/// cockpit dev app-action setLocale locale=zh_Hant_TW
/// cockpit dev app-action setTheme palette='{"primary":"#2196F3"}'
/// cockpit dev app-action setTheme '{"primary":"#2196F3","contrast":0.8}'
/// ```
CockpitLeafCommand cockpitDevAppActionCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'app-action',
  description:
      'Invoke an app-registered action by name with key=value or JSON args.',
  invocationSuffix: 'ACTION [KEY=VALUE...] | ACTION [JSON]',
  example: 'cockpit dev app-action setLocale locale=zh_Hant_TW',
  defaultTimeout: const Duration(seconds: 30),
  configure: cockpitAddDevSessionOption,
  action: (arguments) async {
    if (arguments.rest.isEmpty) {
      throw const FormatException('dev app-action requires an action name.');
    }
    final name = arguments.rest.first.trim();
    if (name.isEmpty) {
      throw const FormatException('dev app-action requires an action name.');
    }
    final actionArguments = cockpitParseAppActionArguments(
      arguments.rest.skip(1),
    );
    return dev.runCommand(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      action: 'app-action',
      command: dev.command(
        type: CockpitCommandType.appAction,
        timeout: runtime.operationTimeout,
        parameters: <String, Object?>{
          'action': name,
          'arguments': ?actionArguments,
        },
      ),
    );
  },
);

CockpitLeafCommand cockpitDevDescribeAppCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'describe-app',
  description:
      'Read app-authored state, derived settings, and registered actions.',
  example: 'cockpit dev describe-app',
  defaultTimeout: const Duration(seconds: 30),
  configure: cockpitAddDevSessionOption,
  action: (arguments) async {
    if (arguments.rest.isNotEmpty) {
      throw const FormatException('dev describe-app takes no arguments.');
    }
    return dev.runCommand(
      await runtime.resolveDevelopmentSession(arguments.option('session')),
      action: 'describe-app',
      command: dev.command(
        type: CockpitCommandType.describeApp,
        timeout: runtime.operationTimeout,
      ),
    );
  },
);

/// Parses the arguments that follow the action name.
///
/// A single argument that starts with `{` is treated as one JSON object;
/// everything else must be `key=value` pairs whose values coerce from JSON
/// scalars (numbers, booleans, nested objects) and fall back to plain
/// strings. Returns null when no arguments were passed so the command omits
/// the `arguments` parameter entirely.
Map<String, Object?>? cockpitParseAppActionArguments(Iterable<String> raw) {
  final values = raw.toList(growable: false);
  if (values.isEmpty) return null;
  if (values.length == 1 && values.single.trimLeft().startsWith('{')) {
    final decoded = _decodeJson(values.single, 'arguments');
    if (decoded is! Map) {
      throw const FormatException(
        'JSON app-action arguments must decode to an object.',
      );
    }
    return Map<String, Object?>.from(decoded);
  }
  if (values.any((value) => value.trimLeft().startsWith('{'))) {
    throw const FormatException(
      'A JSON object must be the only app-action argument; use key=value '
      'pairs or one JSON object.',
    );
  }
  final arguments = <String, Object?>{};
  for (final value in values) {
    final separator = value.indexOf('=');
    if (separator < 1) {
      throw FormatException(
        'App-action arguments must use KEY=VALUE syntax: $value',
      );
    }
    final key = value.substring(0, separator).trim();
    if (key.isEmpty) {
      throw FormatException('App-action argument keys cannot be empty: $value');
    }
    if (arguments.containsKey(key)) {
      throw FormatException('App-action argument "$key" was passed twice.');
    }
    arguments[key] = _coerceScalar(value.substring(separator + 1).trim());
  }
  return arguments;
}

Object? _coerceScalar(String value) {
  if (value.isEmpty) return value;
  final first = value[0];
  final jsonLike =
      first == '{' ||
      first == '[' ||
      first == '"' ||
      value == 'true' ||
      value == 'false' ||
      value == 'null' ||
      RegExp(r'^-?\d').hasMatch(value);
  if (!jsonLike) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}

Object _decodeJson(String source, String what) {
  try {
    return jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException('Invalid $what JSON: ${error.message}');
  }
}
