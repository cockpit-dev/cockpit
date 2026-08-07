import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:acpd/acpd.dart';
import 'package:acpd_io/acpd_io.dart' as acpd_io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

const _maximumConcurrentTerminals = 8;
const _maximumTerminalOutputBytes = 1024 * 1024;
const _maximumFileResponseBytes = 4 * 1024 * 1024;
const _maximumFileScanBytes = 64 * 1024 * 1024;
const _maximumFileWriteBytes = 16 * 1024 * 1024;

/// Bounds the retained agent stderr tail surfaced in connection-failure
/// messages. The acpd_io transport already caps captured stderr at 64 KiB;
/// this keeps only the most recent slice so error strings stay readable.
const _maximumAgentStderrChars = 2048;

/// User-facing configuration for connecting to an ACP agent.
final class AcpConnectionConfig {
  const AcpConnectionConfig({
    required this.command,
    this.args = const [],
    this.env = const {},
    this.workingDirectory,
    this.clientName = 'cockpit-console',
    this.clientVersion = '0.1.0',
    this.sessionCwd = '.',
  });

  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String? workingDirectory;
  final String clientName;
  final String clientVersion;
  final String sessionCwd;

  acpd_io.AcpAgentConfig toSdkConfig({String? resolvedWorkingDirectory}) =>
      acpd_io.AcpAgentConfig(
        command: command,
        args: args,
        env: env,
        workingDirectory: resolvedWorkingDirectory ?? workingDirectory,
      );
}

@visibleForTesting
String resolveAcpSessionRoot(AcpConnectionConfig config) {
  final launchDirectory = config.workingDirectory == null
      ? Directory.current.path
      : p.absolute(config.workingDirectory!);
  final canonicalLaunchDirectory = Directory(
    launchDirectory,
  ).resolveSymbolicLinksSync();
  final requestedSessionRoot = p.isAbsolute(config.sessionCwd)
      ? config.sessionCwd
      : p.join(canonicalLaunchDirectory, config.sessionCwd);
  return Directory(requestedSessionRoot).resolveSymbolicLinksSync();
}

/// A chat message in the ACP conversation.
final class AcpChatMessage {
  const AcpChatMessage({
    required this.role,
    required this.text,
    this.isStreaming = false,
    this.thoughts = const [],
    this.toolCalls = const [],
  });

  final AcpMessageRole role;
  final String text;
  final bool isStreaming;
  final List<String> thoughts;
  final List<String> toolCalls;

  AcpChatMessage copyWith({
    String? text,
    bool? isStreaming,
    List<String>? thoughts,
    List<String>? toolCalls,
  }) {
    return AcpChatMessage(
      role: role,
      text: text ?? this.text,
      isStreaming: isStreaming ?? this.isStreaming,
      thoughts: thoughts ?? this.thoughts,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }
}

enum AcpMessageRole { user, assistant, error }

/// A permission request surfaced to the user for interactive approval.
///
/// Exposes the ACP [ToolCall] that requires approval and the immutable set of
/// [options] the agent offered. Resolved via
/// [AcpAgentNotifier.respondToPermission].
final class AcpPermissionPrompt {
  const AcpPermissionPrompt({
    required this.requestId,
    required this.toolCall,
    required this.options,
  });

  /// Stable identity binding a UI decision to this exact queued request.
  final String requestId;

  /// The tool call that needs permission.
  final ToolCall toolCall;

  /// The permission options offered by the agent (immutable).
  final List<PermissionOption> options;
  bool acceptsDecision({required String requestId, String? optionId}) =>
      this.requestId == requestId &&
      (optionId == null ||
          options.any((option) => option.optionId == optionId));
}

/// State of the ACP agent connection.
sealed class AcpAgentState {
  const AcpAgentState();
}

final class AcpDisconnected extends AcpAgentState {
  const AcpDisconnected();
}

final class AcpConnecting extends AcpAgentState {
  const AcpConnecting();
}

final class AcpConnected extends AcpAgentState {
  const AcpConnected({
    required this.agentInfo,
    required this.sessionId,
    required this.modes,
    this.messages = const [],
    this.pendingPermission,
    this.isPrompting = false,
  });

  final Implementation agentInfo;
  final String sessionId;
  final List<SessionMode> modes;

  /// Reactive, immutable list of chat messages. The UI rebuilds on every
  /// streaming chunk, completion, error, and clear transition.
  final List<AcpChatMessage> messages;

  /// The head of the permission queue awaiting user response, or null if no
  /// permission request is pending.
  final AcpPermissionPrompt? pendingPermission;

  /// Whether a prompt turn is currently in flight.
  ///
  /// This is the single source of truth for send/stop/concurrency. It is true
  /// for the entire turn — from dispatch through completion, error, or cancel —
  /// so the UI can disable the composer and show a Stop button while preventing
  /// a second concurrent turn.
  final bool isPrompting;
}

final class AcpError extends AcpAgentState {
  const AcpError(this.message);
  final String message;
}

/// Exception for path-confinement violations.
class AcpPathEscapeException implements Exception {
  const AcpPathEscapeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Notifier managing the full ACP agent lifecycle.
///
/// Handles all client-side ACP protocol obligations:
/// - `initialize` handshake with client capability advertisement (fs + terminal)
/// - `session/new` creation
/// - `session/prompt` with streaming `session/update` collection (reactive)
/// - `session/request_permission` — cancellable FIFO permission queue
/// - `session/request_cancel`
/// - `fs/read_text_file` — canonical session-root confinement including
///   symlink escapes, correct 1-based `line`/`limit`
/// - `fs/write_text_file` — canonical session-root confinement
/// - `terminal/*` — direct process execution, requested environment,
///   root-confined cwd, byte limit with truthful truncation, real exit status,
///   complete async resource cleanup
/// - All 11 `session/update` variants
///
/// Every agent-to-client callback validates the active session ID so
/// cross-session traffic cannot leak. `session/update` notifications are
/// additionally filtered by session ID.
///
/// Supports any agent that implements ACP over stdio.
final class AcpAgentNotifier extends Notifier<AcpAgentState> {
  acpd_io.AcpAgent? _agentProcess;
  ClientConnection? _client;
  Session? _session;

