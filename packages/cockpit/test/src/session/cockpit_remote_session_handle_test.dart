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

void main() {
  test('fromRemoteStatus prefers the explicit launch token', () {
    // The app reports its session id; the launch token is a separate
    // credential. A handle must authenticate with the token it was launched
    // with, never with an incidental session id.
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
      authToken: 'launch-token-9',
    );

    expect(handle.authToken, 'launch-token-9');
    expect(
      handle.baseUri,
      Uri.parse('http://127.0.0.1:57331?token=launch-token-9'),
    );
  });

  test('fromRemoteStatus falls back to the session id without a token', () {
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

    expect(handle.authToken, 'app-session-id');
    expect(
      handle.baseUri,
      Uri.parse('http://127.0.0.1:57331?token=app-session-id'),
    );
  });
}
