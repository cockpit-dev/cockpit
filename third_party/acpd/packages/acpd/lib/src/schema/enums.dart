/// Enumeration types defined by the Agent Client Protocol schema.
///
/// These cover every `enum`/`const`-discriminated string and integer type in
/// the ACP JSON schema. Each enum maps between its snake_case wire value and
/// the Dart enum value via [fromJson]/[toJson].
library;

/// Protocol version identifier.
///
/// A single integer bumped only for breaking changes. Non-breaking additions
/// are negotiated via capabilities. The stable protocol version is [v1].
enum ProtocolVersion {
  /// ACP protocol version 1 — the current stable wire version.
  v1(1);

  const ProtocolVersion(this.value);

  /// The integer value sent on the wire.
  final int value;

  /// Parses a protocol version integer.
  static ProtocolVersion fromJson(int value) {
    return switch (value) {
      1 => v1,
      _ => throw FormatException('Unknown protocol version: $value'),
    };
  }

  /// Serializes the version to its wire integer.
  int toJson() => value;
}

/// The sender or recipient of a message in a conversation.
enum Role {
  /// The assistant side of a conversation.
  assistant,

  /// The user side of a conversation.
  user;

  /// Parses a role from its snake_case wire value.
  static Role fromJson(String value) => switch (value) {
        'assistant' => assistant,
        'user' => user,
        _ => throw FormatException('Unknown role: $value'),
      };

  /// Serializes the role to its wire value.
  String toJson() => switch (this) {
        assistant => 'assistant',
        user => 'user',
      };
}

/// Categories of tools that an agent can invoke.
///
/// Helps clients choose appropriate icons and optimize tool-progress display.
enum ToolKind {
  read,
  edit,
  delete,
  move,
  search,
  execute,
  think,
  fetch,
  switchMode,
  other;

  /// Parses a tool kind, falling back to [other] on unknown values.
  ///
  /// Matches the schema's `x-deserialize-default-on-error` semantics: unknown
  /// tool kinds must not break deserialization.
  static ToolKind fromJson(String? value) => switch (value) {
        'read' => read,
        'edit' => edit,
        'delete' => delete,
        'move' => move,
        'search' => search,
        'execute' => execute,
        'think' => think,
        'fetch' => fetch,
        'switch_mode' => switchMode,
        _ => other,
      };

  /// Serializes to the wire value.
  String toJson() => switch (this) {
        read => 'read',
        edit => 'edit',
        delete => 'delete',
        move => 'move',
        search => 'search',
        execute => 'execute',
        think => 'think',
        fetch => 'fetch',
        switchMode => 'switch_mode',
        other => 'other',
      };
}

/// Execution status of a tool call.
enum ToolCallStatus {
  pending,
  inProgress,
  completed,
  failed;

  /// Parses a status, defaulting to [pending] on unknown values.
  static ToolCallStatus fromJson(String? value) => switch (value) {
        'pending' => pending,
        'in_progress' => inProgress,
        'completed' => completed,
        'failed' => failed,
        _ => pending,
      };

  String toJson() => switch (this) {
        pending => 'pending',
        inProgress => 'in_progress',
        completed => 'completed',
        failed => 'failed',
      };
}

/// Reasons why an agent stops processing a prompt turn.
enum StopReason {
  endTurn,
  maxTokens,
  maxTurnRequests,
  refusal,
  cancelled;

  static StopReason fromJson(String value) => switch (value) {
        'end_turn' => endTurn,
        'max_tokens' => maxTokens,
        'max_turn_requests' => maxTurnRequests,
        'refusal' => refusal,
        'cancelled' => cancelled,
        _ => throw FormatException('Unknown stop reason: $value'),
      };

  String toJson() => switch (this) {
        endTurn => 'end_turn',
        maxTokens => 'max_tokens',
        maxTurnRequests => 'max_turn_requests',
        refusal => 'refusal',
        cancelled => 'cancelled',
      };
}

/// The type of permission option presented to the user.
enum PermissionOptionKind {
  allowOnce,
  allowAlways,
  rejectOnce,
  rejectAlways;

  static PermissionOptionKind fromJson(String value) => switch (value) {
        'allow_once' => allowOnce,
        'allow_always' => allowAlways,
        'reject_once' => rejectOnce,
        'reject_always' => rejectAlways,
        _ => throw FormatException('Unknown permission option kind: $value'),
      };

  String toJson() => switch (this) {
        allowOnce => 'allow_once',
        allowAlways => 'allow_always',
        rejectOnce => 'reject_once',
        rejectAlways => 'reject_always',
      };
}

/// Priority levels for plan entries.
enum PlanEntryPriority {
  high,
  medium,
  low;

