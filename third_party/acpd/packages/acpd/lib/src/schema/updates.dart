/// Usage, cost, session-info, mode, and command update types.
///
/// These are the smaller update payloads carried by [SessionUpdate] variants.
library;

import '../json_codec.dart';
import 'session_config.dart';

/// Cumulative session cost.
class Cost {
  const Cost(
      {required this.amount,
      required this.currency,
      Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// Total cumulative cost for the session.
  final double amount;

  /// ISO 4217 currency code (e.g. `USD`, `EUR`).
  final String currency;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory Cost.fromJson(Map<String, Object?> json) {
    return Cost(
      amount: requireField<num>(json, 'amount').toDouble(),
      currency: requireField<String>(json, 'currency'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'amount': amount,
      'currency': currency,
    };
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cost &&
          amount == other.amount &&
          currency == other.currency &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(amount, currency, meta);
}

/// Context window and cost update.
class UsageUpdate {
  const UsageUpdate(
      {this.used, this.size, this.cost, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// Tokens currently in context.
  final int? used;

  /// Total context window size in tokens.
  final int? size;

  /// Cumulative session cost (optional).
  final Cost? cost;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory UsageUpdate.fromJson(Map<String, Object?> json) {
    return UsageUpdate(
      used: readField<int>(json, 'used'),
      size: readField<int>(json, 'size'),
      cost: _readCost(json['cost']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (used != null) json['used'] = used;
    if (size != null) json['size'] = size;
    if (cost != null) json['cost'] = cost!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

Cost? _readCost(Object? raw) {
  if (raw is Map<String, Object?>) return Cost.fromJson(raw);
  return null;
}

/// Information about a session (from `session/list`).
class SessionInfo {
  const SessionInfo({
    required this.sessionId,
    required this.cwd,
    this.additionalDirectories = const [],
    this.title,
    this.updatedAt,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String sessionId;
  final String cwd;
  final List<String> additionalDirectories;
  final String? title;
  final String? updatedAt;
  final Map<String, Object?> meta;

  factory SessionInfo.fromJson(Map<String, Object?> json) {
    return SessionInfo(
      sessionId: requireField<String>(json, 'sessionId'),
      cwd: requireField<String>(json, 'cwd'),
      additionalDirectories: _readStringList(json['additionalDirectories']),
      title: readField<String>(json, 'title'),
      updatedAt: readField<String>(json, 'updatedAt'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'cwd': cwd,
    };
    if (additionalDirectories.isNotEmpty) {
      json['additionalDirectories'] = additionalDirectories;
    }
    if (title != null) json['title'] = title;
    if (updatedAt != null) json['updatedAt'] = updatedAt;
    writeMeta(json, meta);
    return json;
  }
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList();
}

/// Update to session metadata (partial).
class SessionInfoUpdate {
  const SessionInfoUpdate(
      {this.title, this.updatedAt, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final String? title;
  final String? updatedAt;
  final Map<String, Object?> meta;

  factory SessionInfoUpdate.fromJson(Map<String, Object?> json) {
    return SessionInfoUpdate(
      title: readField<String>(json, 'title'),
      updatedAt: readField<String>(json, 'updatedAt'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (title != null) json['title'] = title;
    if (updatedAt != null) json['updatedAt'] = updatedAt;
    writeMeta(json, meta);
    return json;
  }
}

/// Unstructured command input — all text typed after the command name.
class UnstructuredCommandInput {
  const UnstructuredCommandInput(
      {required this.hint, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// A hint displayed when input hasn't been provided yet.
  final String hint;
  final Map<String, Object?> meta;

  factory UnstructuredCommandInput.fromJson(Map<String, Object?> json) {
    return UnstructuredCommandInput(
      hint: requireField<String>(json, 'hint'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'hint': hint};
    writeMeta(json, meta);
    return json;
  }
}

/// Information about a command the agent can execute.
class AvailableCommand {
  const AvailableCommand({
    required this.name,
    required this.description,
    this.input,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Command name (e.g. `create_plan`).
  final String name;

  /// Human-readable description.
  final String description;

  /// Optional input specification.
  final UnstructuredCommandInput? input;

  final Map<String, Object?> meta;

  factory AvailableCommand.fromJson(Map<String, Object?> json) {
    return AvailableCommand(
      name: requireField<String>(json, 'name'),
      description: requireField<String>(json, 'description'),
      input: _readInput(json['input']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'name': name,
      'description': description,
    };
    if (input != null) {
      json['input'] = input!.toJson();
    }
    writeMeta(json, meta);
    return json;
  }
}

UnstructuredCommandInput? _readInput(Object? raw) {
  if (raw is Map<String, Object?>) {
    return UnstructuredCommandInput.fromJson(raw);
  }
  return null;
}

/// Notification that available commands changed.
class AvailableCommandsUpdate {
  const AvailableCommandsUpdate({
    this.availableCommands = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final List<AvailableCommand> availableCommands;
  final Map<String, Object?> meta;

  factory AvailableCommandsUpdate.fromJson(Map<String, Object?> json) {
    return AvailableCommandsUpdate(
      availableCommands:
          readListField(json, 'availableCommands', AvailableCommand.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'availableCommands': availableCommands.map((c) => c.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// The current mode of the session changed.
class CurrentModeUpdate {
  const CurrentModeUpdate(
      {required this.currentModeId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final String currentModeId;
  final Map<String, Object?> meta;

  factory CurrentModeUpdate.fromJson(Map<String, Object?> json) {
    return CurrentModeUpdate(
      currentModeId: requireField<String>(json, 'currentModeId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'currentModeId': currentModeId};
    writeMeta(json, meta);
    return json;
  }
}

/// Session configuration options updated.
class ConfigOptionUpdate {
  const ConfigOptionUpdate({
    this.configOptions = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final List<SessionConfigOption> configOptions;
  final Map<String, Object?> meta;

  factory ConfigOptionUpdate.fromJson(Map<String, Object?> json) {
    return ConfigOptionUpdate(
      configOptions:
          readListField(json, 'configOptions', SessionConfigOption.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'configOptions': configOptions.map((o) => o.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}
