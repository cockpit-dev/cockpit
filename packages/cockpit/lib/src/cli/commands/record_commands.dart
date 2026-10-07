import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../application/cockpit_interaction_recording_service.dart';
import '../cockpit_cli_runtime.dart';
import '../cockpit_dev_runtime.dart';
import '../cockpit_record_runtime.dart';
import 'dev_command_options.dart';

final class CockpitRecordCommand extends Command<int> {
  CockpitRecordCommand(this.runtime) {
    final record = CockpitRecordRuntime(runtime, CockpitDevRuntime(runtime));
    for (final action in const <String>['start', 'pause', 'resume', 'stop']) {
      addSubcommand(_lifecycle(runtime, record, action));
    }
    addSubcommand(_status(runtime, record));
    addSubcommand(_steps(runtime, record));
    addSubcommand(_export(runtime, record));
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'record';

  @override
  String get description =>
      'Record in-app interactions on the live development app and export them '
      'as a Cockpit case.';
}

void _addRecorderTargetOptions(ArgParser parser) {
  cockpitAddDevSessionOption(parser);
  parser.addOption(
    'endpoint',
    help:
        'App remote-session base URL, for apps launched outside a development '
        'session.',
  );
}

CockpitLeafCommand _lifecycle(
  CockpitCliRuntime runtime,
  CockpitRecordRuntime record,
  String action,
) => CockpitLeafCommand(
  runtime: runtime,
  name: action,
  description: switch (action) {
    'start' => 'Start recording in-app interactions.',
    'pause' => 'Pause the active interaction recording.',
    'resume' => 'Resume the paused interaction recording.',
    _ => 'Stop the interaction recording and return the recorded result.',
  },
  example: action == 'start'
      ? 'cockpit record start --name checkout'
      : 'cockpit record $action',
  configure: (parser) {
    _addRecorderTargetOptions(parser);
    if (action == 'start') {
      parser.addOption('name', help: 'Recording session name.');
    }
  },
  action: (arguments) async {
    final (service, exitCode) = await record.resolve(
      action: 'record.$action',
      session: arguments.option('session'),
      endpoint: arguments.option('endpoint'),
    );
    if (service == null) return exitCode;
    final payload = switch (action) {
      'start' => await service.start(name: _optionalName(arguments)),
      'pause' => await service.pause(),
      'resume' => await service.resume(),
      _ => await service.stop(),
    };
    await runtime.success(payload);
    return cockpitSuccessExitCode;
  },
);

CockpitLeafCommand _status(
  CockpitCliRuntime runtime,
  CockpitRecordRuntime record,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'status',
  description: 'Read the interaction recording session, or idle.',
  example: 'cockpit record status',
  configure: _addRecorderTargetOptions,
  action: (arguments) => _read(
    runtime,
    record,
    arguments,
    action: 'record.status',
    service: (service) => service.status(),
  ),
);

CockpitLeafCommand _steps(
  CockpitCliRuntime runtime,
  CockpitRecordRuntime record,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'steps',
  description: 'Read the recorded interaction steps after a cursor.',
  example: 'cockpit record steps --after 10',
  configure: (parser) {
    _addRecorderTargetOptions(parser);
    parser.addOption(
      'after',
      defaultsTo: '0',
      help: 'Only return steps recorded after this many consumed steps.',
    );
  },
  action: (arguments) async {
    final after = int.tryParse(arguments.option('after')!);
    if (after == null || after < 0) {
      throw const FormatException('--after must be a non-negative integer.');
    }
    return _read(
      runtime,
      record,
      arguments,
      action: 'record.steps',
      service: (service) => service.steps(after: after),
    );
  },
);

CockpitLeafCommand _export(
  CockpitCliRuntime runtime,
  CockpitRecordRuntime record,
) => CockpitLeafCommand(
  runtime: runtime,
  name: 'export',
  description: 'Export the recording as case YAML or a complete flow bundle.',
  example: 'cockpit record export --out flow.yaml',
  configure: (parser) {
    _addRecorderTargetOptions(parser);
    parser
      ..addOption('out', help: 'Write the document to this file.')
      ..addOption(
        'output-format',
        allowed: const <String>['yaml', 'json'],
        defaultsTo: 'yaml',
        help: 'Case YAML, or the complete flow bundle as JSON.',
      );
  },
  action: (arguments) async {
    final (service, exitCode) = await record.resolve(
      action: 'record.export',
      session: arguments.option('session'),
      endpoint: arguments.option('endpoint'),
    );
    if (service == null) return exitCode;
    final format = arguments.option('output-format')!;
    final bundle = await service.export();
    final out = arguments.option('out');
    if (out == null) {
      await runtime.success(service.exportDocument(bundle, format: format));
      return cockpitSuccessExitCode;
    }
    final resolved = p.normalize(
      p.isAbsolute(out) ? out : p.join(runtime.workingDirectory, out),
    );
    final document = format == 'yaml'
        ? bundle.caseYaml
        : const JsonEncoder.withIndent('  ').convert(bundle.toJson());
    await File(resolved).writeAsString('$document\n', flush: true);
    await runtime.success(<String, Object?>{
      'format': format,
      'path': resolved,
    });
    return cockpitSuccessExitCode;
  },
);

Future<int> _read(
  CockpitCliRuntime runtime,
  CockpitRecordRuntime record,
  ArgResults arguments, {
  required String action,
  required Future<Map<String, Object?>> Function(
    CockpitInteractionRecordingService service,
  )
  service,
}) async {
  final (resolved, exitCode) = await record.resolve(
    action: action,
    session: arguments.option('session'),
    endpoint: arguments.option('endpoint'),
  );
  if (resolved == null) return exitCode;
  await runtime.success(await service(resolved));
  return cockpitSuccessExitCode;
}

String? _optionalName(ArgResults arguments) {
  final name = arguments.option('name')?.trim();
  return name == null || name.isEmpty ? null : name;
}
