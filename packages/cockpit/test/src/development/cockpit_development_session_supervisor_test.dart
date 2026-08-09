import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:cockpit/src/development/cockpit_development_session_supervisor.dart';
import 'package:cockpit/src/development/cockpit_development_session_supervisor_client.dart';
import 'package:cockpit/src/development/cockpit_flutter_run_machine_client.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test(
    'supervisor exposes a starting control plane before remote launch completes',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var connectorCalls = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle.copyWith(
          appId: '',
          remoteSessionHandle: null,
        ),
        machineClient: null,
        machineClientConnector: () async {
          connectorCalls += 1;
          return harness.client;
        },
        remoteReachabilityProbe: (_) async => true,
        now: () => DateTime.utc(2026, 3, 23, 2, 30),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final healthRequest = await client.getUrl(
        (await supervisor.currentHandle()).supervisorBaseUri.resolve('/health'),
      );
      final healthResponse = await healthRequest.close();
      final healthPayload =
          jsonDecode(await utf8.decoder.bind(healthResponse).join())
              as Map<String, Object?>;
      expect(
        healthPayload['state'],
        CockpitDevelopmentSessionState.starting.jsonValue,
      );
      expect(connectorCalls, 0);

      await supervisor.bindRemoteSession(harness.handle.remoteSessionHandle!);
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      expect(connectorCalls, 0);
      final currentHandle = await supervisor.currentHandle();
      expect(currentHandle.appId, '');
      expect(
        currentHandle.remoteSessionHandle?.baseUrl,
        harness.handle.remoteSessionHandle?.baseUrl,
      );
    },
  );

  test(
    'supervisor clears stale lastError after bind and ready recovery',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle.copyWith(
          appId: '',
          remoteSessionHandle: null,
        ),
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        now: () => DateTime.utc(2026, 3, 23, 2, 30),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      supervisor.reportStartupFailure(StateError('stale startup failure'));

      final failedStatus = await supervisor.currentStatus();
      expect(failedStatus.state, CockpitDevelopmentSessionState.failed);
      expect(failedStatus.lastError, contains('stale startup failure'));

      await supervisor.bindRemoteSession(harness.handle.remoteSessionHandle!);
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final recoveredStatus = await supervisor.currentStatus();
      expect(recoveredStatus.state, CockpitDevelopmentSessionState.ready);
      expect(recoveredStatus.lastError, isNull);
    },
  );

  test(
    'supervisor does not settle startup from machine app events before remote session is bound',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var remoteChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle.copyWith(
          appId: '',
          remoteSessionHandle: null,
        ),
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          remoteChecks += 1;
          return true;
        },
        now: () => DateTime.utc(2026, 3, 23, 2, 30),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final pendingStatus = await supervisor.currentStatus();
      expect(pendingStatus.state, CockpitDevelopmentSessionState.starting);
      expect(remoteChecks, 0);

      await supervisor.bindRemoteSession(harness.handle.remoteSessionHandle!);
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      expect(remoteChecks, greaterThanOrEqualTo(1));
    },
  );

  test(
    'supervisor transitions to ready after stable remote recovery',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var remoteChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          remoteChecks += 1;
          return true;
        },
        now: () => DateTime.utc(2026, 3, 23, 3),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      expect(
        (await supervisor.currentStatus()).state,
        CockpitDevelopmentSessionState.starting,
      );

      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final status = await supervisor.currentStatus();
      expect(status.state, CockpitDevelopmentSessionState.ready);
      expect(status.appReachable, isTrue);
      expect(status.remoteSessionReachable, isTrue);
      expect(remoteChecks, greaterThanOrEqualTo(2));
    },
  );

  test(
    'supervisor can settle to ready from app.start when app.started is absent',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var remoteChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          remoteChecks += 1;
          return remoteChecks >= 2;
        },
        now: () => DateTime.utc(2026, 3, 23, 3),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );

      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final status = await supervisor.currentStatus();
      expect(status.state, CockpitDevelopmentSessionState.ready);
      expect(status.appReachable, isTrue);
      expect(status.remoteSessionReachable, isTrue);
      expect(remoteChecks, greaterThanOrEqualTo(2));
    },
  );

  test(
    'supervisor keeps polling after app.started until remote session becomes ready',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var remoteChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          remoteChecks += 1;
          return remoteChecks >= 3;
        },
        now: () => DateTime.utc(2026, 3, 23, 3),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');

      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final status = await supervisor.currentStatus();
      expect(status.state, CockpitDevelopmentSessionState.ready);
      expect(remoteChecks, greaterThanOrEqualTo(3));
    },
  );

  test(
    'supervisor does not report ready until remote control readiness is stable',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var reachabilityChecks = 0;
      var readinessChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          reachabilityChecks += 1;
          return true;
        },
        remoteControlReadinessProbe: (_) async {
          readinessChecks += 1;
          return readinessChecks >= 3;
        },
        now: () => DateTime.utc(2026, 3, 23, 3),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');

      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final status = await supervisor.currentStatus();
      expect(status.state, CockpitDevelopmentSessionState.ready);
      expect(status.appReachable, isTrue);
      expect(status.remoteSessionReachable, isTrue);
      expect(reachabilityChecks, greaterThanOrEqualTo(3));
      expect(readinessChecks, greaterThanOrEqualTo(4));
    },
  );

  test(
    'supervisor can become ready before attach and lazily connect on reload',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var connectorCalls = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: null,
        machineClientConnector: () async {
          connectorCalls += 1;
          return harness.client;
        },
        remoteReachabilityProbe: (_) async => true,
        now: () => DateTime.utc(2026, 3, 23, 3),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);
      expect(connectorCalls, 0);

      final reloadFuture = supervisor.reload(
        CockpitDevelopmentReloadMode.hotReload,
      );
      await Future<void>.delayed(Duration.zero);
      expect(connectorCalls, 1);
      expect(harness.writes.last, contains('"fullRestart":false'));
      harness.stdoutController.add('[{"id":0,"result":{"code":0}}]');
      final reloadedStatus = await reloadFuture;

      expect(reloadedStatus.state, CockpitDevelopmentSessionState.ready);
      expect(
        reloadedStatus.lastReloadMode,
        CockpitDevelopmentReloadMode.hotReload,
      );
    },
  );

  test('hot reload reports ready after remote reachability recovers', () async {
    final harness = _MachineHarness();
    addTearDown(harness.dispose);

    var now = DateTime.utc(2026, 3, 23, 3);
    var remoteChecks = 0;

    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: harness.handle,
      machineClient: harness.client,
      remoteReachabilityProbe: (_) async {
        remoteChecks += 1;
        return true;
      },
      now: () {
        final current = now;
        now = now.add(const Duration(milliseconds: 250));
        return current;
      },
      settleTimeout: const Duration(seconds: 2),
      settlePollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(supervisor.dispose);

    await supervisor.start();
    harness.stdoutController.add(
      '[{"event":"app.start","params":{"appId":"app-1"}}]',
    );
    harness.stdoutController.add('[{"event":"app.started","params":{}}]');
    await supervisor.bindRemoteSession(harness.handle.remoteSessionHandle!);
    await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

    final reloadFuture = supervisor.reload(
      CockpitDevelopmentReloadMode.hotReload,
    );
    await Future<void>.delayed(Duration.zero);
    expect(harness.writes.last, contains('"fullRestart":false'));
    harness.stdoutController.add('[{"id":0,"result":{"code":0}}]');

    final reloadedStatus = await reloadFuture;
    expect(reloadedStatus.state, CockpitDevelopmentSessionState.ready);
    expect(reloadedStatus.lastReloadSucceeded, isTrue);
    expect(remoteChecks, greaterThanOrEqualTo(2));
    expect(
      reloadedStatus.lastReloadMode,
      CockpitDevelopmentReloadMode.hotReload,
    );
  });

  test('rejected hot reload keeps a healthy session ready', () async {
    final harness = _MachineHarness();
    addTearDown(harness.dispose);

    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: harness.handle,
      machineClient: harness.client,
      remoteReachabilityProbe: (_) async => true,
      settlePollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(supervisor.dispose);

    await supervisor.start();
    harness.stdoutController.add(
      '[{"event":"app.start","params":{"appId":"app-1"}}]',
    );
    harness.stdoutController.add('[{"event":"app.started","params":{}}]');
    await supervisor.bindRemoteSession(harness.handle.remoteSessionHandle!);
    await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

    final generation = (await supervisor.currentStatus()).reloadGeneration;
    final reloadFuture = supervisor.reload(
      CockpitDevelopmentReloadMode.hotReload,
    );
    await Future<void>.delayed(Duration.zero);
    harness.stdoutController.add(
      '[{"id":0,"result":{"code":1,"message":"restart required"}}]',
    );

    await expectLater(
      reloadFuture,
      throwsA(
        isA<CockpitFlutterRunMachineRequestException>().having(
          (error) => error.message,
          'message',
          contains('restart required'),
        ),
      ),
    );
    final status = await supervisor.currentStatus();
    expect(status.state, CockpitDevelopmentSessionState.ready);
    expect(status.appReachable, isTrue);
    expect(status.remoteSessionReachable, isTrue);
    expect(status.reloadGeneration, generation);
    expect(status.lastReloadMode, CockpitDevelopmentReloadMode.hotReload);
    expect(status.lastReloadSucceeded, isFalse);
    expect(status.lastError, contains('restart required'));
  });

  test('startup readiness does not depend on UI idle commands', () async {
    final harness = _MachineHarness();
    addTearDown(harness.dispose);

    var now = DateTime.utc(2026, 3, 23, 3);
    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: harness.handle,
      machineClient: harness.client,
      remoteReachabilityProbe: (_) async => true,
      now: () {
        final current = now;
        now = now.add(const Duration(milliseconds: 250));
        return current;
      },
      settleTimeout: const Duration(seconds: 2),
      settlePollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(supervisor.dispose);

    await supervisor.start();
    harness.stdoutController.add(
      '[{"event":"app.start","params":{"appId":"app-1"}}]',
    );
    harness.stdoutController.add('[{"event":"app.started","params":{}}]');

    await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

    final status = await supervisor.currentStatus();
    expect(status.state, CockpitDevelopmentSessionState.ready);
    expect(status.lastError, isNull);
  });

  test(
    'worker-owned supervisor can run without an HTTP control plane',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);
      final handle = harness.handle.copyWith(
        supervisorBaseUrl: 'cockpit-worker://development/dev-session-1',
      );
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        remoteControlReadinessProbe: (_) async => true,
        bindPort: -1,
        bindControlPlane: false,
        settlePollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();

      expect(
        (await supervisor.currentHandle()).supervisorBaseUrl,
        'cockpit-worker://development/dev-session-1',
      );
    },
  );

  test(
    'hot restart reports ready from stable remote recovery without UI idle commands',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var now = DateTime.utc(2026, 3, 23, 3);
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        now: () {
          final current = now;
          now = now.add(const Duration(milliseconds: 250));
          return current;
        },
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final reloadFuture = supervisor.reload(
        CockpitDevelopmentReloadMode.hotRestart,
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.writes.last, contains('"fullRestart":true'));
      harness.stdoutController.add('[{"id":0,"result":{"code":0}}]');

      final status = await reloadFuture;
      expect(status.state, CockpitDevelopmentSessionState.ready);
      expect(status.lastReloadSucceeded, isTrue);
      expect(status.lastReloadMode, CockpitDevelopmentReloadMode.hotRestart);
      expect(status.lastError, isNull);
    },
  );

  test(
    'settle failure reports unreachable remote recovery instead of UI idle',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      var now = DateTime.utc(2026, 3, 23, 3);
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => false,
        now: () {
          final current = now;
          now = now.add(const Duration(milliseconds: 250));
          return current;
        },
        settleTimeout: const Duration(seconds: 1),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');

      await supervisor.waitForState(CockpitDevelopmentSessionState.failed);
      final status = await supervisor.currentStatus();
      expect(status.state, CockpitDevelopmentSessionState.failed);
      expect(
        status.lastError,
        'Remote session did not recover to a reachable ready state.',
      );
    },
  );

  test(
    'web hot restart reports ready after remote reachability recovers',
    () async {
      final harness = _MachineHarness(
        remoteSessionHandle: CockpitRemoteSessionHandle(
          platform: 'web',
          deviceId: 'chrome',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'lib/main.dart',
          appId: 'dev.cockpit.cockpit_demo',
          host: '127.0.0.1',
          hostPort: 0,
          devicePort: 0,
          baseUrl: 'http://127.0.0.1:0',
          launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
        ),
      );
      addTearDown(harness.dispose);

      var now = DateTime.utc(2026, 3, 23, 3);
      var remoteChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle.copyWith(
          platform: 'web',
          deviceId: 'chrome',
          appBaseUrl: 'http://127.0.0.1:0',
        ),
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          remoteChecks += 1;
          return true;
        },
        now: () {
          final current = now;
          now = now.add(const Duration(milliseconds: 250));
          return current;
        },
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final reloadFuture = supervisor.reload(
        CockpitDevelopmentReloadMode.hotRestart,
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.writes.last, contains('"fullRestart":true'));
      harness.stdoutController.add('[{"id":0,"result":{"code":0}}]');

      final reloadedStatus = await reloadFuture;
      expect(reloadedStatus.state, CockpitDevelopmentSessionState.ready);
      expect(reloadedStatus.lastReloadSucceeded, isTrue);
      expect(
        reloadedStatus.lastReloadMode,
        CockpitDevelopmentReloadMode.hotRestart,
      );
      expect(remoteChecks, greaterThanOrEqualTo(2));
    },
  );

  test('settle recovery caps a single blocked probe attempt', () async {
    final harness = _MachineHarness();
    addTearDown(harness.dispose);

    var remoteAttempts = 0;
    final firstBlockedAttempt = Completer<bool>();
    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: harness.handle,
      machineClient: harness.client,
      remoteReachabilityProbe: (_) {
        remoteAttempts += 1;
        if (remoteAttempts == 1) {
          return firstBlockedAttempt.future;
        }
        return Future<bool>.value(true);
      },
      settleTimeout: const Duration(seconds: 2),
      settlePollInterval: const Duration(milliseconds: 10),
      settleProbeTimeout: const Duration(milliseconds: 25),
    );
    addTearDown(supervisor.dispose);

    await supervisor.start();
    harness.stdoutController.add(
      '[{"event":"app.start","params":{"appId":"app-1"}}]',
    );
    harness.stdoutController.add('[{"event":"app.started","params":{}}]');

    await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

    expect(remoteAttempts, greaterThanOrEqualTo(3));
    expect(firstBlockedAttempt.isCompleted, isFalse);
  });

  test(
    'supervisor syncs cached machine app state when the machine client emitted before subscription',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"machine-app-early"}}]',
      );
      harness.stdoutController.add(
        '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:34567/early/ws"}}]',
      );
      await Future<void>.delayed(Duration.zero);

      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle.copyWith(appId: '', vmServiceUri: null),
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        now: () => DateTime.utc(2026, 3, 23, 4),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();

      final currentHandle = await supervisor.currentHandle();
      expect(currentHandle.appId, 'machine-app-early');
      expect(currentHandle.remoteSessionHandle?.appId, 'machine-app-early');
      expect(
        currentHandle.vmServiceUri,
        Uri.parse('ws://127.0.0.1:34567/early/ws'),
      );
    },
  );

  test(
    'supervisor allows a startup machine client to be replaced after a recoverable launch exit',
    () async {
      final firstHarness = _MachineHarness();
      final secondHarness = _MachineHarness();
      addTearDown(firstHarness.dispose);
      addTearDown(secondHarness.dispose);

      var remoteChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: firstHarness.handle.copyWith(
          appId: '',
          remoteSessionHandle: null,
        ),
        machineClient: null,
        remoteReachabilityProbe: (_) async {
          remoteChecks += 1;
          return true;
        },
        now: () => DateTime.utc(2026, 3, 23, 3, 30),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      supervisor.bindMachineClient(firstHarness.client);
      firstHarness.stderrController.add(
        "file 'FlutterPluginRegistrarMacOS.h' has been modified since the module file 'flutter_cockpit.pcm' was built",
      );
      firstHarness.stdoutController.add('[{"event":"app.stop","params":{}}]');
      firstHarness.exitCode.complete(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final interimStatus = await supervisor.currentStatus();
      expect(interimStatus.state, CockpitDevelopmentSessionState.starting);
      expect(interimStatus.lastError, contains('flutter run exited'));

      supervisor.bindMachineClient(secondHarness.client);
      secondHarness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"recovered-app"}}]',
      );
      await supervisor.bindRemoteSession(
        secondHarness.handle.remoteSessionHandle!,
      );
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final currentHandle = await supervisor.currentHandle();
      expect(currentHandle.appId, 'recovered-app');
      expect(remoteChecks, greaterThanOrEqualTo(2));
    },
  );

  test(
    'reload updates generation and stop shuts down the control plane',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        appStopper: (appId) async {
          harness.stoppedAppIds.add(appId);
        },
        now: () => DateTime.utc(2026, 3, 23, 4),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final beforeReload = await supervisor.currentHandle();
      final reloadFuture = supervisor.reload(
        CockpitDevelopmentReloadMode.hotRestart,
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.writes.last, contains('"fullRestart":true'));
      harness.stdoutController.add('[{"id":0,"result":{"code":0}}]');
      final reloadedStatus = await reloadFuture;

      expect(reloadedStatus.state, CockpitDevelopmentSessionState.ready);
      expect(
        reloadedStatus.lastReloadMode,
        CockpitDevelopmentReloadMode.hotRestart,
      );
      expect(
        reloadedStatus.reloadGeneration,
        beforeReload.reloadGeneration + 1,
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final healthRequest = await client.getUrl(
        (await supervisor.currentHandle()).supervisorBaseUri.resolve('/health'),
      );
      final healthResponse = await healthRequest.close();
      final healthPayload =
          jsonDecode(await utf8.decoder.bind(healthResponse).join())
              as Map<String, Object?>;
      expect(
        healthPayload['state'],
        CockpitDevelopmentSessionState.ready.jsonValue,
      );

      await supervisor.stop();
      expect(
        (await supervisor.currentStatus()).state,
        CockpitDevelopmentSessionState.stopped,
      );
      expect(
        harness.writes.any(
          (payload) => payload.contains('"method":"app.stop"'),
        ),
        isTrue,
      );
      await supervisor.done;
      expect(harness.closeProcessCallCount, 1);
      expect(
        harness.stoppedAppIds,
        contains(harness.handle.remoteSessionHandle?.appId),
      );
    },
  );

  test('startup recovery does not attach for a read', () async {
    final harness = _MachineHarness();
    addTearDown(harness.dispose);

    var connectorCalls = 0;
    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: harness.handle,
      machineClient: null,
      machineClientConnector: () async {
        connectorCalls += 1;
        throw StateError('attach unavailable');
      },
      remoteReachabilityProbe: (_) async => false,
      startupSettleTimeout: const Duration(milliseconds: 40),
      settleTimeout: const Duration(seconds: 1),
      settlePollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(supervisor.dispose);

    await supervisor.start();
    await supervisor.waitForStartupRecovery();

    expect(connectorCalls, 0);
    expect(
      (await supervisor.currentStatus()).state,
      CockpitDevelopmentSessionState.failed,
    );
  });

  test(
    'reload keeps its full settle budget after fast startup recovery',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);
      var reloading = false;
      var reloadChecks = 0;
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async {
          if (!reloading) return true;
          reloadChecks += 1;
          return reloadChecks >= 6;
        },
        settleTimeout: const Duration(seconds: 1),
        startupSettleTimeout: const Duration(milliseconds: 100),
        settlePollInterval: const Duration(milliseconds: 25),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      reloading = true;
      final restart = supervisor.reload(
        CockpitDevelopmentReloadMode.hotRestart,
      );
      await Future<void>.delayed(Duration.zero);
      harness.stdoutController.add('[{"id":0,"result":{"code":0}}]');

      final status = await restart;
      expect(status.state, CockpitDevelopmentSessionState.ready);
      expect(reloadChecks, greaterThanOrEqualTo(7));
    },
  );

  test(
    'supervisor stop endpoint returns a stopped payload before closing',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);

      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        appStopper: (appId) async {
          harness.stoppedAppIds.add(appId);
        },
        now: () => DateTime.utc(2026, 3, 23, 5),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      harness.stdoutController.add(
        '[{"event":"app.start","params":{"appId":"app-1"}}]',
      );
      harness.stdoutController.add('[{"event":"app.started","params":{}}]');
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      final client = CockpitDevelopmentSessionSupervisorClient();
      final response = await client.stop(
        (await supervisor.currentHandle()).supervisorBaseUri,
      );

      expect(response.status.state, CockpitDevelopmentSessionState.stopped);
      expect(
        harness.writes.any(
          (payload) => payload.contains('"method":"app.stop"'),
        ),
        isTrue,
      );
      await supervisor.done;
      expect(harness.closeProcessCallCount, 1);
      expect(
        harness.stoppedAppIds,
        contains(harness.handle.remoteSessionHandle?.appId),
      );
    },
  );

  test(
    'supervisor does not call the platform stopper when the remote platform app id is unknown',
    () async {
      final harness = _MachineHarness(
        remoteSessionHandle: CockpitRemoteSessionHandle(
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'lib/main.dart',
          appId: 'remote-session-1',
          platformAppIdKnown: false,
          host: 'fd69:8f18:f0a9::1',
          hostPort: 57331,
          devicePort: 57331,
          baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
          launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
        ),
      );
      addTearDown(harness.dispose);

      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        appStopper: (appId) async {
          harness.stoppedAppIds.add(appId);
        },
        now: () => DateTime.utc(2026, 3, 23, 5),
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);

      await supervisor.stop();

      expect(harness.stoppedAppIds, isEmpty);
    },
  );

  test(
    'supervisor detach preserves app state and closes the detached machine control process',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        appStopper: (appId) async {
          harness.stoppedAppIds.add(appId);
        },
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);
      final detachFuture = supervisor.detach();
      await Future<void>.delayed(Duration.zero);
      expect(harness.writes.last, contains('"method":"app.detach"'));
      harness.stdoutController.add('[{"id":0,"result":true}]');
      await detachFuture;

      expect(
        (await supervisor.currentStatus()).state,
        CockpitDevelopmentSessionState.ready,
      );
      expect(harness.closeProcessCallCount, 1);
      expect(harness.stoppedAppIds, isEmpty);
    },
  );

  test(
    'supervisor preserves machine control when detach is rejected',
    () async {
      final harness = _MachineHarness();
      addTearDown(harness.dispose);
      final supervisor = CockpitDevelopmentSessionSupervisor(
        initialHandle: harness.handle,
        machineClient: harness.client,
        remoteReachabilityProbe: (_) async => true,
        appStopper: (appId) async {
          harness.stoppedAppIds.add(appId);
        },
        settleTimeout: const Duration(seconds: 2),
        settlePollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      await supervisor.waitForState(CockpitDevelopmentSessionState.ready);
      final detachFuture = supervisor.detach();
      await Future<void>.delayed(Duration.zero);
      expect(harness.writes.last, contains('"method":"app.detach"'));
      harness.stdoutController.add('[{"id":0,"result":false}]');
      await detachFuture;

      expect(
        (await supervisor.currentStatus()).state,
        CockpitDevelopmentSessionState.ready,
      );
      expect(harness.closeProcessCallCount, 0);
      expect(harness.stoppedAppIds, isEmpty);
    },
  );
}

