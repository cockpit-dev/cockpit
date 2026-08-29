import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

/// A bounded change observed while sampling the mounted Flutter surface.
final class CockpitWatchChange {
  const CockpitWatchChange({
    required this.at,
    this.fromRoute,
    this.route,
    this.added = const <Map<String, Object?>>[],
    this.removed = const <String>[],
    this.updated = const <Map<String, Object?>>[],
    required this.count,
  });

  /// Logical time from the beginning of the watch.
  final Duration at;

  final String? fromRoute;
  final String? route;
  final List<Map<String, Object?>> added;
  final List<String> removed;
  final List<Map<String, Object?>> updated;
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{
    'atMs': at.inMilliseconds,
    if (fromRoute != route) ...<String, Object?>{
      if (fromRoute != null) 'from': fromRoute,
      if (route != null) 'route': route,
    },
    if (added.isNotEmpty) 'added': added,
    if (removed.isNotEmpty) 'removed': removed,
    if (updated.isNotEmpty) 'updated': updated,
    'count': count,
  };
}

/// Result of a bounded UI watch.
final class CockpitWatchResult {
  const CockpitWatchResult({
    required this.samples,
    required this.changes,
    required this.endedBy,
    required this.elapsed,
  });

  /// Number of snapshots sampled, including the initial snapshot.
  final int samples;

  /// Compact deltas only; complete snapshots are intentionally not retained.
  final List<CockpitWatchChange> changes;

  /// `duration`, `quiet`, `eventLimit`, `timeout`, or `error`.
  final String endedBy;

  final Duration elapsed;

  bool get changed => changes.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'samples': samples,
    'changes': changes.map((change) => change.toJson()).toList(growable: false),
    'changed': changed,
    'endedBy': endedBy,
    'durationMs': elapsed.inMilliseconds,
  };
}

Map<String, Object?> cockpitWatchProjection(CockpitSnapshot snapshot) {
  final targets = <Map<String, Object?>>[];
  for (final target in snapshot.visibleTargets) {
    final state = target.control?.toJson();
    final layout = target.layout?.toJson();
    final style = target.style?.toJson();
    targets.add(<String, Object?>{
      'id': _watchIdentity(target),
      if (target.cockpitId != null) 'cockpitId': target.cockpitId,
      if (target.semanticId != null) 'semanticId': target.semanticId,
      if (target.keyValue != null) 'keyValue': target.keyValue,
      if (target.text != null) 'text': target.text,
      if (target.tooltip != null) 'tooltip': target.tooltip,
      if (target.typeName != null) 'typeName': target.typeName,
      if (!target.visible) 'visible': false,
      'control': ?_watchControl(state),
      'layout': ?_watchControl(layout),
      'style': ?_watchControl(style),
    });
  }
  return <String, Object?>{
    if (snapshot.routeName != null) 'route': snapshot.routeName,
    'count': targets.length,
    'targets': targets,
  };
}

CockpitWatchChange cockpitWatchChange(
  Map<String, Object?> previous,
  Map<String, Object?> current, {
  required Duration at,
}) {
  final previousRoute = previous['route'] as String?;
  final currentRoute = current['route'] as String?;
  final previousTargets = _watchTargetMap(previous['targets']);
  final currentTargets = _watchTargetMap(current['targets']);
  final added = currentTargets.keys
      .where((key) => !previousTargets.containsKey(key))
      .take(8)
      .map((key) => currentTargets[key]!)
      .toList(growable: false);
  final removed = previousTargets.keys
      .where((key) => !currentTargets.containsKey(key))
      .take(8)
      .toList(growable: false);
  final updated = currentTargets.keys
      .where(
        (key) =>
            previousTargets.containsKey(key) &&
            jsonEncode(previousTargets[key]) != jsonEncode(currentTargets[key]),
      )
      .take(8)
      .map(
        (key) => <String, Object?>{
          'id': key,
          'from': previousTargets[key],
          'to': currentTargets[key],
        },
      )
      .toList(growable: false);
  return CockpitWatchChange(
    at: at,
    fromRoute: previousRoute,
    route: currentRoute,
    added: added,
    removed: removed,
    updated: updated,
    count: (current['count'] as num?)?.toInt() ?? 0,
  );
}

Map<String, Map<String, Object?>> _watchTargetMap(Object? value) {
  if (value is! List<Object?>) return <String, Map<String, Object?>>{};
  final result = <String, Map<String, Object?>>{};
  for (final item in value.whereType<Map<Object?, Object?>>()) {
    final target = Map<String, Object?>.from(item);
    final base = target['id'] as String? ?? 'target';
    var key = base;
    var duplicate = 1;
    while (result.containsKey(key)) {
      key = '$base#$duplicate';
      duplicate += 1;
    }
    result[key] = target;
  }
  return result;
}

String _watchIdentity(CockpitSnapshotTarget target) {
  for (final value in <String?>[
    target.cockpitId,
    target.semanticId,
    target.keyValue,
    target.tooltip,
    target.text,
    target.typeName,
  ]) {
    if (value != null && value.isNotEmpty) return value;
  }
  return target.registrationId;
}

Map<String, Object?>? _watchControl(Map<String, Object?>? value) {
  return value == null || value.isEmpty ? null : value;
}
