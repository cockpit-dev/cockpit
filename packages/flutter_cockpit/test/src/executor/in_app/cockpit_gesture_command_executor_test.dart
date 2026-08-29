import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/executor/in_app/cockpit_gesture_command_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes gesture-family commands to the configured handlers', () async {
    final handled = <CockpitCommandType>[];
    final executor = CockpitGestureCommandExecutor(
      hover: _handlerFor(handled),
      wheel: _handlerFor(handled),
      drag: _handlerFor(handled),
      fling: _handlerFor(handled),
      swipe: _handlerFor(handled),
      pinchZoom: _handlerFor(handled),
      rotate: _handlerFor(handled),
      panZoom: _handlerFor(handled),
      multiTouch: _handlerFor(handled),
    );

    await executor.execute(
      CockpitCommand(
        commandId: 'cmd-rotate',
        commandType: CockpitCommandType.rotate,
      ),
      Stopwatch()..start(),
    );

    expect(handled, <CockpitCommandType>[CockpitCommandType.rotate]);
  });
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
