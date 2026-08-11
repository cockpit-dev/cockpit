import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_launch_development_session_service.dart';
import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_machine_launcher.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:cockpit/src/development/cockpit_flutter_run_machine_client.dart';
import 'package:cockpit/src/development/cockpit_vm_network_profiler.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/worker/cockpit_worker_development_session_runtime.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('launch exposes the Flutter machine failure', () async {
    final project = await Directory.systemTemp.createTemp(
      'cockpit-worker-launch-failure-',
    );
    addTearDown(() => project.delete(recursive: true));
    final entrypoint = File(p.join(project.path, 'cockpit', 'main.dart'));
    await entrypoint.parent.create(recursive: true);
    await entrypoint.writeAsString('void main() {}');

    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();
    final machineClient = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (_) async {},
    );
    addTearDown(() async {
      await stdoutController.close();
      await stderrController.close();
      if (!exitCode.isCompleted) exitCode.complete(0);
      await machineClient.dispose(terminateProcess: false);
    });
    Map<String, String>? launchEnvironment;
    final launcher = CockpitDevelopmentSessionMachineLauncher(
      machineClientStarter:
          ({
            required projectDir,
            required target,
            required deviceId,
            flavor,
            flutterExecutable,
            extraArgs = const <String>[],
            environment,
          }) async {
            launchEnvironment = environment;
            scheduleMicrotask(() {
              stderrController.add(
                'Did not find the file passed to '
                '"--dart-define-from-file".',
              );
              exitCode.complete(1);
            });
            return machineClient;
          },
    );
    final runtime = CockpitWorkerDevelopmentSessionRuntime(
      appTempStore: _appTempStore(project),
      machineLauncher: launcher,
      flutterVersionReader: (_) async => '3.32.0',
    );

    await expectLater(
      runtime.launch(
        CockpitLaunchDevelopmentSessionRequest(
          projectDir: project.path,
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
        ),
      ),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having((error) => error.code, 'code', 'flutterLaunchFailed')
            .having(
              (error) => error.message,
              'message',
              contains('Did not find the file passed to'),
            ),
      ),
    );
    final appTempPath = launchEnvironment!['TMPDIR']!;
    expect(launchEnvironment!['TMP'], appTempPath);
    expect(launchEnvironment!['TEMP'], appTempPath);
    expect(await Directory(appTempPath).exists(), isFalse);
  });

  test(
    'runtime recovers a persisted session and detaches without stopping it',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSubscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'ok': true,
            if (request.uri.path == '/ready')
              'ready': true
            else
              'path': request.uri.path,
          }),
        );
        await request.response.close();
      });
      addTearDown(() async {
        await serverSubscription.cancel();
        await server.close(force: true);
      });

      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final writes = <String>[];
      var closeProcessCalls = 0;
      late final CockpitFlutterRunMachineClient machineClient;
      machineClient = CockpitFlutterRunMachineClient(
        stdoutLines: stdoutController.stream,
        stderrLines: stderrController.stream,
        exitCode: exitCode.future,
        requestWriter: (payload) async {
          writes.add(payload);
          final request = Map<String, Object?>.from(
            (jsonDecode(payload.trim()) as List<Object?>).single!
                as Map<Object?, Object?>,
          );
          final method = request['method'];
          final result = method == 'app.detach'
              ? true
              : <String, Object?>{'code': 0};
          scheduleMicrotask(() {
            stdoutController.add(
              jsonEncode(<Object?>[
                <String, Object?>{'id': request['id'], 'result': result},
              ]),
            );
          });
        },
        closeProcess: () async {
          closeProcessCalls += 1;
        },
      );
      addTearDown(() async {
        await stdoutController.close();
        await stderrController.close();
        if (!exitCode.isCompleted) exitCode.complete(0);
        await machineClient.dispose(terminateProcess: false);
      });

      var attachCalls = 0;
      Map<String, String>? attachEnvironment;
      final runtimeRoot = await Directory.systemTemp.createTemp(
        'cockpit-worker-recovery-',
      );
      addTearDown(() => runtimeRoot.delete(recursive: true));
      final networkProfiler = _RecordingNetworkProfiler();
      final runtime = CockpitWorkerDevelopmentSessionRuntime(
        appTempStore: _appTempStore(runtimeRoot),
        networkProfiler: networkProfiler,
        machineClientAttacher: (handle, environment) async {
          attachCalls += 1;
          attachEnvironment = environment;
          stdoutController.add(
            '[{"event":"app.start","params":{"appId":"attached-app"}}]',
          );
          await Future<void>.delayed(Duration.zero);
          return machineClient;
        },
      );

      final handle = _persistedHandle(port: server.port);

      final recovered = await runtime.query(handle);
      expect(recovered.status.state, CockpitDevelopmentSessionState.ready);
      expect(recovered.handle.appId, 'old-machine-app');
      expect(recovered.handle.remoteSessionHandle?.appId, 'old-machine-app');
      expect(attachCalls, 0);
      expect(networkProfiler.enableCalls, <String>[
        'ds-persisted@ws://127.0.0.1:61234/direct/ws',
      ]);

      final reloadFuture = runtime.reload(
        recovered.handle,
        CockpitDevelopmentReloadMode.hotReload,
      );
      while (attachCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      expect(
        writes.any((payload) => payload.contains('"method":"app.restart"')),
        isFalse,
      );
      stdoutController.add('[{"event":"app.started","params":{}}]');
      await Future<void>.delayed(Duration.zero);
      expect(
        writes.any((payload) => payload.contains('"method":"app.restart"')),
        isTrue,
      );
      final reloaded = await reloadFuture;
      expect(attachCalls, 1);
      expect(reloaded.handle.appId, 'attached-app');
      expect(reloaded.handle.remoteSessionHandle?.appId, 'attached-app');
      expect(reloaded.status.state, CockpitDevelopmentSessionState.ready);
      expect(reloaded.handle.reloadGeneration, 4);
      final appTempPath = attachEnvironment!['TMPDIR']!;
      expect(attachEnvironment!['TMP'], appTempPath);
      expect(attachEnvironment!['TEMP'], appTempPath);
      expect(await Directory(appTempPath).exists(), isTrue);
      expect(
        writes.any((payload) => payload.contains('"method":"app.restart"')),
        isTrue,
      );

      await runtime.dispose();
      expect(
        writes.any((payload) => payload.contains('"method":"app.detach"')),
        isTrue,
      );
      expect(closeProcessCalls, 1);
      expect(await Directory(appTempPath).exists(), isTrue);
    },
  );

  test(
    'recovered custom launch blocks reload without touching the app',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSubscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'ok': true,
            if (request.uri.path == '/ready')
              'ready': true
            else
              'path': request.uri.path,
          }),
        );
        await request.response.close();
      });
      addTearDown(() async {
        await serverSubscription.cancel();
        await server.close(force: true);
      });

      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final writes = <String>[];
      final machineClient = CockpitFlutterRunMachineClient(
        stdoutLines: stdoutController.stream,
        stderrLines: stderrController.stream,
        exitCode: exitCode.future,
        requestWriter: (payload) async {
          writes.add(payload);
        },
      );
      addTearDown(() async {
        await stdoutController.close();
        await stderrController.close();
        if (!exitCode.isCompleted) exitCode.complete(0);
        await machineClient.dispose(terminateProcess: false);
      });

      final runtimeRoot = await Directory.systemTemp.createTemp(
        'cockpit-worker-custom-recovery-',
      );
      addTearDown(() => runtimeRoot.delete(recursive: true));
      final runtime = CockpitWorkerDevelopmentSessionRuntime(
        appTempStore: _appTempStore(runtimeRoot),
        machineClientAttacher: (handle, _) async {
          stdoutController.add(
            '[{"event":"app.start","params":{"appId":"attached-app"}}]',
          );
          await Future<void>.delayed(Duration.zero);
          return machineClient;
        },
      );

      final recovered = await runtime.query(
        _persistedHandle(port: server.port, reloadRecoverable: false),
      );
      expect(recovered.status.state, CockpitDevelopmentSessionState.ready);

      await expectLater(
        runtime.reload(
          recovered.handle,
          CockpitDevelopmentReloadMode.hotRestart,
        ),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'reloadNeedsRelaunch')
              .having(
                (error) => error.message,
                'message',
                contains('original custom launch values'),
              ),
        ),
      );
      expect(writes, isEmpty);
      expect(
        (await runtime.query(recovered.handle)).status.state,
        CockpitDevelopmentSessionState.ready,
      );
    },
  );
}

