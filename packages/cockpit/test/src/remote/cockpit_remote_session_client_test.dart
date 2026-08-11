import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'remote session client reads health, snapshot, command, and recording flows',
    () async {
      Uri? snapshotRequestUri;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('GET', '/health'):
            request.response.write(
              jsonEncode(
                CockpitRemoteSessionStatus(
                  sessionId: 'remote-demo',
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
                    supportedCommands: <CockpitCommandType>[
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
                  snapshot: CockpitSnapshot(
                    routeName: '/home',
                    runtime: CockpitRuntimeSnapshot(
                      totalEntryCount: 1,
                      errorCount: 1,
                      warningCount: 0,
                      entries: <CockpitRuntimeEvent>[
                        CockpitRuntimeEvent(
                          eventId: 'runtime-1',
                          kind: CockpitRuntimeEventKind.flutterError,
                          severity: CockpitRuntimeEventSeverity.error,
                          message: 'RenderFlex overflowed',
                          recordedAt: DateTime.utc(2026, 3, 22, 1, 0),
                        ),
                      ],
                    ),
                  ),
                ).toJson(),
              ),
            );
          case ('GET', '/snapshot'):
            snapshotRequestUri = request.uri;
            request.response.write(
              jsonEncode(
                CockpitSnapshot(
                  routeName: '/home',
                  diagnosticLevel: CockpitSnapshotProfile.investigate,
                  runtime: CockpitRuntimeSnapshot(
                    totalEntryCount: 1,
                    errorCount: 1,
                    warningCount: 0,
                    entries: <CockpitRuntimeEvent>[
                      CockpitRuntimeEvent(
                        eventId: 'runtime-1',
                        kind: CockpitRuntimeEventKind.flutterError,
                        severity: CockpitRuntimeEventSeverity.error,
                        message: 'RenderFlex overflowed',
                        recordedAt: DateTime.utc(2026, 3, 22, 1, 0),
                      ),
                    ],
                  ),
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'home.open_form_button',
                      cockpitId: 'open_form_button',
                      text: 'Open form',
                      typeName: 'ElevatedButton',
                      routeName: '/home',
                      supportedCommands: <CockpitCommandType>[
                        CockpitCommandType.tap,
                      ],
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('POST', '/commands/execute'):
            request.response.write(
              jsonEncode(
                CockpitRemoteCommandResponse(
                  result: CockpitCommandResult(
                    success: true,
                    commandId: 'tap-open',
                    commandType: CockpitCommandType.tap,
                    durationMs: 42,
                    locatorResolution: const CockpitLocatorResolution(
                      matchedKind: CockpitLocatorKind.cockpitId,
                      matchedValue: 'open_form_button',
                    ),
                    snapshot: CockpitSnapshot(routeName: '/form').toJson(),
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/form_after_action.png',
                      ),
                      downloadPath:
                          '/artifacts/download?path=screenshots%2Fform_after_action.png',
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('POST', '/recording/start'):
            request.response.write(
              jsonEncode(
                const CockpitRecordingSession(
                  request: CockpitRecordingRequest(
                    purpose: CockpitRecordingPurpose.acceptance,
                    name: 'demo_acceptance',
                    attachToStep: true,
                  ),
                  state: CockpitRecordingState.recording,
                ).toJson(),
              ),
            );
          case ('POST', '/recording/stop'):
            request.response.write(
              jsonEncode(
                CockpitRemoteRecordingResponse(
                  result: CockpitRecordingResult(
                    state: CockpitRecordingState.completed,
                    purpose: CockpitRecordingPurpose.acceptance,
                    recordingKind: CockpitRecordingKind.nativeScreen,
                    artifact: const CockpitArtifactRef(
                      role: 'recording',
                      relativePath: 'recordings/demo_acceptance.mp4',
                    ),
                    durationMs: 2600,
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'recording',
                        relativePath: 'recordings/demo_acceptance.mp4',
                      ),
                      downloadPath:
                          '/artifacts/download?path=recordings%2Fdemo_acceptance.mp4',
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('GET', '/artifacts/download'):
            request.response.headers.contentType = ContentType.binary;
            request.response.add(const <int>[8, 6, 7, 5, 3, 0, 9]);
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final downloadDir = await Directory.systemTemp.createTemp(
        'flutter_cockpit_remote_client_test_',
      );
      addTearDown(() async {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        artifactTempFileFactory: (basename) async =>
            File('${downloadDir.path}${Platform.pathSeparator}$basename'),
      );

      final status = await client.readStatus();
      final snapshot = await client.readSnapshot(
        options: const CockpitSnapshotOptions.investigate(),
      );
      final execution = await client.executeDetailed(
        CockpitCommand(
          commandId: 'tap-open',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(cockpitId: 'open_form_button'),
        ),
      );
      final recordingSession = await client.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'demo_acceptance',
          attachToStep: true,
        ),
      );
      final recordingResult = await client.stopRecording();

      expect(status.currentRouteName, '/home');
      expect(status.snapshot.diagnosticLevel, CockpitSnapshotProfile.live);
      expect(status.snapshot.runtime?.errorCount, 1);
      expect(
        snapshotRequestUri?.queryParameters['profile'],
        CockpitSnapshotProfile.investigate.jsonValue,
      );
      expect(
        snapshotRequestUri?.queryParameters['includeNetworkActivity'],
        'true',
      );
      expect(snapshotRequestUri?.queryParameters['maxNetworkEntries'], '8');
      expect(
        snapshotRequestUri?.queryParameters['networkOnlyFailures'],
        'true',
      );
      expect(
        snapshotRequestUri?.queryParameters['includeRuntimeActivity'],
        'true',
      );
      expect(snapshotRequestUri?.queryParameters['runtimeOnlyErrors'], 'true');
      expect(
        snapshotRequestUri?.queryParameters['includeRebuildActivity'],
        'true',
      );
      expect(snapshotRequestUri?.queryParameters['maxRebuildEntries'], '8');
      expect(
        snapshotRequestUri?.queryParameters['includeAccessibilitySummary'],
        'true',
      );
      expect(
        snapshotRequestUri?.queryParameters['maxAccessibilityEntries'],
        '8',
      );
      expect(snapshot.visibleTargets.single.cockpitId, 'open_form_button');
      expect(snapshot.diagnosticLevel, CockpitSnapshotProfile.investigate);
      expect(snapshot.runtime?.errorCount, 1);
      expect(execution.result.success, isTrue);
      expect(execution.artifactPayloads, isEmpty);
      expect(
        execution.artifactSourcePaths.keys,
        contains('screenshots/form_after_action.png'),
      );
      expect(
        await File(
          execution.artifactSourcePaths['screenshots/form_after_action.png']!,
        ).readAsBytes(),
        <int>[8, 6, 7, 5, 3, 0, 9],
      );
      expect(recordingSession.state, CockpitRecordingState.recording);
      expect(
        recordingResult.artifact?.relativePath,
        'recordings/demo_acceptance.mp4',
      );
      expect(recordingResult.bytes, isNull);
      expect(recordingResult.sourceFilePath, isNotNull);
      expect(await File(recordingResult.sourceFilePath!).readAsBytes(), <int>[
        8,
        6,
        7,
        5,
        3,
        0,
        9,
      ]);
    },
  );

  test('remote session client pings the lightweight endpoint', () async {
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((request) async {
      requestedPaths.add(request.uri.toString());
      request.response.headers.contentType = ContentType.json;
      switch ((request.method, request.uri.path)) {
        case ('GET', '/cockpit/ping'):
          request.response.write(
            jsonEncode(const <String, Object?>{
              'ok': true,
              'transportType': 'remoteHttp',
              'routePrefix': '/cockpit',
            }),
          );
        case ('GET', '/cockpit/health'):
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(
            jsonEncode(const <String, Object?>{
              'error': 'heavyHealthShouldNotBeUsed',
            }),
          );
        default:
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(
            jsonEncode(const <String, Object?>{'error': 'notFound'}),
          );
      }
      await request.response.close();
    });

    final client = CockpitRemoteSessionClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/cockpit'),
    );

    expect(await client.ping(), isTrue);
    expect(requestedPaths, <String>['/cockpit/ping']);
  });

  test(
    'remote session client preserves downloaded command artifact refs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        switch ((request.method, request.uri.path)) {
          case ('POST', '/commands/execute'):
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                CockpitRemoteCommandResponse(
                  result: CockpitCommandResult(
                    success: true,
                    commandId: 'capture-screenshot',
                    commandType: CockpitCommandType.captureScreenshot,
                    durationMs: 24,
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/acceptance.png',
                      ),
                      downloadPath:
                          '/artifacts/download?path=screenshots%2Facceptance.png',
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('GET', '/artifacts/download'):
            request.response.headers.contentType = ContentType.binary;
            request.response.add(const <int>[137, 80, 78, 71]);
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final downloadDir = await Directory.systemTemp.createTemp(
        'flutter_cockpit_remote_client_artifact_refs_test_',
      );
      addTearDown(() async {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        artifactTempFileFactory: (basename) async =>
            File('${downloadDir.path}${Platform.pathSeparator}$basename'),
      );

      final execution = await client.executeDetailed(
        CockpitCommand(
          commandId: 'capture-screenshot',
          commandType: CockpitCommandType.captureScreenshot,
          screenshotRequest: const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: 'acceptance',
          ),
        ),
      );

      expect(execution.result.artifacts, <CockpitArtifactRef>[
        const CockpitArtifactRef(
          role: 'screenshot',
          relativePath: 'screenshots/acceptance.png',
        ),
      ]);
      expect(
        execution.artifactSourcePaths.keys,
        contains('screenshots/acceptance.png'),
      );
    },
  );

  test('remote session client checks lightweight control readiness', () async {
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((request) async {
      requestedPaths.add(request.uri.toString());
      request.response.headers.contentType = ContentType.json;
      switch ((request.method, request.uri.path)) {
        case ('GET', '/cockpit/ready'):
          request.response.write(
            jsonEncode(const <String, Object?>{
              'ok': true,
              'ready': true,
              'supportsInAppControl': true,
              'currentRouteName': '/inbox',
            }),
          );
        case ('GET', '/cockpit/health'):
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(
            jsonEncode(const <String, Object?>{
              'error': 'heavyHealthShouldNotBeUsed',
            }),
          );
        default:
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(
            jsonEncode(const <String, Object?>{'error': 'notFound'}),
          );
      }
      await request.response.close();
    });

    final client = CockpitRemoteSessionClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}/cockpit'),
    );

    expect(await client.ready(), isTrue);
    expect(requestedPaths, <String>['/cockpit/ready']);
  });

  test(
    'remote session client keeps externalized forensic snapshots summarized by default',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      var artifactDownloadCount = 0;

      server.listen((request) async {
        switch ((request.method, request.uri.path)) {
          case ('GET', '/snapshot'):
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, Object?>{
                'snapshot': CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  diagnosticsArtifactRef: const CockpitArtifactRef(
                    role: 'diagnostics',
                    relativePath: 'diagnostics/remote_snapshot_debug.json',
                  ),
                  summary: const CockpitSnapshotSummary(
                    visibleTargetCount: 1,
                    targetsWithCockpitIdCount: 0,
                    targetsWithTextCount: 1,
                    styleDetailsIncluded: true,
                    diagnosticPropertiesIncluded: true,
                    ancestorSummariesIncluded: true,
                    rebuildSummaryIncluded: false,
                    accessibilitySummaryIncluded: false,
                  ),
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      keyValue: 'settings-sync-check-button',
                      text: 'Run check',
                      typeName: 'FilledButton',
                      routeName: '/debug',
                      supportedCommands: <CockpitCommandType>[
                        CockpitCommandType.tap,
                      ],
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
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      keyValue: 'settings-sync-check-button',
                      text: 'Run check',
                      typeName: 'FilledButton',
                      routeName: '/debug',
                      supportedCommands: <CockpitCommandType>[
                        CockpitCommandType.tap,
                      ],
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
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final snapshot = await client.readSnapshot(
        options: const CockpitSnapshotOptions.forensic(),
      );

      expect(snapshot.routeName, '/debug');
      expect(
        snapshot.diagnosticsArtifactRef?.relativePath,
        'diagnostics/remote_snapshot_debug.json',
      );
      expect(snapshot.visibleTargets.single.diagnosticProperties, isEmpty);
      expect(artifactDownloadCount, 0);
    },
  );

  test(
    'remote session client can explicitly download externalized forensic snapshot artifacts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

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
                      keyValue: 'settings-sync-check-button',
                      text: 'Run check',
                      typeName: 'FilledButton',
                      routeName: '/debug',
                      supportedCommands: <CockpitCommandType>[
                        CockpitCommandType.tap,
                      ],
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
            request.response.write(
              jsonEncode(
                CockpitSnapshot(
                  routeName: '/debug',
                  diagnosticLevel: CockpitSnapshotProfile.forensic,
                  visibleTargets: <CockpitSnapshotTarget>[
                    CockpitSnapshotTarget(
                      registrationId: 'debug.sync_check',
                      keyValue: 'settings-sync-check-button',
                      text: 'Run check',
                      typeName: 'FilledButton',
                      routeName: '/debug',
                      supportedCommands: <CockpitCommandType>[
                        CockpitCommandType.tap,
                      ],
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

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      final snapshot = await client.readSnapshot(
        options: const CockpitSnapshotOptions.forensic(),
        downloadDiagnosticsArtifacts: true,
      );

      expect(snapshot.routeName, '/debug');
      expect(
        snapshot.diagnosticsArtifactRef?.relativePath,
        'diagnostics/remote_snapshot_debug.json',
      );
      expect(
        snapshot.visibleTargets.single.diagnosticProperties.single.value.length,
        greaterThan(20000),
      );
    },
  );

  test(
    'remote session client can download externalized widget tree artifacts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('GET', '/snapshot'):
            request.response.write(
              jsonEncode(<String, Object?>{
                'snapshot': CockpitSnapshot(
                  routeName: '/tree',
                  treeArtifactRef: const CockpitArtifactRef(
                    role: 'widget-tree',
                    relativePath: 'trees/current.json',
                  ),
                  tree: CockpitWidgetTree(
                    profile: CockpitWidgetTreeProfile.full,
                    total: 1,
                    visible: 1,
                    truncated: false,
                    emitted: 1,
                  ),
                ).toJson(),
                'artifactDownloads': const <Map<String, Object?>>[
                  <String, Object?>{
                    'artifact': <String, Object?>{
                      'role': 'widget-tree',
                      'relativePath': 'trees/current.json',
                    },
                    'downloadPath':
                        '/artifacts/download?path=trees%2Fcurrent.json',
                  },
                ],
              }),
            );
          case ('GET', '/artifacts/download'):
            request.response.write(
              jsonEncode(
                CockpitWidgetTree(
                  profile: CockpitWidgetTreeProfile.full,
                  total: 1,
                  visible: 1,
                  truncated: false,
                  nodes: <CockpitWidgetNode>[
                    CockpitWidgetNode(
                      node: 0,
                      depth: 0,
                      type: 'TextButton',
                      text: 'Continue',
                      visible: true,
                      offstage: false,
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

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final snapshot = await client.readSnapshot(
        options: const CockpitSnapshotOptions(
          tree: CockpitWidgetTreeOptions.full(),
        ),
        downloadDiagnosticsArtifacts: true,
      );

      expect(snapshot.treeArtifactRef?.relativePath, 'trees/current.json');
      expect(snapshot.tree?.nodes.single.text, 'Continue');
    },
  );

  test(
    'remote session client preserves base route prefix for requests and downloads',
    () async {
      final requestedPaths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      final downloadDir = await Directory.systemTemp.createTemp(
        'flutter_cockpit_remote_prefix_client_test_',
      );
      addTearDown(() async {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      });

      server.listen((request) async {
        requestedPaths.add(
          request.uri.hasQuery
              ? '${request.uri.path}?${request.uri.query}'
              : request.uri.path,
        );
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('GET', '/cockpit/health'):
            request.response.write(
              jsonEncode(
                CockpitRemoteSessionStatus(
                  sessionId: 'prefixed-session',
                  platform: 'web',
                  transportType: 'remoteHttp',
                  currentRouteName: '/home',
                  capabilities: CockpitCapabilities(
                    platform: 'web',
                    transportType: 'remoteHttp',
                    supportsInAppControl: true,
                    supportsFlutterViewCapture: true,
                    supportsNativeScreenCapture: false,
                    supportsHostAutomation: false,
                  ),
                  recordingCapabilities: CockpitRecordingCapabilities(
                    supportsNativeRecording: true,
                  ),
                  snapshot: CockpitSnapshot(routeName: '/home'),
                ).toJson(),
              ),
            );
          case ('POST', '/cockpit/recording/stop'):
            request.response.write(
              jsonEncode(
                CockpitRemoteRecordingResponse(
                  result: CockpitRecordingResult(
                    state: CockpitRecordingState.completed,
                    artifact: const CockpitArtifactRef(
                      role: 'recording',
                      relativePath: 'recordings/prefixed.mp4',
                    ),
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'recording',
                        relativePath: 'recordings/prefixed.mp4',
                      ),
                      downloadPath:
                          '/cockpit/artifacts/download?path=recordings%2Fprefixed.mp4',
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('GET', '/cockpit/artifacts/download'):
            request.response.headers.contentType = ContentType.binary;
            request.response.add(const <int>[9, 4, 2]);
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/cockpit'),
        artifactTempFileFactory: (basename) async =>
            File('${downloadDir.path}${Platform.pathSeparator}$basename'),
      );

      final status = await client.readStatus();
      final recording = await client.stopRecording();

      expect(status.sessionId, 'prefixed-session');
      expect(recording.sourceFilePath, isNotNull);
      expect(await File(recording.sourceFilePath!).readAsBytes(), <int>[
        9,
        4,
        2,
      ]);
      expect(
        requestedPaths,
        containsAllInOrder(<String>[
          '/cockpit/health',
          '/cockpit/recording/stop',
          '/cockpit/artifacts/download?path=recordings%2Fprefixed.mp4',
        ]),
      );
    },
  );

  test(
    'remote session client wraps transport interruptions as remoteUnavailable',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      await server.close(force: true);

      final client = CockpitRemoteSessionClient(baseUri: baseUri);

      expect(
        client.readStatus,
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'remoteUnavailable')
              .having(
                (error) => error.message,
                'message',
                contains('temporarily unavailable'),
              ),
        ),
      );
    },
  );

  test(
    'waitForUiIdle uses the supplied idle timeout as the transport bound',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) {
        // Keep the request open. waitForUiIdle must not wait for the default
        // client request timeout before allowing host-side fallbacks.
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        requestTimeout: const Duration(seconds: 30),
      );
      final stopwatch = Stopwatch()..start();

      final idle = await client.waitForUiIdle(
        timeout: const Duration(milliseconds: 40),
      );
      stopwatch.stop();

      expect(idle, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test(
    'command execution derives its transport timeout from the command budget',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              CockpitRemoteCommandResponse(
                result: CockpitCommandResult(
                  success: true,
                  commandId: 'long-command',
                  commandType: CockpitCommandType.scrollUntilVisible,
                  durationMs: 60,
                ),
              ).toJson(),
            ),
          );
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        requestTimeout: const Duration(milliseconds: 20),
      );
      final execution = await client.executeDetailed(
        CockpitCommand(
          commandId: 'long-command',
          commandType: CockpitCommandType.scrollUntilVisible,
          timeoutMs: 200,
        ),
      );

      expect(execution.result.success, isTrue);
    },
  );

  test(
    'remote session client preserves structured HTTP error payloads',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(const <String, Object?>{
              'error': 'bridgeUnavailable',
              'message': 'The browser bridge is not connected.',
              'details': <String, Object?>{'connectPath': '/cockpit/connect'},
            }),
          );
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/cockpit'),
      );

      await expectLater(
        client.readStatus,
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'remoteUnavailable')
              .having(
                (error) => error.details['remoteCode'],
                'remoteCode',
                'bridgeUnavailable',
              )
              .having(
                (error) => error.details['remoteMessage'],
                'remoteMessage',
                'The browser bridge is not connected.',
              )
              .having(
                (error) => error.details['statusCode'],
                'statusCode',
                HttpStatus.serviceUnavailable,
              )
              .having(
                (error) =>
                    (error.details['remoteDetails']
                        as Map<Object?, Object?>)['connectPath'],
                'remoteDetails.connectPath',
                '/cockpit/connect',
              ),
        ),
      );
    },
  );

  test(
    'remote session client treats bridge timeouts as retryable unavailability',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.gatewayTimeout
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(const <String, Object?>{
              'error': 'bridgeTimeout',
              'message': 'The browser bridge did not respond before timeout.',
            }),
          );
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/cockpit'),
      );

      await expectLater(
        client.readStatus,
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'remoteUnavailable')
              .having(
                (error) => error.details['remoteCode'],
                'remoteCode',
                'bridgeTimeout',
              )
              .having(
                (error) => error.details['statusCode'],
                'statusCode',
                HttpStatus.gatewayTimeout,
              ),
        ),
      );
    },
  );

  test(
    'remote session client preserves structured artifact download failures',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('POST', '/recording/stop'):
            request.response.write(
              jsonEncode(
                CockpitRemoteRecordingResponse(
                  result: CockpitRecordingResult(
                    state: CockpitRecordingState.completed,
                    artifact: const CockpitArtifactRef(
                      role: 'recording',
                      relativePath: 'recordings/missing.mp4',
                    ),
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'recording',
                        relativePath: 'recordings/missing.mp4',
                      ),
                      downloadPath:
                          '/artifacts/download?path=recordings%2Fmissing.mp4',
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('GET', '/artifacts/download'):
            request.response
              ..statusCode = HttpStatus.notFound
              ..write(
                jsonEncode(const <String, Object?>{
                  'error': 'artifactNotFound',
                  'message': 'Artifact file is no longer available.',
                }),
              );
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await expectLater(
        client.stopRecording,
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'artifactNotFound')
              .having(
                (error) => error.message,
                'message',
                'Artifact file is no longer available.',
              )
              .having(
                (error) => error.details['path'],
                'path',
                '/artifacts/download?path=recordings%2Fmissing.mp4',
              ),
        ),
      );
    },
  );

  test(
    'remote session client rejects empty downloaded command artifacts',
    () async {
      final downloadDir = await Directory.systemTemp.createTemp(
        'flutter_cockpit_empty_command_artifact_',
      );
      addTearDown(() async {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('POST', '/commands/execute'):
            request.response.write(
              jsonEncode(
                CockpitRemoteCommandResponse(
                  result: CockpitCommandResult(
                    success: true,
                    commandId: 'tap-empty-screenshot',
                    commandType: CockpitCommandType.tap,
                    durationMs: 12,
                    artifacts: const <CockpitArtifactRef>[
                      CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/empty.png',
                      ),
                    ],
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/empty.png',
                      ),
                      downloadPath:
                          '/artifacts/download?path=screenshots%2Fempty.png',
                    ),
                  ],
                ).toJson(),
              ),
            );
          case ('GET', '/artifacts/download'):
            request.response.headers.contentType = ContentType.binary;
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
        }
        await request.response.close();
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        artifactTempFileFactory: (basename) async =>
            File('${downloadDir.path}${Platform.pathSeparator}$basename'),
      );

      await expectLater(
        () => client.executeDetailed(
          CockpitCommand(
            commandId: 'tap-empty-screenshot',
            commandType: CockpitCommandType.tap,
          ),
        ),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'artifactDownloadEmpty')
              .having(
                (error) => error.details['artifactPath'],
                'artifactPath',
                'screenshots/empty.png',
              ),
        ),
      );
      expect(downloadDir.listSync(), isEmpty);
    },
  );

  test(
    'remote session client retries transient command artifact download timeouts',
    () async {
      final downloadDir = await Directory.systemTemp.createTemp(
        'flutter_cockpit_retry_command_artifact_',
      );
      addTearDown(() async {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      var downloadAttempts = 0;

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('POST', '/commands/execute'):
            request.response.write(
              jsonEncode(
                CockpitRemoteCommandResponse(
                  result: CockpitCommandResult(
                    success: true,
                    commandId: 'tap-retry-screenshot',
                    commandType: CockpitCommandType.tap,
                    durationMs: 12,
                    artifacts: const <CockpitArtifactRef>[
                      CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/retry.png',
                      ),
                    ],
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/retry.png',
                      ),
                      downloadPath:
                          '/artifacts/download?path=screenshots%2Fretry.png',
                    ),
                  ],
                ).toJson(),
              ),
            );
            await request.response.close();
          case ('GET', '/artifacts/download'):
            downloadAttempts += 1;
            request.response.headers.contentType = ContentType.binary;
            if (downloadAttempts == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 120));
            } else {
              request.response.add(const <int>[1, 2, 3]);
            }
            await request.response.close();
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode(const <String, Object?>{'error': 'notFound'}),
            );
            await request.response.close();
        }
      });

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        artifactDownloadTimeout: const Duration(milliseconds: 40),
        artifactTempFileFactory: (basename) async =>
            File('${downloadDir.path}${Platform.pathSeparator}$basename'),
      );

      final execution = await client.executeDetailed(
        CockpitCommand(
          commandId: 'tap-retry-screenshot',
          commandType: CockpitCommandType.tap,
        ),
      );

      expect(downloadAttempts, 2);
      expect(execution.artifactSourcePaths['screenshots/retry.png'], isNotNull);
      expect(
        await File(
          execution.artifactSourcePaths['screenshots/retry.png']!,
        ).readAsBytes(),
        <int>[1, 2, 3],
      );
    },
  );

  test(
    'remote session client rejects cross-origin artifact download paths',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        switch ((request.method, request.uri.path)) {
          case ('POST', '/recording/stop'):
            request.response.write(
              jsonEncode(
                CockpitRemoteRecordingResponse(
                  result: CockpitRecordingResult(
                    state: CockpitRecordingState.completed,
                    artifact: const CockpitArtifactRef(
                      role: 'recording',
                      relativePath: 'recordings/cross_origin.mp4',
                    ),
                  ),
                  artifactDownloads: const <CockpitRemoteArtifactDownload>[
                    CockpitRemoteArtifactDownload(
                      artifact: CockpitArtifactRef(
                        role: 'recording',
                        relativePath: 'recordings/cross_origin.mp4',
                      ),
                      downloadPath:
                          'http://127.0.0.1:1/artifacts/download?path=recordings%2Fcross_origin.mp4',
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

      final client = CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await expectLater(
        client.stopRecording,
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'invalidArtifactUrl')
              .having(
                (error) => error.message,
                'message',
                contains('same remote session origin'),
              ),
        ),
      );
    },
  );
}
