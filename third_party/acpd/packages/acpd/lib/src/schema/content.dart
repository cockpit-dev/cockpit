/// Content blocks, the displayable units of ACP messages.
///
/// [ContentBlock] is the discriminated union consumed by prompts, session
/// updates, and tool-call results. Variants are distinguished by a `type`
/// field: `text`, `image`, `audio`, `resource_link`, or `embedded_resource`.
library;

import '../json_codec.dart';
import 'annotations.dart';
import 'resource_contents.dart';

/// A content block — one of five variants distinguished by [type].
sealed class ContentBlock {
  const ContentBlock(this.type, {Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// The discriminator value on the wire.
  final String type;

  /// Optional annotations shared by all variants (may be null).
  Annotations? get annotations;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  /// Parses a content block from JSON, dispatching on the `type` field.
  static ContentBlock fromJson(Map<String, Object?> json) {
    final type = json['type'];
    return switch (type) {
      'text' => TextContentBlock.fromJson(json),
      'image' => ImageContent.fromJson(json),
      'audio' => AudioContent.fromJson(json),
      'resource_link' => ResourceLink.fromJson(json),
      'embedded_resource' => EmbeddedResource.fromJson(json),
      _ => throw FormatException('Unknown content block type "$type": $json'),
    };
  }

  Map<String, Object?> toJson();
}

/// Text content. May be plain text or Markdown.
final class TextContentBlock extends ContentBlock {
  const TextContentBlock({
    required this.text,
    this.annotations,
    Map<String, Object?>? meta,
  }) : super('text', meta: meta);

  /// The text payload.
  final String text;

  @override
  final Annotations? annotations;

  factory TextContentBlock.fromJson(Map<String, Object?> json) {
    return TextContentBlock(
      text: requireField<String>(json, 'text'),
      annotations: _readAnnotations(json['annotations']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'text': text,
    };
    if (annotations != null) json['annotations'] = annotations!.toJson();
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextContentBlock &&
          text == other.text &&
          annotations == other.annotations &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash('text', text, annotations, meta);
}

/// Alias matching the ACP schema's `TextContent` type name.
typedef TextContent = TextContentBlock;

/// Image content — base64-encoded image data.
final class ImageContent extends ContentBlock {
  const ImageContent({
    required this.data,
    required this.mimeType,
    this.uri,
    this.annotations,
    Map<String, Object?>? meta,
  }) : super('image', meta: meta);

  /// Base64-encoded image payload.
  final String data;

  /// MIME type of the image (e.g. `image/png`).
  final String mimeType;

  /// Optional URI associated with the image.
  final String? uri;

  @override
  final Annotations? annotations;

  factory ImageContent.fromJson(Map<String, Object?> json) {
    return ImageContent(
      data: requireField<String>(json, 'data'),
      mimeType: requireField<String>(json, 'mimeType'),
      uri: readField<String>(json, 'uri'),
      annotations: _readAnnotations(json['annotations']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'data': data,
      'mimeType': mimeType,
    };
    if (uri != null) json['uri'] = uri;
    if (annotations != null) json['annotations'] = annotations!.toJson();
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageContent &&
          data == other.data &&
          mimeType == other.mimeType &&
          uri == other.uri &&
          annotations == other.annotations &&
          meta == other.meta;

  @override
  int get hashCode =>
      Object.hash('image', data, mimeType, uri, annotations, meta);
}

/// Audio content — base64-encoded audio data.
final class AudioContent extends ContentBlock {
  const AudioContent({
    required this.data,
    required this.mimeType,
    this.annotations,
    Map<String, Object?>? meta,
  }) : super('audio', meta: meta);

  /// Base64-encoded audio payload.
  final String data;

  /// MIME type of the audio (e.g. `audio/wav`).
  final String mimeType;

  @override
  final Annotations? annotations;

  factory AudioContent.fromJson(Map<String, Object?> json) {
    return AudioContent(
      data: requireField<String>(json, 'data'),
      mimeType: requireField<String>(json, 'mimeType'),
      annotations: _readAnnotations(json['annotations']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'data': data,
      'mimeType': mimeType,
    };
    if (annotations != null) json['annotations'] = annotations!.toJson();
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioContent &&
          data == other.data &&
          mimeType == other.mimeType &&
          annotations == other.annotations &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash('audio', data, mimeType, annotations, meta);
}

/// A link to a resource the server can read.
final class ResourceLink extends ContentBlock {
  const ResourceLink({
    required this.name,
    required this.uri,
    this.title,
    this.description,
    this.mimeType,
    this.size,
    this.annotations,
    Map<String, Object?>? meta,
  }) : super('resource_link', meta: meta);

  /// Human-readable name.
  final String name;

  /// URI of the resource.
  final String uri;

  /// Optional display title.
  final String? title;

  /// Optional human-readable description.
  final String? description;

  /// Optional MIME type.
  final String? mimeType;

  /// Optional size in bytes.
  final int? size;

  @override
  final Annotations? annotations;

  factory ResourceLink.fromJson(Map<String, Object?> json) {
    return ResourceLink(
      name: requireField<String>(json, 'name'),
      uri: requireField<String>(json, 'uri'),
      title: readField<String>(json, 'title'),
      description: readField<String>(json, 'description'),
      mimeType: readField<String>(json, 'mimeType'),
      size: readField<int>(json, 'size'),
      annotations: _readAnnotations(json['annotations']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'name': name,
      'uri': uri,
    };
    if (title != null) json['title'] = title;
    if (description != null) json['description'] = description;
    if (mimeType != null) json['mimeType'] = mimeType;
    if (size != null) json['size'] = size;
    if (annotations != null) json['annotations'] = annotations!.toJson();
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceLink &&
          name == other.name &&
          uri == other.uri &&
          title == other.title &&
          description == other.description &&
          mimeType == other.mimeType &&
          size == other.size &&
          annotations == other.annotations &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash('resource_link', name, uri, title,
      description, mimeType, size, annotations, meta);
}

/// An embedded resource (text or binary) inlined into the content stream.
final class EmbeddedResource extends ContentBlock {
  const EmbeddedResource({
    required this.resource,
    this.annotations,
    Map<String, Object?>? meta,
  }) : super('embedded_resource', meta: meta);

  /// The embedded resource payload.
  final ResourceContents resource;

  @override
  final Annotations? annotations;

  factory EmbeddedResource.fromJson(Map<String, Object?> json) {
    return EmbeddedResource(
      resource: ResourceContents.fromJson(
          requireField<Map<String, Object?>>(json, 'resource')),
      annotations: _readAnnotations(json['annotations']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'resource': resource.toJson(),
    };
    if (annotations != null) json['annotations'] = annotations!.toJson();
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmbeddedResource &&
          resource == other.resource &&
          annotations == other.annotations &&
          meta == other.meta;

  @override
  int get hashCode =>
      Object.hash('embedded_resource', resource, annotations, meta);
}

Annotations? _readAnnotations(Object? raw) {
  if (raw is Map<String, Object?>) return Annotations.fromJson(raw);
  return null;
}
