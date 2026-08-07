import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:lon/lon.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('CockpitCliOutputSelection', () {
    test('defaults to AI minimal output', () {
      final parser = ArgParser();
      cockpitAddCliOutputOptions(parser);

      final selection = CockpitCliOutputSelection.fromArguments(
        parser.parse(const <String>[]),
      );

      expect(selection.format, CockpitCliFormat.lon);
      expect(selection.detail, CockpitCliOutputDetail.minimal);
      expect(parser.usage, contains('lon by default'));
      expect(
        parser.usage,
        contains('json/yaml/jsonl for structured pipelines'),
      );
      expect(parser.usage, contains('--format'));
      expect(parser.usage, isNot(contains('--stdout-format')));
      expect(parser.usage, contains('--verbosity'));
      expect(parser.usage, isNot(contains('--detail')));
      expect(selection.outputPath, isNull);
    });

    test('reads explicit output controls', () {
      final parser = ArgParser();
      cockpitAddCliOutputOptions(parser);

      final selection = CockpitCliOutputSelection.fromArguments(
        parser.parse(const <String>[
          '--format',
          'none',
          '--verbosity',
          'standard',
          '--output',
          'result.json',
        ]),
      );

      expect(selection.format, CockpitCliFormat.none);
      expect(selection.detail, CockpitCliOutputDetail.standard);
      expect(selection.outputPath, 'result.json');
    });

    test('pre-scans output controls before command parsing', () {
      final selection = CockpitCliOutputSelection.fromRawArguments(
        const <String>[
          'daemon',
          'stop',
          '--format=json',
          '--verbosity',
          'full',
        ],
      );

      expect(selection.format, CockpitCliFormat.json);
      expect(selection.detail, CockpitCliOutputDetail.full);
    });
  });

  test('structured CLI input accepts JSON and LON objects', () {
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    );

    expect(runtime.structuredObject('{"width":800}', null), <String, Object?>{
      'width': 800,
    });
    expect(
      runtime.structuredObject('{width:800 height:600}', null),
      <String, Object?>{'width': 800, 'height': 600},
    );
    expect(
      runtime.structuredObject('width: 800\nheight: 600', null),
      <String, Object?>{'width': 800, 'height': 600},
    );
    expect(
      () => runtime.structuredObject('{}', 'input.lon'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('--input and --input-file'),
        ),
      ),
    );
  });

  test('LON, JSON, and YAML preserve one semantic projection', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'ok': true,
      'action': 'status',
      'session': '1',
      'state': <String, Object?>{
        'lifecycle': 'ready',
        'runtimeErrors': <Object?>[],
      },
    };

    final lonValue = lon.decode(
      renderer.renderAi(
        command: 'dev.status',
        data: data,
        detail: CockpitCliOutputDetail.minimal,
      ),
    );
    final jsonValue = jsonDecode(
      renderer.renderJson(
        command: 'dev.status',
        data: data,
        detail: CockpitCliOutputDetail.minimal,
      ),
    );
    final yamlValue = jsonDecode(
      jsonEncode(
        loadYaml(
          renderer.renderYaml(
            command: 'dev.status',
            data: data,
            detail: CockpitCliOutputDetail.minimal,
          ),
        ),
      ),
    );

    expect(jsonValue, lonValue);
    expect(yamlValue, lonValue);
  });

  test('dev status does not invent diagnostics that were not collected', () {
    const renderer = CockpitCliOutputRenderer();

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.status',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'status',
                  'session': '1',
                  'state': <String, Object?>{
                    'lifecycle': 'ready',
                    'checkoutPath': '/workspace/app',
                    'entrypoint': 'lib/main.dart',
                  },
                },
                detail: CockpitCliOutputDetail.minimal,
              ),
            )!
            as Map<Object?, Object?>;
    final state = value['state']! as Map<Object?, Object?>;

    expect(state, isNot(contains('errors')));
    expect(state, isNot(contains('netFailures')));
  });

  test(
    'dev status reports diagnostic zeroes when diagnostics were collected',
    () {
      const renderer = CockpitCliOutputRenderer();

      final value =
          lon.decode(
                renderer.renderAi(
                  command: 'dev.status',
                  data: const <String, Object?>{
                    'ok': true,
                    'action': 'status',
                    'session': '1',
                    'state': <String, Object?>{
                      'lifecycle': 'ready',
                      'runtimeErrors': <String, Object?>{
                        'summary': <String, Object?>{'errorCount': 0},
                      },
                      'network': <String, Object?>{
                        'summary': <String, Object?>{'failureCount': 0},
                      },
                    },
                  },
                  detail: CockpitCliOutputDetail.minimal,
                ),
              )!
              as Map<Object?, Object?>;
      final state = value['state']! as Map<Object?, Object?>;

      expect(state['errors'], 0);
      expect(state['netFailures'], 0);
    },
  );

  test('dev minimal output keeps only decision fields', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.tap',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'tap',
                  'session': '2',
                  'changed': 'observed',
                  'state': <String, Object?>{
                    'command': <String, Object?>{
                      'command': <String, Object?>{
                        'success': true,
                        'commandId': 'verbose-id',
                        'durationMs': 123,
                        'locator': <String, Object?>{
                          'matchedKind': 'text',
                          'matchedValue': 'Documents',
                        },
                        'effectiveSnapshotOptions': <String, Object?>{
                          'profile': 'baseline',
                        },
                      },
                    },
                    'postcondition': <String, Object?>{
                      'effectiveSnapshotOptions': <String, Object?>{
                        'profile': 'live',
                      },
                    },
                  },
                },
                detail: CockpitCliOutputDetail.minimal,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value['ok'], isTrue);
    expect(value['session'], '2');
    expect(value, isNot(contains('action')));
    expect(value, isNot(contains('state')));
    expect(value, isNot(contains('_meta')));
  });

  test(
    'dev screenshot exposes capture source only when diagnostic or degraded',
    () {
      const renderer = CockpitCliOutputRenderer();
      const data = <String, Object?>{
        'ok': true,
        'action': 'screenshot',
        'session': '1',
        'state': <String, Object?>{
          'capture': 'flutterView',
          'fallback': true,
          'degraded': 'hostCaptureFailed',
          'plane': 'flutterSemanticPlane',
          'width': 800,
          'height': 600,
        },
        'evidence': <String, Object?>{
          'actual': <String, Object?>{'path': '/tmp/current.png'},
        },
      };

      final minimal =
          lon.decode(
                renderer.renderAi(
                  command: 'dev.screenshot',
                  data: data,
                  detail: CockpitCliOutputDetail.minimal,
                ),
              )!
              as Map<Object?, Object?>;
      final minimalState = minimal['state']! as Map<Object?, Object?>;
      expect(minimalState, <Object?, Object?>{
        'capture': 'flutterView',
        'fallback': true,
        'degraded': 'hostCaptureFailed',
      });

      final standard =
          lon.decode(
                renderer.renderAi(
                  command: 'dev.screenshot',
                  data: data,
                  detail: CockpitCliOutputDetail.standard,
                ),
              )!
              as Map<Object?, Object?>;
      expect(standard['state'], data['state']);
    },
  );

  test('dev network keeps a bounded index and body paths only', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'ok': true,
      'action': 'network',
      'session': '1',
      'state': <String, Object?>{
        'available': true,
        'summary': <String, Object?>{
          'totalEntryCount': 42,
          'capturedEntryCount': 80,
          'failureCount': 2,
          'inFlightCount': 1,
          'truncated': true,
          'query': <String, Object?>{},
        },
        'endpointSummaries': <Object?>[
          <String, Object?>{
            'method': 'GET',
            'uriPattern': '/api/items',
            'requestCount': 10,
            'failureCount': 1,
            'averageDurationMs': 24,
            'lastStatusCode': 500,
          },
        ],
        'entries': <Object?>[
          <String, Object?>{
            'requestId': '37',
            'method': 'GET',
            'uri': 'https://example.test/api/items',
            'protocol': 'http',
            'state': 'receiving',
            'statusCode': 200,
            'durationMs': 24,
            'responseBodyBytes': 1024,
            'responseHeaders': <String, String>{'authorization': '********'},
            'responseBodyPreview': 'large preview must not be minimal',
            'sha256': 'unused-digest',
          },
        ],
        'body': <String, String>{'response': '/tmp/network-37-response.json'},
        'continuing': true,
      },
      'evidence': <String, String>{'response': '/tmp/network-37-response.json'},
      'next': 'cockpit dev network 37 --body response',
    };

    final rendered = renderer.renderAi(
      command: 'dev.network',
      data: data,
      detail: CockpitCliOutputDetail.minimal,
    );

    expect(rendered, contains('id:"37"'));
    expect(rendered, contains('active:1'));
    expect(rendered, contains('response:/tmp/network-37-response.json'));
    expect(
      RegExp(
        RegExp.escape('/tmp/network-37-response.json'),
      ).allMatches(rendered),
      hasLength(1),
    );
    expect(rendered, contains('continuing:true'));
    expect(rendered, isNot(contains('bytes')));
    expect(rendered, isNot(contains('responseHeaders')));
    expect(rendered, isNot(contains('large preview')));
    expect(rendered, isNot(contains('sha256')));
    expect(rendered, isNot(contains('unused-digest')));

    final standard = renderer.renderAi(
      command: 'dev.network',
      data: data,
      detail: CockpitCliOutputDetail.standard,
    );
    expect(standard, isNot(contains('responseHeaders')));
    expect(standard, isNot(contains('large preview')));
    expect(standard, isNot(contains('unused-digest')));
  });

  test('structured command flags do not encode JSON in their names', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final op = runner.commands['op']!.subcommands['run']!;
    expect(op.argParser.options, contains('input'));
    expect(op.argParser.options, contains('session'));
    expect(op.argParser.options, isNot(contains('input-json')));
    expect(op.argParser.options, isNot(contains('kind')));
    expect(op.argParser.options['timeout']!.defaultsTo, isNull);
    expect(
      op.argParser.options['timeout']!.help,
      contains('advertised budget'),
    );
    expect(op.invocation, 'cockpit op run KIND [arguments]');
    expect(op.argParser.parse(const <String>['viewport.set']).rest, <String>[
      'viewport.set',
    ]);
    expect(runner.commands, isNot(contains('operation')));
    expect(runner.commands, isNot(contains('exec')));
    expect(runner.commands, isNot(contains('raw')));
    expect(
      runner.commands['explain']!.invocation,
      'cockpit explain KIND [arguments]',
    );

    for (final commandName in <String>['case', 'suite']) {
      final command = runner.commands[commandName]!;
      expect(command.subcommands['run']!.argParser.options, contains('inputs'));
      expect(
        command.subcommands['run']!.argParser.options,
        isNot(contains('inputs-json')),
      );
      expect(
        command.subcommands['validate']!.argParser.options,
        contains('input-format'),
      );
    }
  });

  test('usage errors honor an explicitly requested JSON format', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'daemon',
      'stop',
      '--mode',
      'immediate',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitUsageExitCode);
    final envelope = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect(envelope, isNot(contains('ok')));
    expect((envelope['error']! as Map<String, Object?>)['code'], 'usage');
  });

  test('workspace exposes indexed documents to CLI-only clients', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final workspace = runner.commands['workspace'];
    expect(workspace, isNotNull);
    expect(workspace!.subcommands, contains('documents'));
    final documents = workspace.subcommands['documents'];
    expect(documents, isNotNull);
    expect(documents!.argParser.options, contains('workspace-id'));
    expect(documents.argParser.options, contains('kind'));
    expect(documents.argParser.options, contains('relative-path'));
  });

  test('E2E commands expose focused discovery and session selection', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    for (final commandName in const <String>['case', 'suite']) {
      final command = runner.commands[commandName]!;
      final list = command.subcommands['list']!;
      final run = command.subcommands['run']!;

      expect(list.argParser.options.keys, containsAll(<String>['id', 'path']));
      expect(run.argParser.options['session']!.abbr, 's');
      expect(run.argParser.options, contains('target-id'));
    }
  });

  test('minimal target listings retain the entrypoint identity', () {
    const renderer = CockpitCliOutputRenderer();
    final output = renderer.renderAi(
      command: 'target.list',
      data: const <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'targetId': 'target-1',
            'platform': 'macos',
            'targetKind': 'flutterApp',
            'entrypoint': 'cockpit/main.dart',
          },
        ],
      },
      detail: CockpitCliOutputDetail.minimal,
    );

    expect(output, contains('cockpit/main.dart'));
  });

  test('standard listings omit digests that do not change the next action', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'documentId': 'document-1',
          'relativePath': 'cases/login.yaml',
          'sha256': 'unused-digest',
          'modifiedAt': '2026-08-05T00:00:00Z',
        },
      ],
    };

    final standard = renderer.renderAi(
      command: 'workspace.documents',
      data: data,
      detail: CockpitCliOutputDetail.standard,
    );
    expect(standard, contains('modifiedAt'));
    expect(standard, isNot(contains('sha256')));
    expect(standard, isNot(contains('unused-digest')));
    expect(
      renderer.renderJson(
        command: 'workspace.documents',
        data: data,
        detail: CockpitCliOutputDetail.full,
      ),
      contains('unused-digest'),
    );
  });

  test('artifact listings omit hashes and byte counts', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'artifactId': 'artifact-1',
          'kind': 'attempt.screenshot',
          'relativePath': 'artifacts/screenshot.png',
          'mediaType': 'image/png',
          'sizeBytes': 140965,
          'sha256': 'unused-digest',
        },
      ],
    };

    final output = renderer.renderAi(
      command: 'artifact.list',
      data: data,
      detail: CockpitCliOutputDetail.standard,
    );

    expect(output, contains('artifacts/screenshot.png'));
    expect(output, isNot(contains('140965')));
    expect(output, isNot(contains('sha256')));
    expect(output, isNot(contains('unused-digest')));
  });

  test('run events keep terminal state and failures in minimal output', () {
    const renderer = CockpitCliOutputRenderer();
    final data = <String, Object?>{
      'items': <Object?>[
        for (var sequence = 1; sequence <= 8; sequence += 1)
          <String, Object?>{
            'type': 'event',
            'event': <String, Object?>{
              'sequence': sequence,
              'kind': 'step.passed',
              'stepExecutionId': 'main/step-$sequence',
              'status': 'passed',
            },
          },
        <String, Object?>{
          'type': 'event',
          'event': <String, Object?>{
            'sequence': 9,
            'kind': 'step.failed',
            'stepExecutionId': 'main/capture',
            'status': 'failed',
            'failure': <String, Object?>{
              'primary': <String, Object?>{
                'code': 'evidenceFailed',
                'message': 'Screenshot failed.',
                'retryable': true,
              },
            },
          },
        },
        <String, Object?>{
          'type': 'event',
          'event': <String, Object?>{
            'sequence': 10,
            'kind': 'run.completed',
            'lifecycle': 'completed',
            'outcome': 'failed',
            'stability': 'stable',
          },
        },
        <String, Object?>{'type': 'terminal', 'afterSequence': 10},
      ],
    };

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'run.events',
                data: data,
                detail: CockpitCliOutputDetail.minimal,
              ),
            )!
            as Map<Object?, Object?>;
    final failures = value['failures']! as List<Object?>;
    final failure = failures.single as Map<Object?, Object?>;
    final finalEvent = value['final']! as Map<Object?, Object?>;

    expect(value['stream'], 'terminal');
    expect(value['afterSequence'], 10);
    expect(value['eventCount'], 10);
    expect(failure['stepExecutionId'], 'main/capture');
    expect(
      (failure['failure']! as Map<Object?, Object?>)['code'],
      'evidenceFailed',
    );
    expect(finalEvent['outcome'], 'failed');
    expect(value, isNot(contains('_meta')));
  });

  test('suite report exposes complete offline bundle export', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final suite = runner.commands['suite'];
    expect(suite, isNotNull);
    final report = suite!.subcommands['report'];
    expect(report, isNotNull);
    expect(report!.argParser.options, contains('run-id'));
    expect(report.argParser.options, contains('output-dir'));
  });

  group('CockpitCliOutputRenderer', () {
    test('renders default AI output as canonical LON', () {
      const renderer = CockpitCliOutputRenderer();

      final text = renderer.renderAi(
        command: 'daemon.status',
        data: const <String, Object?>{
          'running': true,
          'healthy': true,
          'auth': 'yolo',
          'unused': null,
        },
        detail: CockpitCliOutputDetail.minimal,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;

      expect(text, '{healthy:true running:true auth:yolo}');
      expect(value['running'], isTrue);
      expect(value['healthy'], isTrue);
      expect(value['auth'], 'yolo');
      expect(value, isNot(contains('unused')));
      expect(lon.encode(value), text);
    });

    test('prioritizes failing report rows and reports omissions', () {
      const renderer = CockpitCliOutputRenderer(standardMaximumBytes: 2400);
      final cases = <Map<String, Object?>>[
        <String, Object?>{
          'entryId': 'failed-entry',
          'caseId': 'failed-case',
          'outcome': 'failed',
          'stability': 'stable',
          'targetId': 'android',
          'attempts': <Object?>[
            <String, Object?>{
              'attemptId': 'attempt-failed',
              'number': 1,
              'outcome': 'failed',
              'targetId': 'android',
              'failure': <String, Object?>{
                'code': 'assertionFailed',
                'message': 'Expected Save to be visible.',
              },
            },
          ],
        },
        for (var index = 0; index < 80; index += 1)
          <String, Object?>{
            'entryId': 'passed-entry-$index',
            'caseId': 'passed-case-$index',
            'outcome': 'passed',
            'stability': 'stable',
            'targetId': 'android',
            'attempts': <Object?>[
              <String, Object?>{
                'attemptId': 'attempt-passed-$index',
                'number': 1,
                'outcome': 'passed',
                'targetId': 'android',
              },
            ],
          },
      ];

      final text = renderer.renderAi(
        command: 'suite.report',
        data: <String, Object?>{
          'schemaVersion': 'cockpit.report/v2',
          'projectId': 'project',
          'workspaceId': 'workspace',
          'runId': 'run-1',
          'suiteId': 'regression',
          'lifecycle': 'completed',
          'outcome': 'failed',
          'stability': 'stable',
          'durationMs': 4200,
          'counts': const <String, Object?>{
            'total': 81,
            'passed': 80,
            'failed': 1,
          },
          'cases': cases,
        },
        detail: CockpitCliOutputDetail.standard,
      );

      final value = lon.decode(text)! as Map<Object?, Object?>;
      final renderedCases = value['cases']! as List<Object?>;
      final metadata = value['_meta']! as Map<Object?, Object?>;

      expect(text.length, lessThanOrEqualTo(2400));
      expect(
        (renderedCases.first as Map<Object?, Object?>)['entryId'],
        'failed-entry',
      );
      expect(metadata['more'], isTrue);
      expect(metadata['skipped'], isA<int>());
      expect(lon.encode(value), text);
    });

    test('renders exact JSON at full detail', () {
      const renderer = CockpitCliOutputRenderer();
      final data = <String, Object?>{
        'items': <Object?>[
          for (var index = 0; index < 100; index += 1)
            <String, Object?>{'id': 'item-$index', 'value': index},
        ],
      };

      final text = renderer.renderJson(
        command: 'artifact.list',
        data: data,
        detail: CockpitCliOutputDetail.full,
      );
      final result = jsonDecode(text) as Map<String, Object?>;

      expect(result['items']! as List<Object?>, hasLength(100));
      expect(result, isNot(contains('_meta')));
    });

    test('projects analysis for both AI text and JSON detail', () {
      const renderer = CockpitCliOutputRenderer();
      final operation = <String, Object?>{
        'operationId': 'operation-1',
        'kind': 'analyze.files',
        'lifecycle': 'completed',
        'outcome': 'failed',
        'workspaceId': 'workspace-1',
        'output': <String, Object?>{
          'workspaceRoot': '/private/workspace',
          'success': false,
          'clean': false,
          'summary': '1 error, 1 warning',
          'totalDiagnostics': 2,
          'severityCounts': <String, Object?>{'error': 1, 'warning': 1},
          'diagnostics': <Object?>[
            <String, Object?>{
              'severity': 'warning',
              'code': 'unused_local_variable',
              'message': 'Unused value.',
              'path': 'lib/a.dart',
              'line': 8,
              'column': 3,
              'documentationUrl': 'https://example.invalid/unused',
            },
            <String, Object?>{
              'severity': 'error',
              'code': 'undefined_identifier',
              'message': 'Undefined name.',
              'path': 'lib/b.dart',
              'line': 4,
              'column': 7,
            },
          ],
        },
      };

      final ai = renderer.renderAi(
        command: 'op.run',
        data: operation,
        detail: CockpitCliOutputDetail.minimal,
      );
      final aiValue = lon.decode(ai)! as Map<Object?, Object?>;
      final json =
          jsonDecode(
                renderer.renderJson(
                  command: 'op.run',
                  data: operation,
                  detail: CockpitCliOutputDetail.minimal,
                ),
              )
              as Map<String, Object?>;

      final aiOutput = aiValue['output']! as Map<Object?, Object?>;
      final aiDiagnostics = aiOutput['diagnostics']! as List<Object?>;
      expect(
        (aiDiagnostics.first as Map<Object?, Object?>)['code'],
        'undefined_identifier',
      );
      expect(ai, isNot(contains('documentationUrl')));
      expect(ai, isNot(contains('/private/workspace')));
      final output = json['output']! as Map<String, Object?>;
      final diagnostics = output['diagnostics']! as List<Object?>;
      expect((diagnostics.first as Map<String, Object?>)['severity'], 'error');
      expect(output, isNot(contains('workspaceRoot')));
    });

    test('preserves concise op session and replay receipts', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: const <String, Object?>{
          'operationId': 'operation-1',
          'kind': 'surface.inspect',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'sessionHandle': '1',
          'idempotencyKey': 'cli-operation-1',
          'output': <String, Object?>{'success': true},
        },
        detail: CockpitCliOutputDetail.minimal,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;

      expect(value['session'], '1');
      expect(value['idempotencyKey'], 'cli-operation-1');
    });

    test('renders one exact operation without truncation metadata', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.list',
        data: const <Object?>[
          <String, Object?>{
            'kind': 'viewport.set',
            'title': 'viewport.set',
            'description': 'Cockpit viewport.set operation.',
            'scope': 'workspace',
            'mutationClass': 'mutating',
            'idempotency': 'required',
            'executionMode': 'synchronous',
            'defaultTimeoutMs': 120000,
            'maximumTimeoutMs': 600000,
            'requestSchemaRef': 'cockpit://operations/schema#viewport.set',
            'responseSchemaRef': 'cockpit://operations/schema#result',
            'safetyEffects': <Object?>[],
          },
        ],
        detail: CockpitCliOutputDetail.minimal,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;

      expect(value['kind'], 'viewport.set');
      expect(value['timeoutMs'], 120000);
      expect(value['maxTimeoutMs'], 600000);
      expect(value, isNot(contains('_meta')));
      expect(value, isNot(contains('title')));
      expect(value, isNot(contains('description')));
    });

    test('keeps latest Flutter logs and omits repeated operation identity', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: <String, Object?>{
          'operationId': 'operation-logs',
          'workspaceId': 'workspace-1',
          'kind': 'logs.read',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'output': <String, Object?>{
            'operationId': 'operation-logs',
            'workspaceId': 'workspace-1',
            'appId': 'app-1',
            'source': 'app_snapshot',
            'available': true,
            'lines': <Object?>[
              for (var index = 0; index < 20; index += 1) 'line-$index',
            ],
          },
        },
        detail: CockpitCliOutputDetail.minimal,
      );

      final value = lon.decode(text)! as Map<Object?, Object?>;
      final output = value['output']! as Map<Object?, Object?>;
      final lines = output['lines']! as List<Object?>;

      expect(RegExp('operation-logs').allMatches(text), hasLength(1));
      expect(lines, contains('line-19'));
      expect(lines, isNot(contains('line-0')));
      expect((value['_meta'] as Map<Object?, Object?>)['more'], isTrue);
    });

    test('emits LON without losing operation hierarchy', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: const <String, Object?>{
          'operationId': 'op-1',
          'kind': 'command.run',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'workspaceId': 'workspace-1',
          'output': <String, Object?>{
            'selectedPlane': 'flutterSemanticPlane',
            'recommendedNextStep': 'readPostActionState',
            'command': <String, Object?>{
              'commandId': 'tap-save',
              'commandType': 'tap',
              'success': true,
              'durationMs': 18,
              'locatorResolution': <String, Object?>{
                'matchedKind': 'text',
                'matchedValue': 'Save',
              },
            },
          },
        },
        detail: CockpitCliOutputDetail.standard,
      );

      final value = lon.decode(text)! as Map<Object?, Object?>;
      final output = value['output']! as Map<Object?, Object?>;
      final command = output['command']! as Map<Object?, Object?>;
      final locator = command['locator']! as Map<Object?, Object?>;

      expect(value['operationId'], 'op-1');
      expect(output['plane'], 'flutterSemanticPlane');
      expect(output['next'], 'readPostActionState');
      expect(command['commandId'], 'tap-save');
      expect(command['type'], 'tap');
      expect(command['success'], isTrue);
      expect(command['ms'], 18);
      expect(locator, <Object?, Object?>{
        'matchedKind': 'text',
        'matchedValue': 'Save',
      });
      expect(lon.encode(value), text);
    });

    test('renders errors as canonical LON', () {
      const renderer = CockpitCliOutputRenderer();

      final text = renderer.renderError(
        code: 'operationDenied',
        message: 'Authorization is required.',
        retryable: false,
        responsibleLayer: 'supervisor',
      );

      expect(
        text,
        '{error:{code:operationDenied message:"Authorization is required." retryable:false layer:supervisor}}',
      );
      expect(lon.decode(text), <Object?, Object?>{
        'error': <Object?, Object?>{
          'code': 'operationDenied',
          'message': 'Authorization is required.',
          'retryable': false,
          'layer': 'supervisor',
        },
      });
    });

    test('shortens public fields without rewriting live schema fields', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderJson(
        command: 'explain',
        data: const <String, Object?>{
          'inputContract': <String, Object?>{
            'schemaRef': 'cockpit://operations/schema#example',
            'schema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'maximumTimeoutMs': <String, Object?>{'type': 'integer'},
              },
              'required': <String>['maximumTimeoutMs'],
            },
          },
          'recommendedCommand': 'cockpit dev status',
          'op': "cockpit op run app.status --input '{}'",
        },
        detail: CockpitCliOutputDetail.full,
      );
      final value = jsonDecode(text) as Map<String, Object?>;
      final input = value['input']! as Map<String, Object?>;
      final schema = input['schema']! as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;

      expect(value['devCommand'], 'cockpit dev status');
      expect(value['op'], "cockpit op run app.status --input '{}'");
      expect(input['ref'], 'cockpit://operations/schema#example');
      expect(properties, contains('maximumTimeoutMs'));
      expect(schema['required'], <Object?>['maximumTimeoutMs']);
    });

    test('explain minimal output preserves input enum values', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderJson(
        command: 'explain',
        data: const <String, Object?>{
          'operation': <String, Object?>{
            'kind': 'command.run',
            'scope': 'workspace',
            'mutationClass': 'mutating',
            'idempotency': 'required',
            'executionMode': 'synchronous',
            'timeoutMs': 300000,
            'maximumTimeoutMs': 1800000,
          },
          'inputContract': <String, Object?>{
            'available': true,
            'schemaRef': 'cockpit://operations/schema#command.run',
            'precision': 'structural',
            'schema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'sessionId': <String, Object?>{
                  'type': 'string',
                  'x-cockpit-injected-by': '--session',
                },
                'profile': <String, Object?>{
                  'type': 'string',
                  'enum': <String>[
                    'minimal',
                    'locate',
                    'standard',
                    'inspect',
                    'evidence',
                  ],
                },
              },
              'required': <String>['sessionId'],
              'additionalProperties': false,
            },
          },
          'recommendedCommand': 'cockpit dev tap "Exact text"',
        },
        detail: CockpitCliOutputDetail.minimal,
      );
      final value = jsonDecode(text) as Map<String, Object?>;
      final input = value['input']! as Map<String, Object?>;
      final schema = input['schema']! as Map<String, Object?>;
      final fields = schema['fields']! as Map<String, Object?>;
      final profile = fields['profile']! as Map<String, Object?>;

      expect(profile['values'], 'minimal|locate|standard|inspect|evidence');
      expect(value, isNot(contains('_meta')));
    });
  });

  test('writer persists JSON and emits only its path receipt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-output-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stdout = StringBuffer();
    final destination = File('${directory.path}/nested/result.json');
    final writer = CockpitCliOutputWriter(
      stdoutSink: stdout,
      workingDirectory: directory.path,
    );

    await writer.writeSuccess(
      command: 'run.get',
      data: const <String, Object?>{
        'runId': 'run-1',
        'lifecycle': 'completed',
        'outcome': 'passed',
      },
      selection: CockpitCliOutputSelection(
        format: CockpitCliFormat.json,
        detail: CockpitCliOutputDetail.full,
        outputPath: destination.path,
      ),
    );

    final persisted =
        jsonDecode(await destination.readAsString()) as Map<String, Object?>;
    expect(persisted['runId'], 'run-1');
    final receipt = jsonDecode(stdout.toString()) as Map<String, Object?>;
    expect(receipt, <String, Object?>{'path': destination.path});
  });

  test(
    'writer persists canonical LON and emits only its LON receipt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit-cli-output-lon-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final stdout = StringBuffer();
      final destination = File('${directory.path}/result.lon');
      final writer = CockpitCliOutputWriter(
        stdoutSink: stdout,
        workingDirectory: directory.path,
      );

      await writer.writeSuccess(
        command: 'dev.status',
        data: const <String, Object?>{
          'ok': true,
          'session': '1',
          'state': 'ready',
        },
        selection: CockpitCliOutputSelection(
          detail: CockpitCliOutputDetail.full,
          outputPath: destination.path,
        ),
      );

      final persisted = lon.decode(await destination.readAsString());
      expect(persisted, <Object?, Object?>{
        'ok': true,
        'session': '1',
        'state': 'ready',
      });
      final receipt = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(receipt, <Object?, Object?>{'path': destination.path});
    },
  );

  test('writer persists YAML and emits only its path receipt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-output-yaml-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stdout = StringBuffer();
    final destination = File('${directory.path}/result.yaml');
    final writer = CockpitCliOutputWriter(
      stdoutSink: stdout,
      workingDirectory: directory.path,
    );

    await writer.writeSuccess(
      command: 'dev.status',
      data: const <String, Object?>{'sessionHandle': '1', 'lifecycle': 'ready'},
      selection: CockpitCliOutputSelection(
        format: CockpitCliFormat.yaml,
        detail: CockpitCliOutputDetail.full,
        outputPath: destination.path,
      ),
    );

    final persisted = loadYaml(await destination.readAsString()) as YamlMap;
    expect(persisted['session'], '1');
    final receipt = loadYaml(stdout.toString()) as YamlMap;
    expect(jsonDecode(jsonEncode(receipt)), <String, Object?>{
      'path': destination.path,
    });
  });

  test('path format prints a screenshot artifact without --output', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-screenshot-path-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final screenshot = File('${directory.path}/current.png');
    await screenshot.writeAsBytes(const <int>[1, 2, 3]);
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(stdoutSink: stdout);

    await writer.writeSuccess(
      command: 'dev.screenshot',
      data: <String, Object?>{
        'evidence': <String, Object?>{
          'actual': <String, Object?>{'path': screenshot.path},
        },
      },
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.path),
    );

    expect(stdout.toString().trim(), await screenshot.resolveSymbolicLinks());
  });

  test('path format prints one network body artifact', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-network-path-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final body = File('${directory.path}/response.json');
    await body.writeAsString('{}');
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(stdoutSink: stdout);

    await writer.writeSuccess(
      command: 'dev.network',
      data: <String, Object?>{
        'evidence': <String, Object?>{'response': body.path},
      },
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.path),
    );

    expect(stdout.toString().trim(), await body.resolveSymbolicLinks());
  });

  test(
    'writer rejects inline artifact and file content before output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit-cli-output-artifact-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final destination = File('${directory.path}/result.json');
      final writer = CockpitCliOutputWriter(
        stdoutSink: StringBuffer(),
        workingDirectory: directory.path,
      );

      await expectLater(
        writer.writeSuccess(
          command: 'dev.screenshot',
          data: const <String, Object?>{
            'artifactPayloads': <String, Object?>{
              'screenshot.png': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB',
            },
          },
          selection: CockpitCliOutputSelection(
            format: CockpitCliFormat.json,
            outputPath: destination.path,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('forbidden'), isNot(contains('iVBOR'))),
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
    },
  );

  test('writer keeps stdout silent for output files when requested', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-output-silent-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(
      stdoutSink: stdout,
      workingDirectory: directory.path,
    );

    await writer.writeSuccess(
      command: 'run.get',
      data: const <String, Object?>{'runId': 'run-1'},
      selection: const CockpitCliOutputSelection(
        format: CockpitCliFormat.none,
        detail: CockpitCliOutputDetail.full,
        outputPath: 'result.json',
      ),
    );

    expect(stdout.toString(), isEmpty);
    expect(await File('${directory.path}/result.json').exists(), isTrue);
  });
}
