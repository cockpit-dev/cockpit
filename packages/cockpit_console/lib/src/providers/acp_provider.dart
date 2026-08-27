import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:acpd/acpd.dart';
import 'package:acpd_io/acpd_io.dart' as acpd_io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../foundation/console_version.dart';
import 'acp_state.dart';

export 'acp_state.dart';

const _maximumConcurrentTerminals = 8;
const _maximumTerminalOutputBytes = 1024 * 1024;
const _maximumFileResponseBytes = 4 * 1024 * 1024;
const _maximumFileScanBytes = 64 * 1024 * 1024;
const _maximumFileWriteBytes = 16 * 1024 * 1024;
const _maximumPromptPayloadBytes = 14 * 1024 * 1024;
const _initializeTimeout = Duration(seconds: 30);
const _controlTimeout = Duration(seconds: 30);
const _sessionSetupTimeout = Duration(minutes: 2);
const _promptTimeout = Duration(minutes: 30);
const _maximumPendingSessionUpdates = 65536;

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
    this.clientVersion = consoleVersion,
    this.sessionCwd = '.',
    this.additionalDirectories = const [],
    this.mcpServers = const [],
  });

  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String? workingDirectory;
  final String clientName;
  final String clientVersion;
  final String sessionCwd;
  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;

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