CockpitAppTempStore _appTempStore(Directory root) => CockpitAppTempStore(
  root: p.join(root.path, 'app-temp'),
  permissionHardener: const _NoopPermissionHardener(),
);

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class _RecordingNetworkProfiler implements CockpitNetworkProfiler {
  final List<String> enableCalls = <String>[];

  @override
  Future<void> enable({
    required String sessionId,
    required Uri vmServiceUri,
  }) async {
    enableCalls.add('$sessionId@$vmServiceUri');
  }

  @override
  Future<CockpitVmNetworkBodies> readBodies({
    required String sessionId,
    required Uri vmServiceUri,
    required CockpitNetworkEntry entry,
  }) => throw UnimplementedError();
}

CockpitDevelopmentSessionHandle _persistedHandle({
  required int port,
  bool reloadRecoverable = true,
}) {
  final remote = CockpitRemoteSessionHandle(
    platform: 'macos',
    deviceId: 'macos',
    projectDir: '/workspace/example',
    target: 'cockpit/main.dart',
    appId: 'old-machine-app',
    platformAppId: 'dev.example.app',
    processId: 4242,
    host: '127.0.0.1',
    hostPort: port,
    devicePort: port,
    baseUrl: 'http://127.0.0.1:$port',
    launchedAt: DateTime.utc(2026, 8, 7),
  );
  return CockpitDevelopmentSessionHandle(
    developmentSessionId: 'ds-persisted',
    platform: 'macos',
    deviceId: 'macos',
    projectDir: '/workspace/example',
    target: 'cockpit/main.dart',
    appId: 'old-machine-app',
    appBaseUrl: remote.baseUrl,
    supervisorBaseUrl: 'cockpit-worker://development/ds-persisted',
    remoteSessionHandle: remote,
    vmServiceUri: Uri.parse('ws://127.0.0.1:61234/direct/ws'),
    launchedAt: DateTime.utc(2026, 8, 7),
    reloadGeneration: 3,
    reloadRecoverable: reloadRecoverable,
  );
}
