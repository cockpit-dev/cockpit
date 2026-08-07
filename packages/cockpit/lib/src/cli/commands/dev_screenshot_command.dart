import 'package:args/args.dart';

import '../cockpit_cli_runtime.dart';
import '../cockpit_dev_runtime.dart';
import '../cockpit_dev_screenshot.dart';

CockpitLeafCommand cockpitDevScreenshotCommand(
  CockpitCliRuntime runtime,
  CockpitDevRuntime dev,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'screenshot',
  description: 'Capture and verify the current app screen as a local PNG.',
  example: 'cockpit dev screenshot --save /tmp/current.png',
  configure: (parser) => parser
    ..addOption('session', abbr: 's')
    ..addOption('save')
    ..addOption('compare')
    ..addOption('diff')
    ..addOption('pixel-tolerance', defaultsTo: '0')
    ..addOption('max-changed-pixels', defaultsTo: '0'),
  action: (arguments) async {
    final pixelTolerance = _integer(arguments, 'pixel-tolerance');
    final maximumChangedPixels = _integer(arguments, 'max-changed-pixels');
    if (pixelTolerance < 0 || pixelTolerance > 255) {
      throw const FormatException(
        '--pixel-tolerance must be between 0 and 255.',
      );
    }
    if (maximumChangedPixels < 0) {
      throw const FormatException('--max-changed-pixels cannot be negative.');
    }
    if (arguments.option('compare') == null &&
        arguments.option('diff') != null) {
      throw const FormatException('--diff requires --compare.');
    }
    return CockpitDevScreenshotService(runtime, dev).capture(
      sessionReference: arguments.option('session'),
      savePath: arguments.option('save'),
      baselinePath: arguments.option('compare'),
      diffPath: arguments.option('diff'),
      pixelTolerance: pixelTolerance,
      maximumChangedPixels: maximumChangedPixels,
    );
  },
);

int _integer(ArgResults arguments, String name) {
  final parsed = int.tryParse(arguments.option(name)!);
  if (parsed == null) throw FormatException('--$name is invalid.');
  return parsed;
}
