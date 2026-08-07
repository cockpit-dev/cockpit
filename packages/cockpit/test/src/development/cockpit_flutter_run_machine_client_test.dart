import 'dart:async';
import 'dart:io';

import 'package:cockpit/src/development/cockpit_flutter_run_machine_client.dart';
import 'package:cockpit/src/development/cockpit_flutter_run_machine_event.dart';
import 'package:test/test.dart';

void main() {
  test(
    'machine output lines map to typed events and capture VM service URI',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final writes = <String>[];

      final client = CockpitFlutterRunMachineClient(
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
        if (!exitCode.isCompleted) {
          exitCode.complete(0);
        }
        await client.dispose();
      });

      final events = <CockpitFlutterRunMachineEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);

      stdoutController
        ..add('[{"event":"daemon.connected","params":{"pid":123}}]')
        ..add('[{"event":"app.start","params":{"appId":"app-1"}}]')
        ..add(
          '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:34567/abcd/ws"}}]',
        );

      await Future<void>.delayed(Duration.zero);

      expect(
        events.map((event) => event.kind),
        containsAll(<Object?>[
          CockpitFlutterRunMachineEventKind.daemonConnected,
          CockpitFlutterRunMachineEventKind.appStart,
          CockpitFlutterRunMachineEventKind.appDebugPort,
        ]),
      );
      expect(client.currentAppId, 'app-1');
      expect(
        await client.vmServiceUri,
        Uri.parse('ws://127.0.0.1:34567/abcd/ws'),
      );
      expect(writes, isEmpty);
    },
  );

  test('hot reload success and failure are distinguishable', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();
    final writes = <String>[];

    final client = CockpitFlutterRunMachineClient(
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
      if (!exitCode.isCompleted) {
        exitCode.complete(0);
      }
      await client.dispose();
    });

    final successFuture = client.hotReload(appId: 'app-1');
    await Future<void>.delayed(Duration.zero);
    expect(writes.single, contains('"method":"app.restart"'));
    expect(writes.single, contains('"fullRestart":false'));
    stdoutController.add('[{"id":0,"result":{"code":0,"message":"ok"}}]');
    final successResult = await successFuture;
    expect(successResult, <String, Object?>{'code': 0, 'message': 'ok'});

    final failureFuture = client.hotRestart(appId: 'app-1');
    await Future<void>.delayed(Duration.zero);
    stdoutController.add('[{"id":1,"error":"hot restart failed"}]');
    await expectLater(
      failureFuture,
      throwsA(
        isA<CockpitFlutterRunMachineRequestException>().having(
          (error) => error.message,
          'message',
          contains('hot restart failed'),
        ),
      ),
    );
  });

  test('stderr and exit become structured events', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();

    final client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (_) async {},
    );
    addTearDown(() async {
      await stdoutController.close();
      await stderrController.close();
      if (!exitCode.isCompleted) {
        exitCode.complete(0);
      }
      await client.dispose();
    });

    final events = <CockpitFlutterRunMachineEvent>[];
    final subscription = client.events.listen(events.add);
    addTearDown(subscription.cancel);

    stderrController.add('Lost connection to device');
    exitCode.complete(1);
    await Future<void>.delayed(Duration.zero);

    expect(
      events.map((event) => event.kind),
      containsAll(<Object?>[
        CockpitFlutterRunMachineEventKind.stderr,
        CockpitFlutterRunMachineEventKind.processExit,
      ]),
    );
    expect(events.last.exitCode, 1);
  });

  test('machine progress and daemon log messages expose params text', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();

    final client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (_) async {},
    );
    addTearDown(() async {
      await stdoutController.close();
      await stderrController.close();
      if (!exitCode.isCompleted) {
        exitCode.complete(0);
      }
      await client.dispose();
    });

    final events = <CockpitFlutterRunMachineEvent>[];
    final subscription = client.events.listen(events.add);
    addTearDown(subscription.cancel);

    stdoutController
      ..add(
        '[{"event":"app.progress","params":{"message":"Building Windows application..."}}]',
      )
      ..add(
        '[{"event":"daemon.logMessage","params":{"level":"status","message":"Launching lib/main.dart on Windows..."}}]',
      );
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .where(
            (event) =>
                event.kind == CockpitFlutterRunMachineEventKind.appProgress,
          )
          .single
          .message,
      'Building Windows application...',
    );
    expect(
      events
          .where(
            (event) =>
                event.kind ==
                CockpitFlutterRunMachineEventKind.daemonLogMessage,
          )
          .single
          .message,
      'Launching lib/main.dart on Windows...',
    );
  });

  test('non-machine stdout lines are retained in recent diagnostics', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();

    final client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (_) async {},
    );
    addTearDown(() async {
      await stdoutController.close();
      await stderrController.close();
      if (!exitCode.isCompleted) {
        exitCode.complete(0);
      }
      await client.dispose();
    });

    stdoutController.add(
      'flutter_cockpit remote session startup failed: SocketException',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      client.recentDiagnosticSummary,
      contains('flutter_cockpit remote session startup failed'),
    );
  });

  test('dispose runs the owned process shutdown hook', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();
    var disposeCalled = 0;

    final client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (_) async {},
      closeProcess: () async {
        disposeCalled += 1;
      },
    );

    await stdoutController.close();
    await stderrController.close();
    exitCode.complete(0);
    await client.dispose();

    expect(disposeCalled, 1);
  });

  test('detach preserves the app and abandons the owned process', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();
    final writes = <String>[];
    var closeProcessCalls = 0;
    final client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (payload) async {
        writes.add(payload);
      },
      closeProcess: () async {
        closeProcessCalls += 1;
      },
    );

    final detachFuture = client.detach(appId: 'app-1');
    await Future<void>.delayed(Duration.zero);
    expect(writes.single, contains('"method":"app.detach"'));
    expect(writes.single, contains('"appId":"app-1"'));
    stdoutController.add('[{"id":0,"result":true}]');
    expect(await detachFuture, isTrue);

    await client.dispose(terminateProcess: false);
    expect(closeProcessCalls, 0);
    await stdoutController.close();
    await stderrController.close();
    exitCode.complete(0);
  });

  test('dispose does not hang on a stuck shutdown hook', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();

    final client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (_) async {},
      closeProcess: () => Completer<void>().future,
    );

    await stdoutController.close();
    await stderrController.close();
    exitCode.complete(0);

    final stopwatch = Stopwatch()..start();
    await client.dispose();
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test(
    'fails immediately when a request is sent after the machine exits',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();

      final client = CockpitFlutterRunMachineClient(
        stdoutLines: stdoutController.stream,
        stderrLines: stderrController.stream,
        exitCode: exitCode.future,
        requestWriter: (_) async {},
      );
      addTearDown(() async {
        await stdoutController.close();
        await stderrController.close();
        await client.dispose();
      });

      stderrController.add('Lost connection to device');
      exitCode.complete(1);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        client.hotReload(appId: 'app-1'),
        throwsA(
          isA<CockpitFlutterRunMachineRequestException>().having(
            (error) => error.message,
            'message',
            contains('exitCode=1'),
          ),
        ),
      );
    },
  );

  test(
    'completes request errors when the writer throws before sending',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();

      final client = CockpitFlutterRunMachineClient(
        stdoutLines: stdoutController.stream,
        stderrLines: stderrController.stream,
        exitCode: exitCode.future,
        requestWriter: (_) async {
          throw const SocketException('stdin closed');
        },
      );
      addTearDown(() async {
        await stdoutController.close();
        await stderrController.close();
        if (!exitCode.isCompleted) {
          exitCode.complete(0);
        }
        await client.dispose();
      });

      await expectLater(
        client.stop(appId: 'app-1'),
        throwsA(isA<SocketException>()),
      );
    },
  );
}
