import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/remote/cockpit_remote_session_endpoint_handler.dart';
import 'package:flutter_cockpit/src/remote/cockpit_remote_session_server.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(FlutterCockpit.dispose);

  test(
    'remote endpoint keeps screenshot evidence downloadable without files',
    () async {
      final handler = CockpitRemoteSessionEndpointHandler(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'inline-evidence-session',
          platform: 'web',
          transportType: 'remoteBridge',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'web',
            transportType: 'remoteBridge',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async =>
            CockpitSnapshot(routeName: '/home'),
        commandExecutor: (command) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: command.commandId,
            commandType: command.commandType,
            durationMs: 12,
            artifacts: const <CockpitArtifactRef>[
              CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/inline.png',
              ),
            ],
          ),
          artifactPayloads: const <String, List<int>>{
            'screenshots/inline.png': <int>[137, 80, 78, 71],
          },
        ),
        startRecording: (_) async => throw StateError('unused'),
        stopRecording: () async => throw StateError('unused'),
        artifactTempFileFactory: (_) async {
          throw UnsupportedError('web cannot persist local artifact files');
        },
      );

      final response = await handler.handle(
        CockpitRemoteSessionEndpointRequest(
          method: 'POST',
          uri: Uri.parse('/commands/execute'),
          jsonBody: CockpitCommand(
            commandId: 'capture-inline',
            commandType: CockpitCommandType.captureScreenshot,
          ).toJson(),
        ),
      );
      final payload = response.jsonBody!;
      final commandResponse = CockpitRemoteCommandResponse.fromJson(payload);

      expect(response.statusCode, HttpStatus.ok);
      expect(commandResponse.result.success, isTrue);
      expect(commandResponse.artifactDownloads, hasLength(1));
      expect(commandResponse.artifactPayloads, isEmpty);
      expect(
        commandResponse.artifactDownloads.single.artifact.relativePath,
        'screenshots/inline.png',
      );
      final downloadResponse = await handler.handle(
        CockpitRemoteSessionEndpointRequest(
          method: 'GET',
          uri: Uri.parse(commandResponse.artifactDownloads.single.downloadPath),
        ),
      );
      expect(downloadResponse.binaryBody, <int>[137, 80, 78, 71]);
    },
  );

  test(
    'remote endpoint returns a command timeout result when command execution stalls',
    () async {
      final handler = CockpitRemoteSessionEndpointHandler(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'timeout-session',
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
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async =>
            CockpitSnapshot(routeName: '/home'),
        commandExecutor: (_) => Completer<CockpitCommandExecution>().future,
        startRecording: (_) async => throw StateError('unused'),
        stopRecording: () async => throw StateError('unused'),
      );

      final response = await handler
          .handle(
            CockpitRemoteSessionEndpointRequest(
              method: 'POST',
              uri: Uri.parse('/commands/execute'),
              jsonBody: CockpitCommand(
                commandId: 'stalling-command',
                commandType: CockpitCommandType.tap,
                timeoutMs: 50,
              ).toJson(),
            ),
          )
          .timeout(const Duration(seconds: 1));
      final commandResponse = CockpitRemoteCommandResponse.fromJson(
        response.jsonBody!,
      );
      final result = commandResponse.result;

      expect(response.statusCode, HttpStatus.ok);
      expect(result.success, isFalse);
      expect(result.commandId, 'stalling-command');
      expect(result.error?.code, CockpitCommandError.timeoutCode);
      expect(result.error?.details['timeoutMs'], 50);
    },
  );

  testWidgets(
    'remote session executes commands against native-discovered widgets',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'remote-native-discovery-session',
        taskId: 'remote-native-discovery-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/home');

      await tester.pumpWidget(
        _RemoteNativeDiscoveryTestApp(
          controller: controller,
          registry: registry,
          configuration: FlutterCockpitConfiguration(
            initialRouteName: '/home',
            remoteSession: const CockpitRemoteSessionConfiguration(
              enabled: true,
              autoStart: false,
              port: 0,
            ),
            nativeRecording: _FakeCockpitNativeRecording(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      final baseUri = await tester.runAsync(() async {
        return rootState.waitForRemoteSession().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('waitForRemoteSession'),
        );
      });

      final snapshotJson = await tester.runAsync(() async {
        return _readJson(baseUri!.resolve('/snapshot'));
      });
      final snapshot = CockpitSnapshot.fromJson(snapshotJson!);
      final nativeButton = snapshot.visibleTargets.firstWhere(
        (target) => target.keyValue == 'native-open-form-button',
      );

      expect(nativeButton.text, 'Open form');
      expect(nativeButton.tooltip, 'Open the remote form');
      expect(nativeButton.semanticId, 'Open form');
      expect(nativeButton.supportedCommands, contains(CockpitCommandType.tap));

      final responseJson = await tester.runAsync(() async {
        return _postJson(
          baseUri!.resolve('/commands/execute'),
          CockpitCommand(
            commandId: 'tap-native-open-form',
            commandType: CockpitCommandType.tap,
            locator: const CockpitLocator(key: 'native-open-form-button'),
          ).toJson(),
        );
      });
      final response = CockpitRemoteCommandResponse.fromJson(responseJson!);

      expect(response.result.success, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(rootState.snapshot().routeName, '/form');
    },
  );

  testWidgets('remote session health returns compact live app state', (
    tester,
  ) async {
    final controller = CockpitSessionController(
      sessionId: 'remote-health-lightweight-session',
      taskId: 'remote-health-lightweight-task',
      platform: 'android',
    );
    final registry = CockpitTargetRegistry(routeName: '/home');

    await tester.pumpWidget(
      _RemoteNativeDiscoveryTestApp(
        controller: controller,
        registry: registry,
        configuration: FlutterCockpitConfiguration(
          initialRouteName: '/home',
          remoteSession: const CockpitRemoteSessionConfiguration(
            enabled: true,
            autoStart: false,
            port: 0,
          ),
          nativeRecording: _FakeCockpitNativeRecording(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final rootState = tester.state<FlutterCockpitRootState>(
      find.byType(FlutterCockpitRoot),
    );
    final baseUri = await tester.runAsync(() async {
      return rootState.waitForRemoteSession().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('waitForRemoteSession'),
      );
    });

    final healthJson = await tester.runAsync(() async {
      return _readJson(baseUri!.resolve('/health'));
    });
    final health = CockpitRemoteSessionStatus.fromJson(healthJson!);
    expect(health.processId, pid);

    expect(health.snapshot.routeName, '/home');
    expect(health.snapshot.diagnosticLevel, CockpitSnapshotProfile.live);
    expect(health.snapshot.visibleTargets, isNotEmpty);
    expect(
      health.snapshot.visibleTargets.any(
        (target) => target.keyValue == 'native-open-form-button',
      ),
      isTrue,
    );
    expect(
      health.snapshot.visibleTargets.any((target) => target.layout != null),
      isFalse,
    );
    expect(health.snapshot.network, isNull);
  });

  testWidgets(
    'remote session health and command execution expose live app state',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'remote-health-session',
        taskId: 'remote-health-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/home');

      await tester.pumpWidget(
        _RemoteTestApp(
          controller: controller,
          registry: registry,
          configuration: FlutterCockpitConfiguration(
            initialRouteName: '/home',
            remoteSession: const CockpitRemoteSessionConfiguration(
              enabled: true,
              autoStart: false,
              port: 0,
            ),
            nativeRecording: _FakeCockpitNativeRecording(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      final baseUri = await tester
          .runAsync(() {
            return rootState.waitForRemoteSession().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                throw TimeoutException('waitForRemoteSession');
              },
            );
          })
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('waitForRemoteSession');
            },
          );

      final healthJson = await tester
          .runAsync(() {
            return _readJson(baseUri!.resolve('/health'));
          })
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('health');
            },
          );
      final health = CockpitRemoteSessionStatus.fromJson(healthJson!);
      expect(health.capabilities.supportsInAppControl, isTrue);
      expect(health.snapshot.routeName, '/home');
      expect(health.snapshot.diagnosticLevel, CockpitSnapshotProfile.live);
      expect(
        health.capabilities.supportedCommands,
        containsAll(<CockpitCommandType>[
          CockpitCommandType.assertVisible,
          CockpitCommandType.assertText,
          CockpitCommandType.waitFor,
          CockpitCommandType.collectSnapshot,
          CockpitCommandType.captureScreenshot,
        ]),
      );

      final responseJson = await tester
          .runAsync(() {
            return _postJson(
              baseUri!.resolve('/commands/execute'),
              CockpitCommand(
                commandId: 'tap-open-form',
                commandType: CockpitCommandType.tap,
                locator: const CockpitLocator(cockpitId: 'open_form_button'),
              ).toJson(),
            );
          })
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('executeCommand');
            },
          );
      final response = CockpitRemoteCommandResponse.fromJson(responseJson!);
      final result = response.result;

      expect(result.success, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(rootState.snapshot().routeName, '/form');
    },
  );

  testWidgets(
    'remote command responses drain runtime steps without an explicit session controller',
    (tester) async {
      FlutterCockpit.initialize(
        FlutterCockpitConfiguration(
          initialRouteName: '/editor',
          remoteSession: CockpitRemoteSessionConfiguration(
            enabled: true,
            autoStart: false,
            port: 0,
          ),
          nativeRecording: _FakeCockpitNativeRecording(),
        ),
      );

      final rootKey = GlobalKey<FlutterCockpitRootState>();

      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[
              FlutterCockpit.navigatorObserver,
            ],
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey<String>('runtime-step-button'),
                  onPressed: () {
                    FlutterCockpit.recordStep(
                      actionType: 'validation_error',
                      actionArgs: const <String, Object?>{
                        'message': 'Task title is required.',
                        'field': 'title',
                      },
                      observation: CockpitObservation(
                        routeName: '/editor',
                        interactiveElements: <String>['Save task'],
                        phase: CockpitObservationPhase.failure,
                      ),
                    );
                  },
                  child: const Text('Save task'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final baseUri = await tester.runAsync(() async {
        return rootKey.currentState!.waitForRemoteSession().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('waitForRemoteSession'),
        );
      });

      final responseJson = await tester.runAsync(() async {
        return _postJson(
          baseUri!.resolve('/commands/execute'),
          CockpitCommand(
            commandId: 'tap-runtime-step',
            commandType: CockpitCommandType.tap,
            locator: const CockpitLocator(key: 'runtime-step-button'),
          ).toJson(),
        );
      });
      final response = CockpitRemoteCommandResponse.fromJson(responseJson!);

      expect(response.result.success, isTrue);
      expect(response.runtimeSteps, hasLength(1));
      expect(response.runtimeSteps.single.actionType, 'validation_error');
      expect(
        response.runtimeSteps.single.actionArgs['message'],
        'Task title is required.',
      );
    },
  );

  testWidgets(
    'remote snapshot endpoint supports explicit diagnostic profile escalation without bloating health',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'remote-snapshot-session',
        taskId: 'remote-snapshot-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/home');

      await tester.pumpWidget(
        _RemoteTestApp(
          controller: controller,
          registry: registry,
          configuration: FlutterCockpitConfiguration(
            initialRouteName: '/home',
            remoteSession: const CockpitRemoteSessionConfiguration(
              enabled: true,
              autoStart: false,
              port: 0,
            ),
            nativeRecording: _FakeCockpitNativeRecording(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      final baseUri = await tester.runAsync(() async {
        return rootState.waitForRemoteSession().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('waitForRemoteSession'),
        );
      });

      final healthJson = await tester.runAsync(() async {
        return _readJson(baseUri!.resolve('/health'));
      });
      final health = CockpitRemoteSessionStatus.fromJson(healthJson!);

      final snapshotJson = await tester.runAsync(() async {
        return _readJson(
          baseUri!.resolve(
            '/snapshot?profile=investigate&includeStyleDetails=true&includeDiagnosticProperties=true',
          ),
        );
      });
      final snapshot = CockpitSnapshot.fromJson(snapshotJson!);

      expect(health.snapshot.diagnosticLevel, CockpitSnapshotProfile.live);
      expect(snapshot.diagnosticLevel, CockpitSnapshotProfile.investigate);
      expect(snapshot.visibleTargets, isNotEmpty);
      expect(
        snapshot.visibleTargets.any((target) => target.layout != null),
        isTrue,
      );
    },
  );

  test('remote session health output omits null fields', () async {
    final server = CockpitRemoteSessionServer(
      configuration: const CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        port: 0,
      ),
      statusProvider: () async => CockpitRemoteSessionStatus(
        sessionId: 'remote-health-compact',
        platform: 'android',
        transportType: 'remoteHttp',
        currentRouteName: null,
        capabilities: CockpitCapabilities(
          platform: 'android',
          transportType: 'remoteHttp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: false,
          supportsHostAutomation: false,
          supportedCommands: const <CockpitCommandType>[
            CockpitCommandType.collectSnapshot,
          ],
          supportedLocatorStrategies: CockpitLocatorKind.values,
        ),
        recordingCapabilities: CockpitRecordingCapabilities(
          supportsNativeRecording: false,
          preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        ),
        snapshot: CockpitSnapshot(routeName: '/home'),
      ),
      snapshotProvider: ({required options}) async =>
          CockpitSnapshot(routeName: '/home', diagnosticLevel: options.profile),
      commandExecutor: (_) async => CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'noop',
          commandType: CockpitCommandType.collectSnapshot,
          durationMs: 0,
        ),
      ),
      startRecording: (request) async => CockpitRecordingSession(
        request: request,
        state: CockpitRecordingState.recording,
      ),
      stopRecording: () async =>
          CockpitRecordingResult(state: CockpitRecordingState.failed),
    );
    await server.start();
    addTearDown(server.close);

    final healthJson = await _readJson(server.baseUri!.resolve('/health'));

    expect(healthJson, isNotNull);
    expect(healthJson['sessionId'], 'remote-health-compact');
    expect(healthJson.containsKey('currentRouteName'), isFalse);
    expect(healthJson.containsKey('environment'), isFalse);
    expect(healthJson.containsKey('activeRecording'), isFalse);
  });

  test('remote session ping avoids heavyweight status construction', () async {
    var statusCalls = 0;
    final server = CockpitRemoteSessionServer(
      configuration: const CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        port: 0,
        routePrefix: '/cockpit',
      ),
      statusProvider: () async {
        statusCalls += 1;
        throw StateError('status should not be used for ping');
      },
      snapshotProvider: ({required options}) async =>
          CockpitSnapshot(routeName: '/home', diagnosticLevel: options.profile),
      commandExecutor: (_) async => CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'noop',
          commandType: CockpitCommandType.collectSnapshot,
          durationMs: 0,
        ),
      ),
      startRecording: (request) async => CockpitRecordingSession(
        request: request,
        state: CockpitRecordingState.recording,
      ),
      stopRecording: () async =>
          CockpitRecordingResult(state: CockpitRecordingState.failed),
    );
    await server.start();
    addTearDown(server.close);

    final pingJson = await _readJson(Uri.parse('${server.baseUri}/ping'));

    expect(pingJson['ok'], isTrue);
    expect(pingJson['transportType'], 'remoteHttp');
    expect(pingJson['routePrefix'], '/cockpit');
    expect(statusCalls, 0);
  });

  test('remote session ready avoids heavyweight status construction', () async {
    var statusCalls = 0;
    var readyCalls = 0;
    final server = CockpitRemoteSessionServer(
      configuration: const CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        port: 0,
        routePrefix: '/cockpit',
      ),
      statusProvider: () async {
        statusCalls += 1;
        throw StateError('status should not be used for readiness');
      },
      readyProvider: () {
        readyCalls += 1;
        return const <String, Object?>{
          'ready': true,
          'currentRouteName': '/home',
          'supportsInAppControl': true,
        };
      },
      snapshotProvider: ({required options}) async =>
          CockpitSnapshot(routeName: '/home', diagnosticLevel: options.profile),
      commandExecutor: (_) async => CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'noop',
          commandType: CockpitCommandType.collectSnapshot,
          durationMs: 0,
        ),
      ),
      startRecording: (request) async => CockpitRecordingSession(
        request: request,
        state: CockpitRecordingState.recording,
      ),
      stopRecording: () async =>
          CockpitRecordingResult(state: CockpitRecordingState.failed),
    );
    await server.start();
    addTearDown(server.close);

    final readyJson = await _readJson(Uri.parse('${server.baseUri}/ready'));

    expect(readyJson['ok'], isTrue);
    expect(readyJson['ready'], isTrue);
    expect(readyJson['currentRouteName'], '/home');
    expect(readyJson['transportType'], 'remoteHttp');
    expect(statusCalls, 0);
    expect(readyCalls, 1);
  });

  test(
    'remote snapshot endpoint forwards network diagnostic query parameters',
    () async {
      CockpitSnapshotOptions? capturedOptions;
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-network-options',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.collectSnapshot,
            ],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async {
          capturedOptions = options;
          return CockpitSnapshot(
            routeName: '/home',
            diagnosticLevel: options.profile,
          );
        },
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.collectSnapshot,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async =>
            CockpitRecordingResult(state: CockpitRecordingState.failed),
      );
      await server.start();
      addTearDown(server.close);

      final baseUri = server.baseUri;
      expect(baseUri, isNotNull);

      await _readJson(
        baseUri!.resolve(
          '/snapshot?profile=forensic&includeNetworkActivity=true&maxNetworkEntries=15&emitArtifactWhenLarge=true&networkOnlyFailures=true&networkMethod=POST&networkUriContains=%2Fsync&networkStatusCodeAtLeast=500',
        ),
      );

      expect(capturedOptions?.profile, CockpitSnapshotProfile.forensic);
      expect(capturedOptions?.includeNetworkActivity, isTrue);
      expect(capturedOptions?.maxNetworkEntries, 15);
      expect(capturedOptions?.emitArtifactWhenLarge, isTrue);
      expect(capturedOptions?.networkQuery.onlyFailures, isTrue);
      expect(capturedOptions?.networkQuery.method, 'POST');
      expect(capturedOptions?.networkQuery.uriContains, '/sync');
      expect(capturedOptions?.networkQuery.statusCodeAtLeast, 500);
    },
  );

  test(
    'remote snapshot endpoint forwards rebuild diagnostic query parameters while health stays lightweight',
    () async {
      CockpitSnapshotOptions? capturedOptions;
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-rebuild-options',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.collectSnapshot,
            ],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(
            routeName: '/home',
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
        snapshotProvider: ({required options}) async {
          capturedOptions = options;
          return CockpitSnapshot(
            routeName: '/home',
            diagnosticLevel: options.profile,
            summary: CockpitSnapshotSummary(
              visibleTargetCount: 0,
              targetsWithCockpitIdCount: 0,
              targetsWithTextCount: 0,
              styleDetailsIncluded: options.includeStyleDetails,
              diagnosticPropertiesIncluded: options.includeDiagnosticProperties,
              ancestorSummariesIncluded: options.maxAncestorsPerTarget > 0,
              rebuildSummaryIncluded: options.includeRebuildActivity,
              accessibilitySummaryIncluded: options.includeAccessibilitySummary,
            ),
            rebuild: options.includeRebuildActivity
                ? const CockpitRebuildSnapshot(
                    totalRebuildCount: 4,
                    uniqueElementCount: 1,
                    capturedEntryCount: 1,
                    truncated: false,
                    entries: <CockpitRebuildEntry>[
                      CockpitRebuildEntry(
                        signature: '/home|FilledButton|save|',
                        routeName: '/home',
                        typeName: 'FilledButton',
                        rebuildCount: 4,
                        builtOnceCount: 1,
                        keyValue: 'save',
                      ),
                    ],
                  )
                : null,
          );
        },
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.collectSnapshot,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async =>
            CockpitRecordingResult(state: CockpitRecordingState.failed),
      );
      await server.start();
      addTearDown(server.close);

      final baseUri = server.baseUri;
      expect(baseUri, isNotNull);

      final healthJson = await _readJson(baseUri!.resolve('/health'));
      final health = CockpitRemoteSessionStatus.fromJson(healthJson);

      final snapshotJson = await _readJson(
        baseUri.resolve(
          '/snapshot?profile=investigate&includeRebuildActivity=true&maxRebuildEntries=1',
        ),
      );
      final snapshot = CockpitSnapshot.fromJson(snapshotJson);

      expect(health.snapshot.diagnosticLevel, CockpitSnapshotProfile.live);
      expect(health.snapshot.rebuild, isNull);
      expect(health.snapshot.summary?.rebuildSummaryIncluded, isFalse);
      expect(capturedOptions?.includeRebuildActivity, isTrue);
      expect(capturedOptions?.maxRebuildEntries, 1);
      expect(snapshot.rebuild?.totalRebuildCount, 4);
      expect(snapshot.summary?.rebuildSummaryIncluded, isTrue);
    },
  );

  test(
    'remote snapshot endpoint rejects invalid query parameters instead of silently defaulting',
    () async {
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-invalid-query',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async => CockpitSnapshot(
          routeName: '/home',
          diagnosticLevel: options.profile,
        ),
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.collectSnapshot,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async =>
            CockpitRecordingResult(state: CockpitRecordingState.failed),
      );
      await server.start();
      addTearDown(server.close);

      for (final invalidPath in <String>[
        '/snapshot?profile=deep',
        '/snapshot?maxTargets=abc',
        '/snapshot?maxNetworkEntries=-1',
        '/snapshot?includeNetworkActivity=yes',
      ]) {
        final response = await _readBinaryResponse(
          server.baseUri!.resolve(invalidPath),
        );
        final body = Map<String, Object?>.from(
          jsonDecode(utf8.decode(response.bytes)) as Map<Object?, Object?>,
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(body['error'], 'invalidPayload');
        expect(body['message'], contains('Query parameter'));
      }
    },
  );

  test(
    'remote command endpoint rejects unknown commandType values with 400 invalidPayload',
    () async {
      final handler = CockpitRemoteSessionEndpointHandler(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'invalid-command-session',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async =>
            CockpitSnapshot(routeName: '/home'),
        commandExecutor: (_) async =>
            throw StateError('The executor must not run for invalid payloads.'),
        startRecording: (_) async => throw StateError('unused'),
        stopRecording: () async => throw StateError('unused'),
      );

      final response = await handler.handle(
        CockpitRemoteSessionEndpointRequest(
          method: 'POST',
          uri: Uri.parse('/commands/execute'),
          jsonBody: const <String, Object?>{
            'commandId': 'bogus-command',
            'commandType': 'launchMissiles',
          },
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.jsonBody?['error'], 'invalidPayload');
      expect(response.jsonBody?['message'], contains('launchMissiles'));
    },
  );

  test(
    'remote snapshot endpoint externalizes large forensic payloads into downloadable diagnostics artifacts',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_remote_snapshot_artifacts',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final artifactFile = File(
        p.join(tempDir.path, 'remote_snapshot_debug.json'),
      );
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
          routePrefix: '/cockpit',
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-forensic-snapshot',
          platform: 'android',
          transportType: 'remoteHttp',
          currentRouteName: '/debug',
          capabilities: CockpitCapabilities(
            platform: 'android',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.collectSnapshot,
            ],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/debug'),
        ),
        snapshotProvider: ({required options}) async => CockpitSnapshot(
          routeName: '/debug',
          diagnosticLevel: options.profile,
          visibleTargets: <CockpitSnapshotTarget>[
            CockpitSnapshotTarget(
              registrationId: 'debug.sync-check',
              keyValue: 'settings-sync-check-button',
              text: 'Run check',
              typeName: 'FilledButton',
              routeName: '/debug',
              supportedCommands: const <CockpitCommandType>[
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
        ),
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.collectSnapshot,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async =>
            CockpitRecordingResult(state: CockpitRecordingState.failed),
        artifactTempFileFactory: (_) async => artifactFile,
      );
      await server.start();
      expect(server.baseUri?.path, '/cockpit');

      final unscopedHealthResponse = await _readBinaryResponse(
        server.baseUri!.replace(path: '/health'),
      );
      expect(unscopedHealthResponse.statusCode, HttpStatus.notFound);

      final responseJson = await _readJson(
        Uri.parse(
          '${server.baseUri}/snapshot?profile=forensic&includeDiagnosticProperties=true&emitArtifactWhenLarge=true',
        ),
      );

      expect(responseJson['snapshot'], isA<Map<Object?, Object?>>());
      expect(responseJson['artifactDownloads'], isA<List<Object?>>());
      final snapshot = CockpitSnapshot.fromJson(
        Map<String, Object?>.from(
          responseJson['snapshot']! as Map<Object?, Object?>,
        ),
      );
      expect(snapshot.diagnosticsArtifactRef, isNotNull);
      expect(
        snapshot.diagnosticsArtifactRef!.relativePath,
        matches(RegExp(r'^diagnostics/\d{8}T\d{12}Z_remote_snapshot\.json$')),
      );
      expect(snapshot.visibleTargets.single.diagnosticProperties, isEmpty);

      final downloadPath =
          ((responseJson['artifactDownloads']! as List<Object?>).single
                  as Map<Object?, Object?>)['downloadPath']!
              as String;
      expect(downloadPath, startsWith('/cockpit/artifacts/download?path='));
      final downloadedJson = await _readJson(
        server.baseUri!.resolve(downloadPath),
      );
      final downloadedSnapshot = CockpitSnapshot.fromJson(downloadedJson);
      expect(
        downloadedSnapshot
            .visibleTargets
            .single
            .diagnosticProperties
            .single
            .value
            .length,
        greaterThan(20000),
      );
      expect(artifactFile.existsSync(), isTrue);

      await server.close();
      expect(artifactFile.existsSync(), isFalse);
    },
  );

  test('full and large standard widget trees are tree-only downloads', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_remote_widget_tree',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });
    final artifactFile = File(p.join(tempDir.path, 'widget_tree.json'));
    CockpitSnapshotOptions? capturedOptions;
    final server = CockpitRemoteSessionServer(
      configuration: const CockpitRemoteSessionConfiguration(
        enabled: true,
        autoStart: false,
        port: 0,
      ),
      statusProvider: () async => CockpitRemoteSessionStatus(
        sessionId: 'remote-widget-tree',
        platform: 'macos',
        transportType: 'remoteHttp',
        currentRouteName: '/tree',
        capabilities: CockpitCapabilities(
          platform: 'macos',
          transportType: 'remoteHttp',
          supportsInAppControl: true,
          supportsFlutterViewCapture: true,
          supportsNativeScreenCapture: false,
          supportsHostAutomation: false,
          supportedCommands: const <CockpitCommandType>[
            CockpitCommandType.collectSnapshot,
          ],
          supportedLocatorStrategies: CockpitLocatorKind.values,
        ),
        recordingCapabilities: CockpitRecordingCapabilities(
          supportsNativeRecording: false,
          preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        ),
        snapshot: CockpitSnapshot(routeName: '/tree'),
      ),
      snapshotProvider: ({required options}) async {
        capturedOptions = options;
        final profile = options.tree?.profile ?? CockpitWidgetTreeProfile.full;
        return CockpitSnapshot(
          routeName: '/tree',
          tree: CockpitWidgetTree(
            profile: profile,
            total: 1,
            visible: 1,
            truncated: false,
            nodes: <CockpitWidgetNode>[
              CockpitWidgetNode(
                node: 0,
                depth: 0,
                type: 'TextButton',
                text: profile == CockpitWidgetTreeProfile.standard
                    ? 'x' * 20000
                    : 'Continue',
                visible: true,
                offstage: false,
              ),
            ],
          ),
        );
      },
      commandExecutor: (_) async => CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: 'noop',
          commandType: CockpitCommandType.collectSnapshot,
          durationMs: 0,
        ),
      ),
      startRecording: (request) async => CockpitRecordingSession(
        request: request,
        state: CockpitRecordingState.recording,
      ),
      stopRecording: () async =>
          CockpitRecordingResult(state: CockpitRecordingState.failed),
      artifactTempFileFactory: (_) async => artifactFile,
    );
    await server.start();

    final responseJson = await _readJson(
      server.baseUri!.resolve(
        '/snapshot?treeProfile=full&treeMaxNodes=100&treeMaxProps=4',
      ),
    );
    expect(capturedOptions?.tree?.profile, CockpitWidgetTreeProfile.full);
    expect(capturedOptions?.tree?.maxNodes, 100);
    expect(capturedOptions?.tree?.maxProps, 4);
    final snapshot = CockpitSnapshot.fromJson(
      Map<String, Object?>.from(
        responseJson['snapshot']! as Map<Object?, Object?>,
      ),
    );
    expect(snapshot.treeArtifactRef?.role, 'widget-tree');
    expect(snapshot.tree?.nodes, isEmpty);
    expect(snapshot.tree?.emitted, 1);

    final downloadPath =
        ((responseJson['artifactDownloads']! as List<Object?>).single
                as Map<Object?, Object?>)['downloadPath']!
            as String;
    final downloaded = CockpitWidgetTree.fromJson(
      await _readJson(server.baseUri!.resolve(downloadPath)),
    );
    expect(downloaded.nodes.single.text, 'Continue');

    final standardResponseJson = await _readJson(
      server.baseUri!.resolve(
        '/snapshot?treeProfile=standard&treeMaxNodes=100&treeMaxProps=0&emitArtifactWhenLarge=true',
      ),
    );
    final standardSnapshot = CockpitSnapshot.fromJson(
      Map<String, Object?>.from(
        standardResponseJson['snapshot']! as Map<Object?, Object?>,
      ),
    );
    expect(standardSnapshot.treeArtifactRef?.role, 'widget-tree');
    expect(standardSnapshot.diagnosticsArtifactRef, isNull);
    expect(standardSnapshot.tree?.nodes, isEmpty);
    final standardDownloadPath =
        ((standardResponseJson['artifactDownloads']! as List<Object?>).single
                as Map<Object?, Object?>)['downloadPath']!
            as String;
    final standardTree = CockpitWidgetTree.fromJson(
      await _readJson(server.baseUri!.resolve(standardDownloadPath)),
    );
    expect(standardTree.profile, CockpitWidgetTreeProfile.standard);
    expect(standardTree.nodes.single.text?.length, greaterThan(19000));

    await server.close();
  });

  test(
    'large artifacts remain downloadable when file persistence is unavailable',
    () async {
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-inline-fallback-session',
          platform: 'web',
          transportType: 'remoteHttp',
          currentRouteName: '/debug',
          capabilities: CockpitCapabilities(
            platform: 'web',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: false,
            supportsHostAutomation: false,
            supportedCommands: const <CockpitCommandType>[
              CockpitCommandType.collectSnapshot,
            ],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: false,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/debug'),
        ),
        snapshotProvider: ({required options}) async => CockpitSnapshot(
          routeName: '/debug',
          diagnosticLevel: options.profile,
          visibleTargets: <CockpitSnapshotTarget>[
            CockpitSnapshotTarget(
              registrationId: 'debug.sync-check',
              keyValue: 'settings-sync-check-button',
              text: 'Run check',
              typeName: 'FilledButton',
              routeName: '/debug',
              supportedCommands: const <CockpitCommandType>[
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
        ),
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.collectSnapshot,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async =>
            CockpitRecordingResult(state: CockpitRecordingState.failed),
        artifactTempFileFactory: (_) async {
          throw UnsupportedError('Unsupported operation: _Namespace');
        },
      );
      await server.start();

      final responseJson = await _readJson(
        server.baseUri!.resolve(
          '/snapshot?profile=forensic&includeDiagnosticProperties=true&emitArtifactWhenLarge=true',
        ),
      );

      final snapshot = CockpitSnapshot.fromJson(
        Map<String, Object?>.from(
          responseJson['snapshot']! as Map<Object?, Object?>,
        ),
      );
      expect(snapshot.diagnosticsArtifactRef, isNotNull);
      expect(snapshot.visibleTargets.single.diagnosticProperties, isEmpty);
      final downloadPath =
          ((responseJson['artifactDownloads']! as List<Object?>).single
                  as Map<Object?, Object?>)['downloadPath']!
              as String;
      final downloaded = CockpitSnapshot.fromJson(
        await _readJson(server.baseUri!.resolve(downloadPath)),
      );
      expect(
        downloaded
            .visibleTargets
            .single
            .diagnosticProperties
            .single
            .value
            .length,
        greaterThan(20000),
      );

      await server.close();
    },
  );

  testWidgets(
    'remote session health reports native capture support when the plugin is available',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const captureChannel = MethodChannel(
        'dev.cockpit.flutter_cockpit/capture',
      );
      messenger.setMockMethodCallHandler(captureChannel, (call) async {
        switch (call.method) {
          case 'queryNativeCaptureAvailability':
            return true;
          case 'captureAcceptanceScreenshot':
            return <String, Object?>{
              'bytes': Uint8List.fromList(<int>[137, 80, 78, 71]),
            };
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(captureChannel, null),
      );

      final controller = CockpitSessionController(
        sessionId: 'remote-native-capture-session',
        taskId: 'remote-native-capture-task',
        platform: 'android',
      );
      final registry = CockpitTargetRegistry(routeName: '/home');

      await tester.pumpWidget(
        _RemoteTestApp(
          controller: controller,
          registry: registry,
          configuration: FlutterCockpitConfiguration(
            initialRouteName: '/home',
            remoteSession: const CockpitRemoteSessionConfiguration(
              enabled: true,
              autoStart: false,
              port: 0,
            ),
            nativeCapture: const CockpitNativeCapture(channel: captureChannel),
            nativeRecording: _FakeCockpitNativeRecording(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      final baseUri = await tester.runAsync(() async {
        return rootState.waitForRemoteSession().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('waitForRemoteSession');
          },
        );
      });

      final responseJson = await tester.runAsync(() async {
        return _readJson(baseUri!.resolve('/health'));
      });
      final status = CockpitRemoteSessionStatus.fromJson(responseJson!);

      expect(status.capabilities.supportsNativeScreenCapture, isTrue);
    },
  );

  testWidgets(
    'remote session health degrades unsupported platform capability probes instead of failing',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const captureChannel = MethodChannel(
        'dev.cockpit.flutter_cockpit/capture',
      );
      messenger.setMockMethodCallHandler(captureChannel, (call) async {
        if (call.method == 'queryNativeCaptureAvailability') {
          throw UnsupportedError('Unsupported operation: _Namespace');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(captureChannel, null),
      );

      final controller = CockpitSessionController(
        sessionId: 'remote-capability-fallback-session',
        taskId: 'remote-capability-fallback-task',
        platform: 'web',
      );
      final registry = CockpitTargetRegistry(routeName: '/home');

      await tester.pumpWidget(
        _RemoteTestApp(
          controller: controller,
          registry: registry,
          configuration: FlutterCockpitConfiguration(
            initialRouteName: '/home',
            remoteSession: const CockpitRemoteSessionConfiguration(
              enabled: true,
              autoStart: false,
              port: 0,
            ),
            nativeCapture: const CockpitNativeCapture(channel: captureChannel),
            nativeRecording: _ThrowingCockpitNativeRecording(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      final baseUri = await tester.runAsync(() async {
        return rootState.waitForRemoteSession().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('waitForRemoteSession');
          },
        );
      });

      final response = (await tester.runAsync(() async {
        return _readBinaryResponse(baseUri!.resolve('/health'));
      }))!;

      expect(response.statusCode, HttpStatus.ok);
      final status = CockpitRemoteSessionStatus.fromJson(
        jsonDecode(utf8.decode(response.bytes)) as Map<String, Object?>,
      );
      expect(status.capabilities.supportsNativeScreenCapture, isFalse);
      expect(status.recordingCapabilities.supportsNativeRecording, isFalse);
      expect(
        status.recordingCapabilities.recordingLimitations.single,
        contains('Unsupported operation: _Namespace'),
      );
    },
  );

  testWidgets(
    'remote session capture command falls back cleanly when native capture is unavailable',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'remote-capture-session',
        taskId: 'remote-capture-task',
        platform: 'ios',
      );
      final registry = CockpitTargetRegistry(routeName: '/home');

      await tester.pumpWidget(
        _RemoteTestApp(
          controller: controller,
          registry: registry,
          configuration: const FlutterCockpitConfiguration(
            initialRouteName: '/home',
            remoteSession: CockpitRemoteSessionConfiguration(
              enabled: true,
              autoStart: false,
              port: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final rootState = tester.state<FlutterCockpitRootState>(
        find.byType(FlutterCockpitRoot),
      );
      final baseUri = await tester
          .runAsync(() {
            return rootState.waitForRemoteSession().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                throw TimeoutException('waitForRemoteSession');
              },
            );
          })
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('waitForRemoteSession');
            },
          );

      final responseJson = await tester
          .runAsync(() {
            return _postJson(
              baseUri!.resolve('/commands/execute'),
              CockpitCommand(
                commandId: 'capture-home',
                commandType: CockpitCommandType.captureScreenshot,
                screenshotRequest: const CockpitScreenshotRequest(
                  reason: CockpitScreenshotReason.acceptance,
                  name: 'remote-home',
                  includeSnapshot: true,
                  attachToStep: true,
                ),
              ).toJson(),
            );
          })
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('executeCaptureCommand');
            },
          );

      final response = CockpitRemoteCommandResponse.fromJson(responseJson!);
      final result = response.result;

      expect(result.success, isTrue);
      expect(result.requestedCaptureProfile, CockpitCaptureProfile.acceptance);
      expect(result.resolvedCaptureKind, CockpitCaptureKind.flutterView);
      expect(result.usedCaptureFallback, isTrue);
      expect(result.degradationReason, 'nativeCaptureUnavailable');
      expect(response.artifactPayloads, isEmpty);
      expect(response.artifactDownloads, hasLength(1));
      expect(
        result.artifacts.single.relativePath,
        allOf(startsWith('screenshots/'), endsWith('.png')),
      );
      expect(
        response.artifactDownloads.single.artifact.relativePath,
        result.artifacts.single.relativePath,
      );
      final downloadedBytes = await tester.runAsync(() {
        return _readBytes(
          baseUri!.resolve(response.artifactDownloads.single.downloadPath),
        );
      });
      expect(downloadedBytes, isNotNull);
      expect(downloadedBytes, isNotEmpty);
    },
  );

  test(
    'remote session recording endpoints expose downloadable artifacts',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_remote_recording_server_test',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File(
        p.join(tempDir.path, 'recordings', 'remote_home_acceptance.mp4'),
      );
      sourceFile.parent.createSync(recursive: true);
      sourceFile.writeAsBytesSync(const <int>[1, 2, 3, 4]);

      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-recording-session',
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
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async => CockpitSnapshot(
          routeName: '/home',
          diagnosticLevel: options.profile,
        ),
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.tap,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async => CockpitRecordingResult(
          state: CockpitRecordingState.completed,
          purpose: CockpitRecordingPurpose.acceptance,
          recordingKind: CockpitRecordingKind.nativeScreen,
          artifact: const CockpitArtifactRef(
            role: 'recording',
            relativePath: 'recordings/remote_home_acceptance.mp4',
          ),
          durationMs: 1800,
          sourceFilePath: sourceFile.path,
        ),
      );
      await server.start();
      addTearDown(server.close);

      final baseUri = server.baseUri;
      expect(baseUri, isNotNull);
      final resolvedBaseUri =
          baseUri ??
          (throw StateError('Remote session server failed to start.'));

      final sessionJson = await _postJson(
        resolvedBaseUri.resolve('/recording/start'),
        const <String, Object?>{
          'purpose': 'acceptance',
          'name': 'remote_home_acceptance',
          'attachToStep': true,
        },
      );
      final session = CockpitRecordingSession.fromJson(sessionJson);
      expect(session.state, CockpitRecordingState.recording);

      final resultJson = await _postJson(
        resolvedBaseUri.resolve('/recording/stop'),
        const <String, Object?>{},
      );
      final response = CockpitRemoteRecordingResponse.fromJson(resultJson);
      final result = response.result;

      expect(result.state, CockpitRecordingState.completed);
      expect(
        result.artifact?.relativePath,
        'recordings/remote_home_acceptance.mp4',
      );
      expect(response.artifactDownloads, hasLength(1));
      expect(
        response.artifactDownloads.single.artifact.relativePath,
        'recordings/remote_home_acceptance.mp4',
      );
      expect(
        response.artifactDownloads.single.downloadPath,
        '/artifacts/download?path=recordings%2Fremote_home_acceptance.mp4',
      );
      expect(
        await _readBytes(
          resolvedBaseUri.resolve(
            response.artifactDownloads.single.downloadPath,
          ),
        ),
        <int>[1, 2, 3, 4],
      );
      sourceFile.deleteSync();
      final deletedResponse = await _readBinaryResponse(
        resolvedBaseUri.resolve(response.artifactDownloads.single.downloadPath),
      );
      expect(deletedResponse.statusCode, HttpStatus.notFound);
    },
  );

  test(
    'remote recording responses externalize inline bytes and omit transport-heavy fields',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_remote_recording_bytes',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final artifactFile = File(p.join(tempDir.path, 'recording.mp4'));
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-recording-bytes',
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
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async => CockpitSnapshot(
          routeName: '/home',
          diagnosticLevel: options.profile,
        ),
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.tap,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async => CockpitRecordingResult(
          state: CockpitRecordingState.completed,
          purpose: CockpitRecordingPurpose.acceptance,
          recordingKind: CockpitRecordingKind.nativeScreen,
          artifact: const CockpitArtifactRef(
            role: 'recording',
            relativePath: 'recordings/remote_inline_acceptance.mp4',
          ),
          durationMs: 900,
          bytes: const <int>[9, 8, 7, 6],
          sourceFilePath: '/device/private/recording.mp4',
        ),
        artifactTempFileFactory: (_) async => artifactFile,
      );
      await server.start();

      await _postJson(
        server.baseUri!.resolve('/recording/start'),
        const <String, Object?>{
          'purpose': 'acceptance',
          'name': 'remote_inline_acceptance',
        },
      );

      final resultJson = await _postJson(
        server.baseUri!.resolve('/recording/stop'),
        const <String, Object?>{},
      );
      final resultPayload = Map<String, Object?>.from(
        resultJson['result']! as Map<Object?, Object?>,
      );
      final response = CockpitRemoteRecordingResponse.fromJson(resultJson);

      expect(resultPayload.containsKey('bytes'), isFalse);
      expect(resultPayload.containsKey('sourceFilePath'), isFalse);
      expect(response.result.bytes, isNull);
      expect(response.result.sourceFilePath, isNull);
      expect(response.artifactDownloads, hasLength(1));
      expect(
        await _readBytes(
          server.baseUri!.resolve(
            response.artifactDownloads.single.downloadPath,
          ),
        ),
        <int>[9, 8, 7, 6],
      );
      expect(artifactFile.existsSync(), isTrue);

      await server.close();
      expect(artifactFile.existsSync(), isFalse);
    },
  );

  test('remote recording rejects zero-length source files', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_remote_empty_source',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final sourceFile = File(p.join(tempDir.path, 'empty.mp4'));
    await sourceFile.create();
    final handler = _recordingEndpointHandler(
      result: CockpitRecordingResult(
        state: CockpitRecordingState.completed,
        purpose: CockpitRecordingPurpose.acceptance,
        artifact: const CockpitArtifactRef(
          role: 'recording',
          relativePath: 'recordings/empty.mp4',
        ),
        sourceFilePath: sourceFile.path,
      ),
    );

    final response = await handler.handle(
      CockpitRemoteSessionEndpointRequest(
        method: 'POST',
        uri: Uri.parse('/recording/stop'),
      ),
    );
    final recording = CockpitRemoteRecordingResponse.fromJson(
      response.jsonBody!,
    );

    expect(recording.result.artifact, isNull);
    expect(recording.artifactDownloads, isEmpty);
  });

  test('remote recording never persists empty inline bytes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_remote_empty_bytes',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final artifactFile = File(p.join(tempDir.path, 'empty.mp4'));
    var createdArtifactFile = false;
    final handler = _recordingEndpointHandler(
      result: CockpitRecordingResult(
        state: CockpitRecordingState.completed,
        purpose: CockpitRecordingPurpose.acceptance,
        artifact: const CockpitArtifactRef(
          role: 'recording',
          relativePath: 'recordings/empty.mp4',
        ),
        bytes: const <int>[],
      ),
      artifactTempFileFactory: (_) async {
        createdArtifactFile = true;
        return artifactFile;
      },
    );

    final response = await handler.handle(
      CockpitRemoteSessionEndpointRequest(
        method: 'POST',
        uri: Uri.parse('/recording/stop'),
      ),
    );
    final recording = CockpitRemoteRecordingResponse.fromJson(
      response.jsonBody!,
    );

    expect(recording.result.artifact, isNull);
    expect(recording.artifactDownloads, isEmpty);
    expect(createdArtifactFile, isFalse);
    expect(artifactFile.existsSync(), isFalse);
  });

  test(
    'remote session server stops an active recording when it closes',
    () async {
      var stopRecordingCount = 0;
      final server = CockpitRemoteSessionServer(
        configuration: const CockpitRemoteSessionConfiguration(
          enabled: true,
          autoStart: false,
          port: 0,
        ),
        statusProvider: () async => CockpitRemoteSessionStatus(
          sessionId: 'remote-active-recording-close',
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
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
        snapshotProvider: ({required options}) async => CockpitSnapshot(
          routeName: '/home',
          diagnosticLevel: options.profile,
        ),
        commandExecutor: (_) async => CockpitCommandExecution(
          result: CockpitCommandResult(
            success: true,
            commandId: 'noop',
            commandType: CockpitCommandType.tap,
            durationMs: 0,
          ),
        ),
        startRecording: (request) async => CockpitRecordingSession(
          request: request,
          state: CockpitRecordingState.recording,
        ),
        stopRecording: () async {
          stopRecordingCount += 1;
          return CockpitRecordingResult(
            state: CockpitRecordingState.completed,
            purpose: CockpitRecordingPurpose.acceptance,
            recordingKind: CockpitRecordingKind.nativeScreen,
          );
        },
      );
      await server.start();

      final baseUri = server.baseUri;
      expect(baseUri, isNotNull);
      final resolvedBaseUri =
          baseUri ??
          (throw StateError('Remote session server failed to start.'));

      final sessionJson = await _postJson(
        resolvedBaseUri.resolve('/recording/start'),
        const <String, Object?>{
          'purpose': 'acceptance',
          'name': 'remote_home_acceptance',
          'attachToStep': true,
        },
      );

      final session = CockpitRecordingSession.fromJson(sessionJson);
      expect(session.state, CockpitRecordingState.recording);

      await server.close();

      expect(stopRecordingCount, 1);
    },
  );
}

