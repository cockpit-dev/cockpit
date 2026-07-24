import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_app_reference_resolver.dart';
import 'package:cockpit/src/application/cockpit_list_apps_service.dart';
import 'package:cockpit/src/application/cockpit_list_launch_targets_service.dart';
import 'package:cockpit/src/application/cockpit_read_logs_service.dart';
import 'package:cockpit/src/application/cockpit_read_network_service.dart';
import 'package:cockpit/src/application/cockpit_read_runtime_errors_service.dart';
import 'package:cockpit/src/application/cockpit_read_session_logs_service.dart';
import 'package:cockpit/src/application/cockpit_session_registry.dart';
import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:cockpit/src/infrastructure/cockpit_file_system.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/infrastructure/cockpit_sdk_environment.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

void main() {
  test('lists Flutter launch targets from machine output', () async {
    final service = CockpitListLaunchTargetsService(
      processManager: _MachineProcessManager(
        stdoutPayload: jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'macos',
            'name': 'macOS',
            'targetPlatform': 'darwin',
            'isSupported': true,
            'emulator': false,
            'sdk': 'macos',
          },
          <String, Object?>{
            'id': 'emulator-5554',
            'name': 'Pixel 8',
            'targetPlatform': 'android-arm64',
            'isSupported': true,
            'emulator': true,
            'sdk': 'android',
          },
          <String, Object?>{
            'id': 'chrome',
            'name': 'Chrome',
            'targetPlatform': 'web-javascript',
            'isSupported': true,
            'emulator': false,
            'sdk': 'web',
          },
        ]),
      ),
      sdkEnvironment: const CockpitSdkEnvironment(
        dartExecutable: 'dart-sdk',
        flutterExecutable: 'flutter-sdk',
      ),
    );

    final result = await service.list();

    expect(result.targets, hasLength(3));
    expect(result.targets[0].id, 'macos');
    expect(result.targets[0].platformType, 'darwin');
    expect(result.targets[0].platform, 'macos');
    expect(result.targets[1].platformType, 'android-arm64');
    expect(result.targets[1].platform, 'android');
    expect(result.targets[2].platformType, 'web-javascript');
    expect(result.targets[2].platform, 'web');
    expect(result.targets[0].toJson()['platform'], 'macos');
  });

  test(
    'lists Flutter launch targets when process stdout is UTF-8 bytes',
    () async {
      final service = CockpitListLaunchTargetsService(
        processManager: _MachineProcessManager(
          stdoutPayload: jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'id': 'macos',
              'name': 'macOS',
              'targetPlatform': 'darwin',
              'isSupported': true,
              'emulator': false,
              'sdk': 'macos',
            },
          ]),
          returnUtf8Bytes: true,
        ),
        sdkEnvironment: const CockpitSdkEnvironment(
          dartExecutable: 'dart-sdk',
          flutterExecutable: 'flutter-sdk',
        ),
      );

      final result = await service.list();

      expect(result.targets, hasLength(1));
      expect(result.targets.single.id, 'macos');
    },
  );

  test(
    'lists launch targets when stdout stays open after flutter devices exits',
    () async {
      final processManager = _MachineProcessManager(
        stdoutPayload: jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'chrome',
            'name': 'Chrome',
            'targetPlatform': 'web-javascript',
            'isSupported': true,
            'emulator': false,
            'sdk': 'web',
          },
        ]),
        keepOutputOpenAfterExit: true,
      );
      addTearDown(processManager.dispose);
      final service = CockpitListLaunchTargetsService(
        processManager: processManager,
        sdkEnvironment: const CockpitSdkEnvironment(
          dartExecutable: 'dart-sdk',
          flutterExecutable: 'flutter-sdk',
        ),
      );

      final result = await service
          .list(timeout: const Duration(seconds: 2))
          .timeout(const Duration(milliseconds: 500));

      expect(result.targets, hasLength(1));
      expect(result.targets.single.id, 'chrome');
    },
  );

  test('list launch targets times out instead of hanging forever', () async {
    final service = CockpitListLaunchTargetsService(
      processManager: _MachineProcessManager(
        stdoutPayload: '[]',
        hangOnStart: true,
      ),
      sdkEnvironment: const CockpitSdkEnvironment(
        dartExecutable: 'dart-sdk',
        flutterExecutable: 'flutter-sdk',
      ),
    );

    await expectLater(
      service.list(timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.code,
          'code',
          'listLaunchTargetsTimedOut',
        ),
      ),
    );
  });

  test('reads the tail of registered development session logs', () async {
    final fileSystem = MemoryFileSystem();
    fileSystem.file('/tmp/dev.log')
      ..createSync(recursive: true)
      ..writeAsStringSync('one\ntwo\nthree\n');
    final registry = CockpitSessionRegistry();
    registry.recordDevelopmentSession(
      handle: _developmentHandle(),
      status: _developmentStatus(lastError: 'boom'),
      supervisorLogPath: '/tmp/dev.log',
    );

    final result =
        await CockpitReadSessionLogsService(
          registry: registry,
          fileSystem: LocalCockpitFileSystem(fileSystem: fileSystem),
        ).read(
          const CockpitReadSessionLogsRequest(
            developmentSessionId: 'dev-session-1',
            maxLines: 2,
          ),
        );

    expect(result.logPath, '/tmp/dev.log');
    expect(result.lines, <String>['two', 'three']);
    expect(result.truncated, isTrue);
  });

  test('lists active apps with normalized app ids and modes', () {
    final registry = CockpitSessionRegistry();
    registry.recordDevelopmentSession(
      handle: _developmentHandle(),
      status: _developmentStatus(),
      supervisorLogPath: '/tmp/dev.log',
    );

    final result = CockpitListAppsService(registry: registry).list();

    expect(result.apps, hasLength(1));
    expect(result.apps.single.appId, 'dev.example.app');
    expect(result.apps.single.mode.jsonValue, 'development');
  });

  test('lists remote apps with the registry readiness state unchanged', () {
    final registry = CockpitSessionRegistry();
    registry.recordRemoteSession(
      handle: _remoteHandle(),
      status: _remoteStatus(),
      recommendedNextStep: 'ready_for_commands',
    );

    final result = CockpitListAppsService(registry: registry).list();

    expect(result.apps, hasLength(1));
    expect(result.apps.single.appId, 'dev.example.remote');
    expect(result.apps.single.mode.jsonValue, 'automation');
    expect(result.apps.single.state, 'ready_for_commands');
  });

  test('reads app snapshot logs by app id', () async {
    final registry = CockpitSessionRegistry();
    registry.recordDevelopmentSession(
      handle: _developmentHandle(),
      status: _developmentStatus(lastError: 'boom'),
      supervisorLogPath: '/tmp/dev.log',
    );

    final result = await CockpitReadLogsService(
      registry: registry,
      readSnapshot: (baseUri, options) async {
        expect(baseUri.toString(), 'http://127.0.0.1:57331');
        expect(options.includeRuntimeActivity, isTrue);
        expect(options.maxRuntimeEntries, 2);
        return CockpitRemoteSnapshotResponse(
          snapshot: CockpitSnapshot(
            routeName: '/inbox',
            runtime: CockpitRuntimeSnapshot(
              totalEntryCount: 2,
              errorCount: 0,
              warningCount: 0,
              entries: <CockpitRuntimeEvent>[
                CockpitRuntimeEvent(
                  eventId: 'runtime-1',
                  kind: CockpitRuntimeEventKind.debugLog,
                  severity: CockpitRuntimeEventSeverity.info,
                  message: 'rendered inbox',
                  recordedAt: DateTime.utc(2026, 3, 30, 10, 0),
                  routeName: '/inbox',
                  source: 'debugPrint',
                ),
                CockpitRuntimeEvent(
                  eventId: 'runtime-2',
                  kind: CockpitRuntimeEventKind.debugLog,
                  severity: CockpitRuntimeEventSeverity.info,
                  message: 'refreshed counters',
                  recordedAt: DateTime.utc(2026, 3, 30, 10, 1),
                  routeName: '/inbox',
                  source: 'print',
                ),
              ],
              capturedEntryCount: 2,
            ),
          ),
        );
      },
    ).read(const CockpitReadLogsRequest(appId: 'dev.example.app', maxLines: 2));

    expect(result.appId, 'dev.example.app');
    expect(result.source, 'app_snapshot');
    expect(result.available, isTrue);
    expect(result.routeName, '/inbox');
    expect(result.lines, <String>[
      'info debugLog debugPrint: rendered inbox',
      'info debugLog print: refreshed counters',
    ]);
  });

  test('reads app snapshot logs directly from a base URL', () async {
    Uri? capturedBaseUri;
    final result =
        await CockpitReadLogsService(
          registry: CockpitSessionRegistry(),
          readSnapshot: (baseUri, options) async {
            capturedBaseUri = baseUri;
            expect(options.includeRuntimeActivity, isTrue);
            expect(options.maxRuntimeEntries, 1);
            return CockpitRemoteSnapshotResponse(
              snapshot: CockpitSnapshot(
                routeName: '/direct',
                runtime: CockpitRuntimeSnapshot(
                  totalEntryCount: 1,
                  errorCount: 0,
                  warningCount: 0,
                  entries: <CockpitRuntimeEvent>[
                    CockpitRuntimeEvent(
                      eventId: 'runtime-1',
                      kind: CockpitRuntimeEventKind.debugLog,
                      severity: CockpitRuntimeEventSeverity.info,
                      message: 'direct log',
                      recordedAt: DateTime.utc(2026, 3, 30, 10, 0),
                      routeName: '/direct',
                    ),
                  ],
                  capturedEntryCount: 1,
                ),
              ),
            );
          },
        ).read(
          CockpitReadLogsRequest(
            baseUri: Uri.parse('http://127.0.0.1:61331/cockpit'),
            maxLines: 1,
          ),
        );

    expect(capturedBaseUri.toString(), 'http://127.0.0.1:61331/cockpit');
    expect(result.appId, 'unknown');
    expect(result.source, 'app_snapshot');
    expect(result.routeName, '/direct');
    expect(result.lines, <String>['info debugLog: direct log']);
  });

  test(
    'returns structured missing log state when the log file is absent',
    () async {
      final registry = CockpitSessionRegistry();
      registry.recordDevelopmentSession(
        handle: _developmentHandle(),
        status: _developmentStatus(),
        supervisorLogPath: '/tmp/missing.log',
      );

      final result =
          await CockpitReadLogsService(
            registry: registry,
            fileSystem: LocalCockpitFileSystem(fileSystem: MemoryFileSystem()),
            readSnapshot: (_, _) => throw StateError('app unavailable'),
          ).read(
            const CockpitReadLogsRequest(appId: 'dev.example.app', maxLines: 2),
          );

      expect(result.available, isFalse);
      expect(result.missingReason, 'log_file_missing');
      expect(result.lines, isEmpty);
    },
  );

  test(
    'resolves a lean app handle back to the registry session record',
    () async {
      final registry = CockpitSessionRegistry();
      registry.recordDevelopmentSession(
        handle: _developmentHandle(),
        status: _developmentStatus(lastError: 'boom'),
        supervisorLogPath: '/tmp/dev.log',
      );

      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_app_handle_resolver',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appFile = File('${tempDir.path}/app.json');
      await appFile.writeAsString(
        jsonEncode(
          CockpitAppHandle(
            appId: 'dev.example.app',
            mode: CockpitAppMode.development,
            platform: 'android',
            deviceId: 'emulator-5554',
            projectDir: '/workspace/app',
            target: 'lib/main.dart',
            baseUrl: 'http://127.0.0.1:57331',
            launchedAt: DateTime.utc(2026, 3, 30),
            supervisorLogPath: '/tmp/dev.log',
          ).toJson(),
        ),
      );

      final resolved = await CockpitAppReferenceResolver(
        registry: registry,
      ).resolve(appHandlePath: appFile.path);

      expect(resolved.app?.developmentSession, isNull);
      expect(
        resolved.developmentRecord?.handle.developmentSessionId,
        'dev-session-1',
      );
    },
  );

  test(
    'reconstructs development control fields from a compact app handle',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_compact_development_handle',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appFile = File('${tempDir.path}/app.json');
      await appFile.writeAsString(
        jsonEncode(
          CockpitAppHandle.fromDevelopmentSession(
            _developmentHandle(),
            supervisorLogPath: '/tmp/dev.log',
          ).toJson(),
        ),
      );

      final resolved = await CockpitAppReferenceResolver().resolve(
        appHandlePath: appFile.path,
      );

      expect(
        resolved.app?.developmentSession?.developmentSessionId,
        'dev-session-1',
      );
      expect(
        resolved.app?.developmentSession?.supervisorBaseUri.toString(),
        'http://127.0.0.1:59331',
      );
    },
  );

  test(
    'accepts a launch-app result wrapper anywhere an app handle is expected',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_wrapped_app_handle',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appFile = File('${tempDir.path}/app.json');
      await appFile.writeAsString(
        jsonEncode(<String, Object?>{
          'app': CockpitAppHandle.fromDevelopmentSession(
            _developmentHandle(),
            supervisorLogPath: '/tmp/dev.log',
          ).toJson(),
          'appJson_path': null,
          'supervisor_log_path': '/tmp/dev.log',
        }),
      );

      final resolved = await CockpitAppReferenceResolver().resolve(
        appHandlePath: appFile.path,
      );

      expect(resolved.app?.appId, 'dev.example.app');
      expect(
        resolved.app?.developmentSession?.developmentSessionId,
        'dev-session-1',
      );
    },
  );

  test(
    'preserves remote session details when reading an automation app handle',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_remote_app_handle',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appFile = File('${tempDir.path}/app.json');
      await appFile.writeAsString(
        jsonEncode(
          CockpitAppHandle.fromRemoteSession(_remoteHandle()).toJson(),
        ),
      );

      final resolved = await CockpitAppReferenceResolver().resolve(
        appHandlePath: appFile.path,
      );

      expect(resolved.app?.remoteSession?.appId, 'dev.example.remote');
      expect(resolved.app?.remoteSession?.hostPort, 57331);
      expect(resolved.app?.platformAppId, 'dev.example.remote');
    },
  );

  test('reads current app runtime errors from an app handle', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_runtime_errors_app_handle',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final appFile = File('${tempDir.path}/app.json');
    await appFile.writeAsString(
      jsonEncode(
        CockpitAppHandle(
          appId: 'dev.example.app',
          mode: CockpitAppMode.development,
          platform: 'macos',
          deviceId: 'macos',
          projectDir: '/workspace/app',
          target: 'cockpit/main.dart',
          baseUrl: 'http://127.0.0.1:57331',
          launchedAt: DateTime.utc(2026, 3, 30),
        ).toJson(),
      ),
    );

    final result =
        await CockpitReadRuntimeErrorsService(
          registry: CockpitSessionRegistry(),
          readSnapshot: (baseUri, options) async {
            expect(baseUri.toString(), 'http://127.0.0.1:57331');
            expect(options.includeRuntimeActivity, isTrue);
            expect(options.runtimeQuery.onlyErrors, isTrue);
            expect(options.maxRuntimeEntries, 4);
            return CockpitRemoteSnapshotResponse(
              snapshot: CockpitSnapshot(
                routeName: '/inbox',
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
                      message: 'setState called after dispose',
                      recordedAt: DateTime.utc(2026, 3, 30, 10, 0),
                      routeName: '/inbox',
                    ),
                  ],
                  capturedEntryCount: 1,
                  query: const CockpitRuntimeQuery(onlyErrors: true),
                ),
              ),
            );
          },
        ).read(
          CockpitReadRuntimeErrorsRequest(
            appHandlePath: appFile.path,
            maxErrors: 4,
          ),
        );

    expect(result.appId, 'dev.example.app');
    expect(result.routeName, '/inbox');
    expect(result.source, 'app_snapshot');
    expect(result.hasErrors, isTrue);
    expect(result.errors.single.message, 'setState called after dispose');
    expect(result.errors.single.kind, 'flutterError');
  });

  test(
    'retries current app runtime errors while Flutter root is remounting',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_runtime_errors_remount',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appFile = File('${tempDir.path}/app.json');
      await appFile.writeAsString(
        jsonEncode(
          CockpitAppHandle(
            appId: 'dev.example.web',
            mode: CockpitAppMode.development,
            platform: 'web',
            deviceId: 'chrome',
            projectDir: '/workspace/app',
            target: 'cockpit/main.dart',
            baseUrl: 'http://127.0.0.1:57331',
            launchedAt: DateTime.utc(2026, 3, 30),
          ).toJson(),
        ),
      );
      var readCount = 0;

      final result =
          await CockpitReadRuntimeErrorsService(
            registry: CockpitSessionRegistry(),
            retryDelay: Duration.zero,
            readSnapshot: (baseUri, options) async {
              readCount += 1;
              if (readCount == 1) {
                throw const CockpitApplicationServiceException(
                  code: 'serverError',
                  message: 'Bad state: FlutterCockpitRoot is not mounted.',
                );
              }
              return CockpitRemoteSnapshotResponse(
                snapshot: CockpitSnapshot(
                  routeName: '/inbox',
                  diagnosticLevel: CockpitSnapshotProfile.investigate,
                ),
              );
            },
          ).read(
            CockpitReadRuntimeErrorsRequest(
              appHandlePath: appFile.path,
              maxErrors: 4,
            ),
          );

      expect(readCount, 2);
      expect(result.hasErrors, isFalse);
      expect(result.routeName, '/inbox');
    },
  );

  test(
    'reads app network summary with endpoint summaries and recent failures',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_read_network_app_handle',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appFile = File('${tempDir.path}/app.json');
      await appFile.writeAsString(
        jsonEncode(
          CockpitAppHandle(
            appId: 'dev.example.app',
            mode: CockpitAppMode.development,
            platform: 'macos',
            deviceId: 'macos',
            projectDir: '/workspace/app',
            target: 'cockpit/main.dart',
            baseUrl: 'http://127.0.0.1:57331',
            launchedAt: DateTime.utc(2026, 3, 30),
          ).toJson(),
        ),
      );

      final result =
          await CockpitReadNetworkService(
            registry: CockpitSessionRegistry(),
            readSnapshot: (baseUri, options) async {
              expect(baseUri.toString(), 'http://127.0.0.1:57331');
              expect(options.includeNetworkActivity, isTrue);
              expect(options.maxNetworkEntries, 6);
              expect(options.networkQuery.uriContains, '/api');
              expect(options.networkQuery.onlyFailures, isFalse);
              expect(options.networkQuery.statusCodeAtLeast, 400);
              return CockpitRemoteSnapshotResponse(
                snapshot: CockpitSnapshot(
                  routeName: '/inbox',
                  network: CockpitNetworkSnapshot(
                    totalEntryCount: 3,
                    failureCount: 1,
                    entries: <CockpitNetworkEntry>[
                      CockpitNetworkEntry(
                        requestId: 'net-2',
                        method: 'GET',
                        uri: 'https://api.example.dev/api/messages',
                        startedAt: DateTime.utc(2026, 3, 30, 10, 0, 1),
                        durationMs: 90,
                        statusCode: 503,
                        error: 'service unavailable',
                      ),
                      CockpitNetworkEntry(
                        requestId: 'net-3',
                        method: 'GET',
                        uri: 'https://api.example.dev/api/profile',
                        startedAt: DateTime.utc(2026, 3, 30, 10, 0, 2),
                        durationMs: 45,
                        statusCode: 200,
                      ),
                    ],
                    endpointSummaries: <CockpitNetworkEndpointSummary>[
                      const CockpitNetworkEndpointSummary(
                        method: 'GET',
                        uriPattern: '/api/messages',
                        requestCount: 2,
                        failureCount: 1,
                        averageDurationMs: 72,
                        lastStatusCode: 503,
                        latestUri: 'https://api.example.dev/api/messages',
                      ),
                      const CockpitNetworkEndpointSummary(
                        method: 'GET',
                        uriPattern: '/api/profile',
                        requestCount: 1,
                        failureCount: 0,
                        averageDurationMs: 45,
                        lastStatusCode: 200,
                        latestUri: 'https://api.example.dev/api/profile',
                      ),
                    ],
                    capturedEntryCount: 5,
                    inFlightCount: 1,
                    query: const CockpitNetworkQuery(
                      uriContains: '/api',
                      statusCodeAtLeast: 400,
                    ),
                    truncated: true,
                  ),
                ),
              );
            },
          ).read(
            CockpitReadNetworkRequest(
              appHandlePath: appFile.path,
              maxEntries: 6,
              maxEndpointSummaries: 1,
              uriContains: '/api',
              statusCodeAtLeast: 400,
            ),
          );

      expect(result.appId, 'dev.example.app');
      expect(result.routeName, '/inbox');
      expect(result.source, 'app_snapshot');
      expect(result.available, isTrue);
      expect(result.summary.totalEntryCount, 3);
      expect(result.summary.failureCount, 1);
      expect(result.summary.inFlightCount, 1);
      expect(result.endpointSummaries, hasLength(1));
      expect(result.endpointSummaries.single.uriPattern, '/api/messages');
      expect(result.endpointSummariesTruncated, isTrue);
      expect(result.recentFailures, hasLength(1));
      expect(result.recentFailures.single.error, 'service unavailable');
      expect(result.entries, isNull);
    },
  );

  test('read network can include matching entries on demand', () async {
    final result =
        await CockpitReadNetworkService(
          registry: CockpitSessionRegistry(),
          appReferenceResolver: CockpitAppReferenceResolver(),
          readSnapshot: (baseUri, options) async {
            expect(baseUri.toString(), 'http://127.0.0.1:57331');
            expect(options.includeNetworkActivity, isTrue);
            expect(options.maxNetworkEntries, 2);
            expect(options.networkQuery.method, 'POST');
            expect(options.networkQuery.onlyFailures, isTrue);
            return CockpitRemoteSnapshotResponse(
              snapshot: CockpitSnapshot(
                routeName: '/compose',
                network: CockpitNetworkSnapshot(
                  totalEntryCount: 1,
                  failureCount: 1,
                  entries: <CockpitNetworkEntry>[
                    CockpitNetworkEntry(
                      requestId: 'net-9',
                      method: 'POST',
                      uri: 'https://api.example.dev/api/send',
                      startedAt: DateTime.utc(2026, 3, 30, 10, 10),
                      durationMs: 120,
                      statusCode: 500,
                      error: 'internal error',
                    ),
                  ],
                  endpointSummaries: const <CockpitNetworkEndpointSummary>[
                    CockpitNetworkEndpointSummary(
                      method: 'POST',
                      uriPattern: '/api/send',
                      requestCount: 1,
                      failureCount: 1,
                      averageDurationMs: 120,
                      lastStatusCode: 500,
                      latestUri: 'https://api.example.dev/api/send',
                    ),
                  ],
                  capturedEntryCount: 1,
                  inFlightCount: 0,
                  query: const CockpitNetworkQuery(
                    method: 'POST',
                    onlyFailures: true,
                  ),
                ),
              ),
            );
          },
        ).read(
          CockpitReadNetworkRequest(
            baseUri: Uri.parse('http://127.0.0.1:57331'),
            maxEntries: 2,
            method: 'POST',
            onlyFailures: true,
            includeEntries: true,
          ),
        );

    expect(result.routeName, '/compose');
    expect(result.entries, hasLength(1));
    expect(result.entries?.single.requestId, 'net-9');
    expect(result.recentFailures, hasLength(1));
  });

  test(
    'read network refetches failures when summary says failures exist',
    () async {
      var readCount = 0;
      final result =
          await CockpitReadNetworkService(
            registry: CockpitSessionRegistry(),
            readSnapshot: (baseUri, options) async {
              readCount += 1;
              if (readCount == 1) {
                expect(options.networkQuery.onlyFailures, isFalse);
                return CockpitRemoteSnapshotResponse(
                  snapshot: CockpitSnapshot(
                    routeName: '/inbox',
                    network: CockpitNetworkSnapshot(
                      totalEntryCount: 3,
                      failureCount: 1,
                      entries: <CockpitNetworkEntry>[
                        CockpitNetworkEntry(
                          requestId: 'net-3',
                          method: 'GET',
                          uri: 'https://api.example.dev/api/profile',
                          startedAt: DateTime.utc(2026, 3, 30, 10, 0, 2),
                          durationMs: 45,
                          statusCode: 200,
                        ),
                      ],
                      endpointSummaries: const <CockpitNetworkEndpointSummary>[
                        CockpitNetworkEndpointSummary(
                          method: 'GET',
                          uriPattern: '/api/messages',
                          requestCount: 2,
                          failureCount: 1,
                          averageDurationMs: 72,
                          lastStatusCode: 503,
                          latestUri: 'https://api.example.dev/api/messages',
                        ),
                      ],
                      capturedEntryCount: 3,
                      inFlightCount: 0,
                      query: const CockpitNetworkQuery(uriContains: '/api'),
                    ),
                  ),
                );
              }
              expect(options.networkQuery.onlyFailures, isTrue);
              return CockpitRemoteSnapshotResponse(
                snapshot: CockpitSnapshot(
                  routeName: '/inbox',
                  network: CockpitNetworkSnapshot(
                    totalEntryCount: 1,
                    failureCount: 1,
                    entries: <CockpitNetworkEntry>[
                      CockpitNetworkEntry(
                        requestId: 'net-2',
                        method: 'GET',
                        uri: 'https://api.example.dev/api/messages',
                        startedAt: DateTime.utc(2026, 3, 30, 10, 0, 1),
                        durationMs: 90,
                        statusCode: 503,
                        error: 'service unavailable',
                      ),
                    ],
                    endpointSummaries: const <CockpitNetworkEndpointSummary>[],
                    capturedEntryCount: 3,
                    inFlightCount: 0,
                    query: const CockpitNetworkQuery(
                      uriContains: '/api',
                      onlyFailures: true,
                    ),
                  ),
                ),
              );
            },
          ).read(
            CockpitReadNetworkRequest(
              baseUri: Uri(scheme: 'http', host: '127.0.0.1', port: 57331),
              uriContains: '/api',
            ),
          );

      expect(readCount, 2);
      expect(result.summary.failureCount, 1);
      expect(result.recentFailures, hasLength(1));
      expect(result.recentFailures.single.requestId, 'net-2');
    },
  );
}

