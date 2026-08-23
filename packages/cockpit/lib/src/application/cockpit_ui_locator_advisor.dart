import 'package:cockpit_protocol/cockpit_protocol.dart';

Map<String, Object?> cockpitBuildUiLocatorMatchesFromOutput(
  Map<String, Object?> output,
  String query, {
  int limit = 12,
}) => cockpitBuildUiLocatorMatches(
  _snapshotFromInspectOutput(output),
  query,
  limit: limit,
);

Map<String, Object?> cockpitBuildUiTargetIndexFromOutput(
  Map<String, Object?> output, {
  int limit = 64,
}) =>
    cockpitBuildUiTargetIndex(_snapshotFromInspectOutput(output), limit: limit);

CockpitSnapshot _snapshotFromInspectOutput(Map<String, Object?> output) {
  final value = output['snapshot'];
  if (value is! Map<Object?, Object?>) {
    throw StateError('ui.inspect locate output did not contain a snapshot.');
  }
  final targets = value['visibleTargets'];
  if (targets is! List<Object?>) {
    throw StateError('ui.inspect locate output did not contain UI targets.');
  }
  final summary = value['summary'];
  final summaryMap = summary is Map<Object?, Object?> ? summary : null;
  final visibleTargetCount =
      summaryMap?['visibleTargetCount'] ?? summaryMap?['visible'];
  return CockpitSnapshot(
    routeName:
        value['routeName'] as String? ??
        value['route'] as String? ??
        output['routeName'] as String? ??
        output['route'] as String?,
    visibleTargets: targets
        .whereType<Map<Object?, Object?>>()
        .map(
          (target) =>
              CockpitSnapshotTarget.fromJson(Map<String, Object?>.from(target)),
        )
        .toList(growable: false),
    truncated: value['truncated'] == true || output['truncated'] == true,
    summary: visibleTargetCount is int
        ? CockpitSnapshotSummary(
            visibleTargetCount: visibleTargetCount,
            targetsWithCockpitIdCount:
                summaryMap?['targetsWithCockpitIdCount'] as int? ?? 0,
            targetsWithTextCount:
                summaryMap?['targetsWithTextCount'] as int? ?? 0,
            styleDetailsIncluded: summaryMap?['styleDetailsIncluded'] == true,
            diagnosticPropertiesIncluded:
                summaryMap?['diagnosticPropertiesIncluded'] == true,
            ancestorSummariesIncluded:
                summaryMap?['ancestorSummariesIncluded'] == true,
            rebuildSummaryIncluded:
                summaryMap?['rebuildSummaryIncluded'] == true,
            accessibilitySummaryIncluded:
                summaryMap?['accessibilitySummaryIncluded'] == true,
          )
        : null,
  );
}

Map<String, Object?> cockpitBuildUiLocatorMatches(
  CockpitSnapshot snapshot,
  String query, {
  int limit = 12,
}) {
  final targets = snapshot.visibleTargets
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
            .where(
              (target) =>
                  target.matchesQuery(normalizedQuery) &&
                  !_isRedundantTextCandidate(target, targets),
            )
            .toList()
          ..sort((left, right) => left.compareForQuery(right, normalizedQuery)))
      : _matchingSelectorTargets(snapshot, targets, selector);
  final visibleMatches = matches.take(limit).toList(growable: false);
  final queryTargetCount = snapshot.summary?.visibleTargetCount;
  final mounted = matches.isEmpty
      ? cockpitBuildUiTargetIndex(snapshot, limit: 4)
      : null;
  final mountedTargets = mounted?['targets'];

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
    if (mounted?['route'] != null) 'route': mounted!['route'],
    if (mountedTargets is List<Object?> && mountedTargets.isNotEmpty)
      'mounted': mountedTargets,
    if (matches.length > visibleMatches.length)
      'more': matches.length - visibleMatches.length,
    if (queryTargetCount != null &&
        queryTargetCount > targets.length &&
        matches.length == targets.length)
      'partial': true,
  };
}