  /// Canonical absolute path of the session root, cached for confinement
  /// checks. Null when not connected.
  String? _sessionRootCanonical;

  // Mutable working state — published to the UI through immutable copies.
  final List<AcpChatMessage> _messages = [];
  final Map<String, _ManagedTerminal> _terminals = {};

  /// FIFO queue of pending permission requests awaiting user interaction.
  final List<_PendingPermission> _permissionQueue = [];

  /// Guard preventing overlapping prompt turns.
  bool _isPrompting = false;
  _ActiveTurn? _activeTurn;
  int _lifecycleGeneration = 0;
  int _permissionCounter = 0;

  /// Bounded tail of the agent process's stderr, retained so connection
  /// failures can report *why* the agent died instead of a generic message.
  final StringBuffer _agentStderr = StringBuffer();
  StreamSubscription<String>? _stderrSub;

  @override
  AcpAgentState build() {
    ref.onDispose(_cleanupSync);
    return const AcpDisconnected();
  }

  // ===========================================================================
  // Connection lifecycle
  // ===========================================================================

  /// Connects to an agent, advertises client capabilities, and creates a
  /// session. On failure, cleans up all partial transport/process resources.
  Future<void> connect(AcpConnectionConfig config) async {
    final generation = ++_lifecycleGeneration;
    state = const AcpConnecting();
    await _cleanup();
    if (generation != _lifecycleGeneration) return;

    acpd_io.AcpAgent? agent;
    ClientConnection? client;
    Session? session;

    try {
      final sessionRoot = resolveAcpSessionRoot(config);
      final launchDirectory = config.workingDirectory == null
          ? null
          : Directory(
              p.absolute(config.workingDirectory!),
            ).resolveSymbolicLinksSync();
      agent = await acpd_io.AcpAgent.start(
        config.toSdkConfig(resolvedWorkingDirectory: launchDirectory),
      );
      _stderrSub = agent.stderr.listen(_appendAgentStderr);
      if (generation != _lifecycleGeneration) {
        await _closeConnectionAttempt(agent: agent);
        return;
      }

      client = _buildClientRole().connect(agent.transport);
      final initResp = await client.client.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.v1,
          clientInfo: Implementation(
            name: config.clientName,
            version: config.clientVersion,
          ),
          clientCapabilities: const ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: true,
          ),
        ),
      );
      if (generation != _lifecycleGeneration) {
        await _closeConnectionAttempt(agent: agent, client: client);
        return;
      }

      session = await Session.create(
        client,
        NewSessionRequest(cwd: sessionRoot, mcpServers: const []),
      );
      if (generation != _lifecycleGeneration) {
        await _closeConnectionAttempt(
          agent: agent,
          client: client,
          session: session,
        );
        return;
      }

      _sessionRootCanonical = sessionRoot;
      _agentProcess = agent;
      _client = client;
      _session = session;
      _messages.clear();
      _permissionQueue.clear();
      _terminals.clear();
      _activeTurn = null;
      _isPrompting = false;