CockpitRemoteSessionEndpointHandler _recordingEndpointHandler({
  required CockpitRecordingResult result,
  CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
}) {
  return CockpitRemoteSessionEndpointHandler(
    configuration: const CockpitRemoteSessionConfiguration(
      enabled: true,
      autoStart: false,
      port: 0,
    ),
    statusProvider: () async => CockpitRemoteSessionStatus(
      sessionId: 'recording-artifact-contract',
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
      ),
      recordingCapabilities: CockpitRecordingCapabilities(
        supportsNativeRecording: true,
      ),
      snapshot: CockpitSnapshot(routeName: '/home'),
    ),
    snapshotProvider: ({required options}) async =>
        CockpitSnapshot(routeName: '/home', diagnosticLevel: options.profile),
    commandExecutor: (command) async => CockpitCommandExecution(
      result: CockpitCommandResult(
        success: true,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 0,
      ),
    ),
    startRecording: (request) async => CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    ),
    stopRecording: () async => result,
    artifactTempFileFactory: artifactTempFileFactory,
  );
}

Future<Map<String, Object?>> _readJson(Uri uri) async {
  return HttpOverrides.runZoned(() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final payload = jsonDecode(await utf8.decoder.bind(response).join());
      return Map<String, Object?>.from(payload as Map<Object?, Object?>);
    } finally {
      client.close(force: true);
    }
  }, createHttpClient: _RealHttpOverrides().createHttpClient);
}

