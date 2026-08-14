// ignore_for_file: deprecated_member_use

import 'dart:collection';

import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../control/cockpit_command_type.dart';
import '../errors/cockpit_command_error.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_target.dart';
import 'cockpit_target_geometry.dart';

typedef CockpitDiscoveredTargetsProvider = List<CockpitTarget> Function();
typedef CockpitDiscoveredTargetsReadinessProbe =
    bool Function({bool allowRouteFallback, String? routeName});

final class CockpitTargetResolutionResult {
  const CockpitTargetResolutionResult._({
    this.target,
    this.locatorResolution,
    this.error,
    this.matches = const <CockpitTarget>[],
  });

  /// Creates a CockpitTargetResolutionResult using the named constructor `success`.
  const CockpitTargetResolutionResult.success({
    required CockpitTarget target,
    CockpitLocatorResolution? locatorResolution,
    List<CockpitTarget> matches = const <CockpitTarget>[],
  }) : this._(
         target: target,
         locatorResolution: locatorResolution,
         matches: matches,
       );

  /// Creates a CockpitTargetResolutionResult using the named constructor `failure`.
  const CockpitTargetResolutionResult.failure({
    required CockpitCommandError error,
    List<CockpitTarget> matches = const <CockpitTarget>[],
  }) : this._(error: error, matches: matches);

  final CockpitTarget? target;
  final CockpitLocatorResolution? locatorResolution;
  final CockpitCommandError? error;
  final List<CockpitTarget> matches;

  bool get isSuccess => target != null && error == null;
}

final class CockpitTargetRegistry {
  static const int liveSnapshotTargetLimit = 25;
  static const int candidateDetailLimit = 8;

  /// Creates a CockpitTargetRegistry.
  CockpitTargetRegistry({this.routeName});

  final LinkedHashMap<String, CockpitTarget> _targets =
      LinkedHashMap<String, CockpitTarget>();

  String? routeName;
  CockpitDiscoveredTargetsProvider? discoveredTargetsProvider;
  CockpitDiscoveredTargetsReadinessProbe? discoveredTargetsReadinessProbe;
  int _discoveryCacheDepth = 0;
  List<CockpitTarget>? _cachedDiscoveredTargets;

  List<CockpitTarget> get registeredTargets =>
      List.unmodifiable(_targets.values.toList(growable: false));

  List<CockpitTarget> get visibleTargets => _withDiscoveryCache(() {
    return List.unmodifiable(<CockpitTarget>[
      ..._explicitVisibleTargets(),
      ..._deduplicatedDiscoveredVisibleTargets(),
    ]);
  });

  List<CockpitTarget> get routeReadyVisibleTargets => _withDiscoveryCache(() {
    return List.unmodifiable(<CockpitTarget>[
      ..._explicitVisibleTargets(allowRouteFallback: false),
      ..._deduplicatedDiscoveredVisibleTargets(allowRouteFallback: false),
    ]);
  });

  /// Returns visible targets satisfying every condition in [locator].
  ///
  /// Results use visual order. A requested locator index reduces the result to
  /// that one target, while an out-of-range index returns an empty list.
  List<CockpitTarget> matchingVisibleTargets(CockpitLocator locator) {
    return _withDiscoveryCache(() {
      final matches = _preferCurrentRouteMatches(
        visibleTargets
            .where((target) => _matches(target, locator))
            .toList(growable: false),
      );
      if (locator.index != null) {
        final selected = _selectIndexedMatch(matches, locator);
        return selected == null
            ? const <CockpitTarget>[]
            : <CockpitTarget>[selected];
      }
      return List<CockpitTarget>.unmodifiable(
        _orderedMatches(matches, locator),
      );
    });
  }

  bool get hasRouteReadyVisibleTargets {
    return _withDiscoveryCache(() {
      if (_explicitVisibleTargets(allowRouteFallback: false).isNotEmpty) {
        return true;
      }
      final probe = discoveredTargetsReadinessProbe;
      if (probe != null) {
        return probe(allowRouteFallback: false, routeName: routeName);
      }
      return _discoveredVisibleTargets(allowRouteFallback: false).isNotEmpty;
    });
  }

  void register(CockpitTarget target) {
    _targets[target.registrationId] = target;
  }

