/// Session modes — operating states the agent can be in.
library;

import '../json_codec.dart';

/// A mode the agent can operate in (e.g. "plan", "normal").
class SessionMode {
  const SessionMode({
    required this.id,
    required this.name,
    this.description,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Stable identifier.
  final String id;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;

  final Map<String, Object?> meta;

  factory SessionMode.fromJson(Map<String, Object?> json) {
    return SessionMode(
      id: requireField<String>(json, 'id'),
      name: requireField<String>(json, 'name'),
      description: readField<String>(json, 'description'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'id': id,
      'name': name,
    };
    if (description != null) json['description'] = description;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionMode &&
          id == other.id &&
          name == other.name &&
          description == other.description &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(id, name, description, meta);
}

/// The set of modes and the one currently active.
class SessionModeState {
  const SessionModeState({
    required this.currentModeId,
    this.availableModes = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// The current mode.
  final String currentModeId;

  /// All available modes.
  final List<SessionMode> availableModes;

  final Map<String, Object?> meta;

  factory SessionModeState.fromJson(Map<String, Object?> json) {
    return SessionModeState(
      currentModeId: requireField<String>(json, 'currentModeId'),
      availableModes:
          readListField(json, 'availableModes', SessionMode.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'currentModeId': currentModeId,
      'availableModes': availableModes.map((m) => m.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}
