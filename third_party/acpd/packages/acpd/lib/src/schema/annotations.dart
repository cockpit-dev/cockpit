/// Annotations and resource-content types used across ACP content blocks.
///
/// These types appear as fields of [ContentBlock] variants and tool-call
/// content, so they live in their own module to keep the dependency graph flat.
library;

import '../json_codec.dart';

/// Optional annotations that help clients decide how to display or route
/// content.
///
/// All fields are nullable and use `x-deserialize-default-on-error`
/// semantics: malformed values are dropped rather than failing the whole
/// message.
class Annotations {
  const Annotations({
    this.audience,
    this.lastModified,
    this.priority,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Intended recipients for this content.
  final List<String>? audience;

  /// Timestamp indicating when the underlying resource was last modified.
  final String? lastModified;

  /// Relative importance when clients choose what to surface.
  final double? priority;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  /// Deserializes from JSON, tolerating malformed values.
  factory Annotations.fromJson(Map<String, Object?> json) {
    return Annotations(
      audience: _readStringList(json['audience']),
      lastModified: readField<String>(json, 'lastModified'),
      priority: _readDouble(json['priority']),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    if (audience != null) json['audience'] = audience;
    if (lastModified != null) json['lastModified'] = lastModified;
    if (priority != null) json['priority'] = priority;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Annotations &&
          _listEq(audience, other.audience) &&
          lastModified == other.lastModified &&
          priority == other.priority &&
          _mapEq(meta, other.meta);

  @override
  int get hashCode => Object.hash(audience, lastModified, priority, meta);

  @override
  String toString() => 'Annotations(audience: $audience, priority: $priority)';
}

List<String>? _readStringList(Object? raw) {
  if (raw is! List) return null;
  return raw.whereType<String>().toList();
}

double? _readDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  return null;
}

bool _listEq(List<Object?>? a, List<Object?>? b) {
  if (a == null) return b == null;
  if (b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}