  Map<String, Object?> routeDiagnostics({int hintLimit = 8}) {
    return _withDiscoveryCache(() {
      final registeredTargets = _targets.values.toList(growable: false);
      final discoveredTargets = _discoveredTargets();
      final allTargets = <CockpitTarget>[
        ...registeredTargets,
        ...discoveredTargets,
      ];

      return <String, Object?>{
        'currentRouteName': routeName,
        'registeredTargetCount': registeredTargets.length,
        'discoveredTargetCount': discoveredTargets.length,
        'visibleTargetCount': visibleTargets.length,
        'routeReadyVisibleTargetCount': routeReadyVisibleTargets.length,
        'registeredRouteCounts': _routeCounts(registeredTargets),
        'discoveredRouteCounts': _routeCounts(discoveredTargets),
        'hiddenTargetCount': allTargets
            .where((target) => !target.isVisible)
            .length,
        'targetHints': _targetHintsFor(
          allTargets.where((target) => target.isVisible),
          limit: hintLimit,
        ),
      };
    });
  }

  void unregister(String registrationId) {
    _targets.remove(registrationId);
  }

  CockpitTargetResolutionResult resolve(
    CockpitLocator locator, {
    CockpitCommandType? requiredCommand,
  }) {
    return _withDiscoveryCache(() {
      for (final candidate in _flatten(locator)) {
        final locatorMatches = _preferCurrentRouteMatches(
          visibleTargets
              .where((target) => _matches(target, candidate))
              .toList(growable: false),
        );
        final commandMatches = requiredCommand == null
            ? locatorMatches
            : locatorMatches
                  .where(
                    (target) =>
                        target.supportedCommands.contains(requiredCommand),
                  )
                  .toList(growable: false);
        final matches = commandMatches.isEmpty
            ? locatorMatches
            : commandMatches;

        if (matches.isEmpty) {
          continue;
        }

        if (candidate.index != null) {
          final indexedMatch = _selectIndexedMatch(matches, candidate);
          if (indexedMatch == null) {
            final orderedMatches = _orderedMatches(matches, candidate);
            return CockpitTargetResolutionResult.failure(
              error: CockpitCommandError.targetNotFound(
                message:
                    'No matched target exists at the requested locator index.',
                details: <String, Object?>{
                  'requestedLocator': candidate.toJson(),
                  'matchedCount': matches.length,
                  'requestedIndex': candidate.index,
                  'candidateCount': orderedMatches.length,
                  'candidates': _candidateIdsFor(orderedMatches),
                  'candidateHints': _targetHintsFor(orderedMatches),
                },
              ),
              matches: matches,
            );
          }
          return CockpitTargetResolutionResult.success(
            target: indexedMatch,
            locatorResolution: CockpitLocatorResolution(
              matchedKind: candidate.kind,
              matchedValue: candidate.value,
              matchedSignals: _matchedSignals(candidate),
            ),
            matches: matches,
          );
        }

        if (matches.length > 1) {
          final orderedMatches = _orderedMatches(matches, candidate);
          final preferredMatch = _selectPreferredMatch(matches, candidate);
          if (preferredMatch != null) {
            return CockpitTargetResolutionResult.success(
              target: preferredMatch,
              locatorResolution: CockpitLocatorResolution(
                matchedKind: candidate.kind,
                matchedValue: candidate.value,
                matchedSignals: _matchedSignals(candidate),
              ),
              matches: matches,
            );
          }
          return CockpitTargetResolutionResult.failure(
            error: CockpitCommandError.ambiguousTarget(
              message: 'Multiple targets matched ${candidate.kind.name}.',
              details: <String, Object?>{
                'matchedKind': candidate.kind.name,
                'matchedValue': candidate.value,
                'candidateCount': orderedMatches.length,
                'candidates': _candidateIdsFor(orderedMatches),
                'candidateHints': _targetHintsFor(orderedMatches),
              },
            ),
            matches: matches,
          );
        }

        return CockpitTargetResolutionResult.success(
          target: matches.single,
          locatorResolution: CockpitLocatorResolution(
            matchedKind: candidate.kind,
            matchedValue: candidate.value,
            matchedSignals: _matchedSignals(candidate),
          ),
          matches: matches,
        );
      }

      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: 'No visible target matched the requested locator chain.',
          details: <String, Object?>{'requestedLocator': locator.toJson()},
        ),
      );
    });
  }

  CockpitTargetResolutionResult resolveCommand(CockpitCommandType commandType) {
    return _withDiscoveryCache(() {
      final matches = _preferCurrentRouteMatches(
        visibleTargets
            .where((target) => target.supportedCommands.contains(commandType))
            .toList(growable: false),
      );
      if (matches.isEmpty) {
        return CockpitTargetResolutionResult.failure(
          error: CockpitCommandError.targetNotFound(
            message: 'No visible target supports ${commandType.name}.',
            details: <String, Object?>{'requiredCommand': commandType.name},
          ),
        );
      }
      if (matches.length > 1) {
        return CockpitTargetResolutionResult.failure(
          error: CockpitCommandError.ambiguousTarget(
            message: 'Multiple visible targets support ${commandType.name}.',
            details: <String, Object?>{
              'requiredCommand': commandType.name,
              'candidateCount': matches.length,
              'candidates': _candidateIdsFor(matches),
              'candidateHints': _targetHintsFor(matches),
            },
          ),
          matches: matches,
        );
      }
      return CockpitTargetResolutionResult.success(target: matches.single);
    });
  }

  CockpitSnapshot snapshot() {
    return _withDiscoveryCache(() {
      final targets = visibleTargets;
      final prioritizedTargets = _prioritizeForLiveSnapshot(targets);
      final truncatedTargets = prioritizedTargets
          .take(liveSnapshotTargetLimit)
          .map(_liveSnapshotTarget)
          .toList(growable: false);

      return CockpitSnapshot(
        routeName: routeName,
        visibleTargets: truncatedTargets,
        truncated: prioritizedTargets.length > liveSnapshotTargetLimit,
        summary: CockpitSnapshotSummary(
          visibleTargetCount: targets.length,
          targetsWithCockpitIdCount: targets
              .where((target) => target.cockpitId != null)
              .length,
          targetsWithTextCount: targets
              .where((target) => target.text != null && target.text!.isNotEmpty)
              .length,
          styleDetailsIncluded: false,
          diagnosticPropertiesIncluded: false,
          ancestorSummariesIncluded: false,
          rebuildSummaryIncluded: false,
          accessibilitySummaryIncluded: false,
        ),
      );
    });
  }

  CockpitSnapshotTarget _liveSnapshotTarget(CockpitTarget target) {
    return CockpitSnapshotTarget(
      registrationId: target.registrationId,
      cockpitId: target.cockpitId,
      semanticId: target.semanticId,
      keyValue: target.keyValue,
      text: target.text,
      textParts: target.textParts.toList(growable: false),
      tooltip: target.tooltip,
      typeName: target.typeName,
      path: target.path,
      scrollablePath: target.scrollablePath,
      scrollableKeyValue: target.scrollableKeyValue,
      scrollableTypeName: target.scrollableTypeName,
      routeName: target.routeName,
      supportedCommands: target.supportedCommands.toList(growable: false),
    );
  }

  T _withDiscoveryCache<T>(T Function() action) {
    _discoveryCacheDepth += 1;
    try {
      return action();
    } finally {
      _discoveryCacheDepth -= 1;
      if (_discoveryCacheDepth == 0) {
        _cachedDiscoveredTargets = null;
      }
    }
  }

  List<CockpitTarget> _discoveredTargets() {
    final provider = discoveredTargetsProvider;
    if (provider == null) {
      return const <CockpitTarget>[];
    }
    if (_discoveryCacheDepth > 0) {
      return _cachedDiscoveredTargets ??= provider().toList(growable: false);
    }
    return provider().toList(growable: false);
  }

  List<CockpitTarget> _prioritizeForLiveSnapshot(List<CockpitTarget> targets) {
    final prioritized = targets.toList(growable: false);
    prioritized.sort((left, right) {
      final commandCompare = right.supportedCommands.length.compareTo(
        left.supportedCommands.length,
      );
      if (commandCompare != 0) {
        return commandCompare;
      }

      final leftSignalScore = _signalScore(left);
      final rightSignalScore = _signalScore(right);
      final signalCompare = rightSignalScore.compareTo(leftSignalScore);
      if (signalCompare != 0) {
        return signalCompare;
      }

      return left.registrationId.compareTo(right.registrationId);
    });
    return prioritized;
  }

  int _signalScore(CockpitTarget target) {
    var score = 0;
    if (target.keyValue != null && target.keyValue!.isNotEmpty) {
      score += 4;
    }
    if (target.semanticId != null && target.semanticId!.isNotEmpty) {
      score += 3;
    }
    if (target.text != null && target.text!.isNotEmpty) {
      score += 2;
    }
    if (target.tooltip != null && target.tooltip!.isNotEmpty) {
      score += 1;
    }
    return score;
  }

  List<Map<String, Object?>> _targetHintsFor(
    Iterable<CockpitTarget> targets, {
    int limit = 8,
  }) {
    final hints = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final target in targets) {
      final hint = _targetHintFor(target);
      if (!seen.add(_targetHintSignature(hint))) {
        continue;
      }
      hints.add(hint);
      if (hints.length >= limit) {
        break;
      }
    }
    return hints;
  }

  List<String> _candidateIdsFor(Iterable<CockpitTarget> targets) {
    return targets
        .take(candidateDetailLimit)
        .map((target) => target.registrationId)
        .toList(growable: false);
  }

  Map<String, Object?> _targetHintFor(CockpitTarget target) {
    final hint = <String, Object?>{
      if (target.cockpitId != null) 'cockpitId': target.cockpitId,
      if (target.semanticId != null) 'semanticId': target.semanticId,
      if (target.keyValue != null) 'key': target.keyValue,
      if (target.text != null) 'text': target.text,
      if (target.tooltip != null) 'tooltip': target.tooltip,
      if (target.typeName != null) 'type': target.typeName,
      if (target.routeName.isNotEmpty) 'route': target.routeName,
      if (target.supportedCommands.isNotEmpty)
        'supportedCommands': target.supportedCommands
            .map((command) => command.name)
            .toList(growable: false),
    };
    if (hint.isEmpty) {
      hint['registrationId'] = target.registrationId;
    }
    return hint;
  }

  String _targetHintSignature(Map<String, Object?> hint) {
    return <Object?>[
      hint['cockpitId'],
      hint['semanticId'],
      hint['key'],
      hint['text'],
      hint['tooltip'],
      hint['type'],
      hint['route'],
      hint['supportedCommands'],
    ].join('|');
  }

  Iterable<CockpitLocator> _flatten(CockpitLocator locator) sync* {
    yield locator;
    for (final fallback in locator.fallbacks) {
      yield* _flatten(fallback);
    }
  }

  bool _matches(CockpitTarget target, CockpitLocator locator) {
    if (!locator.hasSignals) {
      return false;
    }
    for (final signal in locator.signals) {
      if (!_matchesSignal(
        target,
        signal.kind,
        signal.value,
        locator.matchMode,
      )) {
        return false;
      }
    }
    final ancestor = locator.ancestor;
    if (ancestor != null && !_matchesAncestorScope(target, ancestor)) {
      return false;
    }
    return true;
  }

  bool _matchesSignal(
    CockpitTarget target,
    CockpitLocatorKind kind,
    String value,
    CockpitTextMatchMode matchMode,
  ) {
    return switch (kind) {
      CockpitLocatorKind.cockpitId => target.cockpitId == value,
      CockpitLocatorKind.semanticId => _matchesTextSignal(
        target.semanticId,
        value,
        matchMode,
      ),
      CockpitLocatorKind.key => target.keyValue == value,
      CockpitLocatorKind.text => _matchesTextLocator(target, value, matchMode),
      CockpitLocatorKind.tooltip => _matchesTextSignal(
        target.tooltip,
        value,
        matchMode,
      ),
      CockpitLocatorKind.type => _matchesTypeSignal(target.typeName, value),
      CockpitLocatorKind.route => target.routeName == value,
      CockpitLocatorKind.registrationId => target.registrationId == value,
      CockpitLocatorKind.path => _matchesPath(target.path, value),
      CockpitLocatorKind.nativeId ||
      CockpitLocatorKind.testId ||
      CockpitLocatorKind.role ||
      CockpitLocatorKind.coordinate ||
      CockpitLocatorKind.visual => false,
    };
  }

  bool _matchesTextLocator(
    CockpitTarget target,
    String expected,
    CockpitTextMatchMode matchMode,
  ) {
    return <String?>[
      target.text,
      ...target.textParts,
      target.displayLabel,
      target.tooltip,
    ].any((candidate) => _matchesTextSignal(candidate, expected, matchMode));
  }

  bool _matchesTextSignal(
    String? candidate,
    String expected,
    CockpitTextMatchMode matchMode,
  ) => candidate != null && cockpitTextMatches(candidate, expected, matchMode);

  bool _matchesTypeSignal(String? candidate, String expected) {
    final normalizedCandidate = _normalizeTypeName(candidate);
    final normalizedExpected = _normalizeTypeName(expected);
    if (normalizedCandidate == null || normalizedExpected == null) {
      return false;
    }
    return normalizedCandidate == normalizedExpected;
  }

  String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeTypeName(String? value) {
    final normalized = _normalizeText(value)?.toLowerCase();
    if (normalized == null) {
      return null;
    }
    final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return compact.isEmpty ? null : compact;
  }

  List<CockpitTarget> _explicitVisibleTargets({
    bool allowRouteFallback = true,
  }) {
    return _visibleTargetsFor(
      _targets.values,
      allowRouteFallback: allowRouteFallback,
    );
  }

  List<CockpitTarget> _discoveredVisibleTargets({
    bool allowRouteFallback = true,
  }) {
    return _visibleTargetsFor(
      _discoveredTargets(),
      allowRouteFallback: allowRouteFallback,
    );
  }

  List<CockpitTarget> _visibleTargetsFor(
    Iterable<CockpitTarget> targets, {
    bool allowRouteFallback = true,
  }) {
    final visibleTargets = targets
        .where((target) => target.isVisible)
        .toList(growable: false);
    final currentRouteName = routeName;
    if (currentRouteName == null || currentRouteName.isEmpty) {
      return visibleTargets;
    }

    final routeMatched = <CockpitTarget>[];
    final otherRouteTargets = <CockpitTarget>[];
    for (final target in visibleTargets) {
      if (target.routeName == currentRouteName) {
        routeMatched.add(target);
      } else {
        otherRouteTargets.add(target);
      }
    }
    if (routeMatched.isNotEmpty) {
      // Discovery only surfaces targets whose enclosing route is current in
      // its own navigator, so other route names belong to nested navigators
      // that are co-visible with the host route. Keep them addressable while
      // preferring host-route matches during resolution.
      if (otherRouteTargets.isEmpty) {
        return routeMatched;
      }
      return <CockpitTarget>[...routeMatched, ...otherRouteTargets];
    }
    if (!allowRouteFallback) {
      return const <CockpitTarget>[];
    }

    final unresolvedRouteTargets = visibleTargets
        .where((target) => _isUnresolvedRouteTarget(target.routeName))
        .toList(growable: false);
    if (unresolvedRouteTargets.isNotEmpty) {
      return unresolvedRouteTargets;
    }

    return visibleTargets;
  }

  Map<String, int> _routeCounts(Iterable<CockpitTarget> targets) {
    final counts = <String, int>{};
    for (final target in targets) {
      final route = target.routeName.isEmpty ? '<empty>' : target.routeName;
      counts[route] = (counts[route] ?? 0) + 1;
    }
    return counts;
  }

  bool _isUnresolvedRouteTarget(String routeName) {
    return routeName.isEmpty || routeName == '/';
  }

  List<CockpitTarget> _deduplicatedDiscoveredVisibleTargets({
    bool allowRouteFallback = true,
  }) {
    final explicitTargets = _explicitVisibleTargets(
      allowRouteFallback: allowRouteFallback,
    );
    if (explicitTargets.isEmpty) {
      return _discoveredVisibleTargets(allowRouteFallback: allowRouteFallback);
    }

    return _discoveredVisibleTargets(allowRouteFallback: allowRouteFallback)
        .where((discovered) {
          return !explicitTargets.any(
            (explicit) => _targetsOverlap(explicit, discovered),
          );
        })
        .toList(growable: false);
  }

  bool _targetsOverlap(CockpitTarget explicit, CockpitTarget discovered) {
    final explicitNode = explicit.diagnosticNodeProvider?.call();
    final discoveredNode = discovered.diagnosticNodeProvider?.call();
    if (explicitNode != null &&
        discoveredNode != null &&
        identical(explicitNode, discoveredNode)) {
      return true;
    }
    if (_sameSignal(explicit.keyValue, discovered.keyValue)) {
      return true;
    }
    if (_sameSignal(explicit.cockpitId, discovered.cockpitId)) {
      return true;
    }
    if (_sameSignal(explicit.semanticId, discovered.semanticId)) {
      return true;
    }
    if (_sameSignal(explicit.tooltip, discovered.tooltip) &&
        explicit.typeName == discovered.typeName &&
        explicit.routeName == discovered.routeName) {
      return true;
    }
    if (_sameSignal(explicit.text, discovered.text) &&
        explicit.typeName == discovered.typeName &&
        explicit.routeName == discovered.routeName) {
      return true;
    }
    return false;
  }

  bool _sameSignal(String? left, String? right) {
    return left != null &&
        right != null &&
        left.isNotEmpty &&
        right.isNotEmpty &&
        left == right;
  }

  /// Visible targets include co-visible nested-navigator routes so they stay
  /// addressable, but when a locator matches targets on the host route those
  /// must win outright instead of tying into an ambiguous-target failure.
  List<CockpitTarget> _preferCurrentRouteMatches(List<CockpitTarget> matches) {
    final currentRouteName = routeName;
    if (currentRouteName == null ||
        currentRouteName.isEmpty ||
        matches.length < 2) {
      return matches;
    }
    final routeMatched = matches
        .where((target) => target.routeName == currentRouteName)
        .toList(growable: false);
    if (routeMatched.isEmpty || routeMatched.length == matches.length) {
      return matches;
    }
    return routeMatched;
  }

  CockpitTarget? _selectPreferredMatch(
    List<CockpitTarget> matches,
    CockpitLocator locator,
  ) {
    if (matches.length < 2) {
      return matches.isEmpty ? null : matches.single;
    }

    final sorted = matches.toList(growable: false)
      ..sort((left, right) {
        final scoreCompare = _matchPriorityScore(
          right,
          locator,
        ).compareTo(_matchPriorityScore(left, locator));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return left.registrationId.compareTo(right.registrationId);
      });

    final bestScore = _matchPriorityScore(sorted.first, locator);
    final hasTie = sorted
        .skip(1)
        .any(
          (candidate) => _matchPriorityScore(candidate, locator) == bestScore,
        );
    if (hasTie || bestScore <= 0) {
      return null;
    }
    return sorted.first;
  }

  CockpitTarget? _selectIndexedMatch(
    List<CockpitTarget> matches,
    CockpitLocator locator,
  ) {
    final index = locator.index;
    if (index == null) {
      return null;
    }
    if (index < 0) {
      return null;
    }
    final ordered = _orderedMatches(matches, locator);
    if (index >= ordered.length) {
      return null;
    }
    return ordered[index];
  }

  List<CockpitTarget> _orderedMatches(
    List<CockpitTarget> matches,
    CockpitLocator locator,
  ) {
    final ordered = matches.toList(growable: false)
      ..sort((left, right) {
        final geometryCompare = _compareGeometry(left, right);
        if (geometryCompare != 0) {
          return geometryCompare;
        }

        final scoreCompare = _matchPriorityScore(
          right,
          locator,
        ).compareTo(_matchPriorityScore(left, locator));
        if (scoreCompare != 0) {
          return scoreCompare;
        }

        return left.registrationId.compareTo(right.registrationId);
      });
    return ordered;
  }

  int _compareGeometry(CockpitTarget left, CockpitTarget right) {
    final leftGeometry = left.geometryProvider?.call();
    final rightGeometry = right.geometryProvider?.call();
    if (leftGeometry == null || rightGeometry == null) {
      if (leftGeometry == null && rightGeometry == null) {
        return 0;
      }
      return leftGeometry == null ? 1 : -1;
    }

    final topCompare = leftGeometry.top.compareTo(rightGeometry.top);
    if (topCompare != 0) {
      return topCompare;
    }
    final leftCompare = leftGeometry.left.compareTo(rightGeometry.left);
    if (leftCompare != 0) {
      return leftCompare;
    }
    final areaCompare = _geometryArea(
      leftGeometry,
    ).compareTo(_geometryArea(rightGeometry));
    if (areaCompare != 0) {
      return areaCompare;
    }
    return 0;
  }

  double _geometryArea(CockpitTargetGeometry geometry) {
    return geometry.width * geometry.height;
  }

  int _matchPriorityScore(CockpitTarget target, CockpitLocator locator) {
    var score = 0;
    final textSignal = locator.signalMap[CockpitLocatorKind.text.name];
    if (textSignal != null) {
      score += _textMatchPriorityScore(target, textSignal, locator.matchMode);
    }
    final tooltipSignal = locator.signalMap[CockpitLocatorKind.tooltip.name];
    if (tooltipSignal != null) {
      score += _textSignalPriorityScore(
        target.tooltip,
        tooltipSignal,
        locator.matchMode,
        sourceScore: 20,
      );
    }
    final semanticIdSignal =
        locator.signalMap[CockpitLocatorKind.semanticId.name];
    if (semanticIdSignal != null) {
      score += _textSignalPriorityScore(
        target.semanticId,
        semanticIdSignal,
        locator.matchMode,
        sourceScore: 24,
      );
    }
    final pathSignal = locator.signalMap[CockpitLocatorKind.path.name];
    if (pathSignal != null) {
      score += _pathMatchPriorityScore(target.path, pathSignal);
    }
    final registrationIdSignal =
        locator.signalMap[CockpitLocatorKind.registrationId.name];
    if (registrationIdSignal != null &&
        target.registrationId == registrationIdSignal) {
      score += 40;
    }
    if (target.supportedCommands.isNotEmpty) {
      score += 8;
    }
    if (target.keyValue != null && target.keyValue!.isNotEmpty) {
      score += 4;
    }
    if (target.cockpitId != null && target.cockpitId!.isNotEmpty) {
      score += 3;
    }
    if (target.semanticId != null && target.semanticId!.isNotEmpty) {
      score += 2;
    }
    if (target.text != null && target.text!.isNotEmpty) {
      score += 1;
    }
    score += locator.signalMap.length * 2;
    return score;
  }

  bool _matchesAncestorChain(
    List<CockpitSnapshotAncestor> ancestors,
    CockpitLocator locator,
  ) {
    for (var index = 0; index < ancestors.length; index += 1) {
      if (!_matchesAncestor(ancestors[index], locator)) {
        continue;
      }
      final nested = locator.ancestor;
      if (nested == null) {
        return true;
      }
      if (_matchesAncestorChain(ancestors.sublist(index + 1), nested)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesAncestorScope(CockpitTarget target, CockpitLocator locator) {
    if (_matchesRouteOnlyScope(target.routeName, locator)) {
      return true;
    }
    return _matchesAncestorChain(target.locatorAncestors, locator);
  }

  bool _matchesRouteOnlyScope(String routeName, CockpitLocator locator) {
    final routeSignal = locator.signalMap[CockpitLocatorKind.route.name];
    return routeSignal != null &&
        routeSignal == routeName &&
        locator.signalMap.length == 1 &&
        locator.ancestor == null;
  }

  bool _matchesAncestor(
    CockpitSnapshotAncestor ancestor,
    CockpitLocator locator,
  ) {
    for (final signal in locator.signals) {
      final matched = switch (signal.kind) {
        CockpitLocatorKind.cockpitId => ancestor.cockpitId == signal.value,
        CockpitLocatorKind.semanticId =>
          _matchesTextSignal(
                ancestor.semanticId,
                signal.value,
                locator.matchMode,
              ) ||
              _matchesTextSignal(
                ancestor.cockpitId,
                signal.value,
                locator.matchMode,
              ),
        CockpitLocatorKind.key =>
          ancestor.keyValue == signal.value ||
              ancestor.cockpitId == signal.value,
        CockpitLocatorKind.text =>
          _matchesTextSignal(
                ancestor.textPreview,
                signal.value,
                locator.matchMode,
              ) ||
              _matchesTextSignal(
                ancestor.tooltip,
                signal.value,
                locator.matchMode,
              ),
        CockpitLocatorKind.tooltip => _matchesTextSignal(
          ancestor.tooltip,
          signal.value,
          locator.matchMode,
        ),
        CockpitLocatorKind.type => _matchesTypeSignal(
          ancestor.typeName,
          signal.value,
        ),
        CockpitLocatorKind.route => ancestor.routeName == signal.value,
        CockpitLocatorKind.path => _matchesPath(ancestor.path, signal.value),
        CockpitLocatorKind.registrationId ||
        CockpitLocatorKind.nativeId ||
        CockpitLocatorKind.testId ||
        CockpitLocatorKind.role ||
        CockpitLocatorKind.coordinate ||
        CockpitLocatorKind.visual => false,
      };
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  bool _matchesPath(String? candidate, String expected) {
    final normalizedCandidate = _normalizePath(candidate);
    final normalizedExpected = _normalizePath(expected);
    if (normalizedCandidate == null || normalizedExpected == null) {
      return false;
    }
    return normalizedCandidate == normalizedExpected ||
        normalizedCandidate.endsWith(normalizedExpected) ||
        _isPathSubsequence(
          _pathSegments(normalizedCandidate),
          _pathSegments(normalizedExpected),
        );
  }

  String? _normalizePath(String? value) {
    final segments = _pathSegments(value);
    if (segments.isEmpty) {
      return null;
    }
    return '/${segments.join('/')}';
  }

  int _pathMatchPriorityScore(String? candidate, String expected) {
    final normalizedCandidate = _normalizePath(candidate);
    final normalizedExpected = _normalizePath(expected);
    if (normalizedCandidate == null || normalizedExpected == null) {
      return 0;
    }
    if (normalizedCandidate == normalizedExpected) {
      return 30;
    }
    if (normalizedCandidate.endsWith(normalizedExpected)) {
      return 20;
    }
    if (_isPathSubsequence(
      _pathSegments(normalizedCandidate),
      _pathSegments(normalizedExpected),
    )) {
      return 10;
    }
    return 0;
  }

  Map<String, String> _matchedSignals(CockpitLocator locator) {
    if (locator.signalMap.length <= 1 &&
        locator.ancestor == null &&
        locator.index == null &&
        locator.matchMode == CockpitTextMatchMode.exact) {
      return const <String, String>{};
    }
    return <String, String>{
      ...locator.signalMap,
      if (locator.matchMode != CockpitTextMatchMode.exact)
        'matchMode': locator.matchMode.name,
      if (locator.index != null) 'index': '${locator.index}',
    };
  }

  List<String> _pathSegments(String? value) {
    final normalized = _normalizeText(value);
    if (normalized == null) {
      return const <String>[];
    }

    final canonical = normalized
        .replaceAll(RegExp(r'[>\[\]():\s]+'), '/')
        .replaceAll('.', '/');
    return canonical
        .split(RegExp(r'/+'))
        .map(_normalizePathSegment)
        .whereType<String>()
        .where((segment) => !_pathNoiseSegments.contains(segment))
        .toList(growable: false);
  }

  String? _normalizePathSegment(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) {
      return null;
    }
    if (RegExp(r'^\d+$').hasMatch(lower)) {
      return null;
    }
    final alphanumericOnly = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return alphanumericOnly.isEmpty ? null : alphanumericOnly;
  }

  bool _isPathSubsequence(
    List<String> candidateSegments,
    List<String> expectedSegments,
  ) {
    if (candidateSegments.isEmpty || expectedSegments.isEmpty) {
      return false;
    }
    var candidateIndex = 0;
    for (final expected in expectedSegments) {
      var found = false;
      while (candidateIndex < candidateSegments.length) {
        if (candidateSegments[candidateIndex] == expected) {
          found = true;
          candidateIndex += 1;
          break;
        }
        candidateIndex += 1;
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  static const Set<String> _pathNoiseSegments = <String>{
    'actions',
    'appbaractions',
    'body',
    'child',
    'children',
    'content',
    'destination',
    'destinations',
    'footer',
    'header',
    'items',
    'leading',
    'slivers',
    'subtitle',
    'title',
    'trailing',
  };

  int _textMatchPriorityScore(
    CockpitTarget target,
    String expected,
    CockpitTextMatchMode matchMode,
  ) {
    var bestScore = 0;
    for (final candidate in <(String?, int)>[
      (target.text, 30),
      (target.displayLabel, 20),
      (target.tooltip, 12),
    ]) {
      final score = _textSignalPriorityScore(
        candidate.$1,
        expected,
        matchMode,
        sourceScore: candidate.$2,
      );
      bestScore = bestScore < score ? score : bestScore;
    }
    return bestScore;
  }

  int _textSignalPriorityScore(
    String? candidate,
    String expected,
    CockpitTextMatchMode matchMode, {
    required int sourceScore,
  }) => candidate == null
      ? 0
      : cockpitTextMatchScore(
          candidate,
          expected,
          matchMode,
          sourceScore: sourceScore,
        );
}
