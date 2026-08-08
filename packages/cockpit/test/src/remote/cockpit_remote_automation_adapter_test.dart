import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  test(
    'remote automation adapter exposes capabilities and executes commands',
    () async {
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
                  sessionId: 'adapter-demo',
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
                    supportedCommands: <CockpitCommandType>[
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
                    durationMs: 21,
                    snapshot: CockpitSnapshot(routeName: '/form').toJson(),
                  ),
                  artifactPayloads: const <CockpitRemoteArtifactPayload>[
                    CockpitRemoteArtifactPayload(
                      artifact: CockpitArtifactRef(
                        role: 'screenshot',
                        relativePath: 'screenshots/form_after_action.png',
                      ),
                      bytes: <int>[2, 4, 6],
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
      final adapter = CockpitRemoteAutomationAdapter(
        client: client,
        workspaceRoot: Directory.current.path,
      );

      final capabilities = await adapter.describeCapabilities();
      final execution = await adapter.execute(
        CockpitCommand(
          commandId: 'tap-open',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(cockpitId: 'open_form_button'),
        ),
      );

      expect(capabilities.transportType, 'remoteHttp');
      expect(execution.result.success, isTrue);
      expect(execution.result.snapshot?['routeName'], '/form');
      expect(
        execution.artifactPayloads['screenshots/form_after_action.png'],
        <int>[2, 4, 6],
      );
    },
  );

  test('remote automation adapter aborts its active HTTP command', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    addTearDown(() async {
      if (!releaseResponse.isCompleted) {
        releaseResponse.complete();
      }
      await server.close(force: true);
    });

    server.listen((request) async {
      requestStarted.complete();
      await releaseResponse.future;
      try {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            CockpitCommandResult(
              success: true,
              commandId: 'stalled-command',
              commandType: CockpitCommandType.waitFor,
              durationMs: 1,
            ).toJson(),
          ),
        );
        await request.response.close();
      } on Object {
        // The client intentionally closes the request during cancellation.
      }
    });

    final adapter = CockpitRemoteAutomationAdapter(
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      ),
      workspaceRoot: Directory.current.path,
    );
    final execution = adapter.execute(
      CockpitCommand(
        commandId: 'stalled-command',
        commandType: CockpitCommandType.waitFor,
        locator: const CockpitLocator(route: '/never'),
        timeoutMs: 500,
      ),
    );
    await requestStarted.future;

    final cancellationExpectation = expectLater(
      execution,
      throwsA(isA<CockpitRemoteCommandCancelledException>()),
    );
    await adapter.abortActiveOperation();
    await cancellationExpectation;
  });

  test('remote adapter compares Flutter-view screenshots locally', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'cockpit-remote-visual-',
    );
    final baseline = File('${workspace.path}/baselines/settings.png');
    await baseline.parent.create(recursive: true);
    final image = img.Image(width: 2, height: 2);
    img.fill(image, color: img.ColorRgb8(20, 80, 120));
    final png = img.encodePng(image);
    await baseline.writeAsBytes(png);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await workspace.delete(recursive: true);
    });

    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/health') {
        request.response.write(
          jsonEncode(
            CockpitRemoteSessionStatus(
              sessionId: 'visual-demo',
              platform: 'macos',
              transportType: 'remoteHttp',
              currentRouteName: '/settings',
              capabilities: CockpitCapabilities(
                platform: 'macos',
                transportType: 'remoteHttp',
                supportsInAppControl: true,
                supportsFlutterViewCapture: true,
                supportsNativeScreenCapture: false,
                supportsHostAutomation: false,
                supportedCommands: <CockpitCommandType>[
                  CockpitCommandType.captureScreenshot,
                ],
              ),
              recordingCapabilities: CockpitRecordingCapabilities(
                supportsNativeRecording: false,
              ),
              snapshot: CockpitSnapshot(routeName: '/settings'),
            ).toJson(),
          ),
        );
      } else if (request.method == 'POST' &&
          request.uri.path == '/commands/execute') {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        final command = CockpitCommand.fromJson(
          Map<String, Object?>.from(body as Map<Object?, Object?>),
        );
        expect(command.commandType, CockpitCommandType.captureScreenshot);
        expect(
          command.screenshotRequest?.profile,
          CockpitCaptureProfile.flutterPreferred,
        );
        request.response.write(
          jsonEncode(
            CockpitRemoteCommandResponse(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 3,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/settings.png',
                  ),
                ],
                requestedCaptureProfile: CockpitCaptureProfile.flutterPreferred,
                resolvedCaptureKind: CockpitCaptureKind.flutterView,
              ),
              artifactPayloads: <CockpitRemoteArtifactPayload>[
                CockpitRemoteArtifactPayload(
                  artifact: const CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/settings.png',
                  ),
                  bytes: png,
                ),
              ],
            ).toJson(),
          ),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final adapter = CockpitRemoteAutomationAdapter(
      client: CockpitRemoteSessionClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      ),
      workspaceRoot: workspace.path,
    );
    final capabilities = await adapter.describeCapabilities();
    final execution = await adapter.execute(
      CockpitCommand(
        commandId: 'settings-visual',
        commandType: CockpitCommandType.assertScreenshot,
        parameters: const <String, Object?>{
          'baseline': 'baselines/settings.png',
          'pixelTolerance': 0.1,
          'maxDifferingPixelRatio': 0.01,
          'artifactName': 'settings',
        },
      ),
    );

    expect(
      capabilities.supportedCommands,
      contains(CockpitCommandType.assertScreenshot),
    );
    expect(execution.result.success, isTrue);
    expect(execution.result.snapshot?['adapter'], 'flutterViewVisual');
    expect(
      execution.result.artifacts.map((artifact) => artifact.role),
      containsAll(<String>[
        'screenshotActual',
        'screenshotBaseline',
        'screenshotDiff',
      ]),
    );
  });
}