Map<String, Object?> cockpitBuildUiTargetIndex(
  CockpitSnapshot snapshot, {
  int limit = 64,
}) {
  final allTargets = snapshot.visibleTargets
      .map(_DevTarget.new)
      .where((target) => target.hasUsefulSignal)
      .toList(growable: false);
  final targets = allTargets
      .where((target) => target.isControl)
      .where((target) => !_isRedundantTextCandidate(target, allTargets))
      .toList(growable: false);
  final ranked = List<_DevTarget>.of(targets)..sort(_compareForOverview);
  final visible = ranked.take(limit).toList(growable: false);
  final refs = _shortTargetRefs(targets);
  final route =
      _value(snapshot.routeName) ??
      visible.map((target) => _value(target.route)).nonNulls.firstOrNull;
  final targetCount = snapshot.summary?.visibleTargetCount;
  return <String, Object?>{
    'route': ?route,
    'count': targets.length,
    'targets': visible
        .map((target) => target.overviewResult(targets, ref: refs[target]))
        .toList(growable: false),
    if (targets.length > visible.length)
      'more': targets.length - visible.length,
    if (targetCount != null &&
        targetCount > snapshot.visibleTargets.length &&
        targets.length == snapshot.visibleTargets.length)
      'partial': true,
  };
}

List<_DevTarget> _matchingSelectorTargets(
  CockpitSnapshot snapshot,
  List<_DevTarget> targets,
  CockpitLocator selector,
) {
  final registry = CockpitTargetRegistry(routeName: snapshot.routeName);
  final byRegistrationId = <String, _DevTarget>{};
  for (final target in targets) {
    byRegistrationId[target.registrationId] = target;
    registry.register(target.toTarget());
  }
  return registry
      .matchingVisibleTargets(selector)
      .map((target) => byRegistrationId[target.registrationId])
      .nonNulls
      .toList(growable: false);
}

final class _DevTarget {
  _DevTarget(CockpitSnapshotTarget value)
    : registrationId = value.registrationId,
      cockpitId = value.cockpitId,
      semanticId = value.semanticId,
      key = value.keyValue,
      text = value.text,
      textParts = value.textParts,
      tip = value.tooltip,
      type = value.typeName,
      route = value.routeName,
      visible = value.visible,
      path = value.path,
      scrollablePath = value.scrollablePath,
      commands = value.supportedCommands,
      control = value.control,
      can = value.supportedCommands
          .map((command) => command.name)
          .toList(growable: false),
      ancestors = value.ancestors,
      within = value.ancestors
          .map(_DevAncestor.new)
          .where((ancestor) => ancestor.hasUsefulSignal)
          .toList(growable: false),
      layout = _Layout.from(value.layout);

  final String registrationId;
  final String? cockpitId;
  final String? semanticId;
  final String? key;
  final String? text;
  final List<String> textParts;
  final String? tip;
  final String? type;
  final String? route;
  final bool visible;
  final String? path;
  final String? scrollablePath;
  final List<CockpitCommandType> commands;
  final CockpitControlState? control;
  final List<String> can;
  final List<CockpitSnapshotAncestor> ancestors;
  final List<_DevAncestor> within;
  final _Layout? layout;

  CockpitTarget toTarget() => CockpitTarget(
    registrationId: registrationId,
    cockpitId: cockpitId,
    semanticId: semanticId,
    keyValue: key,
    text: text,
    textParts: textParts.toSet(),
    tooltip: tip,
    typeName: type,
    path: path,
    scrollablePath: scrollablePath,
    routeName: route ?? '',
    supportedCommands: commands.toSet(),
    control: control,
    locatorAncestors: ancestors,
    geometryProvider: layout == null
        ? null
        : () => CockpitTargetGeometry(
            left: layout!.dx,
            top: layout!.dy,
            width: layout!.width,
            height: layout!.height,
            viewportLeft: 0,
            viewportTop: 0,
            viewportWidth: 0,
            viewportHeight: 0,
            viewId: 0,
          ),
  );

  bool get hasUsefulSignal =>
      control != null ||
      can.isNotEmpty ||
      <String?>[
        cockpitId,
        key,
        text,
        tip,
      ].any((value) => _value(value) != null);

  bool get isControl => compactActions != null || _hasBlockedControlState;

  bool get _hasBlockedControlState {
    final value = control;
    return value != null &&
        (!value.enabled || value.selected != null || value.checked != null);
  }