@visibleForTesting
List<String> resolveAcpAdditionalDirectories(
  AcpConnectionConfig config,
  String sessionRoot,
) {
  return config.additionalDirectories
      .map((directory) {
        final requested = p.isAbsolute(directory)
            ? directory
            : p.join(sessionRoot, directory);
        return Directory(requested).resolveSymbolicLinksSync();
      })
      .toSet()
      .where((directory) => !p.equals(directory, sessionRoot))
      .toList(growable: false);
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
  AcpSessionState? _activeSessionState;
  AcpSessionSpec? _defaultSessionSpec;
  HandlerRegistration? _sessionUpdateSub;

  /// Canonical roots exposed to the active ACP session. The first root is cwd;
  /// the remainder are additional directories advertised at session setup.
  final List<String> _sessionRootsCanonical = [];

  String? _pendingSessionId;
  bool _captureUnknownPendingSession = false;
  final Map<String, List<SessionUpdate>> _pendingSessionUpdates = {};
  String? _pendingSessionOverflowError;

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

  /// Connects to an agent, advertises every implemented client capability,
  /// then creates the initial session. Authentication and session-setup
  /// failures keep the initialized connection available for recovery.
  Future<void> connect(AcpConnectionConfig config) async {
    final generation = ++_lifecycleGeneration;
    state = const AcpConnecting();
    await _cleanup();
    if (generation != _lifecycleGeneration) return;

    acpd_io.AcpAgent? agent;
    ClientConnection? client;
    try {
      final sessionRoot = resolveAcpSessionRoot(config);
      final additionalDirectories = resolveAcpAdditionalDirectories(
        config,
        sessionRoot,
      );
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
            session: ClientSessionCapabilities(
              configOptions: SessionConfigOptionsCapabilities(
                boolean: BooleanConfigOptionCapabilities(),
              ),
            ),
          ),
        ),
        timeout: _initializeTimeout,
      );
      if (generation != _lifecycleGeneration) {
        await _closeConnectionAttempt(agent: agent, client: client);
        return;
      }

      _agentProcess = agent;
      _client = client;
      _defaultSessionSpec = AcpSessionSpec(
        cwd: sessionRoot,
        additionalDirectories: additionalDirectories,
        mcpServers: config.mcpServers,
      );
      _messages.clear();
      _permissionQueue.clear();
      _terminals.clear();
      _activeTurn = null;
      _isPrompting = false;
      _sessionUpdateSub = client.connection.onNotification(
        SessionUpdateNotification.methodName,
        _handleSessionUpdateNotification,
      );

      unawaited(
        client.closed.then(
          (_) => _handleUnexpectedConnectionClose(generation, client!),
        ),
      );
      state = AcpConnected(
        agentInfo:
            initResp.agentInfo ??
            Implementation(name: config.command, version: 'unknown'),
        protocolVersion: initResp.protocolVersion,
        capabilities: initResp.agentCapabilities ?? const AgentCapabilities(),
        authMethods: List.unmodifiable(initResp.authMethods),
        authStatus: initResp.authMethods.isEmpty
            ? AcpAuthStatus.unavailable
            : AcpAuthStatus.available,
        sessionDefaults: _defaultSessionSpec,
      );

      await _createSessionInternal(
        cwd: sessionRoot,
        additionalDirectories: additionalDirectories,
        mcpServers: config.mcpServers,
        exposeBusyState: false,
      );
    } on Object catch (error) {
      await _stderrSub?.cancel();
      _stderrSub = null;
      await _closeConnectionAttempt(agent: agent, client: client);
      if (generation == _lifecycleGeneration) {
        _sessionRootsCanonical.clear();
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

  Future<bool> sendPrompt(String text) =>
      sendPromptContent(<ContentBlock>[TextContentBlock(text: text)]);

  /// Sends one complete ACP prompt. Non-text blocks are retained exactly so
  /// image, audio, resource-link, and embedded-resource capable agents can use
  /// the full v1 prompt surface.
  Future<bool> sendPromptContent(List<ContentBlock> content) async {
    final session = _session;
    final client = _client;
    final connected = state;
    if (session == null ||
        client == null ||
        connected is! AcpConnected ||
        connected.activeSession == null ||
        content.isEmpty ||
        _isPrompting) {
      return false;
    }

    final prompt = List<ContentBlock>.unmodifiable(content);
    try {
      _validatePromptContent(prompt, connected.capabilities);
    } on AcpPromptValidationException catch (error) {
      _setLastError(error.message);
      return false;
    }

    clearLastError();

    final userIndex = _messages.length;
    _messages.add(
      AcpChatMessage(
        role: AcpMessageRole.user,
        text: _contentText(prompt),
        content: prompt,
      ),
    );
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
      userIndex: userIndex,
      assistantIndex: assistantIndex,
    );
    _activeTurn = turn;
    _isPrompting = true;
    _publishState();

    try {
      final result = await session.sendPrompt(prompt, timeout: _promptTimeout);
      if (!_isActiveTurn(turn)) return true;
      final assistantMessages = _turnAssistantMessageIndices(turn);
      final streamedText = assistantMessages
          .map((index) => _messages[index].text)
          .join();
      final hasStreamedContent = assistantMessages.any(
        (index) => _messageHasContent(_messages[index]),
      );
      if (streamedText.isEmpty && result.agentText.isNotEmpty) {
        final current = _messages[assistantIndex];
        _messages[assistantIndex] = current.copyWith(text: result.agentText);
      } else if (!hasStreamedContent) {
        _messages[assistantIndex] = AcpChatMessage(
          role: AcpMessageRole.assistant,
          text:
              '(Agent returned no content. Stop reason: ${result.stopReason.toJson()})',
        );
      }
    } on Object catch (error) {
      if (_isActiveTurn(turn)) {
        final hasPartialResponse = _turnAssistantMessageIndices(
          turn,
        ).any((index) => _messageHasContent(_messages[index]));
        if (hasPartialResponse) {
          _messages.add(
            AcpChatMessage(role: AcpMessageRole.error, text: '$error'),
          );
        } else {
          _messages[assistantIndex] = AcpChatMessage(
            role: AcpMessageRole.error,
            text: '$error',
          );
        }
        if (error is RpcError && error.code == ErrorCode.authRequired.code) {
          _setAuthRequired(error.message);
        }
      }
    } finally {
      if (_isActiveTurn(turn)) {
        if (turn.userEchoContent.isNotEmpty &&
            turn.userIndex < _messages.length) {
          _messages[turn.userIndex] = _messages[turn.userIndex].copyWith(
            text: _contentText(turn.userEchoContent),
            content: List.unmodifiable(turn.userEchoContent),
          );
        }
        for (
          var index = turn.assistantIndex;
          index < _messages.length;
          index++
        ) {
          if (_messages[index].isStreaming) {
            _messages[index] = _messages[index].copyWith(isStreaming: false);
          }
        }
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

  Future<bool> authenticate(String methodId) async {
    final client = _client;
    final connected = state;
    if (client == null || connected is! AcpConnected) return false;
    if (!connected.authMethods.any((method) => method.id == methodId)) {
      _setLastError('The agent did not advertise auth method "$methodId".');
      return false;
    }
    if (!_beginAction(AcpBusyAction.authenticate)) return false;
    state = (state as AcpConnected).copyWith(
      authStatus: AcpAuthStatus.authenticating,
    );
    try {
      await client.client.authenticate(
        AuthenticateRequest(methodId: methodId),
        timeout: _sessionSetupTimeout,
      );
      _endAction(authStatus: AcpAuthStatus.authenticated);
      final spec = _defaultSessionSpec;
      if (_session == null && spec != null) {
        return await _createSessionInternal(
          cwd: spec.cwd,
          additionalDirectories: spec.additionalDirectories,
          mcpServers: spec.mcpServers,
          exposeBusyState: true,
        );
      }
      return true;
    } on Object catch (error) {
      _endAction(
        error: '$error',
        authStatus:
            error is RpcError && error.code == ErrorCode.authRequired.code
            ? AcpAuthStatus.required
            : AcpAuthStatus.available,
      );
      return false;
    }
  }

  Future<bool> logout() async {
    final client = _client;
    final connected = state;
    if (client == null || connected is! AcpConnected) return false;
    if (!connected.canLogout) {
      _setLastError('The connected agent does not support logout.');
      return false;
    }
    if (!_beginAction(AcpBusyAction.logout)) return false;
    state = (state as AcpConnected).copyWith(
      authStatus: AcpAuthStatus.loggingOut,
    );
    try {
      await client.client.logout(timeout: _sessionSetupTimeout);
      await _detachActiveSession();
      _endAction(authStatus: AcpAuthStatus.available);
      return true;
    } on Object catch (error) {
      _endAction(error: '$error', authStatus: AcpAuthStatus.authenticated);
      return false;
    }
  }

  Future<bool> createSession({
    String? cwd,
    List<String>? additionalDirectories,
    List<McpServer>? mcpServers,
  }) async {
    final defaults = _defaultSessionSpec;
    if (defaults == null) return false;
    try {
      final spec = _canonicalizeSessionSpec(
        cwd: cwd ?? defaults.cwd,
        additionalDirectories:
            additionalDirectories ?? defaults.additionalDirectories,
        mcpServers: mcpServers ?? defaults.mcpServers,
      );
      return await _createSessionInternal(
        cwd: spec.cwd,
        additionalDirectories: spec.additionalDirectories,
        mcpServers: spec.mcpServers,
        exposeBusyState: true,
      );
    } on Object catch (error) {
      _setLastError('$error');
      return false;
    }
  }

  Future<bool> loadSession(SessionInfo info, {List<McpServer>? mcpServers}) {
    return _openExistingSession(info, resume: false, mcpServers: mcpServers);
  }

  Future<bool> resumeSession(SessionInfo info, {List<McpServer>? mcpServers}) {
    return _openExistingSession(info, resume: true, mcpServers: mcpServers);
  }

  Future<bool> _openExistingSession(
    SessionInfo info, {
    required bool resume,
    List<McpServer>? mcpServers,
  }) async {
    final client = _client;
    final connected = state;
    if (client == null || connected is! AcpConnected) return false;
    if (resume ? !connected.canResumeSessions : !connected.canLoadSessions) {
      _setLastError(
        resume
            ? 'The connected agent does not support session resume.'
            : 'The connected agent does not support session load.',
      );
      return false;
    }
    final action = resume
        ? AcpBusyAction.resumeSession
        : AcpBusyAction.loadSession;
    if (!_beginAction(action)) return false;
    Session? candidate;
    try {
      final spec = _canonicalizeSessionSpec(
        cwd: info.cwd,
        additionalDirectories: info.additionalDirectories,
        mcpServers: mcpServers ?? _defaultSessionSpec?.mcpServers ?? const [],
      );
      _validateSessionSpec(spec, connected.capabilities);
      _beginPendingSession(info.sessionId);
      candidate = resume
          ? await Session.resume(
              client,
              ResumeSessionRequest(
                sessionId: info.sessionId,
                cwd: spec.cwd,
                additionalDirectories: spec.additionalDirectories,
                mcpServers: spec.mcpServers,
              ),
              timeout: _sessionSetupTimeout,
            )
          : await Session.load(
              client,
              LoadSessionRequest(
                sessionId: info.sessionId,
                cwd: spec.cwd,
                additionalDirectories: spec.additionalDirectories,
                mcpServers: spec.mcpServers,
              ),
              timeout: _sessionSetupTimeout,
            );
      _throwIfPendingSessionOverflow();
      _defaultSessionSpec = spec;
      await _activateSession(candidate, spec);
      _endAction(
        authStatus: connected.authMethods.isEmpty
            ? AcpAuthStatus.unavailable
            : AcpAuthStatus.authenticated,
      );
      return true;
    } on Object catch (error) {
      candidate?.dispose();
      _endAction(
        error: '$error',
        authStatus: _authStatusAfterError(error, connected),
      );
      return false;
    } finally {
      _clearPendingSession();
    }
  }

  Future<bool> closeSession() async {
    final connected = state;
    final session = _session;
    if (connected is! AcpConnected || session == null) return false;
    if (!connected.canCloseSessions) {
      _setLastError('The connected agent does not support session close.');
      return false;
    }
    if (!_beginAction(AcpBusyAction.closeSession)) return false;
    try {
      await session.close(timeout: _sessionSetupTimeout);
      await _detachActiveSession(sessionAlreadyDisposed: true);
      _endAction();
      return true;
    } on Object catch (error) {
      _endAction(error: '$error');
      return false;
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    final client = _client;
    final connected = state;
    if (client == null || connected is! AcpConnected) return false;
    if (!connected.canDeleteSessions) {
      _setLastError('The connected agent does not support session deletion.');
      return false;
    }
    if (!_beginAction(AcpBusyAction.deleteSession)) return false;
    try {
      await client.client.deleteSession(
        DeleteSessionRequest(sessionId: sessionId),
        timeout: _sessionSetupTimeout,
      );
      if (_session?.sessionId == sessionId) {
        await _detachActiveSession();
      }
      final current = state as AcpConnected;
      state = current.copyWith(
        recentSessions: current.recentSessions
            .where((session) => session.sessionId != sessionId)
            .toList(growable: false),
        busy: null,
        lastError: null,
      );
      return true;
    } on Object catch (error) {
      _endAction(error: '$error');
      return false;
    }
  }

  Future<bool> refreshSessions({String? cwd}) =>
      _listSessions(cwd: cwd, append: false);

  Future<bool> loadMoreSessions() {
    final connected = state;
    if (connected is! AcpConnected || connected.nextSessionCursor == null) {
      return Future.value(false);
    }
    return _listSessions(
      cwd: connected.activeSession?.cwd ?? _defaultSessionSpec?.cwd,
      cursor: connected.nextSessionCursor,
      append: true,
    );
  }

  Future<bool> _listSessions({
    required bool append,
    String? cwd,
    String? cursor,
  }) async {
    final client = _client;
    final connected = state;
    if (client == null || connected is! AcpConnected) return false;
    if (!connected.canListSessions) {
      _setLastError('The connected agent does not support session listing.');
      return false;
    }
    if (!_beginAction(AcpBusyAction.listSessions)) return false;
    try {
      final response = await client.client.listSessions(
        ListSessionsRequest(cwd: cwd, cursor: cursor),
        timeout: _controlTimeout,
      );
      final current = state as AcpConnected;
      final sessions = append
          ? _mergeSessionLists(current.recentSessions, response.sessions)
          : List<SessionInfo>.unmodifiable(response.sessions);
      state = current.copyWith(
        recentSessions: sessions,
        nextSessionCursor: response.nextCursor,
        busy: null,
        lastError: null,
      );
      return true;
    } on Object catch (error) {
      _endAction(error: '$error');
      return false;
    }
  }

  Future<bool> setMode(String modeId) async {
    final session = _session;
    final connected = state;
    final sessionState = _activeSessionState;
    if (session == null || connected is! AcpConnected || sessionState == null) {
      return false;
    }
    if (!(sessionState.modes?.availableModes ?? const []).any(
      (mode) => mode.id == modeId,
    )) {
      _setLastError('The active session did not advertise mode "$modeId".');
      return false;
    }
    if (!_beginAction(AcpBusyAction.setMode)) return false;
    try {
      await session.setMode(modeId, timeout: _controlTimeout);
      final latest = _activeSessionState;
      if (latest != null && latest.sessionId == session.sessionId) {
        _activeSessionState = latest.copyWith(modes: session.modes);
      }
      _endAction();
      _publishState();
      return true;
    } on Object catch (error) {
      _endAction(error: '$error');
      return false;
    }
  }

  Future<bool> setConfigOption(String configId, Object value) async {
    final session = _session;
    final connected = state;
    final sessionState = _activeSessionState;
    if (session == null || connected is! AcpConnected || sessionState == null) {
      return false;
    }
    final matches = sessionState.configOptions.where(
      (option) => option.id == configId,
    );
    if (matches.isEmpty) {
      _setLastError(
        'The active session did not advertise config option "$configId".',
      );
      return false;
    }
    final option = matches.first;
    late final SetSessionConfigOptionRequest request;
    switch (option) {
      case SessionConfigBooleanOption():
        if (value is! bool) {
          _setLastError('Config option "$configId" requires a boolean value.');
          return false;
        }
        request = SetBooleanConfigOption(
          sessionId: session.sessionId,
          configId: configId,
          value: value,
        );
      case SessionConfigSelectOptionValue(:final options):
        if (value is! String || !_selectOptionValues(options).contains(value)) {
          _setLastError(
            'Config option "$configId" requires one advertised value.',
          );
          return false;
        }
        request = SetValueIdConfigOption(
          sessionId: session.sessionId,
          configId: configId,
          value: value,
        );
    }
    if (!_beginAction(AcpBusyAction.setConfig)) return false;
    try {
      final options = await session.setConfigOption(
        request,
        timeout: _controlTimeout,
      );
      final latest = _activeSessionState;
      if (latest != null && latest.sessionId == session.sessionId) {
        _activeSessionState = latest.copyWith(configOptions: options);
      }
      _endAction();
      _publishState();
      return true;
    } on Object catch (error) {
      _endAction(error: '$error');
      return false;
    }
  }

  Future<bool> _createSessionInternal({
    required String cwd,
    required List<String> additionalDirectories,
    required List<McpServer> mcpServers,
    required bool exposeBusyState,
  }) async {
    final client = _client;
    final connected = state;
    if (client == null || connected is! AcpConnected) return false;
    if (exposeBusyState && !_beginAction(AcpBusyAction.createSession)) {
      return false;
    }
    Session? candidate;
    try {
      final spec = _canonicalizeSessionSpec(
        cwd: cwd,
        additionalDirectories: additionalDirectories,
        mcpServers: mcpServers,
      );
      _validateSessionSpec(spec, connected.capabilities);
      _beginPendingSession(null, captureUnknown: true);
      candidate = await Session.create(
        client,
        NewSessionRequest(
          cwd: spec.cwd,
          additionalDirectories: spec.additionalDirectories,
          mcpServers: spec.mcpServers,
        ),
        timeout: _sessionSetupTimeout,
      );
      _pendingSessionId = candidate.sessionId;
      _throwIfPendingSessionOverflow();
      _defaultSessionSpec = spec;
      await _activateSession(candidate, spec);
      _endAction(
        authStatus: connected.authMethods.isEmpty
            ? AcpAuthStatus.unavailable
            : AcpAuthStatus.authenticated,
      );
      return true;
    } on Object catch (error) {
      candidate?.dispose();
      _endAction(
        error: '$error',
        authStatus: _authStatusAfterError(error, connected),
      );
      return false;
    } finally {
      _clearPendingSession();
    }
  }

  Future<void> _activateSession(Session session, AcpSessionSpec spec) async {
    final updates = List<SessionUpdate>.unmodifiable(
      _pendingSessionUpdates[session.sessionId] ?? const [],
    );
    await _detachActiveSession();
    _session = session;
    _sessionRootsCanonical
      ..clear()
      ..add(spec.cwd)
      ..addAll(spec.additionalDirectories);
    _messages.clear();
    _activeSessionState = AcpSessionState(
      sessionId: session.sessionId,
      cwd: spec.cwd,
      additionalDirectories: spec.additionalDirectories,
      mcpServers: spec.mcpServers,
      modes: session.modes,
      configOptions: List.unmodifiable(session.configOptions),
    );
    final connected = state;
    if (connected is AcpConnected) {
      state = connected.copyWith(
        recentSessions: _mergeSessionLists(<SessionInfo>[
          SessionInfo(
            sessionId: session.sessionId,
            cwd: spec.cwd,
            additionalDirectories: spec.additionalDirectories,
          ),
        ], connected.recentSessions),
      );
    }
    for (final update in updates) {
      _applySessionUpdate(update, publish: false);
    }
    for (var index = 0; index < _messages.length; index++) {
      _messages[index] = _messages[index].copyWith(isStreaming: false);
    }
    _publishState();
  }

  Future<void> _detachActiveSession({
    bool sessionAlreadyDisposed = false,
  }) async {
    final session = _session;
    final terminals = _terminals.values.toList(growable: false);
    _session = null;
    _activeSessionState = null;
    _sessionRootsCanonical.clear();
    _messages.clear();
    _activeTurn?.cancelTimer?.cancel();
    _activeTurn = null;
    _isPrompting = false;
    for (final pending in _permissionQueue) {
      pending.complete(const PermissionCancelled());
    }
    _permissionQueue.clear();
    _terminals.clear();
    if (!sessionAlreadyDisposed) session?.dispose();
    await Future.wait<void>([
      for (final terminal in terminals) terminal.dispose(),
    ]);
    _publishState();
  }

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

  /// Clears the latest recoverable ACP error without changing the connection
  /// or active session.
  void clearLastError() {
    final current = state;
    if (current is AcpConnected && current.lastError != null) {
      state = current.copyWith(lastError: null);
    }
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

    final active = _activeSessionState;
    state = current.copyWith(
      sessionDefaults: _defaultSessionSpec,
      activeSession: active?.copyWith(
        messages: List.unmodifiable(_messages),
        pendingPermission: promptHead,
        isPrompting: _isPrompting,
      ),
    );
  }

  bool _beginAction(AcpBusyAction action) {
    final current = state;
    if (current is! AcpConnected || current.busy != null || _isPrompting) {
      return false;
    }
    state = current.copyWith(busy: action, lastError: null);
    return true;
  }

  void _endAction({String? error, AcpAuthStatus? authStatus}) {
    final current = state;
    if (current is! AcpConnected) return;
    state = current.copyWith(
      busy: null,
      lastError: error,
      authStatus: authStatus,
    );
  }

  void _setLastError(String message) {
    final current = state;
    if (current is AcpConnected) {
      state = current.copyWith(lastError: message);
    }
  }

  void _setAuthRequired(String message) {
    final current = state;
    if (current is AcpConnected) {
      state = current.copyWith(
        authStatus: AcpAuthStatus.required,
        lastError: message,
      );
    }
  }

  AcpAuthStatus _authStatusAfterError(Object error, AcpConnected connected) {
    if (error is RpcError && error.code == ErrorCode.authRequired.code) {
      return AcpAuthStatus.required;
    }
    return connected.authStatus;
  }

  void _beginPendingSession(String? sessionId, {bool captureUnknown = false}) {
    _pendingSessionId = sessionId;
    _captureUnknownPendingSession = captureUnknown;
    _pendingSessionUpdates.clear();
    _pendingSessionOverflowError = null;
  }

  void _clearPendingSession() {
    _pendingSessionId = null;
    _captureUnknownPendingSession = false;
    _pendingSessionUpdates.clear();
    _pendingSessionOverflowError = null;
  }

  void _throwIfPendingSessionOverflow() {
    final error = _pendingSessionOverflowError;
    if (error != null) throw StateError(error);
  }

  void _handleSessionUpdateNotification(Object? params) {
    final notification = _parseSessionUpdate(params);
    if (notification == null) return;
    final acceptsPending =
        notification.sessionId == _pendingSessionId ||
        (_captureUnknownPendingSession && _pendingSessionId == null);
    if (acceptsPending) {
      final retainedCount = _pendingSessionUpdates.values.fold<int>(
        0,
        (count, updates) => count + updates.length,
      );
      if (retainedCount >= _maximumPendingSessionUpdates) {
        _pendingSessionOverflowError =
            'Session setup emitted more than $_maximumPendingSessionUpdates updates; '
            'the session was not opened because partial history is unsafe.';
        return;
      }
      _pendingSessionUpdates
          .putIfAbsent(notification.sessionId, () => <SessionUpdate>[])
          .add(notification.update);
      return;
    }
    if (notification.sessionId == _session?.sessionId) {
      _applySessionUpdate(notification.update);
    }
  }

  void _applySessionUpdate(SessionUpdate update, {bool publish = true}) {
    var sessionState = _activeSessionState;
    if (sessionState == null) return;
    switch (update) {
      case UserMessageChunk(:final chunk):
        final turn = _activeTurn;
        if (turn != null && _isActiveTurn(turn)) {
          final firstMessageId = turn.userEchoMessageId;
          if (turn.userEchoContent.isEmpty ||
              chunk.messageId == null ||
              firstMessageId == null ||
              chunk.messageId == firstMessageId) {
            turn.userEchoMessageId ??= chunk.messageId;
            turn.userEchoContent.add(chunk.content);
          } else {
            _appendMessageChunk(AcpMessageRole.user, chunk);
          }
          if (turn.userEchoMessageId != null) {
            _messages[turn.userIndex] = _messages[turn.userIndex].copyWith(
              messageId: turn.userEchoMessageId,
            );
          }
        } else {
          _appendMessageChunk(AcpMessageRole.user, chunk);
        }
      case AgentMessageChunk(:final chunk):
        _appendMessageChunk(AcpMessageRole.assistant, chunk);
      case AgentThoughtChunk(:final chunk):
        final text = _extractText(chunk.content);
        if (text.isNotEmpty) _appendThought(text);
      case ToolCallUpdateSession(:final toolCall):
        final toolCalls = Map<String, AcpToolCallState>.of(
          sessionState.toolCalls,
        )..[toolCall.toolCallId] = AcpToolCallState.fromToolCall(toolCall);
        sessionState = sessionState.copyWith(toolCalls: toolCalls);
        _attachToolCall(toolCall.toolCallId);
      case ToolCallStatusUpdate(:final update):
        final toolCalls = Map<String, AcpToolCallState>.of(
          sessionState.toolCalls,
        );
        toolCalls[update.toolCallId] =
            toolCalls[update.toolCallId]?.merge(update) ??
            AcpToolCallState.fromUpdate(update);
        sessionState = sessionState.copyWith(toolCalls: toolCalls);
        _attachToolCall(update.toolCallId);
      case PlanUpdate(:final plan):
        sessionState = sessionState.copyWith(plan: plan);
      case AvailableCommandsSessionUpdate(:final update):
        sessionState = sessionState.copyWith(
          availableCommands: update.availableCommands,
        );
      case CurrentModeSessionUpdate(:final currentModeId):
        final currentModes = sessionState.modes;
        sessionState = sessionState.copyWith(
          modes: SessionModeState(
            currentModeId: currentModeId,
            availableModes: currentModes?.availableModes ?? const [],
            meta: currentModes?.meta,
          ),
        );
      case ConfigOptionSessionUpdate(:final configOptions):
        sessionState = sessionState.copyWith(configOptions: configOptions);
      case SessionInfoSessionUpdate(:final title, :final updatedAt):
        sessionState = sessionState.copyWith(
          title: title ?? sessionState.title,
          updatedAt: updatedAt ?? sessionState.updatedAt,
        );
        _updateRecentSessionInfo(
          sessionState.sessionId,
          title: title,
          updatedAt: updatedAt,
        );
      case UsageSessionUpdate(
        :final used,
        :final size,
        :final cost,
        :final meta,
      ):
        final currentUsage = sessionState.usage;
        sessionState = sessionState.copyWith(
          usage: UsageUpdate(
            used: used ?? currentUsage?.used,
            size: size ?? currentUsage?.size,
            cost: cost ?? currentUsage?.cost,
            meta: meta.isEmpty ? currentUsage?.meta : meta,
          ),
        );
      case _:
        return;
    }
    _activeSessionState = sessionState;
    if (publish) _publishState();
  }

  void _appendMessageChunk(AcpMessageRole role, ContentChunk chunk) {
    int? index;
    final turn = _activeTurn;
    if (role == AcpMessageRole.assistant &&
        turn != null &&
        _isActiveTurn(turn)) {
      index = _activeAssistantMessageIndex(turn, chunk.messageId);
    } else if (chunk.messageId != null) {
      for (var candidate = _messages.length - 1; candidate >= 0; candidate--) {
        final message = _messages[candidate];
        if (message.role == role && message.messageId == chunk.messageId) {
          index = candidate;
          break;
        }
      }
    } else if (_messages.isNotEmpty &&
        _messages.last.role == role &&
        _messages.last.isStreaming) {
      index = _messages.length - 1;
    }

    if (index == null) {
      index = _messages.length;
      _messages.add(
        AcpChatMessage(
          role: role,
          text: '',
          messageId: chunk.messageId,
          isStreaming: true,
        ),
      );
    }
    final current = _messages[index];
    final content = <ContentBlock>[...current.content, chunk.content];
    _messages[index] = current.copyWith(
      text: current.text + _extractText(chunk.content),
      messageId: chunk.messageId ?? current.messageId,
      content: List.unmodifiable(content),
    );
  }

  void _appendThought(String text) {
    final index = _assistantMessageIndex(create: true);
    final current = _messages[index];
    _messages[index] = current.copyWith(
      thoughts: List.unmodifiable(<String>[...current.thoughts, text]),
    );
  }

  void _attachToolCall(String toolCallId) {
    final index = _assistantMessageIndex(create: true);
    final current = _messages[index];
    if (current.toolCallIds.contains(toolCallId)) return;
    _messages[index] = current.copyWith(
      toolCallIds: List.unmodifiable(<String>[
        ...current.toolCallIds,
        toolCallId,
      ]),
    );
  }

  int _assistantMessageIndex({required bool create}) {
    final turn = _activeTurn;
    if (turn != null && _isActiveTurn(turn)) {
      return turn.currentAssistantIndex;
    }
    for (var index = _messages.length - 1; index >= 0; index--) {
      if (_messages[index].role == AcpMessageRole.assistant) return index;
    }
    if (!create) return -1;
    final index = _messages.length;
    _messages.add(
      const AcpChatMessage(
        role: AcpMessageRole.assistant,
        text: '',
        isStreaming: true,
      ),
    );
    return index;
  }

  int _activeAssistantMessageIndex(_ActiveTurn turn, String? messageId) {
    if (messageId != null) {
      for (
        var index = _messages.length - 1;
        index >= turn.assistantIndex;
        index--
      ) {
        final message = _messages[index];
        if (message.role == AcpMessageRole.assistant &&
            message.messageId == messageId) {
          turn.currentAssistantIndex = index;
          return index;
        }
      }
    }

    final currentIndex = turn.currentAssistantIndex;
    final current = _messages[currentIndex];
    if (messageId == null ||
        current.messageId == null ||
        current.messageId == messageId) {
      return currentIndex;
    }

    if (current.isStreaming) {
      _messages[currentIndex] = current.copyWith(isStreaming: false);
    }
    final index = _messages.length;
    _messages.add(
      AcpChatMessage(
        role: AcpMessageRole.assistant,
        text: '',
        messageId: messageId,
        isStreaming: true,
      ),
    );
    turn.currentAssistantIndex = index;
    return index;
  }

  List<int> _turnAssistantMessageIndices(_ActiveTurn turn) {
    return <int>[
      for (var index = turn.assistantIndex; index < _messages.length; index++)
        if (_messages[index].role == AcpMessageRole.assistant) index,
    ];
  }

  void _updateRecentSessionInfo(
    String sessionId, {
    String? title,
    String? updatedAt,
  }) {
    final current = state;
    if (current is! AcpConnected) return;
    state = current.copyWith(
      recentSessions: current.recentSessions
          .map((session) {
            if (session.sessionId != sessionId) return session;
            return SessionInfo(
              sessionId: session.sessionId,
              cwd: session.cwd,
              additionalDirectories: session.additionalDirectories,
              title: title ?? session.title,
              updatedAt: updatedAt ?? session.updatedAt,
              meta: session.meta,
            );
          })
          .toList(growable: false),
    );
  }

  AcpSessionSpec _canonicalizeSessionSpec({
    required String cwd,
    required List<String> additionalDirectories,
    required List<McpServer> mcpServers,
  }) {
    final canonicalCwd = Directory(p.absolute(cwd)).resolveSymbolicLinksSync();
    final directories = additionalDirectories
        .map((directory) {
          final requested = p.isAbsolute(directory)
              ? directory
              : p.join(canonicalCwd, directory);
          return Directory(requested).resolveSymbolicLinksSync();
        })
        .toSet()
        .where((directory) => !p.equals(directory, canonicalCwd))
        .toList(growable: false);
    return AcpSessionSpec(
      cwd: canonicalCwd,
      additionalDirectories: directories,
      mcpServers: List.unmodifiable(mcpServers),
    );
  }

  void _validateSessionSpec(
    AcpSessionSpec spec,
    AgentCapabilities capabilities,
  ) {
    if (spec.additionalDirectories.isNotEmpty &&
        capabilities.sessionCapabilities?.additionalDirectories == null) {
      throw StateError(
        'The connected agent does not support additional session directories.',
      );
    }
    final names = <String>{};
    for (final server in spec.mcpServers) {
      final name = server.name.trim();
      if (name.isEmpty) {
        throw StateError('MCP servers require a non-empty name.');
      }
      if (!names.add(name)) {
        throw StateError('MCP server names must be unique: ${server.name}.');
      }
      switch (server) {
        case McpServerHttp(:final url):
          if (capabilities.mcpCapabilities?.http != true) {
            throw StateError(
              'The connected agent does not support HTTP MCP servers.',
            );
          }
          _requireHttpUri(url, server.name);
        case McpServerSse(:final url):
          if (capabilities.mcpCapabilities?.sse != true) {
            throw StateError(
              'The connected agent does not support SSE MCP servers.',
            );
          }
          _requireHttpUri(url, server.name);
        case McpServerStdio(:final command):
          if (command.trim().isEmpty || !p.isAbsolute(command)) {
            throw StateError(
              'MCP stdio server "${server.name}" requires an absolute executable path.',
            );
          }
      }
    }
  }

  void _requireHttpUri(String value, String serverName) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError(
        'MCP server "$serverName" requires an absolute HTTP(S) URL.',
      );
    }
  }

  // ===========================================================================
  // Client role construction
  // ===========================================================================

  ClientRole _buildClientRole() {
    return ClientRole()
        .onRequestPermission((context, request, cancellation) async {
          _requireActiveSession(request.sessionId);
          final toolCall = _mergePermissionToolCall(request.toolCall);
          final pending = _PendingPermission(
            id: 'permission-$_lifecycleGeneration-${_permissionCounter++}',
            request: request,
            toolCall: toolCall,
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
          return RequestPermissionResponse(outcome: outcome);
        })
        .onReadTextFile((context, request, cancellation) async {
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
            final filePath = confinePathToRoots(
              request.path,
              _sessionRootsCanonical,
            );
            final content = await readAcpTextFile(
              File(filePath),
              line: request.line,
              limit: request.limit,
              isCancelled: () =>
                  cancellation.isCancelled ||
                  _session?.sessionId != request.sessionId,
            );
            return ReadTextFileResponse(content: content);
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
        .onWriteTextFile((context, request, cancellation) async {
          _requireActiveSession(request.sessionId);
          try {
            final filePath = confinePathToRoots(
              request.path,
              _sessionRootsCanonical,
            );
            await writeAcpTextFileAtomically(
              File(filePath),
              request.content,
              isCancelled: () =>
                  cancellation.isCancelled ||
                  _session?.sessionId != request.sessionId,
            );
            return const WriteTextFileResponse();
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
        .onCreateTerminal((context, request, cancellation) async {
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
            return CreateTerminalResponse(terminalId: terminal.id);
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
        .onTerminalOutput((context, request, cancellation) async {
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          return TerminalOutputResponse(
            output: terminal.output,
            truncated: terminal.truncated,
            exitStatus: terminal.exitStatus,
          );
        })
        .onWaitForTerminalExit((context, request, cancellation) async {
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          final exitCode = await Future.any<int?>([
            terminal.exitCodeFuture,
            cancellation.whenCancelled.then((_) => null),
          ]);
          if (cancellation.isCancelled) {
            return const WaitForTerminalExitResponse();
          }
          return WaitForTerminalExitResponse(exitCode: exitCode);
        })
        .onReleaseTerminal((context, request, cancellation) async {
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          _terminals.remove(request.terminalId);
          await terminal.dispose();
          return const ReleaseTerminalResponse();
        })
        .onKillTerminal((context, request, cancellation) async {
          _requireActiveSession(request.sessionId);
          final terminal = _requireTerminal(request.terminalId);
          if (!terminal.kill()) {
            throw _structuredError(
              ErrorCode.internalError,
              'Failed to terminate terminal ${request.terminalId}.',
            );
          }
          return const KillTerminalResponse();
        });
  }

  AcpToolCallState _mergePermissionToolCall(ToolCallUpdate update) {
    final session = _activeSessionState;
    final existing = session?.toolCalls[update.toolCallId];
    final merged = existing == null
        ? AcpToolCallState.fromUpdate(update)
        : existing.merge(update);
    if (session != null) {
      _activeSessionState = session.copyWith(
        toolCalls: Map.unmodifiable({
          ...session.toolCalls,
          update.toolCallId: merged,
        }),
      );
    }
    return merged;
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
  /// active session roots. Invalid or escaping paths are rejected rather than
  /// silently running the command from a different directory.
  String _resolveTerminalCwd(String? requested) {
    if (_sessionRootsCanonical.isEmpty) {
      throw StateError('No active ACP session root.');
    }
    return requested == null
        ? _sessionRootsCanonical.first
        : confinePathToRoots(requested, _sessionRootsCanonical);
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
      final text = _agentStderr.toString();
      final cut = text.indexOf('\n', overflow);
      final kept = cut >= 0
          ? text.substring(cut + 1)
          : text.substring(text.length - _maximumAgentStderrChars);
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
    _defaultSessionSpec = null;
    _activeSessionState = null;
    _sessionRootsCanonical.clear();
    _sessionUpdateSub?.dispose();
    _sessionUpdateSub = null;
    _clearPendingSession();
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
    _defaultSessionSpec = null;
    _activeSessionState = null;
    _sessionRootsCanonical.clear();
    _sessionUpdateSub?.dispose();
    _sessionUpdateSub = null;
    _clearPendingSession();
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

/// Resolves [path] within the primary session cwd or one advertised additional
/// directory. Relative paths always use the primary cwd; absolute paths may
/// target any advertised root.
String confinePathToRoots(String path, List<String> roots) {
  if (roots.isEmpty) {
    throw const AcpPathEscapeException('No active ACP session roots.');
  }
  if (!p.isAbsolute(path)) return confinePathToRoot(path, roots.first);
  for (final root in roots) {
    try {
      return confinePathToRoot(path, root);
    } on AcpPathEscapeException {
      // Try the next explicitly advertised root.
    }
  }
  throw AcpPathEscapeException(
    'Path "$path" resolves outside every active session root.',
  );
}

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

List<SessionInfo> _mergeSessionLists(
  List<SessionInfo> existing,
  List<SessionInfo> incoming,
) {
  final merged = <String, SessionInfo>{
    for (final session in existing) session.sessionId: session,
    for (final session in incoming) session.sessionId: session,
  };
  return List<SessionInfo>.unmodifiable(merged.values);
}

Set<String> _selectOptionValues(SessionConfigSelectOptions options) {
  return switch (options) {
    SessionConfigUngroupedOptions(:final options) => {
      for (final option in options) option.value,
    },
    SessionConfigGroupedOptions(:final groups) => {
      for (final group in groups)
        for (final option in group.options) option.value,
    },
  };
}

String _contentText(Iterable<ContentBlock> content) =>
    content.whereType<TextContentBlock>().map((block) => block.text).join();

/// A pending permission request awaiting user response.
class _PendingPermission {
  _PendingPermission({
    required this.id,
    required this.request,
    required this.toolCall,
  });

  final String id;
  final RequestPermissionRequest request;
  final AcpToolCallState toolCall;
  AcpPermissionPrompt get prompt => AcpPermissionPrompt(
    requestId: id,
    toolCall: toolCall,
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
    required this.userIndex,
    required this.assistantIndex,
  });

  final int generation;
  final Session session;
  final int userIndex;
  final int assistantIndex;
  late int currentAssistantIndex = assistantIndex;
  final List<ContentBlock> userEchoContent = [];
  String? userEchoMessageId;
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

final class AcpPromptValidationException implements Exception {
  const AcpPromptValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

void _validatePromptContent(
  List<ContentBlock> content,
  AgentCapabilities capabilities,
) {
  if (content.isEmpty) {
    throw const AcpPromptValidationException('A prompt cannot be empty.');
  }
  var hasMeaningfulContent = false;
  for (final block in content) {
    switch (block) {
      case TextContentBlock(:final text):
        hasMeaningfulContent |= text.trim().isNotEmpty;
      case ImageContent(:final data, :final mimeType):
        if (capabilities.promptCapabilities?.image != true) {
          throw const AcpPromptValidationException(
            'The connected agent does not support image prompts.',
          );
        }
        if (!mimeType.startsWith('image/') || !_isValidBase64(data)) {
          throw const AcpPromptValidationException(
            'Image prompts require a valid image MIME type and base64 data.',
          );
        }
        hasMeaningfulContent = true;
      case AudioContent(:final data, :final mimeType):
        if (capabilities.promptCapabilities?.audio != true) {
          throw const AcpPromptValidationException(
            'The connected agent does not support audio prompts.',
          );
        }
        if (!mimeType.startsWith('audio/') || !_isValidBase64(data)) {
          throw const AcpPromptValidationException(
            'Audio prompts require a valid audio MIME type and base64 data.',
          );
        }
        hasMeaningfulContent = true;
      case ResourceLink(:final uri):
        if (!(Uri.tryParse(uri)?.hasScheme ?? false)) {
          throw const AcpPromptValidationException(
            'Resource links require an absolute URI with a scheme.',
          );
        }
        hasMeaningfulContent = true;
      case EmbeddedResource(:final resource):
        if (capabilities.promptCapabilities?.embeddedContext != true) {
          throw const AcpPromptValidationException(
            'The connected agent does not support embedded context.',
          );
        }
        if (resource is BlobResourceContents &&
            !_isValidBase64(resource.blob)) {
          throw const AcpPromptValidationException(
            'Embedded binary resources require valid base64 data.',
          );
        }
        hasMeaningfulContent = true;
    }
  }
  if (!hasMeaningfulContent) {
    throw const AcpPromptValidationException(
      'A prompt must contain text or an attachment.',
    );
  }
  final payloadBytes = utf8
      .encode(
        jsonEncode(<Object?>[for (final block in content) block.toJson()]),
      )
      .length;
  if (payloadBytes > _maximumPromptPayloadBytes) {
    throw AcpPromptValidationException(
      'The encoded prompt is ${_formatByteCount(payloadBytes)}. The ACP stdio '
      'payload limit is ${_formatByteCount(_maximumPromptPayloadBytes)}.',
    );
  }
}

bool _isValidBase64(String value) {
  if (value.isEmpty) return false;
  try {
    base64Decode(value);
    return true;
  } on FormatException {
    return false;
  }
}

String _formatByteCount(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
  return '${(kib / 1024).toStringAsFixed(1)} MiB';
}

String _extractText(ContentBlock block) {
  if (block is TextContentBlock) return block.text;
  return '';
}

bool _messageHasContent(AcpChatMessage message) =>
    message.text.isNotEmpty ||
    message.thoughts.isNotEmpty ||
    message.toolCallIds.isNotEmpty ||
    message.content.isNotEmpty;
