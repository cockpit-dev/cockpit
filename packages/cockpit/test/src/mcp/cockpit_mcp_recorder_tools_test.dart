import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/mcp/cockpit_mcp_development_tools.dart';
import 'package:cockpit/src/mcp/cockpit_mcp_error.dart';
import 'package:cockpit/src/mcp/cockpit_mcp_tool.dart';
import 'package:cockpit/src/mcp/core/cockpit_mcp_tool_adapter.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_catalog.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Wire-level coverage for the recorder MCP tools: a real
/// [CockpitSupervisorApiClient] negotiates with an in-process supervisor stub
/// whose `recorder.*` operations proxy to an in-process fake app, mirroring
/// the worker's recorder proxy end to end.
void main() {
  test(
    'recorder tools advertise read/write annotations and strict schemas',
    () {
      final tools = <String, CockpitMcpTool>{
        for (final tool in cockpitMcpDevelopmentTools(
          () async => throw StateError('Schema assertions must not connect.'),
        ))
          if (tool.name.startsWith('recorder_')) tool.name: tool,
      };

      expect(
        tools.keys,
        containsAll(const <String>[
          'recorder_start',
          'recorder_pause',
          'recorder_resume',
          'recorder_stop',
          'recorder_status',
          'recorder_steps',
          'recorder_export',
        ]),
      );
      for (final tool in tools.values) {
        expect(tool.enabledByDefault, isFalse, reason: tool.name);
        expect(
          tool.categories,
          equals(const <CockpitMcpFeatureCategory>[
            CockpitMcpFeatureCategory.e2e,
            CockpitMcpFeatureCategory.sessionManagement,
          ]),
          reason: tool.name,
        );
        expect(tool.annotations.destructive, isFalse, reason: tool.name);
        expect(tool.inputSchema['required'], const <String>[
          'workspaceId',
          'sessionId',
        ], reason: tool.name);
        expect(
          tool.inputSchema['additionalProperties'],
          isFalse,
          reason: tool.name,
        );
      }
      for (final name in const <String>['recorder_status', 'recorder_steps']) {
        expect(tools[name]!.annotations.readOnly, isTrue, reason: name);
        expect(tools[name]!.annotations.idempotent, isTrue, reason: name);
      }
      for (final name in const <String>[
        'recorder_start',
        'recorder_pause',
        'recorder_resume',
        'recorder_stop',
        'recorder_export',
      ]) {
        expect(tools[name]!.annotations.readOnly, isFalse, reason: name);
        expect(tools[name]!.annotations.idempotent, isFalse, reason: name);
      }

      Map<String, Object?> properties(String name) =>
          tools[name]!.inputSchema['properties']! as Map<String, Object?>;
      expect(
        properties('recorder_start').keys,
        containsAll(const <String>['name']),
      );
      final after =
          properties('recorder_steps')['after']! as Map<String, Object?>;
      expect(after['type'], 'integer');
      expect(after['minimum'], 0);
      expect(properties('recorder_export').keys, isNot(contains('out')));

      // Every tool enforces strict string identity arguments and only its own
      // optional inputs; the wire schemas reject wrong types and bounds.
      for (final tool in tools.values) {
        final schema = CockpitMcpToolAdapter.protocolToolFor(tool).inputSchema;
        const arguments = <String, Object?>{
          'workspaceId': 'workspace-1',
          'sessionId': 'session-1',
        };
        expect(
          schema.validate(arguments),
          isEmpty,
          reason: '${tool.name}: bare call must be schema-valid',
        );
        expect(
          schema.validate(const <String, Object?>{'sessionId': 'session-1'}),
          isNotEmpty,
          reason: '${tool.name}: missing workspaceId',
        );
        expect(
          schema.validate(const <String, Object?>{'workspaceId': 7}),
          isNotEmpty,
          reason: '${tool.name}: workspaceId must be a string',
        );
        expect(
          schema.validate(const <String, Object?>{
            'workspaceId': 'workspace-1',
            'sessionId': 'session-1',
            'unexpected': true,
          }),
          isNotEmpty,
          reason: '${tool.name}: unknown arguments are rejected',
        );
      }
      final stepsSchema = CockpitMcpToolAdapter.protocolToolFor(
        tools['recorder_steps']!,
      ).inputSchema;
      expect(
        stepsSchema.validate(const <String, Object?>{
          'workspaceId': 'workspace-1',
          'sessionId': 'session-1',
          'after': 3,
        }),
        isEmpty,
      );
      for (final invalid in const <Object?>['1', -1, 1000001, 1.5, true]) {
        expect(
          stepsSchema.validate(<String, Object?>{
            'workspaceId': 'workspace-1',
            'sessionId': 'session-1',
            'after': invalid,
          }),
          isNotEmpty,
          reason: 'after=$invalid must fail schema validation',
        );
      }
      final startSchema = CockpitMcpToolAdapter.protocolToolFor(
        tools['recorder_start']!,
      ).inputSchema;
      expect(
        startSchema.validate(const <String, Object?>{
          'workspaceId': 'workspace-1',
          'sessionId': 'session-1',
          'name': 'checkout',
        }),
        isEmpty,
      );
      expect(
        startSchema.validate(const <String, Object?>{
          'workspaceId': 'workspace-1',
          'sessionId': 'session-1',
          'name': 9,
        }),
        isNotEmpty,
      );
    },
  );

  test('recorder tools drive a live recording session end to end', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final tools = <String, CockpitMcpTool>{
      for (final tool in cockpitMcpDevelopmentTools(() async => harness.client))
        tool.name: tool,
    };
    Future<Map<String, Object?>> call(
      String name, [
      Map<String, Object?> arguments = const <String, Object?>{},
    ]) async {
      final result = await tools[name]!.call(<String, Object?>{
        'workspaceId': 'workspace-1',
        'sessionId': 'session-1',
        ...arguments,
      });
      return result['structuredContent']! as Map<String, Object?>;
    }

    final started = await call('recorder_start', {'name': 'checkout flow'});
    expect(started['sessionId'], 'r1');
    expect(started['phase'], 'recording');
    expect(harness.app.startBodies.single, <String, Object?>{
      'name': 'checkout flow',
    });

    final status = await call('recorder_status');
    expect(status['sessionId'], 'r1');
    expect(status['stepCount'], _RecorderAppServer.stepCount);

    final paused = await call('recorder_pause');
    expect(paused['phase'], 'paused');
    expect(paused['pausedAt'], '2026-10-07T09:01:00.000Z');
    final resumed = await call('recorder_resume');
    expect(resumed['phase'], 'recording');

    final page = await call('recorder_steps', {'after': 1});
    expect(page['total'], _RecorderAppServer.stepCount);
    expect(
      (page['steps']! as List<Object?>).map(
        (step) => (step as Map<String, Object?>)['stepId'],
      ),
      const <String>['s2'],
    );
    expect(harness.app.stepsQueries, const <String>['1']);

    final exported = await call('recorder_export');
    expect(exported['format'], 'yaml');
    expect(exported['document'], _RecorderAppServer.caseYaml);
    final parsed = loadYaml(exported['document']! as String) as YamlMap;
    expect(parsed['schemaVersion'], 'cockpit.test/v2');
    expect(parsed['id'], 'recorded-r1');

    final stopped = await call('recorder_stop');
    expect((stopped['session']! as Map<String, Object?>)['phase'], 'stopped');
    expect(stopped['steps'], hasLength(_RecorderAppServer.stepCount));
    // Every tool call crossed the supervisor as one recorder operation
    // carrying the session scope.
    expect(harness.supervisor.recorderCalls, hasLength(7));
    for (final (kind, input) in harness.supervisor.recorderCalls) {
      expect(kind, startsWith('recorder.'));
      expect(input['sessionId'], 'session-1', reason: kind);
    }
    expect(harness.app.requestCount, greaterThan(0));
  });

  test('recorder tools answer the idle session and default cursor', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final tools = <String, CockpitMcpTool>{
      for (final tool in cockpitMcpDevelopmentTools(() async => harness.client))
        tool.name: tool,
    };
    Future<Map<String, Object?>> call(String name) => tools[name]!
        .call(const <String, Object?>{
          'workspaceId': 'workspace-1',
          'sessionId': 'session-1',
        })
        .then((result) => result['structuredContent']! as Map<String, Object?>);

    harness.app.idle = true;
    expect(await call('recorder_status'), const <String, Object?>{
      'phase': 'idle',
    });

    // Without an explicit cursor the tool drains from zero.
    harness.app.idle = false;
    final page = await call('recorder_steps');
    expect(page['total'], _RecorderAppServer.stepCount);
    expect(
      (page['steps']! as List<Object?>),
      hasLength(_RecorderAppServer.stepCount),
    );
    expect(harness.app.stepsQueries, const <String>['0']);
  });

  test('recorder tools map operation failures to MCP errors', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    final tools = <String, CockpitMcpTool>{
      for (final tool in cockpitMcpDevelopmentTools(() async => harness.client))
        tool.name: tool,
    };
    final arguments = const <String, Object?>{
      'workspaceId': 'workspace-1',
      'sessionId': 'session-1',
    };

    // A failed operation keeps the worker-reported error code through the MCP
    // boundary, with the session named in the message.
    harness.app.failPause = true;
    await expectLater(
      tools['recorder_pause']!.call(arguments),
      throwsA(
        isA<CockpitMcpError>()
            .having((error) => error.code, 'code', -32000)
            .having(
              (error) => error.data,
              'data',
              containsPair('apiCode', 'serverError'),
            )
            .having(
              (error) => error.message,
              'message',
              allOf(contains('session-1'), contains('Cannot pause')),
            ),
      ),
    );

    // A result that never finished (still running, no outcome, no failure
    // payload) keeps the same error class with the bare message.
    harness.supervisor.pendingRecorderOperation = true;
    harness.app.failPause = false;
    await expectLater(
      tools['recorder_pause']!.call(arguments),
      throwsA(
        isA<CockpitMcpError>()
            .having((error) => error.code, 'code', -32000)
            .having(
              (error) => error.message,
              'message',
              contains('did not complete'),
            ),
      ),
    );
    harness.supervisor.pendingRecorderOperation = false;

    // Wrong-typed and unknown tool arguments are invalid-argument errors.
    await expectLater(
      tools['recorder_steps']!.call(<String, Object?>{
        'workspaceId': 'workspace-1',
        'sessionId': 'session-1',
        'after': '1',
      }),
      throwsA(
        isA<CockpitMcpError>()
            .having((error) => error.code, 'code', -32602)
            .having((error) => error.message, 'message', contains('after')),
      ),
    );
    await expectLater(
      tools['recorder_start']!.call(<String, Object?>{
        'workspaceId': 'workspace-1',
        'sessionId': 'session-1',
        'out': 'flow.yaml',
      }),
      throwsA(
        isA<CockpitMcpError>()
            .having((error) => error.code, 'code', -32602)
            .having(
              (error) => error.message,
              'message',
              contains('Unknown tool argument out'),
            ),
      ),
    );

    await expectLater(
      tools['recorder_status']!.call(const <String, Object?>{
        'workspaceId': '',
        'sessionId': 'session-1',
      }),
      throwsA(
        isA<CockpitMcpError>().having((error) => error.code, 'code', -32602),
      ),
    );
  });
}

