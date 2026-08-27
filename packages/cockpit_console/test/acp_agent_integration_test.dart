import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:cockpit_console/src/providers/acp_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'real ACP agent keeps distinct message IDs in distinct messages',
    () async {
      final harness = await _AcpAgentHarness.start();
      addTearDown(harness.dispose);

      expect(await harness.notifier.sendPrompt('Stream two messages'), isTrue);
      final connected = harness.connected;
      final messages = connected.messages;

      expect(messages, hasLength(3));
      expect(messages[1].messageId, 'assistant-1');
      expect(messages[1].text, 'First message');
      expect(messages[1].toolCallIds, isEmpty);
      expect(messages[1].isStreaming, isFalse);
      expect(messages[2].messageId, 'assistant-2');
      expect(messages[2].text, 'Second message');
      expect(messages[2].toolCallIds, ['tool-2']);
      expect(messages[2].isStreaming, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('real ACP agent cooperatively cancels before forced teardown', () async {
    final harness = await _AcpAgentHarness.start();
    addTearDown(harness.dispose);

    final prompt = harness.notifier.sendPrompt('wait-for-cancel');
    await harness.waitFor((state) => state.isPrompting);

    final elapsed = Stopwatch()..start();
    harness.notifier.cancelTurn();
    expect(await prompt, isTrue);
    elapsed.stop();

    final connected = harness.connected;
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
    expect(connected.isPrompting, isFalse);
    expect(connected.messages.last.text, 'Cancelled by client');
    expect(connected.messages.last.messageId, 'cancelled-message');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('real ACP permission request accepts only an offered option', () async {
    final harness = await _AcpAgentHarness.start();
    addTearDown(harness.dispose);

    final prompt = harness.notifier.sendPrompt('request-permission');
    final awaitingPermission = await harness.waitFor(
      (state) => state.pendingPermission != null,
    );
    final permission = awaitingPermission.pendingPermission!;

    expect(permission.toolCall.toolCallId, 'permission-tool');
    expect(permission.options.map((option) => option.optionId), [
      'allow-once',
      'reject-once',
    ]);
    expect(
      harness.notifier.respondToPermission(
        requestId: permission.requestId,
        optionId: 'not-offered',
      ),
      isFalse,
    );
    expect(
      harness.notifier.respondToPermission(
        requestId: permission.requestId,
        optionId: 'allow-once',
      ),
      isTrue,
    );
    expect(await prompt, isTrue);

    final session = harness.connected.activeSession!;
    expect(session.pendingPermission, isNull);
    expect(
      session.toolCalls['permission-tool']?.status,
      ToolCallStatus.completed,
    );
    expect(
      session.messages.any(
        (message) => message.text == 'permission:allow-once',
      ),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'real ACP agent uses confined file and terminal client callbacks',
    () async {
      final sessionRoot = Directory.systemTemp.createTempSync(
        'cockpit_console_acp_client_',
      );
      addTearDown(() => sessionRoot.deleteSync(recursive: true));
      File(
        p.join(sessionRoot.path, 'client-input.txt'),
      ).writeAsStringSync('from-client');
      final harness = await _AcpAgentHarness.start(
        sessionCwd: sessionRoot.path,
      );
      addTearDown(harness.dispose);

      expect(await harness.notifier.sendPrompt('exercise-client'), isTrue);

      final connected = harness.connected;
      final response = connected.messages.last.text;
      expect(response, contains('read:from-client;exit:0;'));
      expect(response, contains('Dart SDK version:'));
      expect(
        File(p.join(sessionRoot.path, 'client-output.txt')).readAsStringSync(),
        'written-by-agent',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'real ACP agent preserves initial state and applies all session updates',
    () async {
      final harness = await _AcpAgentHarness.start();
      addTearDown(harness.dispose);

      final initial = harness.connected.activeSession!;
      expect(initial.modes?.currentModeId, 'code');
      expect(initial.modes?.availableModes.map((mode) => mode.id), [
        'code',
        'plan',
      ]);
      expect(initial.configOptions, hasLength(1));
      expect(
        (initial.configOptions.single as SessionConfigBooleanOption)
            .currentValue,
        isFalse,
      );

      expect(await harness.notifier.sendPrompt('all-updates'), isTrue);

      final session = harness.connected.activeSession!;
      expect(session.modes?.currentModeId, 'plan');
      expect(session.modes?.availableModes.map((mode) => mode.id), [
        'code',
        'plan',
      ]);
      expect(
        (session.configOptions.single as SessionConfigBooleanOption)
            .currentValue,
        isTrue,
      );
      expect(session.plan?.entries.single.content, 'Inspect project');
      expect(session.plan?.entries.single.status, PlanEntryStatus.completed);
      expect(session.availableCommands.single.name, 'inspect');
      expect(session.title, 'Validated session');
      expect(session.updatedAt, '2026-08-09T12:00:00Z');
      expect(session.usage?.used, 120);
      expect(session.usage?.size, 4096);
      expect(session.usage?.cost?.amount, 0.02);
      expect(session.usage?.cost?.currency, 'USD');
      expect(session.toolCalls['all-tool']?.title, 'Inspect project');
      expect(session.toolCalls['all-tool']?.status, ToolCallStatus.completed);
      expect(session.toolCalls['all-tool']?.rawOutput, {'files': 3});

      expect(session.messages.first.messageId, 'user-canonical');
      expect(session.messages.first.text, 'Canonical user prompt');
      final assistant = session.messages.singleWhere(
        (message) => message.messageId == 'all-updates-result',
      );
      expect(assistant.text, 'All updates complete');
      expect(assistant.thoughts, ['Inspecting state']);
      expect(assistant.toolCallIds, ['all-tool']);
      expect(assistant.isStreaming, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'real ACP agent completes authentication and session lifecycle controls',
    () async {
      final harness = await _AcpAgentHarness.start(
        agentArgs: const ['--full-lifecycle'],
        requireActiveSession: false,
      );
      addTearDown(harness.dispose);

      var connected = harness.connected;
      expect(connected.activeSession, isNull);
      expect(connected.authStatus, AcpAuthStatus.required);
      expect(connected.authMethods.map((method) => method.id), ['local-auth']);
      expect(await harness.notifier.authenticate('unknown'), isFalse);
      expect(connected.activeSession, isNull);

      expect(await harness.notifier.authenticate('local-auth'), isTrue);
      connected = harness.connected;
      expect(connected.authStatus, AcpAuthStatus.authenticated);
      expect(connected.activeSession?.sessionId, 'lifecycle-1');

      expect(await harness.notifier.setMode('plan'), isTrue);
      expect(harness.connected.activeSession?.modes?.currentModeId, 'plan');
      expect(await harness.notifier.setConfigOption('verbose', true), isTrue);
      expect(
        await harness.notifier.setConfigOption('model', 'accurate'),
        isTrue,
      );
      final configured = harness.connected.activeSession!.configOptions;
      expect(
        (configured.whereType<SessionConfigBooleanOption>().single)
            .currentValue,
        isTrue,
      );
      expect(
        (configured.whereType<SessionConfigSelectOptionValue>().single)
            .currentValue,
        'accurate',
      );

      expect(await harness.notifier.refreshSessions(), isTrue);
      connected = harness.connected;
      expect(connected.recentSessions, hasLength(2));
      expect(connected.nextSessionCursor, 'page-2');
      expect(await harness.notifier.loadMoreSessions(), isTrue);
      connected = harness.connected;
      expect(connected.recentSessions, hasLength(4));
      expect(connected.nextSessionCursor, isNull);

      final archived1 = connected.recentSessions.singleWhere(
        (session) => session.sessionId == 'archived-1',
      );
      final archived2 = connected.recentSessions.singleWhere(
        (session) => session.sessionId == 'archived-2',
      );
      expect(await harness.notifier.loadSession(archived1), isTrue);
      expect(harness.connected.activeSession?.sessionId, 'archived-1');
      expect(await harness.notifier.resumeSession(archived2), isTrue);
      expect(harness.connected.activeSession?.sessionId, 'archived-2');
      expect(await harness.notifier.closeSession(), isTrue);
      expect(harness.connected.activeSession, isNull);

      expect(await harness.notifier.createSession(), isTrue);
      expect(harness.connected.activeSession?.sessionId, 'lifecycle-2');
      expect(await harness.notifier.deleteSession('archived-3'), isTrue);
      expect(
        harness.connected.recentSessions.any(
          (session) => session.sessionId == 'archived-3',
        ),
        isFalse,
      );

      expect(await harness.notifier.logout(), isTrue);
      connected = harness.connected;
      expect(connected.activeSession, isNull);
      expect(connected.authStatus, AcpAuthStatus.available);

      expect(await harness.notifier.authenticate('local-auth'), isTrue);
      connected = harness.connected;
      expect(connected.authStatus, AcpAuthStatus.authenticated);
      expect(connected.activeSession?.sessionId, 'lifecycle-3');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('real ACP agent accepts every supported prompt content type', () async {
    final harness = await _AcpAgentHarness.start();
    addTearDown(harness.dispose);
    final encoded = base64Encode(const [1, 2, 3, 4]);

    expect(
      await harness.notifier.sendPromptContent([
        const TextContentBlock(text: 'all-content-types'),
        ImageContent(data: encoded, mimeType: 'image/png'),
        AudioContent(data: encoded, mimeType: 'audio/wav'),
        const ResourceLink(
          name: 'documentation',
          uri: 'https://example.test/docs',
        ),
        const EmbeddedResource(
          resource: TextResourceContents(
            text: 'embedded text',
            uri: 'file:///project/context.txt',
            mimeType: 'text/plain',
          ),
        ),
        EmbeddedResource(
          resource: BlobResourceContents(
            blob: encoded,
            uri: 'file:///project/context.bin',
            mimeType: 'application/octet-stream',
          ),
        ),
      ]),
      isTrue,
    );
    expect(harness.connected.lastError, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'prompt validation rejects unsupported, malformed, and oversized input',
    () async {
      final limited = await _AcpAgentHarness.start(
        agentArgs: const ['--limited-prompts'],
      );
      addTearDown(limited.dispose);
      final encoded = base64Encode(const [1]);

      expect(
        await limited.notifier.sendPromptContent([
          ImageContent(data: encoded, mimeType: 'image/png'),
        ]),
        isFalse,
      );
      expect(limited.connected.lastError, contains('image prompts'));
      expect(
        await limited.notifier.sendPromptContent([
          AudioContent(data: encoded, mimeType: 'audio/wav'),
        ]),
        isFalse,
      );
      expect(limited.connected.lastError, contains('audio prompts'));
      expect(
        await limited.notifier.sendPromptContent([
          const EmbeddedResource(
            resource: TextResourceContents(
              text: 'context',
              uri: 'file:///context.txt',
            ),
          ),
        ]),
        isFalse,
      );
      expect(limited.connected.lastError, contains('embedded context'));

      final full = await _AcpAgentHarness.start();
      addTearDown(full.dispose);
      expect(
        await full.notifier.sendPromptContent(const [
          ImageContent(data: 'not-base64!', mimeType: 'image/png'),
        ]),
        isFalse,
      );
      expect(full.connected.lastError, contains('valid image MIME type'));
      expect(
        await full.notifier.sendPromptContent(const [
          ResourceLink(name: 'relative', uri: 'docs/readme.md'),
        ]),
        isFalse,
      );
      expect(full.connected.lastError, contains('absolute URI'));

      expect(
        await full.notifier.sendPrompt('recover-after-validation-error'),
        isTrue,
      );
      expect(full.connected.lastError, isNull);

      final oversizedBase64 = 'A' * (14 * 1024 * 1024);
      expect(
        await full.notifier.sendPromptContent([
          ImageContent(data: oversizedBase64, mimeType: 'image/png'),
        ]),
        isFalse,
      );
      expect(full.connected.lastError, contains('payload limit is 14.0 MiB'));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'agent process exit surfaces an error and the same notifier reconnects',
    () async {
      final harness = await _AcpAgentHarness.start();
      addTearDown(harness.dispose);

      final errorFuture = harness.waitForState<AcpError>();
      expect(await harness.notifier.sendPrompt('exit-agent'), isTrue);
      final failed = await errorFuture;
      expect(failed.message, contains('closed unexpectedly'));

      await harness.connect();
      expect(harness.connected.activeSession, isNotNull);
      expect(await harness.notifier.sendPrompt('after-reconnect'), isTrue);
      expect(harness.connected.messages.last.text, 'Second message');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'failed initial session creation keeps the connection recoverable',
    () async {
      final harness = await _AcpAgentHarness.start(
        agentArgs: const ['--fail-first-new-session'],
        requireActiveSession: false,
      );
      addTearDown(harness.dispose);

      var connected = harness.connected;
      expect(connected.activeSession, isNull);
      expect(
        connected.lastError,
        contains('Fixture rejected the first session creation'),
      );

      expect(await harness.notifier.createSession(), isTrue);
      connected = harness.connected;
      expect(connected.activeSession, isNotNull);
      expect(connected.lastError, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'failed session load preserves the active session and its messages',
    () async {
      final harness = await _AcpAgentHarness.start(
        agentArgs: const ['--full-lifecycle'],
        requireActiveSession: false,
      );
      addTearDown(harness.dispose);
      expect(await harness.notifier.authenticate('local-auth'), isTrue);
      expect(await harness.notifier.sendPrompt('before-failed-load'), isTrue);

      final before = harness.connected.activeSession!;
      final messages = before.messages;
      expect(
        await harness.notifier.loadSession(
          SessionInfo(
            sessionId: 'missing-session',
            cwd: before.cwd,
            additionalDirectories: before.additionalDirectories,
          ),
        ),
        isFalse,
      );

      final after = harness.connected;
      expect(after.activeSession?.sessionId, before.sessionId);
      expect(after.messages, same(messages));
      expect(after.lastError, contains('Unknown session'));
      expect(await harness.notifier.sendPrompt('after-failed-load'), isTrue);
      expect(harness.connected.lastError, isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'permission cancellation completes the turn without leaving a blocker',
    () async {
      final harness = await _AcpAgentHarness.start();
      addTearDown(harness.dispose);

      final prompt = harness.notifier.sendPrompt('request-permission');
      final awaitingPermission = await harness.waitFor(
        (state) => state.pendingPermission != null,
      );
      final permission = awaitingPermission.pendingPermission!;
      expect(
        harness.notifier.respondToPermission(requestId: permission.requestId),
        isTrue,
      );
      expect(await prompt, isTrue);

      final connected = harness.connected;
      expect(connected.pendingPermission, isNull);
      expect(connected.isPrompting, isFalse);
      expect(connected.messages.last.text, 'permission:cancelled');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'switching sessions clears old conversation and remains usable',
    () async {
      final harness = await _AcpAgentHarness.start(
        agentArgs: const ['--full-lifecycle'],
        requireActiveSession: false,
      );
      addTearDown(harness.dispose);
      expect(await harness.notifier.authenticate('local-auth'), isTrue);
      expect(await harness.notifier.sendPrompt('before-switch'), isTrue);
      expect(harness.connected.messages, isNotEmpty);
      expect(await harness.notifier.refreshSessions(), isTrue);
      final archived = harness.connected.recentSessions.singleWhere(
        (session) => session.sessionId == 'archived-1',
      );

      expect(await harness.notifier.loadSession(archived), isTrue);
      expect(harness.connected.activeSession?.sessionId, 'archived-1');
      expect(harness.connected.messages, isEmpty);
      expect(await harness.notifier.sendPrompt('after-switch'), isTrue);
      expect(harness.connected.messages.last.text, 'Second message');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

final class _AcpAgentHarness {
  _AcpAgentHarness._(
    this.container,
    this.notifier,
    this.packageDirectory,
    this.sessionCwd,
  );

  final ProviderContainer container;
  final AcpAgentNotifier notifier;
  final String packageDirectory;
  final String sessionCwd;

  static Future<_AcpAgentHarness> start({
    String sessionCwd = '.',
    List<String> agentArgs = const [],
    bool requireActiveSession = true,
  }) async {
    final currentDirectory = Directory.current.path;
    final packageDirectory = p.basename(currentDirectory) == 'cockpit_console'
        ? currentDirectory
        : p.join(currentDirectory, 'packages', 'cockpit_console');
    final container = ProviderContainer();
    final notifier = container.read(acpAgentProvider.notifier);
    final harness = _AcpAgentHarness._(
      container,
      notifier,
      packageDirectory,
      sessionCwd,
    );
    try {
      await harness.connect(agentArgs: agentArgs);
      final connectionState = container.read(acpAgentProvider);
      expect(
        connectionState,
        isA<AcpConnected>(),
        reason: connectionState is AcpError ? connectionState.message : null,
      );
      if (requireActiveSession) {
        expect(
          (connectionState as AcpConnected).activeSession,
          isNotNull,
          reason: connectionState.lastError,
        );
      }
      return harness;
    } on Object {
      await harness.dispose();
      rethrow;
    }
  }

  Future<void> connect({List<String> agentArgs = const []}) {
    return notifier.connect(
      AcpConnectionConfig(
        command: Platform.isWindows ? 'dart.exe' : 'dart',
        args: [
          'run',
          'test/fixtures/acp_message_stream_agent.dart',
          ...agentArgs,
        ],
        workingDirectory: packageDirectory,
        sessionCwd: sessionCwd,
      ),
    );
  }

  AcpConnected get connected {
    final current = container.read(acpAgentProvider);
    if (current case final AcpConnected connected) return connected;
    throw StateError('Expected AcpConnected, got $current.');
  }

  Future<AcpConnected> waitFor(
    bool Function(AcpConnected state) predicate, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final current = container.read(acpAgentProvider);
    if (current is AcpConnected && predicate(current)) return current;

    final result = Completer<AcpConnected>();
    final subscription = container.listen<AcpAgentState>(acpAgentProvider, (
      previous,
      next,
    ) {
      if (next is AcpError && !result.isCompleted) {
        result.completeError(StateError(next.message));
      } else if (next is AcpConnected &&
          predicate(next) &&
          !result.isCompleted) {
        result.complete(next);
      }
    });
    try {
      return await result.future.timeout(timeout);
    } finally {
      subscription.close();
    }
  }

  Future<T> waitForState<T extends AcpAgentState>({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final current = container.read(acpAgentProvider);
    if (current is T) return current;

    final result = Completer<T>();
    final subscription = container.listen<AcpAgentState>(acpAgentProvider, (
      previous,
      next,
    ) {
      if (next is T && !result.isCompleted) result.complete(next);
    });
    try {
      return await result.future.timeout(timeout);
    } finally {
      subscription.close();
    }
  }

  Future<void> dispose() async {
    await notifier.disconnect();
    container.dispose();
  }
}
