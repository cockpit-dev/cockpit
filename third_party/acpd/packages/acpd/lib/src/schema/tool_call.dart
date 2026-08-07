/// Tool calls: actions the agent executes on behalf of the language model.
///
/// [ToolCall] is the full representation; [ToolCallUpdate] carries partial
/// changes. [ToolCallContent] is the sealed union of content produced by a
/// tool call (content/diff/terminal).
library;

import '../json_codec.dart';
import 'tool_call_content.dart';
import 'enums.dart';

/// A file location affected by a tool call.
class ToolCallLocation {
  const ToolCallLocation(
      {required this.path, this.line, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// Absolute file path.
  final String path;

  /// 1-based line number (optional).
  final int? line;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory ToolCallLocation.fromJson(Map<String, Object?> json) {
    return ToolCallLocation(
      path: requireField<String>(json, 'path'),
      line: readField<int>(json, 'line'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'path': path};
    if (line != null) json['line'] = line;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallLocation &&
          path == other.path &&
          line == other.line &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(path, line, meta);
}

/// A complete tool call.
class ToolCall {
  const ToolCall({
    required this.toolCallId,
    required this.title,
    this.kind,
    this.status,
    this.content = const [],
    this.locations = const [],
    this.rawInput,
    this.rawOutput,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String toolCallId;
  final String title;
  final ToolKind? kind;
  final ToolCallStatus? status;
  final List<ToolCallContent> content;
  final List<ToolCallLocation> locations;
  final String? rawInput;
  final String? rawOutput;
  final Map<String, Object?> meta;

  factory ToolCall.fromJson(Map<String, Object?> json) {
    return ToolCall(
      toolCallId: requireField<String>(json, 'toolCallId'),
      title: requireField<String>(json, 'title'),
      kind: _readKind(json['kind']),
      status: ToolCallStatus.fromJson(json['status'] as String?),
      content: readListField(json, 'content', ToolCallContent.fromJson)
          .cast<ToolCallContent>(),
      locations: readListField(json, 'locations', ToolCallLocation.fromJson),
      rawInput: readField<String>(json, 'rawInput'),
      rawOutput: readField<String>(json, 'rawOutput'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'toolCallId': toolCallId,
      'title': title,
    };
    if (kind != null) json['kind'] = kind!.toJson();
    if (status != null) json['status'] = status!.toJson();
    if (content.isNotEmpty) {
      json['content'] = content.map((c) => c.toJson()).toList();
    }
    if (locations.isNotEmpty) {
      json['locations'] = locations.map((l) => l.toJson()).toList();
    }
    if (rawInput != null) json['rawInput'] = rawInput;
    if (rawOutput != null) json['rawOutput'] = rawOutput;
    writeMeta(json, meta);
    return json;
  }

  /// Returns an update carrying this tool call's current state.
  ToolCallUpdate toUpdate() => ToolCallUpdate(
        toolCallId: toolCallId,
        kind: kind,
        status: status,
        title: title,
        content: content,
        locations: locations,
        rawInput: rawInput,
        rawOutput: rawOutput,
        meta: meta,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCall &&
          toolCallId == other.toolCallId &&
          title == other.title &&
          kind == other.kind &&
          status == other.status &&
          _listEq(content, other.content) &&
          _listEq(locations, other.locations) &&
          rawInput == other.rawInput &&
          rawOutput == other.rawOutput &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(toolCallId, title, kind, status, content,
      locations, rawInput, rawOutput, meta);
}

/// A partial update to an existing tool call.
///
/// All fields except [toolCallId] are optional — only changed fields are sent.
class ToolCallUpdate {
  const ToolCallUpdate({
    required this.toolCallId,
    this.kind,
    this.status,
    this.title,
    this.content = const [],
    this.locations = const [],
    this.rawInput,
    this.rawOutput,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String toolCallId;
  final ToolKind? kind;
  final ToolCallStatus? status;
  final String? title;
  final List<ToolCallContent> content;
  final List<ToolCallLocation> locations;
  final String? rawInput;
  final String? rawOutput;
  final Map<String, Object?> meta;

  factory ToolCallUpdate.fromJson(Map<String, Object?> json) {
    return ToolCallUpdate(
      toolCallId: requireField<String>(json, 'toolCallId'),
      kind: _readKind(json['kind']),
      status: ToolCallStatus.fromJson(json['status'] as String?),
      title: readField<String>(json, 'title'),
      content: readListField(json, 'content', ToolCallContent.fromJson)
          .cast<ToolCallContent>(),
      locations: readListField(json, 'locations', ToolCallLocation.fromJson),
      rawInput: readField<String>(json, 'rawInput'),
      rawOutput: readField<String>(json, 'rawOutput'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'toolCallId': toolCallId};
    if (kind != null) json['kind'] = kind!.toJson();
    if (status != null) json['status'] = status!.toJson();
    if (title != null) json['title'] = title;
    if (content.isNotEmpty) {
      json['content'] = content.map((c) => c.toJson()).toList();
    }
    if (locations.isNotEmpty) {
      json['locations'] = locations.map((l) => l.toJson()).toList();
    }
    if (rawInput != null) json['rawInput'] = rawInput;
    if (rawOutput != null) json['rawOutput'] = rawOutput;
    writeMeta(json, meta);
    return json;
  }
}

ToolKind? _readKind(Object? raw) {
  if (raw is String) return ToolKind.fromJson(raw);
  return null;
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
