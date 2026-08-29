// ignore_for_file: deprecated_member_use

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../control/cockpit_command_type.dart';
import 'cockpit_discovery_policy.dart';
import 'cockpit_semantics_bridge.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_target.dart';
import 'cockpit_target_geometry_resolver.dart';
import 'cockpit_text_input_request.dart';

final class CockpitNativeTargetDiscovery {
  const CockpitNativeTargetDiscovery({
    this.policy = const CockpitDiscoveryPolicy(),
  });

  final CockpitDiscoveryPolicy policy;

  List<CockpitTarget> discover({
    required BuildContext rootContext,
    required String? routeName,
    List<CockpitTarget> explicitTargets = const <CockpitTarget>[],
    bool allowInactiveRouteFallback = false,
    bool includeClippedTargets = false,
  }) {
    final rootElement = rootContext as Element;
    final rootViewport = _viewportBoundsFor(rootElement);
    final explicitTargetsByElement = _explicitTargetsByElement(explicitTargets);
    final discoveredTargets = <CockpitTarget>[];
    final session = _DiscoverySession();
    // Route scope, offstage state, and viewport clipping are inherited values.
    // Seed them once from the root's real ancestor chain, then maintain them
    // along the DFS instead of re-walking every element's ancestors — this
    // keeps discovery O(tree) instead of O(tree × depth) on deep trees.
    final rootScope = _seedInheritedScope(
      rootElement,
      rootViewport: rootViewport,
      explicitTargetsByElement: explicitTargetsByElement,
    );

    void visit(
      Element element,
      String path,
      Element? actionableOwner,
      _InheritedDiscoveryScope scope,
    ) {
      final explicitTarget = explicitTargetsByElement[element];
      if (!element.mounted ||
          policy.ignoresSubtree(element) ||
          scope.ancestorHidden ||
          (!allowInactiveRouteFallback &&
              scope.routeScope?.isCurrent == false) ||
          _isControlTarget(explicitTarget)) {
        return;
      }

      final effectiveViewport = _marksViewportBoundary(element)
          ? _intersectViewports(scope.effectiveViewport, element)
          : scope.effectiveViewport;

      final isRenderable = _isRenderable(element);
      final targetRouteName = _effectiveDiscoveryRouteName(
        scope.routeScope,
        fallbackRouteName: routeName,
      );
      final candidate =
          explicitTarget == null &&
              isRenderable &&
              (includeClippedTargets ||
                  _overlapsClippedViewport(element, effectiveViewport))
          ? _buildTarget(
              element,
              routeName: targetRouteName,
              path: path,
              actionableOwner: actionableOwner,
              pointerBlocked: scope.pointerBlocked,
              session: session,
            )
          : null;
      final hasMeaningfulViewportExposure =
          candidate == null ||
          _hasMeaningfulClippedViewportExposure(
            element,
            effectiveViewport,
            strictVisibility:
                candidate.supportedCommands.isEmpty &&
                candidate.control == null,
          );
      final createsActionableScope =
          candidate != null &&
          hasMeaningfulViewportExposure &&
          (_hasOwnedInteraction(candidate.supportedCommands) ||
              _controlOwnsSubtree(element.widget, candidate.control));
      if (candidate != null &&
          (includeClippedTargets || hasMeaningfulViewportExposure)) {
        discoveredTargets.add(
          hasMeaningfulViewportExposure
              ? candidate
              : _copyWithVisibility(candidate, isVisible: false),
        );
      }
      if (policy.stopsTraversal(element)) {
        return;
      }

      final childScope = scope.scopeForChildren(
        element,
        effectiveViewport: effectiveViewport,
      );
      var childIndex = 0;
      element.visitChildElements((child) {
        visit(
          child,
          '$path.$childIndex',
          createsActionableScope ? element : actionableOwner,
          childScope,
        );
        childIndex += 1;
      });
    }

    visit(rootElement, 'root', null, rootScope);
    return _deduplicateDiscoveredTargets(discoveredTargets);
  }

  bool hasTarget({
    required BuildContext rootContext,
    required String? routeName,
    List<CockpitTarget> explicitTargets = const <CockpitTarget>[],
    bool allowInactiveRouteFallback = false,
  }) {
    final rootElement = rootContext as Element;
    final rootViewport = _viewportBoundsFor(rootElement);
    final explicitTargetsByElement = _explicitTargetsByElement(explicitTargets);
    var found = false;
    final session = _DiscoverySession();
    final rootScope = _seedInheritedScope(
      rootElement,
      rootViewport: rootViewport,
      explicitTargetsByElement: explicitTargetsByElement,
    );

    void visit(
      Element element,
      String path,
      Element? actionableOwner,
      _InheritedDiscoveryScope scope,
    ) {
      final explicitTarget = explicitTargetsByElement[element];
      if (found ||
          !element.mounted ||
          policy.ignoresSubtree(element) ||
          scope.ancestorHidden ||
          (!allowInactiveRouteFallback &&
              scope.routeScope?.isCurrent == false) ||
          _isControlTarget(explicitTarget)) {
        return;
      }

      final isRenderable = _isRenderable(element);
      final targetRouteName = _effectiveDiscoveryRouteName(
        scope.routeScope,
        fallbackRouteName: routeName,
      );
      final candidateRouteMatches = _matchesDiscoveryRoute(
        targetRouteName,
        routeName: routeName,
        allowInactiveRouteFallback: allowInactiveRouteFallback,
      );
      final effectiveViewport = _marksViewportBoundary(element)
          ? _intersectViewports(scope.effectiveViewport, element)
          : scope.effectiveViewport;
      final candidate =
          explicitTarget == null &&
              candidateRouteMatches &&
              isRenderable &&
              _overlapsClippedViewport(element, effectiveViewport)
          ? _buildTarget(
              element,
              routeName: targetRouteName,
              path: path,
              actionableOwner: actionableOwner,
              pointerBlocked: scope.pointerBlocked,
              session: session,
            )
          : null;
      final hasMeaningfulViewportExposure =
          candidate == null ||
          _hasMeaningfulClippedViewportExposure(
            element,
            effectiveViewport,
            strictVisibility:
                candidate.supportedCommands.isEmpty &&
                candidate.control == null,
          );
      final createsActionableScope =
          candidate != null &&
          hasMeaningfulViewportExposure &&
          (_hasOwnedInteraction(candidate.supportedCommands) ||
              _controlOwnsSubtree(element.widget, candidate.control));
      if (candidate != null && hasMeaningfulViewportExposure) {
        found = true;
        return;
      }
      if (policy.stopsTraversal(element)) {
        return;
      }

      final childScope = scope.scopeForChildren(
        element,
        effectiveViewport: effectiveViewport,
      );
      var childIndex = 0;
      element.visitChildElements((child) {
        visit(
          child,
          '$path.$childIndex',
          createsActionableScope ? element : actionableOwner,
          childScope,
        );
        childIndex += 1;
      });
    }

    visit(rootElement, 'root', null, rootScope);
    return found;
  }

  /// Discovers native action targets related to one already matched element.
  ///
  /// Ancestors are resolved along the single root-to-element chain. A
  /// descendant scan is used only when that chain owns no actionable target,
  /// avoiding a full-surface discovery for ordinary controls.
  List<CockpitTarget> discoverRelatedActionTargets({
    required BuildContext rootContext,
    required Element element,
    required String? routeName,
    required CockpitCommandType requiredCommand,
    List<CockpitTarget> explicitTargets = const <CockpitTarget>[],
    bool includeInferredInteraction = false,
  }) {
    final rootElement = rootContext as Element;
    if (!rootElement.mounted || !element.mounted) {
      return const <CockpitTarget>[];
    }

    final chain = <Element>[element];
    var reachedRoot = identical(rootElement, element);
    if (!reachedRoot) {
      element.visitAncestorElements((ancestor) {
        chain.add(ancestor);
        if (identical(ancestor, rootElement)) {
          reachedRoot = true;
          return false;
        }
        return true;
      });
    }
    if (!reachedRoot) {
      return const <CockpitTarget>[];
    }

    final explicitTargetsByElement = _explicitTargetsByElement(explicitTargets);
    final session = _DiscoverySession();
    var scope = _seedInheritedScope(
      rootElement,
      rootViewport: _viewportBoundsFor(rootElement),
      explicitTargetsByElement: explicitTargetsByElement,
    );
    Element? actionableOwner;
    final ancestorActions = <CockpitTarget>[];

    for (final candidateElement in chain.reversed) {
      final explicitTarget = explicitTargetsByElement[candidateElement];
      if (!candidateElement.mounted ||
          policy.ignoresSubtree(candidateElement) ||
          scope.ancestorHidden ||
          scope.routeScope?.isCurrent == false) {
        return const <CockpitTarget>[];
      }

      final effectiveViewport = _marksViewportBoundary(candidateElement)
          ? _intersectViewports(scope.effectiveViewport, candidateElement)
          : scope.effectiveViewport;
      final targetRouteName = _effectiveDiscoveryRouteName(
        scope.routeScope,
        fallbackRouteName: routeName,
      );
      final target =
          explicitTarget == null &&
              _isRenderable(candidateElement) &&
              _overlapsClippedViewport(candidateElement, effectiveViewport)
          ? _buildTarget(
              candidateElement,
              routeName: targetRouteName,
              path: _locatorPathForElement(candidateElement, session),
              actionableOwner: actionableOwner,
              pointerBlocked: scope.pointerBlocked,
              session: session,
              includeInferredInteraction: includeInferredInteraction,
            )
          : null;
      final exposed =
          target != null &&
          _hasMeaningfulClippedViewportExposure(
            candidateElement,
            effectiveViewport,
            strictVisibility: false,
          );
      final ownsRequestedCommand =
          target != null &&
          exposed &&
          _ownsRelatedCommand(candidateElement, target, requiredCommand);
      if (ownsRequestedCommand) {
        ancestorActions.add(target);
      }

      // Only an ancestor that owns the requested command may claim the
      // discovery scope. Gesture wrappers such as a swipe-to-delete
      // GestureDetector and the surrounding Scrollable expose other pointer
      // commands, but must not hide a descendant InkWell's long-press/tap or
      // a slider's semantic adjustment when resolving that specific action.
      if (_isControlTarget(explicitTarget) ||
          (target != null &&
              exposed &&
              (ownsRequestedCommand ||
                  _controlOwnsSubtree(
                    candidateElement.widget,
                    target.control,
                  )))) {
        actionableOwner = candidateElement;
      }
      scope = scope.scopeForChildren(
        candidateElement,
        effectiveViewport: effectiveViewport,
      );
    }

    if (ancestorActions.isNotEmpty || actionableOwner != null) {
      return _deduplicateDiscoveredTargets(ancestorActions);
    }

    final descendantTargets =
        discover(
              rootContext: element,
              routeName: routeName,
              explicitTargets: explicitTargets,
            )
            .where(
              (target) => target.supportedCommands.contains(requiredCommand),
            )
            .toList(growable: false);
    return descendantTargets;
  }

  bool _ownsRelatedCommand(
    Element element,
    CockpitTarget target,
    CockpitCommandType requiredCommand,
  ) {
    if (!target.supportedCommands.contains(requiredCommand)) {
      return false;
    }
    if (requiredCommand != CockpitCommandType.tap ||
        element.widget is! Listener) {
      return true;
    }
    final listener = element.widget as Listener;
    final hasCompleteContact =
        listener.onPointerDown != null && listener.onPointerUp != null;
    return hasCompleteContact ||
        _cupertinoSegmentControlAncestor(element) != null;
  }

  bool _matchesDiscoveryRoute(
    String? targetRouteName, {
    required String? routeName,
    required bool allowInactiveRouteFallback,
  }) {
    if (allowInactiveRouteFallback) {
      return true;
    }
    if (routeName == null || routeName.isEmpty) {
      return true;
    }
    return targetRouteName == routeName;
  }

  List<CockpitTarget> _deduplicateDiscoveredTargets(
    List<CockpitTarget> targets,
  ) {
    final deduplicated = <CockpitTarget>[];
    for (final target in targets) {
      final duplicateIndex = deduplicated.indexWhere(
        (existing) =>
            _isDuplicatePassiveTarget(existing, target) ||
            _isDuplicateCupertinoSegmentTarget(existing, target) ||
            _isDuplicateWrappedControl(existing, target),
      );
      if (duplicateIndex == -1) {
        deduplicated.add(target);
        continue;
      }
      deduplicated[duplicateIndex] = _preferredDuplicateTarget(
        deduplicated[duplicateIndex],
        target,
      );
    }
    return deduplicated;
  }

