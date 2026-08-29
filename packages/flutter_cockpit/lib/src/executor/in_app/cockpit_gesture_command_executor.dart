import '../../control/cockpit_command.dart';
import '../../control/cockpit_command_execution.dart';
import '../../control/cockpit_command_type.dart';
import 'cockpit_command_router.dart';

final class CockpitGestureCommandExecutor {
  const CockpitGestureCommandExecutor({
    required this.hover,
    required this.wheel,
    required this.drag,
    required this.fling,
    required this.swipe,
    required this.pinchZoom,
    required this.rotate,
    required this.panZoom,
    required this.multiTouch,
  });

  final CockpitInAppCommandHandler hover;
  final CockpitInAppCommandHandler wheel;
  final CockpitInAppCommandHandler drag;
  final CockpitInAppCommandHandler fling;
  final CockpitInAppCommandHandler swipe;
  final CockpitInAppCommandHandler pinchZoom;
  final CockpitInAppCommandHandler rotate;
  final CockpitInAppCommandHandler panZoom;
  final CockpitInAppCommandHandler multiTouch;

  Future<CockpitCommandExecution> execute(
    CockpitCommand command,
    Stopwatch stopwatch,
  ) {
    return switch (command.commandType) {
      CockpitCommandType.hover => hover(command, stopwatch),
      CockpitCommandType.wheel => wheel(command, stopwatch),
      CockpitCommandType.drag => drag(command, stopwatch),
      CockpitCommandType.fling => fling(command, stopwatch),
      CockpitCommandType.swipe => swipe(command, stopwatch),
      CockpitCommandType.pinchZoom => pinchZoom(command, stopwatch),
      CockpitCommandType.rotate => rotate(command, stopwatch),
      CockpitCommandType.panZoom => panZoom(command, stopwatch),
      CockpitCommandType.multiTouch => multiTouch(command, stopwatch),
      _ => throw UnsupportedError(
        'Unsupported gesture command ${command.commandType.name}.',
      ),
    };
  }
}
