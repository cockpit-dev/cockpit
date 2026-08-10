import 'dart:convert';
import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:cockpit_console/src/providers/acp_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AcpPermissionPrompt', () {
    test('exposes toolCall and immutable options', () {
      const toolCall = AcpToolCallState(
        toolCallId: 'tc-1',
        title: 'Run command',
      );
      const options = [
        PermissionOption(
          optionId: 'allow',
          name: 'Allow',
          kind: PermissionOptionKind.allowOnce,
        ),
        PermissionOption(
          optionId: 'deny',
          name: 'Deny',
          kind: PermissionOptionKind.rejectOnce,
        ),
      ];

      const prompt = AcpPermissionPrompt(
        requestId: 'permission-1',
        toolCall: toolCall,
        options: options,
      );

      expect(prompt.toolCall.toolCallId, 'tc-1');
      expect(prompt.options.length, 2);
      expect(prompt.options.first.optionId, 'allow');
      expect(
        prompt.acceptsDecision(requestId: 'permission-1', optionId: 'allow'),
        isTrue,
      );
      expect(
        prompt.acceptsDecision(
          requestId: 'permission-stale',
          optionId: 'allow',
        ),
        isFalse,
      );
      expect(
        prompt.acceptsDecision(
          requestId: 'permission-1',
          optionId: 'not-offered',
        ),
        isFalse,
      );
    });
  });

  group('AcpConnected contract', () {
    const state = AcpConnected(
      agentInfo: Implementation(name: 'test', version: '1.0'),
      protocolVersion: ProtocolVersion.v1,
      capabilities: AgentCapabilities(),
      activeSession: AcpSessionState(sessionId: 's1', cwd: '/tmp'),
    );

    test('messages defaults to empty', () {
      expect(state.messages, isEmpty);
    });

    test('pendingPermission defaults to null', () {
      expect(state.pendingPermission, isNull);
    });

    test('isPrompting defaults to false', () {
      expect(state.isPrompting, isFalse);
    });
  });

  group('AcpToolCallState', () {
    test(
      'preserves arbitrary JSON raw values and explicit collection clears',
      () {
        final state = AcpToolCallState.fromToolCall(
          const ToolCall(
            toolCallId: 'tool-1',
            title: 'Run command',
            status: ToolCallStatus.inProgress,
            content: [
              ToolCallContentBlock(content: TextContentBlock(text: 'running')),
            ],
            rawInput: {
              'command': 'dart',
              'args': ['test'],
            },
          ),
        );

        final merged = state.merge(
          const ToolCallUpdate(
            toolCallId: 'tool-1',
            status: ToolCallStatus.completed,
            content: [],
            rawOutput: {'exitCode': 0, 'passed': true},
          ),
        );

        expect(merged.content, isEmpty);
        expect(merged.rawInput, {
          'command': 'dart',
          'args': ['test'],
        });
        expect(merged.rawOutput, {'exitCode': 0, 'passed': true});
      },
    );

    test('omitted status preserves the current tool-call status', () {
      const state = AcpToolCallState(
        toolCallId: 'tool-1',
        title: 'Run command',
        status: ToolCallStatus.inProgress,
      );

      final omitted = ToolCallUpdate.fromJson({'toolCallId': 'tool-1'});
      final preserved = state.merge(omitted);
      final completed = preserved.merge(
        const ToolCallUpdate(
          toolCallId: 'tool-1',
          status: ToolCallStatus.completed,
        ),
      );

      expect(omitted.status, isNull);
      expect(preserved.status, ToolCallStatus.inProgress);
      expect(completed.status, ToolCallStatus.completed);
    });
  });

  group('applyLineLimit', () {
    test('full content when no line/limit', () {
      expect(applyLineLimit('a\nb\nc', null, null), 'a\nb\nc');
    });

    test('1-based line starts at correct offset', () {
      expect(applyLineLimit('a\nb\nc', 1, null), 'a\nb\nc');
      expect(applyLineLimit('a\nb\nc', 2, null), 'b\nc');
      expect(applyLineLimit('a\nb\nc', 3, null), 'c');
    });

    test('limit returns N lines from start position', () {
      expect(applyLineLimit('a\nb\nc\nd', null, 2), 'a\nb');
    });

    test('line + limit slices correctly', () {
      expect(applyLineLimit('a\nb\nc\nd', 2, 2), 'b\nc');
    });

    test('line beyond content returns empty', () {
      expect(applyLineLimit('a\nb', 10, null), '');
    });

    test('limit beyond content clamps to content length', () {
      expect(applyLineLimit('a\nb', null, 100), 'a\nb');
    });

    test('single-line content', () {
      expect(applyLineLimit('hello', 1, 1), 'hello');
    });

    test('line 1 limit 1 returns first line only', () {
      expect(applyLineLimit('a\nb\nc', 1, 1), 'a');
    });
  });

  group('confinePathToRoot', () {
    late Directory tempRoot;

    setUp(() async {
      final raw = await Directory.systemTemp.createTemp('acp_confine_');
      // Canonicalize (macOS /tmp → /private/tmp) to match provider behavior
      // where _sessionRootCanonical is set via resolveSymbolicLinksSync.
      tempRoot = Directory(raw.resolveSymbolicLinksSync());
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('relative path resolves within root', () {
      final result = confinePathToRoot('file.txt', tempRoot.path);
      expect(result, p.join(tempRoot.path, 'file.txt'));
    });

    test('nested relative path resolves within root', () async {
      Directory(p.join(tempRoot.path, 'sub')).createSync();
      final result = confinePathToRoot('sub/file.txt', tempRoot.path);
      expect(result, p.join(tempRoot.path, 'sub', 'file.txt'));
    });

    test('absolute path within root resolves correctly', () async {
      final file = File(p.join(tempRoot.path, 'existing.txt'));
      await file.writeAsString('content');
      final result = confinePathToRoot(file.path, tempRoot.path);
      expect(result, file.resolveSymbolicLinksSync());
    });

    test('path traversal with .. is rejected', () {
      expect(
        () => confinePathToRoot('../../etc/passwd', tempRoot.path),
        throwsA(isA<AcpPathEscapeException>()),
      );
    });

    test('symlink escape is rejected', () async {
      final outsideDir = await Directory.systemTemp.createTemp('acp_outside_');
      addTearDown(() => outsideDir.delete(recursive: true));

      final outsideFile = File(p.join(outsideDir.path, 'secret.txt'));
      await outsideFile.writeAsString('secret');

      final link = Link(p.join(tempRoot.path, 'escape'));
      await link.create(outsideFile.path);

      expect(
        () => confinePathToRoot('escape', tempRoot.path),
        throwsA(isA<AcpPathEscapeException>()),
      );
    });

    test('symlink within root is allowed', () async {
      final realFile = File(p.join(tempRoot.path, 'real.txt'));
      await realFile.writeAsString('content');

      final subDir = Directory(p.join(tempRoot.path, 'sub'));
      await subDir.create();

      final link = Link(p.join(subDir.path, 'link.txt'));
      await link.create(realFile.path);

      final result = confinePathToRoot('sub/link.txt', tempRoot.path);
      expect(result, realFile.resolveSymbolicLinksSync());
    });

    test('not-yet-existing path for write resolves parent', () {
      final result = confinePathToRoot('newdir/newfile.txt', tempRoot.path);
      expect(result, p.join(tempRoot.path, 'newdir', 'newfile.txt'));
    });

    test('deeply nested not-yet-existing path normalizes safely', () {
      final result = confinePathToRoot('a/b/c/file.txt', tempRoot.path);
      expect(result, p.join(tempRoot.path, 'a', 'b', 'c', 'file.txt'));
    });

    test('root itself is allowed', () {
      final result = confinePathToRoot('.', tempRoot.path);
      expect(result, tempRoot.path);
    });

    test('absolute path outside root is rejected', () {
      expect(
        () => confinePathToRoot('/etc/passwd', tempRoot.path),
        throwsA(isA<AcpPathEscapeException>()),
      );
    });
  });

  group('provider state transitions (disconnected)', () {
    test('initial state is AcpDisconnected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(acpAgentProvider), isA<AcpDisconnected>());
    });

    test('clearMessages is no-op when disconnected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(acpAgentProvider.notifier).clearMessages();
      expect(container.read(acpAgentProvider), isA<AcpDisconnected>());
    });

    test('cancelTurn is no-op when disconnected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(acpAgentProvider.notifier).cancelTurn();
      expect(container.read(acpAgentProvider), isA<AcpDisconnected>());
    });

    test('respondToPermission is no-op when disconnected', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container
            .read(acpAgentProvider.notifier)
            .respondToPermission(requestId: 'missing'),
        isFalse,
      );
      expect(container.read(acpAgentProvider), isA<AcpDisconnected>());
    });

    test('sendPrompt is no-op when disconnected', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dispatched = await container
          .read(acpAgentProvider.notifier)
          .sendPrompt('hello');
      expect(dispatched, isFalse);
      expect(container.read(acpAgentProvider), isA<AcpDisconnected>());
    });
  });

  group('resolveAcpSessionRoot', () {
    test('resolves a relative session root against the launch directory', () {
      final root = Directory.systemTemp.createTempSync('acp_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      final project = Directory(p.join(root.path, 'project'))..createSync();

      final resolved = resolveAcpSessionRoot(
        AcpConnectionConfig(
          command: 'agent',
          workingDirectory: root.path,
          sessionCwd: 'project',
        ),
      );

      expect(resolved, project.resolveSymbolicLinksSync());
    });

    test('canonicalizes and deduplicates additional directories', () {
      final root = Directory.systemTemp.createTempSync('acp_roots_');
      addTearDown(() => root.deleteSync(recursive: true));
      final project = Directory(p.join(root.path, 'project'))..createSync();
      final sibling = Directory(p.join(root.path, 'shared'))..createSync();
      final config = AcpConnectionConfig(
        command: 'agent',
        workingDirectory: root.path,
        sessionCwd: project.path,
        additionalDirectories: [sibling.path, sibling.path, project.path],
      );

      expect(
        resolveAcpAdditionalDirectories(
          config,
          project.resolveSymbolicLinksSync(),
        ),
        [sibling.resolveSymbolicLinksSync()],
      );
    });
  });

  group('bounded ACP file IO', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('acp_file_io_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('preserves complete content below the byte ceiling', () async {
      final file = File(p.join(root.path, 'input.txt'));
      await file.writeAsString('a\nb\n');

      expect(await readAcpTextFile(file), 'a\nb\n');
    });

    test('streams only the requested line range', () async {
      final file = File(p.join(root.path, 'input.txt'));
      await file.writeAsString('a\nb\nc\nd');

      expect(await readAcpTextFile(file, line: 2, limit: 2), 'b\nc');
    });

    test('rejects a response beyond the client ceiling', () async {
      final file = File(p.join(root.path, 'large.txt'));
      await file.writeAsString('12345');

      await expectLater(
        readAcpTextFile(file, maximumResponseBytes: 4, maximumScanBytes: 8),
        throwsA(anything),
      );
    });

    test('honors cancellation before reading', () async {
      final file = File(p.join(root.path, 'input.txt'));
      await file.writeAsString('content');

      await expectLater(
        readAcpTextFile(file, isCancelled: () => true),
        throwsA(anything),
      );
    });

    test('atomic write replaces the destination only on commit', () async {
      final file = File(p.join(root.path, 'output.txt'));
      await file.writeAsString('old');

      await writeAcpTextFileAtomically(file, 'new');

      expect(await file.readAsString(), 'new');
    });

    test('cancelled atomic write preserves the destination', () async {
      final file = File(p.join(root.path, 'output.txt'));
      await file.writeAsString('old');

      await expectLater(
        writeAcpTextFileAtomically(file, 'new', isCancelled: () => true),
        throwsA(anything),
      );
      expect(await file.readAsString(), 'old');
    });

    test('atomic write rejects a payload above the byte ceiling', () async {
      final file = File(p.join(root.path, 'output.txt'));
      await file.writeAsString('old');

      await expectLater(
        writeAcpTextFileAtomically(file, 'new', maximumWriteBytes: 2),
        throwsA(isA<Object>()),
      );
      // Destination is untouched when the ceiling is exceeded.
      expect(await file.readAsString(), 'old');
    });

    test('atomic write rejects a negative ceiling argument', () {
      final file = File(p.join(root.path, 'output.txt'));
      expect(
        () => writeAcpTextFileAtomically(file, 'x', maximumWriteBytes: -1),
        throwsArgumentError,
      );
    });
  });

  group('AcpTerminalOutputBuffer', () {
    test('retains unbounded output when no peer limit is supplied', () {
      final buffer = AcpTerminalOutputBuffer(null)
        ..add(utf8.encode('hello'))
        ..add(utf8.encode(' world'));

      expect(buffer.text, 'hello world');
      expect(buffer.truncated, isFalse);
      expect(buffer.retainedByteCount, 11);
    });

    test('does not report truncation at the exact limit', () {
      final buffer = AcpTerminalOutputBuffer(5)..add(utf8.encode('hello'));

      expect(buffer.text, 'hello');
      expect(buffer.truncated, isFalse);
    });

    test('retains the most recent bytes when output exceeds the limit', () {
      final buffer = AcpTerminalOutputBuffer(5)
        ..add(utf8.encode('hello world'));

      expect(buffer.text, 'world');
      expect(buffer.truncated, isTrue);
      expect(buffer.retainedByteCount, 5);
    });

    test('later chunks replace older retained output', () {
      final buffer = AcpTerminalOutputBuffer(5)
        ..add(utf8.encode('hi'))
        ..add(utf8.encode('overflow!!!'));

      expect(buffer.text, 'ow!!!');
      expect(buffer.truncated, isTrue);
      expect(buffer.retainedByteCount, 5);
    });

    test('zero limit retains nothing and reports truncation', () {
      final buffer = AcpTerminalOutputBuffer(0)..add(utf8.encode('output'));

      expect(buffer.text, isEmpty);
      expect(buffer.truncated, isTrue);
      expect(buffer.retainedByteCount, 0);
    });

    test('preserves complete UTF-8 characters at the tail boundary', () {
      final buffer = AcpTerminalOutputBuffer(4)
        ..add(utf8.encode('A€'))
        ..add(utf8.encode('B'));

      expect(buffer.text, '€B');
      expect(buffer.truncated, isTrue);
      expect(buffer.retainedByteCount, 4);
    });

    test('drops orphaned UTF-8 continuation bytes', () {
      final buffer = AcpTerminalOutputBuffer(2)..add(utf8.encode('A€'));

      expect(buffer.text, isEmpty);
      expect(buffer.truncated, isTrue);
      expect(buffer.retainedByteCount, 0);
    });

    test('rejects a negative limit', () {
      expect(() => AcpTerminalOutputBuffer(-1), throwsArgumentError);
    });
  });

  group('describeAcpConnectionError', () {
    test('returns the base message when stderr is empty', () {
      expect(describeAcpConnectionError('closed', StringBuffer()), 'closed');
    });

    test('appends trimmed stderr tail when present', () {
      expect(
        describeAcpConnectionError('closed', StringBuffer('boom\n')),
        'closed\n\nAgent stderr:\nboom',
      );
    });

    test('omits whitespace-only stderr', () {
      expect(
        describeAcpConnectionError('closed', StringBuffer('  \n ')),
        'closed',
      );
    });
  });
}
