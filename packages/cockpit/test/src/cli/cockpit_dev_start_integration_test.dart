import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_cli_session_handles.dart';
import 'package:cockpit/src/cli/cockpit_dev_start.dart';
import 'package:cockpit/src/development/cockpit_checkout_identity.dart';
import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_operation_catalog.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Wire-level integration coverage for `cockpit dev start` authentication.
///
/// A real [CockpitSupervisorApiClient] talks HTTP to an in-process supervisor
/// stub, while the daemon lifecycle handshake, protocol negotiation, bridge
/// shell inspection, checkout resolution, device selection, and session handle
/// persistence all run for real. The scenarios follow the operator journey:
/// first launch with --auth, inheritance across restarts, --no-auth, token
/// rotation, fail-closed guards, and retry hints after a failed launch.
void main() {
  late _DevStartIntegrationHarness harness;

  setUp(() async {
    harness = await _DevStartIntegrationHarness.create();
    addTearDown(harness.dispose);
  });

  test(
    'first launch with --auth sends the pair and persists the handle',
    () async {
      final result = await harness.start(
        const CockpitDevStartRequest(
          authenticationEnabled: true,
          authToken: 'integration-first-token',
        ),
      );

      expect(result.exitCode, cockpitSuccessExitCode);
      final launch = harness.stub.launchInputs.single;
      expect(launch['authenticationEnabled'], isTrue);
      expect(launch['authToken'], 'integration-first-token');
      expect(result.envelope['changed'], 'launched');
      expect(result.envelope['session'], isNotNull);

      final handle = await harness.requireActiveHandle();
      expect(handle.authenticationEnabled, isTrue);
      expect(handle.authToken, 'integration-first-token');
      expect(handle.sessionId, 'session-launched');
      expect(handle.lifecycle, 'ready');
      expect(result.allOutput, isNot(contains('integration-first-token')));
    },
  );

  test(
    'relaunch without flags inherits the stored authentication pair',
    () async {
      await harness.bindStoppedSession(
        authenticationEnabled: true,
        authToken: 'inherited-stored-token',
      );

      final result = await harness.start(const CockpitDevStartRequest());

      expect(result.exitCode, cockpitSuccessExitCode);
      final launch = harness.stub.launchInputs.single;
      expect(launch['authenticationEnabled'], isTrue);
      expect(launch['authToken'], 'inherited-stored-token');
      expect(result.envelope['changed'], 'relaunched');

      final handle = await harness.requireActiveHandle();
      expect(handle.authenticationEnabled, isTrue);
      expect(handle.authToken, 'inherited-stored-token');
      expect(handle.sessionId, 'session-launched');
      expect(result.allOutput, isNot(contains('inherited-stored-token')));
    },
  );

  test('--no-auth clears a stored pair on relaunch', () async {
    await harness.bindStoppedSession(
      authenticationEnabled: true,
      authToken: 'token-to-clear',
    );

    final result = await harness.start(
      const CockpitDevStartRequest(authenticationEnabled: false),
    );

    expect(result.exitCode, cockpitSuccessExitCode);
    final launch = harness.stub.launchInputs.single;
    expect(launch.containsKey('authenticationEnabled'), isFalse);
    expect(launch.containsKey('authToken'), isFalse);

    final handle = await harness.requireActiveHandle();
    expect(handle.authenticationEnabled, isFalse);
    expect(handle.authToken, isEmpty);
    expect(result.allOutput, isNot(contains('token-to-clear')));
  });

  test(
    'a rotated --auth token reaches the wire and replaces the handle',
    () async {
      await harness.bindStoppedSession(
        authenticationEnabled: true,
        authToken: 'rotated-away-token',
      );

      final result = await harness.start(
        const CockpitDevStartRequest(
          authenticationEnabled: true,
          authToken: 'rotated-incoming-token',
        ),
      );

      expect(result.exitCode, cockpitSuccessExitCode);
      final launch = harness.stub.launchInputs.single;
      expect(launch['authenticationEnabled'], isTrue);
      expect(launch['authToken'], 'rotated-incoming-token');

      final handle = await harness.requireActiveHandle();
      expect(handle.authToken, 'rotated-incoming-token');
      expect(result.allOutput, isNot(contains('rotated-away-token')));
      expect(result.allOutput, isNot(contains('rotated-incoming-token')));
    },
  );

  test('enabling authentication without any token fails closed', () async {
    await expectLater(
      harness.start(const CockpitDevStartRequest(authenticationEnabled: true)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('pass --auth <token> to set one'),
        ),
      ),
    );
    expect(harness.stub.launchInputs, isEmpty);
    expect(await harness.activeHandle(), isNull);
  });

  test(
    'a stored enabled pair survives an enabling relaunch without flags',
    () async {
      await harness.bindStoppedSession(
        authenticationEnabled: true,
        authToken: 'stored-pair-token',
      );

      final result = await harness.start(
        const CockpitDevStartRequest(authenticationEnabled: true),
      );

      expect(result.exitCode, cockpitSuccessExitCode);
      final launch = harness.stub.launchInputs.single;
      expect(launch['authenticationEnabled'], isTrue);
      expect(launch['authToken'], 'stored-pair-token');
    },
  );

  test(
    'a failed launch reports an authenticated retry hint without a token',
    () async {
      harness.stub.failLaunch = true;
      final result = await harness.start(
        const CockpitDevStartRequest(
          authenticationEnabled: true,
          authToken: 'failed-launch-token',
        ),
      );

      expect(result.exitCode, cockpitDataExitCode);
      expect(result.envelope['changed'], 'none');
      expect(result.envelope['next'], 'cockpit dev start --auth <token>');
      expect(result.allOutput, isNot(contains('failed-launch-token')));
    },
  );

  test(
    'a failed launch after --no-auth suggests the disabling retry',
    () async {
      harness.stub.failLaunch = true;
      final result = await harness.start(
        const CockpitDevStartRequest(authenticationEnabled: false),
      );

      expect(result.exitCode, cockpitDataExitCode);
      expect(result.envelope['next'], 'cockpit dev start --no-auth');
    },
  );

  test(
    'a failed relaunch of a bound session suggests the session handle',
    () async {
      final bound = await harness.bindStoppedSession(
        authenticationEnabled: true,
        authToken: 'bound-session-token',
      );
      harness.stub.failLaunch = true;

      final result = await harness.start(const CockpitDevStartRequest());

      expect(result.exitCode, cockpitDataExitCode);
      expect(
        result.envelope['next'],
        'cockpit dev start --session ${bound.handleId}',
      );
      expect(result.allOutput, isNot(contains('bound-session-token')));
    },
  );

  test('the default first launch stays unauthenticated on the wire', () async {
    final result = await harness.start(const CockpitDevStartRequest());

    expect(result.exitCode, cockpitSuccessExitCode);
    final launch = harness.stub.launchInputs.single;
    expect(launch.containsKey('authenticationEnabled'), isFalse);
    expect(launch.containsKey('authToken'), isFalse);

    final handle = await harness.requireActiveHandle();
    expect(handle.authenticationEnabled, isFalse);
    expect(handle.authToken, isEmpty);
  });

  test(
    'the daemon handshake and protocol negotiation really executed',
    () async {
      final result = await harness.start(const CockpitDevStartRequest());
      expect(result.exitCode, cockpitSuccessExitCode);
      expect(harness.stub.healthHits, greaterThanOrEqualTo(1));
      expect(harness.stub.serverHits, greaterThanOrEqualTo(1));
    },
  );
}