final class _MachineProcessManager implements CockpitProcessManager {
  _MachineProcessManager({
    required this.stdoutPayload,
    this.returnUtf8Bytes = false,
    this.hangOnStart = false,
    this.keepOutputOpenAfterExit = false,
  });

  final String stdoutPayload;
  final bool returnUtf8Bytes;
  final bool hangOnStart;
  final bool keepOutputOpenAfterExit;
  _OpenOutputFakeProcess? openOutputProcess;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    return ProcessResult(
      1,
      0,
      returnUtf8Bytes ? utf8.encode(stdoutPayload) : stdoutPayload,
      '',
    );
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    if (hangOnStart) {
      return _HangingFakeProcess();
    }
    if (keepOutputOpenAfterExit) {
      return openOutputProcess = _OpenOutputFakeProcess(
        stdoutPayload: stdoutPayload,
        stderrPayload: '',
        exitCodeValue: 0,
      );
    }
    return _CompletedFakeProcess(
      stdoutPayload: stdoutPayload,
      stderrPayload: '',
      exitCodeValue: 0,
      returnUtf8Bytes: returnUtf8Bytes,
    );
  }

  Future<void> dispose() async {
    await openOutputProcess?.close();
  }
}

final class _CompletedFakeProcess implements Process {
  _CompletedFakeProcess({
    required String stdoutPayload,
    required String stderrPayload,
    required int exitCodeValue,
    this.returnUtf8Bytes = false,
  }) : stdout = Stream<List<int>>.value(
         returnUtf8Bytes
             ? utf8.encode(stdoutPayload)
             : utf8.encode(stdoutPayload),
       ),
       stderr = Stream<List<int>>.value(
         returnUtf8Bytes
             ? utf8.encode(stderrPayload)
             : utf8.encode(stderrPayload),
       ),
       _exitCode = Future<int>.value(exitCodeValue);

