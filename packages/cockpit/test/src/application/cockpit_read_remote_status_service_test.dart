import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:cockpit/src/application/cockpit_read_remote_status_service.dart';
import 'package:cockpit/src/application/cockpit_session_reference_resolver.dart';
import 'package:cockpit/src/remote/cockpit_android_port_forwarder.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitReadRemoteStatusService', () {
    test('reads status through a session handle', () async {
      final handle = _sessionHandle();
      Uri? capturedBaseUri;
      final service = CockpitReadRemoteStatusService(
        readStatus: (baseUri) async {
          capturedBaseUri = baseUri;
          return _status(snapshot: CockpitSnapshot(routeName: '/home'));
        },
      );

      final result = await service.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: handle,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(capturedBaseUri, handle.baseUri);
      expect(result.sessionId, 'session-1');
      expect(result.currentRouteName, '/home');
      expect(result.snapshot, isNull);
      expect(result.uiSummary, isNull);
    });

    test('preserves active performance capture status', () async {
      final started = DateTime.utc(2026, 9, 5, 12, 0);
      final service = CockpitReadRemoteStatusService(
        readStatus: (_) async => _status(
          snapshot: CockpitSnapshot(routeName: '/profile'),
          performanceCapture: true,
          buildMode: 'profile',
          activePerformance: CockpitPerformanceCaptureSession(
            request: CockpitPerformanceCaptureRequest(name: 'profile'),
            startedAt: started,
            buildMode: 'profile',
          ),
        ),
      );

      final result = await service.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(result.performanceCapture, isTrue);
      expect(result.buildMode, 'profile');
      expect(result.activePerformance?.request.name, 'profile');
      expect(result.toJson()['build'], 'profile');
      expect(result.toJson()['activePerformance'], isNotNull);
    });

    test('reads a richer snapshot when the profile requires it', () async {
      CockpitSnapshotOptions? capturedOptions;
      final service = CockpitReadRemoteStatusService(
        readStatus: (_) async =>
            _status(snapshot: CockpitSnapshot(routeName: '/home')),
        readSnapshot: (_, options) async {
          capturedOptions = options;
          return CockpitRemoteSnapshotResponse(
            snapshot: CockpitSnapshot(
              routeName: '/details',
              diagnosticLevel: CockpitSnapshotProfile.investigate,
              visibleTargets: <CockpitSnapshotTarget>[
                CockpitSnapshotTarget(
                  registrationId: 'target-1',
                  routeName: '/details',
                  text: 'Details',
                ),
              ],
              summary: const CockpitSnapshotSummary(
                visibleTargetCount: 1,
                targetsWithCockpitIdCount: 0,
                targetsWithTextCount: 1,
                styleDetailsIncluded: true,
                diagnosticPropertiesIncluded: true,
                ancestorSummariesIncluded: false,
                rebuildSummaryIncluded: false,
                accessibilitySummaryIncluded: false,
              ),
            ),
          );
        },
      );

      final result = await service.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(capturedOptions?.profile, CockpitSnapshotProfile.investigate);
      expect(result.currentRouteName, '/details');
      expect(result.uiSummary?.routeName, '/details');
      expect(result.snapshot, isNull);
      expect(result.snapshotRef, isNotEmpty);
    });

    test('returns full snapshots for forensic reads', () async {
      final service = CockpitReadRemoteStatusService(
        readStatus: (_) async =>
            _status(snapshot: CockpitSnapshot(routeName: '/home')),
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/forensic',
            diagnosticLevel: CockpitSnapshotProfile.forensic,
          ),
        ),
      );

      final result = await service.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.evidence(),
        ),
      );

      expect(result.snapshot?.routeName, '/forensic');
      expect(result.uiSummary, isNull);
    });

    test('retries transient empty rich snapshots for read-app flows', () async {
      var readCount = 0;
      final service = CockpitReadRemoteStatusService(
        readStatus: (_) async =>
            _status(snapshot: CockpitSnapshot(routeName: '/settings')),
        readSnapshot: (_, _) async {
          readCount += 1;
          return CockpitRemoteSnapshotResponse(
            snapshot: readCount == 1
                ? CockpitSnapshot(
                    routeName: '/settings',
                    diagnosticLevel: CockpitSnapshotProfile.forensic,
                    summary: const CockpitSnapshotSummary(
                      visibleTargetCount: 0,
                      targetsWithCockpitIdCount: 0,
                      targetsWithTextCount: 0,
                      styleDetailsIncluded: true,
                      diagnosticPropertiesIncluded: true,
                      ancestorSummariesIncluded: true,
                      rebuildSummaryIncluded: true,
                      accessibilitySummaryIncluded: true,
                    ),
                  )
                : CockpitSnapshot(
                    routeName: '/settings',
                    diagnosticLevel: CockpitSnapshotProfile.forensic,
                    visibleTargets: <CockpitSnapshotTarget>[
                      CockpitSnapshotTarget(
                        registrationId: 'settings-save',
                        routeName: '/settings',
                        text: 'Save settings',
                      ),
                    ],
                    summary: const CockpitSnapshotSummary(
                      visibleTargetCount: 1,
                      targetsWithCockpitIdCount: 0,
                      targetsWithTextCount: 1,
                      styleDetailsIncluded: true,
                      diagnosticPropertiesIncluded: true,
                      ancestorSummariesIncluded: true,
                      rebuildSummaryIncluded: true,
                      accessibilitySummaryIncluded: true,
                    ),
                  ),
          );
        },
      );

      final result = await service.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.evidence(),
        ),
      );

      expect(readCount, 2);
      expect(result.currentRouteName, '/settings');
      expect(result.snapshot?.visibleTargets, isNotEmpty);
    });

    test('refreshes android host forwarding before reading status', () async {
      Uri? capturedBaseUri;
      final service = CockpitReadRemoteStatusService(
        sessionReferenceResolver: CockpitSessionReferenceResolver(
          portForwarder: CockpitAndroidPortForwarder(
            processRunner: (_, _) async =>
                ProcessResult(0, 0, 'emulator-5554 tcp:61331 tcp:47331\n', ''),
            hostPortAllocator: () async => 61331,
            hostPortAvailabilityChecker: (_) async => false,
          ),
        ),
        readStatus: (baseUri) async {
          capturedBaseUri = baseUri;
          return _status(snapshot: CockpitSnapshot(routeName: '/home'));
        },
      );

      await service.read(
        CockpitReadRemoteStatusRequest(
          sessionHandle: _androidSessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(capturedBaseUri.toString(), 'http://127.0.0.1:61331');
    });
  });
}

