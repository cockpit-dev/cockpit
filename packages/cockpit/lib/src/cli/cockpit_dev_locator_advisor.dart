Map<String, Object?> cockpitBuildDevLocatorMatches(
  Map<String, Object?> output,
  String query, {
  int limit = 12,
}) {
  final snapshot = output['snapshot'];
  if (snapshot is! Map<Object?, Object?>) {
    throw StateError('ui.inspect locate output did not contain a snapshot.');
  }
  final values = snapshot['visibleTargets'];
  if (values is! List<Object?>) {
    throw StateError('ui.inspect locate output did not contain UI targets.');
  }

  final targets = values
      .whereType<Map<Object?, Object?>>()
      .map(_DevTarget.new)
      .toList(growable: false);
  final normalizedQuery = _searchText(query);
  if (normalizedQuery == null) {
    throw const FormatException('dev inspect query cannot be empty.');
  }
  final matches =
      targets
          .where((target) => target.matchesQuery(normalizedQuery))
          .toList(growable: false)
        ..sort((left, right) => left.compareForQuery(right, normalizedQuery));
  final visibleMatches = matches.take(limit).toList(growable: false);

  return <String, Object?>{
    'query': query.trim(),
    'count': matches.length,
    'matches': visibleMatches
        .map((target) => target.result(targets))
        .toList(growable: false),
    if (matches.length > visibleMatches.length)
      'more': matches.length - visibleMatches.length,
    if (snapshot['truncated'] == true || output['truncated'] == true)
      'partial': true,
  };
}

