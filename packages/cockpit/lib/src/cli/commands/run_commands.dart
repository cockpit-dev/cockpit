import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../../supervisor/cockpit_supervisor_api_client.dart';
import '../cockpit_cli_output.dart';
import '../cockpit_cli_runtime.dart';
import '../cockpit_suite_report_exporter.dart';

final class CockpitCaseCommand extends Command<int> {
  CockpitCaseCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List indexed cases for a workspace.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('id', help: 'Return one exact authored case ID.')
          ..addOption('path', help: 'Filter by relative path substring.'),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final requestedId = arguments.option('id');
          final requestedPath = arguments.option('path');
          final items = (await (await runtime.client()).cases(workspaceId))
              .where(
                (testCase) =>
                    (requestedId == null || testCase.caseId == requestedId) &&
                    (requestedPath == null ||
                        testCase.relativePath?.contains(requestedPath) == true),
              )
              .map((testCase) => testCase.toJson())
              .toList(growable: false);
          await runtime.success(<String, Object?>{'items': items});
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'validate',
        description: 'Validate a case document.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('file', mandatory: true)
          ..addOption(
            'input-format',
            allowed: CockpitDocumentFormat.values.map((value) => value.name),
            help: 'Input document format; inferred from the file, then JSON.',
          ),
        action: (arguments) async {
          final file = File(arguments.option('file')!);
          if (await file.length() > cockpitSupervisorMaximumResponseBytes) {
            throw const FormatException('Case document exceeds 1 MiB.');
          }
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final format = _documentFormat(
            arguments.option('input-format'),
            file.path,
          );
          final result = await (await runtime.client()).validateCaseDocument(
            workspaceId,
            CockpitDocumentValidationRequest(
              format: format,
              sourceText: await file.readAsString(),
              relativePath: p.basename(file.path),
            ),
          );
          await runtime.success(result.toJson());
          return result.valid ? cockpitSuccessExitCode : cockpitDataExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'run',
        description: 'Run an indexed case with canonical source identity.',
        defaultTimeout: const Duration(minutes: 30),
        maximumTimeout: const Duration(hours: 6),
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('document-id')
          ..addOption('case-id', mandatory: true)
          ..addOption('idempotency-key', mandatory: true)
          ..addOption('inputs', help: 'Case inputs as LON, JSON, or YAML.')
          ..addOption('inputs-file', help: 'LON, JSON, or YAML case inputs.')
          ..addOption(
            'session',
            abbr: 's',
            help: 'Select another development session for this checkout.',
          )
          ..addOption(
            'target-id',
            help: 'Select a non-development or explicitly registered target.',
          ),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final documents = await (await runtime.client()).documents(
            workspaceId,
            kind: CockpitIndexedDocumentKind.testCase,
          );
          final requestedDocument = arguments.option('document-id');
          final caseId = arguments.option('case-id')!;
          final matches = documents.where(
            (document) =>
                (requestedDocument == null ||
                    document.documentId == requestedDocument) &&
                document.cases.any((testCase) => testCase.caseId == caseId),
          );
          if (matches.length != 1) {
            throw CockpitSupervisorClientException(
              code: matches.isEmpty ? 'caseNotFound' : 'caseAmbiguous',
              message: matches.isEmpty
                  ? 'Indexed case $caseId was not found.'
                  : 'Case $caseId exists in multiple documents; pass --document-id.',
            );
          }
          final document = matches.single;
          final accepted = await (await runtime.client()).submitRun(
            CockpitRunSubmission(
              workspaceId: workspaceId,
              source: CockpitIndexedCaseSource(
                reference: CockpitIndexedCaseReference(
                  documentId: document.documentId,
                  caseId: caseId,
                  documentSha256: document.sha256,
                ),
              ),
              idempotencyKey: CockpitIdempotencyKey(
                arguments.option('idempotency-key')!,
              ),
              inputs: runtime.structuredObject(
                arguments.option('inputs'),
                arguments.option('inputs-file'),
                option: 'inputs',
              ),
              targetId: await _runTargetId(
                runtime,
                arguments,
                workspaceId: workspaceId,
              ),
              timeoutMs: runtime.commandTimeout.inMilliseconds,
            ),
          );
          await runtime.success(accepted.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'case';

  @override
  String get description => 'Inspect, validate, and run canonical cases.';
}

final class CockpitSuiteCommand extends Command<int> {
  CockpitSuiteCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List indexed suites for a workspace.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('id', help: 'Return one exact authored suite ID.')
          ..addOption('path', help: 'Filter by relative path substring.'),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final requestedId = arguments.option('id');
          final requestedPath = arguments.option('path');
          final items =
              (await (await runtime.client()).documents(
                    workspaceId,
                    kind: CockpitIndexedDocumentKind.suite,
                  ))
                  .where(
                    (document) =>
                        document.kind == CockpitIndexedDocumentKind.suite &&
                        (requestedId == null ||
                            document.authoredId == requestedId) &&
                        (requestedPath == null ||
                            document.relativePath.contains(requestedPath)),
                  )
                  .map((document) => document.toJson())
                  .toList(growable: false);
          await runtime.success(<String, Object?>{'items': items});
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'validate',
        description: 'Validate a suite document.',
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('file', mandatory: true)
          ..addOption(
            'input-format',
            allowed: CockpitDocumentFormat.values.map((value) => value.name),
            help: 'Input document format; inferred from the file, then JSON.',
          ),
        action: (arguments) async {
          final file = File(arguments.option('file')!);
          if (await file.length() > cockpitSupervisorMaximumResponseBytes) {
            throw const FormatException('Suite document exceeds 1 MiB.');
          }
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final result = await (await runtime.client()).validateCaseDocument(
            workspaceId,
            CockpitDocumentValidationRequest(
              format: _documentFormat(
                arguments.option('input-format'),
                file.path,
              ),
              sourceText: await file.readAsString(),
              relativePath: p.basename(file.path),
            ),
          );
          await runtime.success(result.toJson());
          return result.valid ? cockpitSuccessExitCode : cockpitDataExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'run',
        description: 'Run an indexed suite as one durable campaign.',
        defaultTimeout: const Duration(hours: 2),
        maximumTimeout: const Duration(hours: 24),
        configure: (parser) => parser
          ..addOption('workspace-id')
          ..addOption('document-id')
          ..addOption('suite-id', mandatory: true)
          ..addOption('idempotency-key', mandatory: true)
          ..addOption('inputs', help: 'Suite inputs as LON, JSON, or YAML.')
          ..addOption('inputs-file', help: 'LON, JSON, or YAML suite inputs.')
          ..addOption(
            'session',
            abbr: 's',
            help: 'Select another development session for this checkout.',
          )
          ..addOption(
            'target-id',
            help: 'Select a non-development or explicitly registered target.',
          ),
        action: (arguments) async {
          final workspaceId = await runtime.workspaceId(
            arguments.option('workspace-id'),
          );
          final suiteId = arguments.option('suite-id')!;
          final requestedDocument = arguments.option('document-id');
          final documents =
              (await (await runtime.client()).documents(
                    workspaceId,
                    kind: CockpitIndexedDocumentKind.suite,
                  ))
                  .where(
                    (document) =>
                        document.kind == CockpitIndexedDocumentKind.suite &&
                        document.authoredId == suiteId &&
                        (requestedDocument == null ||
                            document.documentId == requestedDocument),
                  )
                  .toList(growable: false);
          if (documents.length != 1) {
            throw CockpitSupervisorClientException(
              code: documents.isEmpty ? 'suiteNotFound' : 'suiteAmbiguous',
              message: documents.isEmpty
                  ? 'Indexed suite $suiteId was not found.'
                  : 'Suite $suiteId exists in multiple documents; pass --document-id.',
            );
          }
          final document = documents.single;
          final accepted = await (await runtime.client()).submitRun(
            CockpitRunSubmission(
              workspaceId: workspaceId,
              source: CockpitIndexedSuiteSource(
                reference: CockpitIndexedSuiteReference(
                  documentId: document.documentId,
                  suiteId: suiteId,
                  documentSha256: document.sha256,
                ),
              ),
              idempotencyKey: CockpitIdempotencyKey(
                arguments.option('idempotency-key')!,
              ),
              inputs: runtime.structuredObject(
                arguments.option('inputs'),
                arguments.option('inputs-file'),
                option: 'inputs',
              ),
              targetId: await _runTargetId(
                runtime,
                arguments,
                workspaceId: workspaceId,
              ),
              timeoutMs: runtime.commandTimeout.inMilliseconds,
            ),
          );
          await runtime.success(accepted.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'report',
        description: 'Read or export the finalized canonical suite report.',
        configure: (parser) => parser
          ..addOption('run-id', mandatory: true)
          ..addOption(
            'output-dir',
            help: 'Export the verified complete offline report bundle.',
          ),
        action: (arguments) async {
          final runId = arguments.option('run-id')!;
          final client = await runtime.client();
          final report = await client.report(runId);
          final requestedOutputDirectory = arguments.option('output-dir');
          if (requestedOutputDirectory == null) {
            await runtime.success(report.toJson());
            return cockpitSuccessExitCode;
          }
          if (runtime.outputSelection.outputPath != null) {
            throw const FormatException(
              'Use --output-dir for the bundle without --output.',
            );
          }
          final outputDirectory = p.normalize(
            p.isAbsolute(requestedOutputDirectory)
                ? requestedOutputDirectory
                : p.join(runtime.workingDirectory, requestedOutputDirectory),
          );
          final receipt = await const CockpitSuiteReportExporter().export(
            runId: runId,
            outputDirectory: outputDirectory,
            artifacts: await client.artifacts(runId),
            download: client.downloadArtifactToFile,
          );
          runtime.fileReceipt(
            CockpitCliFileReceipt(
              path: receipt.path,
              mediaType: 'application/vnd.cockpit.report-bundle',
              sizeBytes: receipt.sizeBytes,
              sha256: receipt.manifestSha256,
            ),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'suite';

  @override
  String get description => 'Inspect, validate, run, and report suites.';
}

final class CockpitRunCommand extends Command<int> {
  CockpitRunCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'get',
        description: 'Read a run resource.',
        configure: (parser) => parser.addOption('run-id', mandatory: true),
        action: (arguments) async {
          await runtime.success(
            (await (await runtime.client()).run(
              arguments.option('run-id')!,
            )).toJson(),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'cancel',
        description: 'Cancel a run.',
        configure: (parser) => parser
          ..addOption('run-id', mandatory: true)
          ..addOption('idempotency-key', mandatory: true)
          ..addOption('reason'),
        action: (arguments) async {
          final result = await (await runtime.client()).cancelRun(
            arguments.option('run-id')!,
            CockpitRunCancellationRequest(
              idempotencyKey: CockpitIdempotencyKey(
                arguments.option('idempotency-key')!,
              ),
              reason: arguments.option('reason'),
            ),
          );
          await runtime.success(result.toJson());
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'events',
        description: 'Stream bounded run events until terminal or disconnect.',
        configure: (parser) => parser
          ..addOption('run-id', mandatory: true)
          ..addOption('after-sequence', defaultsTo: '0')
          ..addOption('last-event-id')
          ..addOption('max-events', defaultsTo: '1000'),
        action: (arguments) async {
          final after = _integer(arguments, 'after-sequence', minimum: 0);
          final maximum = _integer(
            arguments,
            'max-events',
            minimum: 1,
            maximum: 1000,
          );
          final jsonLines =
              runtime.outputSelection.format == CockpitCliFormat.jsonl;
          if (jsonLines && runtime.outputSelection.outputPath != null) {
            throw const FormatException(
              '--output cannot be combined with streaming JSONL; redirect stdout instead.',
            );
          }
          final values = <Map<String, Object?>>[];
          var emitted = 0;
          final events = StreamIterator(
            (await runtime.client()).events(
              arguments.option('run-id')!,
              afterSequence: after,
              lastEventId: arguments.option('last-event-id'),
            ),
          );
          try {
            while (await events.moveNext().timeout(
              runtime.remainingTimeout,
              onTimeout: () => throw CockpitCliTimeoutException(
                'run.events',
                runtime.commandTimeout,
              ),
            )) {
              final value = _streamItemJson(events.current);
              emitted += 1;
              if (jsonLines) {
                runtime.jsonLine(value);
              } else {
                values.add(value);
              }
              if (emitted >= maximum) break;
            }
          } finally {
            await events.cancel();
          }
          if (!jsonLines) {
            await runtime.success(<String, Object?>{'items': values});
          }
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'run';

  @override
  String get description => 'Read, cancel, and observe runs.';
}

final class CockpitArtifactCommand extends Command<int> {
  CockpitArtifactCommand(this.runtime) {
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'list',
        description: 'List immutable artifact metadata for a run.',
        configure: (parser) => parser.addOption('run-id', mandatory: true),
        action: (arguments) async {
          await runtime.success(<String, Object?>{
            'items': (await (await runtime.client()).artifacts(
              arguments.option('run-id')!,
            )).map((artifact) => artifact.toJson()).toList(),
          });
          return cockpitSuccessExitCode;
        },
      ),
    );
    addSubcommand(
      CockpitLeafCommand(
        runtime: runtime,
        name: 'read',
        description: 'Download a verified artifact to --output.',
        configure: (parser) => parser
          ..addOption('run-id', mandatory: true)
          ..addOption('artifact-id', mandatory: true),
        action: (arguments) async {
          final requestedOutput = runtime.outputSelection.outputPath;
          if (requestedOutput == null) {
            throw const FormatException('artifact read requires --output.');
          }
          final runId = arguments.option('run-id')!;
          final artifactId = arguments.option('artifact-id')!;
          final client = await runtime.client();
          final matches = (await client.artifacts(runId))
              .where((artifact) => artifact.artifactId == artifactId)
              .toList(growable: false);
          if (matches.length != 1) {
            throw CockpitSupervisorClientException(
              code: 'artifactNotFound',
              message: 'Artifact $artifactId was not found for run $runId.',
            );
          }
          final resolved = p.normalize(
            p.isAbsolute(requestedOutput)
                ? requestedOutput
                : p.join(runtime.workingDirectory, requestedOutput),
          );
          final receipt = await client.downloadArtifactToFile(
            artifact: matches.single,
            destination: File(resolved),
          );
          runtime.fileReceipt(
            CockpitCliFileReceipt(
              path: receipt.file.path,
              mediaType: receipt.mediaType,
              sizeBytes: receipt.sizeBytes,
              sha256: receipt.sha256,
            ),
          );
          return cockpitSuccessExitCode;
        },
      ),
    );
  }

  final CockpitCliRuntime runtime;

  @override
  String get name => 'artifact';

  @override
  String get description => 'List and read verified run artifacts.';
}

CockpitDocumentFormat _documentFormat(String? requested, String path) {
  if (requested != null) return CockpitDocumentFormat.values.byName(requested);
  return switch (p.extension(path).toLowerCase()) {
    '.lon' => CockpitDocumentFormat.lon,
    '.yaml' || '.yml' => CockpitDocumentFormat.yaml,
    _ => CockpitDocumentFormat.json,
  };
}

Future<String?> _runTargetId(
  CockpitCliRuntime runtime,
  ArgResults arguments, {
  required String workspaceId,
}) async {
  final targetId = arguments.option('target-id');
  final session = arguments.option('session');
  if (targetId != null && session != null) {
    throw const FormatException(
      '--session and --target-id are mutually exclusive.',
    );
  }
  if (targetId != null) return targetId;

  final handle = session == null
      ? await runtime.maybeActiveDevelopmentSession(workspaceId: workspaceId)
      : await runtime.resolveDevelopmentSession(session);
  if (handle == null) return null;
  if (handle.workspaceId != workspaceId) {
    throw const FormatException(
      'Session handle belongs to a different workspace.',
    );
  }
  return handle.targetId!;
}

Map<String, Object?> _streamItemJson(CockpitRunStreamItem item) =>
    switch (item) {
      CockpitRunStreamEvent() => <String, Object?>{
        'type': 'event',
        'event': item.event.toJson(),
      },
      CockpitRunStreamGap() => <String, Object?>{
        'type': 'gap',
        'boundary': item.boundary.toJson(),
      },
      CockpitRunStreamTerminal() => <String, Object?>{
        'type': 'terminal',
        'afterSequence': item.afterSequence,
      },
      CockpitRunStreamDisconnected() => <String, Object?>{
        'type': 'disconnected',
        'afterSequence': item.afterSequence,
      },
    };

int _integer(
  ArgResults arguments,
  String name, {
  required int minimum,
  int? maximum,
}) {
  final value = int.tryParse(arguments.option(name)!);
  if (value == null || value < minimum || maximum != null && value > maximum) {
    throw FormatException('--$name is invalid.');
  }
  return value;
}