  String? get compactActions {
    final actions = _compactActions(can);
    if (actions == null || control?.readOnly != true || _isTextInputType) {
      return actions;
    }
    final values = actions.split('|').toSet();
    return const <String>{'tap', 'hold', 'double'}.containsAll(values)
        ? null
        : actions;
  }

  bool get _isTextInputType => const <String>{
    'TextField',
    'TextFormField',
    'CupertinoTextField',
    'CupertinoSearchTextField',
  }.contains(type);

  bool get hasStableIdentity => <String?>[
    cockpitId,
    semanticId,
    key,
  ].any((value) => _value(value) != null);

  String get searchSeed => _searchText(label) ?? '';

  String? get label => _labelSignal?.value;

  List<String> get _humanLabels {
    final values = <String?>[
      if (!_hasCompositeText) text,
      tip,
      semanticId,
      if (!_hasSyntheticCockpitId) cockpitId,
      key,
      ...textParts,
    ];
    final labels = <String>[];
    final seen = <String>{};
    for (final candidate in values) {
      final value = _value(candidate);
      final normalized = _searchText(value);
      if (value != null && normalized != null && seen.add(normalized)) {
        labels.add(value);
      }
    }
    return labels;
  }

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
      'state': ?_compactTargetState(this),
      'value': ?_compactControlValue(control?.value),
      if (advice.ambiguous) 'ambiguous': true,
    };
  }

  Map<String, Object?> overviewResult(
    List<_DevTarget> targets, {
    required String? ref,
  }) {
    if (ref == null) {
      return result(targets, searchSeed);
    }
    final label = _overviewLabel(targets);
    final actions = compactActions;
    final needsPosition = label == null || !_hasUniqueLabelSignal(targets);
    return <String, Object?>{
      'sel': ':$ref',
      'label': ?label,
      if (label == null) 'type': ?type,
      if (needsPosition) 'at': ?_compactPosition(layout),
      'can': ?actions,
      'state': ?_compactTargetState(this),
      'value': ?_compactControlValue(control?.value),
    };
  }

  String? _overviewLabel(List<_DevTarget> targets) {
    final labels = _humanLabels;
    final primary = labels.firstOrNull;
    if (primary == null || _isUniqueLabel(primary, targets)) {
      return primary;
    }
    for (final qualifier in labels.skip(1)) {
      if (_isUniqueLabel(qualifier, targets)) {
        return '$primary · $qualifier';
      }
    }
    return primary;
  }

  bool _hasUniqueLabelSignal(List<_DevTarget> targets) =>
      _humanLabels.any((label) => _isUniqueLabel(label, targets));

  bool _isUniqueLabel(String value, List<_DevTarget> targets) {
    final normalized = _searchText(value);
    if (normalized == null) return false;
    return targets.where((target) {
          return target._humanLabels.any(
            (label) => _searchText(label) == normalized,
          );
        }).length ==
        1;
  }

  Map<String, Object?> selectorResult(CockpitLocator locator) {
    final selector = CockpitSelector.format(locator);
    final actions = _compactActions(can);
    final label = _labelForLocator(locator);
    return <String, Object?>{
      'sel': selector,
      'label': ?label,
      'can': ?actions,
      'state': ?_compactTargetState(this),
      'value': ?_compactControlValue(control?.value),
    };
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

bool _isRedundantTextCandidate(_DevTarget target, List<_DevTarget> candidates) {
  if (target.hasStableIdentity ||
      !const <String>{'Text', 'RichText'}.contains(target.type) ||
      _value(target.text) == null ||
      target.layout == null) {
    return false;
  }
  return candidates.any(
    (candidate) =>
        !identical(candidate, target) &&
        candidate.hasStableIdentity &&
        _exactText(candidate.text) == _exactText(target.text) &&
        candidate.route == target.route &&
        candidate.scrollablePath == target.scrollablePath &&
        _coversActions(candidate.can, target.can) &&
        _sameVerticalBand(candidate.layout, target.layout),
  );
}

bool _coversActions(List<String> stable, List<String> proxy) =>
    stable.toSet().containsAll(proxy);

bool _sameVerticalBand(_Layout? left, _Layout? right) {
  if (left == null || right == null) return false;
  final top = left.dy > right.dy ? left.dy : right.dy;
  final bottom = left.dy + left.height < right.dy + right.height
      ? left.dy + left.height
      : right.dy + right.height;
  final overlap = bottom - top;
  if (overlap <= 0) return false;
  final shorter = left.height < right.height ? left.height : right.height;
  return shorter > 0 && overlap >= shorter * 0.8;
}

final class _Signal {
  const _Signal(this.name, this.value);
  final String name;
  final String value;
}

final class _DevAncestor {
  _DevAncestor(CockpitSnapshotAncestor value)
    : cockpitId = value.cockpitId,
      semanticId = value.semanticId,
      key = value.keyValue,
      text = value.textPreview,
      tip = value.tooltip,
      type = value.typeName,
      route = value.routeName,
      path = value.path;

  final String? cockpitId;
  final String? semanticId;
  final String? key;
  final String? text;
  final String? tip;
  final String? type;
  final String? route;
  final String? path;

  bool get hasUsefulSignal => signals(includePath: true).isNotEmpty;

  List<_Signal> signals({required bool includePath}) => <_Signal>[
    if (_value(cockpitId) case final value?)
      if (value != _value(key) && value != _value(semanticId))
        _Signal('id', value),
    if (_value(key) case final value?) _Signal('key', value),
    if (_value(text) case final value?) _Signal('text', value),
    if (_value(tip) case final value?)
      if (_exactText(value) != _exactText(text)) _Signal('tip', value),
    if (_value(semanticId) case final value?) _Signal('sem', value),
    if (_value(type) case final value?) _Signal('type', value),
    if (includePath)
      if (_value(path) case final value?) _Signal('path', value),
  ];
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

  static _Layout? from(CockpitSnapshotLayout? value) => value == null
      ? null
      : _Layout(value.dx, value.dy, value.width, value.height);
}

_Advice _advise(_DevTarget target, List<_DevTarget> targets, String query) {
  final candidates = target.can.isEmpty
      ? targets
      : targets
            .where((candidate) => candidate.can.any(target.can.contains))
            .toList(growable: false);
  final signals = target.signalsFor(query);
  final stableSignals = signals
      .where((signal) => signal.name != 'path')
      .toList(growable: false);
  final direct = _directAdvice(target, candidates, stableSignals);
  if (direct != null) return direct;

  final scoped = _scopedAdvice(target, candidates, stableSignals);
  if (scoped != null) return scoped;

  final pathAware = _directAdvice(
    target,
    candidates,
    signals,
    requirePath: true,
  );
  if (pathAware != null) return pathAware;

  final indexed = _indexedAdvice(target, candidates, signals);
  return indexed ??
      _Advice(
        signals.isEmpty
            ? const <String, Object?>{}
            : <String, Object?>{signals.first.name: signals.first.value},
        ambiguous: true,
      );
}

_Advice? _directAdvice(
  _DevTarget target,
  List<_DevTarget> candidates,
  List<_Signal> signals, {
  bool requirePath = false,
}) {
  final hasPrimarySignal = signals.any(_isPrimarySignal);
  for (var size = 1; size <= signals.length; size += 1) {
    for (final combination in _combinations(signals, size)) {
      if (hasPrimarySignal && !combination.any(_isPrimarySignal)) continue;
      if (requirePath && !combination.any((signal) => signal.name == 'path')) {
        continue;
      }
      final loc = _signalMap(combination);
      if (_uniquelyMatches(target, candidates, loc)) return _Advice(loc);
    }
  }
  return null;
}

_Advice? _scopedAdvice(
  _DevTarget target,
  List<_DevTarget> candidates,
  List<_Signal> directSignals,
) {
  if (directSignals.isEmpty || target.within.isEmpty) return null;
  final hasPrimarySignal = directSignals.any(_isPrimarySignal);
  var checks = 0;
  const maxChecks = 512;
  for (var totalSize = 2; totalSize <= 4; totalSize += 1) {
    final maxDirectSize = directSignals.length < 2 ? directSignals.length : 2;
    for (var directSize = 1; directSize <= maxDirectSize; directSize += 1) {
      final scopeSize = totalSize - directSize;
      if (scopeSize < 1 || scopeSize > 2) continue;
      for (final direct in _combinations(directSignals, directSize)) {
        if (hasPrimarySignal && !direct.any(_isPrimarySignal)) continue;
        final directLoc = _signalMap(direct);
        final directMatches = candidates
            .where((candidate) => _matches(candidate, directLoc))
            .toList(growable: false);
        if (!directMatches.any((candidate) => identical(candidate, target))) {
          continue;
        }
        for (final scope in _ancestorScopes(
          target.within,
          conditions: scopeSize,
        )) {
          checks += 1;
          if (checks > maxChecks) return null;
          final loc = <String, Object?>{..._signalMap(direct), 'within': scope};
          final matches = directMatches.where(
            (candidate) => _matchesAncestorChain(candidate.within, scope),
          );
          if (matches.length == 1 && identical(matches.single, target)) {
            return _Advice(loc);
          }
        }
      }
    }
  }
  return null;
}

Iterable<Map<String, Object?>> _ancestorScopes(
  List<_DevAncestor> ancestors, {
  required int conditions,
}) sync* {
  final signals = ancestors
      .map((ancestor) => ancestor.signals(includePath: false))
      .toList(growable: false);
  for (final values in signals) {
    if (values.length < conditions) continue;
    for (final combination in _combinations(values, conditions)) {
      yield _signalMap(combination);
    }
  }
  if (conditions != 2) return;
  for (var inner = 0; inner < signals.length; inner += 1) {
    for (var outer = inner + 1; outer < signals.length; outer += 1) {
      for (final innerSignal in signals[inner]) {
        for (final outerSignal in signals[outer]) {
          yield <String, Object?>{
            innerSignal.name: innerSignal.value,
            'within': <String, Object?>{outerSignal.name: outerSignal.value},
          };
        }
      }
    }
  }
}

Map<String, Object?> _signalMap(List<_Signal> signals) => <String, Object?>{
  for (final signal in signals) signal.name: signal.value,
};

bool _isPrimarySignal(_Signal signal) =>
    const <String>{'id', 'sem', 'key', 'text', 'tip'}.contains(signal.name);

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
    if (entry.key == 'within') {
      if (expected is! Map<String, Object?> ||
          !_matchesAncestorChain(target.within, expected)) {
        return false;
      }
      continue;
    }
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
      'path' => _pathMatches(target.path, expected),
      _ => true,
    };
    if (!matched) return false;
  }
  return true;
}

