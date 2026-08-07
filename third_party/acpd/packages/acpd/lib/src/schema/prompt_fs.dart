/// Prompt-turn, file-system, terminal, permission, and config-option requests.
library;

import '../json_codec.dart';
import 'enums.dart';
import 'content.dart';
import 'session_config.dart';

// =========================================================================
// Prompt turn
// =========================================================================

/// Request parameters for `session/prompt`.
///
/// The [prompt] is an array of content blocks (baseline: text + resource_link)
/// sent to the agent.
class PromptRequest {
  const PromptRequest({
    required this.sessionId,
    required this.prompt,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/prompt';

  final String sessionId;

  /// The content blocks composing the user's message.
  final List<ContentBlock> prompt;

  final Map<String, Object?> meta;

  /// Convenience: create a prompt from a single text block.
  factory PromptRequest.text(String sessionId, String text) => PromptRequest(
      sessionId: sessionId, prompt: [TextContentBlock(text: text)]);

  factory PromptRequest.fromJson(Map<String, Object?> json) {
    return PromptRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      prompt: readListField(json, 'prompt', ContentBlock.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'prompt': prompt.map((b) => b.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/prompt`.
class PromptResponse {
  const PromptResponse({required this.stopReason, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final StopReason stopReason;
  final Map<String, Object?> meta;

  factory PromptResponse.fromJson(Map<String, Object?> json) {
    return PromptResponse(
      stopReason: StopReason.fromJson(requireField<String>(json, 'stopReason')),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'stopReason': stopReason.toJson()};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `session/set_config_option`.
sealed class SetSessionConfigOptionRequest {
  const SetSessionConfigOptionRequest({
    required this.sessionId,
    required this.configId,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'session/set_config_option';

  final String sessionId;
  final String configId;
  final Map<String, Object?> meta;

  /// The wire discriminator.
  String get type;

  /// Parses by `type`: `boolean` → boolean, else value-id.
  static SetSessionConfigOptionRequest fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'boolean' => SetBooleanConfigOption.fromJson(json),
      _ => SetValueIdConfigOption.fromJson(json),
    };
  }

  Map<String, Object?> toJson();
}

/// Set a boolean config option.
final class SetBooleanConfigOption extends SetSessionConfigOptionRequest {
  const SetBooleanConfigOption({
    required super.sessionId,
    required super.configId,
    required this.value,
    super.meta,
  });

  @override
  String get type => 'boolean';

  final bool value;

  factory SetBooleanConfigOption.fromJson(Map<String, Object?> json) {
    return SetBooleanConfigOption(
      sessionId: requireField<String>(json, 'sessionId'),
      configId: requireField<String>(json, 'configId'),
      value: requireField<bool>(json, 'value'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'configId': configId,
      'type': type,
      'value': value,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Set a value-id (select) config option.
final class SetValueIdConfigOption extends SetSessionConfigOptionRequest {
  const SetValueIdConfigOption({
    required super.sessionId,
    required super.configId,
    required this.value,
    super.meta,
  });

  @override
  String get type => 'value_id';

  final String value;

  factory SetValueIdConfigOption.fromJson(Map<String, Object?> json) {
    return SetValueIdConfigOption(
      sessionId: requireField<String>(json, 'sessionId'),
      configId: requireField<String>(json, 'configId'),
      value: requireField<String>(json, 'value'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'configId': configId,
      'value': value,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `session/set_config_option`.
class SetSessionConfigOptionResponse {
  const SetSessionConfigOptionResponse({
    required this.configOptions,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final List<SessionConfigOption> configOptions;
  final Map<String, Object?> meta;

  factory SetSessionConfigOptionResponse.fromJson(Map<String, Object?> json) {
    return SetSessionConfigOptionResponse(
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

// =========================================================================
// File system
// =========================================================================

/// Request parameters for `fs/read_text_file`.
class ReadTextFileRequest {
  const ReadTextFileRequest({
    required this.sessionId,
    required this.path,
    this.line,
    this.limit,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'fs/read_text_file';

  final String sessionId;
  final String path;
  final int? line;
  final int? limit;
  final Map<String, Object?> meta;

  factory ReadTextFileRequest.fromJson(Map<String, Object?> json) {
    return ReadTextFileRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      path: requireField<String>(json, 'path'),
      line: readField<int>(json, 'line'),
      limit: readField<int>(json, 'limit'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'path': path,
    };
    if (line != null) json['line'] = line;
    if (limit != null) json['limit'] = limit;
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `fs/read_text_file`.
class ReadTextFileResponse {
  const ReadTextFileResponse({
    required this.content,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String content;
  final Map<String, Object?> meta;

  factory ReadTextFileResponse.fromJson(Map<String, Object?> json) {
    return ReadTextFileResponse(
      content: requireField<String>(json, 'content'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'content': content};
    writeMeta(json, meta);
    return json;
  }
}

/// Request parameters for `fs/write_text_file`.
class WriteTextFileRequest {
  const WriteTextFileRequest({
    required this.sessionId,
    required this.path,
    required this.content,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  static const methodName = 'fs/write_text_file';

  final String sessionId;
  final String path;
  final String content;
  final Map<String, Object?> meta;

  factory WriteTextFileRequest.fromJson(Map<String, Object?> json) {
    return WriteTextFileRequest(
      sessionId: requireField<String>(json, 'sessionId'),
      path: requireField<String>(json, 'path'),
      content: requireField<String>(json, 'content'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'sessionId': sessionId,
      'path': path,
      'content': content,
    };
    writeMeta(json, meta);
    return json;
  }
}

/// Response to `fs/write_text_file` (empty body).
class WriteTextFileResponse {
  const WriteTextFileResponse({Map<String, Object?>? meta})
      : meta = meta ?? const {};

  final Map<String, Object?> meta;

  factory WriteTextFileResponse.fromJson(Map<String, Object?> json) =>
      WriteTextFileResponse(meta: readMeta(json));

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    writeMeta(json, meta);
    return json;
  }
}
