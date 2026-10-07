import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_session_handles.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:cockpit/src/cli/cockpit_dev_runtime.dart';
import 'package:cockpit/src/cli/cockpit_record_runtime.dart';
import 'package:cockpit/src/development/cockpit_checkout_identity.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late _RecorderAppServer app;
  late Directory workingDirectory;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    app = await _RecorderAppServer.start();
    workingDirectory = await Directory.systemTemp.createTemp(
      'cockpit-record-commands-',
    );
    stdout = StringBuffer();
    stderr = StringBuffer();
    addTearDown(() async {
      await app.close();
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
    });
  });

  CockpitCommandRunner runner() => CockpitCommandRunner(
    runtime: CockpitCliRuntime(
      workingDirectory: workingDirectory.path,
      stdoutSink: stdout,
      stderrSink: stderr,
      clientProvider: () async => throw StateError(
        'record endpoint tests must not connect to the Supervisor.',
      ),
    ),
  );

  Future<(int, Map<String, Object?>)> runRecord(List<String> arguments) async {
    stdout.clear();
    stderr.clear();
    final exitCode = await runner().run(<String>[
      'record',
      ...arguments,
      '--endpoint',
      app.endpoint.toString(),
      '--format',
      'json',
      '--view',
      'full',
    ]);
    final decoded = jsonDecode(stdout.toString().trim());
    expect(decoded, isA<Map<Object?, Object?>>());
    return (exitCode, Map<String, Object?>.from(decoded));
  }

  Future<(int, Map<String, Object?>)> runRecordFailure(
    List<String> arguments,
  ) async {
    stdout.clear();
    stderr.clear();
    final exitCode = await runner().run(<String>[
      'record',
      ...arguments,
      '--endpoint',
      app.endpoint.toString(),
      '--format',
      'json',
      '--view',
      'full',
    ]);
    final decoded = jsonDecode(stderr.toString().trim());
    expect(decoded, isA<Map<Object?, Object?>>());
    return (exitCode, decoded['error']! as Map<String, Object?>);
  }

  test('record exposes the interaction recorder command surface', () {
    final record = runner().commands['record'];

    expect(record, isNotNull);
    expect(
      record!.subcommands.keys,
      containsAll(const <String>[
        'start',
        'pause',
        'resume',
        'stop',
        'status',
        'steps',
        'export',
      ]),
    );
    for (final leaf in record.subcommands.values) {
      expect(
        leaf.argParser.options.keys,
        containsAll(const <String>['session', 'endpoint']),
      );
    }
    expect(
      record.subcommands['start']!.argParser.options.keys,
      contains('name'),
    );
    expect(
      record.subcommands['steps']!.argParser.options['after']!.defaultsTo,
      '0',
    );
    final exportOptions = record.subcommands['export']!.argParser.options;
    expect(exportOptions.keys, contains('out'));
    expect(exportOptions['output-format']!.allowed, const <String>[
      'yaml',
      'json',
    ]);
    expect(exportOptions['output-format']!.defaultsTo, 'yaml');
    expect(
      record.subcommands['start']!.usage,
      contains('cockpit record start'),
    );
  });

  test('record leaves drive a live recorder endpoint', () async {
    final (startExit, started) = await runRecord(const <String>[
      'start',
      '--name',
      'checkout flow',
    ]);
    expect(startExit, cockpitSuccessExitCode);
    expect(started['runtime'], 'r1');
    expect(started['phase'], 'recording');
    expect(app.startBodies.single, <String, Object?>{'name': 'checkout flow'});

    final (pauseExit, paused) = await runRecord(const <String>['pause']);
    expect(pauseExit, cockpitSuccessExitCode);
    expect(paused['phase'], 'paused');

    final (resumeExit, resumed) = await runRecord(const <String>['resume']);
    expect(resumeExit, cockpitSuccessExitCode);
    expect(resumed['phase'], 'recording');

    final (statusExit, status) = await runRecord(const <String>['status']);
    expect(statusExit, cockpitSuccessExitCode);
    expect(status['runtime'], 'r1');
    expect(status['stepCount'], _RecorderAppServer.stepCount);

    final (stepsExit, page) = await runRecord(const <String>[
      'steps',
      '--after',
      '1',
    ]);
    expect(stepsExit, cockpitSuccessExitCode);
    expect(page['total'], _RecorderAppServer.stepCount);
    expect(
      (page['steps']! as List<Object?>).map(
        (step) => (step as Map<String, Object?>)['stepId'],
      ),
      const <String>['s2'],
    );

    final (stopExit, stopped) = await runRecord(const <String>['stop']);
    expect(stopExit, cockpitSuccessExitCode);
    expect((stopped['session']! as Map<String, Object?>)['phase'], 'stopped');
    expect(stopped['steps'], hasLength(_RecorderAppServer.stepCount));
  });

  test(
    'record export prints the document or writes the requested file',
    () async {
      final (yamlExit, document) = await runRecord(const <String>['export']);
      expect(yamlExit, cockpitSuccessExitCode);
      expect(document['format'], 'yaml');
      expect(document['document'], _RecorderAppServer.caseYaml);

      final (outExit, receipt) = await runRecord(const <String>[
        'export',
        '--out',
        'flow.yaml',
      ]);
      final yamlPath = p.join(workingDirectory.path, 'flow.yaml');
      expect(outExit, cockpitSuccessExitCode);
      expect(receipt, <String, Object?>{'format': 'yaml', 'path': yamlPath});
      expect(
        File(yamlPath).readAsStringSync(),
        '${_RecorderAppServer.caseYaml}\n',
      );

      final (jsonExit, jsonReceipt) = await runRecord(const <String>[
        'export',
        '--out',
        'flow.json',
        '--output-format',
        'json',
      ]);
      final jsonPath = p.join(workingDirectory.path, 'flow.json');
      expect(jsonExit, cockpitSuccessExitCode);
      expect(jsonReceipt, <String, Object?>{
        'format': 'json',
        'path': jsonPath,
      });
      expect(
        jsonDecode(File(jsonPath).readAsStringSync()),
        isA<Map<Object?, Object?>>(),
      );
    },
  );

  test('record leaves expose only their own options', () {
    final record = runner().commands['record']!;
    final leaves = record.subcommands;

    expect(record.description, contains('Record in-app interactions'));
    for (final leaf in leaves.values) {
      expect(leaf.description, isNotEmpty, reason: leaf.name);
      expect(
        leaf.argParser.options.keys,
        containsAll(const <String>['format', 'view', 'timeout']),
        reason: leaf.name,
      );
    }
    for (final name in const <String>[
      'pause',
      'resume',
      'stop',
      'status',
      'steps',
      'export',
    ]) {
      expect(
        leaves[name]!.argParser.options,
        isNot(contains('name')),
        reason: name,
      );
    }
    for (final name in const <String>[
      'start',
      'pause',
      'resume',
      'stop',
      'status',
    ]) {
      expect(leaves[name]!.argParser.options, isNot(contains('out')));
      expect(leaves[name]!.argParser.options, isNot(contains('output-format')));
      expect(leaves[name]!.argParser.options, isNot(contains('after')));
    }
  });

  test('record rejects an unknown output format before any request', () async {
    stderr.clear();
    final exitCode = await runner().run(<String>[
      'record',
      'export',
      '--endpoint',
      app.endpoint.toString(),
      '--output-format',
      'markdown',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitUsageExitCode);
    expect(stderr.toString(), contains('output-format'));
    expect(app.startBodies, isEmpty);
  });

  test('record steps surfaces the cursor-beyond-total 400 envelope', () async {
    final (exitCode, failure) = await runRecordFailure(const <String>[
      'steps',
      '--after',
      '${_RecorderAppServer.stepCount + 1}',
    ]);

    expect(exitCode, cockpitDataExitCode);
    expect(failure['code'], 'invalidPayload');
    expect(
      failure['message'],
      contains('must not exceed the recorded step count'),
    );
  });

  test('record export overwrites an existing file', () async {
    final stale = File(p.join(workingDirectory.path, 'flow.yaml'));
    await stale.writeAsString('stale content that must disappear');

    final (exitCode, receipt) = await runRecord(const <String>[
      'export',
      '--out',
      'flow.yaml',
    ]);

    expect(exitCode, cockpitSuccessExitCode);
    expect(receipt['path'], stale.path);
    expect(stale.readAsStringSync(), '${_RecorderAppServer.caseYaml}\n');
  });

  test('record export writes into a not-yet-existing directory', () async {
    final (exitCode, receipt) = await runRecord(const <String>[
      'export',
      '--out',
      'reports/nested/flow.yaml',
    ]);

    expect(exitCode, cockpitSuccessExitCode);
    final written = File(
      p.join(workingDirectory.path, 'reports/nested/flow.yaml'),
    );
    expect(receipt['path'], written.path);
    expect(written.existsSync(), isTrue);
    expect(written.readAsStringSync(), '${_RecorderAppServer.caseYaml}\n');
  });

  test('record pause from idle surfaces the server error envelope', () async {
    app.idle = true;
    final (exitCode, failure) = await runRecordFailure(const <String>['pause']);

    expect(exitCode, cockpitDataExitCode);
    expect(failure['code'], 'serverError');
    expect(failure['message'], contains('Cannot pause'));
    expect(failure['retry'], isFalse);
  });

  test('record status prints the idle payload as-is', () async {
    app.idle = true;
    final (exitCode, status) = await runRecord(const <String>['status']);

    expect(exitCode, cockpitSuccessExitCode);
    // The concise key renaming (sessionId -> runtime) has nothing to rename:
    // the idle answer must reach stdout untouched.
    expect(status, <String, Object?>{'phase': 'idle'});
  });

  test('record surfaces a slow endpoint as a retryable timeout', () async {
    app.delay = const Duration(milliseconds: 600);
    stdout.clear();
    stderr.clear();
    final exitCode = await runner().run(<String>[
      'record',
      'status',
      '--endpoint',
      app.endpoint.toString(),
      '--timeout',
      '50ms',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitTemporaryExitCode);
    final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
    final failure = error['error']! as Map<String, Object?>;
    expect(failure['retry'], isTrue);
    expect(failure['code'], anyOf('timeout', 'remoteUnavailable'));
  });

  test(
    'record runtime reports a failed session query through the operation envelope',
    () async {
      final fixtures = await _SessionFixtures.create(lifecycle: 'connecting');
      addTearDown(fixtures.dispose);
      final queries = <int>[];
      final dev = CockpitDevRuntime(
        fixtures.runtime,
        operationInvoker: (_, kind, _) async {
          expect(kind, 'session.development.get');
          queries.add(queries.length);
          // The reconciling query proves the session ready; the read query
          // the recorder runtime issues afterwards fails.
          return queries.length == 1
              ? _operationResult(_readyOutput(app.endpoint))
              : _failedOperationResult();
        },
      );
      fixtures.runtime.configureOutput(
        command: 'record.status',
        selection: const CockpitCliOutputSelection(
          format: CockpitCliFormat.json,
          view: CockpitCliOutputView.full,
        ),
      );

      final (service, exitCode) = await CockpitRecordRuntime(
        fixtures.runtime,
        dev,
      ).resolve(action: 'record.status', session: null, endpoint: null);

      expect(service, isNull);
      expect(exitCode, cockpitDataExitCode);
      expect(queries, hasLength(2));
      // The failed operation surfaces through the standard operation
      // envelope: its primary error and the diagnose follow-up.
      final envelope =
          jsonDecode(fixtures.stdout.toString()) as Map<String, Object?>;
      expect(envelope['action'], 'record.status');
      final errors = envelope['errors']! as List<Object?>;
      final primary =
          (errors.single as Map<String, Object?>)['primary']!
              as Map<String, Object?>;
      expect(primary['code'], 'developmentSessionUnavailable');
      expect(envelope['next'], contains('cockpit dev diagnose'));
    },
  );

  test('record runtime relays the session bridge token to the app', () async {
    final fixtures = await _SessionFixtures.create(authenticationEnabled: true);
    addTearDown(fixtures.dispose);
    final dev = CockpitDevRuntime(
      fixtures.runtime,
      operationInvoker: (_, kind, _) async {
        expect(kind, 'session.development.get');
        return _operationResult(_readyOutput(app.endpoint));
      },
    );

    final (service, exitCode) = await CockpitRecordRuntime(
      fixtures.runtime,
      dev,
    ).resolve(action: 'record.start', session: null, endpoint: null);

    expect(exitCode, cockpitSuccessExitCode);
    await service!.start(name: 'auth flow');
    expect(app.startBodies.single, <String, Object?>{'name': 'auth flow'});
    expect(app.authTokens, const <String>['bridge-token-1']);
  });

  test('record reports an unreachable endpoint as retryable', () async {
    final deadPort = await _reservedThenClosedPort();
    final exitCode = await runner().run(<String>[
      'record',
      'status',
      '--endpoint',
      'http://127.0.0.1:$deadPort',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitTemporaryExitCode);
    final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
    final failure = error['error']! as Map<String, Object?>;
    expect(failure['code'], 'remoteUnavailable');
    expect(failure['retry'], isTrue);
  });

  test('record rejects invalid arguments before resolving a session', () async {
    Future<Map<String, Object?>> runFailure(List<String> arguments) async {
      stderr.clear();
      final exitCode = await runner().run(<String>[
        'record',
        ...arguments,
        '--format',
        'json',
      ]);
      expect(exitCode, cockpitDataExitCode);
      final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
      return error['error']! as Map<String, Object?>;
    }

    expect(
      (await runFailure(const <String>['steps', '--after', 'x']))['code'],
      'invalidInput',
    );
    expect(
      (await runFailure(const <String>['steps', '--after', '-1']))['code'],
      'invalidInput',
    );
    expect(
      (await runFailure(const <String>[
        'status',
        '--endpoint',
        'ftp://app',
      ]))['code'],
      'invalidInput',
    );
    expect(
      await runFailure(const <String>['status', '--endpoint', 'ftp://app']),
      containsPair('message', contains('absolute http(s) URL')),
    );
  });

  test(
    'record runtime resolves the live bridge through the dev session',
    () async {
      final fixtures = await _SessionFixtures.create();
      addTearDown(fixtures.dispose);
      final calls = <String>[];
      final dev = CockpitDevRuntime(
        fixtures.runtime,
        operationInvoker: (_, kind, _) async {
          calls.add(kind);
          expect(kind, 'session.development.get');
          return _operationResult(<String, Object?>{
            'sessionId': 'session-1',
            'targetId': 'target-1',
            'appId': 'app-1',
            'status': <String, Object?>{
              'state': 'ready',
              'appReachable': true,
              'remoteSessionReachable': true,
            },
            'runtime': <String, Object?>{
              'bridge': <String, Object?>{'baseUrl': app.endpoint.toString()},
            },
          });
        },
      );
      fixtures.runtime.configureOutput(
        command: 'record.status',
        selection: const CockpitCliOutputSelection(
          format: CockpitCliFormat.json,
          view: CockpitCliOutputView.full,
        ),
      );

      final (service, exitCode) = await CockpitRecordRuntime(
        fixtures.runtime,
        dev,
      ).resolve(action: 'record.status', session: null, endpoint: null);

      expect(exitCode, cockpitSuccessExitCode);
      expect(service, isNotNull);
      expect(await service!.status(), containsPair('sessionId', 'r1'));
      expect(calls, const <String>['session.development.get']);
    },
  );

  test(
    'record runtime reports a not-ready session instead of a service',
    () async {
      final fixtures = await _SessionFixtures.create();
      addTearDown(fixtures.dispose);
      final queries = <String>[];
      final dev = CockpitDevRuntime(
        fixtures.runtime,
        operationInvoker: (_, kind, _) async {
          queries.add(kind);
          if (queries.length == 1) {
            // The first read fails, so resolution reconciles through the
            // supervisor before deciding availability.
            return _operationResult(const <String, Object?>{'ok': false});
          }
          return _operationResult(<String, Object?>{
            'sessionId': 'session-1',
            'targetId': 'target-1',
            'appId': 'app-1',
            'status': <String, Object?>{
              'state': 'connecting',
              'appReachable': true,
              'remoteSessionReachable': false,
            },
          });
        },
      );
      fixtures.runtime.configureOutput(
        command: 'record.status',
        selection: const CockpitCliOutputSelection(
          format: CockpitCliFormat.json,
          view: CockpitCliOutputView.full,
        ),
      );

      final (service, exitCode) = await CockpitRecordRuntime(
        fixtures.runtime,
        dev,
      ).resolve(action: 'record.status', session: null, endpoint: null);

      expect(service, isNull);
      expect(exitCode, cockpitTemporaryExitCode);
      expect(queries, const <String>[
        'session.development.get',
        'session.development.get',
      ]);
      expect(
        fixtures.stdout.toString(),
        contains('developmentSessionReconnecting'),
      );
    },
  );
}

const String _caseYaml = 'schemaVersion: cockpit.test/v2\nid: recorded-r1\n';

/// Serves the remote recorder routes of one live app behind a loopback port.
final class _RecorderAppServer {
  _RecorderAppServer._(this._server);

  static const int stepCount = 2;

  final HttpServer _server;
  final List<Map<String, Object?>> startBodies = <Map<String, Object?>>[];
  final List<String> authTokens = <String>[];

  /// While true the app mirrors a cold app: no session yet and lifecycle
  /// operations answer the server error the engine would raise.
  bool idle = false;

  /// Extra delay before answering, to exercise command timeouts.
  Duration delay = Duration.zero;

  static String get caseYaml => _caseYaml;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_RecorderAppServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final app = _RecorderAppServer._(server);
    server.listen(app._handle);
    return app;
  }

  Future<void> close() => _server.close(force: true);

  void _handle(HttpRequest request) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final token = request.headers.value('x-cockpit-token');
    if (token != null) {
      authTokens.add(token);
    }
    request.response.headers.contentType = ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('POST', '/recorder/start'):
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        startBodies.add(
          Map<String, Object?>.from(body as Map<Object?, Object?>),
        );
        request.response.write(jsonEncode(_session('recording')));
      case ('POST', '/recorder/pause'):
        if (idle) {
          _writeError(request.response, HttpStatus.internalServerError, {
            'error': 'serverError',
            'message':
                'Bad state: Cannot pause while the interaction recording is '
                'idle.',
          });
          await request.response.close();
          return;
        }
        request.response.write(jsonEncode(_session('paused')));
      case ('POST', '/recorder/resume'):
        request.response.write(jsonEncode(_session('recording')));
      case ('POST', '/recorder/stop'):
        request.response.write(
          jsonEncode(<String, Object?>{
            'session': _session('stopped'),
            'steps': _steps,
          }),
        );
      case ('GET', '/recorder/session'):
        request.response.write(
          jsonEncode(
            idle ? <String, Object?>{'phase': 'idle'} : _session('recording'),
          ),
        );
      case ('GET', '/recorder/steps'):
        final after = int.parse(request.uri.queryParameters['after'] ?? '0');
        if (after > stepCount) {
          // Mirrors the real app: a cursor beyond the recorded total is a
          // client error, not an empty page.
          _writeError(request.response, HttpStatus.badRequest, {
            'error': 'invalidPayload',
            'message':
                'Query parameter "after" must not exceed the recorded step '
                'count ($stepCount).',
          });
          await request.response.close();
          return;
        }
        request.response.write(
          jsonEncode(<String, Object?>{
            'steps': _steps.skip(after).toList(),
            'total': stepCount,
          }),
        );
      case ('GET', '/recorder/export'):
        request.response.write(
          jsonEncode(<String, Object?>{
            'session': _session('recording'),
            'steps': _steps,
            'caseDocument': <String, Object?>{
              'id': 'recorded-r1',
              'schemaVersion': 'cockpit.test/v2',
            },
            'caseYaml': caseYaml,
          }),
        );
      default:
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  static void _writeError(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) {
    response.statusCode = statusCode;
    response.write(jsonEncode(body));
  }

  static Map<String, Object?> _session(String phase) => <String, Object?>{
    'sessionId': 'r1',
    'phase': phase,
    'startedAt': '2026-10-07T09:00:00.000Z',
    'stepCount': stepCount,
    'unresolvedCount': 0,
  };

  static const List<Map<String, Object?>> _steps = <Map<String, Object?>>[
    <String, Object?>{
      'stepId': 's1',
      'kind': 'tap',
      'locatorCandidates': <Object?>[
        <String, Object?>{'kind': 'key', 'selector': '@save', 'score': 4},
      ],
      'phase': 'recording',
      'recordedAt': '2026-10-07T09:00:00.000Z',
    },
    <String, Object?>{
      'stepId': 's2',
      'kind': 'tap',
      'locatorCandidates': <Object?>[
        <String, Object?>{'kind': 'key', 'selector': '@submit', 'score': 4},
      ],
      'phase': 'recording',
      'recordedAt': '2026-10-07T09:00:30.000Z',
    },
  ];
}

Future<int> _reservedThenClosedPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}

