/// Execution plans reported by agents to provide visibility into their strategy.
library;

import '../json_codec.dart';
import 'enums.dart';

/// A single entry in an execution plan.
class PlanEntry {
  const PlanEntry({
    required this.content,
    required this.priority,
    required this.status,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Human-readable description of what this task aims to accomplish.
  final String content;

  /// The relative importance of this task.
  final PlanEntryPriority priority;

  /// The lifecycle state of this task.
  final PlanEntryStatus status;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory PlanEntry.fromJson(Map<String, Object?> json) {
    return PlanEntry(
      content: requireField<String>(json, 'content'),
      priority:
          PlanEntryPriority.fromJson(requireField<String>(json, 'priority')),
      status: PlanEntryStatus.fromJson(requireField<String>(json, 'status')),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'content': content,
      'priority': priority.toJson(),
      'status': status.toJson(),
    };
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanEntry &&
          content == other.content &&
          priority == other.priority &&
          status == other.status &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(content, priority, status, meta);
}

/// An execution plan for accomplishing complex tasks.
///
/// When updating a plan, the agent sends a complete list of all entries,
/// replacing the previous plan entirely.
class Plan {
  const Plan({required this.entries, Map<String, Object?>? meta})
      : meta = meta ?? const {};

  /// The complete list of tasks.
  final List<PlanEntry> entries;

  /// Free-form metadata.
  final Map<String, Object?> meta;

  factory Plan.fromJson(Map<String, Object?> json) {
    return Plan(
      entries: readListField(json, 'entries', PlanEntry.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Plan && _listEq(entries, other.entries) && meta == other.meta;

  @override
  int get hashCode => Object.hash(entries, meta);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
