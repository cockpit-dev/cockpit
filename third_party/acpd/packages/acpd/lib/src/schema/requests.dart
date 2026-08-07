/// Request and response types for the ACP protocol methods.
///
/// Organized by logical group: initialization, session lifecycle, prompt turn,
/// file system, terminal, and permission. Each type carries its JSON-RPC method
/// name as a static [methodName] constant for use by the role layer.
library;

import '../json_codec.dart';
import 'capabilities.dart';
import 'auth.dart';
import 'mcp_server.dart';
import 'enums.dart';
import 'session_modes.dart';
import 'session_config.dart';
import 'updates.dart';

// =========================================================================
// Initialization & authentication
// =========================================================================

/// Request parameters for `initialize`.
class InitializeRequest {
  const InitializeRequest({
    required this.protocolVersion,
    this.clientCapabilities,
    this.clientInfo,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'initialize';

  final ProtocolVersion protocolVersion;
  final ClientCapabilities? clientCapabilities;
  final Implementation? clientInfo;
  final Map<String, Object?> meta;

  factory InitializeRequest.fromJson(Map<String, Object?> json) {
    return InitializeRequest(
      protocolVersion:
          ProtocolVersion.fromJson(requireField<int>(json, 'protocolVersion')),
      clientCapabilities: _readClientCaps(json['clientCapabilities']),
      clientInfo: _readImpl(json['clientInfo']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'protocolVersion': protocolVersion.toJson(),
    };
    if (clientCapabilities != null) {
      json['clientCapabilities'] = clientCapabilities!.toJson();
    }
    if (clientInfo != null) json['clientInfo'] = clientInfo!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `initialize`.
class InitializeResponse {
  const InitializeResponse({
    required this.protocolVersion,
    this.agentCapabilities,
    this.authMethods = const [],
    this.agentInfo,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final ProtocolVersion protocolVersion;
  final AgentCapabilities? agentCapabilities;
  final List<AuthMethod> authMethods;
  final Implementation? agentInfo;
  final Map<String, Object?> meta;

  factory InitializeResponse.fromJson(Map<String, Object?> json) {
    return InitializeResponse(
      protocolVersion:
          ProtocolVersion.fromJson(requireField<int>(json, 'protocolVersion')),
      agentCapabilities: _readAgentCaps(json['agentCapabilities']),
      authMethods: _readAuthMethods(json['authMethods']),
      agentInfo: _readImpl(json['agentInfo']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'protocolVersion': protocolVersion.toJson(),
    };
    if (agentCapabilities != null) {
      json['agentCapabilities'] = agentCapabilities!.toJson();
    }
    if (authMethods.isNotEmpty) {
      json['authMethods'] = authMethods.map((a) => a.toJson()).toList();
    }
    if (agentInfo != null) json['agentInfo'] = agentInfo!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

ClientCapabilities? _readClientCaps(Object? raw) =>
    raw is Map<String, Object?> ? ClientCapabilities.fromJson(raw) : null;
AgentCapabilities? _readAgentCaps(Object? raw) =>
    raw is Map<String, Object?> ? AgentCapabilities.fromJson(raw) : null;
Implementation? _readImpl(Object? raw) =>
    raw is Map<String, Object?> ? Implementation.fromJson(raw) : null;

List<AuthMethod> _readAuthMethods(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, Object?>>()
      .map(AuthMethod.fromJson)
      .toList();
}

/// Request parameters for `authenticate`.
class AuthenticateRequest {
  const AuthenticateRequest(
      {required this.methodId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  static const methodName = 'authenticate';

  final String methodId;
  final Map<String, Object?> meta;

  factory AuthenticateRequest.fromJson(Map<String, Object?> json) {
    return AuthenticateRequest(
      methodId: requireField<String>(json, 'methodId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'methodId': methodId};
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `authenticate` (empty body).
class AuthenticateResponse {
  const AuthenticateResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory AuthenticateResponse.fromJson(Map<String, Object?> json) =>
      AuthenticateResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `logout`.
class LogoutRequest {
  const LogoutRequest({Map<String, Object?>? meta}) : meta = meta ?? const {};

  static const methodName = 'logout';

  final Map<String, Object?> meta;

  factory LogoutRequest.fromJson(Map<String, Object?> json) =>
      LogoutRequest(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `logout` (empty body).
class LogoutResponse {
  const LogoutResponse({Map<String, Object?>? meta}) : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory LogoutResponse.fromJson(Map<String, Object?> json) =>
      LogoutResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

// =========================================================================
// Session setup
// =========================================================================

/// Request parameters for `session/new`.
class NewSessionRequest {
  const NewSessionRequest({
    required this.cwd,
    this.additionalDirectories = const [],
    this.mcpServers = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/new';

  final String cwd;
  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;
  final Map<String, Object?> meta;

  factory NewSessionRequest.fromJson(Map<String, Object?> json) {
    return NewSessionRequest(
      cwd: requireField<String>(json, 'cwd'),
      additionalDirectories: _readStringList(json['additionalDirectories']),
      mcpServers: _readMcpServers(json['mcpServers']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'cwd': cwd,
      'mcpServers': mcpServers.map((s) => s.toJson()).toList(),
    };
    if (additionalDirectories.isNotEmpty) {
      json['additionalDirectories'] = additionalDirectories;
    }
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/new`.
class NewSessionResponse {
  const NewSessionResponse({
    required this.sessionId,
    this.modes = const [],
    this.configOptions = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String sessionId;
  final List<SessionMode> modes;
  final List<SessionConfigOption> configOptions;
  final Map<String, Object?> meta;

  factory NewSessionResponse.fromJson(Map<String, Object?> json) {
    return NewSessionResponse(
      sessionId: requireField<String>(json, 'sessionId'),
      modes: readListField(json, 'modes', SessionMode.fromJson),
      configOptions:
          readListField(json, 'configOptions', SessionConfigOption.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'sessionId': sessionId};
    if (modes.isNotEmpty) json['modes'] = modes.map((m) => m.toJson()).toList();
    if (configOptions.isNotEmpty) {
      json['configOptions'] = configOptions.map((o) => o.toJson()).toList();
    }
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/load`.
class LoadSessionRequest {
  const LoadSessionRequest({
    required this.sessionId,
    required this.cwd,
    this.additionalDirectories = const [],
    this.mcpServers = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/load';

  final String sessionId;
  final String cwd;
  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;
  final Map<String, Object?> meta;

  factory LoadSessionRequest.fromJson(Map<String, Object?> json) {
    return LoadSessionRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      cwd: requireField<String>(json, 'cwd'),
      additionalDirectories: _readStringList(json['additionalDirectories']),
      mcpServers: _readMcpServers(json['mcpServers']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'cwd': cwd,
      'mcpServers': mcpServers.map((s) => s.toJson()).toList(),
    };
    if (additionalDirectories.isNotEmpty) {
      json['additionalDirectories'] = additionalDirectories;
    }
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/load`.
class LoadSessionResponse {
  const LoadSessionResponse({
    this.modes = const [],
    this.configOptions = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final List<SessionMode> modes;
  final List<SessionConfigOption> configOptions;
  final Map<String, Object?> meta;

  factory LoadSessionResponse.fromJson(Map<String, Object?> json) {
    return LoadSessionResponse(
      modes: readListField(json, 'modes', SessionMode.fromJson),
      configOptions:
          readListField(json, 'configOptions', SessionConfigOption.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (modes.isNotEmpty) json['modes'] = modes.map((m) => m.toJson()).toList();
    if (configOptions.isNotEmpty) {
      json['configOptions'] = configOptions.map((o) => o.toJson()).toList();
    }
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/list`.
class ListSessionsRequest {
  const ListSessionsRequest({this.cwd, this.cursor, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  static const methodName = 'session/list';

  final String? cwd;
  final String? cursor;
  final Map<String, Object?> meta;

  factory ListSessionsRequest.fromJson(Map<String, Object?> json) {
    return ListSessionsRequest(
      cwd: readField<String>(json, 'cwd'),
      cursor: readField<String>(json, 'cursor'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (cwd != null) json['cwd'] = cwd;
    if (cursor != null) json['cursor'] = cursor;
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/list`.
class ListSessionsResponse {
  const ListSessionsResponse({
    required this.sessions,
    this.nextCursor,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final List<SessionInfo> sessions;
  final String? nextCursor;
  final Map<String, Object?> meta;

  factory ListSessionsResponse.fromJson(Map<String, Object?> json) {
    return ListSessionsResponse(
      sessions: readListField(json, 'sessions', SessionInfo.fromJson),
      nextCursor: readField<String>(json, 'nextCursor'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
    if (nextCursor != null) json['nextCursor'] = nextCursor;
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/delete`.
class DeleteSessionRequest {
  const DeleteSessionRequest(
      {required this.sessionId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  static const methodName = 'session/delete';

  final String sessionId;
  final Map<String, Object?> meta;

  factory DeleteSessionRequest.fromJson(Map<String, Object?> json) {
    return DeleteSessionRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'sessionId': sessionId};
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/delete` (empty body).
class DeleteSessionResponse {
  const DeleteSessionResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory DeleteSessionResponse.fromJson(Map<String, Object?> json) =>
      DeleteSessionResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/resume`.
class ResumeSessionRequest {
  const ResumeSessionRequest({
    required this.sessionId,
    required this.cwd,
    this.additionalDirectories = const [],
    this.mcpServers = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/resume';

  final String sessionId;
  final String cwd;
  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;
  final Map<String, Object?> meta;

  factory ResumeSessionRequest.fromJson(Map<String, Object?> json) {
    return ResumeSessionRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      cwd: requireField<String>(json, 'cwd'),
      additionalDirectories: _readStringList(json['additionalDirectories']),
      mcpServers: _readMcpServers(json['mcpServers']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'cwd': cwd,
      'mcpServers': mcpServers.map((s) => s.toJson()).toList(),
    };
    if (additionalDirectories.isNotEmpty) {
      json['additionalDirectories'] = additionalDirectories;
    }
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/resume`.
typedef ResumeSessionResponse = LoadSessionResponse;

/// Request parameters for `session/close`.
class CloseSessionRequest {
  const CloseSessionRequest(
      {required this.sessionId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  static const methodName = 'session/close';

  final String sessionId;
  final Map<String, Object?> meta;

  factory CloseSessionRequest.fromJson(Map<String, Object?> json) {
    return CloseSessionRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'sessionId': sessionId};
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/close` (empty body).
class CloseSessionResponse {
  const CloseSessionResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory CloseSessionResponse.fromJson(Map<String, Object?> json) =>
      CloseSessionResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/set_mode`.
class SetSessionModeRequest {
  const SetSessionModeRequest({
    required this.sessionId,
    required this.modeId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/set_mode';

  final String sessionId;
  final String modeId;
  final Map<String, Object?> meta;

  factory SetSessionModeRequest.fromJson(Map<String, Object?> json) {
    return SetSessionModeRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      modeId: requireField<String>(json, 'modeId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'modeId': modeId,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/set_mode` (empty body).
class SetSessionModeResponse {
  const SetSessionModeResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory SetSessionModeResponse.fromJson(Map<String, Object?> json) =>
      SetSessionModeResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList();
}

List<McpServer> _readMcpServers(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map<String, Object?>>().map(McpServer.fromJson).toList();
}