  bool _isDuplicateCupertinoSegmentTarget(
    CockpitTarget left,
    CockpitTarget right,
  ) {
    if (left.typeName != 'CupertinoSegment' ||
        right.typeName != 'CupertinoSegment' ||
        left.routeName != right.routeName ||
        !_sameNonEmptySignal(left.text, right.text)) {
      return false;
    }
    final leftControl = _cupertinoSegmentAncestor(left);
    final rightControl = _cupertinoSegmentAncestor(right);
    if (leftControl == null || rightControl == null) {
      return false;
    }
    if (leftControl.keyValue != rightControl.keyValue ||
        leftControl.path != rightControl.path) {
      return false;
    }
    final leftElement = left.diagnosticNodeProvider?.call();
    final rightElement = right.diagnosticNodeProvider?.call();
    if (leftElement is Element &&
        rightElement is Element &&
        _areRelatedElements(leftElement, rightElement)) {
      return true;
    }
    final leftGeometry = CockpitTargetGeometryResolver.maybeFromTarget(left);
    final rightGeometry = CockpitTargetGeometryResolver.maybeFromTarget(right);
    if (leftGeometry == null || rightGeometry == null) {
      return false;
    }
    final leftRect = Rect.fromLTWH(
      leftGeometry.left,
      leftGeometry.top,
      leftGeometry.width,
      leftGeometry.height,
    );
    final rightRect = Rect.fromLTWH(
      rightGeometry.left,
      rightGeometry.top,
      rightGeometry.width,
      rightGeometry.height,
    );
    final intersection = leftRect.intersect(rightRect);
    if (intersection.isEmpty) {
      return false;
    }
    final leftArea = (leftRect.width * leftRect.height).clamp(
      1.0,
      double.infinity,
    );
    final rightArea = (rightRect.width * rightRect.height).clamp(
      1.0,
      double.infinity,
    );
    final smallerArea = leftArea < rightArea ? leftArea : rightArea;
    return intersection.width * intersection.height >= smallerArea * 0.9;
  }

  bool _isDuplicateWrappedControl(CockpitTarget left, CockpitTarget right) {
    if (!_isControlTarget(left) || !_isControlTarget(right)) {
      return false;
    }
    if (left.routeName != right.routeName ||
        !_hasDuplicateControlSignal(left, right)) {
      return false;
    }
    final leftCommands = left.supportedCommands;
    final rightCommands = right.supportedCommands;
    if (!leftCommands.containsAll(rightCommands) &&
        !rightCommands.containsAll(leftCommands)) {
      return false;
    }

    final leftElement = left.diagnosticNodeProvider?.call();
    final rightElement = right.diagnosticNodeProvider?.call();
    if (leftElement is! Element ||
        rightElement is! Element ||
        !_areRelatedElements(leftElement, rightElement)) {
      return false;
    }

    final leftGeometry = CockpitTargetGeometryResolver.maybeFromTarget(left);
    final rightGeometry = CockpitTargetGeometryResolver.maybeFromTarget(right);
    if (leftGeometry == null || rightGeometry == null) {
      return false;
    }
    final leftRect = Rect.fromLTWH(
      leftGeometry.left,
      leftGeometry.top,
      leftGeometry.width,
      leftGeometry.height,
    );
    final rightRect = Rect.fromLTWH(
      rightGeometry.left,
      rightGeometry.top,
      rightGeometry.width,
      rightGeometry.height,
    );
    final intersection = leftRect.intersect(rightRect);
    if (intersection.isEmpty) {
      return false;
    }
    final leftArea = (leftRect.width * leftRect.height).clamp(
      1.0,
      double.infinity,
    );
    final rightArea = (rightRect.width * rightRect.height).clamp(
      1.0,
      double.infinity,
    );
    final smallerArea = leftArea < rightArea ? leftArea : rightArea;
    return intersection.width * intersection.height >= smallerArea * 0.9;
  }

  bool _hasDuplicateControlSignal(CockpitTarget left, CockpitTarget right) =>
      _sameNonEmptySignal(left.tooltip, right.tooltip) ||
      _sameNonEmptySignal(left.text, right.text) ||
      _sameNonEmptySignal(left.semanticId, right.semanticId) ||
      _sameNonEmptySignal(left.cockpitId, right.cockpitId);

  CockpitSnapshotAncestor? _cupertinoSegmentAncestor(CockpitTarget target) {
    for (final ancestor in target.locatorAncestors.reversed) {
      if (ancestor.typeName.startsWith('CupertinoSegmentedControl') ||
          ancestor.typeName.startsWith('CupertinoSlidingSegmentedControl')) {
        return ancestor;
      }
    }
    return null;
  }

  bool _isDuplicatePassiveTarget(CockpitTarget left, CockpitTarget right) {
    if (_isControlTarget(left) || _isControlTarget(right)) {
      return false;
    }
    if (left.routeName != right.routeName) {
      return false;
    }
    if (!_hasDuplicatePassiveSignal(left, right)) {
      return false;
    }

    final leftElement = left.diagnosticNodeProvider?.call();
    final rightElement = right.diagnosticNodeProvider?.call();
    if (leftElement is Element && rightElement is Element) {
      if (!_areRelatedElements(leftElement, rightElement)) {
        return false;
      }
    }

    final leftGeometry = CockpitTargetGeometryResolver.maybeFromTarget(left);
    final rightGeometry = CockpitTargetGeometryResolver.maybeFromTarget(right);
    if (leftGeometry == null || rightGeometry == null) {
      return true;
    }

    final leftRect = Rect.fromLTWH(
      leftGeometry.left,
      leftGeometry.top,
      leftGeometry.width,
      leftGeometry.height,
    );
    final rightRect = Rect.fromLTWH(
      rightGeometry.left,
      rightGeometry.top,
      rightGeometry.width,
      rightGeometry.height,
    );
    final intersection = leftRect.intersect(rightRect);
    if (intersection.isEmpty) {
      return false;
    }
    final overlapArea = intersection.width * intersection.height;
    final minArea = (leftRect.width * leftRect.height).clamp(
      1.0,
      double.infinity,
    );
    final rightArea = (rightRect.width * rightRect.height).clamp(
      1.0,
      double.infinity,
    );
    final requiredArea = minArea < rightArea ? minArea : rightArea;
    return overlapArea >= requiredArea * 0.9;
  }

  bool _hasDuplicatePassiveSignal(CockpitTarget left, CockpitTarget right) {
    if (_sameNonEmptySignal(left.text, right.text)) {
      return true;
    }

    if (!_sameNonEmptySignal(left.semanticId, right.semanticId)) {
      return false;
    }

    final label = left.semanticId;
    if (label == null || label.isEmpty) {
      return false;
    }

    return _isPassiveSemanticOnlyTarget(left, label) &&
        _isPassiveSemanticOnlyTarget(right, label);
  }

  bool _isPassiveSemanticOnlyTarget(CockpitTarget target, String label) {
    if (_isControlTarget(target)) {
      return false;
    }
    if (target.text != null && target.text!.isNotEmpty) {
      if (target.text != label || _isTextContentTarget(target)) {
        return false;
      }
    }
    if (target.tooltip != null && target.tooltip!.isNotEmpty) {
      return false;
    }
    if (target.cockpitId != null &&
        target.cockpitId!.isNotEmpty &&
        target.cockpitId != label) {
      return false;
    }
    return target.semanticId == label;
  }

  bool _isTextContentTarget(CockpitTarget target) {
    return switch (target.typeName) {
      'Text' || 'RichText' || 'EditableText' => true,
      _ => false,
    };
  }

  bool _sameNonEmptySignal(String? left, String? right) {
    return left != null &&
        right != null &&
        left.isNotEmpty &&
        right.isNotEmpty &&
        left == right;
  }

  bool _areRelatedElements(Element left, Element right) {
    if (identical(left, right)) {
      return true;
    }

    var related = false;
    left.visitAncestorElements((ancestor) {
      if (identical(ancestor, right)) {
        related = true;
        return false;
      }
      return true;
    });
    if (related) {
      return true;
    }

    right.visitAncestorElements((ancestor) {
      if (identical(ancestor, left)) {
        related = true;
        return false;
      }
      return true;
    });
    return related;
  }

  CockpitTarget _preferredDuplicateTarget(
    CockpitTarget existing,
    CockpitTarget candidate,
  ) {
    final existingHasKey = _hasStableKey(existing);
    final candidateHasKey = _hasStableKey(candidate);
    if (existingHasKey != candidateHasKey) {
      return existingHasKey ? existing : candidate;
    }

    final existingElement = existing.diagnosticNodeProvider?.call();
    final candidateElement = candidate.diagnosticNodeProvider?.call();
    final existingType = existing.typeName;
    final candidateType = candidate.typeName;
    final existingIsSemantics = existingType == 'Semantics';
    final candidateIsSemantics = candidateType == 'Semantics';
    if (existingIsSemantics != candidateIsSemantics) {
      return candidateIsSemantics ? existing : candidate;
    }

    if (existingElement is Element && candidateElement is Element) {
      if (_isAncestorOf(existingElement, candidateElement)) {
        return candidate;
      }
      if (_isAncestorOf(candidateElement, existingElement)) {
        return existing;
      }
    }

    final existingGeometry = CockpitTargetGeometryResolver.maybeFromTarget(
      existing,
    );
    final candidateGeometry = CockpitTargetGeometryResolver.maybeFromTarget(
      candidate,
    );
    if (existingGeometry != null && candidateGeometry != null) {
      final existingArea = existingGeometry.width * existingGeometry.height;
      final candidateArea = candidateGeometry.width * candidateGeometry.height;
      if (candidateArea < existingArea) {
        return candidate;
      }
      if (existingArea < candidateArea) {
        return existing;
      }
    }

    return existing.registrationId.compareTo(candidate.registrationId) <= 0
        ? existing
        : candidate;
  }

  bool _hasStableKey(CockpitTarget target) =>
      target.keyValue != null && target.keyValue!.isNotEmpty;

  bool _isAncestorOf(Element ancestor, Element descendant) {
    var isAncestor = false;
    descendant.visitAncestorElements((candidate) {
      if (identical(candidate, ancestor)) {
        isAncestor = true;
        return false;
      }
      return true;
    });
    return isAncestor;
  }

