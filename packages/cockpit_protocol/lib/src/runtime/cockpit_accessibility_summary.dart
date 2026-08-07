import 'package:collection/collection.dart';

final class CockpitAccessibilityEntry {
  /// Creates a CockpitAccessibilityEntry.
  const CockpitAccessibilityEntry({
    required this.nodeId,
    this.label,
    this.identifier,
    this.value,
    this.hint,
    this.tooltip,
  });

  final int nodeId;
  final String? label;
  final String? identifier;
  final String? value;
  final String? hint;
  final String? tooltip;

  String? get primarySignal => label ?? identifier ?? value ?? hint ?? tooltip;

  bool get hasMeaningfulSignal => primarySignal != null;

  /// Encodes this CockpitAccessibilityEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    if (label != null) 'label': label,
    if (identifier != null) 'identifier': identifier,
    if (value != null) 'value': value,
    if (hint != null) 'hint': hint,
    if (tooltip != null) 'tooltip': tooltip,
  };

  /// Decodes a CockpitAccessibilityEntry from a JSON object.
  factory CockpitAccessibilityEntry.fromJson(Map<String, Object?> json) {
    return CockpitAccessibilityEntry(
      nodeId: json['nodeId']! as int,
      label: json['label'] as String?,
      identifier: json['identifier'] as String?,
      value: json['value'] as String?,
      hint: json['hint'] as String?,
      tooltip: json['tooltip'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitAccessibilityEntry &&
            other.nodeId == nodeId &&
            other.label == label &&
            other.identifier == identifier &&
            other.value == value &&
            other.hint == hint &&
            other.tooltip == tooltip;
  }

  @override
  int get hashCode =>
      Object.hash(nodeId, label, identifier, value, hint, tooltip);
}

final class CockpitAccessibilitySummary {
  /// Creates a CockpitAccessibilitySummary.
  CockpitAccessibilitySummary({
    required this.totalAccessibleTargetCount,
    required List<CockpitAccessibilityEntry> traversalEntries,
    required this.truncated,
  }) : traversalEntries = List.unmodifiable(traversalEntries);

  final int totalAccessibleTargetCount;
  final List<CockpitAccessibilityEntry> traversalEntries;
  final bool truncated;

  static const ListEquality<CockpitAccessibilityEntry> _entryEquality =
      ListEquality<CockpitAccessibilityEntry>();

  /// Encodes this CockpitAccessibilitySummary as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalAccessibleTargetCount': totalAccessibleTargetCount,
    'traversalEntries': traversalEntries
        .map((entry) => entry.toJson())
        .toList(growable: false),
    'truncated': truncated,
  };

  /// Decodes a CockpitAccessibilitySummary from a JSON object.
  factory CockpitAccessibilitySummary.fromJson(Map<String, Object?> json) {
    return CockpitAccessibilitySummary(
      totalAccessibleTargetCount:
          json['totalAccessibleTargetCount'] as int? ?? 0,
      traversalEntries:
          (json['traversalEntries'] as List<Object?>? ?? const <Object?>[])
              .cast<Map<Object?, Object?>>()
              .map(
                (entry) => CockpitAccessibilityEntry.fromJson(
                  Map<String, Object?>.from(entry),
                ),
              )
              .toList(growable: false),
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitAccessibilitySummary &&
            other.totalAccessibleTargetCount == totalAccessibleTargetCount &&
            other.truncated == truncated &&
            _entryEquality.equals(other.traversalEntries, traversalEntries);
  }

  @override
  int get hashCode => Object.hash(
    totalAccessibleTargetCount,
    truncated,
    _entryEquality.hash(traversalEntries),
  );
}