  final Future<int> _exitCode;
  final bool returnUtf8Bytes;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  IOSink get stdin => throw UnsupportedError('stdin is not used in tests');
}

final class _HangingFakeProcess implements Process {
  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  IOSink get stdin => throw UnsupportedError('stdin is not used in tests');
}

final class _OpenOutputFakeProcess implements Process {
  _OpenOutputFakeProcess({
    required String stdoutPayload,
    required String stderrPayload,
    required int exitCodeValue,
  }) : _stdoutController = StreamController<List<int>>(),
       _stderrController = StreamController<List<int>>(),
       _exitCode = Future<int>.value(exitCodeValue) {
    scheduleMicrotask(() {
      _stdoutController.add(utf8.encode(stdoutPayload));
      if (stderrPayload.isNotEmpty) {
        _stderrController.add(utf8.encode(stderrPayload));
      }
    });
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final Future<int> _exitCode;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(close());
    return true;
  }

  @override
  IOSink get stdin => throw UnsupportedError('stdin is not used in tests');

  Future<void> close() async {
    if (!_stdoutController.isClosed) {
      unawaited(_stdoutController.close());
    }
    if (!_stderrController.isClosed) {
      unawaited(_stderrController.close());
    }
  }
}

CockpitDevelopmentSessionHandle _developmentHandle() =>
    CockpitDevelopmentSessionHandle(
      developmentSessionId: 'dev-session-1',
      platform: 'android',
      deviceId: 'emulator-5554',
      projectDir: '/workspace/app',
      target: 'lib/main.dart',
      appId: 'dev.example.app',
      appBaseUrl: 'http://127.0.0.1:57331',
      supervisorBaseUrl: 'http://127.0.0.1:59331',
      launchedAt: DateTime.utc(2026, 3, 30),
      reloadGeneration: 0,
    );

