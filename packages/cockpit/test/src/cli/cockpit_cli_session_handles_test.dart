import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_cli_session_handles.dart';
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

  test('keeps one public handle while development identities change', () async {
    final checkout = p.normalize(temporaryDirectory.path);
    final identity = 'a' * 64;
    final first = await store.bindDevelopment(
      checkoutIdentity: identity,
      checkoutPath: checkout,
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
      workspaceId: 'workspace-1',
      sessionId: 'session-2',
      targetId: 'target-1',
      appId: 'app-2',
    );

    expect(reconnected.handleId, first.handleId);
    expect(reconnected.sessionId, 'session-2');
    expect(reconnected.appId, 'app-2');
    expect((await store.activeForCheckout(identity))?.handleId, '1');
    expect(reconnected.entrypoint, 'lib/main.dart');
    expect(reconnected.platform, 'macos');
    expect(reconnected.deviceId, 'macos');
  });

  test(
    'persists only whether custom launches can recover automatically',
    () async {
      final checkout = p.normalize(temporaryDirectory.path);
      final handle = await store.bindDevelopment(
        checkoutIdentity: 'c' * 64,
        checkoutPath: checkout,
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
      expect(persisted, contains('cockpit.cli-sessions/v5'));
      expect(persisted, isNot(contains('secret-value')));
      expect(persisted, isNot(contains('launchConfiguration')));

      final rebound = await store.bindDevelopment(
        checkoutIdentity: 'c' * 64,
        checkoutPath: checkout,
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

  test('does not select a development handle across checkouts', () async {
    final firstIdentity = 'a' * 64;
    final secondIdentity = 'b' * 64;
    final handle = await store.bindDevelopment(
      checkoutIdentity: firstIdentity,
      checkoutPath: p.normalize(temporaryDirectory.path),
      workspaceId: 'workspace-1',
      sessionId: 'session-1',
      targetId: 'target-1',
      appId: 'app-1',
      entrypoint: 'lib/main.dart',
      platform: 'macos',
      deviceId: 'macos',
    );

    await expectLater(
      store.selectForCheckout(
        checkoutIdentity: secondIdentity,
        reference: handle.handleId,
      ),
      throwsA(isA<FormatException>()),
    );
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

  test('generates required idempotency keys and enforces prohibition', () {
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    );
    final required = _descriptor(CockpitIdempotencyBehavior.required);
    final prohibited = _descriptor(CockpitIdempotencyBehavior.prohibited);

    final generated = runtime.operationIdempotencyKey(required, null);

    expect(generated?.value, matches(RegExp(r'^cli-[A-Za-z0-9_-]+$')));
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
