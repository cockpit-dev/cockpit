import '../../control/cockpit_command.dart';
import '../../control/cockpit_command_execution.dart';
import '../../control/cockpit_command_type.dart';
import 'cockpit_command_router.dart';

final class CockpitTextInputCommandExecutor {
  const CockpitTextInputCommandExecutor({
    required this.enterText,
    required this.eraseText,
    required this.copyText,
    required this.pasteText,
    required this.focusTextInput,
    required this.setTextEditingValue,
    required this.sendTextInputAction,
    required this.sendKeyEvent,
    required this.sendKeyDownEvent,
    required this.sendKeyUpEvent,
  });

  final CockpitInAppCommandHandler enterText;
  final CockpitInAppCommandHandler eraseText;
  final CockpitInAppCommandHandler copyText;
  final CockpitInAppCommandHandler pasteText;
  final CockpitInAppCommandHandler focusTextInput;
  final CockpitInAppCommandHandler setTextEditingValue;
  final CockpitInAppCommandHandler sendTextInputAction;
  final CockpitInAppCommandHandler sendKeyEvent;
  final CockpitInAppCommandHandler sendKeyDownEvent;
  final CockpitInAppCommandHandler sendKeyUpEvent;

  Future<CockpitCommandExecution> execute(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    return switch (command.commandType) {
      CockpitCommandType.enterText => enterText(command, stopwatch),
      CockpitCommandType.eraseText => eraseText(command, stopwatch),
      CockpitCommandType.copyText => copyText(command, stopwatch),
      CockpitCommandType.pasteText => pasteText(command, stopwatch),
      CockpitCommandType.focusTextInput => focusTextInput(command, stopwatch),
      CockpitCommandType.setTextEditingValue => setTextEditingValue(
        command,
        stopwatch,
      ),
      CockpitCommandType.sendTextInputAction => sendTextInputAction(
        command,
        stopwatch,
      ),
      CockpitCommandType.sendKeyEvent => sendKeyEvent(command, stopwatch),
      CockpitCommandType.sendKeyDownEvent => sendKeyDownEvent(
        command,
        stopwatch,
      ),
      CockpitCommandType.sendKeyUpEvent => sendKeyUpEvent(command, stopwatch),
      _ => throw UnsupportedError(
        'Unsupported text-input command ${command.commandType.name}.',
      ),
    };
  }
}
