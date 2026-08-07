import 'package:flutter_cockpit/flutter_cockpit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CockpitRemoteSessionConfiguration preserves loopback server settings',
    () {
      const configuration = CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        host: '127.0.0.1',
        port: 47331,
        routePrefix: '/cockpit',
        launchId: 'launch-1',
      );

      expect(
        CockpitRemoteSessionConfiguration.fromJson(configuration.toJson()),
        configuration,
      );
    },
  );

  test(
    'CockpitRemoteSessionConfiguration resolve leaves explicit config unchanged without overrides',
    () {
      const configuration = CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        host: '127.0.0.1',
        port: 47331,
        routePrefix: '/cockpit',
      );

      expect(
        CockpitRemoteSessionConfiguration.resolve(
          fallback: configuration,
          defines: const <String, String>{},
        ),
        configuration,
      );
    },
  );

  test(
    'CockpitRemoteSessionConfiguration resolve applies host and port overrides',
    () {
      const configuration = CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: true,
        host: '127.0.0.1',
        port: 47331,
        routePrefix: '',
      );

      expect(
        CockpitRemoteSessionConfiguration.resolve(
          fallback: configuration,
          defines: const <String, String>{
            'FLUTTER_COCKPIT_REMOTE_HOST': '0.0.0.0',
            'FLUTTER_COCKPIT_REMOTE_PORT': '49321',
            'FLUTTER_COCKPIT_REMOTE_ROUTE_PREFIX': '/session',
            'FLUTTER_COCKPIT_REMOTE_LAUNCH_ID': 'launch-override',
          },
        ),
        const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: true,
          host: '0.0.0.0',
          port: 49321,
          routePrefix: '/session',
          launchId: 'launch-override',
        ),
      );
    },
  );

  test(
    'CockpitRemoteSessionConfiguration resolve can create config from environment-only enablement',
    () {
      expect(
        CockpitRemoteSessionConfiguration.resolve(
          defines: const <String, String>{
            'FLUTTER_COCKPIT_REMOTE_ENABLED': 'true',
            'FLUTTER_COCKPIT_REMOTE_PORT': '48484',
          },
        ),
        const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: true,
          host: '127.0.0.1',
          port: 48484,
          routePrefix: '',
        ),
      );
    },
  );

  test('CockpitRemoteSessionStatus preserves health metadata', () {
    final status = CockpitRemoteSessionStatus(
      sessionId: 'demo-session',
      platform: 'android',
      transportType: 'remoteHttp',
      currentRouteName: '/form',
      processId: 4242,
      capabilities: CockpitCapabilities(
        platform: 'android',
        transportType: 'inApp',
        supportsInAppControl: true,
        supportsFlutterViewCapture: true,
        supportsNativeScreenCapture: true,
        supportsHostAutomation: false,
        supportedCommands: <CockpitCommandType>[
          CockpitCommandType.tap,
          CockpitCommandType.captureScreenshot,
        ],
        supportedLocatorStrategies: CockpitLocatorKind.values,
        capabilityProfile: CockpitCapabilityProfile(
          targetKind: CockpitTargetKind.flutterApp,
          surfaceKinds: <CockpitSurfaceKind>{
            CockpitSurfaceKind.flutterSemantic,
            CockpitSurfaceKind.nativeUi,
          },
          actionCapabilities: <CockpitActionCapability>{
            CockpitActionCapability.tap,
            CockpitActionCapability.captureScreenshot,
          },
          evidenceCapabilities: <CockpitEvidenceCapability>{
            CockpitEvidenceCapability.flutterScreenshot,
            CockpitEvidenceCapability.nativeScreenshot,
          },
        ),
      ),
      recordingCapabilities: CockpitRecordingCapabilities(
        supportsNativeRecording: true,
        preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        recordingLimitations: const <String>['Consent required.'],
      ),
      snapshot: CockpitSnapshot(
        routeName: '/form',
        visibleTargets: <CockpitSnapshotTarget>[
          CockpitSnapshotTarget(
            registrationId: 'form.submit',
            cockpitId: 'submit_button',
            text: 'Submit',
            typeName: 'ElevatedButton',
            routeName: '/form',
            supportedCommands: <CockpitCommandType>[CockpitCommandType.tap],
          ),
        ],
      ),
      activeRecording: const CockpitRecordingSession(
        request: CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'form_acceptance',
          attachToStep: true,
        ),
        state: CockpitRecordingState.recording,
      ),
    );

    expect(CockpitRemoteSessionStatus.fromJson(status.toJson()), status);
    expect(status.toJson()['processId'], 4242);
    expect(
      status.toJson()['capabilities'],
      isA<Map<String, Object?>>().having(
        (value) => value['capabilityProfile'],
        'capabilityProfile',
        isA<Map<String, Object?>>(),
      ),
    );
  });

  test(
    'CockpitRemoteSessionStatus preserves optional environment metadata',
    () {
      final status = CockpitRemoteSessionStatus.fromJson(<String, Object?>{
        'sessionId': 'demo-session',
        'platform': 'android',
        'transportType': 'remoteHttp',
        'currentRouteName': '/form',
        'capabilities': CockpitCapabilities(
          platform: 'android',
          transportType: 'inApp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: true,
          supportsHostAutomation: false,
          supportedCommands: <CockpitCommandType>[
            CockpitCommandType.tap,
            CockpitCommandType.captureScreenshot,
          ],
          supportedLocatorStrategies: CockpitLocatorKind.values,
          capabilityProfile: CockpitCapabilityProfile(
            targetKind: CockpitTargetKind.flutterApp,
            surfaceKinds: <CockpitSurfaceKind>{
              CockpitSurfaceKind.flutterSemantic,
              CockpitSurfaceKind.nativeUi,
            },
            actionCapabilities: <CockpitActionCapability>{
              CockpitActionCapability.tap,
              CockpitActionCapability.captureScreenshot,
            },
            evidenceCapabilities: <CockpitEvidenceCapability>{
              CockpitEvidenceCapability.flutterScreenshot,
            },
          ),
        ).toJson(),
        'recordingCapabilities': CockpitRecordingCapabilities(
          supportsNativeRecording: true,
          preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        ).toJson(),
        'snapshot': CockpitSnapshot(routeName: '/form').toJson(),
        'environment': const CockpitEnvironment(
          platform: 'android',
          flutterVersion: '3.38.9',
          dartVersion: '3.10.8',
        ).toJson(),
      });

      expect(status.toJson()['environment'], const <String, Object?>{
        'platform': 'android',
        'flutterVersion': '3.38.9',
        'dartVersion': '3.10.8',
      });
    },
  );

  test(
    'CockpitRemoteCommandResponse preserves result and inline artifact payloads',
    () {
      final response = CockpitRemoteCommandResponse(
        result: CockpitCommandResult(
          success: true,
          commandId: 'capture-home',
          commandType: CockpitCommandType.captureScreenshot,
          durationMs: 18,
          artifacts: const <CockpitArtifactRef>[
            CockpitArtifactRef(
              role: 'screenshot',
              relativePath: 'screenshots/home_acceptance.png',
            ),
          ],
          requestedCaptureProfile: CockpitCaptureProfile.acceptance,
          resolvedCaptureKind: CockpitCaptureKind.nativeAcceptance,
        ),
        artifactPayloads: const <CockpitRemoteArtifactPayload>[
          CockpitRemoteArtifactPayload(
            artifact: CockpitArtifactRef(
              role: 'screenshot',
              relativePath: 'screenshots/home_acceptance.png',
            ),
            bytes: <int>[137, 80, 78, 71],
          ),
        ],
      );

      expect(
        CockpitRemoteCommandResponse.fromJson(response.toJson()),
        response,
      );
    },
  );

  test(
    'CockpitRemoteCommandResponse ignores orphaned inline artifact payloads',
    () {
      final response = CockpitRemoteCommandResponse.fromExecution(
        CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'capture-home',
            commandType: CockpitCommandType.captureScreenshot,
            durationMs: 18,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/home_acceptance.png',
              ),
            ],
          ),
          artifactPayloads: const <String, List<int>>{
            'screenshots/home_acceptance.png': <int>[137, 80, 78, 71],
            'screenshots/orphaned.png': <int>[1, 2, 3],
          },
        ),
      );

      expect(response.artifactPayloads, hasLength(1));
      expect(
        response.artifactPayloads.single.artifact.relativePath,
        'screenshots/home_acceptance.png',
      );
    },
  );
}