      unawaited(
        client.closed.then(
          (_) => _handleUnexpectedConnectionClose(generation, client!),
        ),
      );
      state = AcpConnected(
        agentInfo:
            initResp.agentInfo ??
            Implementation(name: config.command, version: 'unknown'),
        sessionId: session.sessionId,
        modes: session.modes?.availableModes ?? const [],
        messages: const [],
        pendingPermission: null,
        isPrompting: false,
      );
    } on Object catch (error) {
      await _stderrSub?.cancel();
      _stderrSub = null;
      await _closeConnectionAttempt(
        agent: agent,
        client: client,
        session: session,
      );
      if (generation == _lifecycleGeneration) {
        _sessionRootCanonical = null;
        state = AcpError(describeAcpConnectionError('$error', _agentStderr));
      }
    }
  }

  Future<void> _handleUnexpectedConnectionClose(
    int generation,
    ClientConnection client,
  ) async {
    if (generation != _lifecycleGeneration || !identical(_client, client)) {
      return;
    }
    // Capture the stderr tail before _cleanup clears the buffer, so the
    // error message the user sees actually explains why the agent died.
    final stderrTail = StringBuffer()..write(_agentStderr.toString());
    final failureGeneration = ++_lifecycleGeneration;
    await _cleanup();
    if (failureGeneration == _lifecycleGeneration) {
      state = AcpError(
        describeAcpConnectionError(
          'Agent connection closed unexpectedly.',
          stderrTail,
        ),
      );
    }
  }

  Future<void> _closeConnectionAttempt({
    acpd_io.AcpAgent? agent,
    ClientConnection? client,
    Session? session,
  }) async {
    session?.dispose();
    try {
      await client?.close();
    } on Object {
      // The transport may already be closed.
    }
    try {
      await agent?.close();
    } on Object {
      // The process may already have exited.
    }
  }

  // ===========================================================================
  // Prompt turns
  // ===========================================================================

  /// Sends a prompt to the agent and streams the response into [messages].
  ///
  /// Turns are serialized: if a turn is already in flight (or the agent is not
  /// connected) this is a no-op and returns `false`. The
  /// [AcpConnected.isPrompting] guard is the single source of truth.
  ///
  /// Returns `true` only when the turn was actually dispatched, so callers can
  /// clear their input exactly on success and never on a rejected concurrent
  /// submit.
  Future<bool> sendPrompt(String text) async {
    final session = _session;
    final client = _client;
    final connected = state;
    if (session == null ||
        client == null ||
        connected is! AcpConnected ||
        _isPrompting) {
      return false;
    }

    _messages.add(AcpChatMessage(role: AcpMessageRole.user, text: text));
    final assistantIndex = _messages.length;
    _messages.add(
      const AcpChatMessage(
        role: AcpMessageRole.assistant,
        text: '',
        isStreaming: true,
      ),
    );
    final turn = _ActiveTurn(
      generation: _lifecycleGeneration,
      session: session,
      assistantIndex: assistantIndex,
    );
    _activeTurn = turn;
    _isPrompting = true;
    _publishState();

    final thoughts = <String>[];
    final toolCalls = <String>[];
    final sessionId = session.sessionId;

    try {
      final updateSub = client.connection.onNotification('session/update', (
        params,
      ) {
        if (!_isActiveTurn(turn)) return;
        final notification = _parseSessionUpdate(params);
        if (notification == null || notification.sessionId != sessionId) {
          return;
        }
        switch (notification.update) {
          case AgentMessageChunk(:final chunk):
            final chunkText = _extractText(chunk.content);
            if (chunkText.isNotEmpty) {
              final current = _messages[assistantIndex];
              _messages[assistantIndex] = current.copyWith(
                text: current.text + chunkText,
              );
              _publishState();
            }
          case AgentThoughtChunk(:final chunk):
            final chunkText = _extractText(chunk.content);
            if (chunkText.isNotEmpty) {
              thoughts.add(chunkText);
              _messages[assistantIndex] = _messages[assistantIndex].copyWith(
                thoughts: List.unmodifiable(thoughts),
              );
              _publishState();
            }
          case ToolCallUpdateSession(:final toolCall):
            toolCalls.add(toolCall.title);
            _messages[assistantIndex] = _messages[assistantIndex].copyWith(
              toolCalls: List.unmodifiable(toolCalls),
            );
            _publishState();
          case ToolCallStatusUpdate():
          case PlanUpdate():
          case AvailableCommandsSessionUpdate():
          case CurrentModeSessionUpdate():
          case ConfigOptionSessionUpdate():
          case SessionInfoSessionUpdate():
          case UsageSessionUpdate():
          case UserMessageChunk():
            break;
          case _:
            break;
        }
      });

      try {
        final result = await session.sendPrompt([TextContentBlock(text: text)]);
        if (!_isActiveTurn(turn)) return true;
        if (_messages[assistantIndex].text.isEmpty &&
            thoughts.isEmpty &&
            toolCalls.isEmpty) {
          _messages[assistantIndex] = AcpChatMessage(
            role: AcpMessageRole.assistant,
            text: result.agentText.isEmpty
                ? '(Agent returned no text. Stop reason: ${result.stopReason.toJson()})'
                : result.agentText,
          );
        } else {
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            isStreaming: false,
          );
        }
      } finally {
        updateSub.dispose();
      }
    } on Object catch (error) {
      if (_isActiveTurn(turn)) {
        _messages[assistantIndex] = AcpChatMessage(
          role: AcpMessageRole.error,
          text: '$error',
        );
      }
    } finally {
      if (_isActiveTurn(turn)) {
        turn.cancelTimer?.cancel();
        _activeTurn = null;
        _isPrompting = false;
        _publishState();
      }
    }
    return true;
  }

  bool _isActiveTurn(_ActiveTurn turn) =>
      identical(_activeTurn, turn) &&
      turn.generation == _lifecycleGeneration &&
      turn.assistantIndex < _messages.length;

  /// Requests cooperative cancellation and tears down an agent that does not
  /// settle the active turn within a bounded grace period.
  void cancelTurn() {
    final turn = _activeTurn;
    if (turn == null) return;
    turn.session.cancel();
    turn.cancelTimer ??= Timer(
      const Duration(seconds: 5),
      () => unawaited(_forceCancelTurn(turn)),
    );
  }

  Future<void> _forceCancelTurn(_ActiveTurn turn) async {
    if (!_isActiveTurn(turn)) return;
    final failureGeneration = ++_lifecycleGeneration;
    await _cleanup();
    if (failureGeneration == _lifecycleGeneration) {
      state = const AcpError(
        'The agent did not stop the cancelled turn within 5 seconds.',
      );
    }
  }

  // ===========================================================================
  // Permission queue
  // ===========================================================================

  /// Applies a decision only when [requestId] still identifies the visible
  /// queue head and [optionId] is one of that request's offered options.
  bool respondToPermission({required String requestId, String? optionId}) {
    if (_permissionQueue.isEmpty) return false;
    final pending = _permissionQueue.first;
    if (!pending.prompt.acceptsDecision(
      requestId: requestId,
      optionId: optionId,
    )) {
      return false;
    }

    _permissionQueue.removeAt(0);
    pending.complete(
      optionId == null
          ? const PermissionCancelled()
          : PermissionSelected(optionId: optionId),
    );
    _publishState();
    return true;
  }

  // ===========================================================================
  // Session lifecycle
  // ===========================================================================

  Future<void> disconnect() async {
    final generation = ++_lifecycleGeneration;
    await _cleanup();
    if (generation == _lifecycleGeneration) {
      state = const AcpDisconnected();
    }
  }

  void clearMessages() {
    if (_activeTurn != null) return;
    _messages.clear();
    _publishState();
  }

  // ===========================================================================
  // State publishing
  // ===========================================================================

  /// Rebuilds the immutable [AcpConnected] from internal mutable state so the
  /// UI observes every change. No-op if not connected.
  void _publishState() {
    final current = state;
    if (current is! AcpConnected) return;

    final promptHead = _permissionQueue.isNotEmpty
        ? _permissionQueue.first.prompt
        : null;

    state = AcpConnected(
      agentInfo: current.agentInfo,
      sessionId: current.sessionId,
      modes: current.modes,
      messages: List.unmodifiable(_messages),
      pendingPermission: promptHead,
      isPrompting: _isPrompting,
    );
  }

  // ===========================================================================
  // Client role construction
  // ===========================================================================

  ClientRole _buildClientRole() {
    return ClientRole()
        .handleCancellableRequest(RequestPermissionRequest.methodName, (
          params,
          ctx,
          cancellation,
        ) async {
          final request = RequestPermissionRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          final pending = _PendingPermission(
            id: 'permission-$_lifecycleGeneration-${_permissionCounter++}',
            request: request,
          );
          _permissionQueue.add(pending);
          _publishState();

          final outcome = await Future.any<RequestPermissionOutcome>([
            pending.responseFuture,
            cancellation.whenCancelled.then((_) => const PermissionCancelled()),
          ]);
          if (_permissionQueue.remove(pending)) {
            pending.complete(const PermissionCancelled());
            _publishState();
          }
          return outcome.toJson();
        })
        .handleCancellableRequest(ReadTextFileRequest.methodName, (
          params,
          ctx,
          cancellation,
        ) async {
          final request = ReadTextFileRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          if (request.line case final line? when line < 1) {
            throw _structuredError(
              ErrorCode.invalidParams,
              'Read line must be at least 1.',
            );
          }
          if (request.limit case final limit? when limit < 0) {
            throw _structuredError(
              ErrorCode.invalidParams,
              'Read limit must be non-negative.',
            );
          }

          try {
            final filePath = confinePathToRoot(
              request.path,
              _sessionRootCanonical!,
            );
            final content = await readAcpTextFile(
              File(filePath),
              line: request.line,
              limit: request.limit,
              isCancelled: () =>
                  cancellation.isCancelled ||
                  _session?.sessionId != request.sessionId,
            );
            return ReadTextFileResponse(content: content).toJson();
          } on _AcpRequestCancelled {
            throw _structuredError(
              ErrorCode.invalidRequest,
              'Request cancelled.',
            );
          } on _AcpResourceLimitException catch (error) {
            throw _structuredError(
              ErrorCode.inaccessibleResource,
              error.message,
            );
          } on AcpPathEscapeException catch (error) {
            throw _structuredError(ErrorCode.invalidParams, error.message);
          } on PathNotFoundException catch (error) {
            throw _structuredError(
              ErrorCode.inaccessibleResource,
              'File not found: ${error.path}',
            );
          } on FileSystemException catch (error) {
            throw _structuredError(
              ErrorCode.internalError,
              'Read failed: ${error.message}',
            );
          }
        })
        .handleCancellableRequest(WriteTextFileRequest.methodName, (
          params,
          ctx,
          cancellation,
        ) async {
          final request = WriteTextFileRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          try {
            final filePath = confinePathToRoot(
              request.path,
              _sessionRootCanonical!,
            );
            await writeAcpTextFileAtomically(
              File(filePath),
              request.content,
              isCancelled: () =>
                  cancellation.isCancelled ||
                  _session?.sessionId != request.sessionId,
            );
            return const WriteTextFileResponse().toJson();
          } on _AcpResourceLimitException catch (error) {
            throw _structuredError(
              ErrorCode.inaccessibleResource,
              error.message,
            );
          } on _AcpRequestCancelled {
            throw _structuredError(
              ErrorCode.invalidRequest,
              'Request cancelled.',
            );
          } on AcpPathEscapeException catch (error) {
            throw _structuredError(ErrorCode.invalidParams, error.message);
          } on FileSystemException catch (error) {
            throw _structuredError(
              ErrorCode.internalError,
              'Write failed: ${error.message}',
            );
          }
        })
        .handleCancellableRequest(CreateTerminalRequest.methodName, (
          params,
          ctx,
          cancellation,
        ) async {
          final request = CreateTerminalRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          if (request.outputByteLimit case final limit? when limit < 0) {
            throw _structuredError(
              ErrorCode.invalidParams,
              'Terminal outputByteLimit must be non-negative.',
            );
          }
          if (request.cwd case final cwd? when !p.isAbsolute(cwd)) {
            throw _structuredError(
              ErrorCode.invalidParams,
              'Terminal cwd must be an absolute path.',
            );
          }
          if (_terminals.length >= _maximumConcurrentTerminals) {
            throw _structuredError(
              ErrorCode.inaccessibleResource,
              'At most $_maximumConcurrentTerminals terminals may run concurrently.',
            );
          }

          final requestedLimit = request.outputByteLimit;
          final outputByteLimit =
              requestedLimit == null ||
                  requestedLimit > _maximumTerminalOutputBytes
              ? _maximumTerminalOutputBytes
              : requestedLimit;
          try {
            final terminal = _ManagedTerminal(
              request,
              _resolveTerminalCwd(request.cwd),
              outputByteLimit: outputByteLimit,
            );
            final startFuture = terminal.start();
            final started = await Future.any<bool>([
              startFuture.then((_) => true),
              cancellation.whenCancelled.then((_) => false),
            ]);
            if (!started) {
              unawaited(_disposeTerminalAfterStart(terminal, startFuture));
              throw const _AcpRequestCancelled();
            }
            if (cancellation.isCancelled ||
                _session?.sessionId != request.sessionId) {
              await terminal.dispose();
              if (cancellation.isCancelled) {
                throw const _AcpRequestCancelled();
              }
              _requireActiveSession(request.sessionId);
            }
            _terminals[terminal.id] = terminal;
            return CreateTerminalResponse(terminalId: terminal.id).toJson();
          } on _AcpRequestCancelled {
            throw _structuredError(
              ErrorCode.invalidRequest,
              'Request cancelled.',
            );
          } on AcpPathEscapeException catch (error) {
            throw _structuredError(ErrorCode.invalidParams, error.message);
          } on ProcessException catch (error) {
            throw _structuredError(
              ErrorCode.internalError,
              'Failed to start terminal command: ${error.message}',
            );
          }
        })
        .handleRequest('terminal/output', (params, ctx) async {
          final request = TerminalOutputRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          return TerminalOutputResponse(
            output: terminal.output,
            truncated: terminal.truncated,
            exitStatus: terminal.exitStatus,
          ).toJson();
        })
        .handleCancellableRequest(WaitForTerminalExitRequest.methodName, (
          params,
          ctx,
          cancellation,
        ) async {
          final request = WaitForTerminalExitRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          final exitCode = await Future.any<int?>([
            terminal.exitCodeFuture,
            cancellation.whenCancelled.then((_) => null),
          ]);
          if (cancellation.isCancelled) {
            return const WaitForTerminalExitResponse().toJson();
          }
          return WaitForTerminalExitResponse(exitCode: exitCode).toJson();
        })
        .handleRequest('terminal/release', (params, ctx) async {
          final request = ReleaseTerminalRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          _terminals.remove(request.terminalId);
          await terminal.dispose();
          return const ReleaseTerminalResponse().toJson();
        })
        .handleRequest('terminal/kill', (params, ctx) async {
          final request = KillTerminalRequest.fromJson(params);
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          if (!terminal.kill()) {
            throw _structuredError(
              ErrorCode.internalError,
              'Failed to terminate terminal ${request.terminalId}.',
            );
          }
          return const KillTerminalResponse().toJson();
        });
  }

  // ===========================================================================
  // Session identity enforcement
  // ===========================================================================

  /// Throws an [RpcError] if [sessionId] does not match the active session.
  void _requireActiveSession(String sessionId) {
    final active = _session?.sessionId;
    if (active == null || active != sessionId) {
      throw _structuredError(
        ErrorCode.invalidParams,
        'Request for inactive session "$sessionId" (active: "$active").',
      );
    }
  }

  // ===========================================================================
  // Terminal helpers
  // ===========================================================================

  /// Resolves the terminal [requested] cwd to a path confined within the
  /// active session root. Invalid or escaping paths are rejected rather than
  /// silently running the command from a different directory.
  String _resolveTerminalCwd(String? requested) {
    final root = _sessionRootCanonical;
    if (root == null) {
      throw StateError('No active ACP session root.');
    }
    return requested == null ? root : confinePathToRoot(requested, root);
  }

  _ManagedTerminal _requireTerminal(String terminalId) {
    final terminal = _terminals[terminalId];
    if (terminal == null) {
      throw _structuredError(
        ErrorCode.invalidParams,
        'Unknown terminal: $terminalId',
      );
    }
    return terminal;
  }

  Future<void> _disposeTerminalAfterStart(
    _ManagedTerminal terminal,
    Future<void> startFuture,
  ) async {
    try {
      await startFuture;
    } on Object {
      // Startup errors are reported by the original request future.
    } finally {
      await terminal.dispose();
    }
  }

  /// Appends an agent stderr line to the bounded tail. The acpd_io transport
  /// already caps the raw capture; this keeps only the most recent characters
  /// so a noisy agent never grows the buffer without bound.
  void _appendAgentStderr(String line) {
    if (line.isEmpty) return;
    if (_agentStderr.isNotEmpty) _agentStderr.writeln();
    _agentStderr.write(line);
    final overflow = _agentStderr.length - _maximumAgentStderrChars;
    if (overflow > 0) {
      final cut = _agentStderr.toString().indexOf('\n', overflow);
      final kept = cut >= 0 ? _agentStderr.toString().substring(cut + 1) : '';
      _agentStderr
        ..clear()
        ..write(kept);
    }
  }

  // ===========================================================================
  // Cleanup
  // ===========================================================================

  /// Synchronous teardown for [ref.onDispose].
  void _cleanupSync() {
    _lifecycleGeneration++;
    final agent = _agentProcess;
    final client = _client;
    final session = _session;
    _agentProcess = null;
    _client = null;
    _session = null;
    _agentStderr.clear();
    _stderrSub?.cancel();
    _stderrSub = null;

    _activeTurn?.cancelTimer?.cancel();
    _activeTurn = null;
    _isPrompting = false;
    _messages.clear();
    for (final pending in _permissionQueue) {
      pending.complete(const PermissionCancelled());
    }
    _permissionQueue.clear();
    for (final terminal in _terminals.values) {
      terminal.kill();
    }
    _terminals.clear();
    unawaited(
      _closeConnectionAttempt(agent: agent, client: client, session: session),
    );
  }

  /// Full async teardown. Active resources are detached before the first await
  /// so overlapping lifecycle operations cannot clear a newer connection.
  Future<void> _cleanup() async {
    final agent = _agentProcess;
    final client = _client;
    final session = _session;
    final terminals = _terminals.values.toList(growable: false);
    _agentProcess = null;
    _client = null;
    _session = null;
    _agentStderr.clear();
    _stderrSub?.cancel();
    _stderrSub = null;
    _terminals.clear();

    _activeTurn?.cancelTimer?.cancel();
    _activeTurn = null;
    _isPrompting = false;
    _messages.clear();
    for (final pending in _permissionQueue) {
      pending.complete(const PermissionCancelled());
    }
    _permissionQueue.clear();

    await Future.wait<void>([
      for (final terminal in terminals) terminal.dispose(),
    ]);
    await _closeConnectionAttempt(
      agent: agent,
      client: client,
      session: session,
    );
  }
}