Future<Map<String, Object?>> _postJson(
  Uri uri,
  Map<String, Object?> payload,
) async {
  return HttpOverrides.runZoned(() async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      return Map<String, Object?>.from(
        jsonDecode(body) as Map<Object?, Object?>,
      );
    } finally {
      client.close(force: true);
    }
  }, createHttpClient: _RealHttpOverrides().createHttpClient);
}

Future<List<int>> _readBytes(Uri uri) async {
  final response = await _readBinaryResponse(uri);
  return response.bytes;
}

Future<_HttpBinaryResponse> _readBinaryResponse(Uri uri) async {
  return HttpOverrides.runZoned(() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(<int>[], (bytes, chunk) {
        final combined = List<int>.of(bytes);
        combined.addAll(chunk);
        return combined;
      });
      return _HttpBinaryResponse(statusCode: response.statusCode, bytes: bytes);
    } finally {
      client.close(force: true);
    }
  }, createHttpClient: _RealHttpOverrides().createHttpClient);
}

final class _HttpBinaryResponse {
  const _HttpBinaryResponse({required this.statusCode, required this.bytes});

  final int statusCode;
  final List<int> bytes;
}

final class _RealHttpOverrides extends HttpOverrides {}

final class _FakeCockpitNativeRecording extends CockpitNativeRecording {
  _FakeCockpitNativeRecording({
    Directory? tempDirectory,
    List<int> recordingBytes = const <int>[1, 2, 3, 4],
  }) : _tempDirectory = tempDirectory,
       _recordingBytes = List<int>.unmodifiable(recordingBytes);