  Rect? _viewportBoundsFor(Element rootElement) {
    final renderObject = rootElement.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  /// Resolves the inherited offstage and viewport state for the discovery root.
  _InheritedDiscoveryScope _seedInheritedScope(
    Element rootElement, {
    required Rect? rootViewport,
    Map<Element, CockpitTarget> explicitTargetsByElement =
        const <Element, CockpitTarget>{},
  }) {
    var ancestorHidden = false;
    var pointerBlocked = false;
    _CockpitRouteScope? routeScope;
    var effectiveViewport = rootViewport;

    if (rootElement.mounted) {
      rootElement.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is Offstage && widget.offstage) {
          ancestorHidden = true;
        }
        // A registered explicit target above the discovery root covers the
        // whole discovered subtree, matching the previous per-element
        // ancestor-coverage check.
        if (_isControlTarget(explicitTargetsByElement[ancestor])) {
          ancestorHidden = true;
        }
        pointerBlocked = pointerBlocked || _blocksPointerForDescendants(widget);
        routeScope ??= _cockpitRouteScopeForWidget(widget);
        if (_marksViewportBoundary(ancestor)) {
          effectiveViewport = _intersectViewports(effectiveViewport, ancestor);
        }
        return true;
      });
    }

    return _InheritedDiscoveryScope(
      ancestorHidden: ancestorHidden,
      pointerBlocked: pointerBlocked,
      effectiveViewport: effectiveViewport,
      routeScope: routeScope,
    );
  }

  Rect? _intersectViewports(Rect? current, Element boundaryElement) {
    final viewport = _viewportBoundsFor(boundaryElement);
    if (viewport == null) {
      return current;
    }
    return current == null ? viewport : current.intersect(viewport);
  }

  CockpitTarget? _buildTarget(
    Element element, {
    required String? routeName,
    required String path,
    required Element? actionableOwner,
    required bool pointerBlocked,
    required _DiscoverySession session,
    bool includeInferredInteraction = false,
  }) {
    final resolvedSemantics = cockpitResolveSemanticsTargetInfo(element);
    final semantics = resolvedSemantics?.inheritedFromAncestor == false
        ? resolvedSemantics
        : null;
    var tapHandler = _tapHandlerForElement(element);
    var longPressHandler = _longPressHandlerForElement(element);
    var doubleTapHandler = _doubleTapHandlerForElement(element);
    var enterTextHandler = _enterTextHandlerForElement(element);
    var textInputHandler = _textInputHandlerForElement(element);
    final hoverable =
        !pointerBlocked &&
        _hoverableForElement(
          element,
          includeAncestors: includeInferredInteraction,
        );
    if (pointerBlocked) {
      tapHandler = null;
      longPressHandler = null;
      doubleTapHandler = null;
      enterTextHandler = null;
      textInputHandler = null;
    }
    final isTextInput = _editableTextStateForElement(element) != null;
    final rawDirectHandlers =
        tapHandler != null ||
        longPressHandler != null ||
        doubleTapHandler != null ||
        enterTextHandler != null ||
        textInputHandler != null;
    final control = _controlStateForElement(
      element,
      semantics: semantics,
      hasDirectHandlers: rawDirectHandlers,
      session: session,
    );
    final enabled = control?.enabled != false;
    final writable = !pointerBlocked && enabled && control?.readOnly != true;
    final activatable =
        !pointerBlocked && !(isTextInput && control?.readOnly == true);
    final increaseHandler = enabled && !pointerBlocked
        ? _sliderAdjustmentHandlerForElement(element, increase: true)
        : null;
    final decreaseHandler = enabled && !pointerBlocked
        ? _sliderAdjustmentHandlerForElement(element, increase: false)
        : null;
    final gestureTapFallback =
        enabled &&
        !pointerBlocked &&
        _supportsGestureTapFallback(element.widget);
    final gestureCommands = pointerBlocked || !includeInferredInteraction
        ? const <CockpitCommandType>{}
        : _gestureCommandsForElement(element);
    if (!enabled) {
      tapHandler = null;
      longPressHandler = null;
      doubleTapHandler = null;
    }
    if (!activatable) {
      tapHandler = null;
      longPressHandler = null;
      doubleTapHandler = null;
    }
    if (!writable) {
      enterTextHandler = null;
      textInputHandler = null;
    }
    final hasDirectHandlers =
        tapHandler != null ||
        longPressHandler != null ||
        doubleTapHandler != null ||
        enterTextHandler != null ||
        textInputHandler != null ||
        hoverable ||
        gestureCommands.isNotEmpty ||
        increaseHandler != null ||
        decreaseHandler != null ||
        gestureTapFallback;
    final supportedCommands = <CockpitCommandType>{
      if (tapHandler != null || gestureTapFallback) CockpitCommandType.tap,
      if (longPressHandler != null) CockpitCommandType.longPress,
      if (doubleTapHandler != null) CockpitCommandType.doubleTap,
      if (hoverable) CockpitCommandType.hover,
      ...gestureCommands,
      if (increaseHandler != null) CockpitCommandType.increase,
      if (decreaseHandler != null) CockpitCommandType.decrease,
      if (enterTextHandler != null || textInputHandler != null)
        CockpitCommandType.enterText,
      if (textInputHandler != null) ...<CockpitCommandType>{
        CockpitCommandType.focusTextInput,
        CockpitCommandType.setTextEditingValue,
        CockpitCommandType.sendTextInputAction,
        CockpitCommandType.copyText,
        if (writable) ...<CockpitCommandType>{
          CockpitCommandType.eraseText,
          CockpitCommandType.pasteText,
        },
      },
      if (semantics != null)
        ...semantics.supportedCommands.where(
          (command) => _controlAllowsCommand(
            command,
            enabled: enabled,
            writable: writable,
            activatable: activatable,
          ),
        ),
    };
    final typeName = _publicTypeNameForElement(element);

    if (actionableOwner != null) {
      if (pointerBlocked ||
          !_isIndependentNestedControl(
            actionableOwner.widget,
            element.widget,
            control,
          )) {
        return null;
      }
    }

    if (!hasDirectHandlers &&
        supportedCommands.isNotEmpty &&
        _shouldDeferSemanticsOnlyCandidate(element, semantics, session)) {
      return null;
    }

    if (supportedCommands.isNotEmpty || control != null) {
      final metadata = _extractInteractiveMetadata(
        element,
        semantics: semantics,
        isTextInput: isTextInput,
        session: session,
      );
      if (pointerBlocked &&
          supportedCommands.isEmpty &&
          !_hasAnyMetadata(metadata)) {
        return null;
      }
      final scrollableMetadata = _scrollableMetadataForElement(
        element,
        session,
      );
      return CockpitTarget(
        registrationId: _registrationId(
          routeName: routeName,
          path: path,
          typeName: typeName,
          bestLabel: isTextInput
              ? _inputLabelForElement(element) ?? metadata.displayLabel
              : metadata.displayLabel,
        ),
        cockpitId: _firstNonEmpty(<String?>[
          metadata.semanticId,
          metadata.keyValue,
        ]),
        semanticId: metadata.semanticId,
        keyValue: metadata.keyValue,
        text: metadata.text,
        textParts: _locatorTextParts(element, primaryText: metadata.text),
        tooltip: metadata.tooltip,
        typeName: typeName,
        path: _locatorPathForElement(element, session),
        scrollablePath: scrollableMetadata.path,
        scrollableKeyValue: scrollableMetadata.keyValue,
        scrollableTypeName: scrollableMetadata.typeName,
        routeName: routeName ?? '',
        supportedCommands: supportedCommands,
        control: control,
        locatorAncestors: _extractLocatorAncestors(
          element,
          routeName: routeName,
          session: session,
        ),
        onTap: tapHandler,
        onLongPress: longPressHandler,
        onDoubleTap: doubleTapHandler,
        onEnterText: enterTextHandler,
        onTextInput: textInputHandler,
        onSemanticTap: enabled
            ? semantics?.actionHandler(SemanticsAction.tap)
            : null,
        onSemanticLongPress: enabled
            ? semantics?.actionHandler(SemanticsAction.longPress)
            : null,
        onSemanticShowOnScreen: semantics?.actionHandler(
          SemanticsAction.showOnScreen,
        ),
        onSemanticIncrease:
            increaseHandler ??
            (enabled
                ? semantics?.actionHandler(SemanticsAction.increase)
                : null),
        onSemanticDecrease:
            decreaseHandler ??
            (enabled
                ? semantics?.actionHandler(SemanticsAction.decrease)
                : null),
        onSemanticDismiss: enabled
            ? semantics?.actionHandler(SemanticsAction.dismiss)
            : null,
        onSemanticEnterText:
            !writable ||
                semantics == null ||
                !semantics.supports(SemanticsAction.setText)
            ? null
            : (text) => semantics.performAction(SemanticsAction.setText, text),
        onSemanticTextInput:
            !writable ||
                semantics == null ||
                !semantics.supports(SemanticsAction.setText)
            ? null
            : (request) {
                final text =
                    request.text ?? (request.clearExisting ? '' : null);
                if (text != null) {
                  semantics.performAction(SemanticsAction.setText, text);
                }
              },
        diagnosticNodeProvider: () => element,
        geometryProvider: () =>
            CockpitTargetGeometryResolver.maybeFromElement(element),
      );
    }

    final metadata = _extractPassiveMetadata(
      element,
      semantics: semantics,
      session: session,
    );
    if (!_hasAnyMetadata(metadata)) {
      return null;
    }
    if (_shouldDeferPassiveCandidate(element, semantics, session)) {
      return null;
    }

    final scrollableMetadata = _scrollableMetadataForElement(element, session);
    return CockpitTarget(
      registrationId: _registrationId(
        routeName: routeName,
        path: path,
        typeName: typeName,
        bestLabel: metadata.displayLabel,
      ),
      cockpitId: _firstNonEmpty(<String?>[
        metadata.semanticId,
        metadata.keyValue,
      ]),
      semanticId: metadata.semanticId,
      keyValue: metadata.keyValue,
      text: metadata.text,
      tooltip: metadata.tooltip,
      typeName: typeName,
      path: _locatorPathForElement(element, session),
      scrollablePath: scrollableMetadata.path,
      scrollableKeyValue: scrollableMetadata.keyValue,
      scrollableTypeName: scrollableMetadata.typeName,
      routeName: routeName ?? '',
      locatorAncestors: _extractLocatorAncestors(
        element,
        routeName: routeName,
        session: session,
      ),
      diagnosticNodeProvider: () => element,
      geometryProvider: () =>
          CockpitTargetGeometryResolver.maybeFromElement(element),
    );
  }

  CockpitTarget _copyWithVisibility(
    CockpitTarget target, {
    required bool isVisible,
  }) {
    return CockpitTarget(
      registrationId: target.registrationId,
      cockpitId: target.cockpitId,
      semanticId: target.semanticId,
      keyValue: target.keyValue,
      text: target.text,
      textParts: target.textParts,
      tooltip: target.tooltip,
      typeName: target.typeName,
      path: target.path,
      scrollablePath: target.scrollablePath,
      scrollableKeyValue: target.scrollableKeyValue,
      scrollableTypeName: target.scrollableTypeName,
      routeName: target.routeName,
      isVisible: isVisible,
      supportedCommands: target.supportedCommands,
      control: target.control,
      locatorAncestors: target.locatorAncestors,
      onTap: target.onTap,
      onLongPress: target.onLongPress,
      onDoubleTap: target.onDoubleTap,
      onEnterText: target.onEnterText,
      onTextInput: target.onTextInput,
      onSemanticTap: target.onSemanticTap,
      onSemanticLongPress: target.onSemanticLongPress,
      onSemanticEnterText: target.onSemanticEnterText,
      onSemanticTextInput: target.onSemanticTextInput,
      onSemanticShowOnScreen: target.onSemanticShowOnScreen,
      onSemanticIncrease: target.onSemanticIncrease,
      onSemanticDecrease: target.onSemanticDecrease,
      onSemanticDismiss: target.onSemanticDismiss,
      diagnosticNodeProvider: target.diagnosticNodeProvider,
      geometryProvider: target.geometryProvider,
    );
  }

  bool _isControlTarget(CockpitTarget? target) =>
      target != null &&
      (target.control != null || target.supportedCommands.isNotEmpty);

  bool _hasOwnedInteraction(Set<CockpitCommandType> commands) => commands.any(
    const <CockpitCommandType>{
      CockpitCommandType.tap,
      CockpitCommandType.hover,
      CockpitCommandType.enterText,
      CockpitCommandType.focusTextInput,
      CockpitCommandType.setTextEditingValue,
      CockpitCommandType.sendTextInputAction,
      CockpitCommandType.longPress,
      CockpitCommandType.doubleTap,
      CockpitCommandType.drag,
      CockpitCommandType.fling,
      CockpitCommandType.swipe,
      CockpitCommandType.pinchZoom,
      CockpitCommandType.rotate,
      CockpitCommandType.panZoom,
      CockpitCommandType.multiTouch,
      CockpitCommandType.wheel,
      CockpitCommandType.increase,
      CockpitCommandType.decrease,
      CockpitCommandType.dismiss,
    }.contains,
  );

  bool _controlOwnsSubtree(Widget widget, CockpitControlState? control) {
    if (control == null) return false;
    return widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is FloatingActionButton ||
        widget is ListTile ||
        widget is ActionChip ||
        widget is ChoiceChip ||
        widget is FilterChip ||
        widget is InputChip ||
        widget is Checkbox ||
        widget is CheckboxListTile ||
        widget is Switch ||
        widget is SwitchListTile ||
        widget is Radio ||
        widget is RadioListTile ||
        widget is Slider ||
        widget is RangeSlider ||
        widget is PopupMenuButton<Object?> ||
        widget is DropdownButton<Object?> ||
        widget is DropdownButtonFormField<Object?> ||
        widget is TextField ||
        widget is TextFormField ||
        widget is EditableText ||
        widget is CupertinoButton ||
        widget is CupertinoListTile ||
        widget is CupertinoCheckbox ||
        widget is CupertinoSwitch ||
        widget is CupertinoRadio<Object?> ||
        widget is CupertinoSlider ||
        widget is CupertinoTextField ||
        widget is CupertinoSearchTextField;
  }

  bool _isIndependentNestedControl(
    Widget owner,
    Widget candidate,
    CockpitControlState? control,
  ) {
    if (!_controlOwnsSubtree(candidate, control)) {
      return false;
    }
    if ((owner is IconButton || owner is FloatingActionButton) &&
        candidate is ButtonStyleButton) {
      return false;
    }
    if ((owner is TextField ||
            owner is TextFormField ||
            owner is CupertinoTextField ||
            owner is CupertinoSearchTextField) &&
        candidate is EditableText) {
      return false;
    }
    if (owner is CupertinoSearchTextField && candidate is CupertinoTextField) {
      return false;
    }
    if (owner is CheckboxListTile && candidate is Checkbox) {
      return false;
    }
    if (owner is SwitchListTile && candidate is Switch) {
      return false;
    }
    if (owner is RadioListTile && candidate is Radio) {
      return false;
    }
    if (owner is DropdownButtonFormField<Object?> &&
        candidate is DropdownButton<Object?>) {
      return false;
    }
    return true;
  }

  bool _controlAllowsCommand(
    CockpitCommandType command, {
    required bool enabled,
    required bool writable,
    required bool activatable,
  }) {
    if (!enabled && command != CockpitCommandType.showOnScreen) {
      return false;
    }
    if (!writable &&
        const <CockpitCommandType>{
          CockpitCommandType.enterText,
          CockpitCommandType.eraseText,
          CockpitCommandType.pasteText,
          CockpitCommandType.setTextEditingValue,
          CockpitCommandType.sendTextInputAction,
        }.contains(command)) {
      return false;
    }
    if (!activatable &&
        const <CockpitCommandType>{
          CockpitCommandType.tap,
          CockpitCommandType.longPress,
          CockpitCommandType.doubleTap,
        }.contains(command)) {
      return false;
    }
    return true;
  }

  bool _supportsGestureTapFallback(Widget widget) {
    if (widget is PopupMenuButton<Object?>) {
      return widget.enabled;
    }
    if (widget is DropdownButton<Object?>) {
      return widget.items?.isNotEmpty == true && widget.onChanged != null;
    }
    if (widget is DropdownButtonFormField<Object?>) {
      return widget.enabled;
    }
    return false;
  }

  CockpitSemanticActionHandler? _sliderAdjustmentHandlerForElement(
    Element element, {
    required bool increase,
  }) {
    // A Semantics container is often the stable locator while the actual
    // Slider is its child. Resolve that public control without requiring an
    // application key on the Slider itself; this keeps increase/decrease
    // source-faithful and avoids depending on a merged semantics node.
    final widget = _sliderWidgetForElement(element);
    if (widget is Slider && widget.onChanged != null) {
      return () {
        final current = widget.value;
        final range = widget.max - widget.min;
        final unit = widget.divisions == null
            ? range * _materialSliderAdjustmentFraction()
            : range / widget.divisions!;
        final next = (current + (increase ? unit : -unit))
            .clamp(widget.min, widget.max)
            .toDouble();
        if (next == current) return;
        widget.onChangeStart?.call(current);
        widget.onChanged!.call(next);
        widget.onChangeEnd?.call(next);
      };
    }
    if (widget is CupertinoSlider && widget.onChanged != null) {
      return () {
        final current = widget.value;
        final range = widget.max - widget.min;
        final unit = widget.divisions == null
            ? range * 0.1
            : range / widget.divisions!;
        final next = (current + (increase ? unit : -unit))
            .clamp(widget.min, widget.max)
            .toDouble();
        if (next == current) return;
        widget.onChangeStart?.call(current);
        widget.onChanged!.call(next);
        widget.onChangeEnd?.call(next);
      };
    }
    return null;
  }

  Widget? _sliderWidgetForElement(Element element) {
    final widget = element.widget;
    if (widget is Slider || widget is CupertinoSlider) {
      return widget;
    }
    if (widget is! Semantics) {
      return null;
    }
    var current = element;
    for (var depth = 0; depth < 32; depth += 1) {
      final children = <Element>[];
      current.visitChildElements((child) {
        if (child.mounted) {
          children.add(child);
        }
      });
      // A Semantics wrapper may add framework-only single-child layers around
      // its real control. Once the chain branches, the semantics node covers
      // a composite surface and must not borrow an arbitrary descendant
      // slider's actions.
      if (children.length != 1) {
        return null;
      }
      current = children.single;
      final childWidget = current.widget;
      if (childWidget is Slider || childWidget is CupertinoSlider) {
        return childWidget;
      }
    }
    return null;
  }

  double _materialSliderAdjustmentFraction() => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 0.1,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.windows => 0.05,
  };

  CockpitControlState? _controlStateForElement(
    Element element, {
    required CockpitSemanticsTargetInfo? semantics,
    required bool hasDirectHandlers,
    required _DiscoverySession session,
  }) {
    final widget = element.widget;
    final semanticState = semantics?.control;
    final segmentState =
        _materialSegmentControlStateForElement(element) ??
        _cupertinoSegmentControlStateForElement(element);
    final delegatedState = hasDirectHandlers
        ? _blockedDescendantSelectionState(element, session)
        : null;
    final editableState = _editableTextStateForElement(element);
    CockpitControlState? directState;

    if (segmentState != null) {
      directState = segmentState;
    } else if (editableState != null) {
      final obscured = editableState.widget.obscureText;
      directState = CockpitControlState(
        enabled: _textInputEnabledForElement(element),
        focused: editableState.widget.focusNode.hasFocus,
        readOnly: editableState.widget.readOnly,
        obscured: obscured,
        value: obscured ? null : editableState.widget.controller.text,
      );
    } else if (widget is ButtonStyleButton) {
      directState = CockpitControlState(enabled: widget.enabled);
    } else if (widget is IconButton) {
      directState = CockpitControlState(
        enabled: widget.onPressed != null,
        selected: widget.isSelected,
      );
    } else if (widget is FloatingActionButton) {
      directState = CockpitControlState(enabled: widget.onPressed != null);
    } else if (widget is ListTile) {
      directState = CockpitControlState(
        enabled: widget.enabled,
        selected: widget.selected,
      );
    } else if (widget is ActionChip) {
      directState = CockpitControlState(enabled: widget.isEnabled);
    } else if (widget is ChoiceChip) {
      directState = CockpitControlState(
        enabled: widget.isEnabled,
        selected: widget.selected,
      );
    } else if (widget is FilterChip) {
      directState = CockpitControlState(
        enabled: widget.isEnabled,
        selected: widget.selected,
      );
    } else if (widget is InputChip) {
      directState = CockpitControlState(
        enabled: widget.isEnabled,
        selected: widget.selected,
      );
    } else if (widget is Checkbox) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        checked: _checkState(widget.value),
      );
    } else if (widget is CheckboxListTile) {
      directState = CockpitControlState(
        enabled: (widget.enabled ?? true) && widget.onChanged != null,
        selected: widget.selected,
        checked: _checkState(widget.value),
      );
    } else if (widget is Switch) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        checked: widget.value ? CockpitCheckState.on : CockpitCheckState.off,
      );
    } else if (widget is SwitchListTile) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        checked: widget.value ? CockpitCheckState.on : CockpitCheckState.off,
      );
    } else if (widget is CupertinoCheckbox) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        checked: _checkState(widget.value),
      );
    } else if (widget is CupertinoSwitch) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        checked: widget.value ? CockpitCheckState.on : CockpitCheckState.off,
      );
    } else if (widget is Radio ||
        widget is RadioListTile ||
        widget is CupertinoRadio) {
      directState = _radioControlState(widget, semanticState);
    } else if (widget is Slider) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        value: widget.value,
      );
    } else if (widget is RangeSlider) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        value: <double>[widget.values.start, widget.values.end],
      );
    } else if (widget is CupertinoSlider) {
      directState = CockpitControlState(
        enabled: widget.onChanged != null,
        value: widget.value,
      );
    } else if (widget is PopupMenuButton<Object?>) {
      directState = CockpitControlState(enabled: widget.enabled);
    } else if (widget is DropdownButton<Object?>) {
      directState = CockpitControlState(
        enabled: widget.items?.isNotEmpty == true && widget.onChanged != null,
        value: _jsonSafeControlValue(widget.value),
      );
    } else if (widget is DropdownButtonFormField<Object?>) {
      directState = CockpitControlState(
        enabled: widget.enabled,
        value: _jsonSafeControlValue(widget.initialValue),
      );
    } else if (widget is CupertinoButton) {
      directState = CockpitControlState(enabled: widget.enabled);
    } else if (widget is CupertinoListTile) {
      directState = CockpitControlState(enabled: widget.onTap != null);
    } else if (delegatedState != null) {
      directState = delegatedState;
    } else if (hasDirectHandlers || policy.matchesInteractiveWidget(element)) {
      directState = const CockpitControlState();
    }

    if (directState == null) {
      return semanticState;
    }
    if (semanticState == null) {
      return directState;
    }
    final obscured = directState.obscured || semanticState.obscured;
    return CockpitControlState(
      enabled: directState.enabled,
      selected: directState.selected ?? semanticState.selected,
      checked: directState.checked ?? semanticState.checked,
      focused: directState.focused || semanticState.focused,
      readOnly: directState.readOnly || semanticState.readOnly,
      obscured: obscured,
      value: obscured ? null : directState.value ?? semanticState.value,
    );
  }

  CockpitControlState? _blockedDescendantSelectionState(
    Element element,
    _DiscoverySession session,
  ) {
    var summary = const _DelegatedSelectionSummary();
    element.visitChildElements((child) {
      if (summary.ambiguous) {
        return;
      }
      summary = summary.merge(
        _delegatedSelectionSummary(
          child,
          pointerBlocked: false,
          session: session,
        ),
      );
    });
    return summary.ambiguous ? null : summary.state;
  }

  _DelegatedSelectionSummary _delegatedSelectionSummary(
    Element element, {
    required bool pointerBlocked,
    required _DiscoverySession session,
  }) {
    final cache = pointerBlocked
        ? session.blockedSelectionSummaries
        : session.selectionSummaries;
    final cached = cache[element];
    if (cached != null) {
      return cached;
    }
    if (!element.mounted) {
      return cache[element] = const _DelegatedSelectionSummary();
    }
    if (pointerBlocked) {
      final directState = _selectionStateFromWidget(element.widget);
      if (directState != null) {
        return cache[element] = _DelegatedSelectionSummary(state: directState);
      }
    }

    final blocksChildren =
        pointerBlocked || _blocksPointerForDescendants(element.widget);
    var summary = const _DelegatedSelectionSummary();
    element.visitChildElements((child) {
      if (summary.ambiguous) {
        return;
      }
      summary = summary.merge(
        _delegatedSelectionSummary(
          child,
          pointerBlocked: blocksChildren,
          session: session,
        ),
      );
    });
    cache[element] = summary;
    return summary;
  }

  CockpitControlState? _selectionStateFromWidget(Widget widget) {
    if (widget is Checkbox) {
      return CockpitControlState(checked: _checkState(widget.value));
    }
    if (widget is CheckboxListTile) {
      return CockpitControlState(
        selected: widget.selected,
        checked: _checkState(widget.value),
      );
    }
    if (widget is Switch) {
      return CockpitControlState(
        checked: widget.value ? CockpitCheckState.on : CockpitCheckState.off,
      );
    }
    if (widget is SwitchListTile) {
      return CockpitControlState(
        selected: widget.selected,
        checked: widget.value ? CockpitCheckState.on : CockpitCheckState.off,
      );
    }
    if (widget is CupertinoCheckbox) {
      return CockpitControlState(checked: _checkState(widget.value));
    }
    if (widget is CupertinoSwitch) {
      return CockpitControlState(
        checked: widget.value ? CockpitCheckState.on : CockpitCheckState.off,
      );
    }
    if (widget is Radio ||
        widget is RadioListTile ||
        widget is CupertinoRadio) {
      return _radioControlState(widget, null);
    }
    return null;
  }

  CockpitControlState? _materialSegmentControlStateForElement(Element element) {
    final control = _materialSegmentControlAncestor(element);
    if (control == null) return null;
    final widget = control.widget;
    if (widget is! SegmentedButton) return null;
    final matches = widget.segments
        .where(
          (segment) =>
              (segment.label != null &&
                  _elementContainsWidget(element, segment.label!)) ||
              (segment.icon != null &&
                  _elementContainsWidget(element, segment.icon!)),
        )
        .toList(growable: false);
    if (matches.length != 1) return null;
    final segment = matches.single;
    final onSelectionChanged =
        (widget as dynamic).onSelectionChanged as Function?;
    return CockpitControlState(
      enabled: onSelectionChanged != null && segment.enabled,
      selected: widget.selected.contains(segment.value),
      value: _jsonSafeControlValue(segment.value),
    );
  }

  CockpitControlState? _cupertinoSegmentControlStateForElement(
    Element element,
  ) {
    final control = _cupertinoSegmentControlAncestor(element);
    if (control == null) return null;
    final widget = control.widget;
    final children = switch (widget) {
      CupertinoSegmentedControl(:final children) => children,
      CupertinoSlidingSegmentedControl(:final children) => children,
      _ => const <Object, Widget>{},
    };
    final matches = children.entries
        .where((entry) => _elementContainsWidget(element, entry.value))
        .toList(growable: false);
    if (matches.length != 1) return null;
    final value = matches.single.key;
    return switch (widget) {
      CupertinoSegmentedControl(:final groupValue, :final disabledChildren) =>
        CockpitControlState(
          enabled: !disabledChildren.contains(value),
          selected: groupValue == value,
          value: _jsonSafeControlValue(value),
        ),
      CupertinoSlidingSegmentedControl(
        :final groupValue,
        :final disabledChildren,
      ) =>
        CockpitControlState(
          enabled: !disabledChildren.contains(value),
          selected: groupValue == value,
          value: _jsonSafeControlValue(value),
        ),
      _ => null,
    };
  }

  CockpitControlState _radioControlState(
    Widget widget,
    CockpitControlState? semantics,
  ) {
    final (
      Object? value,
      Object? groupValue,
      Function? onChanged,
    ) = switch (widget) {
      Radio() => (
        widget.value,
        widget.groupValue,
        (widget as dynamic).onChanged as Function?,
      ),
      RadioListTile() => (
        widget.value,
        widget.groupValue,
        (widget as dynamic).onChanged as Function?,
      ),
      CupertinoRadio() => (
        widget.value,
        widget.groupValue,
        (widget as dynamic).onChanged as Function?,
      ),
      _ => (null, null, null),
    };
    return CockpitControlState(
      enabled: semantics?.enabled ?? onChanged != null,
      checked:
          semantics?.checked ??
          (groupValue == value ? CockpitCheckState.on : CockpitCheckState.off),
      value: _jsonSafeControlValue(value),
    );
  }

  CockpitCheckState _checkState(bool? value) => switch (value) {
    true => CockpitCheckState.on,
    false => CockpitCheckState.off,
    null => CockpitCheckState.mixed,
  };

  bool _textInputEnabledForElement(Element element) {
    bool? enabled;
    void read(Widget widget) {
      enabled ??= switch (widget) {
        TextField(:final enabled, :final decoration) =>
          enabled ?? decoration?.enabled ?? true,
        TextFormField() => widget.enabled,
        CupertinoTextField(:final enabled) => enabled,
        CupertinoSearchTextField(:final enabled) => enabled ?? true,
        _ => null,
      };
    }

    read(element.widget);
    if (enabled == null) {
      element.visitAncestorElements((ancestor) {
        read(ancestor.widget);
        return enabled == null;
      });
    }
    return enabled ?? true;
  }

  Object? _jsonSafeControlValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Iterable<Object?>) {
      return value.map(_jsonSafeControlValue).toList(growable: false);
    }
    return _normalizeText(value.toString());
  }

  List<CockpitSnapshotAncestor> _extractLocatorAncestors(
    Element element, {
    required String? routeName,
    required _DiscoverySession session,
  }) {
    final ancestors = <CockpitSnapshotAncestor>[];
    element.visitAncestorElements((ancestor) {
      if (_shouldSkipAncestorElementForLocator(ancestor)) {
        return true;
      }
      final semanticId = _semanticIdForElement(ancestor, session);
      final keyValue = _keyValueForElement(ancestor);
      final tooltip = _tooltipForElement(ancestor, session);
      final textPreview = _firstNonEmpty(<String?>[
        _passiveTextForElement(ancestor),
        tooltip,
      ]);
      final hasStableScopeSignal = <String?>[
        semanticId,
        keyValue,
        tooltip,
        textPreview,
      ].any((value) => value != null);
      if (!hasStableScopeSignal && _shouldSkipPathElement(ancestor)) {
        return true;
      }
      ancestors.add(
        CockpitSnapshotAncestor(
          typeName: ancestor.widget.runtimeType.toString(),
          cockpitId: _firstNonEmpty(<String?>[semanticId, keyValue]),
          semanticId: semanticId,
          keyValue: keyValue,
          textPreview: textPreview,
          tooltip: tooltip,
          routeName: routeName,
          path: _locatorPathForElement(ancestor, session),
        ),
      );
      return true;
    });
    return List<CockpitSnapshotAncestor>.unmodifiable(ancestors);
  }

  bool _shouldSkipAncestorElementForLocator(Element ancestor) {
    final typeName = ancestor.widget.runtimeType.toString();
    if (typeName.startsWith('_')) {
      return true;
    }
    return ancestor.widget is InheritedWidget ||
        ancestor.widget is ParentDataWidget<ParentData> ||
        ancestor.widget is Focus ||
        ancestor.widget is Semantics ||
        ancestor.widget is Listener ||
        ancestor.widget is GestureDetector ||
        ancestor.widget is IgnorePointer ||
        ancestor.widget is MouseRegion ||
        ancestor.widget is ExcludeSemantics ||
        ancestor.widget is MergeSemantics;
  }

  String _locatorPathForElement(Element element, _DiscoverySession session) {
    final cached = session.locatorPaths[element];
    if (cached != null) {
      return cached;
    }
    final segments = _pathNodeForElement(element, session).toSegments();
    final trimmedSegments = _trimMeaningfulPathSegments(segments);
    String result;
    if (trimmedSegments.isEmpty) {
      final fallback = _locatorPathSegment(
        element.widget.runtimeType.toString(),
      );
      result = fallback == null ? '/target' : '/$fallback';
    } else {
      result = '/${trimmedSegments.join('/')}';
    }
    session.locatorPaths[element] = result;
    return result;
  }

  /// Resolves the root→element locator segments as a shared parent-linked
  /// chain, computing each element's contribution at most once per discovery.
  _LocatorPathNode _pathNodeForElement(
    Element element,
    _DiscoverySession session,
  ) {
    final cached = session.pathNodes[element];
    if (cached != null) {
      return cached;
    }
    final pendingChain = <Element>[element];
    var base = _LocatorPathNode.root;
    element.visitAncestorElements((ancestor) {
      final hit = session.pathNodes[ancestor];
      if (hit != null) {
        base = hit;
        return false;
      }
      pendingChain.add(ancestor);
      return true;
    });
    var node = base;
    for (final candidate in pendingChain.reversed) {
      if (!_shouldSkipPathElement(candidate)) {
        final segment = _locatorPathSegment(
          candidate.widget.runtimeType.toString(),
        );
        if (segment != null) {
          node = _LocatorPathNode(node, segment);
        }
      }
      session.pathNodes[candidate] = node;
    }
    return node;
  }

  String? _locatorPathSegment(String typeName) {
    if (typeName.startsWith('_')) {
      return null;
    }
    final slug = _slugify(typeName).replaceAll('-', '');
    return slug.isEmpty ? null : slug;
  }

  bool _shouldSkipPathElement(Element element) {
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    if (typeName.startsWith('_')) {
      return true;
    }
    if (_isNoisyPathTypeName(typeName)) {
      return true;
    }
    return widget is InheritedWidget ||
        widget is ParentDataWidget<ParentData> ||
        widget is Focus ||
        widget is Listener ||
        widget is IgnorePointer ||
        widget is MouseRegion ||
        widget is ExcludeSemantics ||
        widget is MergeSemantics ||
        widget is Padding ||
        widget is Align ||
        widget is Center ||
        widget is Expanded ||
        widget is Flexible ||
        widget is SizedBox ||
        widget is ColoredBox ||
        widget is DecoratedBox ||
        widget is ConstrainedBox ||
        widget is DefaultTextStyle ||
        widget is MediaQuery ||
        widget is Builder ||
        widget is RepaintBoundary ||
        widget is KeepAlive ||
        widget is AutomaticKeepAlive ||
        widget is Row ||
        widget is Column ||
        widget is Stack ||
        widget is Positioned ||
        widget is IconTheme ||
        widget is Scrollable;
  }

  _ScrollableLocatorMetadata _scrollableMetadataForElement(
    Element element,
    _DiscoverySession session,
  ) {
    final scrollable = _nearestScrollableElement(element);
    if (scrollable == null) {
      return const _ScrollableLocatorMetadata();
    }
    return _ScrollableLocatorMetadata(
      path: _locatorPathForElement(scrollable, session),
      keyValue: _scrollableKeyValue(scrollable),
      typeName: _scrollableTypeName(scrollable, session),
    );
  }

  String _scrollableTypeName(Element element, _DiscoverySession session) {
    final ownType = element.widget.runtimeType.toString();
    if (ownType != 'Scrollable') {
      return ownType;
    }
    final pathHint = _scrollableTypeNameFromPath(
      _locatorPathForElement(element, session),
    );
    return pathHint ?? ownType;
  }

  String? _scrollableTypeNameFromPath(String? path) {
    final segments = _pathSegments(path);
    if (segments.isEmpty) {
      return null;
    }
    return switch (segments.last) {
      'customscrollview' => 'CustomScrollView',
      'gridview' => 'GridView',
      'listview' => 'ListView',
      'pageview' => 'PageView',
      'reorderablelistview' => 'ReorderableListView',
      'singlechildscrollview' => 'SingleChildScrollView',
      'tabbarview' => 'TabBarView',
      _ => null,
    };
  }

  Element? _nearestScrollableElement(Element element) {
    if (_marksViewportBoundary(element)) {
      return element;
    }

    Element? scrollable;
    element.visitAncestorElements((ancestor) {
      if (_marksViewportBoundary(ancestor)) {
        scrollable = ancestor;
        return false;
      }
      return true;
    });
    return scrollable;
  }

  String? _scrollableKeyValue(Element element) {
    final ownKey = _keyValueForElement(element);
    if (ownKey != null && ownKey.isNotEmpty) {
      return ownKey;
    }

    String? ancestorKey;
    element.visitAncestorElements((ancestor) {
      ancestorKey = _keyValueForElement(ancestor);
      return ancestorKey == null || ancestorKey!.isEmpty;
    });
    return ancestorKey;
  }

  List<String> _trimMeaningfulPathSegments(List<String> segments) {
    if (segments.isEmpty) {
      return segments;
    }
    final scaffoldIndex = segments.lastIndexOf('scaffold');
    if (scaffoldIndex >= 0) {
      return segments.sublist(scaffoldIndex);
    }
    final screenIndex = segments.lastIndexWhere(
      (segment) =>
          segment.endsWith('screen') ||
          segment.endsWith('page') ||
          segment.endsWith('dialog') ||
          segment.endsWith('drawer'),
    );
    if (screenIndex >= 0) {
      return segments.sublist(screenIndex);
    }
    if (segments.length > 8) {
      return segments.sublist(segments.length - 8);
    }
    return segments;
  }

  bool _isNoisyPathTypeName(String typeName) {
    return _pathNoiseTypeNames.contains(typeName) ||
        _pathNoiseTypePrefixes.any(typeName.startsWith);
  }

  bool _hasAnyMetadata(_TargetMetadata metadata) {
    return <String?>[
      metadata.text,
      metadata.keyValue,
      metadata.semanticId,
      metadata.tooltip,
    ].any((value) => value != null && value.isNotEmpty);
  }

  bool _isRenderable(Element element) {
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderObject || !renderObject.attached) {
      return false;
    }
    if (renderObject is RenderBox) {
      if (!renderObject.hasSize) {
        return false;
      }
      final size = renderObject.size;
      return size.width > 0 && size.height > 0;
    }
    return true;
  }

  bool _overlapsClippedViewport(Element element, Rect? effectiveViewport) {
    if (effectiveViewport == null) {
      return true;
    }
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    final bounds = origin & renderObject.size;
    return bounds.overlaps(effectiveViewport);
  }

  bool _hasMeaningfulClippedViewportExposure(
    Element element,
    Rect? effectiveViewport, {
    required bool strictVisibility,
  }) {
    if (effectiveViewport == null) {
      return true;
    }
    final renderObject = element.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    final bounds = origin & renderObject.size;
    if (!bounds.overlaps(effectiveViewport)) {
      return false;
    }
    final intersection = bounds.intersect(effectiveViewport);
    if (intersection.isEmpty) {
      return false;
    }
    final widthRatio = intersection.width / bounds.width;
    final heightRatio = intersection.height / bounds.height;
    final requiredHeightRatio = strictVisibility ? 0.8 : 0.5;
    return widthRatio >= 0.5 && heightRatio >= requiredHeightRatio;
  }

  bool _marksViewportBoundary(Element element) {
    return (element is StatefulElement && element.state is ScrollableState) ||
        policy.marksScrollableBoundary(element);
  }

  Map<Element, CockpitTarget> _explicitTargetsByElement(
    List<CockpitTarget> explicitTargets,
  ) {
    final targetsByElement = Map<Element, CockpitTarget>.identity();
    for (final target in explicitTargets) {
      final element = target.diagnosticNodeProvider?.call();
      if (element is Element) {
        targetsByElement[element] = target;
      }
    }
    return targetsByElement;
  }

  bool _shouldDeferSemanticsOnlyCandidate(
    Element element,
    CockpitSemanticsTargetInfo? semantics,
    _DiscoverySession session,
  ) {
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    if (typeName.startsWith('_')) {
      return true;
    }
    if (widget is Semantics && _keyValueForElement(element) == null) {
      return true;
    }
    if (widget is Dismissible ||
        widget is Listener && !_widgetHandlesHover(widget) ||
        widget is MouseRegion && !_widgetHandlesHover(widget) ||
        widget is IgnorePointer ||
        widget is ExcludeSemantics ||
        widget is MergeSemantics ||
        widget is InheritedWidget ||
        widget is ParentDataWidget<ParentData> ||
        widget is Focus) {
      return true;
    }
    if (policy.matchesInteractiveWidget(element)) {
      return false;
    }
    if (_ownsSupportedSemanticsActions(widget, semantics)) {
      return false;
    }
    // RadioGroup-managed radios expose activation only through semantics, so
    // keep the public widget addressable instead of deferring to internals.
    if (widget is Radio || widget is RadioListTile) {
      return false;
    }

    final localKey = _keyValueForElement(element);
    final localSemanticId = _semanticIdForElement(element, session);
    final localTooltip = _tooltipForElement(element, session);
    final localText = _passiveTextForElement(element);
    if ((widget is StatelessWidget || widget is StatefulWidget) &&
        localKey != null &&
        localSemanticId == null &&
        localTooltip == null &&
        localText == null) {
      return true;
    }

    final selfSignals = <String?>[
      localKey,
      localSemanticId,
      localTooltip,
      localText,
    ].where((value) => value != null && value.isNotEmpty);

    return selfSignals.isEmpty;
  }

  bool _ownsSupportedSemanticsActions(
    Widget widget,
    CockpitSemanticsTargetInfo? semantics,
  ) {
    if (semantics == null) {
      return false;
    }
    if (widget is Slider ||
        widget is RangeSlider ||
        widget is CupertinoSlider) {
      return semantics.supports(SemanticsAction.increase) ||
          semantics.supports(SemanticsAction.decrease);
    }
    if (widget is PopupMenuButton<Object?> ||
        widget is DropdownButton<Object?> ||
        widget is DropdownButtonFormField<Object?>) {
      return semantics.supports(SemanticsAction.tap);
    }
    return false;
  }

  bool _shouldDeferPassiveCandidate(
    Element element,
    CockpitSemanticsTargetInfo? semantics,
    _DiscoverySession session,
  ) {
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    if (typeName.startsWith('_') || _isFrameworkMirroredKeyedSubtree(widget)) {
      return true;
    }
    if (widget is InheritedWidget ||
        widget is ParentDataWidget<ParentData> ||
        widget is Focus ||
        widget is Listener && !_widgetHandlesHover(widget) ||
        widget is IgnorePointer ||
        widget is MouseRegion && !_widgetHandlesHover(widget) ||
        widget is ExcludeSemantics ||
        widget is MergeSemantics) {
      return true;
    }

    final localSignals = <String?>[
      _keyValueForElement(element),
      _semanticIdForElement(element, session),
      _tooltipForElement(element, session),
      _passiveTextForElement(element),
    ].where((value) => value != null && value.isNotEmpty);
    if (localSignals.isNotEmpty) {
      return false;
    }

    return semantics != null;
  }

  bool _isFrameworkMirroredKeyedSubtree(Widget widget) {
    if (widget is! KeyedSubtree) {
      return false;
    }
    final key = widget.key;
    return key is ValueKey<Object?> && key.value is Key;
  }

  CockpitTapHandler? _tapHandlerForElement(Element element) {
    final customHandler = policy.tapHandlerForElement?.call(element);
    if (customHandler != null) {
      return customHandler;
    }
    final cupertinoSegmentHandler = _cupertinoSegmentTapHandlerForElement(
      element,
    );
    if (cupertinoSegmentHandler != null) {
      return cupertinoSegmentHandler;
    }
    final widget = element.widget;
    if (widget is ButtonStyleButton) {
      return widget.onPressed;
    }
    if (widget is IconButton) {
      return widget.onPressed;
    }
    if (widget is FloatingActionButton) {
      return widget.onPressed;
    }
    if (widget is InkResponse) {
      return widget.onTap;
    }
    if (widget is GestureDetector) {
      return widget.onTap;
    }
    if (widget is ListTile) {
      return widget.onTap;
    }
    if (widget is ActionChip) {
      return widget.onPressed;
    }
    if (widget is CupertinoButton) {
      return widget.onPressed;
    }
    if (widget is CupertinoListTile) {
      return widget.onTap;
    }
    if (widget is ChoiceChip && widget.onSelected != null) {
      return () => widget.onSelected!.call(!widget.selected);
    }
    if (widget is FilterChip && widget.onSelected != null) {
      return () => widget.onSelected!.call(!widget.selected);
    }
    if (widget is InputChip) {
      if (widget.onPressed != null) {
        return widget.onPressed;
      }
      if (widget.onSelected != null) {
        return () => widget.onSelected!.call(!widget.selected);
      }
    }
    if (widget is Checkbox && widget.onChanged != null) {
      return () => widget.onChanged!.call(
        _nextCheckboxValue(widget.value, tristate: widget.tristate),
      );
    }
    if (widget is CheckboxListTile && widget.onChanged != null) {
      return () => widget.onChanged!.call(
        _nextCheckboxValue(widget.value, tristate: widget.tristate),
      );
    }
    if (widget is Switch && widget.onChanged != null) {
      return () => widget.onChanged!.call(!widget.value);
    }
    if (widget is SwitchListTile && widget.onChanged != null) {
      return () => widget.onChanged!.call(!widget.value);
    }
    if (widget is CupertinoCheckbox && widget.onChanged != null) {
      return () => widget.onChanged!.call(
        _nextCheckboxValue(widget.value, tristate: widget.tristate),
      );
    }
    if (widget is CupertinoSwitch && widget.onChanged != null) {
      return () => widget.onChanged!.call(!widget.value);
    }
    if (widget is Radio) {
      // Reading the generic ValueChanged<T?> through Radio<dynamic> trips
      // Dart's covariant-generics soundness check, so go through dynamic.
      return _radioTapHandler(
        onChanged: (widget as dynamic).onChanged as Function?,
        value: widget.value,
        groupValue: widget.groupValue,
        toggleable: widget.toggleable,
      );
    }
    if (widget is RadioListTile) {
      return _radioTapHandler(
        onChanged: (widget as dynamic).onChanged as Function?,
        value: widget.value,
        groupValue: widget.groupValue,
        toggleable: widget.toggleable,
      );
    }
    if (widget is CupertinoRadio) {
      return _radioTapHandler(
        onChanged: (widget as dynamic).onChanged as Function?,
        value: widget.value,
        groupValue: widget.groupValue,
        toggleable: widget.toggleable,
      );
    }
    if (widget is CupertinoButton) {
      return widget.enabled ? widget.onPressed : null;
    }
    if (widget is CupertinoListTile) {
      return widget.onTap;
    }
    final editableState = _editableTextStateForElement(element);
    if (editableState != null) {
      final state = editableState;
      return () => state.widget.focusNode.requestFocus();
    }
    return null;
  }

  bool _hoverableForElement(Element element, {bool includeAncestors = false}) {
    if (_widgetHandlesHover(element.widget)) {
      return true;
    }
    if (!includeAncestors) {
      return false;
    }
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (_widgetHandlesHover(ancestor.widget)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool _widgetHandlesHover(Widget widget) {
    if (widget is MouseRegion) {
      return widget.onEnter != null ||
          widget.onHover != null ||
          widget.onExit != null;
    }
    if (widget is Listener) {
      return widget.onPointerHover != null;
    }
    return false;
  }

  /// Infers pointer capabilities from public Flutter widget contracts.
  ///
  /// Custom controls commonly use a GestureDetector/RawGestureDetector or a
  /// Listener without Semantics or a Key. Publishing the recognizer-backed
  /// commands keeps those controls locatable and lets the executor deliver
  /// real pointer events instead of forcing coordinate guesses.
  Set<CockpitCommandType> _gestureCommandsForElement(Element element) {
    final widget = element.widget;
    final commands = <CockpitCommandType>{};

    // Scrollable handles PointerScrollEvent through its internal listener;
    // expose wheel as a real input path in addition to drag-based scrolling.
    if (widget is Scrollable) {
      commands.add(CockpitCommandType.wheel);
    }

    if (widget is GestureDetector) {
      final hasTap =
          widget.onTap != null ||
          widget.onTapDown != null ||
          widget.onTapUp != null ||
          widget.onTapMove != null ||
          widget.onTapCancel != null ||
          widget.onSecondaryTap != null ||
          widget.onSecondaryTapDown != null ||
          widget.onSecondaryTapUp != null ||
          widget.onSecondaryTapCancel != null ||
          widget.onTertiaryTapDown != null ||
          widget.onTertiaryTapUp != null ||
          widget.onTertiaryTapCancel != null;
      if (hasTap) commands.add(CockpitCommandType.tap);

      final hasDoubleTap =
          widget.onDoubleTap != null ||
          widget.onDoubleTapDown != null ||
          widget.onDoubleTapCancel != null;
      if (hasDoubleTap) commands.add(CockpitCommandType.doubleTap);

      final hasLongPress =
          widget.onLongPress != null ||
          widget.onLongPressDown != null ||
          widget.onLongPressStart != null ||
          widget.onLongPressMoveUpdate != null ||
          widget.onLongPressUp != null ||
          widget.onLongPressEnd != null ||
          widget.onLongPressCancel != null ||
          widget.onSecondaryLongPress != null ||
          widget.onTertiaryLongPress != null;
      if (hasLongPress) commands.add(CockpitCommandType.longPress);

      final hasDrag =
          widget.onPanStart != null ||
          widget.onPanUpdate != null ||
          widget.onPanEnd != null ||
          widget.onPanCancel != null ||
          widget.onHorizontalDragStart != null ||
          widget.onHorizontalDragUpdate != null ||
          widget.onHorizontalDragEnd != null ||
          widget.onHorizontalDragCancel != null ||
          widget.onVerticalDragStart != null ||
          widget.onVerticalDragUpdate != null ||
          widget.onVerticalDragEnd != null ||
          widget.onVerticalDragCancel != null;
      if (hasDrag) {
        commands.addAll(const <CockpitCommandType>{
          CockpitCommandType.drag,
          CockpitCommandType.fling,
          CockpitCommandType.swipe,
        });
      }

      final hasScale =
          widget.onScaleStart != null ||
          widget.onScaleUpdate != null ||
          widget.onScaleEnd != null;
      if (hasScale) {
        commands.addAll(const <CockpitCommandType>{
          CockpitCommandType.pinchZoom,
          CockpitCommandType.rotate,
          CockpitCommandType.panZoom,
          CockpitCommandType.multiTouch,
        });
      }
    } else if (widget is RawGestureDetector) {
      for (final type in widget.gestures.keys) {
        final name = type.toString().toLowerCase();
        if (name.contains('tap')) commands.add(CockpitCommandType.tap);
        if (name.contains('doubletap')) {
          commands.add(CockpitCommandType.doubleTap);
        }
        if (name.contains('longpress')) {
          commands.add(CockpitCommandType.longPress);
        }
        if (name.contains('drag') || name.contains('pan')) {
          commands.addAll(const <CockpitCommandType>{
            CockpitCommandType.drag,
            CockpitCommandType.fling,
            CockpitCommandType.swipe,
          });
        }
        if (name.contains('scale')) {
          commands.addAll(const <CockpitCommandType>{
            CockpitCommandType.pinchZoom,
            CockpitCommandType.rotate,
            CockpitCommandType.panZoom,
            CockpitCommandType.multiTouch,
          });
        }
      }
    } else if (widget is Listener) {
      if (widget.onPointerDown != null || widget.onPointerUp != null) {
        commands.add(CockpitCommandType.tap);
      }
      if (widget.onPointerSignal != null) {
        commands.add(CockpitCommandType.wheel);
      }
      if (widget.onPointerMove != null || widget.onPointerCancel != null) {
        commands.addAll(const <CockpitCommandType>{
          CockpitCommandType.drag,
          CockpitCommandType.fling,
          CockpitCommandType.swipe,
        });
      }
    } else if (widget is Dismissible) {
      commands.addAll(const <CockpitCommandType>{
        CockpitCommandType.drag,
        CockpitCommandType.fling,
        CockpitCommandType.swipe,
      });
    } else if (widget is LongPressDraggable) {
      commands.addAll(const <CockpitCommandType>{
        CockpitCommandType.longPress,
        CockpitCommandType.drag,
        CockpitCommandType.fling,
        CockpitCommandType.swipe,
      });
    } else if (widget is Draggable) {
      commands.addAll(const <CockpitCommandType>{
        CockpitCommandType.drag,
        CockpitCommandType.fling,
        CockpitCommandType.swipe,
      });
    } else if (widget is InteractiveViewer) {
      if (widget.panEnabled) {
        commands.addAll(const <CockpitCommandType>{
          CockpitCommandType.drag,
          CockpitCommandType.fling,
          CockpitCommandType.swipe,
          CockpitCommandType.panZoom,
        });
      }
      if (widget.scaleEnabled) {
        commands.addAll(const <CockpitCommandType>{
          CockpitCommandType.pinchZoom,
          CockpitCommandType.rotate,
          CockpitCommandType.multiTouch,
        });
      }
      if (widget.trackpadScrollCausesScale) {
        commands.add(CockpitCommandType.wheel);
      }
    }

    return commands;
  }

  CockpitTapHandler? _cupertinoSegmentTapHandlerForElement(Element element) {
    final control = _cupertinoSegmentControlAncestor(element);
    if (control == null) {
      return null;
    }
    final controlWidget = control.widget;
    final children = switch (controlWidget) {
      CupertinoSegmentedControl(:final children) => children,
      CupertinoSlidingSegmentedControl(:final children) => children,
      _ => const <Object, Widget>{},
    };
    final matches = children.entries
        .where((entry) => _elementContainsWidget(element, entry.value))
        .toList(growable: false);
    if (matches.length != 1) {
      return null;
    }
    final value = matches.single.key;
    if (controlWidget is CupertinoSegmentedControl) {
      if (controlWidget.disabledChildren.contains(value)) {
        return null;
      }
      final callback = (controlWidget as dynamic).onValueChanged as Function;
      return () {
        if (controlWidget.groupValue != value) {
          Function.apply(callback, <Object?>[value]);
        }
      };
    }
    if (controlWidget is CupertinoSlidingSegmentedControl) {
      if (controlWidget.disabledChildren.contains(value)) {
        return null;
      }
      final callback = (controlWidget as dynamic).onValueChanged as Function;
      return () {
        if (controlWidget.groupValue != value) {
          Function.apply(callback, <Object?>[value]);
        }
      };
    }
    return null;
  }

  bool _elementContainsWidget(Element element, Widget widget) {
    if (identical(element.widget, widget)) {
      return true;
    }
    var found = false;
    void visit(Element child) {
      if (found || !child.mounted) {
        return;
      }
      if (identical(child.widget, widget)) {
        found = true;
        return;
      }
      child.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return found;
  }

  bool? _nextCheckboxValue(bool? value, {required bool tristate}) {
    if (!tristate) {
      return !(value ?? false);
    }
    return switch (value) {
      false => true,
      true => null,
      null => false,
    };
  }

  CockpitTapHandler? _radioTapHandler({
    required Function? onChanged,
    required Object? value,
    required Object? groupValue,
    required bool toggleable,
  }) {
    if (onChanged == null) {
      return null;
    }
    return () {
      if (groupValue == value) {
        if (toggleable) {
          onChanged(null);
        }
        return;
      }
      onChanged(value);
    };
  }

  CockpitEnterTextHandler? _enterTextHandlerForElement(Element element) {
    final customHandler = policy.enterTextHandlerForElement?.call(element);
    if (customHandler != null) {
      return customHandler;
    }
    final textInputHandler = _textInputHandlerForElement(element);
    if (textInputHandler == null) {
      return null;
    }
    return (text) => textInputHandler(CockpitTextInputRequest(text: text));
  }

  CockpitTextInputHandler? _textInputHandlerForElement(Element element) {
    final customHandler = policy.textInputHandlerForElement?.call(element);
    if (customHandler != null) {
      return customHandler;
    }
    final editableState = _editableTextStateForElement(element);
    if (editableState == null) {
      return null;
    }

    final state = editableState;
    return (request) {
      if (request.requestFocus) {
        state.widget.focusNode.requestFocus();
      }
      final currentValue = state.widget.controller.value;
      final nextText = request.text ?? (request.clearExisting ? '' : null);
      final resolvedText = nextText ?? currentValue.text;
      final selectionBase = request.selectionBase;
      final selectionExtent = request.selectionExtent ?? selectionBase;
      final selection = selectionBase == null
          ? (request.text != null || request.clearExisting
                ? TextSelection.collapsed(offset: resolvedText.length)
                : currentValue.selection)
          : TextSelection(
              baseOffset: selectionBase.clamp(0, resolvedText.length),
              extentOffset: (selectionExtent ?? selectionBase).clamp(
                0,
                resolvedText.length,
              ),
            );
      final composingBase = request.composingBase;
      final composingExtent = request.composingExtent ?? composingBase;
      final composing = composingBase == null
          ? (request.text != null || request.clearExisting
                ? TextRange.empty
                : currentValue.composing)
          : TextRange(
              start: composingBase.clamp(0, resolvedText.length),
              end: (composingExtent ?? composingBase).clamp(
                0,
                resolvedText.length,
              ),
            );
      final shouldUpdateValue =
          request.hasEditingMutation || request.requestFocus;
      if (shouldUpdateValue) {
        final value = currentValue.copyWith(
          text: resolvedText,
          selection: selection,
          composing: composing,
        );
        state.userUpdateTextEditingValue(value, SelectionChangedCause.keyboard);
      }
      final action = request.inputAction;
      if (action != null) {
        state.performAction(_mapTextInputAction(action));
      }
    };
  }

  TextInputAction _mapTextInputAction(CockpitTextInputAction action) {
    return switch (action) {
      CockpitTextInputAction.done => TextInputAction.done,
      CockpitTextInputAction.next => TextInputAction.next,
      CockpitTextInputAction.previous => TextInputAction.previous,
      CockpitTextInputAction.search => TextInputAction.search,
      CockpitTextInputAction.send => TextInputAction.send,
      CockpitTextInputAction.go => TextInputAction.go,
      CockpitTextInputAction.newline => TextInputAction.newline,
      CockpitTextInputAction.none => TextInputAction.none,
      CockpitTextInputAction.unspecified => TextInputAction.unspecified,
      CockpitTextInputAction.continueAction => TextInputAction.continueAction,
      CockpitTextInputAction.emergencyCall => TextInputAction.emergencyCall,
      CockpitTextInputAction.join => TextInputAction.join,
      CockpitTextInputAction.route => TextInputAction.route,
    };
  }

  CockpitLongPressHandler? _longPressHandlerForElement(Element element) {
    final customHandler = policy.longPressHandlerForElement?.call(element);
    if (customHandler != null) {
      return customHandler;
    }
    final widget = element.widget;
    if (widget is InkResponse) {
      return widget.onLongPress;
    }
    if (widget is GestureDetector) {
      return widget.onLongPress;
    }
    if (widget is ListTile) {
      return widget.onLongPress;
    }
    if (widget is CupertinoButton) {
      return widget.onLongPress;
    }
    return null;
  }

  CockpitDoubleTapHandler? _doubleTapHandlerForElement(Element element) {
    final customHandler = policy.doubleTapHandlerForElement?.call(element);
    if (customHandler != null) {
      return customHandler;
    }
    final widget = element.widget;
    if (widget is InkResponse) {
      return widget.onDoubleTap;
    }
    if (widget is GestureDetector) {
      return widget.onDoubleTap;
    }
    return null;
  }

  EditableTextState? _editableTextStateForElement(Element element) {
    if (element is StatefulElement && element.state is EditableTextState) {
      return element.state as EditableTextState;
    }

    final widget = element.widget;
    if (widget is! TextField &&
        widget is! TextFormField &&
        widget is! CupertinoTextField &&
        widget is! CupertinoSearchTextField &&
        widget is! EditableText) {
      return null;
    }

    EditableTextState? editableState;

    void visit(Element candidate) {
      if (editableState != null || !candidate.mounted) {
        return;
      }
      if (candidate is StatefulElement &&
          candidate.state is EditableTextState) {
        editableState = candidate.state as EditableTextState;
        return;
      }
      candidate.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return editableState;
  }

  _TargetMetadata _extractInteractiveMetadata(
    Element element, {
    required CockpitSemanticsTargetInfo? semantics,
    required bool isTextInput,
    required _DiscoverySession session,
  }) {
    final inputLabel = _inputLabelForElement(element);
    final inputError = _inputErrorForElement(element);
    final directText = _interactiveTextForElement(element);
    final text = isTextInput && inputLabel != null
        ? _joinTextSignals(<String?>[inputLabel, inputError])
        : _firstNonEmpty(<String?>[
            policy.extractText?.call(element),
            directText,
            semantics?.label,
            semantics?.value,
            semantics?.hint,
            _passiveTextForElement(element),
            inputLabel,
          ]);
    return _TargetMetadata(
      text: text,
      keyValue: _keyValueForElement(element),
      semanticId: _firstNonEmpty(<String?>[
        semantics?.identifier,
        _semanticIdForElement(element, session),
      ]),
      tooltip: _firstNonEmpty(<String?>[
        semantics?.tooltip,
        _tooltipForElement(element, session),
      ]),
    );
  }

  _TargetMetadata _extractPassiveMetadata(
    Element element, {
    required CockpitSemanticsTargetInfo? semantics,
    required _DiscoverySession session,
  }) {
    final selfText = _passiveTextForElement(element);
    return _TargetMetadata(
      text: selfText,
      keyValue: _keyValueForElement(element),
      semanticId: _firstNonEmpty(<String?>[
        semantics?.identifier,
        _semanticIdForElement(element, session),
      ]),
      tooltip: _firstNonEmpty(<String?>[
        semantics?.tooltip,
        _tooltipForElement(element, session),
      ]),
    );
  }

  String? _interactiveTextForElement(Element element) {
    return _firstNonEmpty(<String?>[
      policy.extractText?.call(element),
      _textFromWidget(element.widget),
      _collectDescendantText(element),
      _inputLabelForElement(element),
    ]);
  }

  String? _passiveTextForElement(Element element) {
    return _firstNonEmpty(<String?>[
      policy.extractText?.call(element),
      _textFromWidget(element.widget),
      _textFromSemanticsWidget(element.widget),
      _inputLabelFromWidget(element.widget),
    ]);
  }

  String? _textFromSemanticsWidget(Widget widget) {
    if (widget is! Semantics) {
      return null;
    }
    return _firstNonEmpty(<String?>[
      _normalizeText(widget.properties.label),
      _normalizeText(widget.properties.value),
      _normalizeText(widget.properties.hint),
    ]);
  }

  String? _textFromWidget(Widget widget) {
    if (widget is Text) {
      return _normalizeReadableText(
        widget.data ?? widget.textSpan?.toPlainText(),
      );
    }
    if (widget is RichText) {
      return _normalizeReadableText(widget.text.toPlainText());
    }
    if (widget is EditableText) {
      return _normalizeReadableText(widget.controller.text);
    }
    if (widget is TextField) {
      return _normalizeReadableText(
        widget.controller?.text.isNotEmpty == true
            ? widget.controller?.text
            : widget.decoration?.labelText ?? widget.decoration?.hintText,
      );
    }
    if (widget is TextFormField) {
      final controllerText = widget.controller?.text;
      return _normalizeReadableText(
        controllerText != null && controllerText.isNotEmpty
            ? controllerText
            : widget.initialValue,
      );
    }
    if (widget is CupertinoTextField) {
      return _normalizeReadableText(
        widget.controller?.text.isNotEmpty == true
            ? widget.controller?.text
            : widget.placeholder,
      );
    }
    if (widget is CupertinoSearchTextField) {
      return _normalizeReadableText(
        widget.controller?.text.isNotEmpty == true
            ? widget.controller?.text
            : widget.placeholder ?? 'Search',
      );
    }
    return null;
  }

  String? _inputLabelForElement(Element element) {
    final selfLabel = _inputLabelFromWidget(element.widget);
    if (selfLabel != null) {
      return selfLabel;
    }
    final descendantLabel = _inputLabelFromDescendantTextField(element);
    if (descendantLabel != null) {
      return descendantLabel;
    }

    String? label;
    element.visitAncestorElements((ancestor) {
      label = _inputLabelFromWidget(ancestor.widget);
      return label == null;
    });
    return label;
  }

  String? _inputLabelFromWidget(Widget widget) {
    if (widget is TextField) {
      return _normalizeText(
        widget.decoration?.labelText ?? widget.decoration?.hintText,
      );
    }
    if (widget is CupertinoTextField) {
      return _normalizeText(widget.placeholder);
    }
    if (widget is CupertinoSearchTextField) {
      return _normalizeText(widget.placeholder ?? 'Search');
    }
    return null;
  }

  String? _inputErrorForElement(Element element) {
    final selfError = _inputErrorFromWidget(element.widget);
    if (selfError != null) return selfError;

    String? error;
    void visit(Element candidate) {
      if (error != null || !candidate.mounted) return;
      error = _inputErrorFromWidget(candidate.widget);
      if (error == null) candidate.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    if (error != null) return error;
    element.visitAncestorElements((ancestor) {
      error = _inputErrorFromWidget(ancestor.widget);
      return error == null;
    });
    return error;
  }

  String? _inputErrorFromWidget(Widget widget) {
    final errorText = switch (widget) {
      TextField(:final decoration) => decoration?.errorText,
      _ => null,
    };
    return _normalizeText(errorText);
  }

  String? _joinTextSignals(Iterable<String?> signals) {
    final normalized = signals
        .map(_normalizeText)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    return normalized.isEmpty ? null : normalized.join(' ');
  }

  String? _inputLabelFromDescendantTextField(Element element) {
    String? label;

    void visit(Element candidate) {
      if (label != null || !candidate.mounted) {
        return;
      }
      label = _inputLabelFromWidget(candidate.widget);
      if (label != null) {
        return;
      }
      candidate.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return label;
  }

  String? _stableKeyValue(Key? key) {
    final value = switch (key) {
      ValueKey<Object?>(value: final value) => _normalizeText(
        value?.toString(),
      ),
      ObjectKey(value: final value) => _normalizeText(value.toString()),
      _ => null,
    };
    if (value == null || value.startsWith('_')) {
      return null;
    }
    return value;
  }

  String? _semanticIdForElement(Element element, _DiscoverySession session) {
    if (session.semanticIds.containsKey(element)) {
      return session.semanticIds[element];
    }
    final ownValue =
        _normalizeText(policy.extractSemanticId?.call(element)) ??
        _semanticIdFromWidget(element.widget);
    if (ownValue != null) {
      session.semanticIds[element] = ownValue;
      return ownValue;
    }

    final pendingChain = <Element>[element];
    String? resolved;
    element.visitAncestorElements((ancestor) {
      if (_separatesSemanticChildren(ancestor.widget)) {
        return false;
      }
      if (session.semanticIds.containsKey(ancestor)) {
        resolved = session.semanticIds[ancestor];
        return false;
      }
      final value =
          _normalizeText(policy.extractSemanticId?.call(ancestor)) ??
          _semanticIdFromWidget(ancestor.widget);
      if (value != null) {
        resolved = value;
        session.semanticIds[ancestor] = value;
        return false;
      }
      pendingChain.add(ancestor);
      return true;
    });
    for (final pending in pendingChain) {
      session.semanticIds[pending] = resolved;
    }
    return resolved;
  }

  String? _semanticIdFromWidget(Widget widget) {
    if (widget is Semantics) {
      return _firstNonEmpty(<String?>[
        _normalizeText(widget.properties.identifier),
        _normalizeText(widget.properties.label),
        _normalizeText(widget.properties.hint),
      ]);
    }
    return null;
  }

  String? _tooltipForElement(Element element, _DiscoverySession session) {
    if (session.tooltips.containsKey(element)) {
      return session.tooltips[element];
    }
    final ownValue =
        _normalizeText(policy.extractTooltip?.call(element)) ??
        _tooltipFromWidget(element.widget);
    if (ownValue != null) {
      session.tooltips[element] = ownValue;
      return ownValue;
    }

    final pendingChain = <Element>[element];
    String? resolved;
    element.visitAncestorElements((ancestor) {
      if (_separatesSemanticChildren(ancestor.widget)) {
        return false;
      }
      if (session.tooltips.containsKey(ancestor)) {
        resolved = session.tooltips[ancestor];
        return false;
      }
      final value =
          _normalizeText(policy.extractTooltip?.call(ancestor)) ??
          _tooltipFromWidget(ancestor.widget);
      if (value != null) {
        resolved = value;
        session.tooltips[ancestor] = value;
        return false;
      }
      pendingChain.add(ancestor);
      return true;
    });
    for (final pending in pendingChain) {
      session.tooltips[pending] = resolved;
    }
    return resolved;
  }

  String? _keyValueForElement(Element element) {
    final customKey = _normalizeText(policy.extractKey?.call(element));
    if (customKey != null) {
      return customKey;
    }
    return _stableKeyValue(element.widget.key);
  }

  bool _separatesSemanticChildren(Widget widget) =>
      widget is Semantics && widget.explicitChildNodes;

  String? _tooltipFromWidget(Widget widget) {
    if (widget is Tooltip) {
      return _normalizeText(widget.message);
    }
    if (widget is Semantics) {
      return _normalizeText(widget.properties.tooltip);
    }
    return null;
  }

  String _publicTypeNameForElement(Element element) {
    final widget = element.widget;
    if (widget is TextButton) {
      return 'TextButton';
    }
    if (widget is ElevatedButton) {
      return 'ElevatedButton';
    }
    if (widget is FilledButton) {
      return 'FilledButton';
    }
    if (widget is OutlinedButton) {
      return 'OutlinedButton';
    }
    if (widget is ButtonStyleButton) {
      return 'ButtonStyleButton';
    }
    if (widget is IconButton) {
      return 'IconButton';
    }
    if (widget is FloatingActionButton) {
      return 'FloatingActionButton';
    }
    if (widget is ListTile) {
      return 'ListTile';
    }
    if (widget is ActionChip) {
      return 'ActionChip';
    }
    if (widget is CupertinoButton) {
      return 'CupertinoButton';
    }
    if (widget is CupertinoListTile) {
      return 'CupertinoListTile';
    }
    if (widget is ChoiceChip) {
      return 'ChoiceChip';
    }
    if (widget is FilterChip) {
      return 'FilterChip';
    }
    if (widget is InputChip) {
      return 'InputChip';
    }
    if (widget is CheckboxListTile) {
      return 'CheckboxListTile';
    }
    if (widget is Checkbox) {
      return 'Checkbox';
    }
    if (widget is SwitchListTile) {
      return 'SwitchListTile';
    }
    if (widget is Switch) {
      return 'Switch';
    }
    if (widget is CupertinoCheckbox) {
      return 'CupertinoCheckbox';
    }
    if (widget is CupertinoSwitch) {
      return 'CupertinoSwitch';
    }
    if (widget is CupertinoRadio) {
      return 'CupertinoRadio';
    }
    if (widget is CupertinoSlider) {
      return 'CupertinoSlider';
    }
    if (widget is CupertinoTextField) {
      return 'CupertinoTextField';
    }
    if (widget is CupertinoSearchTextField) {
      return 'CupertinoSearchTextField';
    }
    if (widget is CupertinoSegmentedControl) {
      return 'CupertinoSegmentedControl';
    }
    if (widget is CupertinoSlidingSegmentedControl) {
      return 'CupertinoSlidingSegmentedControl';
    }
    if (_cupertinoSegmentControlAncestor(element) != null) {
      return 'CupertinoSegment';
    }
    if (widget is TextField) {
      return 'TextField';
    }
    if (widget is TextFormField) {
      return 'TextFormField';
    }
    if (widget is EditableText) {
      return 'EditableText';
    }
    return widget.runtimeType.toString();
  }

  Element? _materialSegmentControlAncestor(Element element) {
    Element? result;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is SegmentedButton) {
        result = ancestor;
        return false;
      }
      return true;
    });
    return result;
  }

  Element? _cupertinoSegmentControlAncestor(Element element) {
    Element? result;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is CupertinoSegmentedControl ||
          widget is CupertinoSlidingSegmentedControl) {
        result = ancestor;
        return false;
      }
      return true;
    });
    return result;
  }

  String? _collectDescendantText(Element element) {
    final values = _collectDescendantTextParts(element);
    return values.isEmpty ? null : values.join(' ');
  }

  Set<String> _locatorTextParts(
    Element element, {
    required String? primaryText,
  }) {
    final primary = _normalizeText(primaryText);
    return _collectDescendantTextParts(
      element,
    ).where((part) => part != primary).toSet();
  }

  List<String> _collectDescendantTextParts(Element element) {
    final values = <String>{};

    void visit(Element child) {
      if (values.length >= 3) {
        return;
      }
      final text = _textFromWidget(child.widget);
      if (text != null && text.isNotEmpty) {
        values.add(text);
        return;
      }
      child.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return values.toList(growable: false);
  }

  String _registrationId({
    required String? routeName,
    required String path,
    required String typeName,
    required String? bestLabel,
  }) {
    final routeSegment = _slugify(routeName ?? 'unknown');
    final typeSegment = _slugify(typeName);
    final labelSegment = _slugify(bestLabel ?? typeName);
    final readable = <String>[
      'native',
      _boundedSegment(routeSegment, maxLength: 18),
      _boundedSegment(typeSegment, maxLength: 24),
      _boundedSegment(labelSegment, maxLength: 24),
    ].join('.');
    return '$readable.${_stableHashHex('$routeName|$typeName|$bestLabel|$path')}';
  }

  static final Map<String, String> _slugCache = <String, String>{};
  static const int _slugCacheLimit = 4096;

  String _slugify(String value) {
    final cached = _slugCache[value];
    if (cached != null) {
      return cached;
    }
    final slug = _computeSlug(value);
    if (_slugCache.length < _slugCacheLimit) {
      _slugCache[value] = slug;
    }
    return slug;
  }

  String _computeSlug(String value) {
    final buffer = StringBuffer();
    var lastWasDash = true;
    for (final codeUnit in value.toLowerCase().codeUnits) {
      final isAlphaNumeric =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 97 && codeUnit <= 122);
      if (isAlphaNumeric) {
        buffer.writeCharCode(codeUnit);
        lastWasDash = false;
      } else if (!lastWasDash) {
        buffer.write('-');
        lastWasDash = true;
      }
    }
    final raw = buffer.toString();
    var end = raw.length;
    while (end > 0 && raw.codeUnitAt(end - 1) == 0x2d) {
      end -= 1;
    }
    final slug = end == raw.length ? raw : raw.substring(0, end);
    return slug.isEmpty ? 'value' : slug;
  }

  String _boundedSegment(String value, {required int maxLength}) {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }

  String _stableHashHex(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      final normalized = _normalizeText(candidate);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeReadableText(String? value) {
    if (value == null) return null;
    final withoutIconGlyphs = String.fromCharCodes(
      value.runes.where((rune) => !_isPrivateUseCodePoint(rune)),
    );
    return _normalizeText(withoutIconGlyphs);
  }

  bool _isPrivateUseCodePoint(int rune) =>
      (rune >= 0xe000 && rune <= 0xf8ff) ||
      (rune >= 0xf0000 && rune <= 0xffffd) ||
      (rune >= 0x100000 && rune <= 0x10fffd);

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
        .map((segment) {
          final lower = segment.trim().toLowerCase();
          if (lower.isEmpty || RegExp(r'^\d+$').hasMatch(lower)) {
            return null;
          }
          final alphanumericOnly = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '');
          if (alphanumericOnly.isEmpty ||
              _pathNoiseSegments.contains(alphanumericOnly)) {
            return null;
          }
          return alphanumericOnly;
        })
        .whereType<String>()
        .toList(growable: false);
  }

  static const Set<String> _pathNoiseTypeNames = <String>{
    'AbsorbPointer',
    'Actions',
    'AnimatedBuilder',
    'AnimatedContainer',
    'AnimatedDefaultTextStyle',
    'AnimatedPhysicalModel',
    'AnimatedTheme',
    'AutomaticKeepAlive',
    'Banner',
    'Builder',
    'Center',
    'CheckedModeBanner',
    'ClipRect',
    'ColoredBox',
    'ConstrainedBox',
    'Container',
    'CupertinoTheme',
    'CustomPaint',
    'DecoratedBox',
    'DecoratedBoxTransition',
    'DefaultTextEditingShortcuts',
    'DefaultTextStyle',
    'Expanded',
    'Flexible',
    'FocusTraversalGroup',
    'FractionalTranslation',
    'IconTheme',
    'IndexedSemantics',
    'KeepAlive',
    'KeyedSubtree',
    'ListenableBuilder',
    'Localizations',
    'Material',
    'MaterialApp',
    'MediaQuery',
    'NotificationListener<LayoutChangedNotification>',
    'Offstage',
    'Overlay',
    'Padding',
    'PageStorage',
    'PhysicalModel',
    'Positioned',
    'RawGestureDetector',
    'RawView',
    'RepaintBoundary',
    'RestorationScope',
    'RootRestorationScope',
    'RootWidget',
    'SafeArea',
    'ScaffoldMessenger',
    'ScrollNotificationObserver',
    'Scrollbar',
    'Scrollable',
    'Semantics',
    'SharedAppData',
    'ShortcutRegistrar',
    'Shortcuts',
    'SizedBox',
    'SlideTransition',
    'Stack',
    'TapRegionSurface',
    'Theme',
    'TickerMode',
    'ValuelistenableBuilder<String>',
    'View',
    'Viewport',
    'WidgetsApp',
  };

  static const List<String> _pathNoiseTypePrefixes = <String>[
    'NotificationListener<',
    'ValueListenableBuilder<',
  ];

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
}

