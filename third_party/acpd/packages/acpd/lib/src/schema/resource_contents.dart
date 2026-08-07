/// Resource contents that can be embedded in content blocks.
///
/// Matches the schema's `EmbeddedResourceResource` anyOf: either
/// [TextResourceContents] or [BlobResourceContents]. Discriminated at parse
/// time by the presence of `text` vs `blob`.
library;

import '../json_codec.dart';

/// A sealed union over text and binary resource payloads.
sealed class ResourceContents {
  const ResourceContents(
      {this.mimeType, required this.uri, Map<String, Object?>? meta})
      : meta = meta ?? const {};
  final String? mimeType;

  /// URI associated with this resource.
  final String uri;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  /// Parses a resource contents object.
  ///
  /// Discriminates by presence of the `text` field (text) vs `blob` field
  /// (binary).
  static ResourceContents fromJson(Map<String, Object?> json) {
    if (json.containsKey('text')) {
      return TextResourceContents.fromJson(json);
    }
    if (json.containsKey('blob')) {
      return BlobResourceContents.fromJson(json);
    }
    throw FormatException(
        'Resource contents must have "text" or "blob": $json');
  }

  Map<String, Object?> toJson();
}

/// Text-based resource contents.
final class TextResourceContents extends ResourceContents {
  const TextResourceContents({
    required this.text,
    required super.uri,
    super.mimeType,
    super.meta,
  });

  /// The text payload.
  final String text;

  factory TextResourceContents.fromJson(Map<String, Object?> json) {
    return TextResourceContents(
      text: requireField<String>(json, 'text'),
      uri: requireField<String>(json, 'uri'),
      mimeType: readField<String>(json, 'mimeType'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'uri': uri,
      'text': text,
    };
    if (mimeType != null) json['mimeType'] = mimeType;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextResourceContents &&
          text == other.text &&
          uri == other.uri &&
          mimeType == other.mimeType &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash('text', text, uri, mimeType, meta);
}

/// Binary resource contents.
final class BlobResourceContents extends ResourceContents {
  const BlobResourceContents({
    required this.blob,
    required super.uri,
    super.mimeType,
    super.meta,
  });

  /// Base64-encoded bytes.
  final String blob;

  factory BlobResourceContents.fromJson(Map<String, Object?> json) {
    return BlobResourceContents(
      blob: requireField<String>(json, 'blob'),
      uri: requireField<String>(json, 'uri'),
      mimeType: readField<String>(json, 'mimeType'),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'uri': uri,
      'blob': blob,
    };
    if (mimeType != null) json['mimeType'] = mimeType;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobResourceContents &&
          blob == other.blob &&
          uri == other.uri &&
          mimeType == other.mimeType &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash('blob', blob, uri, mimeType, meta);
}