CockpitRemoteSessionStatus _status({
  required CockpitSnapshot snapshot,
  CockpitPerformanceCaptureSession? activePerformance,
  bool performanceCapture = false,
  String? buildMode,
}) {
  return CockpitRemoteSessionStatus(
    sessionId: 'session-1',
    platform: 'macos',
    transportType: 'remoteHttp',
    currentRouteName: snapshot.routeName,
    capabilities: CockpitCapabilities(
      platform: 'macos',
      transportType: 'remoteHttp',
      supportsInAppControl: true,
      supportsFlutterViewCapture: true,
      supportsNativeScreenCapture: true,
      supportsHostAutomation: false,
      supportedCommands: const <CockpitCommandType>[CockpitCommandType.tap],
      supportedLocatorStrategies: CockpitLocatorKind.values,
    ),
    recordingCapabilities: CockpitRecordingCapabilities(
      supportsNativeRecording: true,
      preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
    ),
    snapshot: snapshot,
    activePerformance: activePerformance,
    performanceCapture: performanceCapture,
    buildMode: buildMode,
  );
}

CockpitRemoteSessionHandle _sessionHandle() {
  return CockpitRemoteSessionHandle(
    platform: 'macos',
    deviceId: 'macos',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    appId: 'dev.cockpit.demo',
    host: '127.0.0.1',
    hostPort: 47331,
    devicePort: 47331,
    baseUrl: 'http://127.0.0.1:47331',
    launchedAt: DateTime.utc(2026, 3, 30),
  );
}

CockpitRemoteSessionHandle _androidSessionHandle() {
  return CockpitRemoteSessionHandle(
    platform: 'android',
    deviceId: 'emulator-5554',
    projectDir: '/workspace/examples/cockpit_demo',
    target: 'cockpit/main.dart',
    appId: 'dev.cockpit.demo',
    host: '127.0.0.1',
    hostPort: 47331,
    devicePort: 47331,
    baseUrl: 'http://127.0.0.1:47331',
    launchedAt: DateTime.utc(2026, 3, 30),
  );
}
