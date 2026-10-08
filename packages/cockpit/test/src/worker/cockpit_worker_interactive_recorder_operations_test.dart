import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/worker/cockpit_worker_application_support.dart';
import 'package:cockpit/src/worker/cockpit_worker_artifact_retainer.dart';
import 'package:cockpit/src/worker/cockpit_worker_development_session_runtime.dart';
import 'package:cockpit/src/worker/cockpit_worker_document_index.dart';
import 'package:cockpit/src/worker/cockpit_worker_interactive_operations.dart';
import 'package:cockpit/src/worker/cockpit_json_rpc_peer.dart';
import 'package:cockpit/src/worker/cockpit_worker_process_manager.dart';
import 'package:cockpit/src/worker/cockpit_worker_resource_grant.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_workspace_operation_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Wire-level coverage for the worker's `recorder.*` operations: one in-memory
/// registry records an app whose handle points at a loopback fake recorder,
/// and the interactive backend proxies every operation to it.
void main() {
  test('recorder operations proxy every recorder endpoint', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);

    final started = await harness.execute('recorder.start', <String, Object?>{
      'sessionId': harness.sessionId,
      'name': 'checkout flow',
    });
    // The sanitizer rewrites identity keys to the workspace session id, like
    // every other session-scoped worker payload.
    expect(started['sessionId'], harness.sessionId);
    expect(started['phase'], 'recording');
    expect(harness.app.startBodies.single, <String, Object?>{
      'name': 'checkout flow',
    });

    final paused = await harness.execute('recorder.pause', <String, Object?>{
      'sessionId': harness.sessionId,
    });
    expect(paused['phase'], 'paused');
    expect(paused['pausedAt'], '2026-10-07T09:01:00.000Z');
    expect(
      (await harness.execute('recorder.resume', <String, Object?>{
        'sessionId': harness.sessionId,
      }))['phase'],
      'recording',
    );

    final session = await harness.execute('recorder.get', <String, Object?>{
      'sessionId': harness.sessionId,
    });
    expect(session['stepCount'], _FakeRecorderApp.stepCount);
    harness.app.idle = true;
    expect(
      await harness.execute('recorder.get', <String, Object?>{
        'sessionId': harness.sessionId,
      }),
      const <String, Object?>{'phase': 'idle'},
    );
    harness.app.idle = false;

    final page = await harness.execute('recorder.steps', <String, Object?>{
      'sessionId': harness.sessionId,
      'after': 1,
    });
    expect(page['total'], _FakeRecorderApp.stepCount);
    expect(
      (page['steps']! as List<Object?>).map(
        (step) => (step as Map<String, Object?>)['stepId'],
      ),
      const <String>['s2'],
    );
    expect(harness.app.stepsQueries, const <String>['1']);

    final exported = await harness.execute('recorder.export', <String, Object?>{
      'sessionId': harness.sessionId,
    });
    expect(exported['caseYaml'], _FakeRecorderApp.caseYaml);
    expect(
      (exported['caseDocument']! as Map<String, Object?>)['id'],
      'recorded-r1',
    );

    final stopped = await harness.execute('recorder.stop', <String, Object?>{
      'sessionId': harness.sessionId,
    });
    expect((stopped['session']! as Map<String, Object?>)['phase'], 'stopped');
    expect(stopped['steps'], hasLength(_FakeRecorderApp.stepCount));
  });

  test(
    'recorder operations reject invalid input before dialing the app',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      Future<Object?> Function() call(
        String kind,
        Map<String, Object?> input,
      ) =>
          () => harness.execute(kind, input);

      // sessionId is required, must be a worker id, and no extra keys travel.
      await expectLater(
        call('recorder.get', const <String, Object?>{}),
        throwsFormatException,
      );
      await expectLater(
        call('recorder.get', <String, Object?>{
          'sessionId': harness.sessionId,
          'name': 'unexpected',
        }),
        throwsFormatException,
      );
      await expectLater(
        call('recorder.get', const <String, Object?>{'sessionId': '../escape'}),
        throwsFormatException,
      );

      // The steps cursor is bounded to 0..1000000 and integral.
      for (final after in const <Object?>[-1, 1000001, '1', 1.5]) {
        await expectLater(
          call('recorder.steps', <String, Object?>{
            'sessionId': harness.sessionId,
            'after': after,
          }),
          throwsFormatException,
          reason: 'after=$after',
        );
      }

      // The start name is bounded to 256 characters.
      await expectLater(
        call('recorder.start', <String, Object?>{
          'sessionId': harness.sessionId,
          'name': 'a' * 257,
        }),
        throwsFormatException,
      );

      expect(harness.app.requestCount, 0);
    },
  );

  test(
    'recorder operations enforce session grants by mutation class',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      Matcher invalidGrant() => isA<CockpitApplicationServiceException>()
          .having((error) => error.code, 'code', 'workerResourceGrantInvalid');

      // Read-only operations arrive grant-less (no lease is acquired for them,
      // as the MCP read path proved live) and must still dial the app.
      final read = await harness.execute('recorder.get', <String, Object?>{
        'sessionId': harness.sessionId,
      }, grants: const <CockpitWorkerResourceGrant>[]);
      expect(read['stepCount'], _FakeRecorderApp.stepCount);

      // Mutating operations without a grant for this session are rejected
      // before the app is dialed.
      for (final kind in const <String>[
        'recorder.start',
        'recorder.pause',
        'recorder.resume',
        'recorder.stop',
        'recorder.export',
      ]) {
        await expectLater(
          harness.execute(kind, <String, Object?>{
            'sessionId': harness.sessionId,
          }, grants: const <CockpitWorkerResourceGrant>[]),
          throwsA(invalidGrant()),
          reason: kind,
        );
      }

      // A grant for a foreign resource authorizes nothing — read included.
      await expectLater(
        harness.execute(
          'recorder.get',
          <String, Object?>{'sessionId': harness.sessionId},
          grants: <CockpitWorkerResourceGrant>[harness.foreignGrant()],
        ),
        throwsA(invalidGrant()),
      );
      expect(harness.app.requestCount, 1);
    },
  );

  test('recorder operations preserve app error codes', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.app.failPause = true;

    await expectLater(
      harness.execute('recorder.pause', <String, Object?>{
        'sessionId': harness.sessionId,
      }),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having((error) => error.code, 'code', 'serverError')
            .having(
              (error) => error.message,
              'message',
              contains('Cannot pause while idle.'),
            ),
      ),
    );
  });
}