final class _TargetMetadata {
  const _TargetMetadata({
    this.text,
    this.keyValue,
    this.semanticId,
    this.tooltip,
  });

  final String? text;
  final String? keyValue;
  final String? semanticId;
  final String? tooltip;

  String? get displayLabel => text ?? semanticId ?? tooltip ?? keyValue;
}

final class _DelegatedSelectionSummary {
  const _DelegatedSelectionSummary({this.state, this.ambiguous = false});

  final CockpitControlState? state;
  final bool ambiguous;

  _DelegatedSelectionSummary merge(_DelegatedSelectionSummary other) {
    if (ambiguous || other.ambiguous) {
      return const _DelegatedSelectionSummary(ambiguous: true);
    }
    if (state == null) {
      return other;
    }
    if (other.state == null) {
      return this;
    }
    return const _DelegatedSelectionSummary(ambiguous: true);
  }
}

final class _ScrollableLocatorMetadata {
  const _ScrollableLocatorMetadata({this.path, this.keyValue, this.typeName});

  final String? path;
  final String? keyValue;
  final String? typeName;
}

/// Offstage and viewport state inherited along the discovery DFS.
final class _InheritedDiscoveryScope {
  const _InheritedDiscoveryScope({
    required this.ancestorHidden,
    required this.pointerBlocked,
    required this.effectiveViewport,
    this.routeScope,
  });