const String _caseYaml = 'schemaVersion: cockpit.test/v2\nid: recorded-r1\n';

/// Binds one supervisor stub, one fake recorder app, and a real supervisor
/// client talking HTTP to both.
final class _Harness {
  _Harness._(this.home, this.supervisor, this.app, this.client);

  static const String engineVersion = '4.10.0';

  final Directory home;
  final _SupervisorStub supervisor;
  final _RecorderAppServer app;
  final CockpitSupervisorApiClient client;

  static Future<_Harness> create() async {
    final created = await Directory.systemTemp.createTemp(
      'cockpit-mcp-recorder-',
    );
    final home = Directory(p.normalize(await created.resolveSymbolicLinks()));
    final app = await _RecorderAppServer.start();
    final supervisor = await _SupervisorStub.start(appUrl: app.endpoint);
    final paths = CockpitHomePaths(home.path);
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(pid);
    if (identity == null) {
      await supervisor.close();
      await app.close();
      throw StateError('Unable to probe the test process start identity.');
    }
    await CockpitDaemonDiscoveryStore(
      paths: paths,
      permissionHardener: const CockpitPosixPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    ).write(
      CockpitDaemonDiscovery(
        instanceId: _SupervisorStub.instanceId,
        processId: pid,
        processStartIdentity: identity,
        endpoint: supervisor.endpoint,
        bearerToken: supervisor.bearerToken,
        apiMajor: 2,
        apiMinor: 0,
        engineVersion: engineVersion,
        startedAt: DateTime.now().toUtc(),
        authorizationMode: CockpitAuthorizationMode.yolo,
      ),
    );
    final client = CockpitSupervisorApiClient(
      lifecycle: CockpitDaemonLifecycleClient(
        paths: paths,
        executable: 'dart',
        daemonArguments: const <String>[],
        restartArguments: const <String>[],
        permissionHardener: const CockpitPosixPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
        requiredEngineVersion: engineVersion,
      ),
    );
    return _Harness._(home, supervisor, app, client);
  }

