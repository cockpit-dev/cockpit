import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_collect_development_probe_service.dart';
import 'package:cockpit/src/application/cockpit_collect_remote_snapshot_service.dart';
import 'package:cockpit/src/development/cockpit_development_probe.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_reference_resolver.dart';
import 'package:cockpit/src/foundation/cockpit_ids.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('development session handle round-trips through json', () {
    final remoteHandle = CockpitRemoteSessionHandle(
      platform: 'ios',
      deviceId: 'simulator',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'lib/main.dart',
      appId: 'dev.cockpit.cockpit_demo',
      host: '127.0.0.1',
      hostPort: 58421,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:58421',
      launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
    );
    final handle = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-1',
      platform: 'ios',
      deviceId: 'simulator',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'lib/main.dart',
      appId: 'dev.cockpit.cockpit_demo',
      appBaseUrl: 'http://127.0.0.1:58421',
      supervisorBaseUrl: 'http://127.0.0.1:59421',
      remoteSessionHandle: remoteHandle,
      launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
      lastReloadAt: DateTime.utc(2026, 3, 23, 0, 5),
      reloadGeneration: 3,
      vmServiceUri: Uri.parse('ws://127.0.0.1:34567/abcd/ws'),
    );

    final decoded = CockpitDevelopmentSessionHandle.fromJson(handle.toJson());

    expect(decoded.toJson(), handle.toJson());
    expect(decoded.baseUri, Uri.parse('http://127.0.0.1:58421'));
    expect(decoded.supervisorBaseUri, Uri.parse('http://127.0.0.1:59421'));
  });

  test('development probe accepts the supported probe profiles', () {
    final profiles = CockpitDevelopmentProbeProfile.values
        .map(
          (profile) => CockpitDevelopmentProbe(
            probeId: 'probe-${profile.jsonValue}',
            sessionId: 'dev-session-1',
            reloadGeneration: 2,
            capturedAt: DateTime.utc(2026, 3, 23, 1),
            reason: CockpitDevelopmentProbeReason.manual,
            checkpoint: 'before_edit',
            profile: profile,
            routeName: '/inbox',
          ),
        )
        .toList(growable: false);

    expect(
      profiles.map((probe) => probe.profile),
      orderedEquals(CockpitDevelopmentProbeProfile.values),
    );
    for (final probe in profiles) {
      expect(
        CockpitDevelopmentProbe.fromJson(probe.toJson()).toJson(),
        probe.toJson(),
      );
    }
  });

  test('development session resolver reads a persisted handle file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_dev_session_resolver',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final remoteHandle = CockpitRemoteSessionHandle(
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'lib/main.dart',
      appId: 'dev.cockpit.cockpit_demo',
      host: '127.0.0.1',
      hostPort: 57331,
      devicePort: 47331,
      baseUrl: 'http://127.0.0.1:57331',
      launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
    );
    final handle = CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-android',
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/examples/cockpit_demo',
      target: 'lib/main.dart',
      appId: 'dev.cockpit.cockpit_demo',
      appBaseUrl: 'http://127.0.0.1:57331',
      supervisorBaseUrl: 'http://127.0.0.1:59331',
      remoteSessionHandle: remoteHandle,
      launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
      reloadGeneration: 1,
    );
    final handleFile = File(p.join(tempDir.path, 'developmentSession.json'));
    await handleFile.writeAsString(jsonEncode(handle.toJson()));

    final resolver = CockpitDevelopmentSessionReferenceResolver();
    final resolved = await resolver.resolve(sessionHandlePath: handleFile.path);

    expect(resolved.sessionHandle?.toJson(), handle.toJson());
    expect(resolved.supervisorBaseUri, handle.supervisorBaseUri);
    expect(resolved.remoteBaseUri, handle.baseUri);
  });

  test(
    'collect builds an interactive development probe from a persisted handle',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_collect_development_probe',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 57331,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:57331',
        launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
      );
      final handle = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'dev-session-android',
        platform: 'android',
        deviceId: 'emulator-5554',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        appBaseUrl: 'http://127.0.0.1:57331',
        supervisorBaseUrl: 'http://127.0.0.1:59331',
        remoteSessionHandle: remoteHandle,
        launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
        reloadGeneration: 4,
      );
      final handleFile = File(p.join(tempDir.path, 'developmentSession.json'));
      await handleFile.writeAsString(jsonEncode(handle.toJson()));

      final service = CockpitCollectDevelopmentProbeService(
        collectRemoteSnapshot: (request) async {
          expect(request.baseUri, Uri.parse('http://127.0.0.1:57331'));
          expect(request.options.includeNetworkActivity, isTrue);
          expect(request.options.includeRuntimeActivity, isTrue);
          expect(request.options.includeAccessibilitySummary, isTrue);
          return CockpitCollectRemoteSnapshotResult(
            snapshot: CockpitSnapshot(
              routeName: '/settings',
              diagnosticLevel: CockpitSnapshotProfile.baseline,
              diagnosticsArtifactRef: const CockpitArtifactRef(
                role: 'diagnostics',
                relativePath: 'diagnostics/current_snapshot.json',
              ),
              visibleTargets: <CockpitSnapshotTarget>[
                CockpitSnapshotTarget(
                  registrationId: 'target-heading',
                  text: 'Settings',
                  typeName: 'Text',
                  routeName: '/settings',
                  supportedCommands: const <CockpitCommandType>[
                    CockpitCommandType.assertText,
                  ],
                ),
                CockpitSnapshotTarget(
                  registrationId: 'target-theme',
                  semanticId: 'settings-theme-toggle',
                  text: 'Theme',
                  typeName: 'SwitchListTile',
                  routeName: '/settings',
                  supportedCommands: const <CockpitCommandType>[
                    CockpitCommandType.tap,
                  ],
                ),
              ],
              network: CockpitNetworkSnapshot(
                totalEntryCount: 3,
                failureCount: 1,
                inFlightCount: 1,
                truncated: false,
                entries: <CockpitNetworkEntry>[
                  CockpitNetworkEntry(
                    requestId: 'network-1',
                    method: 'GET',
                    uri: '/sync/health',
                    startedAt: DateTime.utc(2026, 3, 23, 1, 0),
                    statusCode: 200,
                    durationMs: 300,
                  ),
                  CockpitNetworkEntry(
                    requestId: 'network-2',
                    method: 'POST',
                    uri: '/settings/save',
                    startedAt: DateTime.utc(2026, 3, 23, 1, 1),
                    statusCode: 500,
                    durationMs: 500,
                    error: 'server error',
                  ),
                ],
              ),
              runtime: CockpitRuntimeSnapshot(
                totalEntryCount: 2,
                errorCount: 1,
                warningCount: 0,
                truncated: false,
                entries: <CockpitRuntimeEvent>[
                  CockpitRuntimeEvent(
                    eventId: 'runtime-1',
                    kind: CockpitRuntimeEventKind.flutterError,
                    severity: CockpitRuntimeEventSeverity.error,
                    message: 'RenderFlex overflowed by 12 pixels',
                    recordedAt: DateTime.utc(2026, 3, 23, 1, 2),
                  ),
                ],
              ),
              rebuild: CockpitRebuildSnapshot(
                totalRebuildCount: 12,
                uniqueElementCount: 2,
                capturedEntryCount: 2,
                truncated: false,
                entries: const <CockpitRebuildEntry>[
                  CockpitRebuildEntry(
                    signature: 'settings.theme',
                    routeName: '/settings',
                    typeName: 'SwitchListTile',
                    rebuildCount: 8,
                    builtOnceCount: 1,
                    semanticId: 'settings-theme-toggle',
                    textPreview: 'Theme',
                  ),
                ],
              ),
              accessibility: CockpitAccessibilitySummary(
                totalAccessibleTargetCount: 2,
                traversalEntries: const <CockpitAccessibilityEntry>[
                  CockpitAccessibilityEntry(nodeId: 1, label: 'Settings'),
                  CockpitAccessibilityEntry(
                    nodeId: 2,
                    label: 'Theme',
                    identifier: 'settings-theme-toggle',
                  ),
                ],
                truncated: false,
              ),
            ),
            effectiveOptions: const CockpitSnapshotOptions(
              profile: CockpitSnapshotProfile.baseline,
              maxTargets: 24,
              maxAncestorsPerTarget: 1,
              maxPropertiesPerTarget: 4,
              includeNetworkActivity: true,
              includeRuntimeActivity: true,
              includeAccessibilitySummary: true,
            ),
            sessionHandle: remoteHandle,
            warnings: const <String>[
              'network query widened to include activity',
            ],
          );
        },
        collectScreenshot: (_, _) async => null,
        tokenGenerator: const _FixedTokenGenerator(),
      );

      final result = await service.collect(
        CockpitCollectDevelopmentProbeRequest(
          sessionHandlePath: handleFile.path,
          profile: CockpitDevelopmentProbeProfile.interactive,
          reason: CockpitDevelopmentProbeReason.postReload,
          checkpoint: 'after_reload',
        ),
      );

      expect(result.sessionHandle.toJson(), handle.toJson());
      expect(
        result.effectiveSnapshotOptions.profile,
        CockpitSnapshotProfile.baseline,
      );
      expect(
        result.warnings,
        contains('network query widened to include activity'),
      );
      expect(result.probe.profile, CockpitDevelopmentProbeProfile.interactive);
      expect(result.probe.probeId, 'q0000000001');
      expect(result.probe.reason, CockpitDevelopmentProbeReason.postReload);
      expect(result.probe.checkpoint, 'after_reload');
      expect(result.probe.routeName, '/settings');
      expect(
        result.probe.ui['visibleTextPreviews'],
        orderedEquals(const <String>['Settings', 'Theme']),
      );
      expect(
        result.probe.ui['visibleSemanticIds'],
        orderedEquals(const <String>['settings-theme-toggle']),
      );
      expect(
        result.probe.ui['interactiveLabels'],
        orderedEquals(const <String>['Settings', 'Theme']),
      );
      expect(
        result.probe.ui['accessibilityLabels'],
        orderedEquals(const <String>['Settings', 'Theme']),
      );
      expect(result.probe.network['failureCount'], 1);
      expect(
        result.probe.network['failureSignals'],
        orderedEquals(const <String>[
          'POST /settings/save -> 500 server error',
        ]),
      );
      expect(result.probe.runtime['errorCount'], 1);
      expect(
        result.probe.runtime['errorSignals'],
        orderedEquals(const <String>[
          'flutterError:error:RenderFlex overflowed by 12 pixels',
        ]),
      );
      expect(
        result.probe.rebuild['hotspots'],
        orderedEquals(const <String>['settings.theme']),
      );
      expect(
        result.probe.artifacts['diagnosticsArtifactPath'],
        'diagnostics/current_snapshot.json',
      );
    },
  );

  test(
    'interactive development probes include screenshot evidence and visual signals',
    () async {
      final remoteHandle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: 'simulator',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 58421,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:58421',
        launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
      );
      final handle = CockpitDevelopmentSessionHandle(
        developmentSessionId: 'dev-session-ios',
        platform: 'ios',
        deviceId: 'simulator',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        appBaseUrl: 'http://127.0.0.1:58421',
        supervisorBaseUrl: 'http://127.0.0.1:59421',
        remoteSessionHandle: remoteHandle,
        launchedAt: DateTime.utc(2026, 3, 23, 0, 0),
        reloadGeneration: 7,
      );

      final service = CockpitCollectDevelopmentProbeService(
        collectRemoteSnapshot: (_) async {
          return CockpitCollectRemoteSnapshotResult(
            snapshot: CockpitSnapshot(
              routeName: '/detail',
              diagnosticLevel: CockpitSnapshotProfile.baseline,
              visibleTargets: <CockpitSnapshotTarget>[
                CockpitSnapshotTarget(
                  registrationId: 'title',
                  text: 'Release readiness audit',
                  typeName: 'Text',
                  routeName: '/detail',
                  layout: CockpitSnapshotLayout(
                    width: 220,
                    height: 28,
                    dx: 24,
                    dy: 88,
                  ),
                  style: CockpitSnapshotStyle(
                    textColor: '#FFFEF3C7',
                    fontSize: 24,
                    fontWeight: 'w700',
                  ),
                ),
              ],
            ),
            effectiveOptions: const CockpitSnapshotOptions.baseline(),
          );
        },
        collectScreenshot: (sessionHandle, profile) async {
          expect(sessionHandle.developmentSessionId, 'dev-session-ios');
          expect(profile, CockpitDevelopmentProbeProfile.interactive);
          return const CockpitDevelopmentProbeScreenshot(
            path: '/tmp/dev-probe-1.png',
            byteCount: 4096,
            digest: 'fnv1a64:abc123',
            width: 1320,
            height: 2868,
          );
        },
      );

      final result = await service.collect(
        CockpitCollectDevelopmentProbeRequest(
          sessionHandle: handle,
          profile: CockpitDevelopmentProbeProfile.interactive,
          checkpoint: 'after_reload',
          reason: CockpitDevelopmentProbeReason.postReload,
        ),
      );

      expect(result.probe.artifacts['screenshotPath'], '/tmp/dev-probe-1.png');
      expect(result.probe.artifacts['screenshotDigest'], 'fnv1a64:abc123');
      expect(result.probe.artifacts['screenshotWidth'], 1320);
      expect(result.probe.artifacts['screenshotHeight'], 2868);
      expect(
        result.probe.ui['visualSignals'],
        orderedEquals(const <String>[
          'Text|Release readiness audit|24.0,88.0,220.0x28.0|#FFFEF3C7|24.0|w700',
        ]),
      );
    },
  );
}

final class _FixedTokenGenerator implements CockpitTokenGenerator {
  const _FixedTokenGenerator();

  @override
  String nextToken({int byteLength = 32}) => '0000000001';
}
