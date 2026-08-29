import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_cli_session_handles.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:cockpit/src/development/cockpit_checkout_identity.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late CockpitCliSessionHandleStore store;
  var tick = 0;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'cockpit-cli-session-test-',
    );
    store = CockpitCliSessionHandleStore.file(
      path: p.join(temporaryDirectory.path, 'sessions.json'),
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
      utcNow: () => DateTime.utc(2026).add(Duration(seconds: tick++)),
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('persists stable short handles and updates recency', () async {
    final first = await store.bind(
      workspaceId: 'workspace-1',
      sessionId: 'session-canonical-1',
    );
    final rebound = await store.bind(
      workspaceId: 'workspace-1',
      sessionId: 'session-canonical-1',
    );
    final second = await store.bind(
      workspaceId: 'workspace-1',
      sessionId: 'session-canonical-2',
    );

    expect(first.handleId, '1');
    expect(rebound.handleId, first.handleId);
    expect(rebound.updatedAt, isNot(first.updatedAt));
    expect(second.handleId, '2');
    expect((await store.list()).map((item) => item.handleId), ['2', '1']);

    final reopened = CockpitCliSessionHandleStore.file(
      path: p.join(temporaryDirectory.path, 'sessions.json'),
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    );
    expect((await reopened.find('1'))?.sessionId, 'session-canonical-1');
    expect(await reopened.remove('1'), isTrue);
    expect(await reopened.find('1'), isNull);
    expect(await reopened.remove('1'), isFalse);
  });

  test('allocates compact lowercase base-36 handles', () async {
    final handles = <String>[];
    for (var index = 1; index <= 12; index += 1) {
      handles.add(
        (await store.bind(
          workspaceId: 'workspace-$index',
          sessionId: 'session-$index',
        )).handleId,
      );
    }

    expect(handles, <String>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'a',
      'b',
      'c',
    ]);
  });

  test('keeps one public handle while development identities change', () async {
    final checkout = p.normalize(temporaryDirectory.path);
    final identity = 'a' * 64;
    final first = await store.bindDevelopment(
      checkoutIdentity: identity,
      checkoutPath: checkout,
      projectPath: checkout,
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );

    final reconnected = await store.bindDevelopment(
      checkoutIdentity: identity,
      checkoutPath: checkout,
      projectPath: checkout,
      workspaceId: 'workspace-1',
      sessionId: 'session-2',
      targetId: 'target-1',
      appId: 'app-2',
    );

    expect(reconnected.handleId, first.handleId);
    expect(reconnected.sessionId, 'session-2');
    expect(reconnected.appId, 'app-2');
    expect(
      (await store.activeForPath(
        checkoutIdentity: identity,
        path: checkout,
      ))?.handleId,
      '1',
    );
    expect(reconnected.entrypoint, 'lib/main.dart');
    expect(reconnected.platform, 'macos');
    expect(reconnected.deviceId, 'macos');
  });

  test('session state refresh preserves the active project handle', () async {
    final checkoutPath = p.normalize(temporaryDirectory.path);
    final checkoutIdentity = 'a' * 64;
    final first = await store.bindDevelopment(
      checkoutIdentity: checkoutIdentity,
      checkoutPath: checkoutPath,
      projectPath: checkoutPath,
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );
    final second = await store.bindDevelopment(
      checkoutIdentity: checkoutIdentity,
      checkoutPath: checkoutPath,
      projectPath: checkoutPath,
      workspaceId: 'workspace-1',
      sessionId: 'session-2',
      targetId: 'target-2',
      appId: 'app-2',
      entrypoint: 'lib/main.dart',
      platform: 'android',
      deviceId: 'emulator-5554',
    );
    await store.selectDevelopment(first.handleId);
    final runtime = CockpitCliRuntime(
      workingDirectory: checkoutPath,
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      sessionHandleStoreProvider: () async => store,
    );

    final refreshed = await runtime.updateDevelopmentSession(
      previous: second,
      workspaceId: second.workspaceId,
      sessionId: 'session-2-refreshed',
      targetId: second.targetId!,
      appId: 'app-2-refreshed',
      lifecycle: 'crashed',
    );

    expect(refreshed.handleId, second.handleId);
    expect(
      (await store.activeForPath(
        checkoutIdentity: checkoutIdentity,
        path: checkoutPath,
      ))?.handleId,
      first.handleId,
    );

    await runtime.updateDevelopmentSession(
      activate: true,
      previous: refreshed,
      workspaceId: refreshed.workspaceId,
      sessionId: refreshed.sessionId,
      targetId: refreshed.targetId!,
      appId: refreshed.appId!,
      lifecycle: refreshed.lifecycle,
    );
    expect(
      (await store.activeForPath(
        checkoutIdentity: checkoutIdentity,
        path: checkoutPath,
      ))?.handleId,
      second.handleId,
    );
  });

  test(
    'persists only whether custom launches can recover automatically',
    () async {
      final checkout = p.normalize(temporaryDirectory.path);
      final handle = await store.bindDevelopment(
        checkoutIdentity: 'c' * 64,
        checkoutPath: checkout,
        projectPath: checkout,
        workspaceId: 'workspace-1',
        sessionId: 'session-1',
        targetId: 'target-1',
        appId: 'app-1',
        entrypoint: 'lib/main.dart',
        platform: 'ios',
        deviceId: 'iphone-1',
        flavor: 'staging',
        recoverable: false,
        launchTimeoutMilliseconds: 123456,
      );

      expect(handle.recoverable, isFalse);
      expect(handle.launchTimeoutMilliseconds, 123456);
      final persisted = await File(
        p.join(temporaryDirectory.path, 'sessions.json'),
      ).readAsString();
      expect(persisted, contains('cockpit.cli-sessions/v6'));
      expect(persisted, isNot(contains('secret-value')));
      expect(persisted, isNot(contains('launchConfiguration')));

      final rebound = await store.bindDevelopment(
        checkoutIdentity: 'c' * 64,
        checkoutPath: checkout,
        projectPath: checkout,
        workspaceId: 'workspace-1',
        sessionId: 'session-2',
        targetId: 'target-1',
        appId: 'app-2',
      );
      expect(rebound.handleId, handle.handleId);
      expect(rebound.recoverable, isFalse);
      expect(rebound.launchTimeoutMilliseconds, 123456);
    },
  );

  test('keeps implicit selection isolated across checkouts', () async {
    final firstIdentity = 'a' * 64;
    final secondIdentity = 'b' * 64;
    final firstProject = p.join(temporaryDirectory.path, 'first');
    final secondProject = p.join(temporaryDirectory.path, 'second');
    await Directory(firstProject).create();
    await Directory(secondProject).create();
    final handle = await store.bindDevelopment(
      checkoutIdentity: firstIdentity,
      checkoutPath: p.normalize(temporaryDirectory.path),
      projectPath: p.normalize(firstProject),
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );

    await store.bindDevelopment(
      checkoutIdentity: secondIdentity,
      checkoutPath: p.normalize(temporaryDirectory.path),
      projectPath: p.normalize(secondProject),
      workspaceId: 'workspace-2',
      sessionId: 'session-2',
      targetId: 'target-2',
      appId: 'app-2',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );

    expect(
      await store.activeForPath(
        checkoutIdentity: secondIdentity,
        path: firstProject,
      ),
      isNull,
    );
    expect((await store.selectDevelopment(handle.handleId)).handleId, '1');
  });

  test(
    'runtime resolves bound IDs and rejects unknown short handles',
    () async {
      final runtime = CockpitCliRuntime(
        workingDirectory: temporaryDirectory.path,
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
        sessionHandleStoreProvider: () async => store,
      );
      final bound = await runtime.bindSessionHandle(
        workspaceId: 'workspace-1',
        sessionId: 'session-canonical',
      );

      final resolved = await runtime.resolveSessionHandle(bound.handleId);

      expect(resolved.handleId, '1');
      expect(resolved.sessionId, 'session-canonical');
      expect(
        () => runtime.resolveSessionHandle('9'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('active development sessions stay within their workspace', () async {
    final runtime = CockpitCliRuntime(
      workingDirectory: temporaryDirectory.path,
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
      sessionHandleStoreProvider: () async => store,
    );
    final checkout = await runtime.checkoutIdentity();
    expect(
      await runtime.maybeActiveDevelopmentSession(workspaceId: 'workspace-1'),
      isNull,
    );
    await store.bindDevelopment(
      checkoutIdentity: checkout.value,
      checkoutPath: checkout.canonicalRoot,
      projectPath: checkout.canonicalRoot,
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );

    expect(
      (await runtime.activeDevelopmentSession(
        workspaceId: 'workspace-1',
      )).sessionId,
      'session-1',
    );
    expect(
      (await runtime.maybeActiveDevelopmentSession(
        workspaceId: 'workspace-1',
      ))?.targetId,
      'target-1',
    );
    await expectLater(
      runtime.activeDevelopmentSession(workspaceId: 'workspace-2'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'resolves implicit sessions by project and rejects ancestor ambiguity',
    () async {
      final firstProject = Directory(
        p.join(temporaryDirectory.path, 'apps', 'first'),
      );
      final secondProject = Directory(
        p.join(temporaryDirectory.path, 'apps', 'second'),
      );
      final gitCommon = Directory(p.join(temporaryDirectory.path, '.git'));
      await Future.wait(<Future<void>>[
        firstProject.create(recursive: true),
        secondProject.create(recursive: true),
        gitCommon.create(recursive: true),
      ]);
      final resolver = CockpitCheckoutIdentityResolver(
        processRunner: (_, _, {workingDirectory, environment}) async =>
            ProcessResult(
              1,
              0,
              '${temporaryDirectory.path}\n'
                  '${gitCommon.path}\n'
                  '${gitCommon.path}\n',
              '',
            ),
      );
      CockpitCliRuntime createRuntime(String workingDirectory) =>
          CockpitCliRuntime(
            workingDirectory: workingDirectory,
            stdoutSink: StringBuffer(),
            stderrSink: StringBuffer(),
            sessionHandleStoreProvider: () async => store,
            checkoutIdentityResolver: resolver,
          );

      final firstRuntime = createRuntime(firstProject.path);
      final checkout = await firstRuntime.checkoutIdentity();
      final firstPath = p.normalize(await firstProject.resolveSymbolicLinks());
      final secondPath = p.normalize(
        await secondProject.resolveSymbolicLinks(),
      );
      final first = await store.bindDevelopment(
        checkoutIdentity: checkout.value,
        checkoutPath: checkout.canonicalRoot,
        projectPath: firstPath,
        workspaceId: 'workspace-1',
        sessionId: 'session-1',
        targetId: 'target-1',
        appId: 'app-1',
        entrypoint: 'lib/main.dart',
        platform: 'macos',
        deviceId: 'macos',
      );
      final second = await store.bindDevelopment(
        checkoutIdentity: checkout.value,
        checkoutPath: checkout.canonicalRoot,
        projectPath: secondPath,
        workspaceId: 'workspace-2',
        sessionId: 'session-2',
        targetId: 'target-2',
        appId: 'app-2',
        entrypoint: 'lib/main.dart',
        platform: 'android',
        deviceId: 'emulator-5554',
      );

      expect(
        (await firstRuntime.resolveDevelopmentSession(null)).handleId,
        first.handleId,
      );
      expect(
        (await createRuntime(
          secondProject.path,
        ).resolveDevelopmentSession(null)).handleId,
        second.handleId,
      );
      final rootRuntime = createRuntime(temporaryDirectory.path);
      await expectLater(
        rootRuntime.resolveDevelopmentSession(null),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Multiple Flutter projects'),
          ),
        ),
      );
      expect(
        (await rootRuntime.resolveDevelopmentSession(second.handleId)).handleId,
        second.handleId,
      );
      expect(
        (await store.activeForPath(
          checkoutIdentity: checkout.value,
          path: firstPath,
        ))?.handleId,
        first.handleId,
      );
    },
  );

  test('session list reads saved state without connecting', () async {
    final checkout = await CockpitCliRuntime(
      workingDirectory: temporaryDirectory.path,
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    ).checkoutIdentity();
    await store.bindDevelopment(
      checkoutIdentity: checkout.value,
      checkoutPath: checkout.canonicalRoot,
      projectPath: checkout.canonicalRoot,
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'android',
      deviceId: 'emulator-5554',
      lifecycle: 'crashed',
    );
    final stdout = StringBuffer();
    var clientRequests = 0;
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        workingDirectory: temporaryDirectory.path,
        stdoutSink: stdout,
        stderrSink: StringBuffer(),
        sessionHandleStoreProvider: () async => store,
        clientProvider: () async {
          clientRequests += 1;
          throw StateError('session list must not connect');
        },
      ),
    );

    final exitCode = await runner.run(const <String>[
      'session',
      'list',
      '--format',
      'json',
    ]);
    final output = jsonDecode(stdout.toString()) as Map<String, Object?>;
    final items = output['items']! as List<Object?>;
    final item = items.single! as Map<String, Object?>;

    expect(exitCode, cockpitSuccessExitCode);
    expect(clientRequests, 0);
    expect(item['last'], 'crashed');
    expect(item, isNot(contains('state')));
    expect(item, isNot(contains('lastState')));
    expect(item, isNot(contains('lifecycle')));
    expect(item, isNot(contains('reachable')));
  });

  test('generates required idempotency keys and enforces prohibition', () {
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    );
    final required = _descriptor(CockpitIdempotencyBehavior.required);
    final prohibited = _descriptor(CockpitIdempotencyBehavior.prohibited);

    final generated = runtime.operationIdempotencyKey(required, null);

    expect(generated?.value, matches(RegExp(r'^c[0-9a-z]{10}$')));
    expect(
      runtime.operationIdempotencyKey(required, 'caller-key')?.value,
      'caller-key',
    );
    expect(
      () => runtime.operationIdempotencyKey(prohibited, 'not-allowed'),
      throwsA(isA<FormatException>()),
    );
  });

  test('adopts advertised operation timeout bounds', () {
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    );
    final descriptor = _descriptor(CockpitIdempotencyBehavior.required);

    runtime.configureTimeout(const Duration(minutes: 2), explicit: false);
    runtime.adoptOperationTimeout(descriptor);
    expect(runtime.commandTimeout, const Duration(seconds: 1));
    expect(runtime.timeoutExplicit, isFalse);

    runtime.configureTimeout(
      const Duration(milliseconds: 1500),
      explicit: true,
    );
    runtime.adoptOperationTimeout(descriptor);
    expect(runtime.commandTimeout, const Duration(milliseconds: 1500));
    expect(runtime.timeoutExplicit, isTrue);

    runtime.configureTimeout(const Duration(seconds: 3), explicit: true);
    expect(
      () => runtime.adoptOperationTimeout(descriptor),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cannot exceed 2s'),
        ),
      ),
    );
  });

  test('keeps request operation budgets stable and bounded', () {
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    );

    runtime.configureTimeout(const Duration(minutes: 20), explicit: false);

    expect(runtime.operationBudget(), const Duration(minutes: 19, seconds: 59));
    expect(
      runtime.operationBudget(maximum: const Duration(minutes: 10)),
      const Duration(minutes: 10),
    );
    expect(runtime.operationTimeout, lessThan(runtime.operationBudget()));
  });
}

CockpitOperationDescriptor _descriptor(CockpitIdempotencyBehavior behavior) =>
    CockpitOperationDescriptor(
      kind: 'test.operation',
      title: 'Test operation',
      description: 'Exercises CLI operation policy.',
      scope: CockpitOperationScope.workspace,
      mutationClass: CockpitMutationClass.mutating,
      idempotency: behavior,
      executionMode: CockpitOperationExecutionMode.synchronous,
      defaultTimeoutMs: 1000,
      maximumTimeoutMs: 2000,
      requestSchemaRef: r'#/$defs/test.request',
      responseSchemaRef: r'#/$defs/test.response',
    );

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
