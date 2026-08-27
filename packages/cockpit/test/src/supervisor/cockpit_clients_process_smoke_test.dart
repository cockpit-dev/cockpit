import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String? _compiledClientExecutable;

void main() {
  test('CLI and MCP use the authenticated Supervisor HTTP boundary', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-clients-smoke-',
    );
    final home = await Directory(p.join(temporary.path, 'home')).create();
    final root = await Directory(p.join(temporary.path, 'projects')).create();
    final workspace = await Directory(p.join(root.path, 'sample')).create();
    await File(p.join(workspace.path, 'pubspec.yaml')).writeAsString('''
name: cockpit_client_smoke
environment:
  sdk: '>=3.8.0 <4.0.0'
''');
    final dartFile = await File(
      p.join(workspace.path, 'lib', 'smoke.dart'),
    ).create(recursive: true);
    await dartFile.writeAsString('int smokeValue() => 2;\n');
    final supportFile = await File(
      p.join(workspace.path, 'test', 'support.dart'),
    ).create(recursive: true);
    await supportFile.writeAsString('''
int expectedSmokeValue() => 2;

void main() => throw StateError('support.dart is not a test suite');
''');
    await File(p.join(workspace.path, 'test', 'smoke_test.dart')).writeAsString(
      '''
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('runs the selected test directory', () {
    expect(expectedSmokeValue(), 2);
  });
}
''',
    );
    await File(p.join(workspace.path, 'smoke_case.yaml')).writeAsString('''
schemaVersion: cockpit.test/v2
kind: case
id: smokeCase
target: {platform: flutter, targetKind: flutterApp, plane: semantic}
steps:
  - stepId: goBack
    action: {type: back}
''');
    final suiteSource = '''
schemaVersion: cockpit.test/v2
kind: suite
id: smokeSuite
execution: {isolation: sharedSession}
cases:
  - id: smokeEntry
    source:
      kind: inline
      case:
        schemaVersion: cockpit.test/v2
        kind: case
        id: suiteSmokeCase
        target: {platform: flutter, targetKind: flutterApp, plane: semantic}
        steps:
          - stepId: goBack
            action: {type: back}
''';
    final suiteFile = await File(
      p.join(workspace.path, 'smoke_suite.yaml'),
    ).writeAsString(suiteSource);
    final packageLibrary = await Isolate.resolvePackageUri(
      Uri.parse('package:cockpit/cockpit.dart'),
    );
    if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
    final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
    final packageConfig = await Isolate.packageConfig;
    if (packageConfig == null) {
      throw StateError('Cannot resolve the test package configuration.');
    }
    final workspaceDartTool = await Directory(
      p.join(workspace.path, '.dart_tool'),
    ).create();
    await File.fromUri(
      packageConfig,
    ).copy(p.join(workspaceDartTool.path, 'package_config.json'));
    final environment = <String, String>{
      ...Platform.environment,
      'COCKPIT_HOME': await home.resolveSymbolicLinks(),
    };
    _compiledClientExecutable = p.join(
      temporary.path,
      Platform.isWindows ? 'cockpit-smoke.exe' : 'cockpit-smoke',
    );
    await _compileClient(packageRoot, _compiledClientExecutable!);
    final authorizationFile =
        await File(p.join(temporary.path, 'authorization.json')).writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 'cockpit.supervisor.authorization/v2',
            'allowedDangerousOperations': <String>['target.launch'],
            'allowedOperationSafetyEffects': <String>['externalSideEffect'],
            'allowedTargetEnvironments': <String>[
              'development',
              'test',
              'staging',
              'production',
            ],
            'allowedSafetyEffects': <String>[],
            'allowedEnvironmentSecretNames': <String>[],
          }),
        );

    addTearDown(() async {
      _compiledClientExecutable = null;
      await _cli(packageRoot, environment, const <String>[
        'daemon',
        'stop',
        '--mode',
        'emergency',
      ], allowFailure: true);
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    final validatedPolicy = await _cli(packageRoot, environment, <String>[
      'daemon',
      'policy',
      'validate',
      '--file',
      authorizationFile.path,
    ]);
    expect(validatedPolicy['targetEnvs'], contains('production'));
    final appliedPolicy = await _cli(packageRoot, environment, <String>[
      'daemon',
      'policy',
      'apply',
      '--file',
      authorizationFile.path,
    ]);
    expect(
      (appliedPolicy['daemon']! as Map<String, Object?>)['running'],
      isFalse,
    );
    final started = await _cli(packageRoot, environment, const <String>[
      'daemon',
      'start',
    ]);
    expect(started['running'], isTrue);
    expect(started['healthy'], isTrue);

    final server = await _cli(packageRoot, environment, const <String>[
      'server',
    ]);
    expect(server['api'], <String, Object?>{'major': 2, 'minor': 0});
    expect(server, isNot(contains('bearerToken')));

    final registeredRoot = await _cli(packageRoot, environment, <String>[
      'root',
      'add',
      '--path',
      root.path,
    ]);
    final rootId = registeredRoot['root']! as String;
    final registeredWorkspace = await _cli(packageRoot, environment, <String>[
      'workspace',
      'register',
      '--root-id',
      rootId,
      '--path',
      workspace.path,
    ]);
    final workspaceId = registeredWorkspace['workspace']! as String;
    final explained = await _cli(packageRoot, environment, <String>[
      'explain',
      'viewport.set',
      '--workspace-id',
      workspaceId,
    ]);
    final explainedOperation = explained['operation']! as Map<String, Object?>;
    expect(explainedOperation['title'], 'Set viewport');
    final inputContract = explained['input']! as Map<String, Object?>;
    final inputSchema = inputContract['schema']! as Map<String, Object?>;
    expect(
      inputSchema['properties']! as Map<String, Object?>,
      containsPair('width', isA<Map<String, Object?>>()),
    );

    final registeredTarget = await _cli(packageRoot, environment, <String>[
      'target',
      'register',
      '--workspace-id',
      workspaceId,
      '--platform',
      'android',
      '--device-id',
      'smoke-device',
      '--target-kind',
      'nativeApp',
      '--environment',
      'test',
      '--app-id',
      'com.example.smoke',
      '--idempotency-key',
      'smoke-target-register',
    ]);
    expect(
      registeredTarget['outcome'],
      'succeeded',
      reason: '$registeredTarget',
    );
    final targetId = registeredTarget['output']! as Map<String, Object?>;
    final registeredTargetId = targetId['target']! as String;
    final targets = await _cli(packageRoot, environment, <String>[
      'target',
      'list',
      '--workspace-id',
      workspaceId,
    ]);
    expect(
      (targets['items']! as List<Object?>).cast<Map<String, Object?>>().map(
        (target) => target['target'],
      ),
      contains(registeredTargetId),
    );
    final target = await _cli(packageRoot, environment, <String>[
      'target',
      'get',
      '--workspace-id',
      workspaceId,
      '--target-id',
      registeredTargetId,
    ]);
    expect(target['app'], 'com.example.smoke');
    final discovery =
        jsonDecode(await File(p.join(home.path, 'daemon.json')).readAsString())
            as Map<String, Object?>;
    final http = HttpClient();
    try {
      final request = await http.getUrl(
        Uri.parse(
          discovery['endpoint']! as String,
        ).resolve('/api/v2/workspaces/$workspaceId/targets/target_missing'),
      );
      request.headers
        ..set(
          HttpHeaders.authorizationHeader,
          'Bearer ${discovery['bearerToken']}',
        )
        ..set('Cockpit-API-Version', '2.0');
      final response = await request.close();
      final body =
          jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, Object?>;
      expect(response.statusCode, HttpStatus.notFound, reason: '$body');
      expect(
        (body['error']! as Map<String, Object?>)['code'],
        'opaqueReferenceNotFound',
      );
    } finally {
      http.close(force: true);
    }

    final cases = await _cli(packageRoot, environment, <String>[
      'case',
      'list',
      '--workspace-id',
      workspaceId,
    ]);
    expect(
      (cases['items']! as List<Object?>).cast<Map<String, Object?>>().map(
        (item) => item['case'],
      ),
      contains('smokeCase'),
    );

    final suites = await _cli(packageRoot, environment, <String>[
      'suite',
      'list',
      '--workspace-id',
      workspaceId,
    ]);
    expect(
      (suites['items']! as List<Object?>).cast<Map<String, Object?>>().map(
        (item) => item['id'],
      ),
      contains('smokeSuite'),
    );
    final validatedSuite = await _cli(packageRoot, environment, <String>[
      'suite',
      'validate',
      '--workspace-id',
      workspaceId,
      '--file',
      suiteFile.path,
    ]);
    expect(validatedSuite['valid'], isTrue);
    final acceptedSuite = await _cli(packageRoot, environment, <String>[
      'suite',
      'run',
      '--workspace-id',
      workspaceId,
      '--suite-id',
      'smokeSuite',
      '--idempotency-key',
      'smoke-suite-run',
    ]);
    final suiteRunId = acceptedSuite['run']! as String;
    expect(suiteRunId, matches(RegExp(r'^r[0-9a-z]{10}$')));
    final suiteRun = await _waitForCompletedRun(
      packageRoot,
      environment,
      suiteRunId,
    );
    expect(suiteRun['docType'], 'suite');
    final reportDirectory = p.join(temporary.path, 'cockpit-report');
    final reportReceipt = await _cli(packageRoot, environment, <String>[
      'suite',
      'report',
      '--run-id',
      suiteRunId,
      '--output-dir',
      reportDirectory,
    ]);
    expect(reportReceipt, <String, Object?>{'path': reportDirectory});
    final reportManifest =
        jsonDecode(
              await File(
                p.join(reportDirectory, 'manifest.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    expect(reportManifest['runId'], suiteRunId);
    final reportFiles = (reportManifest['files']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((file) => file['relativePath']);
    expect(
      reportFiles,
      containsAll(<String>[
        'report.json',
        'index.html',
        'summary.md',
        'junit.xml',
        'run/events.jsonl',
      ]),
    );

    final inlineSuite = await _cli(packageRoot, environment, <String>[
      'suite',
      'run',
      '--workspace-id',
      workspaceId,
      '--file',
      suiteFile.path,
      '--idempotency-key',
      'smoke-suite-inline',
    ]);
    expect(inlineSuite['run'], matches(RegExp(r'^r[0-9a-z]{10}$')));

    final accepted = await _cli(packageRoot, environment, <String>[
      'case',
      'run',
      '--workspace-id',
      workspaceId,
      '--case-id',
      'smokeCase',
      '--idempotency-key',
      'smoke-case-run',
    ]);
    final runId = accepted['run']! as String;
    expect(runId, matches(RegExp(r'^r[0-9a-z]{10}$')));
    final run = await _cli(packageRoot, environment, <String>[
      'run',
      'get',
      '--run-id',
      runId,
    ]);
    expect(run['run'], runId);

    final inlineCase = await _cli(packageRoot, environment, <String>[
      'case',
      'run',
      '--workspace-id',
      workspaceId,
      '--file',
      p.join(workspace.path, 'smoke_case.yaml'),
      '--idempotency-key',
      'smoke-case-inline',
    ]);
    expect(inlineCase['run'], matches(RegExp(r'^r[0-9a-z]{10}$')));

    final events = await _cli(packageRoot, environment, <String>[
      'run',
      'events',
      '--run-id',
      runId,
      '--after-sequence',
      '0',
      '--max-events',
      '1',
    ]);
    expect(events['items'], isNotEmpty);

    final cancellation = await _cli(packageRoot, environment, <String>[
      'run',
      'cancel',
      '--run-id',
      runId,
      '--idempotency-key',
      'smoke-case-cancel',
    ]);
    expect(cancellation['run'], runId);
    final listedArtifacts = await _cli(packageRoot, environment, <String>[
      'artifact',
      'list',
      '--run-id',
      runId,
    ]);
    expect(listedArtifacts['items'], isA<List<Object?>>());

    final mcp = await _mcp(
      packageRoot,
      environment,
      runId: runId,
      workspaceId: workspaceId,
      targetId: registeredTargetId,
      suiteSource: suiteSource,
      dartFilePath: await dartFile.resolveSymbolicLinks(),
      testDirectoryPath: await Directory(
        p.join(workspace.path, 'test'),
      ).resolveSymbolicLinks(),
    );
    Map<String, Object?> response(int id) =>
        mcp.singleWhere((message) => message['id'] == id);
    expect(response(1)['result'], isA<Map<String, Object?>>());
    final resource = response(2)['result']! as Map<String, Object?>;
    final contents = (resource['contents']! as List<Object?>).single;
    final resourceJson =
        jsonDecode((contents as Map<String, Object?>)['text']! as String)
            as Map<String, Object?>;
    expect(resourceJson['instanceId'], server['instanceId']);
    final tool = response(3)['result']! as Map<String, Object?>;
    expect(
      (tool['structuredContent']! as Map<String, Object?>)['runId'],
      runId,
    );
    final suiteResource = response(4)['result']! as Map<String, Object?>;
    final suiteContents = (suiteResource['contents']! as List<Object?>).single;
    final suitesJson =
        jsonDecode((suiteContents as Map<String, Object?>)['text']! as String)
            as Map<String, Object?>;
    expect(
      (suitesJson['items']! as List<Object?>).cast<Map<String, Object?>>().map(
        (item) => item['authoredId'],
      ),
      contains('smokeSuite'),
    );
    final suiteValidation = response(5)['result']! as Map<String, Object?>;
    expect(
      (suiteValidation['structuredContent']! as Map<String, Object?>)['valid'],
      isTrue,
    );
    final targetsResource = response(6)['result']! as Map<String, Object?>;
    final targetsContents =
        (targetsResource['contents']! as List<Object?>).single;
    final targetsJson =
        jsonDecode((targetsContents as Map<String, Object?>)['text']! as String)
            as Map<String, Object?>;
    expect(
      (targetsJson['items']! as List<Object?>).cast<Map<String, Object?>>().map(
        (target) => target['targetId'],
      ),
      contains(registeredTargetId),
    );
    final targetResource = response(7)['result']! as Map<String, Object?>;
    final targetContents =
        (targetResource['contents']! as List<Object?>).single;
    final targetJson =
        jsonDecode((targetContents as Map<String, Object?>)['text']! as String)
            as Map<String, Object?>;
    expect(targetJson['targetId'], registeredTargetId);
    final targetTool = response(8)['result']! as Map<String, Object?>;
    expect(
      (targetTool['structuredContent']! as Map<String, Object?>)['targetId'],
      registeredTargetId,
    );
    final artifactResource = response(9)['result']! as Map<String, Object?>;
    final artifactContents =
        (artifactResource['contents']! as List<Object?>).single;
    final artifactResourceJson =
        jsonDecode(
              (artifactContents as Map<String, Object?>)['text']! as String,
            )
            as Map<String, Object?>;
    expect(artifactResourceJson['items'], isA<List<Object?>>());
    final artifactTool = response(10)['result']! as Map<String, Object?>;
    expect(
      (artifactTool['structuredContent']! as Map<String, Object?>)['items'],
      isA<List<Object?>>(),
    );
    final toolsResult = response(11)['result']! as Map<String, Object?>;
    final toolNames = (toolsResult['tools']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((tool) => tool['name']);
    expect(toolNames, contains('analyze_files'));
    final analysisTool = response(12)['result']! as Map<String, Object?>;
    expect(
      (analysisTool['structuredContent']! as Map<String, Object?>)['outcome'],
      'succeeded',
    );
    final testTool = response(13)['result']! as Map<String, Object?>;
    final testStructured =
        testTool['structuredContent']! as Map<String, Object?>;
    expect(testStructured['outcome'], 'succeeded', reason: '$testTool');
    final testOutput = testStructured['output']! as Map<String, Object?>;
    final testCommand = testOutput['command']! as Map<String, Object?>;
    expect(testCommand['arguments'], <Object?>['test', 'test']);
    final schemaResource = response(14)['result']! as Map<String, Object?>;
    final schemaContents =
        (schemaResource['contents']! as List<Object?>).single;
    final schemaJson =
        jsonDecode((schemaContents as Map<String, Object?>)['text']! as String)
            as Map<String, Object?>;
    expect(schemaJson[r'$id'], 'cockpit://operations/schema');
    expect(
      schemaJson[r'$defs']! as Map<String, Object?>,
      contains('viewport.set.request'),
    );

    final workspaceRetirement = await _cli(packageRoot, environment, <String>[
      'workspace',
      'unregister',
      '--workspace-id',
      workspaceId,
      '--force',
    ]);
    expect(workspaceRetirement['id'], workspaceId);
    expect(workspaceRetirement['refs'], isA<Map<String, Object?>>());
    final rootRetirement = await _cli(packageRoot, environment, <String>[
      'root',
      'remove',
      '--root-id',
      rootId,
      '--force',
    ]);
    expect(rootRetirement['id'], rootId);
    expect(rootRetirement['refs'], isA<Map<String, Object?>>());
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<Map<String, Object?>> _waitForCompletedRun(
  String packageRoot,
  Map<String, String> environment,
  String runId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final run = await _cli(packageRoot, environment, <String>[
      'run',
      'get',
      '--run-id',
      runId,
    ]);
    if (run['lifecycle'] == 'completed') return run;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Suite run $runId did not complete.');
}

Future<Map<String, Object?>> _cli(
  String packageRoot,
  Map<String, String> environment,
  List<String> arguments, {
  bool allowFailure = false,
}) async {
  final executable = _compiledClientExecutable;
  final result = await Process.run(
    executable ?? Platform.resolvedExecutable,
    <String>[
      if (executable == null) p.join(packageRoot, 'bin', 'cockpit.dart'),
      ...arguments,
      '--format',
      'json',
      '--view',
      'full',
    ],
    workingDirectory: packageRoot,
    environment: environment,
  ).timeout(const Duration(seconds: 45));
  if (allowFailure && result.exitCode != 0) return const <String, Object?>{};
  expect(
    result.exitCode,
    0,
    reason: 'cockpit ${arguments.join(' ')}\n${result.stderr}',
  );
  return Map<String, Object?>.from(
    jsonDecode('${result.stdout}'.trim()) as Map<Object?, Object?>,
  );
}

Future<List<Map<String, Object?>>> _mcp(
  String packageRoot,
  Map<String, String> environment, {
  required String runId,
  required String workspaceId,
  required String targetId,
  required String suiteSource,
  required String dartFilePath,
  required String testDirectoryPath,
}) async {
  final executable = _compiledClientExecutable;
  final process = await Process.start(
    executable ?? Platform.resolvedExecutable,
    <String>[
      if (executable == null) p.join(packageRoot, 'bin', 'cockpit.dart'),
      'serve-mcp',
      '--profile',
      'dart',
    ],
    workingDirectory: packageRoot,
    environment: environment,
  );
  final output = <int>[];
  final errors = StringBuffer();
  final initialized = Completer<void>();
  final responsesReceived = Completer<void>();
  var responseLines = 0;
  final outputDone = process.stdout.listen((chunk) {
    output.addAll(chunk);
    responseLines += chunk.where((byte) => byte == 0x0a).length;
    if (responseLines >= 1 && !initialized.isCompleted) initialized.complete();
    if (responseLines >= 14 && !responsesReceived.isCompleted) {
      responsesReceived.complete();
    }
  }).asFuture<void>();
  final errorDone = process.stderr
      .transform(utf8.decoder)
      .listen(errors.write)
      .asFuture<void>();
  process.stdin.add(
    _encodeLine(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{
        'protocolVersion': '2025-11-05',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'cockpit-smoke',
          'version': '2.0.0',
        },
      },
    }),
  );
  await initialized.future.timeout(const Duration(seconds: 10));
  for (final message in <Map<String, Object?>>[
    <String, Object?>{'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'resources/read',
      'params': <String, Object?>{'uri': 'cockpit://server'},
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'run_get',
        'arguments': <String, Object?>{'runId': runId},
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'resources/read',
      'params': <String, Object?>{
        'uri': 'cockpit://workspaces/$workspaceId/suites',
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 5,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'suite_validate',
        'arguments': <String, Object?>{
          'workspaceId': workspaceId,
          'format': 'yaml',
          'sourceText': suiteSource,
          'relativePath': 'smoke_suite.yaml',
        },
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 6,
      'method': 'resources/read',
      'params': <String, Object?>{
        'uri': 'cockpit://workspaces/$workspaceId/targets',
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'resources/read',
      'params': <String, Object?>{
        'uri': 'cockpit://workspaces/$workspaceId/targets/$targetId',
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 8,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'target_get',
        'arguments': <String, Object?>{
          'workspaceId': workspaceId,
          'targetId': targetId,
        },
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 9,
      'method': 'resources/read',
      'params': <String, Object?>{'uri': 'cockpit://runs/$runId/artifacts'},
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 10,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'artifact_list',
        'arguments': <String, Object?>{'runId': runId},
      },
    },
    <String, Object?>{'jsonrpc': '2.0', 'id': 11, 'method': 'tools/list'},
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 12,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'analyze_files',
        'arguments': <String, Object?>{
          'workspaceId': workspaceId,
          'paths': <String>[dartFilePath],
        },
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 13,
      'method': 'tools/call',
      'params': <String, Object?>{
        'name': 'run_tests',
        'arguments': <String, Object?>{
          'workspaceId': workspaceId,
          'paths': <String>[testDirectoryPath],
          'idempotencyKey': 'mcp-run-tests-directory',
        },
      },
    },
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': 14,
      'method': 'resources/read',
      'params': <String, Object?>{'uri': 'cockpit://operations/schema'},
    },
  ]) {
    process.stdin.add(_encodeLine(message));
  }
  await responsesReceived.future.timeout(const Duration(seconds: 30));
  await process.stdin.close();
  final exitCode = await process.exitCode.timeout(const Duration(seconds: 30));
  await Future.wait(<Future<void>>[outputDone, errorDone]);
  expect(exitCode, 0, reason: errors.toString());
  final responses = _decodeLines(output);
  expect(responses, hasLength(14), reason: errors.toString());
  return responses;
}

Future<void> _compileClient(String packageRoot, String outputPath) async {
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'compile',
    'exe',
    p.join(packageRoot, 'bin', 'cockpit.dart'),
    '-o',
    outputPath,
  ], workingDirectory: packageRoot).timeout(const Duration(minutes: 2));
  expect(
    result.exitCode,
    0,
    reason: 'dart compile exe failed:\n${result.stderr}',
  );
}

List<int> _encodeLine(Map<String, Object?> message) =>
    utf8.encode('${jsonEncode(message)}\n');

List<Map<String, Object?>> _decodeLines(List<int> bytes) => const LineSplitter()
    .convert(utf8.decode(bytes))
    .where((line) => line.trim().isNotEmpty)
    .map(
      (line) =>
          Map<String, Object?>.from(jsonDecode(line) as Map<Object?, Object?>),
    )
    .toList(growable: false);
