import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_collect_remote_snapshot_service.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'collect service resolves a persisted session handle and preserves forensic artifact preferences',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_collect_remote_snapshot_service',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final handle = CockpitRemoteSessionHandle(
        platform: 'ios',
        deviceId: 'simulator',
        projectDir: '/workspace/examples/cockpit_demo',
        target: 'lib/main.dart',
        appId: 'dev.cockpit.cockpit_demo',
        host: '127.0.0.1',
        hostPort: 58421,
        devicePort: 47331,
        baseUrl: 'http://127.0.0.1:58421',
        launchedAt: DateTime.utc(2026, 3, 22, 0, 0),
      );
      final sessionJsonFile = File(p.join(tempDir.path, 'sessionHandle.json'));
      await sessionJsonFile.writeAsString(jsonEncode(handle.toJson()));

      Uri? capturedBaseUri;
      CockpitSnapshotOptions? capturedOptions;
      final service = CockpitCollectRemoteSnapshotService(
        snapshotReader: (baseUri, options) async {
          capturedBaseUri = baseUri;
          capturedOptions = options;
          return CockpitRemoteSnapshotResponse(
            snapshot: CockpitSnapshot(
              routeName: '/inbox',
              diagnosticLevel: options.profile,
              truncated: true,
            ),
          );
        },
      );

      final result = await service.collect(
        CockpitCollectRemoteSnapshotRequest(
          sessionHandlePath: sessionJsonFile.path,
          options: const CockpitSnapshotOptions.forensic(),
        ),
      );

      expect(capturedBaseUri, handle.baseUri);
      expect(capturedOptions?.profile, CockpitSnapshotProfile.forensic);
      expect(capturedOptions?.artifact, CockpitSnapshotArtifactMode.large);
      expect(result.snapshot.routeName, '/inbox');
      expect(result.effectiveOptions.profile, CockpitSnapshotProfile.forensic);
      expect(
        result.effectiveOptions.artifact,
        CockpitSnapshotArtifactMode.large,
      );
      expect(result.sessionHandle?.toJson(), handle.toJson());
      expect(result.warnings, isEmpty);
    },
  );

  test(
    'collect service keeps externalized diagnostics artifacts summarized by default',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      var artifactDownloadCount = 0;

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('GET', '/snapshot'):
            request.response.write(
              jsonEncode(<String, Object?>{
                'snapshot': CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  diagnosticsArtifactRef: const CockpitArtifactRef(
                    role: 'diagnostics',
                    relativePath: 'diagnostics/remote_snapshot_debug.json',
                  ),
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      text: 'Run check',
                      routeName: '/debug',
                    ),
                  ],
                ).toJson(),
                'artifactDownloads': const <Map<String, Object?>>[
                  <String, Object?>{
                    'artifact': <String, Object?>{
                      'role': 'diagnostics',
                      'relativePath': 'diagnostics/remote_snapshot_debug.json',
                    },
                    'downloadPath':
                        '/artifacts/download?path=diagnostics%2Fremote_snapshot_debug.json',
                  },
                ],
              }),
            );
          case ('GET', '/artifacts/download'):
            artifactDownloadCount += 1;
            request.response.write(
              jsonEncode(
                CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      text: 'Run check',
                      routeName: '/debug',
                      diagnosticProperties: <CockpitDiagnosticProperty>[
                        CockpitDiagnosticProperty(
                          name: 'payload',
                          value: 'x' * 24000,
                          category: CockpitDiagnosticCategory.other,
                        ),
                      ],
                    ),
                  ],
                ).toJson(),
              ),
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final service = CockpitCollectRemoteSnapshotService();

      final result = await service.collect(
        CockpitCollectRemoteSnapshotRequest(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          options: const CockpitSnapshotOptions.forensic(),
        ),
      );

      expect(artifactDownloadCount, 0);
      expect(
        result.snapshot.diagnosticsArtifactRef?.relativePath,
        'diagnostics/remote_snapshot_debug.json',
      );
      expect(
        result.snapshot.visibleTargets.single.diagnosticProperties,
        isEmpty,
      );
    },
  );

  test(
    'collect service downloads externalized diagnostics artifacts only when requested',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      var artifactDownloadCount = 0;

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('GET', '/snapshot'):
            request.response.write(
              jsonEncode(<String, Object?>{
                'snapshot': CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  diagnosticsArtifactRef: const CockpitArtifactRef(
                    role: 'diagnostics',
                    relativePath: 'diagnostics/remote_snapshot_debug.json',
                  ),
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      text: 'Run check',
                      routeName: '/debug',
                    ),
                  ],
                ).toJson(),
                'artifactDownloads': const <Map<String, Object?>>[
                  <String, Object?>{
                    'artifact': <String, Object?>{
                      'role': 'diagnostics',
                      'relativePath': 'diagnostics/remote_snapshot_debug.json',
                    },
                    'downloadPath':
                        '/artifacts/download?path=diagnostics%2Fremote_snapshot_debug.json',
                  },
                ],
              }),
            );
          case ('GET', '/artifacts/download'):
            artifactDownloadCount += 1;
            request.response.write(
              jsonEncode(
                CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      text: 'Run check',
                      routeName: '/debug',
                      diagnosticProperties: <CockpitDiagnosticProperty>[
                        CockpitDiagnosticProperty(
                          name: 'payload',
                          value: 'x' * 24000,
                          category: CockpitDiagnosticCategory.other,
                        ),
                      ],
                    ),
                  ],
                ).toJson(),
              ),
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final service = CockpitCollectRemoteSnapshotService();

      final result = await service.collect(
        CockpitCollectRemoteSnapshotRequest(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          options: const CockpitSnapshotOptions.forensic(),
          downloadDiagnosticsArtifacts: true,
        ),
      );

      expect(artifactDownloadCount, 1);
      expect(
        result
            .snapshot
            .visibleTargets
            .single
            .diagnosticProperties
            .single
            .value
            .length,
        greaterThan(20000),
      );
    },
  );
}
