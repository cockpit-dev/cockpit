import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test('development session handle omits absent optional JSON fields', () {
    final json = CockpitDevelopmentSessionHandle(
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
    ).toJson();

    expect(json.containsKey('remoteSessionHandle'), isFalse);
    expect(json.containsKey('vmServiceUri'), isFalse);
    expect(json.containsKey('lastReloadAt'), isFalse);
  });

  test('development session handle copyWith can clear nullable fields', () {
    final remoteSession = CockpitRemoteSessionHandle(
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 4, 5),
    );
    final handle = CockpitDevelopmentSessionHandle(
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
      remoteSessionHandle: remoteSession,
      vmServiceUri: Uri.parse('ws://127.0.0.1:34567/ws'),
      lastReloadAt: DateTime.utc(2026, 4, 5, 0, 1),
    );

    final cleared = handle.copyWith(
      remoteSessionHandle: null,
      vmServiceUri: null,
      lastReloadAt: null,
    );

    expect(cleared.remoteSessionHandle, isNull);
    expect(cleared.vmServiceUri, isNull);
    expect(cleared.lastReloadAt, isNull);
  });

  test('development session handle baseUri carries the remote token', () {
    CockpitRemoteSessionHandle remoteWithoutToken() =>
        CockpitRemoteSessionHandle(
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
        );
    final handle = CockpitDevelopmentSessionHandle(
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
      remoteSessionHandle: remoteWithoutToken().copyWith(
        authToken: 'launch-token-1',
      ),
    );
    final withoutRemote = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-2',
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      appId: 'dev.example.app',
      appBaseUrl: 'http://127.0.0.1:57331',
      supervisorBaseUrl: 'http://127.0.0.1:57332',
      launchedAt: DateTime.utc(2026, 4, 5),
      reloadGeneration: 2,
      remoteSessionHandle: remoteWithoutToken(),
    );

    expect(
      handle.baseUri,
      Uri.parse('http://127.0.0.1:57331?token=launch-token-1'),
    );
    expect(handle.appBaseUrl, 'http://127.0.0.1:57331');
    // Without a known token the endpoint view stays exactly as stored.
    expect(withoutRemote.baseUri, Uri.parse('http://127.0.0.1:57331'));
  });
}