final acpAgentProvider = NotifierProvider<AcpAgentNotifier, AcpAgentState>(
  AcpAgentNotifier.new,
);

// =============================================================================
// Pure-logic functions (testable)
// =============================================================================

/// Resolves [path] to a canonical absolute path confined within [root].
///
/// Follows symlinks and verifies the canonical target is inside [root]. For
/// not-yet-existing paths (write case), resolves the deepest existing ancestor
/// and normalizes the remainder, rejecting `..` escapes.
///
/// This is the shared production safety boundary for session-root confinement
/// — used by both the ACP client role (fs/terminal handlers) and the document
/// store. It must remain public and its behavior must never loosen.
///
/// Throws [AcpPathEscapeException] on any escape attempt.
String confinePathToRoot(String path, String root) {
  final canonicalRoot = p.normalize(p.absolute(root));
  late final String currentRootTarget;
  try {
    currentRootTarget = Directory(canonicalRoot).resolveSymbolicLinksSync();
  } on FileSystemException {
    throw AcpPathEscapeException(
      'The ACP session root is no longer accessible.',
    );
  }
  if (!p.equals(currentRootTarget, canonicalRoot)) {
    throw AcpPathEscapeException(
      'The ACP session root changed after the session started.',
    );
  }
  final absolute = p.normalize(
    p.isAbsolute(path) ? path : p.join(canonicalRoot, path),
  );
  _checkWithinRoot(absolute, canonicalRoot, path);

  // Resolve the deepest existing ancestor. This is required for writes: a
  // missing descendant can still sit below a symlink that escapes the root.
  // Pure lexical normalization cannot detect that case.
  var ancestor = absolute;
  final missingSegments = <String>[];
  while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(ancestor);
    if (parent == ancestor) {
      throw AcpPathEscapeException(
        'Path "$path" has no resolvable ancestor inside the session root.',
      );
    }
    missingSegments.add(p.basename(ancestor));
    ancestor = parent;
  }

  late final String canonicalAncestor;
  try {
    canonicalAncestor = File(ancestor).resolveSymbolicLinksSync();
  } on FileSystemException {
    throw AcpPathEscapeException(
      'Path "$path" cannot be resolved inside the session root.',
    );
  }
  _checkWithinRoot(canonicalAncestor, canonicalRoot, path);

  var resolved = canonicalAncestor;
  for (final segment in missingSegments.reversed) {
    resolved = p.join(resolved, segment);
  }
  resolved = p.normalize(resolved);
  _checkWithinRoot(resolved, canonicalRoot, path);
  return resolved;
}

