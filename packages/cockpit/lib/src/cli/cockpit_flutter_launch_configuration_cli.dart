import 'package:args/args.dart';

import '../session/cockpit_flutter_launch_configuration.dart';

void cockpitAddFlutterLaunchConfigurationOptions(ArgParser parser) {
  parser
    ..addMultiOption(
      'dart-define',
      help:
          'Repeatable Flutter --dart-define KEY=VALUE. '
          'FLUTTER_COCKPIT_* keys are reserved.',
      splitCommas: false,
    )
    ..addMultiOption(
      'dart-define-from-file',
      help: 'Repeatable Flutter --dart-define-from-file path.',
      splitCommas: false,
    )
    ..addMultiOption(
      'flutter-arg',
      help:
          'Repeatable additional Flutter tool argument. Structured launch '
          'options and Cockpit control arguments cannot be overridden.',
      splitCommas: false,
    )
    ..addMultiOption(
      'env',
      help: 'Repeatable child-process environment override as KEY=VALUE.',
      splitCommas: false,
    );
}

Map<String, Object?>? cockpitReadFlutterLaunchConfiguration(
  ArgResults arguments,
) {
  final configuration = CockpitFlutterLaunchConfiguration(
    dartDefines: arguments.multiOption('dart-define'),
    dartDefineFromFiles: arguments.multiOption('dart-define-from-file'),
    flutterArgs: <String>[
      for (final value in arguments.multiOption('flutter-arg'))
        ...cockpitParseFlutterArgumentString(value),
    ],
    environment: _environment(arguments.multiOption('env')),
  );
  return configuration.isEmpty
      ? null
      : configuration.toJson(includeEnvironmentValues: true);
}

Map<String, String> _environment(List<String> values) {
  final result = <String, String>{};
  for (final value in values) {
    final separator = value.indexOf('=');
    if (separator <= 0) {
      throw FormatException('--env must use KEY=VALUE syntax: $value');
    }
    result[value.substring(0, separator)] = value.substring(separator + 1);
  }
  return result;
}
