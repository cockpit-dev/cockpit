import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_execute_remote_command_service.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_data.dart';
import 'package:cockpit/src/application/cockpit_list_apps_service.dart';
import 'package:cockpit/src/application/cockpit_stop_app_service.dart';
import 'package:cockpit/src/development/cockpit_development_probe.dart';
import 'package:cockpit/src/development/cockpit_development_probe_delta.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:test/test.dart';

void main() {
  test('execute remote command result omits optional null sections', () {
    final json = const CockpitExecuteRemoteCommandResult(
      command: CockpitInteractiveCommandCore(
        commandId: 'tap-inbox',
        commandType: 'tap',
        success: true,
        durationMs: 120,
        usedCaptureFallback: false,
      ),
      artifacts: <CockpitInteractiveArtifactDescriptor>[],
    ).toJson();

    expect(json.containsKey('uiSummary'), isFalse);
    expect(json.containsKey('snapshot'), isFalse);
    expect(json.containsKey('diagnostics'), isFalse);
    expect(json.containsKey('delta'), isFalse);
    expect(json.containsKey('snapshotRef'), isFalse);
    expect(json.containsKey('sessionHandle'), isFalse);
    expect(json.containsKey('effectiveSnapshotOptions'), isFalse);
  });

  test('high-frequency app status models omit null optional fields', () {
    final appSummaryJson = CockpitAppSummary(
      appId: 'dev.example.app',
      mode: CockpitAppMode.development,
      platform: 'macos',
      deviceId: 'macos',
      projectDir: '/workspace/app',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:57331',
      updatedAt: DateTime.utc(2026, 4, 5),
    ).toJson();
    expect(appSummaryJson.containsKey('platformAppId'), isFalse);
    expect(appSummaryJson.containsKey('state'), isFalse);
    expect(appSummaryJson.containsKey('lastError'), isFalse);

    final developmentStatusJson = CockpitDevelopmentSessionStatus(
      developmentSessionId: 'dev-session-1',
      state: CockpitDevelopmentSessionState.ready,
      appReachable: true,
      remoteSessionReachable: true,
      reloadGeneration: 2,
      lastStatusAt: DateTime.utc(2026, 4, 5),
    ).toJson();
    expect(developmentStatusJson.containsKey('lastReloadMode'), isFalse);
    expect(developmentStatusJson.containsKey('lastReloadSucceeded'), isFalse);
    expect(developmentStatusJson.containsKey('lastError'), isFalse);

    final stopStatusJson = const CockpitAppStopStatus(
      mode: CockpitAppMode.automation,
      state: 'stopped',
      appReachable: false,
      remoteSessionReachable: false,
    ).toJson();
    expect(stopStatusJson.containsKey('lastError'), isFalse);
  });

  test('development probe models omit null optional fields', () {
    final probeJson = CockpitDevelopmentProbe(
      probeId: 'probe-1',
      sessionId: 'dev-session-1',
      reloadGeneration: 3,
      capturedAt: DateTime.utc(2026, 4, 5),
      reason: CockpitDevelopmentProbeReason.manual,
      profile: CockpitDevelopmentProbeProfile.quick,
      routeName: '/home',
    ).toJson();
    expect(probeJson.containsKey('checkpoint'), isFalse);

    final deltaJson = const CockpitDevelopmentProbeDelta(
      fromProbeId: 'probe-before',
      toProbeId: 'probe-after',
      reloadGenerationChanged: false,
      routeChanged: true,
      focusChanged: false,
      overlayChanged: false,
      visualChanged: false,
      screenshotChanged: false,
    ).toJson();
    expect(deltaJson.containsKey('changeSummary'), isFalse);
  });
}
