import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_query_remote_session_service.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'query service resolves a persisted session handle and returns status with a recommended next step',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_query_remote_session_service',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final handle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 58421,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:58421',
        launchedAt: DateTime.utc(2026, 3, 21, 0, 0),
      );
      final sessionJsonFile = File(p.join(tempDir.path, 'sessionHandle.json'));
      await sessionJsonFile.writeAsString(jsonEncode(handle.toJson()));

      final expectedStatus = CockpitRemoteSessionStatus(
        sessionId: 'query-demo',
        platform: 'ios',
        transportType: 'remoteHttp',
        currentRouteName: '/ready',
        capabilities: CockpitCapabilities(
          platform: 'ios',
          transportType: 'remoteHttp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: true,
          supportsHostAutomation: false,
          supportedCommands: <CockpitCommandType>[CockpitCommandType.tap],
          supportedLocatorStrategies: CockpitLocatorKind.values,
        ),
        recordingCapabilities: CockpitRecordingCapabilities(
          supportsNativeRecording: true,
          preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        ),
        snapshot: CockpitSnapshot(routeName: '/ready'),
      );

      final service = CockpitQueryRemoteSessionService(
        statusReader: (baseUri, {String password = ''}) async {
          expect(baseUri.toString(), handle.baseUrl);
          return expectedStatus;
        },
      );

      final result = await service.query(
        CockpitQueryRemoteSessionRequest(
          sessionHandlePath: sessionJsonFile.path,
        ),
      );

      expect(result.status.sessionId, 'query-demo');
      expect(result.sessionHandle?.toJson(), handle.toJson());
      expect(result.recommendedNextStep, 'ready_for_commands');
    },
  );

  test('query service rejects requests without a session reference', () async {
    final service = CockpitQueryRemoteSessionService(
      statusReader: (_, {String password = ''}) async =>
          throw UnimplementedError(),
    );

    expect(
      () => service.query(const CockpitQueryRemoteSessionRequest()),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.code,
          'code',
          'missingSessionReference',
        ),
      ),
    );
  });
}