final class _DevStartIntegrationHarness {
  _DevStartIntegrationHarness._({
    required this.checkoutDirectory,
    required this.homeDirectory,
    required this.stub,
    required this.lifecycle,
    required this.store,
  });

  final Directory checkoutDirectory;
  final Directory homeDirectory;
  final _StubSupervisorServer stub;
  final CockpitDaemonLifecycleClient lifecycle;
  final CockpitCliSessionHandleStore store;

  CockpitCheckoutIdentity? cachedCheckout;

  static const String engineVersion = '4.10.0';

  static Future<Directory> _canonicalTempDirectory(String prefix) async {
    final created = await Directory.systemTemp.createTemp(prefix);
    return Directory(p.normalize(await created.resolveSymbolicLinks()));
  }

  static Future<_DevStartIntegrationHarness> create() async {
    final checkoutDirectory = await _canonicalTempDirectory(
      'cockpit_dev_start_checkout',
    );
    await _writeCheckoutFixture(checkoutDirectory);

    final homeDirectory = await _canonicalTempDirectory(
      'cockpit_dev_start_home',
    );
    final stub = await _StubSupervisorServer.start();
    final paths = CockpitHomePaths(homeDirectory.path);
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(pid);
    if (identity == null) {
      await stub.close();
      throw StateError('Unable to probe the test process start identity.');
    }
    await CockpitDaemonDiscoveryStore(
      paths: paths,
      permissionHardener: const CockpitPosixPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    ).write(
      CockpitDaemonDiscovery(
        instanceId: _StubSupervisorServer.instanceId,
        processId: pid,
        processStartIdentity: identity,
        endpoint: stub.endpoint,
        bearerToken: stub.bearerToken,
        apiMajor: 2,
        apiMinor: 0,
        engineVersion: engineVersion,
        startedAt: DateTime.now().toUtc(),
        authorizationMode: CockpitAuthorizationMode.yolo,
      ),
    );

    final lifecycle = CockpitDaemonLifecycleClient(
      paths: paths,
      executable: 'dart',
      daemonArguments: const <String>[],
      restartArguments: const <String>[],
      permissionHardener: const CockpitPosixPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
      requiredEngineVersion: engineVersion,
    );
    final store = CockpitCliSessionHandleStore.file(
      path: paths.cliSessions,
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    );

    return _DevStartIntegrationHarness._(
      checkoutDirectory: checkoutDirectory,
      homeDirectory: homeDirectory,
      stub: stub,
      lifecycle: lifecycle,
      store: store,
    );
  }

