import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_query_development_session_service.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_reference_resolver.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:cockpit/src/development/cockpit_development_session_supervisor_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'query service resolves a persisted development handle and reports the recommended next step',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_query_development_session_service',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final handle = _handle();
      final handleFile = File('${tempDir.path}/development_handle.json');
      await handleFile.writeAsString(jsonEncode(handle.toJson()));

      final service = CockpitQueryDevelopmentSessionService(
        sessionReferenceResolver:
            const CockpitDevelopmentSessionReferenceResolver(),
        statusReader: (supervisorBaseUri) async {
          expect(supervisorBaseUri, handle.supervisorBaseUri);
          return CockpitDevelopmentSessionSupervisorResponse(
            status: _readyStatus(handle),
            sessionHandle: handle,
          );
        },
      );

      final result = await service.query(
        CockpitQueryDevelopmentSessionRequest(
          sessionHandlePath: handleFile.path,
        ),
      );

      expect(result.sessionHandle?.toJson(), handle.toJson());
      expect(result.status.state, CockpitDevelopmentSessionState.ready);
      expect(result.recommendedNextStep, 'ready_for_incremental_probe');
    },
  );

  test(
    'query service directs unknown platform reachability to discovery',
    () async {
      final handle = _handle();
      final service = CockpitQueryDevelopmentSessionService(
        statusReader: (_) async => CockpitDevelopmentSessionSupervisorResponse(
          status: CockpitDevelopmentSessionStatus(
            developmentSessionId: handle.developmentSessionId,
            state: CockpitDevelopmentSessionState.starting,
            appReachable: null,
            remoteSessionReachable: false,
            reloadGeneration: handle.reloadGeneration,
            lastStatusAt: DateTime.utc(2026, 8, 14),
          ),
          sessionHandle: handle,
        ),
      );

      final result = await service.query(
        CockpitQueryDevelopmentSessionRequest(sessionHandle: handle),
      );

      expect(result.recommendedNextStep, 'discover_platform_target');
    },
  );
}

CockpitDevelopmentSessionHandle _handle() {
  return CockpitDevelopmentSessionHandle(
    developmentSessionId: 'dev-session-1',
    platform: 'ios',
    deviceId: 'simulator',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'lib/main.dart',
    appId: 'dev.cockpit.cockpit_demo',
    appBaseUrl: 'http://127.0.0.1:57331',
    supervisorBaseUrl: 'http://127.0.0.1:59421',
    launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
    reloadGeneration: 1,
  );
}

CockpitDevelopmentSessionStatus _readyStatus(
  CockpitDevelopmentSessionHandle handle,
) {
  return CockpitDevelopmentSessionStatus(
    developmentSessionId: handle.developmentSessionId,
    state: CockpitDevelopmentSessionState.ready,
    appReachable: true,
    remoteSessionReachable: true,
    reloadGeneration: handle.reloadGeneration,
    lastStatusAt: DateTime.utc(2026, 3, 23, 0, 1),
  );
}