/// Verifies [resolved] is [root] itself or a descendant of [root].
void _checkWithinRoot(String resolved, String root, String originalPath) {
  if (!p.equals(resolved, root) && !p.isWithin(root, resolved)) {
    throw AcpPathEscapeException(
      'Path "$originalPath" resolves outside the session root.',
    );
  }
}

/// Applies 1-based [line] and [limit] to [content], mirroring the ACP
/// `fs/read_text_file` semantics.
///
/// [line] is 1-based (line 1 is the first line). [limit] is the maximum number
/// of lines to return. If both are null the full content is returned.
@visibleForTesting
String applyLineLimit(String content, int? line, int? limit) {
  if (line == null && limit == null) return content;
  final lines = content.split('\n');
  var start = 0;
  var end = lines.length;
  if (line != null) {
    // 1-based: line 1 → index 0.
    start = (line - 1).clamp(0, lines.length);
  }
  if (limit != null) {
    end = (start + limit).clamp(start, lines.length);
  }
  return lines.sublist(start, end).join('\n');
}

/// Reads an ACP text-file range without materializing an unbounded file.
@visibleForTesting
Future<String> readAcpTextFile(
  File file, {
  int? line,
  int? limit,
  int maximumResponseBytes = _maximumFileResponseBytes,
  int maximumScanBytes = _maximumFileScanBytes,
  bool Function()? isCancelled,
}) async {
  if (line != null && line < 1) {
    throw ArgumentError.value(line, 'line', 'Must be at least 1.');
  }
  if (limit != null && limit < 0) {
    throw ArgumentError.value(limit, 'limit', 'Must be non-negative.');
  }
  if (maximumResponseBytes < 1 || maximumScanBytes < maximumResponseBytes) {
    throw ArgumentError('Invalid ACP file byte ceilings.');
  }

  void checkCancellation() {
    if (isCancelled?.call() ?? false) {
      throw const _AcpRequestCancelled();
    }
  }

  if (limit == 0) return '';
  if (line == null && limit == null) {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      checkCancellation();
      if (bytes.length + chunk.length > maximumResponseBytes) {
        throw const _AcpResourceLimitException(
          'The requested file exceeds the 4 MiB response limit.',
        );
      }
      bytes.add(chunk);
    }
    checkCancellation();
    return utf8.decode(bytes.takeBytes());
  }

  var scannedBytes = 0;
  Stream<List<int>> boundedChunks() async* {
    await for (final chunk in file.openRead()) {
      checkCancellation();
      scannedBytes += chunk.length;
      if (scannedBytes > maximumScanBytes) {
        throw const _AcpResourceLimitException(
          'The requested line range exceeds the 64 MiB scan limit.',
        );
      }
      yield chunk;
    }
  }

  final firstLine = line ?? 1;
  var currentLine = 0;
  var emittedLines = 0;
  var responseBytes = 0;
  final result = StringBuffer();
  await for (final value
      in boundedChunks()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    currentLine++;
    if (currentLine < firstLine) continue;
    final encodedLength = utf8.encode(value).length;
    final separatorBytes = emittedLines == 0 ? 0 : 1;
    if (responseBytes + separatorBytes + encodedLength > maximumResponseBytes) {
      throw const _AcpResourceLimitException(
        'The requested file range exceeds the 4 MiB response limit.',
      );
    }
    if (emittedLines > 0) result.write('\n');
    result.write(value);
    responseBytes += separatorBytes + encodedLength;
    emittedLines++;
    if (limit != null && emittedLines >= limit) break;
  }
  checkCancellation();
  return result.toString();
}

