import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_app_reference_resolver.dart';
import 'package:cockpit/src/application/cockpit_inspect_ui_service.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:cockpit/src/application/cockpit_read_remote_snapshot_service.dart';
import 'package:cockpit/src/remote/cockpit_android_port_forwarder.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test(
    'app-first inspection returns the refreshed remote session handle',
    () async {
      Uri? capturedBaseUri;
      final service = CockpitInspectUiService(
        appReferenceResolver: CockpitAppReferenceResolver(
          portForwarder: CockpitAndroidPortForwarder(
            processRunner: (_, _) async =>
                ProcessResult(0, 0, 'emulator-5554 tcp:61331 tcp:47331\n', ''),
            hostPortAllocator: () async => 61331,
            hostPortAvailabilityChecker: (_) async => false,
          ),
        ),
        snapshotService: CockpitReadRemoteSnapshotService(
          readSnapshot: (baseUri, options) async {
            capturedBaseUri = baseUri;
            return CockpitRemoteSnapshotResponse(
              snapshot: CockpitSnapshot(
                routeName: '/home',
                diagnosticLevel: options.profile,
              ),
            );
          },
        ),
      );

      final result = await service.inspect(
        CockpitInspectUiRequest(
          app: _androidAppHandle(),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(capturedBaseUri.toString(), 'http://127.0.0.1:61331');
      expect(result.routeName, '/home');
      expect(result.snapshot, isNull);
    },
  );

  test(
    'locator inspection reduces a large snapshot artifact in-process',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-locator-snapshot-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final artifact = File('${temporary.path}/snapshot.json');
      final snapshot = CockpitSnapshot(
        routeName: '/large',
        visibleTargets: List<CockpitSnapshotTarget>.generate(
          2000,
          (index) => CockpitSnapshotTarget(
            registrationId: 'target-$index',
            keyValue: 'target-$index',
            text: 'Target $index',
            routeName: '/large',
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.tap,
            ],
          ),
        ),
        summary: const CockpitSnapshotSummary(
          visibleTargetCount: 2000,
          targetsWithCockpitIdCount: 0,
          targetsWithTextCount: 2000,
          styleDetailsIncluded: false,
          diagnosticPropertiesIncluded: false,
          ancestorSummariesIncluded: false,
          rebuildSummaryIncluded: false,
          accessibilitySummaryIncluded: false,
        ),
      );
      await artifact.writeAsString(jsonEncode(snapshot.toJson()));
      const artifactRef = CockpitArtifactRef(
        role: 'diagnostics',
        relativePath: 'diagnostics/snapshot.json',
      );
      final service = CockpitInspectUiService(
        appReferenceResolver: CockpitAppReferenceResolver(),
        snapshotService: CockpitReadRemoteSnapshotService(
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: CockpitSnapshot(
              routeName: '/large',
              visibleTargets: snapshot.visibleTargets.take(24).toList(),
              diagnosticsArtifactRef: artifactRef,
              summary: snapshot.summary,
              truncated: true,
            ),
            artifactDownloads: const <CockpitRemoteArtifactDownload>[
              CockpitRemoteArtifactDownload(
                artifact: artifactRef,
                downloadPath: '/artifacts/download?path=snapshot.json',
              ),
            ],
          ),
          downloadArtifacts: (_, _) async => <String, String>{
            artifactRef.relativePath: artifact.path,
          },
        ),
      );

      final result = await service.inspect(
        CockpitInspectUiRequest(
          baseUri: Uri.parse('http://127.0.0.1:61331'),
          resultProfile: const CockpitInteractiveResultProfile.locate(),
          snapshotOptions: const CockpitSnapshotOptions(
            profile: CockpitSnapshotProfile.baseline,
            maxTargets: 10000,
            artifact: CockpitSnapshotArtifactMode.large,
          ).copyWith(query: 'Target 1999'),
        ),
      );

      expect(result.locator?['count'], 1);
      expect(result.locator?['matches'], <Object?>[
        <String, Object?>{
          'sel': '@target-1999',
          'label': 'Target 1999',
          'can': 'tap',
        },
      ]);
      expect(result.snapshot?.visibleTargets, hasLength(24));
      expect(result.artifactDownloads, isEmpty);
      expect(result.artifactSourcePaths, isEmpty);
      expect(await artifact.exists(), isFalse);
      expect(jsonEncode(result.toJson()).length, lessThan(250000));
    },
  );

  test(
    'locator miss reads one unfiltered snapshot and returns mounted context',
    () async {
      CockpitSnapshotOptions? capturedOptions;
      final service = CockpitInspectUiService(
        appReferenceResolver: CockpitAppReferenceResolver(),
        snapshotService: CockpitReadRemoteSnapshotService(
          readSnapshot: (_, options) async {
            capturedOptions = options;
            return CockpitRemoteSnapshotResponse(
              snapshot: CockpitSnapshot(
                routeName: '/upgrade',
                visibleTargets: <CockpitSnapshotTarget>[
                  for (var index = 0; index < 6; index += 1)
                    CockpitSnapshotTarget(
                      registrationId: 'action-$index',
                      cockpitId: 'action-$index',
                      text: 'Action $index',
                      routeName: '/upgrade',
                      supportedCommands: const <CockpitCommandType>[
                        CockpitCommandType.tap,
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      );

      final result = await service.inspect(
        CockpitInspectUiRequest(
          baseUri: Uri.parse('http://127.0.0.1:61331'),
          resultProfile: const CockpitInteractiveResultProfile.locate(),
          snapshotOptions: const CockpitSnapshotOptions.baseline().copyWith(
            query: 'Missing target',
          ),
        ),
      );

      expect(capturedOptions?.query, isNull);
      expect(result.locator?['count'], 0);
      expect(result.locator?['route'], '/upgrade');
      expect(result.locator?['mounted'], hasLength(4));
    },
  );

  test('locator inspection removes an invalid temporary artifact', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-invalid-locator-snapshot-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final artifact = File('${temporary.path}/snapshot.json');
    await artifact.writeAsString('{invalid');
    const artifactRef = CockpitArtifactRef(
      role: 'diagnostics',
      relativePath: 'diagnostics/snapshot.json',
    );
    final service = CockpitInspectUiService(
      appReferenceResolver: CockpitAppReferenceResolver(),
      snapshotService: CockpitReadRemoteSnapshotService(
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/invalid',
            diagnosticsArtifactRef: artifactRef,
          ),
          artifactDownloads: const <CockpitRemoteArtifactDownload>[
            CockpitRemoteArtifactDownload(
              artifact: artifactRef,
              downloadPath: '/artifacts/download?path=snapshot.json',
            ),
          ],
        ),
        downloadArtifacts: (_, _) async => <String, String>{
          artifactRef.relativePath: artifact.path,
        },
      ),
    );

    await expectLater(
      service.inspect(
        CockpitInspectUiRequest(
          baseUri: Uri.parse('http://127.0.0.1:61331'),
          resultProfile: const CockpitInteractiveResultProfile.locate(),
          snapshotOptions: const CockpitSnapshotOptions(
            profile: CockpitSnapshotProfile.baseline,
            artifact: CockpitSnapshotArtifactMode.large,
          ),
        ),
      ),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.code,
          'code',
          'snapshotArtifactInvalid',
        ),
      ),
    );
    expect(await artifact.exists(), isFalse);
  });
}

CockpitAppHandle _androidAppHandle() {
  return CockpitAppHandle(
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
  );
}