  static PlanEntryPriority fromJson(String value) => switch (value) {
        'high' => high,
        'medium' => medium,
        'low' => low,
        _ => throw FormatException('Unknown plan priority: $value'),
      };

  String toJson() => switch (this) {
        high => 'high',
        medium => 'medium',
        low => 'low',
      };
}

/// Status of a plan entry in the execution flow.
enum PlanEntryStatus {
  pending,
  inProgress,
  completed;

  static PlanEntryStatus fromJson(String value) => switch (value) {
        'pending' => pending,
        'in_progress' => inProgress,
        'completed' => completed,
        _ => throw FormatException('Unknown plan status: $value'),
      };

  String toJson() => switch (this) {
        pending => 'pending',
        inProgress => 'in_progress',
        completed => 'completed',
      };
}

/// Semantic category for a session configuration option (UX hint only).
///
/// The `other` variant carries an arbitrary free-form string for unknown /
/// custom (`_`-prefixed) categories.
class SessionConfigOptionCategory {
  const SessionConfigOptionCategory._(this._kind, this.customValue);

  /// Session mode selector.
  static const mode = SessionConfigOptionCategory._('mode', null);

  /// Model selector.
  static const model = SessionConfigOptionCategory._('model', null);

  /// Model-related configuration parameter.
  static const modelConfig =
      SessionConfigOptionCategory._('model_config', null);

  /// Thought/reasoning level selector.
  static const thoughtLevel =
      SessionConfigOptionCategory._('thought_level', null);

  final String _kind;
  final String? customValue;

  /// Creates a custom/unknown category from an arbitrary string.
  factory SessionConfigOptionCategory.custom(String value) =>
      SessionConfigOptionCategory._('other', value);

  /// Parses a category string. Unknown reserved names become [custom].
  static SessionConfigOptionCategory fromJson(String? value) {
    return switch (value) {
      'mode' => mode,
      'model' => model,
      'model_config' => modelConfig,
      'thought_level' => thoughtLevel,
      _ => SessionConfigOptionCategory.custom(value ?? ''),
    };
  }

  /// Serializes to the wire value.
  ///
  /// Known categories emit their reserved name; custom categories emit the
  /// raw string.
  String? toJson() {
    if (_kind == 'other') return customValue;
    return _kind;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionConfigOptionCategory &&
      _kind == other._kind &&
      customValue == other.customValue;

  @override
  int get hashCode => Object.hash(_kind, customValue);

  @override
  String toString() => 'SessionConfigOptionCategory(${toJson()})';
}

/// Predefined error codes for JSON-RPC 2.0 and ACP-specific errors.
///
/// ACP uses the JSON-RPC reserved range -32000 to -32099 for protocol errors.
enum ErrorCode {
  parseError(-32700),
  invalidRequest(-32600),
  methodNotFound(-32601),
  invalidParams(-32602),
  internalError(-32603),
  requestCancelled(-32800),
  authRequired(-32000),
  inaccessibleResource(-32001),
  mcpError(-32002);

  const ErrorCode(this.code);

  /// The integer code sent on the wire.
  final int code;

  /// Looks up an [ErrorCode] by code, returning null for unknown values.
  static ErrorCode? fromCode(int code) {
    for (final ec in ErrorCode.values) {
      if (ec.code == code) return ec;
    }
    return null;
  }

  /// Serializes to the wire integer.
  int toJson() => code;
}

/// A human-readable label for each [ErrorCode], per the schema.
extension ErrorCodeMessage on ErrorCode {
  /// Returns the canonical error message for this code.
  String get message => switch (this) {
        ErrorCode.parseError => 'Parse error: Invalid JSON was received.',
        ErrorCode.invalidRequest =>
          'Invalid request: The JSON sent is not a valid Request object.',
        ErrorCode.methodNotFound =>
          'Method not found: The method does not exist or is not available.',
        ErrorCode.invalidParams =>
          'Invalid params: Invalid method parameter(s).',
        ErrorCode.internalError => 'Internal error: Internal JSON-RPC error.',
        ErrorCode.requestCancelled =>
          'Request cancelled: Execution was aborted.',
        ErrorCode.authRequired =>
          'Authentication required: The agent requires authentication.',
        ErrorCode.inaccessibleResource =>
          'Inaccessible resource: The referenced resource could not be accessed.',
        ErrorCode.mcpError => 'MCP error: An error occurred in an MCP server.',
      };
}

/// Ensures [value] is non-null, otherwise throws a [FormatException].
///
/// Used by enum parsers for strict (non-defaulting) variants.
Never unknownValue(String type, Object? value) =>
    throw FormatException('Unknown $type value: $value');