final class _DevTarget {
  _DevTarget(Map<Object?, Object?> value)
    : registrationId = value['registrationId'] as String? ?? '',
      cockpitId = value['cockpitId'] as String?,
      semanticId = value['semanticId'] as String?,
      key = value['keyValue'] as String?,
      text = value['text'] as String?,
      tip = value['tooltip'] as String?,
      type = value['typeName'] as String?,
      route = value['routeName'] as String?,
      path = value['path'] as String?,
      can = (value['supportedCommands'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      within = (value['ancestors'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((ancestor) => ancestor['typeName'])
          .whereType<String>()
          .where((type) => type.trim().isNotEmpty)
          .toSet()
          .toList(growable: false),
      layout = _Layout.from(value['layout']);

  final String registrationId;
  final String? cockpitId;
  final String? semanticId;
  final String? key;
  final String? text;
  final String? tip;
  final String? type;
  final String? route;
  final String? path;
  final List<String> can;
  final List<String> within;
  final _Layout? layout;

  String? get label =>
      _value(text) ??
      _value(tip) ??
      _value(cockpitId) ??
      _value(key) ??
      _value(type);

  String? get displayLabel =>
      _value(cockpitId) ??
      _value(semanticId) ??
      _value(text) ??
      _value(tip) ??
      _value(key) ??
      _value(type);

  List<_Signal> get signals => <_Signal>[
    if (_value(cockpitId) case final value?) _Signal('id', value),
    if (_value(key) case final value?) _Signal('key', value),
    if (_value(text) case final value?) _Signal('text', value),
    if (_value(tip) case final value?)
      if (_exactText(value) != _exactText(text)) _Signal('tip', value),
    if (_value(type) case final value?) _Signal('type', value),
    if (_value(route) case final value?) _Signal('route', value),
    if (_value(path) case final value?) _Signal('path', value),
  ];

  bool matchesQuery(String query) => <String?>[
    text,
    tip,
    cockpitId,
    semanticId,
    key,
    type,
    path,
  ].any((value) => _searchText(value)?.contains(query) ?? false);

  int compareForQuery(_DevTarget other, String query) {
    final rank = _queryRank(query).compareTo(other._queryRank(query));
    if (rank != 0) return rank;
    final actionable = other.can.isNotEmpty == can.isNotEmpty
        ? 0
        : other.can.isNotEmpty
        ? 1
        : -1;
    if (actionable != 0) return actionable;
    return (label?.length ?? 1 << 20).compareTo(other.label?.length ?? 1 << 20);
  }

  int _queryRank(String query) {
    final fields = <String?>[text, tip, cockpitId, semanticId, key, type];
    for (var index = 0; index < fields.length; index += 1) {
      final value = _searchText(fields[index]);
      if (value == query) return index;
      if (value?.startsWith(query) ?? false) return 10 + index;
    }
    return 20;
  }

  Map<String, Object?> result(List<_DevTarget> targets) {
    final advice = _advise(this, targets);
    return <String, Object?>{
      'loc': advice.loc,
      if (!advice.loc.containsKey('text') && label != null) 'label': label,
      if (can.isNotEmpty) 'can': can,
      if (advice.ambiguous) 'ambiguous': true,
    };
  }
}

final class _Signal {
  const _Signal(this.name, this.value);
  final String name;
  final String value;
}

final class _Advice {
  const _Advice(this.loc, {this.ambiguous = false});
  final Map<String, Object?> loc;
  final bool ambiguous;
}

final class _Layout {
  const _Layout(this.dx, this.dy, this.width, this.height);
  final double dx;
  final double dy;
  final double width;
  final double height;

  static _Layout? from(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final dx = value['dx'];
    final dy = value['dy'];
    final width = value['width'];
    final height = value['height'];
    if (dx is! num || dy is! num || width is! num || height is! num) {
      return null;
    }
    return _Layout(
      dx.toDouble(),
      dy.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }
}

_Advice _advise(_DevTarget target, List<_DevTarget> targets) {
  final candidates = target.can.isEmpty
      ? targets
      : targets
            .where((candidate) => candidate.can.any(target.can.contains))
            .toList(growable: false);
  final signals = target.signals;
  final hasPrimarySignal = signals.any(
    (signal) =>
        const <String>{'id', 'key', 'text', 'tip'}.contains(signal.name),
  );
  for (var size = 1; size <= signals.length; size += 1) {
    for (final combination in _combinations(signals, size)) {
      if (hasPrimarySignal &&
          !combination.any(
            (signal) => const <String>{
              'id',
              'key',
              'text',
              'tip',
            }.contains(signal.name),
          )) {
        continue;
      }
      final loc = <String, Object?>{
        for (final signal in combination) signal.name: signal.value,
      };
      if (_uniquelyMatches(target, candidates, loc)) return _Advice(loc);
    }
    if (size < 2) continue;
    for (final ancestor in target.within) {
      for (final combination in _combinations(signals, size - 1)) {
        final loc = <String, Object?>{
          for (final signal in combination) signal.name: signal.value,
          'within': ancestor,
        };
        if (_uniquelyMatches(target, candidates, loc)) return _Advice(loc);
      }
    }
  }

  final indexed = _indexedAdvice(target, candidates, signals);
  return indexed ??
      _Advice(
        signals.isEmpty
            ? const <String, Object?>{}
            : <String, Object?>{signals.first.name: signals.first.value},
        ambiguous: true,
      );
}

List<List<_Signal>> _combinations(List<_Signal> values, int size) {
  final result = <List<_Signal>>[];
  void add(int start, List<_Signal> current) {
    if (current.length == size) {
      result.add(List<_Signal>.of(current));
      return;
    }
    for (
      var index = start;
      index <= values.length - (size - current.length);
      index += 1
    ) {
      current.add(values[index]);
      add(index + 1, current);
      current.removeLast();
    }
  }

  add(0, <_Signal>[]);
  return result;
}

bool _uniquelyMatches(
  _DevTarget target,
  List<_DevTarget> targets,
  Map<String, Object?> loc,
) {
  final matches = targets.where((candidate) => _matches(candidate, loc));
  return matches.length == 1 && identical(matches.single, target);
}

_Advice? _indexedAdvice(
  _DevTarget target,
  List<_DevTarget> targets,
  List<_Signal> signals,
) {
  final groups = <(Map<String, Object?>, List<_DevTarget>)>[];
  for (final signal in signals) {
    final loc = <String, Object?>{signal.name: signal.value};
    final matches = targets.where((item) => _matches(item, loc)).toList();
    if (matches.length > 1) groups.add((loc, matches));
  }
  groups.sort((left, right) => left.$2.length.compareTo(right.$2.length));
  for (final group in groups) {
    if (group.$2.any((item) => item.layout == null) ||
        group.$2.map((item) => item.can.join('|')).toSet().length != 1) {
      continue;
    }
    if (_hasUnstableIndexTie(group.$2, group.$1)) continue;
    final ordered = List<_DevTarget>.of(group.$2)
      ..sort((left, right) => _compareForIndex(left, right, group.$1));
    final index = ordered.indexWhere((item) => identical(item, target));
    if (index >= 0) {
      return _Advice(<String, Object?>{...group.$1, 'index': index});
    }
  }
  return null;
}

bool _matches(_DevTarget target, Map<String, Object?> loc) {
  for (final entry in loc.entries) {
    final expected = entry.value;
    if (expected is! String) continue;
    final matched = switch (entry.key) {
      'id' => target.cockpitId == expected,
      'key' => target.key == expected,
      'text' => <String?>[
        target.text,
        target.displayLabel,
        target.tip,
      ].any((value) => _exactText(value) == _exactText(expected)),
      'tip' => _exactText(target.tip) == _exactText(expected),
      'type' => _type(target.type) == _type(expected),
      'route' => target.route == expected,
      'path' => target.path == expected,
      'within' => target.within.any((type) => _type(type) == _type(expected)),
      _ => true,
    };
    if (!matched) return false;
  }
  return true;
}

int _compareForIndex(
  _DevTarget left,
  _DevTarget right,
  Map<String, Object?> loc,
) {
  final leftLayout = left.layout!;
  final rightLayout = right.layout!;
  var compared = leftLayout.dy.compareTo(rightLayout.dy);
  if (compared != 0) return compared;
  compared = leftLayout.dx.compareTo(rightLayout.dx);
  if (compared != 0) return compared;
  compared = (leftLayout.width * leftLayout.height).compareTo(
    rightLayout.width * rightLayout.height,
  );
  if (compared != 0) return compared;
  compared = _locatorScore(right, loc).compareTo(_locatorScore(left, loc));
  if (compared != 0) return compared;
  return left.registrationId.compareTo(right.registrationId);
}

bool _hasUnstableIndexTie(List<_DevTarget> targets, Map<String, Object?> loc) {
  for (var left = 0; left < targets.length; left += 1) {
    for (var right = left + 1; right < targets.length; right += 1) {
      if (_compareForStableIndex(targets[left], targets[right], loc) == 0) {
        return true;
      }
    }
  }
  return false;
}

int _compareForStableIndex(
  _DevTarget left,
  _DevTarget right,
  Map<String, Object?> loc,
) {
  final leftLayout = left.layout!;
  final rightLayout = right.layout!;
  var compared = leftLayout.dy.compareTo(rightLayout.dy);
  if (compared != 0) return compared;
  compared = leftLayout.dx.compareTo(rightLayout.dx);
  if (compared != 0) return compared;
  compared = (leftLayout.width * leftLayout.height).compareTo(
    rightLayout.width * rightLayout.height,
  );
  if (compared != 0) return compared;
  return _locatorScore(right, loc).compareTo(_locatorScore(left, loc));
}

int _locatorScore(_DevTarget target, Map<String, Object?> loc) {
  var score = 0;
  final text = loc['text'];
  if (text is String) {
    if (_exactText(target.text) == _exactText(text)) {
      score += 10030;
    } else if (_exactText(target.displayLabel) == _exactText(text)) {
      score += 10020;
    } else if (_exactText(target.tip) == _exactText(text)) {
      score += 10012;
    }
  }
  if (loc['tip'] case final String tip) {
    if (_exactText(target.tip) == _exactText(tip)) score += 10020;
  }
  if (target.can.isNotEmpty) score += 8;
  if (_value(target.key) != null) score += 4;
  if (_value(target.cockpitId) != null) score += 3;
  if (_value(target.semanticId) != null) score += 2;
  if (_value(target.text) != null) score += 1;
  score += loc.keys.where((key) => key != 'within').length * 2;
  return score;
}

String? _value(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _exactText(String? value) =>
    _value(value)?.replaceAll(RegExp(r'\s+'), ' ');

String? _searchText(String? value) => _exactText(value)?.toLowerCase();

String? _type(String? value) =>
    _searchText(value)?.replaceAll(RegExp(r'[^a-z0-9]+'), '');
