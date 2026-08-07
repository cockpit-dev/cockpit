/// [ClientContext] — methods a client calls on the agent during a connection.
///
/// A client initializes the connection, creates or loads a session, sends
/// prompts, and manages session lifecycle. This context wraps a [Connection]
/// to expose those agent-side methods as typed Dart functions.
library;

import 'dart:async';
import '../json_codec.dart';
import '../jsonrpc/connection.dart';
import '../schema/requests.dart';
import '../schema/prompt_fs.dart';

/// The client's view of the agent, for issuing agent-side ACP requests.
class ClientContext {
  ClientContext(this._conn);

  final Connection _conn;

  /// Sends an `initialize` request.
  Future<InitializeResponse> initialize(InitializeRequest request) {
    return _conn.sendRequest(
      'initialize',
      params: request.toJson(),
      mapResult: (r) => InitializeResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends an `authenticate` request.
  Future<void> authenticate(AuthenticateRequest request) {
    return _conn.sendRequest(
      'authenticate',
      params: request.toJson(),
      mapResult: (_) {},
    );
  }

  /// Sends a `logout` request.
  Future<void> logout() {
    return _conn.sendRequest(
      'logout',
      params: const LogoutRequest().toJson(),
      mapResult: (_) {},
    );
  }

  /// Sends a `session/new` request.
  Future<NewSessionResponse> newSession(NewSessionRequest request) {
    return _conn.sendRequest(
      'session/new',
      params: request.toJson(),
      mapResult: (r) => NewSessionResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `session/load` request.
  Future<LoadSessionResponse> loadSession(LoadSessionRequest request) {
    return _conn.sendRequest(
      'session/load',
      params: request.toJson(),
      mapResult: (r) => LoadSessionResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `session/list` request.
  Future<ListSessionsResponse> listSessions(ListSessionsRequest request) {
    return _conn.sendRequest(
      'session/list',
      params: request.toJson(),
      mapResult: (r) => ListSessionsResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `session/delete` request.
  Future<void> deleteSession(DeleteSessionRequest request) {
    return _conn.sendRequest(
      'session/delete',
      params: request.toJson(),
      mapResult: (_) {},
    );
  }

  /// Sends a `session/resume` request.
  Future<ResumeSessionResponse> resumeSession(ResumeSessionRequest request) {
    return _conn.sendRequest(
      'session/resume',
      params: request.toJson(),
      mapResult: (r) => ResumeSessionResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `session/close` request.
  Future<void> closeSession(CloseSessionRequest request) {
    return _conn.sendRequest(
      'session/close',
      params: request.toJson(),
      mapResult: (_) {},
    );
  }

  /// Sends a `session/set_mode` request.
  Future<void> setSessionMode(SetSessionModeRequest request) {
    return _conn.sendRequest(
      'session/set_mode',
      params: request.toJson(),
      mapResult: (_) {},
    );
  }

  /// Sends a `session/set_config_option` request.
  Future<SetSessionConfigOptionResponse> setSessionConfigOption(
      SetSessionConfigOptionRequest request) {
    return _conn.sendRequest(
      'session/set_config_option',
      params: request.toJson(),
      mapResult: (r) =>
          SetSessionConfigOptionResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `session/prompt` request. The [PromptResponse] arrives when the
  /// turn ends; intermediate updates arrive via `session/update` notifications
  /// (subscribe through the [Connection] or a higher-level [Session]).
  Future<PromptResponse> prompt(PromptRequest request) {
    return _conn.sendRequest(
      'session/prompt',
      params: request.toJson(),
      mapResult: (r) => PromptResponse.fromJson(asJsonObject(r)),
    );
  }

  /// Sends a `session/cancel` notification.
  void cancel(String sessionId) {
    _conn.notify('session/cancel', params: {'sessionId': sessionId});
  }
}
