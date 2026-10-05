/// Records agent training trajectories against a live Cockpit session.
///
/// Usage:
///   dart run tool/record_trajectory.dart record \
///     --scenario tool/trajectory/scenarios/cockpit_demo/settings_dark_mode.yaml \
///     --dataset tool/trajectory/datasets/demo
///   dart run tool/record_trajectory.dart validate \
///     --dataset tool/trajectory/datasets/demo
library;

import 'dart:io';

import 'package:args/args.dart';

import 'src/trajectory/cockpit_cli.dart';
import 'src/trajectory/recorder.dart';
import 'src/trajectory/scenario.dart';
import 'src/trajectory/trajectory.dart';
import 'src/trajectory/trajectory_writer.dart';

Future<int> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    _usage(_recordParser(), 'Specify a command: record or validate.');
    return 64;
  }
  switch (arguments.first) {
    case 'record':
      return _record(arguments.sublist(1));
    case 'validate':
      return _validate(arguments.sublist(1));
    default:
      _usage(_recordParser(), 'Unknown command: ${arguments.first}');
      return 64;
  }
}

ArgParser _recordParser() {
  return ArgParser(usageLineLength: 88)
    ..addOption(
      'scenario',
      abbr: 's',
      help: 'Scenario YAML file, or a directory of scenarios to record.',
    )
    ..addOption(
      'dataset',
      help: 'Dataset output directory.',
      defaultsTo: 'tool/trajectory/datasets/default',
    )
    ..addOption('session', help: 'Reuse a running dev session handle.')
    ..addOption(
      'platform',
      help: 'Override the scenario app platform for a recorder-launched app.',
    )
    ..addOption(
      'cockpit-bin',
      help: 'Cockpit executable.',
      defaultsTo: Platform.environment['COCKPIT_BIN'] ?? 'cockpit',
    )
    ..addOption(
      'format',
      help: 'Observation capture format appended to every command.',
      allowed: <String>['lon', 'json'],
      defaultsTo: 'lon',
    )
    ..addOption(
      'view',
      help: 'Observation capture view.',
      allowed: <String>['brief', 'more', 'full'],
      defaultsTo: 'brief',
    )
    ..addFlag('no-paraphrases', help: 'Skip emitting paraphrase variants.')
    ..addFlag(
      'keep-session',
      help: 'Do not stop a recorder-launched session afterwards.',
    )
    ..addOption(
      'repo-root',
      help: 'Repository root used to resolve app directories.',
      defaultsTo: Directory.current.path,
    );
}

Future<int> _record(List<String> arguments) async {
  final parser = _recordParser();
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    _usage(parser, error.message);
    return 64;
  }
  final scenarioSource = options['scenario'] as String?;
  if (scenarioSource == null) {
    _usage(parser, 'Missing --scenario.');
    return 64;
  }

  final scenarioFiles = _scenarioFiles(scenarioSource);
  if (scenarioFiles.isEmpty) {
    _usage(parser, 'No scenario files found at $scenarioSource.');
    return 64;
  }

  final repoRoot = _normalize(options['repo-root'] as String);
  final dataset = _normalize(options['dataset'] as String);
  final cockpitBin = options['cockpit-bin'] as String;
  final session = options['session'] as String?;
  final platformOverride = options['platform'] as String?;

  final version = await _cockpitVersion(cockpitBin);
  final recorder = TrajectoryRecorder(
    runner: ProcessCockpitRunner(bin: cockpitBin),
    repoRoot: repoRoot,
    cockpitBin: cockpitBin,
    observationFormat: options['format'] as String,
    observationView: options['view'] as String,
    cockpitVersion: version,
  );
  const writer = TrajectoryWriter();

  var failures = 0;
  for (final file in scenarioFiles) {
    final Scenario scenario;
    try {
      scenario = parseScenario(
        await File(file).readAsString(),
        sourceName: file,
      );
    } on ScenarioFormatException catch (error) {
      stderr.writeln('$error');
      failures++;
      continue;
    }
    final effective = platformOverride == null || platformOverride.isEmpty
        ? scenario
        : _withPlatform(scenario, platformOverride);
    final RecordedScenario recorded;
    try {
      recorded = await recorder.record(
        effective,
        datasetDirectory: dataset,
        sessionHandle: session,
        keepSession: options['keep-session'] as bool,
      );
    } on RecorderException catch (error) {
      stderr.writeln('Recording ${effective.id} failed: $error');
      failures++;
      continue;
    }
    final count = await writer.write(
      record: RecordedRecord(
        scenarioId: effective.id,
        trajectory: recorded.trajectory,
      ),
      datasetDirectory: dataset,
      includeParaphrases: !(options['no-paraphrases'] as bool),
    );
    stdout.writeln(
      '${effective.id}: ${trajectoryOutcomeToJson(recorded.trajectory.outcome)}'
      ' (${recorded.trajectory.steps.length} steps, $count records)',
    );
    for (final asset in recorded.assetPaths) {
      stdout.writeln('  asset: ${_relativeToCwd(asset)}');
    }
  }
  return failures == 0 ? 0 : 1;
}

Future<int> _validate(List<String> arguments) async {
  final parser = ArgParser(usageLineLength: 88)
    ..addOption(
      'dataset',
      help: 'Dataset directory to validate.',
      mandatory: true,
    );
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    _usage(parser, error.message);
    return 64;
  }
  final errors = await const TrajectoryDatasetValidator().validate(
    _normalize(options['dataset'] as String),
  );
  if (errors.isEmpty) {
    stdout.writeln('Dataset is valid.');
    return 0;
  }
  for (final error in errors) {
    stderr.writeln(error);
  }
  return 1;
}

List<String> _scenarioFiles(String source) {
  final type = FileSystemEntity.typeSync(source, followLinks: true);
  if (type == FileSystemEntityType.file) return <String>[source];
  if (type == FileSystemEntityType.directory) {
    return Directory(source)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.yaml'))
        .map((file) => file.path)
        .toList()
      ..sort();
  }
  return const <String>[];
}

Scenario _withPlatform(Scenario scenario, String platform) {
  return Scenario(
    id: scenario.id,
    app: ScenarioApp(
      name: scenario.app.name,
      directory: scenario.app.directory,
      platform: platform,
    ),
    goal: scenario.goal,
    paraphrases: scenario.paraphrases,
    completion: scenario.completion,
    includeSetup: scenario.includeSetup,
    steps: scenario.steps,
  );
}

Future<String?> _cockpitVersion(String bin) async {
  final result = await Process.run(bin, <String>['--version']);
  if (result.exitCode != 0) return null;
  final output = (result.stdout as String).trim();
  return output.isEmpty ? null : output.split('\n').first;
}

String _normalize(String path) {
  return path.startsWith('/') ? path : '${Directory.current.path}/$path';
}

String _relativeToCwd(String path) {
  final cwd = Directory.current.path;
  return path.startsWith('$cwd/') ? path.substring(cwd.length + 1) : path;
}

void _usage(ArgParser parser, String message) {
  stderr
    ..writeln('record_trajectory: $message')
    ..writeln(parser.usage);
}
