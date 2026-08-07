import 'package:collection/collection.dart';

import 'cockpit_runtime_event.dart';
import 'cockpit_runtime_query.dart';

final class CockpitRuntimeSnapshot {
  /// Creates a CockpitRuntimeSnapshot.
  const CockpitRuntimeSnapshot({
    required this.totalEntryCount,
    required this.errorCount,
    required this.warningCount,
    required this.entries,
    this.capturedEntryCount = 0,
    this.query = const CockpitRuntimeQuery(),
    this.truncated = false,
  });

  final int totalEntryCount;
  final int errorCount;
  final int warningCount;
  final List<CockpitRuntimeEvent> entries;
  final int capturedEntryCount;
  final CockpitRuntimeQuery query;
  final bool truncated;

  static const ListEquality<CockpitRuntimeEvent> _entryEquality =
      ListEquality<CockpitRuntimeEvent>();

  /// Encodes this CockpitRuntimeSnapshot as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalEntryCount': totalEntryCount,
    'errorCount': errorCount,
    'warningCount': warningCount,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'capturedEntryCount': capturedEntryCount,
    'query': query.toJson(),
    'truncated': truncated,
  };

  /// Decodes a CockpitRuntimeSnapshot from a JSON object.
  factory CockpitRuntimeSnapshot.fromJson(Map<String, Object?> json) {
    final queryJson = json['query'] as Map<Object?, Object?>?;
    return CockpitRuntimeSnapshot(
      totalEntryCount: json['totalEntryCount'] as int? ?? 0,
      errorCount: json['errorCount'] as int? ?? 0,
      warningCount: json['warningCount'] as int? ?? 0,
      entries: (json['entries'] as List<Object?>? ?? const <Object?>[])
          .map(
            (entry) => CockpitRuntimeEvent.fromJson(
              Map<String, Object?>.from(entry! as Map<Object?, Object?>),
            ),
          )
          .toList(growable: false),
      capturedEntryCount: json['capturedEntryCount'] as int? ?? 0,
      query: queryJson == null
          ? const CockpitRuntimeQuery()
          : CockpitRuntimeQuery.fromJson(Map<String, Object?>.from(queryJson)),
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRuntimeSnapshot &&
            other.totalEntryCount == totalEntryCount &&
            other.errorCount == errorCount &&
            other.warningCount == warningCount &&
            _entryEquality.equals(other.entries, entries) &&
            other.capturedEntryCount == capturedEntryCount &&
            other.query == query &&
            other.truncated == truncated;
  }

  @override
  int get hashCode => Object.hash(
    totalEntryCount,
    errorCount,
    warningCount,
    _entryEquality.hash(entries),
    capturedEntryCount,
    query,
    truncated,
  );
}
