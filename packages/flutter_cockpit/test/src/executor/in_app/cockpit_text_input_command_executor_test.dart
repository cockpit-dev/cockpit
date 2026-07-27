import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/executor/in_app/cockpit_text_input_command_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'routes text-input family commands to the configured handlers',
    () async {
      final handled = <CockpitCommandType>[];
      final executor = CockpitTextInputCommandExecutor(
        enterText: _handlerFor(handled),
        eraseText: _handlerFor(handled),
        copyText: _handlerFor(handled),
        pasteText: _handlerFor(handled),
        focusTextInput: _handlerFor(handled),
        setTextEditingValue: _handlerFor(handled),
        sendTextInputAction: _handlerFor(handled),
        sendKeyEvent: _handlerFor(handled),
        sendKeyDownEvent: _handlerFor(handled),
        sendKeyUpEvent: _handlerFor(handled),
      );

      await executor.execute(
        CockpitCommand(
          commandId: 'cmd-key-down',
          commandType: CockpitCommandType.sendKeyDownEvent,
        ),
        Stopwatch()..start(),
      );

      expect(handled, <CockpitCommandType>[
        CockpitCommandType.sendKeyDownEvent,
      ]);
    },
  );
}

Future<CockpitCommandExecution> Function(CockpitCommand, Stopwatch) _handlerFor(
  List<CockpitCommandType> handled,
) {
  return (command, stopwatch) async {
    handled.add(command.commandType);
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );
  };
}
