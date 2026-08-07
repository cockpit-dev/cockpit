/// Session updates streamed during a prompt turn.
///
/// [SessionUpdate] is a sealed union with 11 variants discriminated by the
/// `sessionUpdate` field. These provide real-time feedback about agent
/// progress: message chunks, tool calls, plans, commands, mode/config changes,
/// and usage.
library;

import '../json_codec.dart';
import 'tool_call.dart';
import 'tool_call_content.dart';
import 'plan.dart';
import 'updates.dart';
import 'session_config.dart';

/// The discriminator value for each [SessionUpdate] variant.
extension type const SessionUpdateKind(String value) {
  static const userMessageChunk = SessionUpdateKind('user_message_chunk');
  static const agentMessageChunk = SessionUpdateKind('agent_message_chunk');
  static const agentThoughtChunk = SessionUpdateKind('agent_thought_chunk');
  static const toolCall = SessionUpdateKind('tool_call');
  static const toolCallUpdate = SessionUpdateKind('tool_call_update');
  static const plan = SessionUpdateKind('plan');
  static const availableCommandsUpdate =
      SessionUpdateKind('available_commands_update');
  static const currentModeUpdate = SessionUpdateKind('current_mode_update');
  static const configOptionUpdate = SessionUpdateKind('config_option_update');
  static const sessionInfoUpdate = SessionUpdateKind('session_info_update');
  static const usageUpdate = SessionUpdateKind('usage_update');
}

/// A session update — one of 11 variants.
sealed class SessionUpdate {
  const SessionUpdate(this.kind);

  /// The wire discriminator.
  final SessionUpdateKind kind;

  /// The [_meta] payload shared by all variants.
  Map<String, Object?> get meta;

  /// Parses a session update by its `sessionUpdate` discriminator.
  static SessionUpdate fromJson(Map<String, Object?> json) {
    final kind = json['sessionUpdate'] as String;
    return switch (kind) {
      'user_message_chunk' => UserMessageChunk.fromJson(json),
      'agent_message_chunk' => AgentMessageChunk.fromJson(json),
      'agent_thought_chunk' => AgentThoughtChunk.fromJson(json),
      'tool_call' => ToolCallUpdateSession.fromJson(json),
      'tool_call_update' => ToolCallStatusUpdate.fromJson(json),
      'plan' => PlanUpdate.fromJson(json),
      'available_commands_update' =>
        AvailableCommandsSessionUpdate.fromJson(json),
      'current_mode_update' => CurrentModeSessionUpdate.fromJson(json),
      'config_option_update' => ConfigOptionSessionUpdate.fromJson(json),
      'session_info_update' => SessionInfoSessionUpdate.fromJson(json),
      'usage_update' => UsageSessionUpdate.fromJson(json),
      _ => throw FormatException('Unknown session update "$kind": $json'),
    };
  }

  Map<String, Object?> toJson();
}

/// Base class mixing in [ContentChunk] fields for chunk-style updates.
abstract class _ChunkUpdate extends SessionUpdate {
  _ChunkUpdate(super.kind, {required this.chunk});

  /// The content chunk payload.
  final ContentChunk chunk;

  @override
  Map<String, Object?> get meta => chunk.meta;

  @override
  Map<String, Object?> toJson() {
    final json = chunk.toJson();
    json['sessionUpdate'] = kind.value;
    return json;
  }
}

/// A chunk of the user's message being streamed.
final class UserMessageChunk extends _ChunkUpdate {
  UserMessageChunk({required super.chunk})
      : super(SessionUpdateKind.userMessageChunk);

  factory UserMessageChunk.fromJson(Map<String, Object?> json) =>
      UserMessageChunk(chunk: ContentChunk.fromJson(json));
}

/// A chunk of the agent's response being streamed.
final class AgentMessageChunk extends _ChunkUpdate {
  AgentMessageChunk({required super.chunk})
      : super(SessionUpdateKind.agentMessageChunk);

  factory AgentMessageChunk.fromJson(Map<String, Object?> json) =>
      AgentMessageChunk(chunk: ContentChunk.fromJson(json));
}

/// A chunk of the agent's internal reasoning being streamed.
final class AgentThoughtChunk extends _ChunkUpdate {
  AgentThoughtChunk({required super.chunk})
      : super(SessionUpdateKind.agentThoughtChunk);

  factory AgentThoughtChunk.fromJson(Map<String, Object?> json) =>
      AgentThoughtChunk(chunk: ContentChunk.fromJson(json));
}

