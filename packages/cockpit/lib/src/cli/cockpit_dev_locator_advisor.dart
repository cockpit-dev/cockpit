import 'package:cockpit_protocol/cockpit_protocol.dart';

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
  final selector = CockpitSelector.isExplicit(query)
      ? CockpitSelector.parse(query)
      : null;
  final normalizedQuery = _searchText(query);
  if (normalizedQuery == null) {
    throw const FormatException('dev inspect query cannot be empty.');
  }
  final matches = selector == null
      ? (targets
            .where((target) => target.matchesQuery(normalizedQuery))
            .toList(growable: false)
          ..sort((left, right) => left.compareForQuery(right, normalizedQuery)))
      : targets;
  final visibleMatches = matches.take(limit).toList(growable: false);
  final queryTargetCount = _snapshotTargetCount(snapshot);

  return <String, Object?>{
    'query': query.trim(),
    'count': matches.length,
    'matches': visibleMatches
        .map(
          (target) => selector != null && matches.length == 1
              ? target.selectorResult(selector)
              : target.result(
                  matches,
                  selector == null ? normalizedQuery : target.searchSeed,
                ),
        )
        .toList(growable: false),
    if (matches.length > visibleMatches.length)
      'more': matches.length - visibleMatches.length,
    if (queryTargetCount != null && queryTargetCount > targets.length)
      'partial': true,
  };
}

int? _snapshotTargetCount(Map<Object?, Object?> snapshot) {
  final summary = snapshot['summary'];
  if (summary is! Map<Object?, Object?>) return null;
  return switch (summary['visibleTargetCount'] ?? summary['visible']) {
    final int value => value,
    _ => null,
  };
}

