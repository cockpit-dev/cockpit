/// Generates synthetic Cockpit pattern apps for agent trajectory recording.
///
/// Usage:
///   dart run tool/gen_pattern_app.dart --pattern settings_flow --seed 7
///   dart run tool/gen_pattern_app.dart --pattern form_flow --name alpha_form
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/pattern_app/generator.dart';

Future<int> main(List<String> arguments) async {
  final parser = ArgParser(usageLineLength: 88)
    ..addOption(
      'pattern',
      abbr: 'k',
      help: 'UI pattern to generate.',
      allowed: <String>['settings_flow', 'form_flow', 'lazy_feed'],
      mandatory: true,
    )
    ..addOption(
      'seed',
      abbr: 'S',
      help: 'Seed controlling label/structure variation.',
      defaultsTo: '1',
    )
    ..addOption(
      'name',
      abbr: 'n',
      help: 'App package name (defaults to <pattern>_seed<seed>).',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Output parent directory.',
      defaultsTo: 'tool/trajectory/apps',
    )
    ..addOption(
      'repo-root',
      help: 'Repository root used to resolve the flutter_cockpit dependency.',
      defaultsTo: Directory.current.path,
    )
    ..addFlag(
      'overwrite',
      help: 'Replace the target directory if it already exists.',
    );
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    _usage(parser, error.message);
    return 64;
  }

  final kind = patternAppKindFromString(options['pattern'] as String);
  final seed = int.tryParse(options['seed'] as String);
  if (seed == null) {
    _usage(parser, '--seed must be an integer.');
    return 64;
  }
  final nameOption = (options['name'] as String?)?.trim();
  final name = nameOption != null && nameOption.isNotEmpty
      ? nameOption
      : '${options['pattern'] as String}_seed$seed';
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    _usage(parser, "--name must be a lower_snake_case Dart package name.");
    return 64;
  }

  final repoRoot = p.normalize(p.absolute(options['repo-root'] as String));
  final outputParent = p.normalize(p.absolute(options['output'] as String));
  final appDirectory = p.join(outputParent, name);
  final directory = Directory(appDirectory);
  if (directory.existsSync()) {
    if (!(options['overwrite'] as bool)) {
      _usage(parser, 'Target exists: $appDirectory (use --overwrite).');
      return 1;
    }
    directory.deleteSync(recursive: true);
  }

  final flutterCockpitPath = p.relative(
    p.join(repoRoot, 'packages', 'flutter_cockpit'),
    from: appDirectory,
  );
  final output = const PatternAppGenerator().generate(
    kind: kind,
    name: name,
    seed: seed,
    flutterCockpitPath: flutterCockpitPath,
  );
  for (final entry in output.files.entries) {
    final file = File(p.join(appDirectory, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  stdout
    ..writeln('Generated ${output.files.length} files in $appDirectory')
    ..writeln('flutter_cockpit dependency: $flutterCockpitPath')
    ..writeln('Next:')
    ..writeln('  cd $appDirectory')
    ..writeln('  flutter pub get')
    ..writeln(
      '  dart run tool/record_trajectory.dart record '
      '--scenario <scenario.yaml> --session <handle>',
    );
  return 0;
}

void _usage(ArgParser parser, String message) {
  stderr
    ..writeln('gen_pattern_app: $message')
    ..writeln(parser.usage);
}