  Future<void> dispose() async {
    await supervisor.close();
    await app.close();
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  }
}

/// Serves the workspace-operation v2 REST surface for one workspace, proxying
/// every `recorder.*` operation to one fake app the way the worker does.
final class _SupervisorStub {
  _SupervisorStub._(this._server)
    : bearerToken = 'mcp-recorder-wire-token-0123456789abcdef';

  static const String instanceId = 'mcp-recorder-supervisor';

  final HttpServer _server;
  final String bearerToken;

  /// Answers every `recorder.*` operation with a still-running result (no
  /// outcome, no failure), exercising the bare did-not-complete message.
  bool pendingRecorderOperation = false;

  /// Every recorder operation the stub received, as (kind, input) pairs.
  final List<(String, Map<String, Object?>)> recorderCalls =
      <(String, Map<String, Object?>)>[];

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_SupervisorStub> start({required Uri appUrl}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = _SupervisorStub._(server).._appUrl = appUrl;
    server.listen(stub._handle);
    return stub;
  }

  late final Uri _appUrl;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty
          ? null
          : jsonDecode(text) as Map<Object?, Object?>;
      final outcome = await _route(request.method, request.uri.path, body);
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(outcome));
    } on Object {
      response.statusCode = HttpStatus.internalServerError;
    }
    await response.close();
  }

  Future<Object?> _route(
    String method,
    String path,
    Map<Object?, Object?>? body,
  ) async {
    if (method == 'GET' &&
        (path == '/_cockpit/health' || path == '/api/v2/server')) {
      return _serverInfo();
    }
    final workspaceMatch = RegExp(
      r'^/api/v2/workspaces/([^/]+)/operations$',
    ).firstMatch(path);
    if (workspaceMatch != null) {
      if (method == 'GET') return _page(_descriptors());
      if (method == 'POST') {
        final kind = body?['kind'];
        if (kind is String && kind.startsWith('recorder.')) {
          return (await _recorderResult(kind, body!['input'])).toJson();
        }
      }
    }
    throw StateError('Unexpected supervisor request $method $path');
  }

  Map<String, Object?> _serverInfo() => CockpitServerInfo(
    instanceId: instanceId,
    apiVersion: CockpitApiVersion(major: 2, minor: 0),
    engineVersion: _Harness.engineVersion,
    startedAt: DateTime.now().toUtc(),
  ).toJson();

  Map<String, Object?> _page(List<Object?> items) => <String, Object?>{
    'items': items,
    'totalCount': items.length,
  };

  List<Object?> _descriptors() => CockpitSupervisorOperationCatalog
      .allOperations
      .map((descriptor) => descriptor.toJson())
      .toList(growable: false);

  /// Proxies one `recorder.*` operation to the fake app and wraps its answer
  /// in a succeeded operation result, mirroring the worker's proxy.
  Future<CockpitOperationResult> _recorderResult(
    String kind,
    Object? rawInput,
  ) async {
    final input = rawInput is Map<Object?, Object?>
        ? Map<String, Object?>.from(rawInput)
        : const <String, Object?>{};
    recorderCalls.add((kind, input));
    final now = DateTime.now().toUtc();
    if (pendingRecorderOperation) {
      return CockpitOperationResult(
        operationId: 'operation-$kind',
        kind: kind,
        lifecycle: CockpitOperationLifecycle.running,
        submittedAt: now,
        startedAt: now,
        workspaceId: 'workspace-1',
      );
    }
    final (method, target, body) = switch (kind) {
      'recorder.start' => (
        'POST',
        _appUrl.replace(path: '/recorder/start'),
        jsonEncode(<String, Object?>{'name': ?input['name']}),
      ),
      'recorder.pause' => (
        'POST',
        _appUrl.replace(path: '/recorder/pause'),
        null,
      ),
      'recorder.resume' => (
        'POST',
        _appUrl.replace(path: '/recorder/resume'),
        null,
      ),
      'recorder.stop' => (
        'POST',
        _appUrl.replace(path: '/recorder/stop'),
        null,
      ),
      'recorder.get' => (
        'GET',
        _appUrl.replace(path: '/recorder/session'),
        null,
      ),
      'recorder.steps' => (
        'GET',
        _appUrl.replace(
          path: '/recorder/steps',
          queryParameters: <String, String>{'after': '${input['after'] ?? 0}'},
        ),
        null,
      ),
      _ => ('GET', _appUrl.replace(path: '/recorder/export'), null),
    };
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, target);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(body);
      final response = await request.close();
      final payload = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode != HttpStatus.ok) {
        final error = payload as Map<Object?, Object?>;
        return CockpitOperationResult(
          operationId: 'operation-$kind',
          kind: kind,
          lifecycle: CockpitOperationLifecycle.completed,
          submittedAt: now,
          startedAt: now,
          finishedAt: now,
          outcome: CockpitOperationOutcome.failed,
          workspaceId: 'workspace-1',
          failure: CockpitFailure(
            primary: CockpitApiError(
              code: error['error']! as String,
              category: CockpitErrorCategory.application,
              message: error['message']! as String,
              retryable: false,
              responsibleLayer: CockpitResponsibleLayer.application,
            ),
          ),
        );
      }
      return CockpitOperationResult(
        operationId: 'operation-$kind',
        kind: kind,
        lifecycle: CockpitOperationLifecycle.completed,
        submittedAt: now,
        startedAt: now,
        finishedAt: now,
        outcome: CockpitOperationOutcome.succeeded,
        workspaceId: 'workspace-1',
        output: Map<String, Object?>.from(payload as Map<Object?, Object?>),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Serves the remote recorder routes of one live app behind a loopback port.
final class _RecorderAppServer {
  _RecorderAppServer._(this._server);

  static const int stepCount = 2;

  final HttpServer _server;
  final List<Map<String, Object?>> startBodies = <Map<String, Object?>>[];
  final List<String> stepsQueries = <String>[];
  int requestCount = 0;

  /// While true the app answers the cold-app payloads: idle session and the
  /// server error a pause from idle raises.
  bool idle = false;
  bool failPause = false;

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
    requestCount++;
    request.response.headers.contentType = ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('POST', '/recorder/start'):
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        startBodies.add(
          Map<String, Object?>.from(body as Map<Object?, Object?>),
        );
        request.response.write(jsonEncode(_session('recording')));
      case ('POST', '/recorder/pause'):
        if (failPause || idle) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(
            jsonEncode(const <String, Object?>{
              'error': 'serverError',
              'message':
                  'Bad state: Cannot pause while the interaction recording '
                  'is idle.',
            }),
          );
        } else {
          request.response.write(
            jsonEncode({
              ..._session('paused'),
              'pausedAt': '2026-10-07T09:01:00.000Z',
            }),
          );
        }
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
        final after = request.uri.queryParameters['after'] ?? '0';
        stepsQueries.add(after);
        request.response.write(
          jsonEncode(<String, Object?>{
            'steps': _steps.skip(int.parse(after)).toList(),
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

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