  /// Whether any ancestor is an active Offstage (subtree invisible).
  final bool ancestorHidden;

  /// Whether an ancestor prevents its descendants from receiving UI input.
  final bool pointerBlocked;

  /// Viewport bounds clipped by all enclosing scrollable boundaries.
  final Rect? effectiveViewport;

  /// The nearest modal route reported by Flutter's public route state.
  final _CockpitRouteScope? routeScope;

  _InheritedDiscoveryScope scopeForChildren(
    Element element, {
    required Rect? effectiveViewport,
  }) {
    final widget = element.widget;
    final hidden = ancestorHidden || (widget is Offstage && widget.offstage);
    final pointerBlocked =
        this.pointerBlocked || _blocksPointerForDescendants(widget);
    final routeScope = _cockpitRouteScopeForWidget(widget) ?? this.routeScope;
    if (hidden == ancestorHidden &&
        pointerBlocked == this.pointerBlocked &&
        identical(effectiveViewport, this.effectiveViewport) &&
        identical(routeScope, this.routeScope)) {
      return this;
    }
    return _InheritedDiscoveryScope(
      ancestorHidden: hidden,
      pointerBlocked: pointerBlocked,
      effectiveViewport: effectiveViewport,
      routeScope: routeScope,
    );
  }
}

bool _blocksPointerForDescendants(Widget widget) => switch (widget) {
  IgnorePointer(:final ignoring) => ignoring,
  AbsorbPointer(:final absorbing) => absorbing,
  _ => false,
};

