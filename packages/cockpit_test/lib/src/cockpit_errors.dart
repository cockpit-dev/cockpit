import 'package:cockpit_protocol/cockpit_protocol.dart';

/// Base error for failures raised by the platform-neutral Cockpit test API.
sealed class CockpitTestException implements Exception {
  const CockpitTestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Raised when a translated value cannot be resolved for the active locale.
final class CockpitTestLocalizationException extends CockpitTestException {
  const CockpitTestLocalizationException({
    required this.key,
    required String message,
  }) : super(message);

  final String key;
}

/// Raised before execution when a target cannot faithfully provide a command.
final class CockpitTestCapabilityException extends CockpitTestException {
  const CockpitTestCapabilityException(this.capability)
    : super('Cockpit test capability is not supported: $capability.');

  final String capability;
}

/// Raised when a command executed by a programmatic tester fails.
final class CockpitTestCommandException extends CockpitTestException {
  CockpitTestCommandException({required this.command, required this.execution})
    : super(
        'Cockpit command ${command.commandType.name} failed'
        '${execution.result.error == null ? '' : ': ${execution.result.error!.message}'}.',
      );

  final CockpitCommand command;
  final CockpitCommandExecution execution;
}

/// Preserves the primary action failure when cleanup also fails.
final class CockpitTestCleanupException extends CockpitTestException {
  CockpitTestCleanupException({
    required this.primaryError,
    required this.primaryStackTrace,
    required this.cleanupError,
    required this.cleanupStackTrace,
  }) : super(
         'The test action failed and cleanup also failed. '
         'Action: $primaryError. Cleanup: $cleanupError.',
       );

  final Object primaryError;
  final StackTrace primaryStackTrace;
  final Object cleanupError;
  final StackTrace cleanupStackTrace;
}
