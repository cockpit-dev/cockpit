import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:cockpit/src/development/cockpit_flutter_run_machine_client.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/worker/cockpit_worker_development_session_runtime.dart';
import 'package:test/test.dart';

void main() {
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
      final runtime = CockpitWorkerDevelopmentSessionRuntime(
        machineClientAttacher: (handle) async {
          attachCalls += 1;
          stdoutController
            ..add('[{"event":"app.start","params":{"appId":"attached-app"}}]')
            ..add(
              '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:61234/direct/ws"}}]',
            );
          await Future<void>.delayed(Duration.zero);
          return machineClient;
        },
      );

      final remote = CockpitRemoteSessionHandle(
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/example',
        target: 'cockpit/main.dart',
        appId: 'old-machine-app',
        platformAppId: 'dev.example.app',
        processId: 4242,
        host: '127.0.0.1',
        hostPort: server.port,
        devicePort: server.port,
        baseUrl: 'http://127.0.0.1:${server.port}',
        launchedAt: DateTime.utc(2026, 8, 7),
      );
      final handle = CockpitDevelopmentSessionHandle(
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
      );

      final recovered = await runtime.query(handle);
      expect(recovered.status.state, CockpitDevelopmentSessionState.ready);
      expect(recovered.handle.appId, 'attached-app');
      expect(recovered.handle.remoteSessionHandle?.appId, 'attached-app');
      expect(attachCalls, 1);

      final reloaded = await runtime.reload(
        recovered.handle,
        CockpitDevelopmentReloadMode.hotReload,
      );
      expect(reloaded.status.state, CockpitDevelopmentSessionState.ready);
      expect(reloaded.handle.reloadGeneration, 4);
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
    },
  );
}