final class _Harness {
  _Harness._(
    this._temporary,
    this.app,
    this._operations,
    this._sanitizer,
    this._context,
    this._grants,
    this.sessionId,
    this._foreignResourceId,
  );

  final Directory _temporary;
  final _FakeRecorderApp app;
  final CockpitWorkerInteractiveOperations _operations;
  final CockpitWorkerResultSanitizer _sanitizer;
  final CockpitWorkspaceOperationContext _context;
  final List<CockpitWorkerResourceGrant> _grants;
  final String sessionId;
  final String _foreignResourceId;

  static Future<_Harness> create() async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-recorder-',
    );
    final workspaceRoot = await temporary.resolveSymbolicLinks();
    final stateRoot = p.join(workspaceRoot, 'state');
    await Directory(stateRoot).create();
    final app = await _FakeRecorderApp.start();
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      stateRoot: stateRoot,
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    final targetId = await registry.registerTarget(
      const CockpitWorkerTargetRegistration(
        workspaceId: 'workspaceA',
        platform: 'android',
        deviceId: 'emulator-5554',
      ),
    );
    final recorded = await registry.recordApp(
      targetId: targetId,
      handle: CockpitAppHandle.fromRemoteSession(
        CockpitRemoteSessionHandle(
          platform: 'android',
          deviceId: 'emulator-5554',
          projectDir: workspaceRoot,
          target: 'android',
          appId: 'recorder-app',
          platformAppIdKnown: false,
          host: app.endpoint.host,
          hostPort: app.endpoint.port,
          devicePort: app.endpoint.port,
          baseUrl: app.endpoint.toString(),
          launchedAt: DateTime.utc(2026, 10, 7, 9),
        ),
      ),
    );
    final sessionId = await registry.sessionIdForApp(recorded.appId);
    final operations = CockpitWorkerInteractiveOperations(
      workspaceId: 'workspaceA',
      workspaceRoot: workspaceRoot,
      registry: registry,
      developmentRuntime: CockpitWorkerDevelopmentSessionRuntime(
        appTempStore: CockpitAppTempStore(
          root: p.join(stateRoot, 'app-temp'),
          permissionHardener: const CockpitPosixPermissionHardener(),
        ),
      ),
      documents: CockpitWorkerDocumentIndex(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot,
        permissionHardener: const CockpitPosixPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
      ),
      producerRoot: p.join(stateRoot, 'producer'),
      targets: registry,
      processManager: CockpitWorkerProcessManager(),
    );
    final binding = await registry.requireSession(sessionId);
    final now = DateTime.now().toUtc();
    final grants = <CockpitWorkerResourceGrant>[
      CockpitWorkerResourceGrant(
        grantId: 'grant-recorder-1',
        leaseId: 'lease-recorder-1',
        workspaceId: 'workspaceA',
        holderId: 'holder-1',
        resourceKind: CockpitLeaseResourceKind.session,
        resourceId: binding.resourceId,
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    ];
    return _Harness._(
      temporary,
      app,
      operations,
      CockpitWorkerResultSanitizer(
        workspaceRoot: workspaceRoot,
        registry: registry,
        artifactRetainer: CockpitWorkerArtifactRetainer(
          stateRoot: stateRoot,
          producerRoot: p.join(stateRoot, 'producer'),
          permissionHardener: const CockpitPosixPermissionHardener(),
          directorySyncer: const _NoopDirectorySyncer(),
        ),
      ),
      CockpitWorkspaceOperationContext(
        workspaceId: 'workspaceA',
        workspaceRoot: workspaceRoot,
        requestId: 'request-recorder-1',
        deadline: now.add(const Duration(minutes: 2)),
        idempotencyKey: 'idem-recorder-1',
        requiredFeatures: const <String>[],
        cancellation: CockpitRpcCancellation.detached(),
      ),
      grants,
      sessionId,
      'session:other-session',
    );
  }

  CockpitWorkerResourceGrant foreignGrant() => CockpitWorkerResourceGrant(
    grantId: 'grant-recorder-2',
    leaseId: 'lease-recorder-2',
    workspaceId: 'workspaceA',
    holderId: 'holder-1',
    resourceKind: CockpitLeaseResourceKind.session,
    resourceId: _foreignResourceId,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
  );

  Future<Map<String, Object?>> execute(
    String kind,
    Map<String, Object?> input, {
    List<CockpitWorkerResourceGrant>? grants,
  }) => _operations.execute(
    kind: kind,
    input: input,
    context: _context,
    grants: grants ?? _grants,
    sanitizer: _sanitizer,
  );

  Future<void> dispose() async {
    await app.close();
    await _temporary.delete(recursive: true);
  }
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}

/// Serves the remote recorder routes of one live app behind a loopback port.
final class _FakeRecorderApp {
  _FakeRecorderApp._(this._server);

  static const int stepCount = 2;
  static const String caseYaml =
      'schemaVersion: cockpit.test/v2\nid: recorded-r1\n';

  final HttpServer _server;
  final List<Map<String, Object?>> startBodies = <Map<String, Object?>>[];
  final List<String> stepsQueries = <String>[];
  int requestCount = 0;

  bool idle = false;
  bool failPause = false;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_FakeRecorderApp> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final app = _FakeRecorderApp._(server);
    server.listen(app._handle);
    return app;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
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
              'message': 'Bad state: Cannot pause while idle.',
            }),
          );
        } else {
          request.response.write(
            jsonEncode(<String, Object?>{
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
            idle
                ? const <String, Object?>{'phase': 'idle'}
                : _session('recording'),
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