bool _matchesAncestorChain(
  List<_DevAncestor> ancestors,
  Map<String, Object?> loc,
) {
  for (var index = 0; index < ancestors.length; index += 1) {
    if (!_matchesAncestor(ancestors[index], loc)) continue;
    final parent = loc['within'];
    if (parent == null) return true;
    if (parent is Map<String, Object?> &&
        _matchesAncestorChain(ancestors.sublist(index + 1), parent)) {
      return true;
    }
  }
  return false;
}

bool _matchesAncestor(_DevAncestor ancestor, Map<String, Object?> loc) {
  for (final entry in loc.entries) {
    if (entry.key == 'within') continue;
    final expected = entry.value;
    if (expected is! String) continue;
    final matched = switch (entry.key) {
      'id' => ancestor.cockpitId == expected,
      'sem' =>
        ancestor.semanticId == expected || ancestor.cockpitId == expected,
      'key' => ancestor.key == expected || ancestor.cockpitId == expected,
      'text' => <String?>[
        ancestor.text,
        ancestor.tip,
      ].any((value) => _exactText(value) == _exactText(expected)),
      'tip' => _exactText(ancestor.tip) == _exactText(expected),
      'type' => _type(ancestor.type) == _type(expected),
      'route' => ancestor.route == expected,
      'path' => _pathMatches(ancestor.path, expected),
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

bool _pathMatches(String? candidate, String expected) {
  final candidateSegments = _pathSegments(candidate);
  final expectedSegments = _pathSegments(expected);
  if (candidateSegments.isEmpty || expectedSegments.isEmpty) return false;
  if (_endsWith(candidateSegments, expectedSegments)) return true;
  var expectedIndex = 0;
  for (final segment in candidateSegments) {
    if (segment == expectedSegments[expectedIndex]) expectedIndex += 1;
    if (expectedIndex == expectedSegments.length) return true;
  }
  return false;
}

List<String> _pathSegments(String? value) =>
    (value ?? '').split('/').where((segment) => segment.isNotEmpty).toList();

bool _endsWith(List<String> value, List<String> suffix) {
  if (suffix.length > value.length) return false;
  final offset = value.length - suffix.length;
  for (var index = 0; index < suffix.length; index += 1) {
    if (value[offset + index] != suffix[index]) return false;
  }
  return true;
}

int _compareForOverview(_DevTarget left, _DevTarget right) {
  final leftLayout = left.layout;
  final rightLayout = right.layout;
  if (leftLayout != null && rightLayout != null) {
    var compared = leftLayout.dy.compareTo(rightLayout.dy);
    if (compared != 0) return compared;
    compared = leftLayout.dx.compareTo(rightLayout.dx);
    if (compared != 0) return compared;
  } else if (leftLayout != null) {
    return -1;
  } else if (rightLayout != null) {
    return 1;
  }
  var compared = right.can.isNotEmpty == left.can.isNotEmpty
      ? 0
      : right.can.isNotEmpty
      ? 1
      : -1;
  if (compared != 0) return compared;
  compared = _overviewRank(right).compareTo(_overviewRank(left));
  if (compared != 0) return compared;
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

Map<_DevTarget, String> _shortTargetRefs(List<_DevTarget> targets) {
  final tokens = <_DevTarget, String>{
    for (final target in targets)
      target: cockpitTargetRefToken(target.registrationId),
  };
  final refs = <_DevTarget, String>{};
  for (final target in targets) {
    final token = tokens[target]!;
    for (
      var length = cockpitTargetRefMinimumLength;
      length <= token.length;
      length += 1
    ) {
      final candidate = token.substring(0, length);
      final unique = tokens.entries.every(
        (entry) =>
            identical(entry.key, target) || !entry.value.startsWith(candidate),
      );
      if (unique) {
        refs[target] = candidate;
        break;
      }
    }
  }
  return refs;
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
  ancestor: switch (loc['within']) {
    final Map<String, Object?> value => _locator(value),
    _ => null,
  },
);

String? _compactActions(List<String> actions) {
  final compact = <String>[];
  for (final action in actions) {
    final value = switch (action) {
      'tap' => 'tap',
      'enterText' || 'setTextEditingValue' || 'focusTextInput' => 'type',
      'longPress' => 'hold',
      'doubleTap' => 'double',
      'increase' => 'inc',
      'decrease' => 'dec',
      'dismiss' => 'dismiss',
      'scrollUntilVisible' || 'showOnScreen' => 'scroll',
      _ => null,
    };
    if (value == null) continue;
    if (!compact.contains(value)) compact.add(value);
  }
  return compact.isEmpty ? null : compact.join('|');
}

String? _compactPosition(_Layout? layout) {
  if (layout == null) return null;
  final x = (layout.dx + layout.width / 2).round();
  final y = (layout.dy + layout.height / 2).round();
  return '$x,$y';
}

String? _compactControlState(CockpitControlState? control) {
  if (control == null) return null;
  final values = <String>[
    if (!control.enabled) 'disabled',
    if (control.selected case final selected?)
      selected ? 'selected' : 'unselected',
    if (control.checked case final checked?) checked.jsonValue,
    if (control.focused) 'focused',
    if (control.readOnly) 'readonly',
    if (control.obscured) 'obscured',
  ];
  return values.isEmpty ? null : values.join('|');
}

String? _compactTargetState(_DevTarget target) {
  final controlState = _compactControlState(target.control);
  if (target.visible) {
    return controlState;
  }
  return controlState == null ? 'offscreen' : 'offscreen|$controlState';
}

Object? _compactControlValue(Object? value) {
  if (value is String) {
    final normalized = _exactText(value);
    if (normalized == null) return null;
    const limit = 96;
    return normalized.length <= limit
        ? normalized
        : '${normalized.substring(0, limit)}…';
  }
  if (value is List<Object?>) {
    const limit = 4;
    return <Object?>[
      ...value.take(limit).map(_compactControlValue),
      if (value.length > limit) '…',
    ];
  }
  return value;
}
