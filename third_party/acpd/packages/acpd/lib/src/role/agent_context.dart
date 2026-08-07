/// [AgentContext] — methods an agent calls on the client during a connection.
///
/// An agent receives requests (initialize, session/new, session/prompt) and,
/// while handling them, calls back into the client for permissions, session
/// updates, file access, and terminal control. This context wraps a
/// [Connection] to expose those client-side methods as typed Dart functions.
library;

import 'dart:async';
import '../json_codec.dart';
import '../jsonrpc/connection.dart';
import '../schema/session_update.dart';
import '../schema/prompt_fs.dart';
import '../schema/terminal_permission.dart';

/// The agent's view of the client, for issuing client-side ACP requests.
class AgentContext {
  AgentContext(this._conn);

  final Connection _conn;

  /// Sends a `session/update` notification.
  void sessionUpdate(
      {required String sessionId, required SessionUpdate update}) {
    _conn.notify('session/update', params: {
      'sessionId': sessionId,
      'update': update.toJson(),
    });
  }

  /// Sends a `session/request_permission` request.
  Future<RequestPermissionOutcome> requestPermission(
      RequestPermissionRequest request) {
    return _conn.sendRequest(
      'session/request_permission',
      params: request.toJson(),
      mapResult: (r) =>
          RequestPermissionResponse.fromJson(asJsonObject(r)).outcome,
    );
  }

  /// Sends a `fs/read_text_file` request.
  Future<ReadTextFileResponse> readTextFile(ReadTextFileRequest request) {
    return _conn.sendRequest(
      'fs/read_text_file',
      params: request.toJson(),
      mapResult: (r) => ReadTextFileResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `fs/write_text_file` request.
  Future<WriteTextFileResponse> writeTextFile(WriteTextFileRequest request) {
    return _conn.sendRequest(
      'fs/write_text_file',
      params: request.toJson(),
      mapResult: (r) => WriteTextFileResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `terminal/create` request.
  Future<CreateTerminalResponse> createTerminal(CreateTerminalRequest request) {
    return _conn.sendRequest(
      'terminal/create',
      params: request.toJson(),
      mapResult: (r) => CreateTerminalResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `terminal/output` request.
  Future<TerminalOutputResponse> terminalOutput(TerminalOutputRequest request) {
    return _conn.sendRequest(
      'terminal/output',
      params: request.toJson(),
      mapResult: (r) => TerminalOutputResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `terminal/release` request.
  Future<void> releaseTerminal(ReleaseTerminalRequest request) {
    return _conn.sendRequest(
      'terminal/release',
      params: request.toJson(),
      mapResult: (_) {},
    );
  }

  /// Sends a `terminal/wait_for_exit` request.
  Future<WaitForTerminalExitResponse> waitForTerminalExit(
      WaitForTerminalExitRequest request) {
    return _conn.sendRequest(
      'terminal/wait_for_exit',
      params: request.toJson(),
      mapResult: (r) => WaitForTerminalExitResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `terminal/kill` request.
  Future<void> killTerminal(KillTerminalRequest request) {
    return _conn.sendRequest(
      'terminal/kill',
      params: request.toJson(),
      mapResult: (_) {},
    );
  }
}