  final Directory? _tempDirectory;
  final List<int> _recordingBytes;

  @override
  Future<CockpitRecordingCapabilities> queryCapabilities() async {
    return CockpitRecordingCapabilities(
      supportsNativeRecording: true,
      preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
    );
  }

  @override
  Future<CockpitRecordingSession> startRecording({
    required CockpitRecordingRequest request,
  }) async {
    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording({
    required CockpitRecordingSession session,
  }) async {
    final relativePath = cockpitRecordingRelativePathFor(session.request);
    final sourceFilePath = _writeRecordingFile(relativePath);
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: session.request.purpose,
      recordingKind: CockpitRecordingKind.nativeScreen,
      artifact: CockpitArtifactRef(
        role: 'recording',
        relativePath: relativePath,
      ),
      durationMs: 1800,
      sourceFilePath: sourceFilePath,
    );
  }

  String? _writeRecordingFile(String relativePath) {
    final tempDirectory = _tempDirectory;
    if (tempDirectory == null) {
      return null;
    }

    final file = File('${tempDirectory.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_recordingBytes);
    return file.path;
  }
}

final class _ThrowingCockpitNativeRecording extends CockpitNativeRecording {
  @override
  Future<CockpitRecordingCapabilities> queryCapabilities() {
    throw UnsupportedError('Unsupported operation: _Namespace');
  }
}

final class _RemoteTestApp extends StatelessWidget {
  _RemoteTestApp({
    required this.controller,
    required this.registry,
    required this.configuration,
  }) {
    FlutterCockpit.initialize(
      configuration.copyWith(registry: configuration.registry ?? registry),
    );
  }

