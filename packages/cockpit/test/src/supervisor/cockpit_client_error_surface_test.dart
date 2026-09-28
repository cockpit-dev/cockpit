import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart'
    show CockpitDirectorySyncer;
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Failure-path coverage for the surfaces a project sees when the daemon or
/// supervisor answers badly: malformed error envelopes must surface the HTTP
/// status and body, and an unhealthy daemon must name the probe failure.
void main() {
  late final Directory homeDirectory;
  late final _FlakyServer server;
  late final CockpitHomePaths paths;

  setUpAll(() async {
    final created = await Directory.systemTemp.createTemp(
      'cockpit_client_error_home',
    );
    homeDirectory = Directory(p.normalize(await created.resolveSymbolicLinks()));
    paths = CockpitHomePaths(homeDirectory.path);
    server = await _FlakyServer.start();
  });

  tearDownAll(() async {
    await server.close();
    if (await homeDirectory.exists()) {
      await homeDirectory.delete(recursive: true);
    }
  });

  Future<CockpitSupervisorApiClient> buildClient() async {
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(pid);
    if (identity == null) {
      throw StateError('Unable to probe the test process start identity.');
    }
    await CockpitDaemonDiscoveryStore(
      paths: paths,
      permissionHardener: const CockpitPosixPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    ).write(
      CockpitDaemonDiscovery(
        instanceId: 'client-error-itest',
        processId: pid,
        processStartIdentity: identity,
        endpoint: server.endpoint,
        bearerToken: 'client-error-itest-token-0123456789',
        apiMajor: 2,
        apiMinor: 0,
        engineVersion: _FlakyServer.engineVersion,
        startedAt: DateTime.now().toUtc(),
        authorizationMode: CockpitAuthorizationMode.yolo,
      ),
    );
    return CockpitSupervisorApiClient(
      lifecycle: CockpitDaemonLifecycleClient(
        paths: paths,
        executable: 'dart',
        daemonArguments: const <String>[],
        restartArguments: const <String>[],
        permissionHardener: const CockpitPosixPermissionHardener(),
        directorySyncer: const _NoopDirectorySyncer(),
        requiredEngineVersion: _FlakyServer.engineVersion,
      ),
    );
  }

  test('malformed supervisor error bodies surface status and body excerpt', () async {
    server.mode = _FlakyServerMode.malformedError;
    final client = await buildClient();
    try {
      await client.workspaces();
      fail('workspaces must not succeed against a malformed error body.');
    } on CockpitSupervisorClientException catch (error) {
      expect(error.code, 'invalidErrorResponse');
      expect(error.message, contains('HTTP 500'));
      expect(error.message, contains('Body:'));
      expect(error.message, contains('proxy-reason'));
    }
  });

  test('an unhealthy daemon names the health probe failure', () async {
    server.mode = _FlakyServerMode.unhealthy;
    final client = await buildClient();
    try {
      await client.workspaces();
      fail('workspaces must not succeed against an unhealthy daemon.');
    } on CockpitDaemonException catch (error) {
      expect(error.code, 'activeDaemonUnhealthy');
      expect(error.message, contains('HTTP 503'));
    }
  });
}

enum _FlakyServerMode { healthy, malformedError, unhealthy }

final class _FlakyServer {
  _FlakyServer._(this._server);

  final HttpServer _server;

  _FlakyServerMode mode = _FlakyServerMode.healthy;

  static const String engineVersion = '9.9.9-error-surface';

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_FlakyServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final flaky = _FlakyServer._(server);
    server.listen((request) => flaky._handle(request));
    return flaky;
  }

  Future<void> _handle(HttpRequest request) async {
    switch (request) {
      case HttpRequest()
          when request.method == 'GET' &&
              request.uri.path == '/_cockpit/health':
        if (mode == _FlakyServerMode.unhealthy) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            CockpitServerInfo(
              instanceId: 'client-error-itest',
              apiVersion: CockpitApiVersion(major: 2, minor: 0),
              engineVersion: engineVersion,
              startedAt: DateTime.now().toUtc(),
            ).toJson(),
          ),
        );
        await request.response.close();
        return;
      default:
        await request.drain<void>();
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'unexpected': <String, Object?>{'reason': 'proxy-reason'},
          }),
        );
        await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
