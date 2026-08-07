import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/development/cockpit_development_session_machine_launcher.dart';
import 'package:cockpit/src/development/cockpit_flutter_run_machine_client.dart';
import 'package:cockpit/src/platform/ios/cockpit_ios_device_connection.dart';
import 'package:cockpit/src/remote/cockpit_android_port_forwarder.dart';
import 'package:cockpit/src/session/cockpit_flutter_launch_configuration.dart';
import 'package:test/test.dart';

void main() {
  test(
    'launch starts flutter run with remote session defines and returns the machine app id',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final capturedStarts = <Map<String, Object?>>[];
      final probedBaseUris = <Uri>[];

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
              capturedStarts.add(<String, Object?>{
                'projectDir': projectDir,
                'target': target,
                'deviceId': deviceId,
                'flavor': flavor,
                'flutterExecutable': flutterExecutable,
                'extraArgs': extraArgs,
              });
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              stdoutController.add(
                '[{"event":"app.start","params":{"appId":"machine-app-1"}}]',
              );
              stdoutController.add(
                '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:34567/abcd/ws"}}]',
              );
              return client;
            },
        statusReader: (baseUri) async {
          probedBaseUris.add(baseUri);
          return _readyStatus('android', processId: 4242);
        },
        portForwarder: const _RecordingPortForwarder(58331),
        platformAppIdResolver:
            ({required projectDir, required platform, flavor}) async {
              expect(projectDir, '/workspace/examples/cockpit_demo');
              expect(platform, 'android');
              expect(flavor, isNull);
              return 'dev.example.android';
            },
        now: () => DateTime.utc(2026, 4, 4, 15),
      );

      final result = await launcher.launch(
        const CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'android',
          deviceId: 'emulator-5554',
          sessionPort: 47331,
          hostPort: 57331,
          launchTimeout: Duration(seconds: 10),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
      );

      expect(capturedStarts, hasLength(1));
      expect(capturedStarts.single['extraArgs'], <String>[
        '--no-dds',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=0.0.0.0',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331',
        '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.39.0',
      ]);
      expect(probedBaseUris, <Uri>[Uri.parse('http://127.0.0.1:58331')]);
      expect(result.remoteSessionHandle.appId, 'machine-app-1');
      expect(result.remoteSessionHandle.platformAppId, 'dev.example.android');
      expect(result.remoteSessionHandle.processId, 4242);
      expect(
        result.remoteSessionHandle.effectivePlatformAppId,
        'dev.example.android',
      );
      expect(result.remoteSessionHandle.hostPort, 58331);
      expect(
        result.machineClient.currentVmServiceUri,
        Uri.parse('ws://127.0.0.1:34567/abcd/ws'),
      );

      await stdoutController.close();
      await stderrController.close();
      exitCode.complete(0);
      await result.machineClient.dispose();
    },
  );

  test(
    'launch forwards user Flutter args before cockpit defines and passes process environment',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      Map<String, Object?>? capturedStart;
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
              capturedStart = <String, Object?>{
                'extraArgs': extraArgs,
                'environment': environment,
              };
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              stdoutController.add(
                '[{"event":"app.start","params":{"appId":"machine-app-1"}}]',
              );
              stdoutController.add(
                '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:34567/abcd/ws"}}]',
              );
              return client;
            },
        statusReader: (_) async => _readyStatus('android'),
        portForwarder: const _RecordingPortForwarder(58331),
        platformAppIdResolver:
            ({required projectDir, required platform, flavor}) async =>
                'dev.example.android',
        now: () => DateTime.utc(2026, 4, 4, 15),
      );

      final result = await launcher.launch(
        CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'android',
          deviceId: 'emulator-5554',
          sessionPort: 47331,
          hostPort: 57331,
          launchTimeout: const Duration(seconds: 10),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
          launchConfiguration: CockpitFlutterLaunchConfiguration(
            dartDefines: const <String>['API_URL=https://example.test'],
            dartDefineFromFiles: const <String>['config/dev.json'],
            flutterArgs: const <String>['--track-widget-creation'],
            environment: const <String, String>{'API_TOKEN': 'secret'},
          ),
        ),
      );

      expect(capturedStart?['extraArgs'], <String>[
        '--dart-define=API_URL=https://example.test',
        '--dart-define-from-file=config/dev.json',
        '--track-widget-creation',
        '--no-dds',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=0.0.0.0',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331',
        '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.39.0',
      ]);
      expect(capturedStart?['environment'], <String, String>{
        'API_TOKEN': 'secret',
      });

      await stdoutController.close();
      await stderrController.close();
      exitCode.complete(0);
      await result.machineClient.dispose();
    },
  );

  test(
    'ios development launch binds the remote session to a host-reachable address',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final capturedStarts = <Map<String, Object?>>[];

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
              capturedStarts.add(<String, Object?>{
                'projectDir': projectDir,
                'target': target,
                'deviceId': deviceId,
                'flavor': flavor,
                'flutterExecutable': flutterExecutable,
                'extraArgs': extraArgs,
              });
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              stdoutController.add(
                '[{"event":"app.start","params":{"appId":"machine-ios-app"}}]',
              );
              stdoutController.add(
                '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:35567/ios/ws"}}]',
              );
              return client;
            },
        statusReader: (_) async => _readyStatus('ios'),
        platformAppIdResolver:
            ({required projectDir, required platform, flavor}) async {
              expect(projectDir, '/workspace/examples/cockpit_demo');
              expect(platform, 'ios');
              expect(flavor, isNull);
              return 'dev.example.ios';
            },
        now: () => DateTime.utc(2026, 4, 4, 16),
      );

      final result = await launcher.launch(
        const CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: 'FC5B7D0F-B7FB-4A7A-B1B0-FF28BC289BC2',
          sessionPort: 47331,
          hostPort: 57331,
          launchTimeout: Duration(seconds: 10),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
      );

      expect(capturedStarts, hasLength(1));
      expect(capturedStarts.single['extraArgs'], <String>[
        '--no-dds',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=0.0.0.0',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331',
        '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.39.0',
      ]);
      expect(result.remoteSessionHandle.appId, 'machine-ios-app');
      expect(result.remoteSessionHandle.platformAppId, 'dev.example.ios');
      expect(
        result.remoteSessionHandle.effectivePlatformAppId,
        'dev.example.ios',
      );
      expect(result.remoteSessionHandle.hostPort, 57331);

      await stdoutController.close();
      await stderrController.close();
      exitCode.complete(0);
      await result.machineClient.dispose();
    },
  );

  test(
    'web development launch uses explicit IPv4 loopback health probes',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final capturedStarts = <Map<String, Object?>>[];
      final probedBaseUris = <Uri>[];

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
              capturedStarts.add(<String, Object?>{
                'projectDir': projectDir,
                'target': target,
                'deviceId': deviceId,
                'flavor': flavor,
                'flutterExecutable': flutterExecutable,
                'extraArgs': extraArgs,
              });
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              stdoutController.add(
                '[{"event":"app.start","params":{"appId":"machine-web-app"}}]',
              );
              stdoutController.add(
                '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:37567/web/ws"}}]',
              );
              return client;
            },
        statusReader: (baseUri) async {
          probedBaseUris.add(baseUri);
          return _readyStatus('web');
        },
        now: () => DateTime.utc(2026, 4, 4, 17),
      );

      final result = await launcher.launch(
        const CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'web',
          deviceId: 'chrome',
          sessionPort: 59331,
          hostPort: 59331,
          launchTimeout: Duration(seconds: 10),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
      );

      expect(capturedStarts, hasLength(1));
      expect(capturedStarts.single['extraArgs'], <String>[
        '--no-dds',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=127.0.0.1',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=59331',
        '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.39.0',
      ]);
      expect(probedBaseUris, <Uri>[Uri.parse('http://127.0.0.1:59331')]);
      expect(result.remoteSessionHandle.host, '127.0.0.1');
      expect(result.remoteSessionHandle.baseUrl, 'http://127.0.0.1:59331');

      await stdoutController.close();
      await stderrController.close();
      exitCode.complete(0);
      await result.machineClient.dispose();
    },
  );

  test(
    'rejects stale same-platform remote health when launch id does not match',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      List<String>? capturedExtraArgs;
      var statusReadCount = 0;

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
              capturedExtraArgs = extraArgs;
              Future<void>.microtask(() {
                stdoutController.add(
                  '[{"event":"app.start","params":{"appId":"machine-macos-app"}}]',
                );
              });
              return CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
            },
        statusReader: (_) async {
          statusReadCount += 1;
          if (statusReadCount == 1) {
            return _readyStatus('macos', sessionId: 'old-macos-session');
          }
          return _readyStatus('macos', sessionId: 'launch-macos-1');
        },
        platformAppIdResolver:
            ({required projectDir, required platform, flavor}) async {
              expect(platform, 'macos');
              return 'dev.example.macos';
            },
        now: () => DateTime.utc(2026, 4, 4, 17, 15),
      );

      final result = await launcher.launch(
        const CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 57331,
          hostPort: 57331,
          launchTimeout: Duration(seconds: 10),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
          launchId: 'launch-macos-1',
        ),
      );

      expect(statusReadCount, 2);
      expect(
        capturedExtraArgs,
        contains(
          '--dart-define=FLUTTER_COCKPIT_REMOTE_LAUNCH_ID=launch-macos-1',
        ),
      );
      expect(result.remoteSessionHandle.appId, 'machine-macos-app');
      expect(result.remoteSessionHandle.platform, 'macos');
      expect(result.remoteSessionHandle.platformAppId, 'dev.example.macos');

      await stdoutController.close();
      await stderrController.close();
      exitCode.complete(0);
      await result.machineClient.dispose();
    },
  );

  test(
    'macos development launch cleans and restarts once for stale Swift module cache failures',
    () async {
      final stdoutControllers = <StreamController<String>>[];
      final stderrControllers = <StreamController<String>>[];
      final exitCodes = <Completer<int>>[];
      final startAttempts = <String>[];
      final boundClients = <CockpitFlutterRunMachineClient>[];
      final cleanInvocations = <String>[];

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
              startAttempts.add('$projectDir|$target|$deviceId');
              final stdoutController = StreamController<String>();
              final stderrController = StreamController<String>();
              final exitCode = Completer<int>();
              stdoutControllers.add(stdoutController);
              stderrControllers.add(stderrController);
              exitCodes.add(exitCode);
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              if (startAttempts.length == 1) {
                Future<void>.microtask(() {
                  stderrController.add(
                    "file 'FlutterPluginRegistrarMacOS.h' has been modified since the module file 'flutter_cockpit.pcm' was built",
                  );
                  exitCode.complete(1);
                });
              } else {
                Future<void>.microtask(() {
                  stdoutController.add(
                    '[{"event":"app.start","params":{"appId":"machine-macos-app"}}]',
                  );
                  stdoutController.add(
                    '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:37567/macos/ws"}}]',
                  );
                });
              }
              return client;
            },
        recoveryProcessRunner:
            (
              executable,
              arguments, {
              workingDirectory,
              required timeout,
            }) async {
              cleanInvocations.add(
                '$executable ${arguments.join(' ')} cwd=$workingDirectory',
              );
              return ProcessResult(321, 0, '', '');
            },
        statusReader: (_) async => _readyStatus('macos'),
        platformAppIdResolver:
            ({required projectDir, required platform, flavor}) async {
              expect(platform, 'macos');
              return 'dev.example.macos';
            },
        now: () => DateTime.utc(2026, 4, 4, 17, 20),
      );

      final result = await launcher.launchWithLifecycle(
        const CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 57331,
          hostPort: 57331,
          launchTimeout: Duration(seconds: 30),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
        onMachineClientStarted: boundClients.add,
      );

      expect(startAttempts, hasLength(2));
      expect(boundClients, hasLength(2));
      expect(cleanInvocations, <String>[
        '/opt/flutter/bin/flutter clean cwd=/workspace/examples/cockpit_demo',
      ]);
      expect(result.remoteSessionHandle.appId, 'machine-macos-app');
      expect(result.remoteSessionHandle.platformAppId, 'dev.example.macos');

      for (final controller in stdoutControllers) {
        await controller.close();
      }
      for (final controller in stderrControllers) {
        await controller.close();
      }
      if (!exitCodes.last.isCompleted) {
        exitCodes.last.complete(0);
      }
      await result.machineClient.dispose();
    },
  );

  test('resident compiler connection races restart once without clean', () async {
    final stdoutControllers = <StreamController<String>>[];
    final stderrControllers = <StreamController<String>>[];
    final exitCodes = <Completer<int>>[];
    var starts = 0;
    var cleans = 0;
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
            starts += 1;
            final stdout = StreamController<String>();
            final stderr = StreamController<String>();
            final exitCode = Completer<int>();
            stdoutControllers.add(stdout);
            stderrControllers.add(stderr);
            exitCodes.add(exitCode);
            if (starts == 1) {
              Future<void>.microtask(() {
                stderr
                  ..add(
                    'A connection to the Resident Frontend Compiler could not be established.',
                  )
                  ..add('Bad state: A server is already running.');
                exitCode.complete(1);
              });
            } else {
              Future<void>.microtask(() {
                stdout.add(
                  '[{"event":"app.start","params":{"appId":"machine-app"}}]',
                );
              });
            }
            return CockpitFlutterRunMachineClient(
              stdoutLines: stdout.stream,
              stderrLines: stderr.stream,
              exitCode: exitCode.future,
              requestWriter: (_) async {},
            );
          },
      recoveryProcessRunner:
          (_, _, {workingDirectory, required timeout}) async {
            cleans += 1;
            return ProcessResult(1, 0, '', '');
          },
      statusReader: (_) async => _readyStatus('macos'),
      platformAppIdResolver:
          ({required projectDir, required platform, flavor}) async =>
              'dev.example.macos',
      now: () => DateTime.utc(2026, 4, 4, 17, 25),
    );

    final result = await launcher.launch(
      const CockpitLaunchDevelopmentMachineSessionRequest(
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        platform: 'macos',
        deviceId: 'macos',
        sessionPort: 57331,
        hostPort: 57331,
        launchTimeout: Duration(seconds: 30),
        flutterVersion: '3.44.0',
      ),
    );

    expect(starts, 2);
    expect(cleans, 0);
    expect(result.remoteSessionHandle.appId, 'machine-app');
    for (final controller in stdoutControllers) {
      await controller.close();
    }
    for (final controller in stderrControllers) {
      await controller.close();
    }
    if (!exitCodes.last.isCompleted) exitCodes.last.complete(0);
    await result.machineClient.dispose();
  });

  test('passes flavor through the development machine launch', () async {
    final stdoutController = StreamController<String>();
    final stderrController = StreamController<String>();
    final exitCode = Completer<int>();
    final capturedStarts = <Map<String, Object?>>[];

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
            capturedStarts.add(<String, Object?>{
              'projectDir': projectDir,
              'target': target,
              'deviceId': deviceId,
              'flavor': flavor,
              'flutterExecutable': flutterExecutable,
              'extraArgs': extraArgs,
            });
            final client = CockpitFlutterRunMachineClient(
              stdoutLines: stdoutController.stream,
              stderrLines: stderrController.stream,
              exitCode: exitCode.future,
              requestWriter: (_) async {},
            );
            stdoutController.add(
              '[{"event":"app.start","params":{"appId":"machine-flavor-app"}}]',
            );
            stdoutController.add(
              '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:38567/flavor/ws"}}]',
            );
            return client;
          },
      statusReader: (_) async => _readyStatus('android'),
      portForwarder: const _RecordingPortForwarder(58331),
      now: () => DateTime.utc(2026, 4, 4, 17, 30),
    );

    final result = await launcher.launch(
      const CockpitLaunchDevelopmentMachineSessionRequest(
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        flavor: 'staging',
        platform: 'android',
        deviceId: 'emulator-5554',
        sessionPort: 47331,
        hostPort: 57331,
        launchTimeout: Duration(seconds: 10),
        flutterVersion: '3.39.0',
        flutterExecutable: '/opt/flutter/bin/flutter',
      ),
    );

    expect(capturedStarts.single['flavor'], 'staging');

    await stdoutController.close();
    await stderrController.close();
    exitCode.complete(0);
    await result.machineClient.dispose();
  });

  test(
    'physical iOS development launch uses the device tunnel host and IPv6 bind host',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final capturedStarts = <Map<String, Object?>>[];
      final probedBaseUris = <Uri>[];

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
              capturedStarts.add(<String, Object?>{
                'projectDir': projectDir,
                'target': target,
                'deviceId': deviceId,
                'flavor': flavor,
                'flutterExecutable': flutterExecutable,
                'extraArgs': extraArgs,
              });
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              stdoutController.add(
                '[{"event":"app.start","params":{"appId":"machine-ios-device-app"}}]',
              );
              stdoutController.add(
                '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:36567/ios-device/ws"}}]',
              );
              return client;
            },
        statusReader: (baseUri) async {
          probedBaseUris.add(baseUri);
          return _readyStatus('ios');
        },
        iosDeviceConnectionResolver: (deviceId) async {
          expect(deviceId, '00008110-0009341C2EF3801E');
          return const CockpitIosDeviceConnection(
            isPhysical: true,
            tunnelIpAddress: 'fd69:8f18:f0a9::1',
          );
        },
        now: () => DateTime.utc(2026, 4, 4, 18),
      );

      final result = await launcher.launch(
        const CockpitLaunchDevelopmentMachineSessionRequest(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          sessionPort: 47331,
          hostPort: 57331,
          launchTimeout: Duration(seconds: 10),
          flutterVersion: '3.39.0',
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
      );

      expect(capturedStarts, hasLength(1));
      expect(capturedStarts.single['extraArgs'], <String>[
        '--no-dds',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=::',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331',
        '--dart-define=FLUTTER_COCKPIT_ENABLE_HTTP_NETWORK_OBSERVER=false',
        '--dart-define=FLUTTER_COCKPIT_ENABLE_RUNTIME_OBSERVER=false',
        '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.39.0',
      ]);
      expect(probedBaseUris, <Uri>[
        Uri.parse('http://[fd69:8f18:f0a9::1]:57331'),
      ]);
      expect(result.remoteSessionHandle.host, 'fd69:8f18:f0a9::1');
      expect(
        result.remoteSessionHandle.baseUrl,
        'http://[fd69:8f18:f0a9::1]:57331',
      );

      await stdoutController.close();
      await stderrController.close();
      exitCode.complete(0);
      await result.machineClient.dispose();
    },
  );

  test(
    'fails fast when flutter run exits before the remote session becomes reachable',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();

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
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              Future<void>.microtask(() {
                stderrController.add('Lost connection to device.');
                exitCode.complete(1);
              });
              return client;
            },
        statusReader: (_) async => throw StateError('connection refused'),
        portForwarder: const _RecordingPortForwarder(58331),
        now: () => DateTime.utc(2026, 4, 4, 19),
      );

      await expectLater(
        () => launcher.launch(
          const CockpitLaunchDevelopmentMachineSessionRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'android',
            deviceId: 'emulator-5554',
            sessionPort: 47331,
            hostPort: 57331,
            launchTimeout: Duration(seconds: 10),
            flutterVersion: '3.39.0',
            flutterExecutable: '/opt/flutter/bin/flutter',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('exitCode=1'),
          ),
        ),
      );

      await stdoutController.close();
      await stderrController.close();
    },
  );

  test(
    'reports a safe automation fallback when physical iOS remote session is ready but app.start never arrives',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();

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
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              Future<void>.microtask(() {
                stderrController.add('The Dart VM Service was not discovered.');
                exitCode.complete(1);
              });
              return client;
            },
        statusReader: (_) async => _readyStatus('ios'),
        iosDeviceConnectionResolver: (_) async =>
            const CockpitIosDeviceConnection(
              isPhysical: true,
              tunnelIpAddress: 'fd69:8f18:f0a9::1',
            ),
        now: () => DateTime.utc(2026, 4, 4, 20),
      );

      await expectLater(
        () => launcher.launch(
          const CockpitLaunchDevelopmentMachineSessionRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'ios',
            deviceId: '00008110-0009341C2EF3801E',
            sessionPort: 47331,
            hostPort: 57331,
            launchTimeout: Duration(seconds: 10),
            flutterVersion: '3.39.0',
            flutterExecutable: '/opt/flutter/bin/flutter',
          ),
        ),
        throwsA(
          isA<CockpitDevelopmentSessionFallbackException>()
              .having(
                (error) => error.code,
                'code',
                'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              )
              .having(
                (error) => error.message,
                'message',
                contains('Automation fallback is safe'),
              ),
        ),
      );

      await stdoutController.close();
      await stderrController.close();
    },
  );

  test(
    'keeps polling physical iOS remote health after flutter run exits so a ready tunnel session can still be reused',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      var now = DateTime.utc(2026, 4, 4, 20, 30);
      var statusReadCount = 0;

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
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              Future<void>.microtask(() {
                stderrController.add('The Dart VM Service was not discovered.');
                exitCode.complete(1);
              });
              return client;
            },
        statusReader: (_) async {
          statusReadCount += 1;
          if (statusReadCount < 3) {
            throw StateError('connection refused');
          }
          return _readyStatus('ios');
        },
        iosDeviceConnectionResolver: (_) async =>
            const CockpitIosDeviceConnection(
              isPhysical: true,
              tunnelIpAddress: 'fd69:8f18:f0a9::1',
            ),
        delay: (duration) async {
          now = now.add(duration);
        },
        now: () => now,
      );

      await expectLater(
        () => launcher.launch(
          const CockpitLaunchDevelopmentMachineSessionRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'ios',
            deviceId: '00008110-0009341C2EF3801E',
            sessionPort: 47331,
            hostPort: 57331,
            launchTimeout: Duration(seconds: 10),
            flutterVersion: '3.39.0',
            flutterExecutable: '/opt/flutter/bin/flutter',
          ),
        ),
        throwsA(
          isA<CockpitDevelopmentSessionFallbackException>()
              .having(
                (error) => error.code,
                'code',
                'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
              )
              .having(
                (error) => error.remoteSessionHandle?.baseUrl,
                'baseUrl',
                'http://[fd69:8f18:f0a9::1]:57331',
              ),
        ),
      );

      expect(statusReadCount, 3);
      await stdoutController.close();
      await stderrController.close();
    },
  );

  test(
    'physical iOS fallback preserves session identity but leaves platform app id unknown when bundle lookup fails',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();

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
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              Future<void>.microtask(() {
                stderrController.add('The Dart VM Service was not discovered.');
                exitCode.complete(1);
              });
              return client;
            },
        statusReader: (_) async => _readyStatus('ios'),
        iosDeviceConnectionResolver: (_) async =>
            const CockpitIosDeviceConnection(
              isPhysical: true,
              tunnelIpAddress: 'fd69:8f18:f0a9::1',
            ),
        iosFallbackAppBundlePathResolver:
            ({required projectDir, flavor}) async {
              throw StateError('missing device app bundle');
            },
        now: () => DateTime.utc(2026, 4, 4, 20, 45),
      );

      await expectLater(
        () => launcher.launch(
          const CockpitLaunchDevelopmentMachineSessionRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'ios',
            deviceId: '00008110-0009341C2EF3801E',
            sessionPort: 47331,
            hostPort: 57331,
            launchTimeout: Duration(seconds: 10),
            flutterVersion: '3.39.0',
            flutterExecutable: '/opt/flutter/bin/flutter',
          ),
        ),
        throwsA(
          isA<CockpitDevelopmentSessionFallbackException>()
              .having(
                (error) => error.remoteSessionHandle?.appId,
                'remoteSessionHandle.appId',
                'remote-session-1',
              )
              .having(
                (error) => error.remoteSessionHandle?.platformAppIdKnown,
                'remoteSessionHandle.platformAppIdKnown',
                isFalse,
              )
              .having(
                (error) => error.remoteSessionHandle?.effectivePlatformAppId,
                'remoteSessionHandle.effectivePlatformAppId',
                isNull,
              ),
        ),
      );

      await stdoutController.close();
      await stderrController.close();
    },
  );

  test(
    'development machine launcher logs remote-health probe failures before timeout',
    () async {
      final stdoutController = StreamController<String>();
      final stderrController = StreamController<String>();
      final exitCode = Completer<int>();
      final diagnosticLog = <String>[];
      var now = DateTime.utc(2026, 4, 4, 21);

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
              final client = CockpitFlutterRunMachineClient(
                stdoutLines: stdoutController.stream,
                stderrLines: stderrController.stream,
                exitCode: exitCode.future,
                requestWriter: (_) async {},
              );
              stdoutController.add(
                '[{"event":"app.start","params":{"appId":"app-1"}}]',
              );
              return client;
            },
        statusReader: (_) async => throw StateError('connection refused'),
        portForwarder: const _RecordingPortForwarder(58331),
        diagnosticLogger: diagnosticLog.add,
        delay: (duration) async {
          now = now.add(duration);
          await Future<void>.delayed(Duration.zero);
        },
        now: () => now,
      );
      addTearDown(() async {
        await stdoutController.close();
        await stderrController.close();
        if (!exitCode.isCompleted) {
          exitCode.complete(0);
        }
      });

      await expectLater(
        () => launcher.launch(
          const CockpitLaunchDevelopmentMachineSessionRequest(
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            platform: 'android',
            deviceId: 'emulator-5554',
            sessionPort: 47331,
            hostPort: 57331,
            launchTimeout: Duration(milliseconds: 120),
            flutterVersion: '3.39.0',
            flutterExecutable: '/opt/flutter/bin/flutter',
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );

      final joinedLog = diagnosticLog.join('\n');
      expect(joinedLog, contains('remote_status_probe failed'));
      expect(joinedLog, contains('base_url=http://127.0.0.1:58331'));
      expect(joinedLog, contains('remote_status_probe timed_out'));
    },
  );

  test(
    'development machine launcher enforces the launch timeout on a hanging remote-health probe',
    () async {
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
            }) async => CockpitFlutterRunMachineClient(
              stdoutLines: const Stream<String>.empty(),
              stderrLines: const Stream<String>.empty(),
              exitCode: Completer<int>().future,
              requestWriter: (_) async {},
            ),
        statusReader: (_) => Completer<CockpitRemoteSessionStatus>().future,
        portForwarder: const _RecordingPortForwarder(58331),
      );

      expect(
        () => launcher
            .launch(
              const CockpitLaunchDevelopmentMachineSessionRequest(
                projectDir: '/workspace/examples/cockpit_demo',
                target: 'cockpit/main.dart',
                platform: 'android',
                deviceId: 'emulator-5554',
                sessionPort: 47331,
                hostPort: 57331,
                launchTimeout: Duration(milliseconds: 50),
                flutterVersion: '3.39.0',
                flutterExecutable: '/opt/flutter/bin/flutter',
              ),
            )
            .timeout(
              const Duration(milliseconds: 120),
              onTimeout: () => throw StateError(
                'development launcher did not enforce probe timeout',
              ),
            ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test(
    'development machine launcher caps remote-health retry delays to the remaining deadline',
    () async {
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
            }) async => CockpitFlutterRunMachineClient(
              stdoutLines: const Stream<String>.empty(),
              stderrLines: const Stream<String>.empty(),
              exitCode: Completer<int>().future,
              requestWriter: (_) async {},
            ),
        statusReader: (_) async => throw StateError('still booting'),
        portForwarder: const _RecordingPortForwarder(58331),
      );

      expect(
        () => launcher
            .launch(
              const CockpitLaunchDevelopmentMachineSessionRequest(
                projectDir: '/workspace/examples/cockpit_demo',
                target: 'cockpit/main.dart',
                platform: 'android',
                deviceId: 'emulator-5554',
                sessionPort: 47331,
                hostPort: 57331,
                launchTimeout: Duration(milliseconds: 50),
                flutterVersion: '3.39.0',
                flutterExecutable: '/opt/flutter/bin/flutter',
              ),
            )
            .timeout(
              const Duration(milliseconds: 120),
              onTimeout: () => throw StateError(
                'development launcher slept past the remaining deadline',
              ),
            ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}

final class _RecordingPortForwarder extends CockpitAndroidPortForwarder {
  const _RecordingPortForwarder(this.hostPort);

  final int hostPort;

  @override
  Future<int> ensureForwarded({
    required String deviceId,
    required int preferredHostPort,
    required int devicePort,
  }) async {
    expect(deviceId, 'emulator-5554');
    expect(preferredHostPort, 57331);
    expect(devicePort, 47331);
    return hostPort;
  }
}

CockpitRemoteSessionStatus _readyStatus(
  String platform, {
  String sessionId = 'remote-session-1',
  int? processId,
}) {
  return CockpitRemoteSessionStatus(
    sessionId: sessionId,
    platform: platform,
    transportType: 'http',
    currentRouteName: '/inbox',
    processId: processId,
    capabilities: CockpitCapabilities(
      platform: platform,
      transportType: 'http',
      supportsInAppControl: true,
      supportsFlutterViewCapture: true,
      supportsNativeScreenCapture: false,
      supportsHostAutomation: false,
    ),
    recordingCapabilities: CockpitRecordingCapabilities(
      supportsNativeRecording: false,
    ),
    snapshot: CockpitSnapshot(routeName: '/inbox'),
  );
}
