/// Authentication, implementation metadata, and simple identifier types.
library;

import '../json_codec.dart';

/// Metadata about a client or agent implementation.
class Implementation {
  const Implementation({
    required this.name,
    required this.version,
    this.title,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Programmatic name.
  final String name;

  /// Semantic version.
  final String version;

  /// Optional human-readable UI title.
  final String? title;

  final Map<String, Object?> meta;

  factory Implementation.fromJson(Map<String, Object?> json) {
    return Implementation(
      name: requireField<String>(json, 'name'),
      version: requireField<String>(json, 'version'),
      title: readField<String>(json, 'title'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'name': name, 'version': version};
    if (title != null) json['title'] = title;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Implementation &&
          name == other.name &&
          version == other.version &&
          title == other.title &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(name, version, title, meta);
}

/// Agent-handled authentication method (default type).
class AuthMethodAgent {
  const AuthMethodAgent({
    required this.id,
    required this.name,
    this.description,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Unique identifier for this method.
  final String id;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;

  final Map<String, Object?> meta;

  factory AuthMethodAgent.fromJson(Map<String, Object?> json) {
    return AuthMethodAgent(
      id: requireField<String>(json, 'id'),
      name: requireField<String>(json, 'name'),
      description: readField<String>(json, 'description'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'id': id, 'name': name};
    if (description != null) json['description'] = description;
    writeMeta(json, meta);
    return json;
  }
}

///
/// The `type` field discriminates the method; when absent it is treated as
/// `agent`. Only `agent` is defined in v1.
sealed class AuthMethod {
  const AuthMethod();

  static AuthMethod fromJson(Map<String, Object?> json) {
    return AgentAuthMethod(AuthMethodAgent.fromJson(json));
  }

  Map<String, Object?> toJson();

  /// The auth-method identifier.
  String get id;
}

/// The agent auth-method variant.
final class AgentAuthMethod extends AuthMethod {
  const AgentAuthMethod(this.agent);

  final AuthMethodAgent agent;

  @override
  String get id => agent.id;

  @override
  Map<String, Object?> toJson() => agent.toJson();
}
