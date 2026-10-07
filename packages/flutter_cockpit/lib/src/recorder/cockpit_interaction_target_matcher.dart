import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

/// Resolves observed interactions to registered targets and builds the
/// ordered locator candidates recorded with each step.
///
/// Matching is structural: a target matches a pointer event when its
/// element's render object participates in the event's hit-test path, and a
/// text field when its element is the field's element or one of its
/// ancestors. Among the matches, the strongest signal wins — key over
/// semanticId over text over tooltip, the same precedence the registry's
/// signal scoring already encodes — with depth as the tie-break, so a keyed
/// control beats its inner text node while equally strong matches resolve
/// to the most specific (deepest) one.
abstract final class CockpitInteractionTargetMatcher {
  /// Returns the best matching visible target for [hitPath], or `null` when
  /// no target participates.
  ///
  /// Matching runs against [CockpitTargetRegistry.visibleTargets]: hidden or
  /// offscreen targets would produce candidates that cannot replay, and
  /// `visibleTargets` already merges explicitly registered and discovered
  /// targets while preferring the current route.
  static CockpitTarget? matchHitPath(
    CockpitTargetRegistry registry,
    List<RenderObject> hitPath,
  ) {
    _Match? matched;
    for (final target in registry.visibleTargets) {
      final renderObject = _renderObjectOf(target);
      if (renderObject == null) {
        continue;
      }
      final depth = hitPath.indexOf(renderObject);
      if (depth >= 0 && _isBetterMatch(target, depth, matched)) {
        matched = _Match(target, depth);
      }
    }
    return matched?.target;
  }

  /// Returns the best matching visible target whose element is [element]
  /// itself or one of its ancestors, or `null` when no target is on the
  /// ancestry chain. Used for text capture, where the tracked element is the
  /// `EditableText` and the registered description is usually an ancestor
  /// such as a `TextField`.
  static CockpitTarget? matchElementAncestry(
    CockpitTargetRegistry registry,
    Element element,
  ) {
    _Match? matched;
    for (final target in registry.visibleTargets) {
      final node = target.diagnosticNodeProvider?.call();
      if (node is! Element || !node.mounted) {
        continue;
      }
      final depth = identical(node, element)
          ? 0
          : _ancestorDepth(element, node);
      if (depth != null && _isBetterMatch(target, depth, matched)) {
        matched = _Match(target, depth);
      }
    }
    return matched?.target;
  }

  /// Builds the ordered locator candidates for [target]: key, semanticId,
  /// text, tooltip, then type — the registry's signal precedence, encoded as
  /// scores 4 down to 0. Empty or missing signals are skipped; a target with
  /// no signals yields an empty list and the step records `unresolved: true`.
  static List<CockpitLocatorCandidate> locatorCandidates(CockpitTarget target) {
    final candidates = <CockpitLocatorCandidate>[];
    void add(
      String kind,
      String? value,
      int score,
      CockpitLocator Function(String value) locator,
    ) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return;
      }
      candidates.add(
        CockpitLocatorCandidate(
          kind: kind,
          selector: CockpitSelector.format(locator(trimmed)),
          score: score,
        ),
      );
    }

    add('key', target.keyValue, 4, (value) => CockpitLocator(key: value));
    add(
      'semanticId',
      target.semanticId,
      3,
      (value) => CockpitLocator(semanticId: value),
    );
    add('text', target.text, 2, (value) => CockpitLocator(text: value));
    add(
      'tooltip',
      target.tooltip,
      1,
      (value) => CockpitLocator(tooltip: value),
    );
    add('type', target.typeName, 0, (value) => CockpitLocator(type: value));
    return candidates;
  }

  static bool _isBetterMatch(CockpitTarget target, int depth, _Match? best) {
    if (best == null) {
      return true;
    }
    final scoreDelta = _signalScore(target) - _signalScore(best.target);
    return scoreDelta > 0 || (scoreDelta == 0 && depth < best.depth);
  }

  /// Signal strength precedence mirroring the registry's own scoring.
  static int _signalScore(CockpitTarget target) {
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

  static RenderObject? _renderObjectOf(CockpitTarget target) {
    final node = target.diagnosticNodeProvider?.call();
    if (node is! Element || !node.mounted) {
      return null;
    }
    final renderObject = node.findRenderObject();
    return renderObject is RenderObject && renderObject.attached
        ? renderObject
        : null;
  }

  /// Hop count from [element] up to [ancestor], or `null` when [ancestor] is
  /// not on the chain. The direct parent is one hop: depth 0 belongs to the
  /// element itself, so an equal-signal match on the element beats every
  /// ancestor and nearer ancestors beat farther ones.
  static int? _ancestorDepth(Element element, Element ancestor) {
    int? depth;
    var hops = 1;
    element.visitAncestorElements((candidate) {
      if (identical(candidate, ancestor)) {
        depth = hops;
        return false;
      }
      hops += 1;
      return true;
    });
    return depth;
  }
}

final class _Match {
  const _Match(this.target, this.depth);

  final CockpitTarget target;
  final int depth;
}
