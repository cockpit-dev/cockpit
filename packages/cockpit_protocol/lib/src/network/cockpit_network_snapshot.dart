import 'package:collection/collection.dart';

import 'cockpit_network_entry.dart';
import 'cockpit_network_endpoint_summary.dart';
import 'cockpit_network_query.dart';

final class CockpitNetworkSnapshot {
  /// Creates a CockpitNetworkSnapshot.
  const CockpitNetworkSnapshot({
    required this.totalEntryCount,
    required this.failureCount,
    required this.entries,
    this.endpointSummaries = const <CockpitNetworkEndpointSummary>[],
    this.capturedEntryCount = 0,
    this.inFlightCount = 0,
    this.query = const CockpitNetworkQuery(),
    this.truncated = false,
  });

  final int totalEntryCount;
  final int failureCount;
  final List<CockpitNetworkEntry> entries;
  final List<CockpitNetworkEndpointSummary> endpointSummaries;
  final int capturedEntryCount;
  final int inFlightCount;
  final CockpitNetworkQuery query;
  final bool truncated;

  static const ListEquality<CockpitNetworkEntry> _entryEquality =
      ListEquality<CockpitNetworkEntry>();
  static const ListEquality<CockpitNetworkEndpointSummary>
  _endpointSummaryEquality = ListEquality<CockpitNetworkEndpointSummary>();

  /// Encodes this CockpitNetworkSnapshot as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalEntryCount': totalEntryCount,
    'failureCount': failureCount,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'endpointSummaries': endpointSummaries
        .map((summary) => summary.toJson())
        .toList(growable: false),
    'capturedEntryCount': capturedEntryCount,
    'inFlightCount': inFlightCount,
    'query': query.toJson(),
    'truncated': truncated,
  };

  /// Decodes a CockpitNetworkSnapshot from a JSON object.
  factory CockpitNetworkSnapshot.fromJson(Map<String, Object?> json) {
    final queryJson = json['query'] as Map<Object?, Object?>?;
    return CockpitNetworkSnapshot(
      totalEntryCount: json['totalEntryCount'] as int? ?? 0,
      failureCount: json['failureCount'] as int? ?? 0,
      entries: (json['entries'] as List<Object?>? ?? const <Object?>[])
          .map(
            (entry) => CockpitNetworkEntry.fromJson(
              Map<String, Object?>.from(entry! as Map<Object?, Object?>),
            ),
          )
          .toList(growable: false),
      endpointSummaries:
          (json['endpointSummaries'] as List<Object?>? ?? const <Object?>[])
              .map(
                (summary) => CockpitNetworkEndpointSummary.fromJson(
                  Map<String, Object?>.from(summary! as Map<Object?, Object?>),
                ),
              )
              .toList(growable: false),
      capturedEntryCount: json['capturedEntryCount'] as int? ?? 0,
      inFlightCount: json['inFlightCount'] as int? ?? 0,
      query: queryJson == null
          ? const CockpitNetworkQuery()
          : CockpitNetworkQuery.fromJson(Map<String, Object?>.from(queryJson)),
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitNetworkSnapshot &&
            other.totalEntryCount == totalEntryCount &&
            other.failureCount == failureCount &&
            _entryEquality.equals(other.entries, entries) &&
            _endpointSummaryEquality.equals(
              other.endpointSummaries,
              endpointSummaries,
            ) &&
            other.capturedEntryCount == capturedEntryCount &&
            other.inFlightCount == inFlightCount &&
            other.query == query &&
            other.truncated == truncated;
  }

  @override
  int get hashCode => Object.hash(
    totalEntryCount,
    failureCount,
    _entryEquality.hash(entries),
    _endpointSummaryEquality.hash(endpointSummaries),
    capturedEntryCount,
    inFlightCount,
    query,
    truncated,
  );
}