final class _CockpitRouteScope {
  const _CockpitRouteScope({required this.routeName, required this.isCurrent});

  final String? routeName;
  final bool isCurrent;
}

_CockpitRouteScope? _cockpitRouteScopeForWidget(Widget widget) {
  // Flutter's modal route marker is a private InheritedModel, so read its
  // public route fields dynamically without registering a dependency during
  // discovery. Registering dependencies here would make tree scans mutate the
  // build graph and can invalidate an in-progress build.
  if (widget is! InheritedModel<dynamic>) {
    return null;
  }
  try {
    final dynamic modalScopeStatus = widget;
    final dynamic route = modalScopeStatus.route;
    final dynamic isCurrent = modalScopeStatus.isCurrent;
    if (route is! ModalRoute<dynamic> || isCurrent is! bool) {
      return null;
    }
    return _CockpitRouteScope(
      routeName: route.settings.name?.trim(),
      isCurrent: isCurrent,
    );
  } on Object {
    return null;
  }
}

String? _effectiveDiscoveryRouteName(
  _CockpitRouteScope? routeScope, {
  required String? fallbackRouteName,
}) {
  if (routeScope == null) {
    return fallbackRouteName;
  }
  final routeName = routeScope.routeName;
  if (routeName == null || routeName.isEmpty) {
    return routeScope.isCurrent ? fallbackRouteName : null;
  }
  if (routeName == '/' &&
      routeScope.isCurrent &&
      fallbackRouteName != null &&
      fallbackRouteName != '/') {
    return fallbackRouteName;
  }
  return routeName;
}

