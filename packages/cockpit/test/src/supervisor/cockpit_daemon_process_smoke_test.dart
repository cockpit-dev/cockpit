import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/foundation/cockpit_version.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_host.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'AOT CLI launches its self-contained daemon',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-aot-daemon-smoke-',
      );
      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:cockpit/cockpit.dart'),
      );
      if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
      final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
      final executable = p.join(
        temporary.path,
        Platform.isWindows ? 'cockpit.exe' : 'cockpit',
      );
      final home = await Directory(p.join(temporary.path, 'home')).create();
      final allowedRoot = await Directory(
        p.join(temporary.path, 'projects'),
      ).create();
      final workspace = await Directory(
        p.join(allowedRoot.path, 'sample'),
      ).create();
      await File(p.join(workspace.path, 'pubspec.yaml')).writeAsString('''
name: cockpit_aot_worker_smoke
environment:
  sdk: '>=3.8.0 <4.0.0'
''');
      final environment = <String, String>{
        ...Platform.environment,
        'COCKPIT_HOME': await home.resolveSymbolicLinks(),
      };
      addTearDown(() async {
        if (await File(executable).exists()) {
          await Process.run(executable, const <String>[
            'daemon',
            'stop',
            '--mode',
            'emergency',
            '--format',
            'none',
          ], environment: environment).timeout(
            const Duration(seconds: 10),
            onTimeout: () => ProcessResult(0, 1, '', 'stop timed out'),
          );
        }
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final compilation = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'compile',
          'exe',
          p.join(packageRoot, 'bin', 'cockpit.dart'),
          '-o',
          executable,
        ],
        workingDirectory: packageRoot,
      ).timeout(const Duration(minutes: 2));
      expect(compilation.exitCode, 0, reason: '${compilation.stderr}');

      final started = await Process.run(executable, const <String>[
        'daemon',
        'start',
        '--yolo',
        '--format',
        'json',
        '--view',
        'full',
      ], environment: environment).timeout(const Duration(seconds: 20));
      expect(started.exitCode, 0, reason: '${started.stderr}');
      final output =
          jsonDecode('${started.stdout}'.trim()) as Map<String, Object?>;
      expect(output['running'], isTrue);
      expect(output['healthy'], isTrue);
      expect(output['auth'], 'yolo');

      final rootResult = await _runAotCli(executable, environment, <String>[
        'root',
        'add',
        '--path',
        allowedRoot.path,
      ]);
      final rootId = rootResult['root']! as String;
      final workspaceResult = await _runAotCli(
        executable,
        environment,
        <String>[
          'workspace',
          'register',
          '--root-id',
          rootId,
          '--path',
          workspace.path,
        ],
      );
      final workspaceId = workspaceResult['workspace']! as String;
      final discovery = await _waitForDiscovery(
        CockpitHomePaths(environment['COCKPIT_HOME']!),
      );
      final capabilitiesStopwatch = Stopwatch()..start();
      final capabilities = await _get(
        discovery,
        '/api/v2/capabilities',
        headers: const <String, String>{'Cockpit-API-Version': '2.0'},
      );
      capabilitiesStopwatch.stop();
      expect(capabilities.statusCode, HttpStatus.ok);
      expect(
        capabilitiesStopwatch.elapsed,
        lessThan(const Duration(seconds: 2)),
      );
      final capabilityKinds =
          ((jsonDecode(utf8.decode(capabilities.body))
                      as Map<String, Object?>)['operations']!
                  as List<Object?>)
              .cast<Map<String, Object?>>()
              .map((operation) => operation['kind']);
      expect(capabilityKinds, contains('analyze.workspace'));
      expect(
        await File(
          CockpitHomePaths(environment['COCKPIT_HOME']!).daemonLog,
        ).readAsString(),
        isNot(contains('Workspace worker started.')),
      );
      final cases = await _runAotCli(executable, environment, <String>[
        'case',
        'list',
        '--workspace-id',
        workspaceId,
      ]);
      expect(cases['items'], isEmpty);

      final beforePreservingStart = await Process.run(
        executable,
        const <String>['daemon', 'status', '--format', 'json'],
        environment: environment,
      );
      expect(beforePreservingStart.exitCode, 0);
      final beforePreservingStartJson =
          jsonDecode('${beforePreservingStart.stdout}') as Map<String, Object?>;
      final preservingStart = await Process.run(executable, const <String>[
        'daemon',
        'start',
        '--format',
        'none',
      ], environment: environment);
      expect(
        preservingStart.exitCode,
        0,
        reason: '${preservingStart.stdout}\n${preservingStart.stderr}',
      );
      final afterPreservingStart = await Process.run(executable, const <String>[
        'daemon',
        'status',
        '--format',
        'json',
      ], environment: environment);
      expect(afterPreservingStart.exitCode, 0);
      final afterPreservingStartJson =
          jsonDecode('${afterPreservingStart.stdout}') as Map<String, Object?>;
      expect(
        afterPreservingStartJson['auth'],
        CockpitAuthorizationMode.yolo.name,
      );
      expect(
        afterPreservingStartJson['processId'],
        beforePreservingStartJson['processId'],
      );

      for (var iteration = 0; iteration < 3; iteration += 1) {
        final stopped = await Process.run(executable, const <String>[
          'daemon',
          'stop',
          '--mode',
          'emergency',
          '--format',
          'none',
        ], environment: environment).timeout(const Duration(seconds: 20));
        expect(
          stopped.exitCode,
          0,
          reason: '${stopped.stdout}\n${stopped.stderr}',
        );
        final restricted = await Process.run(executable, const <String>[
          'daemon',
          'start',
          '--format',
          'none',
        ], environment: environment).timeout(const Duration(seconds: 20));
        expect(
          restricted.exitCode,
          0,
          reason: '${restricted.stdout}\n${restricted.stderr}',
        );

        final concurrent = await Future.wait(<Future<ProcessResult>>[
          Process.run(executable, const <String>[
            'daemon',
            'start',
            '--yolo',
            '--format',
            'none',
          ], environment: environment),
          for (var reader = 0; reader < 8; reader += 1)
            Process.run(executable, const <String>[
              'workspace',
              'list',
              '--format',
              'none',
            ], environment: environment),
        ]).timeout(const Duration(seconds: 30));
        for (final result in concurrent) {
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        }

        final status = await Process.run(executable, const <String>[
          'daemon',
          'status',
          '--format',
          'json',
        ], environment: environment).timeout(const Duration(seconds: 20));
        expect(status.exitCode, 0, reason: '${status.stderr}');
        expect(
          (jsonDecode('${status.stdout}') as Map<String, Object?>)['auth'],
          CockpitAuthorizationMode.yolo.name,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('process start identity is stable across caller locales', () async {
    if (Platform.isWindows) return;
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-process-identity-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final packageLibrary = await Isolate.resolvePackageUri(
      Uri.parse('package:cockpit/cockpit.dart'),
    );
    if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
    final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
    final workspaceRoot = p.dirname(p.dirname(packageRoot));
    final probe = File(p.join(temporary.path, 'probe.dart'));
    await probe.writeAsString('''
import 'dart:io';

import 'package:cockpit/src/supervisor/cockpit_daemon_discovery.dart';

Future<void> main(List<String> arguments) async {
  final identity = await const CockpitSystemProcessIdentityProbe()
      .readStartIdentity(int.parse(arguments.single));
  stdout.write(identity ?? '');
}
''');

    Future<ProcessResult> readIdentity(String locale) => Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(workspaceRoot, '.dart_tool', 'package_config.json')}',
        probe.path,
        '$pid',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'LANG': locale,
        'LC_ALL': locale,
      },
    );

    final localized = await readIdentity('zh_CN.UTF-8');
    final neutral = await readIdentity('C');
    expect(localized.exitCode, 0, reason: '${localized.stderr}');
    expect(neutral.exitCode, 0, reason: '${neutral.stderr}');
    expect('${localized.stdout}', '${neutral.stdout}');
  });

  test('stop completes when the daemon removes its discovery record', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-daemon-stop-discovery-',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final paths = CockpitHomePaths(await temporary.resolveSymbolicLinks());
    final policy = Platform.isWindows
        ? const CockpitWindowsAclPermissionHardener()
        : const CockpitPosixPermissionHardener();
    final syncer = CockpitSystemDirectorySyncer(
      Platform.isWindows
          ? CockpitHostPlatform.windows
          : Platform.isMacOS
          ? CockpitHostPlatform.macos
          : CockpitHostPlatform.linux,
    );
    final store = CockpitDaemonDiscoveryStore(
      paths: paths,
      permissionHardener: policy,
      directorySyncer: syncer,
    );
    final discovery = CockpitDaemonDiscovery(
      instanceId: 'daemon-stop-discovery',
      processId: pid,
      processStartIdentity: await const CockpitSystemProcessIdentityProbe()
          .current(),
      endpoint: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      ),
      bearerToken: List<String>.filled(32, 'a').join(),
      apiMajor: 2,
      apiMinor: 0,
      engineVersion: 'test',
      startedAt: DateTime.now().toUtc(),
    );
    await store.write(discovery);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      await store.deleteIfMatches(discovery);
    });
    final lifecycle = CockpitDaemonLifecycleClient(
      paths: paths,
      executable: Platform.resolvedExecutable,
      daemonArguments: const <String>['unused'],
      restartArguments: const <String>['unused'],
      permissionHardener: policy,
      directorySyncer: syncer,
      requiredEngineVersion: 'test',
    );

    final stopwatch = Stopwatch()..start();
    await lifecycle.stop(timeout: const Duration(seconds: 5));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(await File(paths.daemonDiscovery).exists(), isFalse);
  });

  test('daemon lifecycle lock respects the requested timeout', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-daemon-lock-timeout-',
    );
    final paths = CockpitHomePaths(await temporary.resolveSymbolicLinks());
    final ready = File(p.join(temporary.path, 'ready'));
    final release = File(p.join(temporary.path, 'release'));
    final packageLibrary = await Isolate.resolvePackageUri(
      Uri.parse('package:cockpit/cockpit.dart'),
    );
    if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
    final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
    final holder = await Process.start(Platform.resolvedExecutable, <String>[
      p.join(
        packageRoot,
        'test',
        'src',
        'supervisor',
        'cockpit_daemon_lock_holder.dart',
      ),
      paths.daemonEnsureLock,
      ready.path,
      release.path,
    ]);
    addTearDown(() async {
      await release.writeAsString('release');
      await holder.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          holder.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final readyDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (!await ready.exists() && DateTime.now().isBefore(readyDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await ready.exists(), isTrue);

    final policy = Platform.isWindows
        ? const CockpitWindowsAclPermissionHardener()
        : const CockpitPosixPermissionHardener();
    final lifecycle = CockpitDaemonLifecycleClient(
      paths: paths,
      executable: Platform.resolvedExecutable,
      daemonArguments: const <String>['unused'],
      restartArguments: const <String>['unused'],
      permissionHardener: policy,
      directorySyncer: CockpitSystemDirectorySyncer(
        Platform.isWindows
            ? CockpitHostPlatform.windows
            : Platform.isMacOS
            ? CockpitHostPlatform.macos
            : CockpitHostPlatform.linux,
      ),
      requiredEngineVersion: 'test',
    );
    final stopwatch = Stopwatch()..start();
    await expectLater(
      lifecycle.ensure(timeout: const Duration(milliseconds: 150)),
      throwsA(
        isA<CockpitDaemonException>().having(
          (error) => error.code,
          'code',
          'daemonTimeout',
        ),
      ),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test(
    'ensure replaces an older engine and preserves authorization',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpitd-engine-upgrade-',
      );
      final paths = CockpitHomePaths(await temporary.resolveSymbolicLinks());
      final policy = Platform.isWindows
          ? const CockpitWindowsAclPermissionHardener()
          : const CockpitPosixPermissionHardener();
      final syncer = CockpitSystemDirectorySyncer(
        Platform.isWindows
            ? CockpitHostPlatform.windows
            : Platform.isMacOS
            ? CockpitHostPlatform.macos
            : CockpitHostPlatform.linux,
      );
      final store = CockpitDaemonDiscoveryStore(
        paths: paths,
        permissionHardener: policy,
        directorySyncer: syncer,
      );
      final oldServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final startedAt = DateTime.now().toUtc();
      final oldDiscovery = CockpitDaemonDiscovery(
        instanceId: 'daemon-old-engine',
        processId: pid,
        processStartIdentity: await const CockpitSystemProcessIdentityProbe()
            .current(),
        endpoint: Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: oldServer.port,
        ),
        bearerToken: List<String>.filled(32, 'o').join(),
        apiMajor: 2,
        apiMinor: 0,
        engineVersion: '3.0.4',
        startedAt: startedAt,
        authorizationMode: CockpitAuthorizationMode.yolo,
      );
      await store.write(oldDiscovery);
      var shutdownCount = 0;
      oldServer.listen((request) async {
        if (request.uri.path == '/_cockpit/health') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              CockpitServerInfo(
                instanceId: oldDiscovery.instanceId,
                apiVersion: CockpitApiVersion(major: 2, minor: 0),
                engineVersion: oldDiscovery.engineVersion,
                startedAt: startedAt,
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/_cockpit/lifecycle') {
          await request.drain<void>();
          shutdownCount += 1;
          request.response.statusCode = HttpStatus.accepted;
          await request.response.close();
          await store.deleteIfMatches(oldDiscovery);
          await oldServer.close(force: true);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:cockpit/cockpit.dart'),
      );
      if (packageLibrary == null) throw StateError('Cannot resolve cockpit.');
      final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
      final lifecycle = CockpitDaemonLifecycleClient(
        paths: paths,
        executable: Platform.resolvedExecutable,
        daemonArguments: <String>[p.join(packageRoot, 'bin', 'cockpitd.dart')],
        restartArguments: <String>[p.join(packageRoot, 'bin', 'cockpit.dart')],
        permissionHardener: policy,
        directorySyncer: syncer,
        requiredEngineVersion: cockpitVersion,
      );
      addTearDown(() async {
        try {
          await lifecycle.stop(
            mode: CockpitDaemonShutdownMode.emergency,
            timeout: const Duration(seconds: 5),
          );
        } on Object {
          // The assertion failure remains primary; the process timeout is bounded.
        }
        await oldServer.close(force: true);
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      expect((await lifecycle.status()).diagnostic, 'upgradeRequired');

      final upgraded = await lifecycle.ensure(
        timeout: const Duration(seconds: 20),
      );

      expect(shutdownCount, 1);
      expect(upgraded.instanceId, isNot(oldDiscovery.instanceId));
      expect(upgraded.engineVersion, cockpitVersion);
      expect(upgraded.authorizationMode, CockpitAuthorizationMode.yolo);
      expect((await lifecycle.status()).diagnostic, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

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
        executable: Platform.resolvedExecutable,
        daemonArguments: <String>[daemonEntrypoint],
        restartArguments: <String>[p.join(packageRoot, 'bin', 'cockpit.dart')],
        permissionHardener: policy,
        directorySyncer: CockpitSystemDirectorySyncer(
          Platform.isWindows
              ? CockpitHostPlatform.windows
              : Platform.isMacOS
              ? CockpitHostPlatform.macos
              : CockpitHostPlatform.linux,
        ),
        requiredEngineVersion: cockpitVersion,
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
      await lifecycle.scheduleRestart();
      final restarted = await _waitForReplacement(
        lifecycle,
        previousProcessId: yolo.processId,
      );
      expect(restarted.authorizationMode, CockpitAuthorizationMode.yolo);
      final staleDiscovery = await _waitForDiscovery(paths);
      await lifecycle.stop(mode: CockpitDaemonShutdownMode.emergency);
      await _waitForProcessExit(staleDiscovery);
      await CockpitDaemonDiscoveryStore(
        paths: paths,
        permissionHardener: policy,
        directorySyncer: CockpitSystemDirectorySyncer(
          Platform.isWindows
              ? CockpitHostPlatform.windows
              : Platform.isMacOS
              ? CockpitHostPlatform.macos
              : CockpitHostPlatform.linux,
        ),
      ).write(staleDiscovery);
      expect((await lifecycle.status()).diagnostic, 'staleDiscovery');
      final restartedFromStale = await lifecycle.restart(
        authorizationMode: CockpitAuthorizationMode.yolo,
      );
      expect(
        restartedFromStale.authorizationMode,
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

Future<Map<String, Object?>> _runAotCli(
  String executable,
  Map<String, String> environment,
  List<String> arguments,
) async {
  final result = await Process.run(executable, <String>[
    ...arguments,
    '--format',
    'json',
    '--view',
    'full',
  ], environment: environment).timeout(const Duration(seconds: 30));
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return Map<String, Object?>.from(
    jsonDecode('${result.stdout}'.trim()) as Map<Object?, Object?>,
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

Future<CockpitDaemonStatus> _waitForReplacement(
  CockpitDaemonLifecycleClient lifecycle, {
  required int previousProcessId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final status = await lifecycle.status();
    if (status.healthy && status.processId != previousProcessId) return status;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Detached restart did not publish a healthy replacement.');
}

Future<void> _waitForProcessExit(CockpitDaemonDiscovery discovery) async {
  const probe = CockpitSystemProcessIdentityProbe();
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final identity = await probe.readStartIdentity(discovery.processId);
    if (identity != discovery.processStartIdentity) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Stopped cockpitd process did not exit.');
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