Map<String, Object?> cockpitBuildDevTargetIndex(
  Map<String, Object?> output, {
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
      .where((target) => target.hasUsefulSignal)
      .toList(growable: false);
  final ranked = List<_DevTarget>.of(targets)..sort(_compareForOverview);
  final visible = ranked.take(limit).toList(growable: false);
  final route =
      _value(snapshot['route'] as String?) ??
      _value(output['route'] as String?) ??
      visible.map((target) => _value(target.route)).nonNulls.firstOrNull;
  return <String, Object?>{
    'route': ?route,
    'count': targets.length,
    'targets': visible
        .map((target) => target.result(targets, target.searchSeed))
        .toList(growable: false),
    if (targets.length > visible.length)
      'more': targets.length - visible.length,
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
      textParts = (value['textParts'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
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
  final List<String> textParts;
  final String? tip;
  final String? type;
  final String? route;
  final String? path;
  final List<String> can;
  final List<String> within;
  final _Layout? layout;

  bool get hasUsefulSignal =>
      can.isNotEmpty ||
      <String?>[
        cockpitId,
        key,
        text,
        tip,
      ].any((value) => _value(value) != null);

  String get searchSeed => _searchText(label) ?? '';

  String? get label => _labelSignal?.value;

  _Signal? get _labelSignal {
    final textValue = _value(text);
    if (textValue != null && !_hasCompositeText) {
      return _Signal('text', textValue);
    }
    if (_value(tip) case final value?) return _Signal('tip', value);
    if (_value(semanticId) case final value?) return _Signal('sem', value);
    if (_value(cockpitId) case final value?) return _Signal('id', value);
    if (_value(key) case final value?) return _Signal('key', value);
    final parts = textParts.map(_value).nonNulls.toList(growable: false)
      ..sort((left, right) => left.length.compareTo(right.length));
    if (parts.firstOrNull case final value?) return _Signal('text', value);
    if (_value(type) case final value?) return _Signal('type', value);
    return null;
  }

  bool get _hasCompositeText {
    final primary = _exactText(text);
    if (primary == null) return false;
    final parts = textParts.map(_exactText).nonNulls.toSet();
    return parts.length > 1 && parts.every(primary.contains);
  }

  String? get displayLabel =>
      _value(cockpitId) ??
      _value(semanticId) ??
      _value(text) ??
      _value(tip) ??
      _value(key) ??
      _value(type);

  List<_Signal> signalsFor(String query) => <_Signal>[
    if (!_hasSyntheticCockpitId)
      if (_value(cockpitId) case final value?) _Signal('id', value),
    if (_value(key) case final value?) _Signal('key', value),
    if (_value(_textFor(query)) case final value?) _Signal('text', value),
    if (_value(tip) case final value?)
      if (_exactText(value) != _exactText(text)) _Signal('tip', value),
    if (_value(semanticId) case final value?) _Signal('sem', value),
    if (_value(type) case final value?) _Signal('type', value),
    if (_value(route) case final value?) _Signal('route', value),
    if (_value(path) case final value?) _Signal('path', value),
  ];

  bool get _hasSyntheticCockpitId =>
      registrationId.startsWith('native.') &&
      (cockpitId == key || cockpitId == semanticId);

  bool matchesQuery(String query) => <String?>[
    text,
    ...textParts,
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
    for (final part in textParts) {
      final value = _searchText(part);
      if (value == query) return 0;
      if (value?.startsWith(query) ?? false) return 10;
    }
    final fields = <String?>[text, tip, cockpitId, semanticId, key, type];
    for (var index = 0; index < fields.length; index += 1) {
      final value = _searchText(fields[index]);
      if (value == query) return index;
      if (value?.startsWith(query) ?? false) return 10 + index;
    }
    return 20;
  }

  String? _textFor(String query) {
    for (final part in textParts) {
      if (_searchText(part) == query) return part;
    }
    for (final part in textParts) {
      if (_searchText(part)?.contains(query) ?? false) return part;
    }
    if (_hasCompositeText &&
        <String?>[
          cockpitId,
          semanticId,
          key,
          tip,
        ].any((value) => _value(value) != null)) {
      return null;
    }
    return text;
  }

  Map<String, Object?> result(List<_DevTarget> targets, String query) {
    final advice = _advise(this, targets, query);
    final actions = _compactActions(can);
    final label = _labelForAdvice(advice.loc);
    return <String, Object?>{
      'sel': CockpitSelector.format(_locator(advice.loc)),
      'label': ?label,
      'can': ?actions,
      if (advice.ambiguous) 'ambiguous': true,
    };
  }

  Map<String, Object?> selectorResult(CockpitLocator locator) {
    final selector = CockpitSelector.format(locator);
    final actions = _compactActions(can);
    final label = _labelForLocator(locator);
    return <String, Object?>{'sel': selector, 'label': ?label, 'can': ?actions};
  }

  String? _labelForAdvice(Map<String, Object?> loc) {
    final signal = _labelSignal;
    if (signal == null) return null;
    final selected = loc[signal.name];
    if (selected is String &&
        _exactText(selected) == _exactText(signal.value)) {
      return null;
    }
    return signal.value;
  }

  String? _labelForLocator(CockpitLocator locator) {
    final signal = _labelSignal;
    if (signal == null) return null;
    final selected = switch (signal.name) {
      'id' => locator.cockpitId,
      'sem' => locator.semanticId,
      'key' => locator.key,
      'text' => locator.text,
      'tip' => locator.tooltip,
      'type' => locator.type,
      _ => null,
    };
    return _exactText(selected) == _exactText(signal.value)
        ? null
        : signal.value;
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

_Advice _advise(_DevTarget target, List<_DevTarget> targets, String query) {
  final candidates = target.can.isEmpty
      ? targets
      : targets
            .where((candidate) => candidate.can.any(target.can.contains))
            .toList(growable: false);
  final signals = target.signalsFor(query);
  final hasPrimarySignal = signals.any(
    (signal) =>
        const <String>{'id', 'sem', 'key', 'text', 'tip'}.contains(signal.name),
  );
  for (var size = 1; size <= signals.length; size += 1) {
    for (final combination in _combinations(signals, size)) {
      if (hasPrimarySignal &&
          !combination.any(
            (signal) => const <String>{
              'id',
              'sem',
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
      'sem' => target.semanticId == expected,
      'key' => target.key == expected,
      'text' => <String?>[
        target.text,
        ...target.textParts,
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
    } else if (target.textParts.any(
      (part) => _exactText(part) == _exactText(text),
    )) {
      score += 10025;
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

int _compareForOverview(_DevTarget left, _DevTarget right) {
  var compared = right.can.isNotEmpty == left.can.isNotEmpty
      ? 0
      : right.can.isNotEmpty
      ? 1
      : -1;
  if (compared != 0) return compared;
  compared = _overviewRank(right).compareTo(_overviewRank(left));
  if (compared != 0) return compared;
  final leftLayout = left.layout;
  final rightLayout = right.layout;
  if (leftLayout != null && rightLayout != null) {
    compared = leftLayout.dy.compareTo(rightLayout.dy);
    if (compared != 0) return compared;
    compared = leftLayout.dx.compareTo(rightLayout.dx);
    if (compared != 0) return compared;
  }
  return (left.label ?? '').compareTo(right.label ?? '');
}

int _overviewRank(_DevTarget target) {
  var rank = 0;
  if (_value(target.cockpitId) != null) rank += 80;
  if (_value(target.key) != null) rank += 60;
  if (_value(target.text) != null) rank += 40;
  if (_value(target.tip) != null) rank += 20;
  return rank;
}

CockpitLocator _locator(Map<String, Object?> loc) => CockpitLocator(
  cockpitId: loc['id'] as String?,
  semanticId: loc['sem'] as String?,
  key: loc['key'] as String?,
  text: loc['text'] as String?,
  tooltip: loc['tip'] as String?,
  type: loc['type'] as String?,
  route: loc['route'] as String?,
  path: loc['path'] as String?,
  index: loc['index'] as int?,
  ancestor: loc['within'] is String
      ? CockpitLocator(type: loc['within']! as String)
      : null,
);

String? _compactActions(List<String> actions) {
  final compact = <String>[];
  for (final action in actions) {
    final value = switch (action) {
      'tap' => 'tap',
      'enterText' || 'setTextEditingValue' || 'focusTextInput' => 'type',
      'scrollUntilVisible' || 'showOnScreen' => 'scroll',
      _ => null,
    };
    if (value == null) continue;
    if (!compact.contains(value)) compact.add(value);
  }
  return compact.isEmpty ? null : compact.join('|');
}
