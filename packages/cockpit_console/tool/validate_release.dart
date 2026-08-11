import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/validate_release.dart <tag>');
    exitCode = 64;
    return;
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('Run this command from packages/cockpit_console.');
    exitCode = 66;
    return;
  }

  final document = loadYaml(pubspec.readAsStringSync());
  if (document is! YamlMap || document['version'] is! String) {
    stderr.writeln('pubspec.yaml must declare a string version.');
    exitCode = 65;
    return;
  }

  final version = document['version'] as String;
  final versionSource = File('lib/src/foundation/console_version.dart');
  final versionMatch = versionSource.existsSync()
      ? RegExp(
          r"const String consoleVersion = '([^']+)';",
        ).firstMatch(versionSource.readAsStringSync())
      : null;
  if (versionMatch?.group(1) != version) {
    stderr.writeln('consoleVersion must match pubspec.yaml version $version.');
    exitCode = 65;
    return;
  }
  final expectedTag = 'cockpit-console-v$version';
  if (arguments.single != expectedTag) {
    stderr.writeln(
      'Release tag ${arguments.single} does not match $expectedTag.',
    );
    exitCode = 65;
  }
}