CockpitRemoteSessionHandle _remoteHandle() => CockpitRemoteSessionHandle(
  platform: 'macos',
  deviceId: 'macos',
  projectDir: '/workspace/app',
  target: 'cockpit/main.dart',
  appId: 'dev.example.remote',
  host: '127.0.0.1',
  hostPort: 57331,
  devicePort: 47331,
  baseUrl: 'http://127.0.0.1:57331',
  launchedAt: DateTime.utc(2026, 3, 30),
);

CockpitRemoteSessionStatus _remoteStatus() => CockpitRemoteSessionStatus(
  sessionId: 'remote-session-1',
  platform: 'macos',
  transportType: 'remoteHttp',
  currentRouteName: '/home',
  capabilities: CockpitCapabilities(
    platform: 'macos',
    transportType: 'remoteHttp',
    supportsInAppControl: true,
    supportsFlutterViewCapture: true,
    supportsNativeScreenCapture: true,
    supportsHostAutomation: true,
    supportedCommands: <CockpitCommandType>[CockpitCommandType.tap],
    supportedLocatorStrategies: CockpitLocatorKind.values,
  ),
  recordingCapabilities: CockpitRecordingCapabilities(
    supportsNativeRecording: true,
    preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
  ),
  snapshot: CockpitSnapshot(routeName: '/home'),
);

CockpitDevelopmentSessionStatus _developmentStatus({String? lastError}) =>
    CockpitDevelopmentSessionStatus(
      developmentSessionId: 'dev-session-1',
      state: CockpitDevelopmentSessionState.failed,
      appReachable: false,
      remoteSessionReachable: false,
      reloadGeneration: 0,
      lastError: lastError,
      lastStatusAt: DateTime.utc(2026, 3, 30),
    );