  Future<void> dispose() async {
    await stub.close();
    if (await checkoutDirectory.exists()) {
      await checkoutDirectory.delete(recursive: true);
    }
    if (await homeDirectory.exists()) {
      await homeDirectory.delete(recursive: true);
    }
  }

  static Future<void> _writeCheckoutFixture(Directory root) async {
    await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: demo
environment:
  sdk: ^3.0.0
dependencies:
  flutter_cockpit: any
''');
    final bridgeDirectory = Directory(p.join(root.path, 'cockpit'))
      ..createSync();
    await File(p.join(bridgeDirectory.path, 'main.dart')).writeAsString('''
import 'package:flutter_cockpit/flutter_cockpit.dart';

Future<void> main(List<String> arguments) async {
  final shell = FlutterCockpitApp.fromEnvironment();
  await shell.run(arguments);
}
''');
    final dartTool = Directory(p.join(root.path, '.dart_tool'))..createSync();
    await File(p.join(dartTool.path, 'package_config.json')).writeAsString(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'demo',
            'rootUri': '../',
            'packageUri': 'lib/',
          },
          <String, Object?>{
            'name': 'flutter_cockpit',
            'rootUri': '../../../flutter_cockpit',
            'packageUri': 'lib/',
          },
        ],
      }),
    );
  }

  Future<CockpitCheckoutIdentity> checkout() async => cachedCheckout ??=
      await _newRuntime(StringBuffer(), StringBuffer()).checkoutIdentity();

  CockpitCliRuntime _newRuntime(StringBuffer stdout, StringBuffer stderr) =>
      CockpitCliRuntime(
        workingDirectory: checkoutDirectory.path,
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
        clientProvider: () async =>
            CockpitSupervisorApiClient(lifecycle: lifecycle),
      );

  Future<_DevStartOutcome> start(CockpitDevStartRequest request) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final runtime = _newRuntime(stdout, stderr);
    runtime.configureTimeout(const Duration(minutes: 5), explicit: false);
    runtime.configureOutput(
      command: 'dev start',
      selection: const CockpitCliOutputSelection(
        format: CockpitCliFormat.json,
        view: CockpitCliOutputView.full,
      ),
    );
    final exitCode = await CockpitDevStartService(runtime).start(request);
    return _DevStartOutcome(
      exitCode: exitCode,
      stdoutText: stdout.toString(),
      stderrText: stderr.toString(),
    );
  }

  Future<CockpitCliSessionHandle> bindStoppedSession({
    required bool authenticationEnabled,
    required String authToken,
  }) async {
    final checkout = await this.checkout();
    return store.bindDevelopment(
      activate: true,
      checkoutIdentity: checkout.value,
      checkoutPath: checkout.canonicalRoot,
      projectPath: checkout.canonicalRoot,
      workspaceId: 'workspace-stored',
      sessionId: 'session-stored',
      targetId: _StubSupervisorServer.targetId,
      appId: 'app-stored',
      entrypoint: _StubSupervisorServer.entrypoint,
      platform: 'macos',
      deviceId: 'macos',
      lifecycle: 'stopped',
      authenticationEnabled: authenticationEnabled,
      authToken: authToken,
    );
  }

  Future<CockpitCliSessionHandle?> activeHandle() async {
    final checkout = await this.checkout();
    return store.activeForPath(
      checkoutIdentity: checkout.value,
      path: checkout.canonicalRoot,
    );
  }

  Future<CockpitCliSessionHandle> requireActiveHandle() async {
    final handle = await activeHandle();
    expect(handle, isNotNull, reason: 'A session handle must be persisted.');
    return handle!;
  }
}

final class _DevStartOutcome {
  const _DevStartOutcome({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;

  String get allOutput => '$stdoutText\n$stderrText';

  Map<Object?, Object?> get envelope {
    expect(stdoutText.trim(), isNotEmpty);
    final decoded = jsonDecode(stdoutText);
    expect(decoded, isA<Map<Object?, Object?>>());
    return decoded as Map<Object?, Object?>;
  }
}

/// Minimal supervisor HTTP contract stub: enough of the v2 REST surface for
/// `cockpit dev start`, backed by the real protocol resource codecs.
final class _StubSupervisorServer {
  _StubSupervisorServer._(this._server)
    : bearerToken = 'integration-wire-token-0123456789abcdef';

  static const String instanceId = 'dev-start-integration-daemon';
  static const String entrypoint = 'cockpit/main.dart';
  static const String entrypointSha256 =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  static const String targetId = 'target-itest';

  final HttpServer _server;
  final String bearerToken;

  final List<Map<String, Object?>> launchInputs = <Map<String, Object?>>[];
  final List<CockpitAutomationTargetResource> registeredTargets =
      <CockpitAutomationTargetResource>[];
  bool failLaunch = false;
  int healthHits = 0;
  int serverHits = 0;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_StubSupervisorServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = _StubSupervisorServer._(server);
    server.listen(stub._handle);
    return stub;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final response = request.response;
      final body = await _readBody(request);
      final outcome = _route(request.method, request.uri.path, body);
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(outcome));
      await response.close();
    } on Object {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<Map<Object?, Object?>?> _readBody(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.isEmpty) return null;
    return jsonDecode(text) as Map<Object?, Object?>;
  }

  Map<String, Object?> _route(
    String method,
    String path,
    Map<Object?, Object?>? body,
  ) {
    if (method == 'GET' && path == '/_cockpit/health') {
      healthHits += 1;
      return _serverInfo();
    }
    if (method == 'GET' && path == '/api/v2/server') {
      serverHits += 1;
      return _serverInfo();
    }
    if (method == 'GET' && path == '/api/v2/roots') return _page(const []);
    if (method == 'POST' && path == '/api/v2/roots') {
      return _rootResource((body?['path'] ?? '') as String).toJson();
    }
    if (method == 'GET' && path == '/api/v2/workspaces') return _page(const []);
    if (method == 'POST' && path == '/api/v2/workspaces/register') {
      return _workspaceResource(
        rootId: (body?['rootId'] ?? 'root-itest') as String,
        path: (body?['path'] ?? '') as String,
      ).toJson();
    }
    final workspaceMatch = RegExp(
      r'^/api/v2/workspaces/([^/]+)(/.*)?$',
    ).firstMatch(path);
    if (workspaceMatch != null) {
      final workspaceId = workspaceMatch.group(1)!;
      final tail = workspaceMatch.group(2) ?? '';
      if (method == 'GET' && tail == '/targets') {
        return _page(
          registeredTargets.map((target) => target.toJson()).toList(),
        );
      }
      if (method == 'GET' && tail == '/operations') {
        return _page(_descriptorJson());
      }
      if (method == 'GET' && tail == '/documents') {
        return _page(<Object?>[_documentResource(workspaceId).toJson()]);
      }
      if (method == 'POST' && tail == '/operations') {
        return _execute(workspaceId, body).toJson();
      }
    }
    if (method == 'GET' && path == '/api/v2/operations') {
      return _page(_descriptorJson());
    }
    if (method == 'POST' && path == '/api/v2/operations') {
      return _execute(null, body).toJson();
    }
    throw StateError('Unexpected supervisor request $method $path');
  }

  Map<String, Object?> _serverInfo() => CockpitServerInfo(
    instanceId: instanceId,
    apiVersion: CockpitApiVersion(major: 2, minor: 0),
    engineVersion: _DevStartIntegrationHarness.engineVersion,
    startedAt: DateTime.now().toUtc(),
  ).toJson();

  Map<String, Object?> _page(List<Object?> items) => <String, Object?>{
    'items': items,
    'totalCount': items.length,
  };

  List<Object?> _descriptorJson() => CockpitSupervisorOperationCatalog
      .allOperations
      .map((descriptor) => descriptor.toJson())
      .toList(growable: false);

  CockpitRootResource _rootResource(String path) => CockpitRootResource(
    rootId: 'root-itest',
    canonicalPath: path,
    filesystemIdentity: 'filesystem-itest',
    state: CockpitRootState.active,
    registeredAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  CockpitWorkspaceResource _workspaceResource({
    required String rootId,
    required String path,
  }) => CockpitWorkspaceResource(
    workspaceId: 'workspace-itest',
    projectId: 'project-itest',
    checkoutId: 'checkout-itest',
    rootId: rootId,
    canonicalPath: path,
    filesystemIdentity: 'filesystem-itest',
    state: CockpitWorkspaceState.active,
    registeredAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  CockpitDocumentResource _documentResource(String workspaceId) =>
      CockpitDocumentResource(
        documentId: 'document-entrypoint',
        workspaceId: workspaceId,
        relativePath: entrypoint,
        sha256: entrypointSha256,
        modifiedAt: DateTime.now().toUtc(),
        kind: CockpitIndexedDocumentKind.source,
      );

  CockpitOperationResult _execute(
    String? workspaceId,
    Map<Object?, Object?>? body,
  ) {
    final kind = (body?['kind'] ?? '') as String;
    final input = body?['input'];
    final wireInput = input is Map<Object?, Object?>
        ? Map<String, Object?>.from(input)
        : const <String, Object?>{};
    switch (kind) {
      case 'target.discover':
        return _operationResult(
          kind,
          workspaceId,
          output: <String, Object?>{
            'targets': <Object?>[
              <String, Object?>{
                'id': 'macos',
                'name': 'Mac desktop',
                'platform': 'macos',
                'platformType': 'darwin',
                'emulator': false,
                'ephemeral': false,
                'sdk': 'macos',
              },
            ],
          },
        );
      case 'target.register':
        registeredTargets.add(
          CockpitAutomationTargetResource(
            targetId: targetId,
            workspaceId: workspaceId ?? 'workspace-itest',
            platform: (wireInput['platform'] ?? 'macos') as String,
            deviceId: (wireInput['deviceId'] ?? 'macos') as String,
            targetKind: CockpitTargetKind.flutterApp,
            mode: CockpitAutomationTargetMode.development,
            environment: CockpitAutomationTargetEnvironment.development,
            entrypoint: entrypoint,
            entrypointSha256: entrypointSha256,
          ),
        );
        return _operationResult(kind, workspaceId);
      case 'target.launch':
        launchInputs.add(wireInput);
        if (failLaunch) {
          return _operationResult(
            kind,
            workspaceId,
            outcome: CockpitOperationOutcome.failed,
            output: const <String, Object?>{'reason': 'buildFailed'},
          );
        }
        return _operationResult(
          kind,
          workspaceId,
          output: const <String, Object?>{
            'sessionId': 'session-launched',
            'appId': 'app-launched',
            'targetId': targetId,
          },
        );
      default:
        return _operationResult(kind, workspaceId);
    }
  }

  CockpitOperationResult _operationResult(
    String kind,
    String? workspaceId, {
    CockpitOperationOutcome outcome = CockpitOperationOutcome.succeeded,
    Map<String, Object?> output = const <String, Object?>{},
  }) {
    final now = DateTime.now().toUtc();
    return CockpitOperationResult(
      operationId: 'operation-$kind',
      kind: kind,
      lifecycle: CockpitOperationLifecycle.completed,
      submittedAt: now,
      startedAt: now,
      finishedAt: now,
      outcome: outcome,
      workspaceId: workspaceId,
      output: output,
      failure: outcome == CockpitOperationOutcome.succeeded
          ? null
          : CockpitFailure(
              primary: CockpitApiError(
                code: 'launchFailed',
                category: CockpitErrorCategory.environment,
                message: 'The Flutter launch failed.',
                retryable: true,
                responsibleLayer: CockpitResponsibleLayer.supervisor,
              ),
            ),
    );
  }
}

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
