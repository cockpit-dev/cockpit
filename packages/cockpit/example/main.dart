import 'dart:io';

import 'package:cockpit/cockpit.dart';

Future<void> main(List<String> args) async {
  final runner = CockpitCommandRunner();
  if (args.isNotEmpty) {
    exitCode = await runner.run(args);
    return;
  }

  stdout.writeln('Cockpit host tooling example');
  stdout.writeln('');
  stdout.writeln('Cockpit 3.0 fast path:');
  stdout.writeln('  cockpit dev start');
  stdout.writeln('  cockpit dev status');
  stdout.writeln('  cockpit dev inspect');
  stdout.writeln('  cockpit dev screenshot');
  stdout.writeln('  cockpit case list');
  stdout.writeln('  cockpit_mcp');
  stdout.writeln('');
  stdout.writeln(
    'This example can also proxy arguments into CockpitCommandRunner:',
  );
  stdout.writeln('  dart run example/main.dart daemon status');
}