  final CockpitSessionController controller;
  final CockpitTargetRegistry registry;
  final FlutterCockpitConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    return FlutterCockpitRoot(
      child: MaterialApp(
        navigatorObservers: <NavigatorObserver>[
          FlutterCockpit.navigatorObserver,
        ],
        home: _RemoteHomePage(controller: controller, registry: registry),
      ),
    );
  }
}

final class _RemoteNativeDiscoveryTestApp extends StatelessWidget {
  _RemoteNativeDiscoveryTestApp({
    required this.controller,
    required this.registry,
    required this.configuration,
  }) {
    FlutterCockpit.initialize(
      configuration.copyWith(registry: configuration.registry ?? registry),
    );
  }

  final CockpitSessionController controller;
  final CockpitTargetRegistry registry;
  final FlutterCockpitConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    return FlutterCockpitRoot(
      child: MaterialApp(
        navigatorObservers: <NavigatorObserver>[
          FlutterCockpit.navigatorObserver,
        ],
        home: _RemoteNativeHomePage(controller: controller, registry: registry),
      ),
    );
  }
}

final class _RemoteHomePage extends StatelessWidget {
  const _RemoteHomePage({required this.controller, required this.registry});

  final CockpitSessionController controller;
  final CockpitTargetRegistry registry;

