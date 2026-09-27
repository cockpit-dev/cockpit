import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test('app handle json round-trips nested session handles', () {
    final remoteSession = CockpitRemoteSessionHandle(
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.remote',
      platformAppId: 'dev.example.platform',
      processId: 4101,
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
    );
    final developmentSession = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-1',
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      appBaseUrl: 'http://127.0.0.1:57331',
      supervisorBaseUrl: 'http://127.0.0.1:57332',
      launchedAt: DateTime.utc(2026, 4, 5),
      reloadGeneration: 2,
      remoteSessionHandle: remoteSession,
    );
    final handle = CockpitAppHandle(
      appId: 'dev.example.app',
      mode: CockpitAppMode.development,
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
      platformAppId: 'dev.example.platform',
      supervisorLogPath: '/tmp/flutter_cockpit/supervisor.log',
      developmentSession: developmentSession,
      remoteSession: remoteSession,
    );

    final reloaded = CockpitAppHandle.fromJson(handle.toJson());

    expect(reloaded.platformAppId, 'dev.example.platform');
    expect(reloaded.processId, 4101);
    expect(reloaded.remoteSession?.toJson(), remoteSession.toJson());
    expect(reloaded.developmentSession?.toJson(), developmentSession.toJson());
  });

  test('app handle copyWith can clear nullable fields', () {
    final developmentSession = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-1',
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      appBaseUrl: 'http://127.0.0.1:57331',
      supervisorBaseUrl: 'http://127.0.0.1:57332',
      launchedAt: DateTime.utc(2026, 4, 5),
      reloadGeneration: 2,
    );
    final remoteSession = CockpitRemoteSessionHandle(
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      processId: 5101,
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
    );

    final handle = CockpitAppHandle(
      appId: 'dev.example.app',
      mode: CockpitAppMode.development,
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
      platformAppId: 'platform-app-id',
      processId: 5101,
      supervisorLogPath: '/tmp/flutter_cockpit/supervisor.log',
      developmentSession: developmentSession,
      remoteSession: remoteSession,
    );

    final cleared = handle.copyWith(
      platformAppId: null,
      processId: null,
      supervisorLogPath: null,
      developmentSession: null,
      remoteSession: null,
    );

    expect(cleared.platformAppId, isNull);
    expect(cleared.processId, isNull);
    expect(cleared.supervisorLogPath, isNull);
    expect(cleared.developmentSession, isNull);
    expect(cleared.remoteSession, isNull);
  });

  test(
    'remote-session app handle omits platform app id when it is explicitly unknown',
    () {
      final handle = CockpitAppHandle.fromRemoteSession(
        CockpitRemoteSessionHandle(
          platform: 'ios',
          deviceId: '00008110-0009341C2EF3801E',
          projectDir: '/workspace/app',
          target: 'cockpit/main.dart',
          appId: 'remote-session-1',
          platformAppIdKnown: false,
          host: 'fd69:8f18:f0a9::1',
          hostPort: 57331,
          devicePort: 47331,
          baseUrl: 'http://[fd69:8f18:f0a9::1]:57331',
          launchedAt: DateTime.utc(2026, 4, 5),
        ),
      );

      expect(handle.appId, 'remote-session-1');
      expect(handle.platformAppId, isNull);
    },
  );

  test('app handle keeps the remote session token out of the base URI', () {
    final remoteSession = CockpitRemoteSessionHandle(
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 57331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
      password: 'launch-token-1',
    );
    final handle = CockpitAppHandle(
      appId: 'dev.example.app',
      mode: CockpitAppMode.automation,
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
      remoteSession: remoteSession,
    );

    // The secret is exposed through password only; URIs and persisted
    // values stay clean.
    expect(handle.baseUri, Uri.parse('http://127.0.0.1:57331'));
    expect(handle.baseUrl, 'http://127.0.0.1:57331');
    expect(handle.password, 'launch-token-1');
  });

  test('app handle strips a legacy tokenized base URL on resolve', () {
    final remoteSession = CockpitRemoteSessionHandle(
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
      password: 'launch-token-1',
    );
    final tokenized = CockpitAppHandle(
      appId: 'dev.example.app',
      mode: CockpitAppMode.automation,
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:57331?token=launch-token-1',
      launchedAt: DateTime.utc(2026, 4, 5),
      remoteSession: remoteSession,
    );
    final unauthenticated = CockpitAppHandle(
      appId: 'dev.example.app',
      mode: CockpitAppMode.automation,
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
    );

    // Legacy tokenized URLs resolve clean; a duplicate token would instead
    // surface as a FormatException from the endpoint resolver.
    expect(tokenized.baseUri, Uri.parse('http://127.0.0.1:57331'));
    expect(tokenized.password, 'launch-token-1');
    expect(unauthenticated.baseUri, Uri.parse('http://127.0.0.1:57331'));
    expect(unauthenticated.password, isEmpty);
  });
}
