import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/application/cockpit_execute_remote_command_service.dart';
import 'package:cockpit/src/application/cockpit_interactive_result_profile.dart';
import 'package:cockpit/src/application/cockpit_interactive_snapshot_store.dart';
import 'package:cockpit/src/application/cockpit_session_reference_resolver.dart';
import 'package:cockpit/src/remote/cockpit_android_port_forwarder.dart';
import 'package:cockpit/src/remote/cockpit_remote_command_timeout_budget.dart';
import 'package:cockpit/src/remote/cockpit_remote_session_client.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CockpitExecuteRemoteCommandService', () {
    test(
      'cancellation ends an in-flight command without waiting for it',
      () async {
        final cancellation = Completer<void>();
        final command = Completer<CockpitCommandExecution>();
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, _) => command.future,
        );
        final execution = service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'cancelled-command',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.minimal(),
            cancellation: cancellation.future,
          ),
        );

        cancellation.complete();
        await expectLater(
          execution,
          throwsA(isA<CockpitRemoteCommandCancelledException>()),
        );
        expect(command.isCompleted, isFalse);
      },
    );

    test('executes a command with compact results by default', () async {
      final handle = _sessionHandle();
      Uri? capturedBaseUri;
      CockpitCommand? capturedCommand;
      var snapshotReads = 0;
      final service = CockpitExecuteRemoteCommandService(
        executeCommand: (baseUri, command) async {
          capturedBaseUri = baseUri;
          capturedCommand = command;
          return CockpitCommandExecution(
            result: CockpitCommandResult(
              success: true,
              commandId: command.commandId,
              commandType: command.commandType,
              durationMs: 120,
            ),
          );
        },
        readSnapshot: (_, _) async {
          snapshotReads += 1;
          throw UnimplementedError('compact results should not read snapshots');
        },
      );

      final result = await service.execute(
        CockpitExecuteRemoteCommandRequest(
          sessionHandle: handle,
          command: CockpitCommand(
            commandId: 'tap-1',
            commandType: CockpitCommandType.tap,
          ),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
        ),
      );

      expect(capturedBaseUri, handle.baseUri);
      expect(capturedCommand?.commandId, 'tap-1');
      expect(snapshotReads, 0);
      expect(result.command.commandId, 'tap-1');
      expect(result.command.success, isTrue);
      expect(result.uiSummary, isNull);
      expect(result.snapshot, isNull);
      expect(result.diagnostics, isNull);
      expect(result.artifacts, isEmpty);
      expect(result.snapshotRef, isNull);
      expect(result.selectedPlane, CockpitPlaneKind.flutterSemanticPlane);
      expect(result.fallbackTrail, <CockpitPlaneKind>[
        CockpitPlaneKind.nativeUiPlane,
        CockpitPlaneKind.deviceSystemPlane,
      ]);
      expect(result.recommendedNextStep, 'readPostActionState');
      expect(result.toJson()['selectedPlane'], 'flutterSemanticPlane');
    });

    test('injects a default timeout when the command omits one', () async {
      CockpitCommand? capturedCommand;
      final service = CockpitExecuteRemoteCommandService(
        executeCommand: (_, command) async {
          capturedCommand = command;
          return CockpitCommandExecution(
            result: CockpitCommandResult(
              success: true,
              commandId: command.commandId,
              commandType: command.commandType,
              durationMs: 50,
            ),
          );
        },
      );

      await service.execute(
        CockpitExecuteRemoteCommandRequest(
          sessionHandle: _sessionHandle(),
          command: CockpitCommand(
            commandId: 'tap-timeout-default',
            commandType: CockpitCommandType.tap,
          ),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
          defaultCommandTimeout: const Duration(milliseconds: 4800),
        ),
      );

      expect(capturedCommand?.timeoutMs, 4800);
    });

    test(
      'defaults AI key-step captures to screenshots while reading structured UI separately',
      () async {
        CockpitCommand? capturedCommand;
        var snapshotReads = 0;
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            capturedCommand = command;
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/tap-save.png',
                  ),
                ],
              ),
              artifactPayloads: const <String, List<int>>{
                'screenshots/tap-save.png': <int>[137, 80, 78, 71],
              },
            );
          },
          readSnapshot: (_, _) async {
            snapshotReads += 1;
            return CockpitRemoteSnapshotResponse(
              snapshot: _richSnapshot(routeName: '/saved', label: 'Saved'),
            );
          },
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-save',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.standard(),
          ),
        );

        expect(
          capturedCommand?.capturePolicy,
          CockpitCapturePolicy.afterAction,
        );
        expect(
          capturedCommand?.captureFailurePolicy,
          CockpitCaptureFailurePolicy.degradeCommand,
        );
        expect(capturedCommand?.screenshotRequest?.includeSnapshot, isFalse);
        expect(capturedCommand?.screenshotRequest?.snapshotOptions, isNull);
        expect(
          result.artifacts.single.relativePath,
          'screenshots/tap-save.png',
        );
        expect(snapshotReads, 1);
        expect(result.uiSummary?.routeName, '/saved');
        expect(result.snapshotRef, isNotEmpty);
      },
    );

    test(
      'refreshes android host forwarding before executing commands',
      () async {
        Uri? capturedBaseUri;
        final service = CockpitExecuteRemoteCommandService(
          sessionReferenceResolver: CockpitSessionReferenceResolver(
            portForwarder: CockpitAndroidPortForwarder(
              processRunner: (_, _) async => ProcessResult(
                0,
                0,
                'emulator-5554 tcp:61331 tcp:47331\n',
                '',
              ),
              hostPortAllocator: () async => 61331,
              hostPortAvailabilityChecker: (_) async => false,
            ),
          ),
          executeCommand: (baseUri, command) async {
            capturedBaseUri = baseUri;
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 120,
              ),
            );
          },
        );

        await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _androidSessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-android-forwarded',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.minimal(),
          ),
        );

        expect(capturedBaseUri.toString(), 'http://127.0.0.1:61331');
      },
    );

    test('uses a longer inferred timeout for long scroll commands', () async {
      CockpitCommand? capturedCommand;
      final service = CockpitExecuteRemoteCommandService(
        executeCommand: (_, command) async {
          capturedCommand = command;
          return CockpitCommandExecution(
            result: CockpitCommandResult(
              success: true,
              commandId: command.commandId,
              commandType: command.commandType,
              durationMs: 50,
            ),
          );
        },
      );

      await service.execute(
        CockpitExecuteRemoteCommandRequest(
          sessionHandle: _sessionHandle(),
          command: CockpitCommand(
            commandId: 'scroll-timeout-default',
            commandType: CockpitCommandType.scrollUntilVisible,
            locator: const CockpitLocator(text: 'Emit debug log'),
            parameters: const <String, Object?>{
              'maxScrolls': 10,
              'durationPerStepMs': 220,
              'revealAlignment': 'center',
            },
          ),
          resultProfile: const CockpitInteractiveResultProfile.minimal(),
          defaultCommandTimeout: const Duration(seconds: 4),
        ),
      );

      expect(capturedCommand?.timeoutMs, greaterThanOrEqualTo(8000));
    });

    test(
      'extends inferred timeout when scroll probing splits large steps',
      () async {
        CockpitCommand? capturedCommand;
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            capturedCommand = command;
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
              ),
            );
          },
        );

        await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'scroll-probe-timeout-default',
              commandType: CockpitCommandType.scrollUntilVisible,
              locator: const CockpitLocator(key: 'settings-sync-check-button'),
              parameters: const <String, Object?>{
                'maxScrolls': 6,
                'viewportFraction': 0.8,
              },
            ),
            resultProfile: const CockpitInteractiveResultProfile.minimal(),
            defaultCommandTimeout: const Duration(seconds: 4),
          ),
        );

        expect(capturedCommand?.timeoutMs, greaterThanOrEqualTo(12000));
      },
    );

    test(
      'budgets complex AI-evidence scrolling beyond the default request timeout',
      () async {
        CockpitCommand? capturedCommand;
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            capturedCommand = command;
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
              ),
            );
          },
        );

        await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'verify-scroll-run-queued-sync',
              commandType: CockpitCommandType.scrollUntilVisible,
              locator: const CockpitLocator(
                text: 'Run queued sync',
                route: '/settings',
                ancestor: CockpitLocator(route: '/settings'),
              ),
              parameters: const <String, Object?>{
                'maxScrolls': 10,
                'viewportFraction': 0.82,
                'continuous': true,
                'durationPerStepMs': 220,
                'revealAlignment': 'center',
                'scrollableLocator': <String, Object?>{
                  'type': 'ListView',
                  'path': 'scaffold.body/list_view.slivers/0',
                  'route': '/settings',
                },
              },
            ),
            resultProfile: const CockpitInteractiveResultProfile.minimal(),
          ),
        );

        expect(
          capturedCommand?.capturePolicy,
          CockpitCapturePolicy.afterAction,
        );
        expect(capturedCommand?.timeoutMs, greaterThan(30000));
        expect(
          cockpitRemoteCommandTransportTimeoutForCommand(capturedCommand!),
          greaterThan(const Duration(seconds: 45)),
        );
      },
    );

    test(
      'remote command transport timeout leaves headroom for AI evidence',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });
        server.listen((request) async {
          if (request.method == 'POST' &&
              request.uri.path == '/commands/execute') {
            await Future<void>.delayed(const Duration(milliseconds: 6500));
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              '{"result":{"success":true,"commandId":"slow-tap",'
              '"commandType":"tap","durationMs":200}}',
            );
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final service = CockpitExecuteRemoteCommandService();
        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
            command: CockpitCommand(
              commandId: 'slow-tap',
              commandType: CockpitCommandType.tap,
              timeoutMs: 100,
            ),
            resultProfile: const CockpitInteractiveResultProfile.minimal(),
          ),
        );

        expect(result.command.success, isTrue);
      },
    );

    test('remote command transport budget accounts for evidence recovery', () {
      final plain = cockpitRemoteCommandTransportTimeoutForCommand(
        CockpitCommand(
          commandId: 'plain',
          commandType: CockpitCommandType.assertText,
          timeoutMs: 100,
        ),
      );
      final evidence = cockpitRemoteCommandTransportTimeoutForCommand(
        CockpitCommand(
          commandId: 'evidence',
          commandType: CockpitCommandType.tap,
          capturePolicy: CockpitCapturePolicy.afterAction,
          timeoutMs: 30000,
        ),
      );

      expect(plain, const Duration(seconds: 15));
      expect(evidence, const Duration(seconds: 45));
    });

    test(
      'returns summary, diagnostics, artifact metadata, and snapshot refs',
      () async {
        final handle = _sessionHandle();
        CockpitSnapshotOptions? capturedOptions;
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 240,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'step_screenshot',
                    relativePath: 'artifacts/after-tap.png',
                  ),
                ],
              ),
              artifactPayloads: const <String, List<int>>{
                'artifacts/after-tap.png': <int>[1, 2, 3, 4],
              },
            );
          },
          readSnapshot: (_, options) async {
            capturedOptions = options;
            return CockpitRemoteSnapshotResponse(
              snapshot: _richSnapshot(routeName: '/details'),
            );
          },
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: handle,
            command: CockpitCommand(
              commandId: 'tap-2',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
          ),
        );

        expect(capturedOptions?.profile, CockpitSnapshotProfile.investigate);
        expect(result.uiSummary?.routeName, '/details');
        expect(result.snapshot, isNull);
        expect(result.diagnostics?['network'], isNotNull);
        expect(result.artifacts.single.byteLength, 4);
        expect(result.snapshotRef, isNotEmpty);
        expect(
          result.effectiveSnapshotOptions?.profile,
          CockpitSnapshotProfile.investigate,
        );
      },
    );

    test('returns a full snapshot for forensic profiles', () async {
      final handle = _sessionHandle();
      final service = CockpitExecuteRemoteCommandService(
        executeCommand: (_, command) async {
          return CockpitCommandExecution(
            result: CockpitCommandResult(
              success: true,
              commandId: command.commandId,
              commandType: command.commandType,
              durationMs: 80,
            ),
          );
        },
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: _richSnapshot(routeName: '/forensic'),
        ),
      );

      final result = await service.execute(
        CockpitExecuteRemoteCommandRequest(
          sessionHandle: handle,
          command: CockpitCommand(
            commandId: 'tap-3',
            commandType: CockpitCommandType.tap,
          ),
          resultProfile: const CockpitInteractiveResultProfile.evidence(),
        ),
      );

      expect(result.snapshot?.routeName, '/forensic');
      expect(result.uiSummary, isNull);
      expect(result.diagnostics?['runtime'], isNotNull);
    });

    test(
      'retries transient empty post-action snapshots before summarizing',
      () async {
        var snapshotReads = 0;
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 80,
              ),
            );
          },
          readSnapshot: (_, _) async {
            snapshotReads += 1;
            return CockpitRemoteSnapshotResponse(
              snapshot: snapshotReads == 1
                  ? _emptyRouteSnapshot('/inbox')
                  : _richSnapshot(routeName: '/inbox', label: 'Create task'),
            );
          },
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-after-route-change',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.standard(),
          ),
        );

        expect(snapshotReads, 2);
        expect(result.uiSummary?.routeName, '/inbox');
        expect(result.uiSummary?.visibleTargetCount, 1);
        expect(result.uiSummary?.textPreviews, contains('Create task'));
      },
    );

    test(
      'returns refs without metadata for standard artifact profiles',
      () async {
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'step_screenshot',
                    relativePath: 'artifacts/standard.png',
                  ),
                ],
              ),
              artifactPayloads: <String, List<int>>{
                'artifacts/standard.png': <int>[1, 2, 3],
              },
              artifactSourcePaths: <String, String>{
                'artifacts/standard.png': '/tmp/standard.png',
              },
            );
          },
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: _richSnapshot(routeName: '/standard'),
          ),
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-standard',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.standard(),
          ),
        );

        expect(result.artifacts.single.role, 'step_screenshot');
        expect(result.artifacts.single.relativePath, 'artifacts/standard.png');
        expect(result.artifacts.single.byteLength, isNull);
        expect(result.artifacts.single.sourcePath, isNull);
      },
    );

    test(
      'persists metadata-profile artifact payloads so evidence can be exported',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'cockpit_command_evidence_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final service = CockpitExecuteRemoteCommandService(
          artifactTempFileFactory: (relativePath) async {
            return File('${tempDir.path}/$relativePath');
          },
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/after-tap.png',
                  ),
                ],
              ),
              artifactPayloads: const <String, List<int>>{
                'screenshots/after-tap.png': <int>[137, 80, 78, 71],
              },
            );
          },
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: _richSnapshot(routeName: '/standard'),
          ),
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-persisted-evidence',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
          ),
        );

        final sourcePath = result.artifacts.single.sourcePath;
        expect(sourcePath, isNotNull);
        expect(File(sourcePath!).readAsBytesSync(), <int>[137, 80, 78, 71]);
      },
    );

    test('uses the configured artifact factory for remote downloads', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_remote_command_factory_',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      server.listen((request) async {
        if (request.method == 'POST' &&
            request.uri.path == '/commands/execute') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              CockpitRemoteCommandResponse(
                result: CockpitCommandResult(
                  success: true,
                  commandId: 'capture-remote',
                  commandType: CockpitCommandType.captureScreenshot,
                  durationMs: 10,
                  artifacts: <CockpitArtifactRef>[
                    CockpitArtifactRef(
                      role: 'screenshot',
                      relativePath: 'screenshots/remote.png',
                    ),
                  ],
                ),
                artifactDownloads: const <CockpitRemoteArtifactDownload>[
                  CockpitRemoteArtifactDownload(
                    artifact: CockpitArtifactRef(
                      role: 'screenshot',
                      relativePath: 'screenshots/remote.png',
                    ),
                    downloadPath: '/artifacts/remote.png',
                  ),
                ],
              ).toJson(),
            ),
          );
          await request.response.close();
          return;
        }
        if (request.method == 'GET' &&
            request.uri.path == '/artifacts/remote.png') {
          request.response.add(const <int>[137, 80, 78, 71]);
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      var factoryCalls = 0;
      final service = CockpitExecuteRemoteCommandService(
        artifactTempFileFactory: (basename) async {
          factoryCalls += 1;
          return File(p.join(tempDir.path, basename));
        },
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: _richSnapshot(routeName: '/remote'),
        ),
      );

      final result = await service.execute(
        CockpitExecuteRemoteCommandRequest(
          baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
          command: CockpitCommand(
            commandId: 'capture-remote',
            commandType: CockpitCommandType.captureScreenshot,
          ),
          resultProfile: const CockpitInteractiveResultProfile.inspect(),
        ),
      );

      expect(factoryCalls, 1);
      expect(result.artifacts.single.sourcePath, isNotNull);
      expect(
        await File(result.artifacts.single.sourcePath!).readAsBytes(),
        const <int>[137, 80, 78, 71],
      );
    });

    test(
      'rejects metadata-profile screenshot refs without downloadable evidence',
      () async {
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/missing-evidence.png',
                  ),
                ],
              ),
            );
          },
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: _richSnapshot(routeName: '/standard'),
          ),
        );

        await expectLater(
          () => service.execute(
            CockpitExecuteRemoteCommandRequest(
              sessionHandle: _sessionHandle(),
              command: CockpitCommand(
                commandId: 'tap-missing-evidence',
                commandType: CockpitCommandType.tap,
              ),
              resultProfile: const CockpitInteractiveResultProfile.inspect(),
            ),
          ),
          throwsA(
            isA<CockpitApplicationServiceException>()
                .having(
                  (error) => error.code,
                  'code',
                  'requiredArtifactEvidenceMissing',
                )
                .having(
                  (error) => error.details['artifactPath'],
                  'artifactPath',
                  'screenshots/missing-evidence.png',
                ),
          ),
        );
      },
    );

    test(
      'keeps downloaded command artifacts as file metadata without inline payloads',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'cockpit_downloaded_evidence_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final sourceFile = File('${tempDir.path}/after-tap.png')
          ..writeAsBytesSync(<int>[137, 80, 78, 71]);
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 50,
                artifacts: const <CockpitArtifactRef>[
                  CockpitArtifactRef(
                    role: 'screenshot',
                    relativePath: 'screenshots/after-tap.png',
                  ),
                ],
              ),
              artifactSourcePaths: <String, String>{
                'screenshots/after-tap.png': sourceFile.path,
              },
            );
          },
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: _richSnapshot(routeName: '/standard'),
          ),
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-downloaded-evidence',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
          ),
        );

        expect(result.artifacts.single.byteLength, 4);
        expect(result.artifacts.single.sourcePath, sourceFile.path);
      },
    );

    test(
      'filters failures-only diagnostics down to failing sections',
      () async {
        final service = CockpitExecuteRemoteCommandService(
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 75,
              ),
            );
          },
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: _richSnapshot(routeName: '/failures-only'),
          ),
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-inspect',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
          ),
        );

        expect(result.diagnostics?['level'], 'failures_only');
        expect(result.diagnostics?['network'], isNotNull);
        expect(result.diagnostics?['runtime'], isNotNull);
        expect(result.diagnostics?.containsKey('rebuild'), isFalse);
        expect(result.diagnostics?.containsKey('accessibility'), isFalse);
      },
    );

    test('adds command context to structured remote command errors', () async {
      final service = CockpitExecuteRemoteCommandService(
        executeCommand: (_, _) async {
          throw const CockpitApplicationServiceException(
            code: 'remoteUnavailable',
            message: 'Session is offline.',
            details: <String, Object?>{'path': '/commands/execute'},
          );
        },
      );

      expect(
        () => service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-4',
              commandType: CockpitCommandType.tap,
            ),
          ),
        ),
        throwsA(
          isA<CockpitApplicationServiceException>()
              .having((error) => error.code, 'code', 'remoteUnavailable')
              .having(
                (error) => error.details['commandId'],
                'commandId',
                'tap-4',
              )
              .having(
                (error) => error.details['commandType'],
                'commandType',
                'tap',
              )
              .having(
                (error) => error.details['path'],
                'path',
                '/commands/execute',
              ),
        ),
      );
    });

    test('fails when comparing against a missing snapshot ref', () async {
      final service = CockpitExecuteRemoteCommandService(
        executeCommand: (_, command) async {
          return CockpitCommandExecution(
            result: CockpitCommandResult(
              success: true,
              commandId: command.commandId,
              commandType: command.commandType,
              durationMs: 120,
            ),
          );
        },
        readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
          snapshot: _richSnapshot(routeName: '/compare'),
        ),
      );

      expect(
        () => service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-5',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
            compareAgainstSnapshotRef: 'missing-snapshot-ref',
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

    test(
      'includes deltas when comparing against a previous snapshot ref',
      () async {
        final store = CockpitInteractiveSnapshotStore();
        final baselineRef = store.put(
          sessionKey: _sessionHandle().baseUri.toString(),
          snapshot: _richSnapshot(routeName: '/before', label: 'Before'),
        );
        final service = CockpitExecuteRemoteCommandService(
          snapshotStore: store,
          executeCommand: (_, command) async {
            return CockpitCommandExecution(
              result: CockpitCommandResult(
                success: true,
                commandId: command.commandId,
                commandType: command.commandType,
                durationMs: 95,
              ),
            );
          },
          readSnapshot: (_, _) async => CockpitRemoteSnapshotResponse(
            snapshot: _richSnapshot(routeName: '/after', label: 'After'),
          ),
        );

        final result = await service.execute(
          CockpitExecuteRemoteCommandRequest(
            sessionHandle: _sessionHandle(),
            command: CockpitCommand(
              commandId: 'tap-6',
              commandType: CockpitCommandType.tap,
            ),
            resultProfile: const CockpitInteractiveResultProfile.inspect(),
            compareAgainstSnapshotRef: baselineRef,
          ),
        );

        expect(result.delta?.routeChanged, isTrue);
        expect(result.delta?.fromRouteName, '/before');
        expect(result.delta?.toRouteName, '/after');
        expect(result.delta?.addedTextPreviews, contains('After'));
      },
    );
  });
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