/// Per-discovery-pass memo so ancestor-derived metadata (locator paths,
/// inherited semantic ids and tooltips) is computed at most once per element.
final class _DiscoverySession {
  final Map<Element, _LocatorPathNode> pathNodes =
      Map<Element, _LocatorPathNode>.identity();
  final Map<Element, String> locatorPaths = Map<Element, String>.identity();
  final Map<Element, String?> semanticIds = Map<Element, String?>.identity();
  final Map<Element, String?> tooltips = Map<Element, String?>.identity();
  final Map<Element, _DelegatedSelectionSummary> selectionSummaries =
      Map<Element, _DelegatedSelectionSummary>.identity();
  final Map<Element, _DelegatedSelectionSummary> blockedSelectionSummaries =
      Map<Element, _DelegatedSelectionSummary>.identity();
}

/// Parent-linked locator path segment chain shared across sibling subtrees.
final class _LocatorPathNode {
  const _LocatorPathNode(this.parent, this.segment);

  static const _LocatorPathNode root = _LocatorPathNode(null, null);

  final _LocatorPathNode? parent;
  final String? segment;

  List<String> toSegments() {
    final reversed = <String>[];
    _LocatorPathNode? node = this;
    while (node != null) {
      final segment = node.segment;
      if (segment != null) {
        reversed.add(segment);
      }
      node = node.parent;
    }
    return reversed.reversed.toList(growable: false);
  }
}
