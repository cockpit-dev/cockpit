import 'package:args/args.dart';
import 'package:cockpit/src/cli/cockpit_flutter_launch_configuration_cli.dart';
import 'package:test/test.dart';

void main() {
  test('reads the complete structured Flutter launch configuration', () {
    final parser = ArgParser();
    cockpitAddFlutterLaunchConfigurationOptions(parser);

    final configuration = cockpitReadFlutterLaunchConfiguration(
      parser.parse(<String>[
        '--dart-define=API_URL=https://example.test',
        '--dart-define-from-file=config/staging.json',
        '--flutter-arg=--track-widget-creation',
        '--env=LOG_LEVEL=debug',
        '--env=EMPTY=',
      ]),
    );

    expect(configuration, <String, Object?>{
      'dartDefines': <String>['API_URL=https://example.test'],
      'dartDefineFromFiles': <String>['config/staging.json'],
      'flutterArgs': <String>['--track-widget-creation'],
      'environment': <String, String>{'LOG_LEVEL': 'debug', 'EMPTY': ''},
    });
  });

  test('omits an empty launch configuration', () {
    final parser = ArgParser();
    cockpitAddFlutterLaunchConfigurationOptions(parser);

    expect(cockpitReadFlutterLaunchConfiguration(parser.parse(const [])), null);
  });
}