  void _openForm(BuildContext context) {
    controller.recordStep(
      actionType: 'open_form',
      actionArgs: const <String, Object?>{'target': 'open_form_button'},
      observation: CockpitObservation(
        routeName: '/home',
        interactiveElements: <String>['open_form_button'],
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/form'),
        builder: (_) =>
            _RemoteFormPage(controller: controller, registry: registry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CockpitTargetNode(
          registrationId: 'home.open_form_button',
          cockpitId: 'open_form_button',
          text: 'Open form',
          typeName: 'ElevatedButton',
          supportedCommands: const <CockpitCommandType>{CockpitCommandType.tap},
          onTap: () => _openForm(context),
          child: ElevatedButton(
            onPressed: () => _openForm(context),
            child: const Text('Open form'),
          ),
        ),
      ),
    );
  }
}

final class _RemoteNativeHomePage extends StatelessWidget {
  const _RemoteNativeHomePage({
    required this.controller,
    required this.registry,
  });

  final CockpitSessionController controller;
  final CockpitTargetRegistry registry;

  void _openForm(BuildContext context) {
    controller.recordStep(
      actionType: 'native_open_form',
      actionArgs: const <String, Object?>{'target': 'native-open-form-button'},
      observation: CockpitObservation(
        routeName: '/home',
        interactiveElements: <String>['native-open-form-button'],
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/form'),
        builder: (_) =>
            _RemoteFormPage(controller: controller, registry: registry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'Open form',
          hint: 'Navigates to the remote form screen',
          child: Tooltip(
            message: 'Open the remote form',
            child: ElevatedButton(
              key: const ValueKey<String>('native-open-form-button'),
              onPressed: () => _openForm(context),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RemoteFormPage extends StatelessWidget {
  const _RemoteFormPage({required this.controller, required this.registry});

  final CockpitSessionController controller;
  final CockpitTargetRegistry registry;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Form page')));
  }
}
