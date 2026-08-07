import 'dart:io';

import 'package:lon/lon.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_session_handles.dart';
import 'package:cockpit/src/cli/cockpit_dev_runtime.dart';
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
    runtime = CockpitCliRuntime(
      workingDirectory: temporaryDirectory.path,
      stdoutSink: stdout,
      stderrSink: StringBuffer(),
      sessionHandleStoreProvider: () async => store,
      checkoutIdentityResolver: CockpitCheckoutIdentityResolver(
        processRunner: (_, _, {workingDirectory, environment}) async =>
            ProcessResult(1, 1, '', ''),
      ),
    );
    final checkout = await runtime.checkoutIdentity();
    session = await runtime.bindDevelopmentSession(
      checkout: checkout,
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
    expect(calls.where((kind) => kind == 'target.launch'), isEmpty);
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
          return _result(kind, output: const <String, Object?>{'ok': false});
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
        return _result(kind, output: const <String, Object?>{'ok': false});
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
    'inspect uses the UI-only locate profile and returns concise locators',
    () async {
      String? requestedProfile;
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
            expect(options.maxTargets, 160);
            return _result(
              kind,
              output: const <String, Object?>{
                'snapshot': <String, Object?>{
                  'visibleTargets': <Object?>[
                    <String, Object?>{
                      'registrationId': 'not-public',
                      'text': 'Documents',
                      'typeName': 'TextButton',
                      'routeName': '/',
                      'supportedCommands': <Object?>['tap'],
                      'ancestors': <Object?>[],
                    },
                  ],
                  'network': <String, Object?>{
                    'entries': <Object?>[
                      <String, Object?>{'sha256': 'not-public'},
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
        command: 'dev.inspect',
        selection: const CockpitCliOutputSelection(),
      );

      expect(
        await dev.inspect(session, query: 'Documents'),
        cockpitSuccessExitCode,
      );
      expect(requestedProfile, 'locate');
      final output = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      final state = output['state']! as Map<Object?, Object?>;
      final matches = state['matches']! as List<Object?>;
      expect(matches, hasLength(1));
      expect(
        matches.single,
        containsPair('loc', <String, Object?>{'text': 'Documents'}),
      );
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
        detail: CockpitCliOutputDetail.full,
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

  test('command actions keep one post-action commit snapshot', () async {
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
        expect(input['profile'], 'standard');
        final command = CockpitCommand.fromJson(
          Map<String, Object?>.from(input['command']! as Map<Object?, Object?>),
        );
        expect(command.capturePolicy, CockpitCapturePolicy.onFailure);
        return _result(
          kind,
          output: const <String, Object?>{
            'command': <String, Object?>{'success': true},
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