/// Binds one active development session handle, mirroring the dev recovery
/// fixtures, so `record` session resolution runs against a real store.
final class _SessionFixtures {
  _SessionFixtures._(this.directory, this.runtime, this.stdout, this.stderr);

  final Directory directory;
  final CockpitCliRuntime runtime;
  final StringBuffer stdout;
  final StringBuffer stderr;

  static Future<_SessionFixtures> create({
    String lifecycle = 'ready',
    bool authenticationEnabled = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-record-session-',
    );
    final store = CockpitCliSessionHandleStore.file(
      path: p.join(directory.path, 'sessions.json'),
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    );
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final runtime = CockpitCliRuntime(
      workingDirectory: directory.path,
      stdoutSink: stdout,
      stderrSink: stderr,
      sessionHandleStoreProvider: () async => store,
      checkoutIdentityResolver: CockpitCheckoutIdentityResolver(
        processRunner:
            (
              String executable,
              List<String> arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async => ProcessResult(1, 1, '', ''),
      ),
    )..configureTimeout(const Duration(minutes: 5), explicit: false);
    final checkout = await runtime.checkoutIdentity();
    await runtime.bindDevelopmentSession(
      checkout: checkout,
      projectPath: checkout.canonicalRoot,
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
      lifecycle: lifecycle,
      authenticationEnabled: authenticationEnabled,
      authToken: authenticationEnabled ? 'bridge-token-1' : null,
    );
    return _SessionFixtures._(directory, runtime, stdout, stderr);
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

CockpitOperationResult _operationResult(Map<String, Object?> output) {
  final now = DateTime.utc(2026, 10, 7);
  return CockpitOperationResult(
    operationId: 'operation-development-get',
    kind: 'session.development.get',
    workspaceId: 'workspace-1',
    lifecycle: CockpitOperationLifecycle.completed,
    outcome: CockpitOperationOutcome.succeeded,
    submittedAt: now,
    startedAt: now,
    finishedAt: now,
    output: output,
  );
}

CockpitOperationResult _failedOperationResult() {
  final now = DateTime.utc(2026, 10, 7);
  return CockpitOperationResult(
    operationId: 'operation-development-get',
    kind: 'session.development.get',
    workspaceId: 'workspace-1',
    lifecycle: CockpitOperationLifecycle.completed,
    outcome: CockpitOperationOutcome.failed,
    submittedAt: now,
    startedAt: now,
    finishedAt: now,
    failure: CockpitFailure(
      primary: CockpitApiError(
        code: 'developmentSessionUnavailable',
        category: CockpitErrorCategory.environment,
        message: 'The development session is gone.',
        retryable: true,
        responsibleLayer: CockpitResponsibleLayer.supervisor,
      ),
    ),
  );
}

Map<String, Object?> _readyOutput(Uri bridgeUrl) => <String, Object?>{
  'sessionId': 'session-1',
  'targetId': 'target-1',
  'appId': 'app-1',
  'status': <String, Object?>{
    'state': 'ready',
    'appReachable': true,
    'remoteSessionReachable': true,
  },
  'runtime': <String, Object?>{
    'bridge': <String, Object?>{'baseUrl': bridgeUrl.toString()},
  },
};

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
