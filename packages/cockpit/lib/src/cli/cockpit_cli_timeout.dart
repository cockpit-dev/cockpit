import 'package:args/args.dart';

const Duration cockpitDefaultCliTimeout = Duration(minutes: 1);
const Duration cockpitMaximumCliTimeout = Duration(hours: 24);

void cockpitAddCliTimeoutOption(
  ArgParser parser, {
  Duration defaultTimeout = cockpitDefaultCliTimeout,
  Duration maximumTimeout = cockpitMaximumCliTimeout,
  String? defaultDescription,
}) {
  _validateBounds(defaultTimeout, maximumTimeout);
  parser.addOption(
    'timeout',
    defaultsTo: defaultDescription == null
        ? cockpitFormatDuration(defaultTimeout)
        : null,
    help:
        'Maximum command duration using ms, s, m, or h '
        '(max ${cockpitFormatDuration(maximumTimeout)}).'
        '${defaultDescription == null ? '' : ' $defaultDescription'}',
  );
}

Duration cockpitReadCliTimeout(
  ArgResults arguments, {
  Duration maximumTimeout = cockpitMaximumCliTimeout,
}) {
  final raw = arguments.option('timeout');
  if (raw == null) {
    throw const FormatException('Missing --timeout value.');
  }
  final timeout = cockpitParseDuration(raw);
  if (timeout <= Duration.zero || timeout > maximumTimeout) {
    throw FormatException(
      '--timeout must be between 1ms and '
      '${cockpitFormatDuration(maximumTimeout)}.',
    );
  }
  return timeout;
}

Duration cockpitParseDuration(String value) {
  final match = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(value.trim());
  if (match == null) {
    throw const FormatException(
      'Duration must be an integer followed by ms, s, m, or h.',
    );
  }
  final amount = int.tryParse(match.group(1)!);
  if (amount == null) throw const FormatException('Duration is too large.');
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: amount),
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    'h' => Duration(hours: amount),
    _ => throw StateError('Unreachable duration unit.'),
  };
}

String cockpitFormatDuration(Duration value) {
  final milliseconds = value.inMilliseconds;
  if (milliseconds % Duration.millisecondsPerHour == 0) {
    return '${value.inHours}h';
  }
  if (milliseconds % Duration.millisecondsPerMinute == 0) {
    return '${value.inMinutes}m';
  }
  if (milliseconds % Duration.millisecondsPerSecond == 0) {
    return '${value.inSeconds}s';
  }
  return '${milliseconds}ms';
}

void _validateBounds(Duration value, Duration maximum) {
  if (value <= Duration.zero || maximum < value) {
    throw ArgumentError('CLI timeout bounds are invalid.');
  }
}
