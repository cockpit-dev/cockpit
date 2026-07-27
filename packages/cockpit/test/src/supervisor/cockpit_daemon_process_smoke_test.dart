import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_host.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'cockpitd discovery auth route and ensure process smoke',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpitd-smoke-',
      );
      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:cockpit/cockpit.dart'),
      );
      if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
      final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
      final daemonEntrypoint = p.join(packageRoot, 'bin', 'cockpitd.dart');
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        daemonEntrypoint,
        '--home=${temporary.path}',
      ], workingDirectory: packageRoot);
      addTearDown(() async {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () => -1,
        );
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final paths = CockpitHomePaths(await temporary.resolveSymbolicLinks());
      final discovery = await _waitForDiscovery(paths);
      expect(discovery.authorizationMode, CockpitAuthorizationMode.restricted);
      final policy = Platform.isWindows
          ? const CockpitWindowsAclPermissionHardener()
          : const CockpitPosixPermissionHardener();
      final lifecycle = CockpitDaemonLifecycleClient(
        paths: paths,
        dartExecutable: Platform.resolvedExecutable,
        daemonEntrypoint: daemonEntrypoint,
        permissionHardener: policy,
        directorySyncer: CockpitSystemDirectorySyncer(
          Platform.isWindows
              ? CockpitHostPlatform.windows
              : Platform.isMacOS
              ? CockpitHostPlatform.macos
              : CockpitHostPlatform.linux,
        ),
      );
      final ensured = await Future.wait(
        List<Future<CockpitDaemonDiscovery>>.generate(
          8,
          (_) => lifecycle.ensure(),
        ),
      );
      expect(ensured.map((item) => item.instanceId).toSet(), <String>{
        discovery.instanceId,
      });
      if (!Platform.isWindows) {
        expect((await File(paths.daemonDiscovery).stat()).mode & 0x3f, 0);
      }

      expect(
        (await _get(discovery, '/_cockpit/health', token: 'wrong')).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await _get(discovery, '/api/v2/server')).statusCode,
        HttpStatus.ok,
      );
      expect(
        (await _get(discovery, '/api/v2/capabilities')).statusCode,
        HttpStatus.badRequest,
      );
      final capabilities = await _get(
        discovery,
        '/api/v2/capabilities',
        headers: const <String, String>{'Cockpit-API-Version': '2.0'},
      );
      expect(
        capabilities.statusCode,
        HttpStatus.ok,
        reason: utf8.decode(capabilities.body),
      );
      final capabilitiesText = utf8.decode(capabilities.body);
      final capabilitiesJson = jsonDecode(capabilitiesText);
      final features =
          (capabilitiesJson as Map<String, Object?>)['features']!
              as List<Object?>;
      expect(
        features.cast<Map<String, Object?>>().map((feature) => feature['id']),
        contains('suiteRuns'),
      );
      expect(
        (await _request(
          discovery,
          'PUT',
          '/api/v2/roots',
          headers: const <String, String>{'Cockpit-API-Version': '2.0'},
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
      expect(
        (await _get(
          discovery,
          '/api/v2/server',
          headers: const <String, String>{'Origin': 'https://example.invalid'},
        )).statusCode,
        HttpStatus.forbidden,
      );
      await lifecycle.stop(mode: CockpitDaemonShutdownMode.emergency);
      expect(await process.exitCode, 0);
      expect(await File(paths.daemonDiscovery).exists(), isFalse);
      final yolo = await lifecycle.start(
        authorizationMode: CockpitAuthorizationMode.yolo,
      );
      expect(yolo.authorizationMode, CockpitAuthorizationMode.yolo);
      expect(
        (await lifecycle.status()).authorizationMode,
        CockpitAuthorizationMode.yolo,
      );
      await lifecycle.stop(mode: CockpitDaemonShutdownMode.emergency);
      final log = await File(paths.daemonLog).readAsString();
      expect(log, isNot(contains(discovery.bearerToken)));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'foreground daemon derives exit and cleans isolated state',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpitd-foreground-',
      );
      final workspace = await Directory(
        p.join(temporary.path, 'workspace'),
      ).create();
      final home = await Directory(p.join(temporary.path, 'home')).create();
      final submission = await File(p.join(temporary.path, 'submission.json'))
          .writeAsString(
            jsonEncode(<String, Object?>{
              'workspaceId': 'workspace-placeholder',
              'source': <String, Object?>{
                'kind': 'inline',
                'case': <String, Object?>{
                  'schemaVersion': 'cockpit.test/v2',
                  'kind': 'case',
                  'id': 'foregroundCase',
                  'target': <String, Object?>{
                    'platform': 'android',
                    'targetKind': 'flutterApp',
                    'plane': 'semantic',
                  },
                  'steps': <Object?>[
                    <String, Object?>{
                      'stepId': 'assertReady',
                      'action': <String, Object?>{
                        'type': 'assertText',
                        'text': 'Ready',
                      },
                    },
                  ],
                },
                'sourceSha256': List<String>.filled(64, '0').join(),
              },
              'idempotencyKey': 'foreground-run',
              'inputs': <String, Object?>{},
              'requiredFeatures': <String>[],
            }),
          );
      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:cockpit/cockpit.dart'),
      );
      if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
      final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        p.join(packageRoot, 'bin', 'cockpitd.dart'),
        '--home=${home.path}',
        '--foreground-workspace=${workspace.path}',
        '--foreground-submission=${submission.path}',
      ], workingDirectory: packageRoot);
      addTearDown(() async {
        process.kill(ProcessSignal.sigkill);
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      expect(await process.exitCode, 2);
      final canonicalHome = await home.resolveSymbolicLinks();
      expect(
        await File(p.join(canonicalHome, 'daemon.json')).exists(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<CockpitDaemonDiscovery> _waitForDiscovery(CockpitHomePaths paths) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final file = File(paths.daemonDiscovery);
      if (await file.exists()) {
        return CockpitDaemonDiscovery.fromJson(
          jsonDecode(await file.readAsString()),
        );
      }
    } on Object {
      // Atomic publication may still be completing.
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('cockpitd did not publish discovery.');
}

Future<_Response> _get(
  CockpitDaemonDiscovery discovery,
  String path, {
  String? token,
  Map<String, String> headers = const <String, String>{},
}) => _request(discovery, 'GET', path, token: token, headers: headers);

Future<_Response> _request(
  CockpitDaemonDiscovery discovery,
  String method,
  String path, {
  String? token,
  Map<String, String> headers = const <String, String>{},
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      discovery.endpoint.resolve(path),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${token ?? discovery.bearerToken}',
    );
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return _Response(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

final class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final List<int> body;
}
