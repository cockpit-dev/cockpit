/// Content produced by a tool call.
///
/// [ToolCallContent] is a sealed union with three variants distinguished by
/// a `type` discriminator: `content` (a [ContentBlock]), `diff` (file
/// modification), or `terminal` (embedded terminal reference).
library;

import '../json_codec.dart';
import 'content.dart';

/// Content produced by a tool call.
sealed class ToolCallContent {
  const ToolCallContent(this.type, {Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// The wire discriminator.
  final String type;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  /// Parses a tool-call content value by its `type` discriminator.
  static ToolCallContent fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'content' => ToolCallContentBlock.fromJson(json),
      'diff' => ToolCallDiff.fromJson(json),
      'terminal' => ToolCallTerminal.fromJson(json),
      _ => throw FormatException(
          'Unknown tool call content type "${json['type']}": $json'),
    };
  }

  Map<String, Object?> toJson();
}

/// A standard content block wrapped for tool-call output.
final class ToolCallContentBlock extends ToolCallContent {
  const ToolCallContentBlock(
      {required this.content, Map<String, Object?>? meta})
      : super('content', meta: meta);

  /// The wrapped content block.
  final ContentBlock content;

  factory ToolCallContentBlock.fromJson(Map<String, Object?> json) {
    return ToolCallContentBlock(
      content: ContentBlock.fromJson(
          requireField<Map<String, Object?>>(json, 'content')),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'content': content.toJson(),
    };
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallContentBlock &&
          content == other.content &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash('tc-content', content, meta);
}

/// A file modification diff.
final class ToolCallDiff extends Diff implements ToolCallContent {
  const ToolCallDiff({
    required super.path,
    required super.newText,
    super.oldText,
    super.meta,
  });

  @override
  String get type => 'diff';

  factory ToolCallDiff.fromJson(Map<String, Object?> json) {
    return ToolCallDiff(
      path: requireField<String>(json, 'path'),
      newText: requireField<String>(json, 'newText'),
      oldText: readField<String>(json, 'oldText'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() => super.toJson()..['type'] = 'diff';
}

/// An embedded terminal reference.
final class ToolCallTerminal extends Terminal implements ToolCallContent {
  const ToolCallTerminal({required super.terminalId, super.meta});

  @override
  String get type => 'terminal';

  factory ToolCallTerminal.fromJson(Map<String, Object?> json) {
    return ToolCallTerminal(
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() => super.toJson()..['type'] = 'terminal';
}

/// A standard content block wrapper (the `Content` schema type).
///
/// This wraps a [ContentBlock] for contexts where content is the payload of a
/// tool-call output.
class Content {
  const Content({required this.content, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// The content block.
  final ContentBlock content;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory Content.fromJson(Map<String, Object?> json) {
    return Content(
      content: ContentBlock.fromJson(
          requireField<Map<String, Object?>>(json, 'content')),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'content': content.toJson()};
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Content && content == other.content && meta == other.meta;

  @override
  int get hashCode => Object.hash(content, meta);
}

/// A diff representing file modifications.
class Diff {
  const Diff(
      {required this.path,
      required this.newText,
      this.oldText,
      Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// Absolute file path being modified.
  final String path;

  /// Original content (null for new files).
  final String? oldText;

  /// New content after modification.
  final String newText;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory Diff.fromJson(Map<String, Object?> json) {
    return Diff(
      path: requireField<String>(json, 'path'),
      newText: requireField<String>(json, 'newText'),
      oldText: readField<String>(json, 'oldText'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'path': path,
      'newText': newText,
    };
    if (oldText != null) json['oldText'] = oldText;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Diff &&
          path == other.path &&
          newText == other.newText &&
          oldText == other.oldText &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(path, newText, oldText, meta);
}

/// An embedded terminal reference (the `Terminal` schema type).
class Terminal {
  const Terminal({required this.terminalId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// Identifier of the terminal instance.
  final String terminalId;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory Terminal.fromJson(Map<String, Object?> json) {
    return Terminal(
      terminalId: requireField<String>(json, 'terminalId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'terminalId': terminalId};
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Terminal && terminalId == other.terminalId && meta == other.meta;

  @override
  int get hashCode => Object.hash(terminalId, meta);
}

/// A streamed item of content.
class ContentChunk {
  const ContentChunk(
      {required this.content, this.messageId, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// A single content block.
  final ContentBlock content;

  /// Identifier for the message this chunk belongs to.
  ///
  /// Chunks sharing a [messageId] belong to the same message. A change
  /// indicates a new message has started.
  final String? messageId;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory ContentChunk.fromJson(Map<String, Object?> json) {
    return ContentChunk(
      content: ContentBlock.fromJson(
          requireField<Map<String, Object?>>(json, 'content')),
      messageId: readField<String>(json, 'messageId'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'content': content.toJson()};
    if (messageId != null) json['messageId'] = messageId;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentChunk &&
          content == other.content &&
          messageId == other.messageId &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(content, messageId, meta);
}