CockpitRemoteSessionHandle _androidSessionHandle() {
  return CockpitRemoteSessionHandle(
    platform: 'android',
    deviceId: 'emulator-5554',
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

CockpitSnapshot _emptyRouteSnapshot(String routeName) {
  return CockpitSnapshot(
    routeName: routeName,
    diagnosticLevel: CockpitSnapshotProfile.baseline,
    visibleTargets: const <CockpitSnapshotTarget>[],
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
  );
}

CockpitSnapshot _richSnapshot({
  required String routeName,
  String label = 'Inbox',
}) {
  return CockpitSnapshot(
    routeName: routeName,
    diagnosticLevel: CockpitSnapshotProfile.investigate,
    visibleTargets: <CockpitSnapshotTarget>[
      CockpitSnapshotTarget(
        registrationId: 'target-1',
        routeName: routeName,
        text: label,
        cockpitId: 'primary-button',
      ),
    ],
    summary: const CockpitSnapshotSummary(
      visibleTargetCount: 1,
      targetsWithCockpitIdCount: 1,
      targetsWithTextCount: 1,
      styleDetailsIncluded: true,
      diagnosticPropertiesIncluded: true,
      ancestorSummariesIncluded: false,
      rebuildSummaryIncluded: true,
      accessibilitySummaryIncluded: true,
    ),
    network: const CockpitNetworkSnapshot(
      totalEntryCount: 2,
      failureCount: 1,
      entries: <CockpitNetworkEntry>[],
      capturedEntryCount: 2,
      inFlightCount: 0,
      truncated: false,
    ),
    runtime: const CockpitRuntimeSnapshot(
      totalEntryCount: 1,
      errorCount: 1,
      warningCount: 0,
      entries: <CockpitRuntimeEvent>[],
      capturedEntryCount: 1,
      truncated: false,
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
        CockpitAccessibilityEntry(nodeId: 1, label: 'Inbox'),
      ],
      truncated: false,
    ),
  );
}
