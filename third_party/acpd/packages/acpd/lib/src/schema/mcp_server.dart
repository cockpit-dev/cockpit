/// MCP server configuration types.
///
/// [McpServer] is a sealed union over transport type: stdio (default), http,
/// or sse. All agents must support stdio; http/sse require the matching
/// `mcpCapabilities`.
library;

import '../json_codec.dart';

/// An HTTP header to set when making requests to an MCP server.
class HttpHeader {
  const HttpHeader(
      {required this.name, required this.value, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final String name;
  final String value;
  final Map<String, Object?> meta;

  factory HttpHeader.fromJson(Map<String, Object?> json) {
    return HttpHeader(
      name: requireField<String>(json, 'name'),
      value: requireField<String>(json, 'value'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'name': name, 'value': value};
    writeMeta(json, meta);
    return json;
  }
}

/// An environment variable to set when launching an MCP server.
class EnvVariable {
  const EnvVariable(
      {required this.name, required this.value, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final String name;
  final String value;
  final Map<String, Object?> meta;

  factory EnvVariable.fromJson(Map<String, Object?> json) {
    return EnvVariable(
      name: requireField<String>(json, 'name'),
      value: requireField<String>(json, 'value'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'name': name, 'value': value};
    writeMeta(json, meta);
    return json;
  }
}

/// MCP server configuration.
sealed class McpServer {
  const McpServer({required this.name, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// Human-readable name identifying this server.
  final String name;

  /// The transport discriminator (null = stdio).
  String? get type;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  /// Parses by `type`: `http`/`sse` → typed; absent/null → stdio.
  static McpServer fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'http' => McpServerHttp.fromJson(json),
      'sse' => McpServerSse.fromJson(json),
      _ => McpServerStdio.fromJson(json),
    };
  }

  Map<String, Object?> toJson();
}

/// Stdio transport configuration (all agents must support this).
final class McpServerStdio extends McpServer {
  const McpServerStdio({
    required super.name,
    required this.command,
    this.args = const [],
    this.env = const [],
    super.meta,
  });

  /// Absolute path to the executable.
  final String command;

  /// Command-line arguments.
  final List<String> args;

  /// Environment variables.
  final List<EnvVariable> env;

  @override
  String? get type => null;

  factory McpServerStdio.fromJson(Map<String, Object?> json) {
    return McpServerStdio(
      name: requireField<String>(json, 'name'),
      command: requireField<String>(json, 'command'),
      args: _readStringList(json['args']),
      env: readListField(json, 'env', EnvVariable.fromJson),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'name': name,
      'command': command,
      'args': args,
      'env': env.map((e) => e.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// HTTP transport configuration.
final class McpServerHttp extends McpServer {
  const McpServerHttp({
    required super.name,
    required this.url,
    this.headers = const [],
    super.meta,
  });

  final String url;
  final List<HttpHeader> headers;

  @override
  String? get type => 'http';

  factory McpServerHttp.fromJson(Map<String, Object?> json) {
    return McpServerHttp(
      name: requireField<String>(json, 'name'),
      url: requireField<String>(json, 'url'),
      headers: readListField(json, 'headers', HttpHeader.fromJson),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': 'http',
      'name': name,
      'url': url,
      'headers': headers.map((h) => h.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// SSE transport configuration.
final class McpServerSse extends McpServer {
  const McpServerSse({
    required super.name,
    required this.url,
    this.headers = const [],
    super.meta,
  });

  final String url;
  final List<HttpHeader> headers;

  @override
  String? get type => 'sse';

  factory McpServerSse.fromJson(Map<String, Object?> json) {
    return McpServerSse(
      name: requireField<String>(json, 'name'),
      url: requireField<String>(json, 'url'),
      headers: readListField(json, 'headers', HttpHeader.fromJson),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': 'sse',
      'name': name,
      'url': url,
      'headers': headers.map((h) => h.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList();
}
