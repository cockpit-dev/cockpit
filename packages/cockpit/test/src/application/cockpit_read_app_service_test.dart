import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_app_reference_resolver.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:cockpit/src/application/cockpit_read_app_service.dart';
import 'package:cockpit/src/application/cockpit_read_remote_status_service.dart';
import 'package:cockpit/src/platform/cockpit_platform_driver.dart';
import 'package:cockpit/src/platform/cockpit_platform_driver_registry.dart';
import 'package:cockpit/src/remote/cockpit_android_port_forwarder.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test(
    'read app returns refreshed remote session handles for app-first reads',
    () async {
      Uri? capturedBaseUri;
      final service = CockpitReadAppService(
        appReferenceResolver: CockpitAppReferenceResolver(
          portForwarder: CockpitAndroidPortForwarder(
            processRunner: (_, _) async =>
                ProcessResult(0, 0, 'emulator-5554 tcp:61331 tcp:47331\n', ''),
            hostPortAllocator: () async => 61331,
            hostPortAvailabilityChecker: (_) async => false,
          ),
        ),
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (baseUri) async {
            capturedBaseUri = baseUri;
            return CockpitRemoteSessionStatus(
              sessionId: 'session-android',
              platform: 'android',
              transportType: 'remoteHttp',
              currentRouteName: '/home',
              capabilities: CockpitCapabilities(
                platform: 'android',
                transportType: 'remoteHttp',
                supportsInAppControl: true,
                supportsFlutterViewCapture: true,
                supportsNativeScreenCapture: true,
                supportsHostAutomation: false,
                supportedCommands: const <CockpitCommandType>[
                  CockpitCommandType.tap,
                ],
                supportedLocatorStrategies: CockpitLocatorKind.values,
              ),
              recordingCapabilities: CockpitRecordingCapabilities(
                supportsNativeRecording: true,
                preferredAcceptanceRecordingKind:
                    CockpitRecordingKind.nativeScreen,
              ),
              snapshot: CockpitSnapshot(routeName: '/home'),
            );
          },
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: CockpitAppHandle(
            appId: 'android-app',
            mode: CockpitAppMode.automation,
            platform: 'android',
            deviceId: 'emulator-5554',
            projectDir: '/workspace/app',
            target: 'cockpit/main.dart',
            baseUrl: 'http://127.0.0.1:57331',
            launchedAt: DateTime.utc(2026, 5, 10),
            remoteSession: CockpitRemoteSessionHandle(
              platform: 'android',
              deviceId: 'emulator-5554',
              projectDir: '/workspace/app',
              target: 'cockpit/main.dart',
              appId: 'android-app',
              host: '127.0.0.1',
              hostPort: 57331,
              devicePort: 47331,
              baseUrl: 'http://127.0.0.1:57331',
              launchedAt: DateTime.utc(2026, 5, 10),
            ),
          ),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(capturedBaseUri.toString(), 'http://127.0.0.1:61331');
      expect(result.app?.baseUrl, 'http://127.0.0.1:61331');
      expect(result.app?.remoteSession?.baseUrl, 'http://127.0.0.1:61331');
      expect(result.app?.remoteSession?.devicePort, 47331);
    },
  );

  test('read app includes selected plane and recommended next step', () async {
    final app = CockpitAppHandle(
      appId: 'dev.cockpit.demo',
      mode: CockpitAppMode.automation,
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:47331',
      launchedAt: DateTime.utc(2026, 4, 11),
    );
    final service = CockpitReadAppService(
      remoteStatusService: CockpitReadRemoteStatusService(
        readStatus: (_) async => CockpitRemoteSessionStatus(
          sessionId: 'session-1',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: false,
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.tap,
            ],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      ),
    );

    final result = await service.read(
      CockpitReadAppRequest(
        app: app,
        resultProfile: const CockpitInteractiveResultProfile.minimal(),
      ),
    );

    expect(result.selectedPlane, CockpitPlaneKind.flutterSemanticPlane);
    expect(result.fallbackTrail, <CockpitPlaneKind>[
      CockpitPlaneKind.nativeUiPlane,
      CockpitPlaneKind.deviceSystemPlane,
    ]);
    expect(result.recommendedNextStep, 'runNextCommand');
    expect(result.toJson()['selectedPlane'], 'flutterSemanticPlane');
  });

  test('read app preserves performance capability and active capture', () async {
    final started = DateTime.utc(2026, 9, 5, 12, 0);
    final service = CockpitReadAppService(
      remoteStatusService: CockpitReadRemoteStatusService(
        readStatus: (_) async => CockpitRemoteSessionStatus(
          sessionId: 'session-1',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: false,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
          performanceCapture: true,
          buildMode: 'profile',
          activePerformance: CockpitPerformanceCaptureSession(
            request: CockpitPerformanceCaptureRequest(name: 'home'),
            startedAt: started,
            buildMode: 'profile',
          ),
        ),
      ),
    );

    final result = await service.read(
      CockpitReadAppRequest(
        app: CockpitAppHandle(
          appId: 'dev.cockpit.demo',
          mode: CockpitAppMode.automation,
          platform: 'android',
          deviceId: 'emulator-5554',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          baseUrl: 'http://127.0.0.1:47331',
          launchedAt: DateTime.utc(2026, 4, 11),
        ),
        resultProfile: const CockpitInteractiveResultProfile.minimal(),
      ),
    );

    expect(result.performanceCapture, isTrue);
    expect(result.buildMode, 'profile');
    expect(result.activePerformance?.request.name, 'home');
    expect(result.toJson()['activePerformance'], isNotNull);
  });

  test('read app preserves diagnostics artifact download metadata', () async {
    final app = CockpitAppHandle(
      appId: 'dev.cockpit.demo',
      mode: CockpitAppMode.automation,
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'cockpit/main.dart',
      baseUrl: 'http://127.0.0.1:47331',
      launchedAt: DateTime.utc(2026, 4, 11),
    );
    final service = CockpitReadAppService(
      remoteStatusService: CockpitReadRemoteStatusService(
        readStatus: (_) async => CockpitRemoteSessionStatus(
          sessionId: 'session-1',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/debug',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: false,
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.tap,
            ],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/debug'),
        ),
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/debug',
            diagnosticLevel: CockpitSnapshotProfile.forensic,
            diagnosticsArtifactRef: const CockpitArtifactRef(
              role: 'diagnostics',
              relativePath: 'diagnostics/remote_snapshot_debug.json',
            ),
          ),
          artifactDownloads: const <CockpitRemoteArtifactDownload>[
            CockpitRemoteArtifactDownload(
              artifact: CockpitArtifactRef(
                role: 'diagnostics',
                relativePath: 'diagnostics/remote_snapshot_debug.json',
              ),
              downloadPath:
                  '/artifacts/download?path=diagnostics%2Fremote_snapshot_debug.json',
            ),
          ],
        ),
      ),
    );

    final result = await service.read(
      CockpitReadAppRequest(
        app: app,
        resultProfile: const CockpitInteractiveResultProfile.evidence(),
      ),
    );

    expect(result.artifactDownloads, hasLength(1));
    expect(result.toJson()['artifactDownloads'], isA<List<Object?>>());
  });

  test(
    'read app keeps platform-specific capability profile details when the driver exposes extra target abilities',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.web',
        mode: CockpitAppMode.development,
        platform: 'web',
        deviceId: 'chrome',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:48331',
        launchedAt: DateTime.utc(2026, 4, 11),
      );
      final service = CockpitReadAppService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'web': ({required String deviceId}) => _FakePlatformDriver(
              platform: 'web',
              capabilityProfile: CockpitCapabilityProfile(
                targetKind: CockpitTargetKind.browserPage,
                surfaceKinds: const <CockpitSurfaceKind>{
                  CockpitSurfaceKind.browserDom,
                },
                actionCapabilities: const <CockpitActionCapability>{
                  CockpitActionCapability.captureScreenshot,
                  CockpitActionCapability.startRecording,
                  CockpitActionCapability.stopRecording,
                },
                evidenceCapabilities: const <CockpitEvidenceCapability>{
                  CockpitEvidenceCapability.domSnapshot,
                  CockpitEvidenceCapability.screenRecording,
                },
              ),
            ),
          },
        ),
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-web',
            platform: 'web',
            transportType: 'remoteHttp',
            currentRouteName: '/inbox',
            capabilities: CockpitCapabilities(
              platform: 'web',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: false,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
                CockpitCommandType.captureScreenshot,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
              recordingLimitations: const <String>[
                'Browser recording is best-effort when multiple browser windows share the same host process.',
              ],
            ),
            snapshot: CockpitSnapshot(routeName: '/inbox'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(result.capabilities.platform, 'web');
      expect(result.selectedPlane, CockpitPlaneKind.flutterSemanticPlane);
      expect(
        result.capabilities.capabilityProfile?.targetKind,
        CockpitTargetKind.browserPage,
      );
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        contains(CockpitActionCapability.startRecording),
      );
      expect(result.recordingCapabilities.supportsNativeRecording, isTrue);
      expect(
        result.recordingCapabilities.recordingLimitations.join(' '),
        contains('best-effort'),
      );
    },
  );

  test(
    'read app keeps browser recording disabled when the target browser has no host recording support',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.web.safari',
        mode: CockpitAppMode.development,
        platform: 'web',
        deviceId: 'safari',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:48331',
        launchedAt: DateTime.utc(2026, 4, 11),
      );
      final service = CockpitReadAppService(
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-web-safari',
            platform: 'web',
            transportType: 'remoteHttp',
            currentRouteName: '/inbox',
            capabilities: CockpitCapabilities(
              platform: 'web',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: false,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
                CockpitCommandType.captureScreenshot,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(routeName: '/inbox'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.startRecording)),
      );
      expect(result.recordingCapabilities.supportsNativeRecording, isFalse);
    },
  );

  test(
    'read app does not promote linux recording when the merged capability profile lacks recording support',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.linux',
        mode: CockpitAppMode.automation,
        platform: 'linux',
        deviceId: 'linux',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:49331',
        launchedAt: DateTime.utc(2026, 5, 10),
        platformAppId: 'cockpit_demo',
      );
      final service = CockpitReadAppService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'linux': ({required String deviceId}) => _FakePlatformDriver(
              platform: 'linux',
              capabilityProfile: CockpitCapabilityProfile(
                targetKind: CockpitTargetKind.desktopApp,
                surfaceKinds: const <CockpitSurfaceKind>{
                  CockpitSurfaceKind.desktopWindow,
                  CockpitSurfaceKind.hostShell,
                },
                actionCapabilities: const <CockpitActionCapability>{
                  CockpitActionCapability.captureScreenshot,
                },
                evidenceCapabilities: const <CockpitEvidenceCapability>{
                  CockpitEvidenceCapability.windowCapture,
                },
              ),
            ),
          },
        ),
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-linux',
            platform: 'linux',
            transportType: 'remoteHttp',
            currentRouteName: '/desktop-home',
            capabilities: CockpitCapabilities(
              platform: 'linux',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: true,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(routeName: '/desktop-home'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(result.recordingCapabilities.supportsNativeRecording, isFalse);
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.startRecording)),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.screenRecording)),
      );
    },
  );

  test(
    'read app points browser targets at visibility recovery when the route is known but no targets are visible',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.web.zero-targets',
        mode: CockpitAppMode.development,
        platform: 'web',
        deviceId: 'chrome',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:58331',
        launchedAt: DateTime.utc(2026, 4, 12),
      );
      final service = CockpitReadAppService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'web': ({required String deviceId}) => _FakePlatformDriver(
              platform: 'web',
              capabilityProfile: CockpitCapabilityProfile(
                targetKind: CockpitTargetKind.browserPage,
                surfaceKinds: const <CockpitSurfaceKind>{
                  CockpitSurfaceKind.browserDom,
                },
                actionCapabilities: const <CockpitActionCapability>{
                  CockpitActionCapability.captureScreenshot,
                },
                evidenceCapabilities: const <CockpitEvidenceCapability>{
                  CockpitEvidenceCapability.domSnapshot,
                },
                qualityFlags: const <CockpitQualityFlag>{
                  CockpitQualityFlag.requiresBrowserDriver,
                },
              ),
            ),
          },
        ),
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-web-zero-targets',
            platform: 'web',
            transportType: 'remoteHttp',
            currentRouteName: '/inbox',
            capabilities: CockpitCapabilities(
              platform: 'web',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: false,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(
              routeName: '/inbox',
              summary: const CockpitSnapshotSummary(
                visibleTargetCount: 0,
                targetsWithCockpitIdCount: 0,
                targetsWithTextCount: 0,
                styleDetailsIncluded: false,
                diagnosticPropertiesIncluded: false,
                ancestorSummariesIncluded: false,
                rebuildSummaryIncluded: false,
                accessibilitySummaryIncluded: false,
              ),
            ),
          ),
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: CockpitSnapshot(
              routeName: '/inbox',
              summary: const CockpitSnapshotSummary(
                visibleTargetCount: 0,
                targetsWithCockpitIdCount: 0,
                targetsWithTextCount: 0,
                styleDetailsIncluded: false,
                diagnosticPropertiesIncluded: false,
                ancestorSummariesIncluded: false,
                rebuildSummaryIncluded: false,
                accessibilitySummaryIncluded: false,
              ),
            ),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.standard(),
        ),
      );

      expect(result.uiSummary?.visibleTargetCount, 0);
      expect(result.recommendedNextStep, 'recoverBrowserVisibility');
      expect(
        result.whatMatters,
        contains('no visible targets were discovered'),
      );
      expect(result.whatMatters, contains('/inbox'));
    },
  );

  test(
    'read app promotes host automation when the platform driver exposes host shell support',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.macos',
        mode: CockpitAppMode.development,
        platform: 'macos',
        deviceId: 'macos',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:49331',
        launchedAt: DateTime.utc(2026, 4, 11),
      );
      final service = CockpitReadAppService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'macos': ({required String deviceId}) => _FakePlatformDriver(
              platform: 'macos',
              capabilityProfile: CockpitCapabilityProfile(
                targetKind: CockpitTargetKind.desktopApp,
                surfaceKinds: const <CockpitSurfaceKind>{
                  CockpitSurfaceKind.desktopWindow,
                  CockpitSurfaceKind.hostShell,
                },
                actionCapabilities: const <CockpitActionCapability>{
                  CockpitActionCapability.captureScreenshot,
                  CockpitActionCapability.runShell,
                },
                evidenceCapabilities: const <CockpitEvidenceCapability>{
                  CockpitEvidenceCapability.windowCapture,
                },
              ),
            ),
          },
        ),
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-macos',
            platform: 'macos',
            transportType: 'remoteHttp',
            currentRouteName: '/inbox',
            capabilities: CockpitCapabilities(
              platform: 'macos',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
                CockpitCommandType.captureScreenshot,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: true,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(routeName: '/inbox'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(result.capabilities.supportsHostAutomation, isTrue);
      expect(
        result.capabilities.capabilityProfile?.surfaceKinds,
        contains(CockpitSurfaceKind.hostShell),
      );
    },
  );

  test(
    'read app keeps desktop host evidence disabled when the driver has no bound evidence adapters',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.windows',
        mode: CockpitAppMode.development,
        platform: 'windows',
        deviceId: 'windows',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:51331',
        launchedAt: DateTime.utc(2026, 4, 17),
      );
      final service = CockpitReadAppService(
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-windows',
            platform: 'windows',
            transportType: 'remoteHttp',
            currentRouteName: '/home',
            capabilities: CockpitCapabilities(
              platform: 'windows',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(routeName: '/home'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.captureScreenshot)),
      );
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.startRecording)),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.windowCapture)),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.screenRecording)),
      );
      expect(result.recordingCapabilities.supportsNativeRecording, isFalse);
    },
  );

  test(
    'read app includes desktop host evidence when the launched app carries a bound platform app id',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.windows',
        mode: CockpitAppMode.development,
        platform: 'windows',
        deviceId: 'windows',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:51331',
        launchedAt: DateTime.utc(2026, 4, 17),
        platformAppId: 'cockpit_demo',
        processId: 4101,
      );
      final service = CockpitReadAppService(
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-windows-bound',
            platform: 'windows',
            transportType: 'remoteHttp',
            currentRouteName: '/home',
            capabilities: CockpitCapabilities(
              platform: 'windows',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(routeName: '/home'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        contains(CockpitActionCapability.captureScreenshot),
      );
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        contains(CockpitActionCapability.startRecording),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        contains(CockpitEvidenceCapability.windowCapture),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        contains(CockpitEvidenceCapability.screenRecording),
      );
      expect(result.recordingCapabilities.supportsNativeRecording, isTrue);
    },
  );

  test(
    'read app keeps Android recording disabled when runtime health reports native recording unavailable',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.android',
        mode: CockpitAppMode.development,
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:52331',
        launchedAt: DateTime.utc(2026, 4, 17),
      );
      final service = CockpitReadAppService(
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-android-recording-unavailable',
            platform: 'android',
            transportType: 'remoteHttp',
            currentRouteName: '/home',
            capabilities: CockpitCapabilities(
              platform: 'android',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
              recordingLimitations: const <String>[
                'Screen recording consent is unavailable in the current activity.',
              ],
            ),
            snapshot: CockpitSnapshot(routeName: '/home'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(result.recordingCapabilities.supportsNativeRecording, isFalse);
      expect(
        result.recordingCapabilities.recordingLimitations.join(' '),
        contains('unavailable'),
      );
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.startRecording)),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.screenRecording)),
      );
    },
  );

  test(
    'read app keeps iOS recording disabled when runtime health reports ReplayKit unavailable',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.ios.device',
        mode: CockpitAppMode.development,
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:53331',
        launchedAt: DateTime.utc(2026, 4, 17),
      );
      final service = CockpitReadAppService(
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-ios-recording-unavailable',
            platform: 'ios',
            transportType: 'remoteHttp',
            currentRouteName: '/home',
            capabilities: CockpitCapabilities(
              platform: 'ios',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: false,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
              recordingLimitations: const <String>[
                'Native recording requires iOS 14 or newer.',
              ],
            ),
            snapshot: CockpitSnapshot(routeName: '/home'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(result.recordingCapabilities.supportsNativeRecording, isFalse);
      expect(
        result.recordingCapabilities.recordingLimitations.join(' '),
        contains('iOS 14'),
      );
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.startRecording)),
      );
      expect(
        result.capabilities.capabilityProfile?.evidenceCapabilities,
        isNot(contains(CockpitEvidenceCapability.screenRecording)),
      );
    },
  );

  test(
    'read app does not inherit simulator-only capabilities for physical iOS devices',
    () async {
      final app = CockpitAppHandle(
        appId: 'dev.cockpit.ios.device',
        mode: CockpitAppMode.development,
        platform: 'ios',
        deviceId: '00008110-0009341C2EF3801E',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'cockpit/main.dart',
        baseUrl: 'http://127.0.0.1:50331',
        launchedAt: DateTime.utc(2026, 4, 16),
      );
      final service = CockpitReadAppService(
        remoteStatusService: CockpitReadRemoteStatusService(
          readStatus: (_) async => CockpitRemoteSessionStatus(
            sessionId: 'session-ios-device',
            platform: 'ios',
            transportType: 'remoteHttp',
            currentRouteName: '/home',
            capabilities: CockpitCapabilities(
              platform: 'ios',
              transportType: 'remoteHttp',
              supportsInAppControl: true,
              supportsFlutterViewCapture: true,
              supportsNativeScreenCapture: true,
              supportsHostAutomation: false,
              supportedCommands: const <CockpitCommandType>[
                CockpitCommandType.tap,
              ],
              supportedLocatorStrategies: CockpitLocatorKind.values,
            ),
            recordingCapabilities: CockpitRecordingCapabilities(
              supportsNativeRecording: true,
              preferredAcceptanceRecordingKind:
                  CockpitRecordingKind.nativeScreen,
            ),
            snapshot: CockpitSnapshot(routeName: '/home'),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadAppRequest(
          app: app,
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(
        result.capabilities.capabilityProfile?.qualityFlags,
        isNot(contains(CockpitQualityFlag.simulatorOnly)),
      );
      expect(
        result.capabilities.capabilityProfile?.actionCapabilities,
        isNot(contains(CockpitActionCapability.runShell)),
      );
    },
  );
}

final class _FakePlatformDriver implements CockpitPlatformDriver {
  const _FakePlatformDriver({
    required this.platform,
    required this.capabilityProfile,
  });

  @override
  final String platform;
  final CockpitCapabilityProfile capabilityProfile;

  @override
  Future<CockpitCapabilityProfile> describeCapabilities() async {
    return capabilityProfile;
  }
}
