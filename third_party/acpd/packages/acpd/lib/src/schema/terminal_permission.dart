/// Terminal and permission request/response types.
library;

import '../json_codec.dart';
import 'enums.dart';
import 'tool_call.dart';
import 'mcp_server.dart';

// =========================================================================
// Terminal
// =========================================================================

/// Exit status of a terminal command.
class TerminalExitStatus {
  const TerminalExitStatus(
      {this.exitCode, this.signal, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final int? exitCode;
  final String? signal;
  final Map<String, Object?> meta;

  factory TerminalExitStatus.fromJson(Map<String, Object?> json) {
    return TerminalExitStatus(
      exitCode: readField<int>(json, 'exitCode'),
      signal: readField<String>(json, 'signal'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (exitCode != null) json['exitCode'] = exitCode;
    if (signal != null) json['signal'] = signal;
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `terminal/create`.
class CreateTerminalRequest {
  const CreateTerminalRequest({
    required this.sessionId,
    required this.command,
    this.args = const [],
    this.env = const [],
    this.cwd,
    this.outputByteLimit,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'terminal/create';

  final String sessionId;
  final String command;
  final List<String> args;
  final List<EnvVariable> env;
  final String? cwd;
  final int? outputByteLimit;
  final Map<String, Object?> meta;

  factory CreateTerminalRequest.fromJson(Map<String, Object?> json) {
    return CreateTerminalRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      command: requireField<String>(json, 'command'),
      args: _readStringList(json['args']),
      env: readListField(json, 'env', EnvVariable.fromJson),
      cwd: readField<String>(json, 'cwd'),
      outputByteLimit: readField<int>(json, 'outputByteLimit'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'command': command,
    };
    if (args.isNotEmpty) json['args'] = args;
    if (env.isNotEmpty) json['env'] = env.map((e) => e.toJson()).toList();
    if (cwd != null) json['cwd'] = cwd;
    if (outputByteLimit != null) json['outputByteLimit'] = outputByteLimit;
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `terminal/create`.
class CreateTerminalResponse {
  const CreateTerminalResponse({
    required this.terminalId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String terminalId;
  final Map<String, Object?> meta;

  factory CreateTerminalResponse.fromJson(Map<String, Object?> json) {
    return CreateTerminalResponse(
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'terminalId': terminalId};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `terminal/output`.
class TerminalOutputRequest {
  const TerminalOutputRequest({
    required this.sessionId,
    required this.terminalId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'terminal/output';

  final String sessionId;
  final String terminalId;
  final Map<String, Object?> meta;

  factory TerminalOutputRequest.fromJson(Map<String, Object?> json) {
    return TerminalOutputRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'terminalId': terminalId,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `terminal/output`.
class TerminalOutputResponse {
  const TerminalOutputResponse({
    required this.output,
    required this.truncated,
    this.exitStatus,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String output;
  final bool truncated;
  final TerminalExitStatus? exitStatus;
  final Map<String, Object?> meta;

  factory TerminalOutputResponse.fromJson(Map<String, Object?> json) {
    return TerminalOutputResponse(
      output: requireField<String>(json, 'output'),
      truncated: requireField<bool>(json, 'truncated'),
      exitStatus: _readExit(json['exitStatus']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'output': output,
      'truncated': truncated,
    };
    if (exitStatus != null) json['exitStatus'] = exitStatus!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

TerminalExitStatus? _readExit(Object? raw) =>
    raw is Map<String, Object?> ? TerminalExitStatus.fromJson(raw) : null;

/// Request parameters for `terminal/release`.
class ReleaseTerminalRequest {
  const ReleaseTerminalRequest({
    required this.sessionId,
    required this.terminalId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'terminal/release';

  final String sessionId;
  final String terminalId;
  final Map<String, Object?> meta;

  factory ReleaseTerminalRequest.fromJson(Map<String, Object?> json) {
    return ReleaseTerminalRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'terminalId': terminalId,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `terminal/release` (empty body).
class ReleaseTerminalResponse {
  const ReleaseTerminalResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory ReleaseTerminalResponse.fromJson(Map<String, Object?> json) =>
      ReleaseTerminalResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `terminal/wait_for_exit`.
class WaitForTerminalExitRequest {
  const WaitForTerminalExitRequest({
    required this.sessionId,
    required this.terminalId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'terminal/wait_for_exit';

  final String sessionId;
  final String terminalId;
  final Map<String, Object?> meta;

  factory WaitForTerminalExitRequest.fromJson(Map<String, Object?> json) {
    return WaitForTerminalExitRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'terminalId': terminalId,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `terminal/wait_for_exit`.
class WaitForTerminalExitResponse {
  const WaitForTerminalExitResponse({
    this.exitCode,
    this.signal,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final int? exitCode;
  final String? signal;
  final Map<String, Object?> meta;

  factory WaitForTerminalExitResponse.fromJson(Map<String, Object?> json) {
    return WaitForTerminalExitResponse(
      exitCode: readField<int>(json, 'exitCode'),
      signal: readField<String>(json, 'signal'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (exitCode != null) json['exitCode'] = exitCode;
    if (signal != null) json['signal'] = signal;
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `terminal/kill`.
class KillTerminalRequest {
  const KillTerminalRequest({
    required this.sessionId,
    required this.terminalId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'terminal/kill';

  final String sessionId;
  final String terminalId;
  final Map<String, Object?> meta;

  factory KillTerminalRequest.fromJson(Map<String, Object?> json) {
    return KillTerminalRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'terminalId': terminalId,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `terminal/kill` (empty body).
class KillTerminalResponse {
  const KillTerminalResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory KillTerminalResponse.fromJson(Map<String, Object?> json) =>
      KillTerminalResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}

// =========================================================================
// Permission
// =========================================================================

/// A permission option presented to the user.
class PermissionOption {
  const PermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String optionId;
  final String name;
  final PermissionOptionKind kind;
  final Map<String, Object?> meta;

  factory PermissionOption.fromJson(Map<String, Object?> json) {
    return PermissionOption(
      optionId: requireField<String>(json, 'optionId'),
      name: requireField<String>(json, 'name'),
      kind: PermissionOptionKind.fromJson(requireField<String>(json, 'kind')),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'optionId': optionId,
      'name': name,
      'kind': kind.toJson(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/request_permission`.
class RequestPermissionRequest {
  const RequestPermissionRequest({
    required this.sessionId,
    required this.toolCall,
    required this.options,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/request_permission';

  final String sessionId;
  final ToolCall toolCall;
  final List<PermissionOption> options;
  final Map<String, Object?> meta;

  factory RequestPermissionRequest.fromJson(Map<String, Object?> json) {
    return RequestPermissionRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      toolCall: ToolCall.fromJson(
          requireField<Map<String, Object?>>(json, 'toolCall')),
      options: readListField(json, 'options', PermissionOption.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'toolCall': toolCall.toJson(),
      'options': options.map((o) => o.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// The outcome of a permission request.
sealed class RequestPermissionOutcome {
  const RequestPermissionOutcome();

  /// Parses by the `outcome` discriminator.
  static RequestPermissionOutcome fromJson(Map<String, Object?> json) {
    return switch (json['outcome']) {
      'cancelled' => const PermissionCancelled(),
      'selected' => PermissionSelected.fromJson(json),
      _ => throw FormatException(
          'Unknown permission outcome "${json['outcome']}": $json'),
    };
  }

  Map<String, Object?> toJson();
}

/// The turn was cancelled before the user responded.
final class PermissionCancelled extends RequestPermissionOutcome {
  const PermissionCancelled();

  @override
  Map<String, Object?> toJson() => {'outcome': 'cancelled'};
}

/// The user selected a permission option.
final class PermissionSelected extends RequestPermissionOutcome {
  const PermissionSelected({required this.optionId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final String optionId;
  final Map<String, Object?> meta;

  factory PermissionSelected.fromJson(Map<String, Object?> json) {
    return PermissionSelected(
      optionId: requireField<String>(json, 'optionId'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'outcome': 'selected', 'optionId': optionId};
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/request_permission`.
class RequestPermissionResponse {
  const RequestPermissionResponse({
    required this.outcome,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final RequestPermissionOutcome outcome;
  final Map<String, Object?> meta;

  factory RequestPermissionResponse.fromJson(Map<String, Object?> json) {
    return RequestPermissionResponse(
      outcome: RequestPermissionOutcome.fromJson(json),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = outcome.toJson();
    writeMeta(json, meta);
    return json;
  }
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList();
}
