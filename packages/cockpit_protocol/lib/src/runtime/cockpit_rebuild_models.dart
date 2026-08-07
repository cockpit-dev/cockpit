import 'package:collection/collection.dart';

final class CockpitRebuildEntry {
  /// Creates a CockpitRebuildEntry.
  const CockpitRebuildEntry({
    required this.signature,
    required this.routeName,
    required this.typeName,
    required this.rebuildCount,
    required this.builtOnceCount,
    this.keyValue,
    this.semanticId,
    this.textPreview,
  });

  final String signature;
  final String routeName;
  final String typeName;
  final int rebuildCount;
  final int builtOnceCount;
  final String? keyValue;
  final String? semanticId;
  final String? textPreview;

  /// Encodes this CockpitRebuildEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'signature': signature,
    'routeName': routeName,
    'typeName': typeName,
    'rebuildCount': rebuildCount,
    'builtOnceCount': builtOnceCount,
    if (keyValue != null) 'keyValue': keyValue,
    if (semanticId != null) 'semanticId': semanticId,
    if (textPreview != null) 'textPreview': textPreview,
  };

  /// Decodes a CockpitRebuildEntry from a JSON object.
  factory CockpitRebuildEntry.fromJson(Map<String, Object?> json) {
    return CockpitRebuildEntry(
      signature: json['signature']! as String,
      routeName: json['routeName']! as String,
      typeName: json['typeName']! as String,
      rebuildCount: json['rebuildCount'] as int? ?? 0,
      builtOnceCount: json['builtOnceCount'] as int? ?? 0,
      keyValue: json['keyValue'] as String?,
      semanticId: json['semanticId'] as String?,
      textPreview: json['textPreview'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRebuildEntry &&
            other.signature == signature &&
            other.routeName == routeName &&
            other.typeName == typeName &&
            other.rebuildCount == rebuildCount &&
            other.builtOnceCount == builtOnceCount &&
            other.keyValue == keyValue &&
            other.semanticId == semanticId &&
            other.textPreview == textPreview;
  }

  @override
  int get hashCode => Object.hash(
    signature,
    routeName,
    typeName,
    rebuildCount,
    builtOnceCount,
    keyValue,
    semanticId,
    textPreview,
  );
}

final class CockpitRebuildSnapshot {
  /// Creates a CockpitRebuildSnapshot.
  const CockpitRebuildSnapshot({
    required this.totalRebuildCount,
    required this.uniqueElementCount,
    required this.capturedEntryCount,
    required this.truncated,
    required this.entries,
  });

  final int totalRebuildCount;
  final int uniqueElementCount;
  final int capturedEntryCount;
  final bool truncated;
  final List<CockpitRebuildEntry> entries;

  static const ListEquality<CockpitRebuildEntry> _entryEquality =
      ListEquality<CockpitRebuildEntry>();

  /// Encodes this CockpitRebuildSnapshot as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalRebuildCount': totalRebuildCount,
    'uniqueElementCount': uniqueElementCount,
    'capturedEntryCount': capturedEntryCount,
    'truncated': truncated,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
  };

  /// Decodes a CockpitRebuildSnapshot from a JSON object.
  factory CockpitRebuildSnapshot.fromJson(Map<String, Object?> json) {
    return CockpitRebuildSnapshot(
      totalRebuildCount: json['totalRebuildCount'] as int? ?? 0,
      uniqueElementCount: json['uniqueElementCount'] as int? ?? 0,
      capturedEntryCount: json['capturedEntryCount'] as int? ?? 0,
      truncated: json['truncated'] as bool? ?? false,
      entries: (json['entries'] as List<Object?>? ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (entry) =>
                CockpitRebuildEntry.fromJson(Map<String, Object?>.from(entry)),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRebuildSnapshot &&
            other.totalRebuildCount == totalRebuildCount &&
            other.uniqueElementCount == uniqueElementCount &&
            other.capturedEntryCount == capturedEntryCount &&
            other.truncated == truncated &&
            _entryEquality.equals(other.entries, entries);
  }

  @override
  int get hashCode => Object.hash(
    totalRebuildCount,
    uniqueElementCount,
    capturedEntryCount,
    truncated,
    _entryEquality.hash(entries),
  );
}
