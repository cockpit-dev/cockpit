/// High-level session helper for the client-side prompt-turn lifecycle.
///
/// A [Session] wraps a [ClientConnection] and a session id, collecting
/// `session/update` notifications into a buffer while a prompt turn runs.
/// [sendPrompt] returns once the turn ends (the `session/prompt` response
/// arrives), yielding the [StopReason] plus all updates observed during the
/// turn. This mirrors the Rust SDK's `Session::send_prompt` + `read_to_string`
/// pattern.
library;

import 'dart:async';
import '../jsonrpc/connection.dart';
import '../role/role.dart';
import '../schema/enums.dart';
import '../schema/content.dart';
import '../schema/session_update.dart';
import '../schema/requests.dart';
import '../schema/session_modes.dart';
import '../schema/session_config.dart';
import '../schema/prompt_fs.dart';

/// The result of a prompt turn: the terminal [stopReason] and every
/// [SessionUpdate] observed during the turn, in arrival order.
class PromptTurnResult {
  const PromptTurnResult({required this.stopReason, required this.updates});

  /// Why the turn ended.
  final StopReason stopReason;

  /// All updates streamed during the turn.
  final List<SessionUpdate> updates;

  /// Concatenated text from agent message chunks.
  String get agentText => updates
      .whereType<AgentMessageChunk>()
      .map((c) => _chunkText(c.chunk.content))
      .join();

  /// Concatenated text from user message chunks.
  String get userText => updates
      .whereType<UserMessageChunk>()
      .map((c) => _chunkText(c.chunk.content))
      .join();

  /// Tool calls initiated during the turn.
  List<ToolCallUpdateSession> get toolCalls =>
      updates.whereType<ToolCallUpdateSession>().toList();

  /// Tool-call status updates during the turn.
  List<ToolCallStatusUpdate> get toolCallUpdates =>
      updates.whereType<ToolCallStatusUpdate>().toList();
}

String _chunkText(ContentBlock block) {
  if (block is TextContentBlock) return block.text;
  return '';
}

/// A high-level client session bound to a [ClientConnection].
///
/// Create via [Session.create] (calls `session/new`) or [Session.load] (calls
class Session {
  Session._(this._conn, this.sessionId);

  final ClientConnection _conn;

  /// The session identifier.
  final String sessionId;

  /// Modes advertised by the agent for this session (from session/new or
  /// session/load). Null if the agent did not report modes.
  SessionModeState? modes;

  /// Configuration options advertised for this session.
  List<SessionConfigOption> configOptions = const [];

  /// The `_meta` from the session response.
  Map<String, Object?> meta = const {};

  /// Updates received outside a turn (cleared at each [sendPrompt]).
  final List<SessionUpdate> _backgroundUpdates = [];

  HandlerRegistration? _backgroundSub;

  /// Creates a new session via `session/new`.
  static Future<Session> create(
    ClientConnection conn,
    NewSessionRequest request,
  ) async {
    // Register the background listener before sending session/new, so any
    // updates the agent emits during setup are not lost. The sessionId is
    // unknown until the response arrives, so we buffer unconditionally and
    // rebind to the real id once known.
    final early = <SessionUpdate>[];
    final earlySub = conn.connection.onNotification('session/update', (params) {
      final notif = _parseUpdate(params);
      if (notif != null) early.add(notif.update);
    });
    final resp = await conn.client.newSession(request);
    final session = Session._(conn, resp.sessionId);
    session.modes = resp.modes.isNotEmpty
        ? SessionModeState(
            currentModeId: resp.modes.first.id,
            availableModes: resp.modes,
          )
        : null;
    session.configOptions = resp.configOptions;
    session.meta = resp.meta;
    session._backgroundUpdates.addAll(early);
    earlySub.dispose();
    session._startBackgroundListener();
    return session;
  }

  /// Loads an existing session via `session/load`.
  static Future<Session> load(
    ClientConnection conn,
    LoadSessionRequest request,
  ) async {
    final session = Session._(conn, request.sessionId);
    session._startBackgroundListener();
    final resp = await conn.client.loadSession(request);
    session.modes = resp.modes.isNotEmpty
        ? SessionModeState(
            currentModeId: resp.modes.first.id,
            availableModes: resp.modes,
          )
        : null;
    session.configOptions = resp.configOptions;
    session.meta = resp.meta;
    return session;
  }

  void _startBackgroundListener() {
    _backgroundSub =
        _conn.connection.onNotification('session/update', (params) {
      final notif = _parseUpdate(params);
      if (notif != null && notif.sessionId == sessionId) {
        _backgroundUpdates.add(notif.update);
      }
    });
  }

  /// Sends a prompt and collects all `session/update` notifications until the
  /// turn ends.
  Future<PromptTurnResult> sendPrompt(List<ContentBlock> prompt) async {
    final updates = <SessionUpdate>[];
    updates.addAll(_backgroundUpdates);
    _backgroundUpdates.clear();

    final reg = _conn.connection.onNotification('session/update', (params) {
      final notif = _parseUpdate(params);
      if (notif != null && notif.sessionId == sessionId) {
        updates.add(notif.update);
      }
    });

    try {
      final response = await _conn.client.prompt(PromptRequest(
        sessionId: sessionId,
        prompt: prompt,
      ));
      // Flush queued notifications before returning.
      await Future<void>.delayed(Duration.zero);
      return PromptTurnResult(
        stopReason: response.stopReason,
        updates: updates,
      );
    } finally {
      reg.dispose();
      // The background listener also captured turn updates; drop them so the
      // next turn starts clean.
      _backgroundUpdates.clear();
    }
  }

  /// Cancels the ongoing turn via `session/cancel`.
  void cancel() => _conn.client.cancel(sessionId);

  /// Releases background notification listening.
  void dispose() => _backgroundSub?.dispose();
}

SessionUpdateNotification? _parseUpdate(Object? params) {
  if (params is Map<String, Object?>) {
    return SessionUpdateNotification.fromJson(params);
  }
  return null;
}
