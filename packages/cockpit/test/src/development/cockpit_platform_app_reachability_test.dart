import 'dart:io';

import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_platform_app_reachability.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Android pidof proves the app is running without a ps fallback',
    () async {
      final calls = <List<String>>[];
      final probe = CockpitPlatformAppReachability(
        processRunner: (executable, arguments, {required timeout}) async {
          calls.add(<String>[executable, ...arguments]);
          return ProcessResult(1, 0, '12136\n', '');
        },
      );

      expect(await probe.probe(_handle(platform: 'android')), isTrue);
      expect(calls, <List<String>>[
        <String>[
          'adb',
          '-s',
          'emulator-5554',
          'shell',
          'pidof',
          'dev.example.app',
        ],
      ]);
    },
  );

  test('Android ps proves the app exited when pidof is unavailable', () async {
    var calls = 0;
    final probe = CockpitPlatformAppReachability(
      processRunner: (executable, arguments, {required timeout}) async {
        calls += 1;
        if (arguments.contains('pidof')) {
          return ProcessResult(1, 1, '', 'pidof: not found');
        }
        return ProcessResult(2, 0, 'USER PID NAME\nu0_a1 44 other.app\n', '');
      },
    );

    expect(await probe.probe(_handle(platform: 'android')), isFalse);
    expect(calls, 2);
  });

  test('Android transport failure stays inconclusive', () async {
    final probe = CockpitPlatformAppReachability(
      processRunner: (executable, arguments, {required timeout}) async =>
          ProcessResult(1, 1, '', 'error: device offline'),
    );

    expect(await probe.probe(_handle(platform: 'android')), isNull);
  });

  test(
    'macOS process identity proves a persisted app is still running',
    () async {
      final probe = CockpitPlatformAppReachability(
        processRunner: (executable, arguments, {required timeout}) async {
          expect(executable, 'ps');
          expect(arguments, <String>['-p', '4242', '-o', 'pid=']);
          return ProcessResult(1, 0, ' 4242\n', '');
        },
      );

      expect(await probe.probe(_handle(platform: 'macos')), isTrue);
    },
  );
}

CockpitDevelopmentSessionHandle _handle({required String platform}) {
  final deviceId = platform == 'android' ? 'emulator-5554' : 'macos';
  final remote = CockpitRemoteSessionHandle(
    platform: platform,
    deviceId: deviceId,
    projectDir: '/workspace/example',
    target: 'cockpit/main.dart',
    appId: 'machine-app',
    platformAppId: 'dev.example.app',
    processId: 4242,
    host: '127.0.0.1',
    hostPort: 47331,
    devicePort: 47331,
    baseUrl: 'http://127.0.0.1:47331',
    launchedAt: DateTime.utc(2026, 8, 13),
  );
  return CockpitDevelopmentSessionHandle(
    developmentSessionId: 'session-1',
    platform: platform,
    deviceId: deviceId,
    projectDir: remote.projectDir,
    target: remote.target,
    appId: remote.appId,
    appBaseUrl: remote.baseUrl,
    supervisorBaseUrl: 'cockpit-worker://development/session-1',
    remoteSessionHandle: remote,
    launchedAt: remote.launchedAt,
    reloadGeneration: 0,
  );
}
