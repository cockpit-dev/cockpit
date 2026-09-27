import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

CockpitRemoteSessionStatus _status({required String sessionId}) {
  return CockpitRemoteSessionStatus(
    sessionId: sessionId,
    platform: 'macos',
    transportType: 'remoteHttp',
    currentRouteName: '/home',
    capabilities: CockpitCapabilities(
      platform: 'macos',
      transportType: 'remoteHttp',
      supportsInAppControl: true,
      supportsFlutterViewCapture: true,
      supportsNativeScreenCapture: true,
      supportsHostAutomation: true,
    ),
    recordingCapabilities: CockpitRecordingCapabilities(
      supportsNativeRecording: false,
      preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
    ),
    snapshot: CockpitSnapshot(routeName: '/home'),
  );
}

CockpitRemoteSessionHandle _handle({
  String baseUrl = 'http://127.0.0.1:57331',
  String password = '',
}) {
  return CockpitRemoteSessionHandle(
    platform: 'macos',
    deviceId: 'macos',
    projectDir: '/workspace/app',
    target: 'cockpit/main.dart',
    appId: 'dev.example.app',
    host: '127.0.0.1',
    hostPort: 57331,
    devicePort: 57331,
    baseUrl: baseUrl,
    launchedAt: DateTime.utc(2026, 9, 10),
    password: password,
  );
}

void main() {
  test('fromRemoteStatus keeps an explicit launch token out of the URI', () {
    final handle = CockpitRemoteSessionHandle.fromRemoteStatus(
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      deviceId: 'macos',
      appId: 'dev.example.app',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 57331,
      status: _status(sessionId: 'app-session-id'),
      launchedAt: DateTime.utc(2026, 9, 10),
      password: 'launch-token-9',
    );

    expect(handle.password, 'launch-token-9');
    expect(handle.baseUri, Uri.parse('http://127.0.0.1:57331'));
    expect(handle.baseUrl, 'http://127.0.0.1:57331');
  });

  test('fromRemoteStatus never treats the public session id as a token', () {
    final handle = CockpitRemoteSessionHandle.fromRemoteStatus(
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      deviceId: 'macos',
      appId: 'dev.example.app',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 57331,
      status: _status(sessionId: 'app-session-id'),
      launchedAt: DateTime.utc(2026, 9, 10),
    );

    expect(handle.password, isEmpty);
    expect(handle.baseUri, Uri.parse('http://127.0.0.1:57331'));
  });

  test('public JSON omits credentials and private JSON restores them', () {
    final handle = _handle(password: 'launch-token-9');

    final publicJson = handle.toJson();
    expect(publicJson.containsKey('password'), isFalse);
    expect(publicJson['baseUrl'], 'http://127.0.0.1:57331');
    expect(publicJson.toString(), isNot(contains('launch-token-9')));

    final privateJson = handle.toPrivateJson();
    expect(privateJson['password'], 'launch-token-9');
    final restored = CockpitRemoteSessionHandle.fromJson(privateJson);
    expect(restored.password, 'launch-token-9');
    expect(restored.baseUri, Uri.parse('http://127.0.0.1:57331'));
  });

  test('legacy query credentials migrate to a clean endpoint', () {
    final handle = CockpitRemoteSessionHandle.fromJson(<String, Object?>{
      ..._handle().toJson(),
      'baseUrl':
          'http://127.0.0.1:57331/cockpit?channel=stable&token=legacy-token',
    });

    expect(handle.password, 'legacy-token');
    expect(
      handle.baseUri,
      Uri.parse('http://127.0.0.1:57331/cockpit?channel=stable'),
    );
    expect(handle.toJson().toString(), isNot(contains('legacy-token')));
  });

  test('matching legacy field and query credentials migrate once', () {
    final handle = CockpitRemoteSessionHandle.fromJson(<String, Object?>{
      ..._handle().toJson(),
      'baseUrl': 'http://127.0.0.1:57331?token=legacy-token',
      'password': 'legacy-token',
    });

    expect(handle.password, 'legacy-token');
    expect(handle.baseUri, Uri.parse('http://127.0.0.1:57331'));
  });

  test('conflicting legacy credentials fail closed', () {
    expect(
      () => CockpitRemoteSessionHandle.fromJson(<String, Object?>{
        ..._handle().toJson(),
        'baseUrl': 'http://127.0.0.1:57331?token=query-token',
        'password': 'field-token',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Conflicting remote authentication tokens'),
        ),
      ),
    );
  });
}
