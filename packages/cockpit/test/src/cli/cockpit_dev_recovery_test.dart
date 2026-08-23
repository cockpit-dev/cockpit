import 'dart:io';

import 'package:lon/lon.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_session_handles.dart';
import 'package:cockpit/src/cli/cockpit_dev_runtime.dart';
import 'package:cockpit/src/cli/cockpit_dev_start.dart';
import 'package:cockpit/src/development/cockpit_checkout_identity.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late CockpitCliSessionHandleStore store;
  late CockpitCliRuntime runtime;
  late CockpitCliSessionHandle session;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'cockpit-dev-recovery-',
    );
    store = CockpitCliSessionHandleStore.file(
      path: p.join(temporaryDirectory.path, 'sessions.json'),
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    );
    stdout = StringBuffer();
    stderr = StringBuffer();
    runtime = CockpitCliRuntime(
      workingDirectory: temporaryDirectory.path,
      stdoutSink: stdout,
      stderrSink: stderr,
      sessionHandleStoreProvider: () async => store,
      checkoutIdentityResolver: CockpitCheckoutIdentityResolver(
        processRunner: (_, _, {workingDirectory, environment}) async =>
            ProcessResult(1, 1, '', ''),
      ),
    );
    final checkout = await runtime.checkoutIdentity();
    session = await runtime.bindDevelopmentSession(
      checkout: checkout,
      projectPath: checkout.canonicalRoot,
      workspaceId: 'workspace-1',
      sessionId: 'session-old',
      targetId: 'target-1',
      appId: 'app-old',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('path output preserves the operation failure', () async {
    runtime.configureOutput(
      command: 'dev.screenshot',
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.path),
    );
    final dev = CockpitDevRuntime(runtime);

    final exitCode = await dev.writeEnvelope(
      action: 'screenshot',
      session: session,
      ok: false,
      state: const <String, Object?>{},
      changed: 'none',
      errors: const <Object?>[
        <String, Object?>{
          'primary': <String, Object?>{
            'code': 'captureFailed',
            'message': 'adb screencap failed.',
          },
        },
      ],
    );

    expect(exitCode, cockpitDataExitCode);
    expect(stdout, isEmpty);
    expect(stderr.toString(), contains('captureFailed'));
    expect(stderr.toString(), contains('adb screencap failed.'));
    expect(stderr.toString(), isNot(contains('--format path requires')));
  });

  test('diagnostic network reads remain readable when requests failed', () {
    final dev = CockpitDevRuntime(runtime);
    final result = _result(
      'network.read',
      output: const <String, Object?>{
        'available': true,
        'summary': <String, Object?>{'failureCount': 1},
        'entries': <Object?>[
          <String, Object?>{'requestId': '10', 'statusCode': 503},
        ],
      },
    );

    expect(dev.diagnosticReadSucceeded(result), isTrue);
    expect(dev.operationSucceeded(result), isFalse);
  });

  test(
    'rebinds the latest same-target bridge while retaining its handle',
    () async {
      final calls = <String>[];
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, _) async {
          calls.add(kind);
          if (kind == 'session.development.get' && calls.length == 1) {
            return _result(kind, output: const <String, Object?>{'ok': false});
          }
          return switch (kind) {
            'target.list' => _result(
              kind,
              output: const <String, Object?>{
                'targets': <Object?>[
                  <String, Object?>{
                    'targetId': 'target-1',
                    'sessionId': 'session-new',
                  },
                ],
              },
            ),
            'app.list' => _result(
              kind,
              output: const <String, Object?>{
                'apps': <Object?>[
                  <String, Object?>{'targetId': 'target-1', 'appId': 'app-new'},
                ],
              },
            ),
            'session.development.get' => _result(
              kind,
              output: const <String, Object?>{
                'sessionId': 'session-new',
                'targetId': 'target-1',
                'appId': 'app-new',
                'status': <String, Object?>{
                  'state': 'ready',
                  'appReachable': true,
                  'remoteSessionReachable': true,
                },
              },
            ),
            _ => throw StateError('Unexpected operation $kind'),
          };
        },
      );

      final resolved = await dev.reconcile(session, allowRelaunch: false);

      expect(resolved.ready, isTrue);
      expect(resolved.changed, 'reconnected');
      expect(resolved.session.handleId, session.handleId);
      expect(resolved.session.sessionId, 'session-new');
      expect(resolved.session.appId, 'app-new');
      expect(calls.where((kind) => kind == 'target.launch'), isEmpty);
    },
  );

  test('read reconciliation never relaunches an exited app', () async {
    final calls = <String>[];
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, _) async {
        calls.add(kind);
        return _result(kind, output: const <String, Object?>{'ok': false});
      },
    );

    final resolved = await dev.reconcile(session, allowRelaunch: false);

    expect(resolved.ready, isFalse);
    expect(resolved.session.lifecycle, 'connecting');
    expect(
      resolved.errors,
      contains(containsPair('code', 'developmentSessionReconnecting')),
    );
    expect(calls.where((kind) => kind == 'target.launch'), isEmpty);
  });

  test(
    'reconnecting status retries the same handle instead of starting',
    () async {
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, _) async =>
            _result(kind, output: const <String, Object?>{'ok': false}),
      );
      runtime.configureOutput(
        command: 'dev.status',
        selection: const CockpitCliOutputSelection(),
      );

      final resolution = await dev.reconcile(session, allowRelaunch: false);
      expect(
        await dev.writeUnavailable(action: 'status', resolution: resolution),
        cockpitTemporaryExitCode,
      );

      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(output['session'], int.parse(session.handleId));
      expect(
        output['next'],
        'cockpit dev status --session ${session.handleId}',
      );
    },
  );

  test(
    'unavailable platform target does not recommend status polling',
    () async {
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, _) async => _result(
          kind,
          output: const <String, Object?>{
            'status': <String, Object?>{
              'state': 'starting',
              'appReachable': null,
              'remoteSessionReachable': false,
            },
          },
        ),
      );
      runtime.configureOutput(
        command: 'dev.status',
        selection: const CockpitCliOutputSelection(),
      );

      final resolution = await dev.reconcile(session, allowRelaunch: false);
      expect(
        resolution.errors,
        contains(containsPair('code', 'developmentTargetUnavailable')),
      );
      expect(
        await dev.writeUnavailable(action: 'status', resolution: resolution),
        cockpitTemporaryExitCode,
      );

      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(output, isNot(contains('appLive')));
      expect(output['bridgeLive'], isFalse);
      expect(output['next'], 'cockpit target discover');
    },
  );

  test('live app with a disconnected bridge points to safe recovery', () async {
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, _) async => _result(
        kind,
        output: const <String, Object?>{
          'status': <String, Object?>{
            'state': 'starting',
            'appReachable': true,
            'remoteSessionReachable': false,
          },
        },
      ),
    );
    runtime.configureOutput(
      command: 'dev.status',
      selection: const CockpitCliOutputSelection(),
    );

    final resolution = await dev.reconcile(session, allowRelaunch: false);
    expect(
      await dev.writeUnavailable(action: 'status', resolution: resolution),
      cockpitTemporaryExitCode,
    );

    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    expect(output['next'], 'cockpit dev recover --session ${session.handleId}');
  });

  test(
    'mutation reconciliation relaunches an exited app at most once',
    () async {
      final calls = <String>[];
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, _) async {
          calls.add(kind);
          if (kind == 'target.launch') {
            return _result(
              kind,
              output: const <String, Object?>{
                'sessionId': 'session-new',
                'targetId': 'target-1',
                'appId': 'app-new',
              },
            );
          }
          if (kind == 'session.development.get') {
            return _result(
              kind,
              output: const <String, Object?>{
                'status': <String, Object?>{
                  'state': 'failed',
                  'appReachable': false,
                  'remoteSessionReachable': false,
                },
              },
            );
          }
          throw StateError('Unexpected operation $kind');
        },
      );

      final resolved = await dev.reconcile(session, allowRelaunch: true);

      expect(resolved.ready, isTrue);
      expect(resolved.changed, 'relaunched');
      expect(resolved.session.handleId, session.handleId);
      expect(calls.where((kind) => kind == 'target.launch'), hasLength(1));
    },
  );

  test('custom launch values require an explicit restart after exit', () async {
    final checkout = await runtime.checkoutIdentity();
    session = await runtime.bindDevelopmentSession(
      checkout: checkout,
      projectPath: checkout.canonicalRoot,
      workspaceId: 'workspace-1',
      sessionId: 'session-custom',
      targetId: 'target-1',
      appId: 'app-custom',
      recoverable: false,
    );
    final calls = <String>[];
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, _) async {
        calls.add(kind);
        if (kind == 'session.development.get') {
          return _result(
            kind,
            output: const <String, Object?>{
              'status': <String, Object?>{
                'state': 'failed',
                'appReachable': false,
                'remoteSessionReachable': false,
              },
            },
          );
        }
        throw StateError('Unexpected operation $kind');
      },
    );

    final resolved = await dev.reconcile(session, allowRelaunch: true);

    expect(resolved.ready, isFalse);
    expect(calls.where((kind) => kind == 'target.launch'), isEmpty);
    expect(
      resolved.errors,
      contains(containsPair('code', 'explicitRestartRequired')),
    );
    expect(
      resolved.errors.toString(),
      contains('cockpit dev start --session ${session.handleId}'),
    );
  });

  test(
    'stopped custom launch stays stopped and points back to start',
    () async {
      final checkout = await runtime.checkoutIdentity();
      session = await runtime.bindDevelopmentSession(
        checkout: checkout,
        projectPath: checkout.canonicalRoot,
        workspaceId: 'workspace-1',
        sessionId: 'session-custom-stopped',
        targetId: 'target-1',
        appId: 'app-custom-stopped',
        lifecycle: 'stopped',
        recoverable: false,
      );
      final dev = CockpitDevRuntime(runtime);

      final resolved = await dev.relaunch(session);

      expect(resolved.ready, isFalse);
      expect(resolved.session.lifecycle, 'stopped');
      runtime.configureOutput(
        command: 'dev.start',
        selection: const CockpitCliOutputSelection(),
      );
      expect(
        await dev.writeUnavailable(action: 'start', resolution: resolved),
        cockpitTemporaryExitCode,
      );
      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(output['next'], 'cockpit dev start --session ${session.handleId}');
    },
  );

  test(
    'crashed sessions point back to start for handle-preserving recovery',
    () async {
      final crashed = session.copyWith(lifecycle: 'crashed');
      final dev = CockpitDevRuntime(runtime);
      final resolution = CockpitDevSessionResolution(
        session: crashed,
        ready: false,
        changed: 'none',
        state: const <String, Object?>{'lifecycle': 'crashed'},
        errors: const <Object?>[
          <String, Object?>{'code': 'developmentSessionCrashed'},
        ],
      );

      runtime.configureOutput(
        command: 'dev.status',
        selection: const CockpitCliOutputSelection(),
      );
      expect(
        await dev.writeUnavailable(action: 'status', resolution: resolution),
        cockpitTemporaryExitCode,
      );
      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(output['next'], 'cockpit dev start --session ${session.handleId}');
    },
  );

  test('only live session states require stop before target launch', () {
    CockpitCliSessionHandle handle(String lifecycle) =>
        session.copyWith(lifecycle: lifecycle);

    expect(
      cockpitDevSessionRequiresStopBeforeLaunch(handle('connecting')),
      isTrue,
    );
    expect(cockpitDevSessionRequiresStopBeforeLaunch(handle('ready')), isTrue);
    expect(
      cockpitDevSessionRequiresStopBeforeLaunch(handle('crashed')),
      isTrue,
    );
    expect(
      cockpitDevSessionRequiresStopBeforeLaunch(handle('stopped')),
      isFalse,
    );
  });

  test(
    'inspect uses the UI-only locate profile and returns concise locators',
    () async {
      String? requestedProfile;
      String? requestedQuery;
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, input) async {
          if (kind == 'session.development.get') {
            return _result(
              kind,
              output: const <String, Object?>{
                'sessionId': 'session-old',
                'targetId': 'target-1',
                'appId': 'app-old',
                'status': <String, Object?>{
                  'state': 'ready',
                  'appReachable': true,
                  'remoteSessionReachable': true,
                },
              },
            );
          }
          if (kind == 'ui.inspect') {
            requestedProfile = input['profile'] as String?;
            final options = CockpitSnapshotOptions.fromJson(
              Map<String, Object?>.from(
                input['snapshotOptions']! as Map<Object?, Object?>,
              ),
            );
            expect(options.includeNetworkActivity, isFalse);
            expect(options.includeRuntimeActivity, isFalse);
            expect(options.maxTargets, 10000);
            requestedQuery = options.query;
            return _result(
              kind,
              output: const <String, Object?>{
                'locator': <String, Object?>{
                  'query': 'Documents',
                  'count': 1,
                  'matches': <Object?>[
                    <String, Object?>{'sel': 'Documents', 'can': 'tap'},
                  ],
                },
              },
            );
          }
          throw StateError('Unexpected operation $kind');
        },
      );
      runtime.configureOutput(
        command: 'dev.inspect',
        selection: const CockpitCliOutputSelection(),
      );

      expect(
        await dev.inspect(session, query: 'Documents'),
        cockpitSuccessExitCode,
      );
      expect(requestedProfile, 'locate');
      expect(requestedQuery, 'Documents');
      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      final matches = output['matches']! as List<Object?>;
      expect(matches, hasLength(1));
      expect(matches.single, containsPair('sel', 'Documents'));
      expect(stdout.toString(), isNot(contains('not-public')));
    },
  );

  test('full widget tree downloads one path-only artifact', () async {
    final artifact = File(p.join(temporaryDirectory.path, 'tree.json'))
      ..writeAsStringSync('{"tree":true}');
    String? requestedProfile;
    CockpitSnapshotOptions? requestedOptions;
    final dev = CockpitDevRuntime(
      runtime,
      artifactDownloader:
          (
            session, {
            required artifactId,
            required name,
            required mediaType,
          }) async {
            expect(session.sessionId, 'session-old');
            expect(artifactId, 'artifact-tree');
            expect(name, 'current_widget_tree.json');
            expect(mediaType, 'application/json');
            return artifact.path;
          },
      operationInvoker: (_, kind, input) async {
        if (kind == 'session.development.get') {
          return _result(
            kind,
            output: const <String, Object?>{
              'sessionId': 'session-old',
              'targetId': 'target-1',
              'appId': 'app-old',
              'status': <String, Object?>{
                'state': 'ready',
                'appReachable': true,
                'remoteSessionReachable': true,
              },
            },
          );
        }
        if (kind == 'ui.inspect') {
          requestedProfile = input['profile'] as String?;
          requestedOptions = CockpitSnapshotOptions.fromJson(
            Map<String, Object?>.from(
              input['snapshotOptions']! as Map<Object?, Object?>,
            ),
          );
          return _result(
            kind,
            output: <String, Object?>{
              'snapshot': const <String, Object?>{
                'treeArtifactRef': <String, Object?>{
                  'role': 'widget-tree',
                  'artifactRef': <String, Object?>{
                    'artifactId': 'artifact-tree',
                    'kind': 'widget-tree',
                    'name': 'current_widget_tree.json',
                    'mediaType': 'application/json',
                  },
                },
                'tree': <String, Object?>{
                  'profile': 'full',
                  'total': 240,
                  'visible': 180,
                  'emitted': 240,
                  'truncated': false,
                  'nodes': <Object?>[],
                },
              },
            },
          );
        }
        throw StateError('Unexpected operation $kind');
      },
    );
    runtime.configureOutput(
      command: 'dev.tree',
      selection: const CockpitCliOutputSelection(
        format: CockpitCliFormat.path,
        view: CockpitCliOutputView.full,
      ),
    );

    expect(await dev.tree(session), cockpitSuccessExitCode);
    expect(requestedProfile, 'tree');
    expect(requestedOptions?.tree, const CockpitWidgetTreeOptions.full());
    expect(requestedOptions?.maxTargets, 1);
    expect(requestedOptions?.maxAncestorsPerTarget, 0);
    expect(requestedOptions?.artifact, CockpitSnapshotArtifactMode.always);
    expect(stdout.toString().trim(), artifact.resolveSymbolicLinksSync());
  });

  test('structural tree fails when the required artifact is absent', () async {
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, input) async {
        if (kind == 'session.development.get') {
          return _result(
            kind,
            output: const <String, Object?>{
              'sessionId': 'session-old',
              'targetId': 'target-1',
              'appId': 'app-old',
              'status': <String, Object?>{
                'state': 'ready',
                'appReachable': true,
                'remoteSessionReachable': true,
              },
            },
          );
        }
        if (kind == 'ui.inspect') {
          return _result(
            kind,
            output: const <String, Object?>{
              'snapshot': <String, Object?>{
                'tree': <String, Object?>{
                  'profile': 'standard',
                  'total': 1,
                  'visible': 1,
                  'emitted': 1,
                  'truncated': false,
                  'nodes': <Object?>[
                    <String, Object?>{'type': 'Text'},
                  ],
                },
              },
            },
          );
        }
        throw StateError('Unexpected operation $kind');
      },
    );
    runtime.configureOutput(
      command: 'dev.tree',
      selection: const CockpitCliOutputSelection(
        view: CockpitCliOutputView.more,
      ),
    );

    expect(await dev.tree(session), cockpitDataExitCode);
    expect(stdout.toString(), contains('treeArtifactUnavailable'));
    expect(stdout.toString(), isNot(contains('nodes')));
    expect(stdout.toString(), isNot(contains('Text')));
  });

  test(
    'brief tree returns a compact selector index without building a tree',
    () async {
      String? requestedProfile;
      CockpitSnapshotOptions? requestedOptions;
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, input) async {
          if (kind == 'session.development.get') {
            return _result(
              kind,
              output: const <String, Object?>{
                'sessionId': 'session-old',
                'targetId': 'target-1',
                'appId': 'app-old',
                'status': <String, Object?>{
                  'state': 'ready',
                  'appReachable': true,
                  'remoteSessionReachable': true,
                },
              },
            );
          }
          if (kind == 'ui.inspect') {
            requestedProfile = input['profile'] as String?;
            requestedOptions = CockpitSnapshotOptions.fromJson(
              Map<String, Object?>.from(
                input['snapshotOptions']! as Map<Object?, Object?>,
              ),
            );
            return _result(
              kind,
              output: const <String, Object?>{
                'locator': <String, Object?>{
                  'route': '/home',
                  'count': 1,
                  'targets': <Object?>[
                    <String, Object?>{
                      'sel': '#save',
                      'label': 'Save',
                      'can': 'tap',
                    },
                  ],
                },
              },
            );
          }
          throw StateError('Unexpected operation $kind');
        },
      );
      runtime.configureOutput(
        command: 'dev.tree',
        selection: const CockpitCliOutputSelection(),
      );

      expect(await dev.tree(session), cockpitSuccessExitCode);
      expect(requestedProfile, 'locate');
      expect(requestedOptions?.tree, isNull);
      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(output['profile'], 'brief');
      expect(output['route'], '/home');
      expect(output['targets'], <Object?>[
        <String, Object?>{'sel': '#save', 'label': 'Save', 'can': 'tap'},
      ]);
      expect(stdout.toString(), isNot(contains('not-public')));
    },
  );

  test('status reuses the session query without diagnostic probes', () async {
    final calls = <String>[];
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, _) async {
        calls.add(kind);
        expect(kind, 'session.development.get');
        return _result(
          kind,
          output: const <String, Object?>{
            'sessionId': 'session-old',
            'targetId': 'target-1',
            'appId': 'app-old',
            'status': <String, Object?>{
              'state': 'ready',
              'appReachable': true,
              'remoteSessionReachable': true,
              'generation': 3,
              'reloadOk': true,
            },
          },
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.status',
      selection: const CockpitCliOutputSelection(
        view: CockpitCliOutputView.full,
      ),
    );

    expect(await dev.status(session), cockpitSuccessExitCode);
    expect(calls, <String>['session.development.get']);
    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    final state = output['state']! as Map<Object?, Object?>;
    expect(state['connection'], <String, Object?>{
      'app': true,
      'bridge': true,
      'generation': 3,
      'reloadOk': true,
    });
  });

  test(
    'diagnose uses compact UI summary and dedicated diagnostic reads',
    () async {
      final calls = <String>[];
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, input) async {
          calls.add(kind);
          return switch (kind) {
            'target.inspect' => _result(
              kind,
              output: const <String, Object?>{
                'targetKind': 'flutterApp',
                'currentRouteName': '/inbox',
              },
            ),
            'ui.inspect' => () {
              expect(input['profile'], 'standard');
              final options = CockpitSnapshotOptions.fromJson(
                Map<String, Object?>.from(
                  input['snapshotOptions']! as Map<Object?, Object?>,
                ),
              );
              expect(options.profile, CockpitSnapshotProfile.investigate);
              expect(options.includeNetworkActivity, isFalse);
              expect(options.includeRuntimeActivity, isFalse);
              expect(options.includeRebuildActivity, isTrue);
              expect(options.includeAccessibilitySummary, isTrue);
              return _result(
                kind,
                output: const <String, Object?>{
                  'routeName': '/inbox',
                  'diagnosticLevel': 'investigate',
                  'truncated': true,
                  'uiSummary': <String, Object?>{
                    'routeName': '/inbox',
                    'diagnosticLevel': 'investigate',
                    'truncated': true,
                    'visibleTargetCount': 25,
                    'targetsWithCockpitIdCount': 11,
                    'targetsWithTextCount': 19,
                    'networkEntryCount': 2,
                    'networkFailureCount': 1,
                    'runtimeEntryCount': 1,
                    'runtimeErrorCount': 1,
                    'rebuildEntryCount': 0,
                    'totalRebuildCount': 0,
                    'accessibilityTargetCount': 14,
                    'accessibilityTraversalCount': 8,
                    'textPreviews': <Object?>['New task'],
                  },
                  'snapshotRef': 'snapshot-1',
                },
              );
            }(),
            'errors.read' => _result(
              kind,
              output: const <String, Object?>{
                'source': 'app_snapshot',
                'routeName': '/inbox',
                'errors': <Object?>[
                  <String, Object?>{'message': 'build failed'},
                ],
              },
            ),
            'network.read' => _result(
              kind,
              output: const <String, Object?>{
                'available': true,
                'routeName': '/inbox',
                'summary': <String, Object?>{'failureCount': 1},
              },
            ),
            'logs.read' => _result(
              kind,
              output: const <String, Object?>{
                'source': 'app_snapshot',
                'routeName': '/inbox',
                'lines': <Object?>['error: build failed'],
              },
            ),
            _ => throw StateError('Unexpected operation $kind'),
          };
        },
      );
      runtime.configureOutput(
        command: 'dev.diagnose',
        selection: const CockpitCliOutputSelection(
          view: CockpitCliOutputView.more,
        ),
      );

      expect(
        await dev.status(session, diagnose: true),
        cockpitTemporaryExitCode,
      );
      expect(calls, <String>[
        'target.inspect',
        'ui.inspect',
        'errors.read',
        'network.read',
        'logs.read',
      ]);
      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      final ui = output['ui']! as Map<Object?, Object?>;
      expect(ui['visible'], 25);
      expect(ui['cockpitIds'], 11);
      expect(ui['textTargets'], 19);
      expect(ui['a11y'], 14);
      expect(ui['a11yOrder'], 8);
      expect(ui, isNot(contains('ui')));
      expect(ui, isNot(contains('route')));
      expect(ui, isNot(contains('snapshot')));
      expect(output['errors'], 1);
      expect(output['netFailures'], 1);
    },
  );

  test('brief command actions skip hidden post-action snapshots', () async {
    final calls = <String>[];
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, input) async {
        calls.add(kind);
        if (kind == 'session.development.get') {
          return _result(
            kind,
            output: const <String, Object?>{
              'sessionId': 'session-old',
              'targetId': 'target-1',
              'appId': 'app-old',
              'status': <String, Object?>{
                'state': 'ready',
                'appReachable': true,
                'remoteSessionReachable': true,
              },
            },
          );
        }
        expect(kind, 'command.run');
        expect(input['profile'], 'minimal');
        final command = CockpitCommand.fromJson(
          Map<String, Object?>.from(input['command']! as Map<Object?, Object?>),
        );
        expect(command.capturePolicy, CockpitCapturePolicy.onFailure);
        return _result(
          kind,
          output: const <String, Object?>{
            'command': <String, Object?>{'success': true, 'changed': true},
            'changed': true,
            'uiSummary': <String, Object?>{'routeName': '/'},
          },
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.tap',
      selection: const CockpitCliOutputSelection(),
    );

    expect(
      await dev.runCommand(
        session,
        action: 'tap',
        command: dev.command(
          type: CockpitCommandType.tap,
          timeout: const Duration(seconds: 30),
          locator: const CockpitLocator(text: 'Documents'),
        ),
      ),
      cockpitSuccessExitCode,
    );
    expect(calls, <String>['session.development.get', 'command.run']);
    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    expect(output['changed'], isTrue);
    expect(output['session'], 1);
  });

  test('detailed command actions request proportional evidence', () async {
    for (final (:view, :profile)
        in <({CockpitCliOutputView view, String profile})>[
          (view: CockpitCliOutputView.more, profile: 'standard'),
          (view: CockpitCliOutputView.full, profile: 'evidence'),
        ]) {
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, input) async {
          if (kind == 'session.development.get') {
            return _result(
              kind,
              output: const <String, Object?>{
                'sessionId': 'session-old',
                'targetId': 'target-1',
                'appId': 'app-old',
                'status': <String, Object?>{
                  'state': 'ready',
                  'appReachable': true,
                  'remoteSessionReachable': true,
                },
              },
            );
          }
          expect(kind, 'command.run');
          expect(input['profile'], profile);
          return _result(
            kind,
            output: const <String, Object?>{
              'command': <String, Object?>{'success': true, 'changed': true},
              'changed': true,
              'uiSummary': <String, Object?>{'routeName': '/documents'},
            },
          );
        },
      );
      runtime.configureOutput(
        command: 'dev.tap',
        selection: CockpitCliOutputSelection(view: view),
      );

      expect(
        await dev.runCommand(
          session,
          action: 'tap',
          command: dev.command(
            type: CockpitCommandType.tap,
            timeout: const Duration(seconds: 30),
            locator: const CockpitLocator(text: 'Documents'),
          ),
        ),
        cockpitSuccessExitCode,
      );
    }
  });

  test(
    'locator failures point to a bounded inspect of the same target',
    () async {
      final dev = CockpitDevRuntime(
        runtime,
        operationInvoker: (_, kind, _) async {
          if (kind == 'session.development.get') {
            return _result(
              kind,
              output: const <String, Object?>{
                'sessionId': 'session-old',
                'targetId': 'target-1',
                'appId': 'app-old',
                'status': <String, Object?>{
                  'state': 'ready',
                  'appReachable': true,
                  'remoteSessionReachable': true,
                },
              },
            );
          }
          return _result(
            kind,
            output: const <String, Object?>{
              'command': <String, Object?>{
                'success': false,
                'error': <String, Object?>{
                  'code': CockpitCommandError.targetNotFoundCode,
                  'message': 'No visible target matched the locator.',
                },
              },
            },
          );
        },
      );
      runtime.configureOutput(
        command: 'dev.tap',
        selection: const CockpitCliOutputSelection(),
      );

      expect(
        await dev.runCommand(
          session,
          action: 'tap',
          command: dev.command(
            type: CockpitCommandType.tap,
            locator: const CockpitLocator(text: "Owner's task"),
          ),
        ),
        cockpitDataExitCode,
      );

      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      final quoted = Platform.isWindows
          ? "'Owner''s task'"
          : "'Owner'\"'\"'s task'";
      expect(
        output['next'],
        'cockpit dev inspect $quoted --session ${session.handleId}',
      );
    },
  );

  test('expired live refs point to the current control surface', () async {
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, _) async {
        if (kind == 'session.development.get') {
          return _result(
            kind,
            output: const <String, Object?>{
              'sessionId': 'session-old',
              'targetId': 'target-1',
              'appId': 'app-old',
              'status': <String, Object?>{
                'state': 'ready',
                'appReachable': true,
                'remoteSessionReachable': true,
              },
            },
          );
        }
        return _result(
          kind,
          output: const <String, Object?>{
            'command': <String, Object?>{
              'success': false,
              'error': <String, Object?>{
                'code': CockpitCommandError.targetNotFoundCode,
                'message': 'No visible target matched the live ref.',
              },
            },
          },
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.tap',
      selection: const CockpitCliOutputSelection(),
    );

    expect(
      await dev.runCommand(
        session,
        action: 'tap',
        command: dev.command(
          type: CockpitCommandType.tap,
          locator: const CockpitLocator(ref: 'a7b9x2'),
        ),
      ),
      cockpitDataExitCode,
    );

    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    expect(output['next'], 'cockpit dev inspect --session ${session.handleId}');
  });

  test('open URI reuses the exact session through system control', () async {
    final calls = <String>[];
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, input) async {
        calls.add(kind);
        if (kind == 'session.development.get') {
          return _result(
            kind,
            output: const <String, Object?>{
              'sessionId': 'session-old',
              'targetId': 'target-1',
              'appId': 'app-old',
              'status': <String, Object?>{
                'state': 'ready',
                'appReachable': true,
                'remoteSessionReachable': true,
              },
            },
          );
        }
        expect(kind, 'system.action');
        expect(input, <String, Object?>{
          'sessionId': 'session-old',
          'action': 'openUrl',
          'parameters': <String, Object?>{'url': 'cockpit-demo://tasks/42'},
          'timeoutMs': 60000,
        });
        return _result(
          kind,
          output: const <String, Object?>{
            'action': 'openUrl',
            'availability': 'available',
            'success': true,
            'strategy': 'test.openUrl',
          },
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.open',
      selection: const CockpitCliOutputSelection(
        view: CockpitCliOutputView.full,
      ),
    );

    expect(
      await dev.openUri(
        session,
        uri: 'cockpit-demo://tasks/42',
        scheme: 'cockpit-demo',
        timeoutMilliseconds: 60000,
      ),
      cockpitSuccessExitCode,
    );
    expect(calls, <String>['session.development.get', 'system.action']);
    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    final state = output['state']! as Map<Object?, Object?>;
    expect(state['scheme'], 'cockpit-demo');
    expect(output['session'], 1);
    expect(stdout.toString(), isNot(contains('tasks/42')));
    expect(stdout.toString(), isNot(contains('command')));
  });

  test('system recovery defaults to focus-only for one session', () async {
    final calls = <String>[];
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, input) async {
        calls.add(kind);
        expect(kind, 'system.action');
        expect(input, <String, Object?>{
          'sessionId': 'session-old',
          'action': 'resolveBlockers',
          'parameters': <String, Object?>{},
          'timeoutMs': 120000,
        });
        return _result(
          kind,
          output: const <String, Object?>{
            'action': 'resolveBlockers',
            'availability': 'available',
            'success': true,
            'changed': false,
            'strategy': 'test.resolveBlockers',
          },
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.recover',
      selection: const CockpitCliOutputSelection(),
    );

    expect(
      await dev.recoverSystemBlockers(
        Future<CockpitCliSessionHandle>.value(session),
        dialog: null,
        dismissKeyboard: false,
        timeoutMilliseconds: 120000,
      ),
      cockpitSuccessExitCode,
    );
    expect(calls, <String>['system.action']);
    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    expect(output.containsKey('dialog'), isFalse);
    expect(output['changed'], isFalse);
    expect(output['session'], 1);
    expect(stdout.toString(), isNot(contains('success')));
  });

  test('system recovery forwards an explicit native dialog decision', () async {
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, input) async {
        expect(input, <String, Object?>{
          'sessionId': 'session-old',
          'action': 'resolveBlockers',
          'parameters': <String, Object?>{'decision': 'accept'},
          'timeoutMs': 120000,
        });
        return _result(
          kind,
          output: const <String, Object?>{
            'action': 'resolveBlockers',
            'availability': 'available',
            'success': true,
            'changed': true,
          },
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.recover',
      selection: const CockpitCliOutputSelection(),
    );

    expect(
      await dev.recoverSystemBlockers(
        Future<CockpitCliSessionHandle>.value(session),
        dialog: 'accept',
        dismissKeyboard: false,
        timeoutMilliseconds: 120000,
      ),
      cockpitSuccessExitCode,
    );
    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    expect(output['dialog'], 'accept');
    expect(output['changed'], isTrue);
  });

  test('failed system recovery does not claim that state changed', () async {
    final dev = CockpitDevRuntime(
      runtime,
      operationInvoker: (_, kind, input) async {
        final now = DateTime.utc(2026, 8, 4);
        return CockpitOperationResult(
          operationId: 'operation-recover-failed',
          kind: kind,
          workspaceId: 'workspace-1',
          lifecycle: CockpitOperationLifecycle.completed,
          outcome: CockpitOperationOutcome.failed,
          submittedAt: now,
          startedAt: now,
          finishedAt: now,
          failure: CockpitFailure(
            primary: CockpitApiError(
              code: 'macosSessionLocked',
              category: CockpitErrorCategory.application,
              message: 'Unlock the macOS session.',
              retryable: false,
              responsibleLayer: CockpitResponsibleLayer.worker,
              redactedDetails: const <String, Object?>{
                'next': 'unlockMacosSession',
              },
            ),
          ),
        );
      },
    );
    runtime.configureOutput(
      command: 'dev.recover',
      selection: const CockpitCliOutputSelection(),
    );

    expect(
      await dev.recoverSystemBlockers(
        Future<CockpitCliSessionHandle>.value(session),
        dialog: null,
        dismissKeyboard: false,
        timeoutMilliseconds: 120000,
      ),
      cockpitUnavailableExitCode,
    );
    final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
    expect(output.containsKey('changed'), isFalse);
    expect(output['next'], 'unlockMacosSession');
  });
}

CockpitOperationResult _result(
  String kind, {
  required Map<String, Object?> output,
}) {
  final now = DateTime.utc(2026, 8, 4);
  return CockpitOperationResult(
    operationId: 'operation-${kind.replaceAll('.', '-')}',
    kind: kind,
    workspaceId: 'workspace-1',
    lifecycle: CockpitOperationLifecycle.completed,
    outcome: CockpitOperationOutcome.succeeded,
    submittedAt: now,
    startedAt: now,
    finishedAt: now,
    output: output,
  );
}

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
