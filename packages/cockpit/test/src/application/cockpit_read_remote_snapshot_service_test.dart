import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:cockpit/src/application/cockpit_interactive_snapshot_store.dart';
import 'package:cockpit/src/application/cockpit_read_remote_snapshot_service.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  group('CockpitReadRemoteSnapshotService', () {
    test('reads snapshots with profile-normalized options', () async {
      CockpitSnapshotOptions? capturedOptions;
      final service = CockpitReadRemoteSnapshotService(
        readSnapshot: (_, options) async {
          capturedOptions = options;
          return CockpitRemoteSnapshotResponse(
            snapshot: CockpitSnapshot(
              routeName: '/details',
              diagnosticLevel: options.profile,
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
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.standard(),
        ),
      );

      expect(capturedOptions?.profile, CockpitSnapshotProfile.baseline);
      expect(result.uiSummary?.routeName, '/details');
      expect(result.snapshot, isNull);
      expect(result.snapshotRef, isNotEmpty);
    });

    test('returns full snapshots for forensic reads', () async {
      final service = CockpitReadRemoteSnapshotService(
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/forensic',
            diagnosticLevel: CockpitSnapshotProfile.forensic,
          ),
        ),
      );

      final result = await service.read(
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.evidence(),
        ),
      );

      expect(result.snapshot?.routeName, '/forensic');
      expect(result.uiSummary, isNull);
    });

    test(
      'preserves externalized diagnostics artifact download metadata',
      () async {
        final service = CockpitReadRemoteSnapshotService(
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: CockpitSnapshot(
              routeName: '/forensic',
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
        );

        final result = await service.read(
          CockpitReadRemoteSnapshotRequest(
            sessionHandle: _sessionHandle(),
            resultProfile: const CockpitInteractiveResultProfile.evidence(),
          ),
        );

        expect(result.snapshot?.diagnosticsArtifactRef, isNotNull);
        expect(result.artifactDownloads, hasLength(1));
        expect(result.toJson()['artifactDownloads'], isA<List<Object?>>());
      },
    );

    test('resolves complete evidence diagnostics from its artifact', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'cockpit-evidence-snapshot-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final artifact = File('${temporary.path}/snapshot.json');
      final complete = CockpitSnapshot(
        routeName: '/failure',
        runtime: CockpitRuntimeSnapshot(
          totalEntryCount: 1,
          errorCount: 1,
          warningCount: 0,
          capturedEntryCount: 1,
          entries: <CockpitRuntimeEvent>[
            CockpitRuntimeEvent(
              eventId: 'runtime-error',
              kind: CockpitRuntimeEventKind.flutterError,
              severity: CockpitRuntimeEventSeverity.error,
              message: 'Complete runtime evidence',
              recordedAt: DateTime.utc(2026, 8, 13),
            ),
          ],
        ),
      );
      await artifact.writeAsString(jsonEncode(complete.toJson()));
      const artifactRef = CockpitArtifactRef(
        role: 'diagnostics',
        relativePath: 'diagnostics/evidence.json',
      );
      final service = CockpitReadRemoteSnapshotService(
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/failure',
            diagnosticsArtifactRef: artifactRef,
          ),
          artifactDownloads: const <CockpitRemoteArtifactDownload>[
            CockpitRemoteArtifactDownload(
              artifact: artifactRef,
              downloadPath: '/artifacts/evidence.json',
            ),
          ],
        ),
        downloadArtifacts: (_, _) async => <String, String>{
          artifactRef.relativePath: artifact.path,
        },
      );

      final result = await service.read(
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.evidence(),
        ),
      );

      expect(
        result.diagnostics?['runtime'].toString(),
        contains('Complete runtime evidence'),
      );
      expect(result.snapshot?.visibleTargets, isEmpty);
      expect(result.completeSnapshot?.runtime?.entries, hasLength(1));
      expect(result.artifactDownloads, hasLength(1));
      expect(await artifact.exists(), isTrue);
    });

    test('retries transient empty snapshots before returning', () async {
      var readCount = 0;
      final service = CockpitReadRemoteSnapshotService(
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
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.evidence(),
        ),
      );

      expect(readCount, 2);
      expect(result.snapshot?.routeName, '/settings');
      expect(result.snapshot?.visibleTargets, isNotEmpty);
    });

    test('does not retry an empty targeted snapshot', () async {
      var readCount = 0;

      final response = await cockpitReadRemoteSnapshotConsistently(
        baseUri: _sessionHandle().baseUri,
        options: const CockpitSnapshotOptions(query: 'Missing target'),
        readSnapshot: (_, _) async {
          readCount += 1;
          return CockpitRemoteSnapshotResponse(
            snapshot: _emptySnapshot('/editor'),
          );
        },
      );

      expect(readCount, 1);
      expect(response.snapshot.visibleTargets, isEmpty);
    });

    test('waits for remote ui idle before one final snapshot retry', () async {
      var readCount = 0;
      Uri? waitedBaseUri;
      Duration? waitedQuietWindow;
      Duration? waitedTimeout;
      bool? waitedIncludeNetworkIdle;

      final response = await cockpitReadRemoteSnapshotConsistently(
        baseUri: _sessionHandle().baseUri,
        options: const CockpitSnapshotOptions.forensic(),
        readSnapshot: (_, _) async {
          readCount += 1;
          return CockpitRemoteSnapshotResponse(
            snapshot: readCount < 4
                ? _emptySnapshot('/editor')
                : CockpitSnapshot(
                    routeName: '/editor',
                    diagnosticLevel: CockpitSnapshotProfile.forensic,
                    visibleTargets: <CockpitSnapshotTarget>[
                      CockpitSnapshotTarget(
                        registrationId: 'editor-save',
                        routeName: '/editor',
                        text: 'Save task',
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
        waitForUiIdle:
            (
              baseUri, {
              required quietWindow,
              required timeout,
              required includeNetworkIdle,
            }) async {
              waitedBaseUri = baseUri;
              waitedQuietWindow = quietWindow;
              waitedTimeout = timeout;
              waitedIncludeNetworkIdle = includeNetworkIdle;
              return true;
            },
      );

      expect(readCount, 4);
      expect(waitedBaseUri, _sessionHandle().baseUri);
      expect(waitedQuietWindow, const Duration(milliseconds: 96));
      expect(waitedTimeout, const Duration(milliseconds: 1600));
      expect(waitedIncludeNetworkIdle, isTrue);
      expect(response.snapshot.visibleTargets, isNotEmpty);
    });

    test(
      'still performs one final snapshot read after an idle wait attempt returns false',
      () async {
        var readCount = 0;

        final response = await cockpitReadRemoteSnapshotConsistently(
          baseUri: _sessionHandle().baseUri,
          options: const CockpitSnapshotOptions.forensic(),
          readSnapshot: (_, _) async {
            readCount += 1;
            return CockpitRemoteSnapshotResponse(
              snapshot: readCount < 4
                  ? _emptySnapshot('/editor')
                  : CockpitSnapshot(
                      routeName: '/editor',
                      diagnosticLevel: CockpitSnapshotProfile.forensic,
                      visibleTargets: <CockpitSnapshotTarget>[
                        CockpitSnapshotTarget(
                          registrationId: 'editor-title',
                          routeName: '/editor',
                          text: 'Task title',
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
          waitForUiIdle:
              (
                baseUri, {
                required quietWindow,
                required timeout,
                required includeNetworkIdle,
              }) async {
                return false;
              },
        );

        expect(readCount, 4);
        expect(response.snapshot.visibleTargets, isNotEmpty);
      },
    );

    test('all transition retries share one remote read deadline', () async {
      var readCount = 0;
      final stopwatch = Stopwatch()..start();

      await expectLater(
        cockpitReadRemoteSnapshotConsistently(
          baseUri: _sessionHandle().baseUri,
          options: const CockpitSnapshotOptions.forensic(),
          deadline: DateTime.now().toUtc().add(
            const Duration(milliseconds: 220),
          ),
          readSnapshot: (_, _) {
            readCount += 1;
            if (readCount == 1) {
              return Future<CockpitRemoteSnapshotResponse>.value(
                CockpitRemoteSnapshotResponse(
                  snapshot: _emptySnapshot('/editor'),
                ),
              );
            }
            return Completer<CockpitRemoteSnapshotResponse>().future;
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
      stopwatch.stop();

      expect(readCount, 2);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('filters failures-only diagnostics for inspect reads', () async {
      final service = CockpitReadRemoteSnapshotService(
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/inspect',
            diagnosticLevel: CockpitSnapshotProfile.investigate,
            network: CockpitNetworkSnapshot(
              totalEntryCount: 1,
              failureCount: 1,
              entries: <CockpitNetworkEntry>[
                CockpitNetworkEntry(
                  requestId: 'network-1',
                  method: 'GET',
                  uri: 'https://example.com/fail',
                  startedAt: DateTime.utc(2026, 3, 30),
                  durationMs: 80,
                  statusCode: 500,
                ),
              ],
              capturedEntryCount: 1,
            ),
            runtime: CockpitRuntimeSnapshot(
              totalEntryCount: 1,
              errorCount: 1,
              warningCount: 0,
              entries: <CockpitRuntimeEvent>[
                CockpitRuntimeEvent(
                  eventId: 'runtime-1',
                  kind: CockpitRuntimeEventKind.flutterError,
                  severity: CockpitRuntimeEventSeverity.error,
                  message: 'boom',
                  recordedAt: DateTime.utc(2026, 3, 30),
                ),
              ],
            ),
            rebuild: const CockpitRebuildSnapshot(
              totalRebuildCount: 3,
              uniqueElementCount: 1,
              capturedEntryCount: 1,
              truncated: false,
              entries: <CockpitRebuildEntry>[],
            ),
            accessibility: CockpitAccessibilitySummary(
              totalAccessibleTargetCount: 1,
              traversalEntries: const <CockpitAccessibilityEntry>[
                CockpitAccessibilityEntry(nodeId: 1, label: 'Inspect'),
              ],
              truncated: false,
            ),
          ),
        ),
      );

      final result = await service.read(
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: _sessionHandle(),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(result.diagnostics?['level'], 'failures_only');
      expect(result.diagnostics?['network'], isNotNull);
      expect(result.diagnostics?['runtime'], isNotNull);
      expect(result.diagnostics?.containsKey('rebuild'), isFalse);
      expect(result.diagnostics?.containsKey('accessibility'), isFalse);
    });

    test('reports missing compare refs as structured errors', () async {
      final service = CockpitReadRemoteSnapshotService(
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(routeName: '/details'),
        ),
      );

      expect(
        () => service.read(
          CockpitReadRemoteSnapshotRequest(
            sessionHandle: _sessionHandle(),
            compareAgainstSnapshotRef: 'missing-ref',
          ),
        ),
        throwsA(
          isA<CockpitApplicationServiceException>().having(
            (error) => error.code,
            'code',
            'interactiveSnapshotRefNotFound',
          ),
        ),
      );
    });

    test('returns deltas when comparing with a stored snapshot', () async {
      final store = CockpitInteractiveSnapshotStore();
      final baselineRef = store.put(
        sessionKey: _sessionHandle().baseUri.toString(),
        snapshot: CockpitSnapshot(
          routeName: '/before',
          visibleTargets: <CockpitSnapshotTarget>[
            CockpitSnapshotTarget(
              registrationId: 'target-1',
              routeName: '/before',
              text: 'Before',
            ),
          ],
        ),
      );
      final service = CockpitReadRemoteSnapshotService(
        snapshotStore: store,
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/after',
            visibleTargets: <CockpitSnapshotTarget>[
              CockpitSnapshotTarget(
                registrationId: 'target-1',
                routeName: '/after',
                text: 'After',
              ),
            ],
          ),
        ),
      );

      final result = await service.read(
        CockpitReadRemoteSnapshotRequest(
          sessionHandle: _sessionHandle(),
          compareAgainstSnapshotRef: baselineRef,
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(result.delta?.routeChanged, isTrue);
      expect(result.delta?.addedTextPreviews, contains('After'));
    });
  });
}

CockpitSnapshot _emptySnapshot(String routeName) {
  return CockpitSnapshot(
    routeName: routeName,
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
