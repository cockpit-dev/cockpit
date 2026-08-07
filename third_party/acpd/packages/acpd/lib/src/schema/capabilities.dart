/// Capability negotiation types exchanged during `initialize`.
library;

import '../json_codec.dart';

/// Prompt input capabilities.
class PromptCapabilities {
  const PromptCapabilities({
    this.image = false,
    this.audio = false,
    this.embeddedContext = false,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final bool image;
  final bool audio;
  final bool embeddedContext;
  final Map<String, Object?> meta;

  factory PromptCapabilities.fromJson(Map<String, Object?> json) {
    return PromptCapabilities(
      image: readFieldOr<bool>(json, 'image', false),
      audio: readFieldOr<bool>(json, 'audio', false),
      embeddedContext: readFieldOr<bool>(json, 'embeddedContext', false),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'image': image,
      'audio': audio,
      'embeddedContext': embeddedContext,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// MCP transport capabilities.
class McpCapabilities {
  const McpCapabilities({
    this.http = false,
    this.sse = false,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final bool http;
  final bool sse;
  final Map<String, Object?> meta;

  factory McpCapabilities.fromJson(Map<String, Object?> json) {
    return McpCapabilities(
      http: readFieldOr<bool>(json, 'http', false),
      sse: readFieldOr<bool>(json, 'sse', false),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'http': http, 'sse': sse};
    writeMeta(json, meta);
    return json;
  }
}

/// File-system capabilities.
class FileSystemCapabilities {
  const FileSystemCapabilities({
    this.readTextFile = false,
    this.writeTextFile = false,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final bool readTextFile;
  final bool writeTextFile;
  final Map<String, Object?> meta;

  factory FileSystemCapabilities.fromJson(Map<String, Object?> json) {
    return FileSystemCapabilities(
      readTextFile: readFieldOr<bool>(json, 'readTextFile', false),
      writeTextFile: readFieldOr<bool>(json, 'writeTextFile', false),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'readTextFile': readTextFile,
      'writeTextFile': writeTextFile,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Marker capability sub-objects (empty body, just `_meta`).
class CapabilityFlag {
  const CapabilityFlag({Map<String, Object?>? meta}) : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory CapabilityFlag.fromJson(Map<String, Object?> json) =>
      CapabilityFlag(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Logout sub-capability of [AgentAuthCapabilities].
typedef LogoutCapabilities = CapabilityFlag;

/// Session-level capability sub-objects.
typedef SessionListCapabilities = CapabilityFlag;
typedef SessionDeleteCapabilities = CapabilityFlag;
typedef SessionAdditionalDirectoriesCapabilities = CapabilityFlag;
typedef SessionResumeCapabilities = CapabilityFlag;
typedef SessionCloseCapabilities = CapabilityFlag;

/// Boolean config-option sub-capability.
class BooleanConfigOptionCapabilities {
  const BooleanConfigOptionCapabilities({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory BooleanConfigOptionCapabilities.fromJson(Map<String, Object?> json) =>
      BooleanConfigOptionCapabilities(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Client session config-options capability.
class SessionConfigOptionsCapabilities {
  const SessionConfigOptionsCapabilities(
      {this.boolean, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final BooleanConfigOptionCapabilities? boolean;
  final Map<String, Object?> meta;

  factory SessionConfigOptionsCapabilities.fromJson(Map<String, Object?> json) {
    return SessionConfigOptionsCapabilities(
      boolean: _readBooleanFlag(json['boolean']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (boolean != null) json['boolean'] = boolean!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

BooleanConfigOptionCapabilities? _readBooleanFlag(Object? raw) {
  if (raw is Map<String, Object?>) {
    return BooleanConfigOptionCapabilities.fromJson(raw);
  }
  return null;
}

/// Client-side session capabilities.
class ClientSessionCapabilities {
  const ClientSessionCapabilities(
      {this.configOptions, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final SessionConfigOptionsCapabilities? configOptions;
  final Map<String, Object?> meta;

  factory ClientSessionCapabilities.fromJson(Map<String, Object?> json) {
    return ClientSessionCapabilities(
      configOptions: _readConfigOptions(json['configOptions']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (configOptions != null) json['configOptions'] = configOptions!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

SessionConfigOptionsCapabilities? _readConfigOptions(Object? raw) {
  if (raw is Map<String, Object?>) {
    return SessionConfigOptionsCapabilities.fromJson(raw);
  }
  return null;
}

/// Agent-side session capabilities.
class SessionCapabilities {
  const SessionCapabilities({
    this.list,
    this.delete,
    this.additionalDirectories,
    this.resume,
    this.close,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final SessionListCapabilities? list;
  final SessionDeleteCapabilities? delete;
  final SessionAdditionalDirectoriesCapabilities? additionalDirectories;
  final SessionResumeCapabilities? resume;
  final SessionCloseCapabilities? close;
  final Map<String, Object?> meta;

  factory SessionCapabilities.fromJson(Map<String, Object?> json) {
    return SessionCapabilities(
      list: _readFlag(json['list']),
      delete: _readFlag(json['delete']),
      additionalDirectories: _readFlag(json['additionalDirectories']),
      resume: _readFlag(json['resume']),
      close: _readFlag(json['close']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (list != null) json['list'] = list!.toJson();
    if (delete != null) json['delete'] = delete!.toJson();
    if (additionalDirectories != null) {
      json['additionalDirectories'] = additionalDirectories!.toJson();
    }
    if (resume != null) json['resume'] = resume!.toJson();
    if (close != null) json['close'] = close!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

CapabilityFlag? _readFlag(Object? raw) {
  if (raw is Map<String, Object?>) return CapabilityFlag.fromJson(raw);
  return null;
}

/// Agent auth capabilities.
class AgentAuthCapabilities {
  const AgentAuthCapabilities({this.logout, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final LogoutCapabilities? logout;
  final Map<String, Object?> meta;

  factory AgentAuthCapabilities.fromJson(Map<String, Object?> json) {
    return AgentAuthCapabilities(
      logout: _readFlag(json['logout']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (logout != null) json['logout'] = logout!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

/// Capabilities supported by the agent.
class AgentCapabilities {
  const AgentCapabilities({
    this.loadSession = false,
    this.promptCapabilities,
    this.mcpCapabilities,
    this.sessionCapabilities,
    this.auth,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final bool loadSession;
  final PromptCapabilities? promptCapabilities;
  final McpCapabilities? mcpCapabilities;
  final SessionCapabilities? sessionCapabilities;
  final AgentAuthCapabilities? auth;
  final Map<String, Object?> meta;

  factory AgentCapabilities.fromJson(Map<String, Object?> json) {
    return AgentCapabilities(
      loadSession: readFieldOr<bool>(json, 'loadSession', false),
      promptCapabilities: _readPrompt(json['promptCapabilities']),
      mcpCapabilities: _readMcp(json['mcpCapabilities']),
      sessionCapabilities: _readSession(json['sessionCapabilities']),
      auth: _readAuth(json['auth']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'loadSession': loadSession};
    if (promptCapabilities != null) {
      json['promptCapabilities'] = promptCapabilities!.toJson();
    }
    if (mcpCapabilities != null) {
      json['mcpCapabilities'] = mcpCapabilities!.toJson();
    }
    if (sessionCapabilities != null) {
      json['sessionCapabilities'] = sessionCapabilities!.toJson();
    }
    if (auth != null) json['auth'] = auth!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

PromptCapabilities? _readPrompt(Object? raw) =>
    raw is Map<String, Object?> ? PromptCapabilities.fromJson(raw) : null;
McpCapabilities? _readMcp(Object? raw) =>
    raw is Map<String, Object?> ? McpCapabilities.fromJson(raw) : null;
SessionCapabilities? _readSession(Object? raw) =>
    raw is Map<String, Object?> ? SessionCapabilities.fromJson(raw) : null;
AgentAuthCapabilities? _readAuth(Object? raw) =>
    raw is Map<String, Object?> ? AgentAuthCapabilities.fromJson(raw) : null;

/// Capabilities supported by the client.
class ClientCapabilities {
  const ClientCapabilities({
    this.fs,
    this.terminal = false,
    this.session,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final FileSystemCapabilities? fs;
  final bool terminal;
  final ClientSessionCapabilities? session;
  final Map<String, Object?> meta;

  factory ClientCapabilities.fromJson(Map<String, Object?> json) {
    return ClientCapabilities(
      fs: _readFs(json['fs']),
      terminal: readFieldOr<bool>(json, 'terminal', false),
      session: _readClientSession(json['session']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (fs != null) json['fs'] = fs!.toJson();
    json['terminal'] = terminal;
    if (session != null) json['session'] = session!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

FileSystemCapabilities? _readFs(Object? raw) =>
    raw is Map<String, Object?> ? FileSystemCapabilities.fromJson(raw) : null;
ClientSessionCapabilities? _readClientSession(Object? raw) =>
    raw is Map<String, Object?>
        ? ClientSessionCapabilities.fromJson(raw)
        : null;
