import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_app_reference_resolver.dart';
import 'package:cockpit/src/application/cockpit_inspect_surface_service.dart';
import 'package:cockpit/src/application/cockpit_inspect_ui_service.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/adapters/cockpit_capture_adapter.dart';
import 'package:cockpit/src/capture/cockpit_capture_strategy_resolver.dart';
import 'package:cockpit/src/capture/cockpit_host_capture_adapter.dart';
import 'package:cockpit/src/platform/cockpit_evidence_driver.dart';
import 'package:cockpit/src/platform/cockpit_platform_driver.dart';
import 'package:cockpit/src/platform/cockpit_platform_driver_registry.dart';
import 'package:cockpit/src/platform/ios/cockpit_ios_device_connection.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:cockpit/src/targets/cockpit_target_handle.dart';
import 'package:cockpit/src/targets/cockpit_target_reference_resolver.dart';
import 'package:test/test.dart';

void main() {
  test(
    'inspect surface reuses flutter inspection for desktop targets when available',
    () async {
      final service = CockpitInspectSurfaceService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'macos': ({required String deviceId}) =>
                _FakeEvidencePlatformDriver(
                  platform: 'macos',
                  capabilityProfile: CockpitCapabilityProfile(
                    targetKind: CockpitTargetKind.desktopApp,
                    surfaceKinds: <CockpitSurfaceKind>{
                      CockpitSurfaceKind.desktopWindow,
                      CockpitSurfaceKind.hostShell,
                    },
                    actionCapabilities: <CockpitActionCapability>{
                      CockpitActionCapability.captureScreenshot,
                    },
                    evidenceCapabilities: <CockpitEvidenceCapability>{
                      CockpitEvidenceCapability.windowCapture,
                    },
                  ),
                ),
          },
        ),
        inspectFlutterSurface: (_) async => const CockpitInspectUiResult(
          routeName: '/desktop-home',
          diagnosticLevel: 'inspect',
          truncated: false,
          locator: <String, Object?>{
            'query': 'Documents',
            'count': 1,
            'matches': <Object?>[
              <String, Object?>{'sel': 'Documents', 'can': 'tap'},
            ],
          },
        ),
      );

      final result = await service.inspect(
        CockpitInspectSurfaceRequest(
          target: CockpitTargetHandle(
            targetId: 'dev.cockpit.desktop.macos',
            targetKind: CockpitTargetKind.desktopApp,
            platform: 'macos',
            deviceId: 'macos',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            connection: const CockpitTargetConnection(
              baseUrl: 'http://127.0.0.1:57331',
            ),
            launchedAt: DateTime.utc(2026, 4, 11),
          ),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(result.routeName, '/desktop-home');
      expect(result.selectedPlane, CockpitPlaneKind.flutterSemanticPlane);
      expect(
        result.capabilityProfile.surfaceKinds,
        contains(CockpitSurfaceKind.flutterSemantic),
      );
      expect(result.recommendedNextStep, 'runNextCommand');
      expect(result.locator?['count'], 1);
    },
  );

  test(
    'inspect surface falls back to native evidence for desktop targets when flutter inspection is unavailable',
    () async {
      String? capturedAppId;
      final service = CockpitInspectSurfaceService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'macos': ({required String deviceId}) =>
                _FakeEvidencePlatformDriver(
                  platform: 'macos',
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
                  captureAdapter: _FakeHostCaptureAdapter(
                    execution: CockpitCommandExecution(
                      result: CockpitCommandResult(
                        success: true,
                        commandId: 'inspect-surface-capture',
                        commandType: CockpitCommandType.captureScreenshot,
                        durationMs: 42,
                        artifacts: const <CockpitArtifactRef>[
                          CockpitArtifactRef(
                            role: 'screenshot',
                            relativePath: 'screenshots/macos_inspect.png',
                          ),
                        ],
                        resolvedCaptureKind:
                            CockpitCaptureKind.nativeAcceptance,
                      ),
                      artifactSourcePaths: const <String, String>{
                        'screenshots/macos_inspect.png':
                            '/tmp/flutter_cockpit/macos_inspect.png',
                      },
                    ),
                  ),
                ),
          },
        ),
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => _UnexpectedRemoteCaptureAdapter(),
          macosAdapterFactory: (appId, {processId}) {
            capturedAppId = appId;
            return _FakeHostCaptureAdapter(
              execution: CockpitCommandExecution(
                result: CockpitCommandResult(
                  success: true,
                  commandId: 'inspect-surface-capture',
                  commandType: CockpitCommandType.captureScreenshot,
                  durationMs: 42,
                  artifacts: const <CockpitArtifactRef>[
                    CockpitArtifactRef(
                      role: 'screenshot',
                      relativePath: 'screenshots/macos_inspect.png',
                    ),
                  ],
                  resolvedCaptureKind: CockpitCaptureKind.nativeAcceptance,
                ),
                artifactSourcePaths: const <String, String>{
                  'screenshots/macos_inspect.png':
                      '/tmp/flutter_cockpit/macos_inspect.png',
                },
              ),
            );
          },
        ),
        inspectFlutterSurface: (_) async {
          throw const CockpitApplicationServiceException(
            code: 'remoteUnavailable',
            message: 'Remote flutter inspection is unavailable.',
          );
        },
      );

      final result = await service.inspect(
        CockpitInspectSurfaceRequest(
          target: CockpitTargetHandle(
            targetId: 'dev.cockpit.desktop.macos',
            targetKind: CockpitTargetKind.desktopApp,
            platform: 'macos',
            deviceId: 'macos',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            connection: const CockpitTargetConnection(
              baseUrl: 'http://127.0.0.1:57331',
            ),
            launchedAt: DateTime.utc(2026, 4, 11),
            metadata: const <String, Object?>{
              'platformAppId': 'dev.cockpit.real.desktop',
            },
          ),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(capturedAppId, 'dev.cockpit.real.desktop');
      expect(result.surfaceKind, CockpitSurfaceKind.desktopWindow);
      expect(result.selectedPlane, CockpitPlaneKind.nativeUiPlane);
      expect(result.snapshotRef, '/tmp/flutter_cockpit/macos_inspect.png');
      expect(result.recommendedNextStep, 'reviewCapture');
      expect(result.diagnostics?['artifacts'], isA<List<Object?>>());
    },
  );

  test(
    'inspect surface preserves windows process ids when reconstructing desktop host capture from a target handle',
    () async {
      String? capturedAppId;
      int? capturedProcessId;
      final target = CockpitTargetHandle.fromAppHandle(
        CockpitAppHandle(
          appId: 'dev.cockpit.desktop.windows',
          mode: CockpitAppMode.automation,
          platform: 'windows',
          deviceId: 'windows',
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          baseUrl: 'http://127.0.0.1:57331',
          launchedAt: DateTime.utc(2026, 4, 17),
          platformAppId: 'cockpit_demo',
          processId: 4101,
        ),
      );
      final service = CockpitInspectSurfaceService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => _UnexpectedRemoteCaptureAdapter(),
          windowsAdapterFactory: (appId, {processId}) {
            capturedAppId = appId;
            capturedProcessId = processId;
            return _FakeHostCaptureAdapter(
              execution: CockpitCommandExecution(
                result: CockpitCommandResult(
                  success: true,
                  commandId: 'inspect-surface-capture',
                  commandType: CockpitCommandType.captureScreenshot,
                  durationMs: 42,
                  artifacts: const <CockpitArtifactRef>[
                    CockpitArtifactRef(
                      role: 'screenshot',
                      relativePath: 'screenshots/windows_inspect.png',
                    ),
                  ],
                  resolvedCaptureKind: CockpitCaptureKind.nativeAcceptance,
                ),
                artifactSourcePaths: const <String, String>{
                  'screenshots/windows_inspect.png':
                      '/tmp/flutter_cockpit/windows_inspect.png',
                },
              ),
            );
          },
        ),
        inspectFlutterSurface: (_) async {
          throw const CockpitApplicationServiceException(
            code: 'remoteUnavailable',
            message: 'Remote flutter inspection is unavailable.',
          );
        },
      );

      final result = await service.inspect(
        CockpitInspectSurfaceRequest(
          target: target.copyWith(targetKind: CockpitTargetKind.desktopApp),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(capturedAppId, 'cockpit_demo');
      expect(capturedProcessId, 4101);
      expect(result.surfaceKind, CockpitSurfaceKind.desktopWindow);
      expect(result.snapshotRef, '/tmp/flutter_cockpit/windows_inspect.png');
    },
  );

  test(
    'inspect surface falls back to nested remote session identity when target metadata omits desktop host fields',
    () async {
      String? capturedAppId;
      int? capturedProcessId;
      final service = CockpitInspectSurfaceService(
        captureStrategyResolver: CockpitCaptureStrategyResolver(
          remoteAdapterFactory: (_) => _UnexpectedRemoteCaptureAdapter(),
          windowsAdapterFactory: (appId, {processId}) {
            capturedAppId = appId;
            capturedProcessId = processId;
            return _FakeHostCaptureAdapter(
              execution: CockpitCommandExecution(
                result: CockpitCommandResult(
                  success: true,
                  commandId: 'inspect-surface-capture',
                  commandType: CockpitCommandType.captureScreenshot,
                  durationMs: 42,
                  artifacts: const <CockpitArtifactRef>[
                    CockpitArtifactRef(
                      role: 'screenshot',
                      relativePath: 'screenshots/windows_nested_identity.png',
                    ),
                  ],
                  resolvedCaptureKind: CockpitCaptureKind.nativeAcceptance,
                ),
                artifactSourcePaths: const <String, String>{
                  'screenshots/windows_nested_identity.png':
                      '/tmp/flutter_cockpit/windows_nested_identity.png',
                },
              ),
            );
          },
        ),
        inspectFlutterSurface: (_) async {
          throw const CockpitApplicationServiceException(
            code: 'remoteUnavailable',
            message: 'Remote flutter inspection is unavailable.',
          );
        },
      );

      final result = await service.inspect(
        CockpitInspectSurfaceRequest(
          target: CockpitTargetHandle(
            targetId: 'machine-app-1',
            targetKind: CockpitTargetKind.desktopApp,
            platform: 'windows',
            deviceId: 'windows',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            connection: const CockpitTargetConnection(
              baseUrl: 'http://127.0.0.1:57331',
            ),
            launchedAt: DateTime.utc(2026, 5, 10),
            metadata: <String, Object?>{
              'appId': 'machine-app-1',
              'remoteSession': CockpitRemoteSessionHandle(
                platform: 'windows',
                deviceId: 'windows',
                projectDir: '/workspace/examples/cockpit_demo',
                target: 'cockpit/main.dart',
                appId: 'machine-app-1',
                platformAppId: 'cockpit_demo',
                host: '127.0.0.1',
                hostPort: 57331,
                devicePort: 57331,
                baseUrl: 'http://127.0.0.1:57331',
                launchedAt: DateTime.utc(2026, 5, 10),
                processId: 4101,
              ).toJson(),
            },
          ),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(capturedAppId, 'cockpit_demo');
      expect(capturedProcessId, 4101);
      expect(result.surfaceKind, CockpitSurfaceKind.desktopWindow);
      expect(
        result.snapshotRef,
        '/tmp/flutter_cockpit/windows_nested_identity.png',
      );
    },
  );

  test(
    'inspect surface rethrows unexpected desktop flutter inspection failures',
    () async {
      final service = CockpitInspectSurfaceService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'macos': ({required String deviceId}) =>
                _FakeEvidencePlatformDriver(
                  platform: 'macos',
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
        inspectFlutterSurface: (_) async {
          throw StateError('unexpected inspect failure');
        },
      );

      await expectLater(
        () => service.inspect(
          CockpitInspectSurfaceRequest(
            target: CockpitTargetHandle(
              targetId: 'dev.cockpit.desktop.macos',
              targetKind: CockpitTargetKind.desktopApp,
              platform: 'macos',
              deviceId: 'macos',
              projectDir: '/workspace/examples/cockpit_demo',
              target: 'cockpit/main.dart',
              connection: const CockpitTargetConnection(
                baseUrl: 'http://127.0.0.1:57331',
              ),
              launchedAt: DateTime.utc(2026, 4, 11),
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'inspect surface does not label physical iOS targets as simulator-only when flutter inspection succeeds',
    () async {
      final service = CockpitInspectSurfaceService(
        targetReferenceResolver: CockpitTargetReferenceResolver(
          appReferenceResolver: CockpitAppReferenceResolver(
            iosDeviceConnectionReader: (_) async =>
                const CockpitIosDeviceConnection(
                  isPhysical: true,
                  tunnelIpAddress: 'fd00::1',
                ),
          ),
        ),
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'ios': ({required String deviceId}) => _FakeEvidencePlatformDriver(
              platform: 'ios',
              capabilityProfile: CockpitCapabilityProfile(
                targetKind: CockpitTargetKind.flutterApp,
                surfaceKinds: const <CockpitSurfaceKind>{
                  CockpitSurfaceKind.flutterSemantic,
                  CockpitSurfaceKind.nativeUi,
                },
                actionCapabilities: const <CockpitActionCapability>{
                  CockpitActionCapability.captureScreenshot,
                  CockpitActionCapability.tap,
                },
                evidenceCapabilities: const <CockpitEvidenceCapability>{
                  CockpitEvidenceCapability.flutterScreenshot,
                  CockpitEvidenceCapability.nativeScreenshot,
                },
              ),
            ),
          },
        ),
        inspectFlutterSurface: (_) async => const CockpitInspectUiResult(
          routeName: '/physical-ios-home',
          diagnosticLevel: 'inspect',
          truncated: false,
        ),
      );

      final result = await service.inspect(
        CockpitInspectSurfaceRequest(
          target: CockpitTargetHandle(
            targetId: 'dev.cockpit.ios.device',
            targetKind: CockpitTargetKind.flutterApp,
            platform: 'ios',
            deviceId: '00008110-0009341C2EF3801E',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'cockpit/main.dart',
            connection: const CockpitTargetConnection(
              baseUrl: 'http://127.0.0.1:57331',
            ),
            launchedAt: DateTime.utc(2026, 4, 16),
          ),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(result.routeName, '/physical-ios-home');
      expect(
        result.capabilityProfile.qualityFlags,
        isNot(contains(CockpitQualityFlag.simulatorOnly)),
      );
    },
  );

  test(
    'inspect surface reuses flutter inspection for launched browser targets that retain app metadata',
    () async {
      CockpitInspectUiRequest? capturedRequest;
      final service = CockpitInspectSurfaceService(
        platformDriverRegistry: CockpitPlatformDriverRegistry(
          drivers: <String, CockpitPlatformDriverFactory>{
            'web': ({required String deviceId}) => _FakeEvidencePlatformDriver(
              platform: 'web',
              capabilityProfile: CockpitCapabilityProfile(
                targetKind: CockpitTargetKind.browserPage,
                surfaceKinds: const <CockpitSurfaceKind>{
                  CockpitSurfaceKind.browserDom,
                },
                actionCapabilities: const <CockpitActionCapability>{
                  CockpitActionCapability.tap,
                  CockpitActionCapability.captureScreenshot,
                },
                evidenceCapabilities: const <CockpitEvidenceCapability>{
                  CockpitEvidenceCapability.domSnapshot,
                },
              ),
            ),
          },
        ),
        inspectFlutterSurface: (request) async {
          capturedRequest = request;
          return const CockpitInspectUiResult(
            routeName: '/web-home',
            diagnosticLevel: 'inspect',
            truncated: false,
          );
        },
      );

      final result = await service.inspect(
        CockpitInspectSurfaceRequest(
          target: CockpitTargetHandle(
            targetId: 'chrome-demo',
            targetKind: CockpitTargetKind.browserPage,
            platform: 'web',
            deviceId: 'chrome',
            projectDir: '/workspace/examples/cockpit_demo',
            target: 'web',
            connection: const CockpitTargetConnection(
              baseUrl: 'http://127.0.0.1:57331',
            ),
            launchedAt: DateTime.utc(2026, 5, 10),
            metadata: const <String, Object?>{
              'appId': 'web-app',
              'appMode': 'development',
              'supportsHotReload': true,
            },
          ),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(capturedRequest?.app?.appId, 'web-app');
      expect(capturedRequest?.app?.mode, CockpitAppMode.development);
      expect(result.routeName, '/web-home');
      expect(result.selectedPlane, CockpitPlaneKind.flutterSemanticPlane);
      expect(result.recommendedNextStep, 'runNextCommand');
      expect(
        result.capabilityProfile.surfaceKinds,
        containsAll(<CockpitSurfaceKind>[
          CockpitSurfaceKind.browserDom,
          CockpitSurfaceKind.flutterSemantic,
        ]),
      );
    },
  );
}

final class _FakeEvidencePlatformDriver
    implements CockpitPlatformDriver, CockpitEvidenceDriver {
  const _FakeEvidencePlatformDriver({
    required this.platform,
    required this.capabilityProfile,
    this.captureAdapter,
  });

  @override
  final String platform;
  final CockpitCapabilityProfile capabilityProfile;
  @override
  final CockpitHostCaptureAdapter? captureAdapter;

  @override
  Future<CockpitCapabilityProfile> describeCapabilities() async {
    return capabilityProfile;
  }

  @override
  Null get recordingAdapter => null;
}

final class _FakeHostCaptureAdapter implements CockpitHostCaptureAdapter {
  const _FakeHostCaptureAdapter({required this.execution});

  final CockpitCommandExecution execution;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    return execution;
  }
}

final class _UnexpectedRemoteCaptureAdapter implements CockpitCaptureAdapter {
  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) {
    throw StateError('remote capture should not be used in this test');
  }
}