final class _MachineHarness {
  _MachineHarness({CockpitRemoteSessionHandle? remoteSessionHandle})
    : stdoutController = StreamController<String>(),
      stderrController = StreamController<String>(),
      exitCode = Completer<int>(),
      writes = <String>[],
      handle = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'dev-session-1',
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        appBaseUrl: 'http://127.0.0.1:57331',
        supervisorBaseUrl: 'http://127.0.0.1:0',
        launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
        reloadGeneration: 1,
        remoteSessionHandle:
            remoteSessionHandle ??
            CockpitRemoteSessionHandle(
              platform: 'android',
              deviceId: 'emulator-5554',
              projectDir: '/workspace/examples/cockpit_demo',
              target: 'lib/main.dart',
              appId: 'dev.cockpit.cockpit_demo',
              platformAppId: 'dev.cockpit.cockpit_demo',
              host: '127.0.0.1',
              hostPort: 57331,
              devicePort: 47331,
              baseUrl: 'http://127.0.0.1:57331',
              launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
            ),
      ) {
    client = CockpitFlutterRunMachineClient(
      stdoutLines: stdoutController.stream,
      stderrLines: stderrController.stream,
      exitCode: exitCode.future,
      requestWriter: (payload) async {
        writes.add(payload);
      },
      closeProcess: () async {
        closeProcessCallCount += 1;
      },
    );
  }

  final StreamController<String> stdoutController;
  final StreamController<String> stderrController;
  final Completer<int> exitCode;
  final List<String> writes;
  final CockpitDevelopmentSessionHandle handle;
  int closeProcessCallCount = 0;
  final List<String> stoppedAppIds = <String>[];
  late final CockpitFlutterRunMachineClient client;

  Future<void> dispose() async {
    await stdoutController.close();
    await stderrController.close();
    if (!exitCode.isCompleted) {
      exitCode.complete(0);
    }
    await client.dispose();
  }
}