var _temporaryFileCounter = 0;

/// Commits an ACP file write only after its content is fully staged.
@visibleForTesting
Future<void> writeAcpTextFileAtomically(
  File file,
  String content, {
  bool Function()? isCancelled,
  int maximumWriteBytes = _maximumFileWriteBytes,
}) async {
  void checkCancellation() {
    if (isCancelled?.call() ?? false) {
      throw const _AcpRequestCancelled();
    }
  }

  if (maximumWriteBytes < 0) {
    throw ArgumentError.value(
      maximumWriteBytes,
      'maximumWriteBytes',
      'Must be non-negative.',
    );
  }

  checkCancellation();
  final writeBytes = utf8.encode(content).length;
  if (writeBytes > maximumWriteBytes) {
    throw _AcpResourceLimitException(
      'Write payload exceeds the $maximumWriteBytes-byte limit.',
    );
  }
  checkCancellation();
  await file.parent.create(recursive: true);
  checkCancellation();
  final temporary = File(
    p.join(
      file.parent.path,
      '.${p.basename(file.path)}.cockpit-$pid-${_temporaryFileCounter++}.tmp',
    ),
  );
  RandomAccessFile? output;
  try {
    await temporary.create(exclusive: true);
    output = await temporary.open(mode: FileMode.writeOnly);
    await output.writeString(content, encoding: utf8);
    await output.flush();
    await output.close();
    output = null;
    checkCancellation();
    await temporary.rename(file.path);
  } finally {
    await output?.close();
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

/// Builds a user-facing connection-failure message, appending the agent's
/// stderr tail (if any) so the user can see *why* the agent died rather than a
/// generic "closed unexpectedly".
///
/// Pure and testable: callers pass the base message and the retained stderr
/// buffer. A non-empty tail is trimmed and quoted so it stays scannable.
@visibleForTesting
String describeAcpConnectionError(String baseMessage, StringBuffer stderr) {
  final tail = stderr.toString().trim();
  if (tail.isEmpty) return baseMessage;
  return '$baseMessage\n\nAgent stderr:\n$tail';
}

/// Constructs a structured [RpcError] that the JSON-RPC engine serializes as
/// an error response.
RpcError _structuredError(ErrorCode code, String message) =>
    RpcError(code: code.code, message: message);

// =============================================================================
// Internal helpers
// =============================================================================

/// A pending permission request awaiting user response.
class _PendingPermission {
  _PendingPermission({required this.id, required this.request});

  final String id;
  final RequestPermissionRequest request;
  AcpPermissionPrompt get prompt => AcpPermissionPrompt(
    requestId: id,
    toolCall: request.toolCall,
    options: List.unmodifiable(request.options),
  );

  final Completer<RequestPermissionOutcome> _completer =
      Completer<RequestPermissionOutcome>();

  Future<RequestPermissionOutcome> get responseFuture => _completer.future;

  void complete(RequestPermissionOutcome outcome) {
    if (!_completer.isCompleted) {
      _completer.complete(outcome);
    }
  }
}

final class _ActiveTurn {
  _ActiveTurn({
    required this.generation,
    required this.session,
    required this.assistantIndex,
  });

  final int generation;
  final Session session;
  final int assistantIndex;
  Timer? cancelTimer;
}

final class _AcpRequestCancelled implements Exception {
  const _AcpRequestCancelled();
}

final class _AcpResourceLimitException implements Exception {
  const _AcpResourceLimitException(this.message);

  final String message;
}

/// Retains terminal output according to ACP's byte-limit contract.
///
/// When the limit is exceeded, bytes are discarded from the beginning so the
/// most recent output remains available. A partial leading UTF-8 code point is
/// discarded as well, ensuring the exposed string always begins at a character
/// boundary. Malformed process output is represented with replacement
/// characters rather than failing the terminal stream.
@visibleForTesting
final class AcpTerminalOutputBuffer {
  AcpTerminalOutputBuffer(this.byteLimit) {
    if (byteLimit case final limit? when limit < 0) {
      throw ArgumentError.value(
        limit,
        'byteLimit',
        'The terminal output byte limit must be non-negative.',
      );
    }
  }

  final int? byteLimit;
  final List<int> _bytes = <int>[];
  bool _truncated = false;
  String? _cachedText;

  bool get truncated => _truncated;
  int get retainedByteCount => _bytes.length;

  String get text => _cachedText ??= utf8.decode(_bytes, allowMalformed: true);

  void add(List<int> data) {
    if (data.isEmpty) return;
    _cachedText = null;

    final limit = byteLimit;
    if (limit == null) {
      _bytes.addAll(data);
      return;
    }
    if (limit == 0) {
      _bytes.clear();
      _truncated = true;
      return;
    }

    var didTruncate = false;
    if (data.length >= limit) {
      final firstRetained = data.length - limit;
      didTruncate = _bytes.isNotEmpty || firstRetained > 0;
      _bytes
        ..clear()
        ..addAll(data.getRange(firstRetained, data.length));
    } else {
      _bytes.addAll(data);
      final overflow = _bytes.length - limit;
      if (overflow > 0) {
        _bytes.removeRange(0, overflow);
        didTruncate = true;
      }
    }

    if (didTruncate) {
      _truncated = true;
      // UTF-8 continuation bytes cannot begin a valid retained string.
      // Dropping them may retain slightly fewer bytes, as ACP requires.
      while (_bytes.isNotEmpty && (_bytes.first & 0xC0) == 0x80) {
        _bytes.removeAt(0);
      }
    }
  }
}

/// A managed terminal subprocess for ACP terminal/* requests.
///
/// Runs the command directly (not through a shell), applies the requested
/// environment variables, respects the [outputByteLimit] with truthful
/// truncation tracking, and cleans up all async resources on [dispose].
final class _ManagedTerminal {
  _ManagedTerminal(this.request, this.cwd, {required int outputByteLimit})
    : id = 'term-${_counter++}',
      _output = AcpTerminalOutputBuffer(outputByteLimit);

  static int _counter = 0;

  final String id;
  final CreateTerminalRequest request;
  final String cwd;
  final AcpTerminalOutputBuffer _output;

  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final Completer<int> _exitCompleter = Completer<int>();
  int? _exitCode;

  String get output => _output.text;
  bool get truncated => _output.truncated;

  /// The exit status if the process has exited, otherwise null.
  TerminalExitStatus? get exitStatus {
    if (!_exitCompleter.isCompleted) return null;
    return TerminalExitStatus(exitCode: _exitCode);
  }

  Future<int> get exitCodeFuture => _exitCompleter.future;

  Future<void> start() async {
    // Build environment: inherit the current environment and apply requested
    // overrides.
    final env = <String, String>{}..addAll(Platform.environment);
    for (final v in request.env) {
      env[v.name] = v.value;
    }

    _process = await Process.start(
      request.command,
      request.args,
      workingDirectory: cwd,
      environment: env,
      // Direct execution — no shell wrapping.
      runInShell: false,
    );

    _stdoutSub = _process!.stdout.listen(_appendOutput);
    _stderrSub = _process!.stderr.listen(_appendOutput);

    // Collect exit code and complete the future exactly once.
    _process!.exitCode.then((code) {
      _exitCode = code;
      if (!_exitCompleter.isCompleted) {
        _exitCompleter.complete(code);
      }
    });
  }

  void _appendOutput(List<int> data) => _output.add(data);

  bool kill() {
    final process = _process;
    if (process == null || _exitCompleter.isCompleted) return true;
    return _kill(process, force: true);
  }

  Future<void> dispose() async {
    final process = _process;
    _process = null;
    if (process != null) {
      _kill(process, force: false);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        _kill(process, force: true);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // The operating system still owns the process; subscriptions are
          // cancelled below so the client can complete deterministic cleanup.
        }
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
  }

  bool _kill(Process process, {required bool force}) {
    if (Platform.isWindows) return process.kill();
    return process.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
  }
}

SessionUpdateNotification? _parseSessionUpdate(Object? params) {
  if (params is Map<String, Object?>) {
    try {
      return SessionUpdateNotification.fromJson(params);
    } on Object {
      return null;
    }
  }
  return null;
}

String _extractText(ContentBlock block) {
  if (block is TextContentBlock) return block.text;
  return '';
}
