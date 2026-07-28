import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/cockpit_demo_acceptance_runner.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'platform',
      allowed: const <String>[
        'android',
        'ios',
        'linux',
        'macos',
        'web',
        'windows',
      ],
      defaultsTo: _hostPlatform(),
      help: 'Flutter launch platform.',
    )
    ..addOption('device-id', help: 'Connected Flutter device id.')
    ..addOption(
      'visual-profile',
      help: 'Named platform, viewport, and DPR profile for visual baselines.',
    )
    ..addOption(
      'project-dir',
      defaultsTo: _defaultProjectDirectory(),
      help: 'Absolute cockpit_demo development-shell directory.',
    )
    ..addOption(
      'root-dir',
      help:
          'Allowed root to register when no existing root contains the project.',
    )
    ..addOption('entrypoint', defaultsTo: 'main.dart')
    ..addOption('suite', defaultsTo: 'e2e/suites/regression.suite.yaml')
    ..addOption('output-root', defaultsTo: '.dart_tool/cockpit_acceptance')
    ..addOption('discovery-timeout-seconds', defaultsTo: '180')
    ..addOption('launch-timeout-seconds', defaultsTo: '600')
    ..addOption('run-timeout-seconds', defaultsTo: '900')
    ..addFlag(
      'require-recording',
      negatable: false,
      help: 'Fail when unattended native recording is unavailable.',
    )
    ..addFlag('stop-daemon', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  late final ArgResults parsed;
  try {
    parsed = parser.parse(arguments);
    if (parsed.flag('help')) {
      stdout.writeln('Run the Cockpit 2.0 demo acceptance suite.');
      stdout.writeln();
      stdout.writeln(parser.usage);
      return;
    }
    final request = CockpitDemoAcceptanceRequest(
      projectDirectory: parsed.option('project-dir')!,
      rootDirectory: parsed.option('root-dir'),
      platform: parsed.option('platform')!,
      deviceId: parsed.option('device-id'),
      visualProfile: parsed.option('visual-profile'),
      entrypoint: parsed.option('entrypoint')!,
      suitePath: parsed.option('suite')!,
      outputRoot: parsed.option('output-root')!,
      discoveryTimeout: _seconds(parsed, 'discovery-timeout-seconds'),
      launchTimeout: _seconds(parsed, 'launch-timeout-seconds'),
      runTimeout: _seconds(parsed, 'run-timeout-seconds'),
      stopDaemon: parsed.flag('stop-daemon'),
      requireRecording: parsed.flag('require-recording'),
    );
    final result = await CockpitDemoAcceptanceRunner(
      progress: (event) => stderr.writeln(jsonEncode(event)),
    ).run(request);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    exitCode = result.success ? 0 : 1;
  } on FormatException catch (error) {
    stderr.writeln('Invalid arguments: ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Acceptance runner failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

Duration _seconds(ArgResults parsed, String name) {
  final value = int.tryParse(parsed.option(name)!);
  if (value == null || value < 1) {
    throw FormatException('--$name must be a positive integer.');
  }
  return Duration(seconds: value);
}

String _defaultProjectDirectory() {
  final script = Platform.script;
  if (script.scheme == 'file') {
    return p.normalize(p.dirname(p.dirname(script.toFilePath())));
  }
  return p.normalize(Directory.current.absolute.path);
}

String _hostPlatform() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  throw const FormatException('--platform is required on this host.');
}