/// Notification that a new tool call has been initiated.
final class ToolCallUpdateSession extends SessionUpdate {
  ToolCallUpdateSession({required this.toolCall, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.toolCall);

  final ToolCall toolCall;

  @override
  final Map<String, Object?> meta;

  factory ToolCallUpdateSession.fromJson(Map<String, Object?> json) {
    final tc = ToolCall.fromJson(json);
    return ToolCallUpdateSession(toolCall: tc, meta: tc.meta);
  }

  @override
  Map<String, Object?> toJson() {
    final json = toolCall.toJson();
    json['sessionUpdate'] = kind.value;
    return json;
  }
}

/// Update on the status or results of a tool call.
final class ToolCallStatusUpdate extends SessionUpdate {
  ToolCallStatusUpdate({required this.update, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.toolCallUpdate);

  final ToolCallUpdate update;

  @override
  final Map<String, Object?> meta;

  factory ToolCallStatusUpdate.fromJson(Map<String, Object?> json) {
    final u = ToolCallUpdate.fromJson(json);
    return ToolCallStatusUpdate(update: u, meta: u.meta);
  }

  @override
  Map<String, Object?> toJson() {
    final json = update.toJson();
    json['sessionUpdate'] = kind.value;
    return json;
  }
}

/// The agent's execution plan.
final class PlanUpdate extends SessionUpdate {
  PlanUpdate({required this.plan, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.plan);

  final Plan plan;

  @override
  final Map<String, Object?> meta;

  factory PlanUpdate.fromJson(Map<String, Object?> json) {
    final p = Plan.fromJson(json);
    return PlanUpdate(plan: p, meta: p.meta);
  }

  @override
  Map<String, Object?> toJson() {
    final json = plan.toJson();
    json['sessionUpdate'] = kind.value;
    return json;
  }
}

/// Available commands are ready or have changed.
final class AvailableCommandsSessionUpdate extends SessionUpdate {
  AvailableCommandsSessionUpdate(
      {required this.update, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.availableCommandsUpdate);

  final AvailableCommandsUpdate update;

  @override
  final Map<String, Object?> meta;

  factory AvailableCommandsSessionUpdate.fromJson(Map<String, Object?> json) {
    final u = AvailableCommandsUpdate.fromJson(json);
    return AvailableCommandsSessionUpdate(update: u, meta: u.meta);
  }

  @override
  Map<String, Object?> toJson() {
    final json = update.toJson();
    json['sessionUpdate'] = kind.value;
    return json;
  }
}

/// The current mode of the session changed.
final class CurrentModeSessionUpdate extends SessionUpdate {
  CurrentModeSessionUpdate(
      {required this.currentModeId, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.currentModeUpdate);

  final String currentModeId;

  @override
  final Map<String, Object?> meta;

  factory CurrentModeSessionUpdate.fromJson(Map<String, Object?> json) {
    return CurrentModeSessionUpdate(
      currentModeId: requireField<String>(json, 'currentModeId'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionUpdate': kind.value,
      'currentModeId': currentModeId,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Session configuration options updated.
final class ConfigOptionSessionUpdate extends SessionUpdate {
  ConfigOptionSessionUpdate(
      {required this.configOptions, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.configOptionUpdate);

  final List<SessionConfigOption> configOptions;

  @override
  final Map<String, Object?> meta;

  factory ConfigOptionSessionUpdate.fromJson(Map<String, Object?> json) {
    return ConfigOptionSessionUpdate(
      configOptions:
          readListField(json, 'configOptions', SessionConfigOption.fromJson),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionUpdate': kind.value,
      'configOptions': configOptions.map((o) => o.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Session metadata updated (title, timestamps).
final class SessionInfoSessionUpdate extends SessionUpdate {
  SessionInfoSessionUpdate(
      {this.title, this.updatedAt, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.sessionInfoUpdate);

  final String? title;
  final String? updatedAt;

  @override
  final Map<String, Object?> meta;

  factory SessionInfoSessionUpdate.fromJson(Map<String, Object?> json) {
    return SessionInfoSessionUpdate(
      title: readField<String>(json, 'title'),
      updatedAt: readField<String>(json, 'updatedAt'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'sessionUpdate': kind.value};
    if (title != null) json['title'] = title;
    if (updatedAt != null) json['updatedAt'] = updatedAt;
    writeMeta(json, meta);
    return json;
  }
}

/// Context window and cost update.
final class UsageSessionUpdate extends SessionUpdate {
  UsageSessionUpdate(
      {this.used, this.size, this.cost, Map<String, Object?>? meta})
      : meta = meta ?? const {},
        super(SessionUpdateKind.usageUpdate);

  final int? used;
  final int? size;
  final Cost? cost;

  @override
  final Map<String, Object?> meta;

  factory UsageSessionUpdate.fromJson(Map<String, Object?> json) {
    return UsageSessionUpdate(
      used: readField<int>(json, 'used'),
      size: readField<int>(json, 'size'),
      cost: _readCost(json['cost']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'sessionUpdate': kind.value};
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

/// The `session/update` notification envelope: binds a [sessionId] to an
/// [update] payload.
class SessionUpdateNotification {
  const SessionUpdateNotification(
      {required this.sessionId,
      required this.update,
      Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final String sessionId;
  final SessionUpdate update;
  final Map<String, Object?> meta;

  factory SessionUpdateNotification.fromJson(Map<String, Object?> json) {
    return SessionUpdateNotification(
      sessionId: requireField<String>(json, 'sessionId'),
      update: SessionUpdate.fromJson(
          requireField<Map<String, Object?>>(json, 'update')),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'update': update.toJson(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// The `$/cancel_request` protocol-level notification payload.
class CancelRequestNotification {
  const CancelRequestNotification(
      {required this.requestId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// The JSON-RPC method name.
  static const methodName = r'$/cancel_request';

  /// The id of the request to cancel.
  final Object requestId;

  final Map<String, Object?> meta;

  factory CancelRequestNotification.fromJson(Map<String, Object?> json) {
    return CancelRequestNotification(
      requestId: requireField<Object>(json, 'requestId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'requestId': requestId};
    writeMeta(json, meta);
    return json;
  }
}

/// The `session/cancel` client→agent notification payload.
class CancelNotification {
  const CancelNotification(
      {required this.sessionId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// The JSON-RPC method name.
  static const methodName = 'session/cancel';

  final String sessionId;

  final Map<String, Object?> meta;

  factory CancelNotification.fromJson(Map<String, Object?> json) {
    return CancelNotification(
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
