// ignore_for_file: deprecated_member_use

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
      bool insideActionableTarget,
      _InheritedDiscoveryScope scope,
    ) {
      final explicitTarget = explicitTargetsByElement[element];
      if (!element.mounted ||
          policy.ignoresSubtree(element) ||
          scope.ancestorHidden ||
          (!allowInactiveRouteFallback &&
              scope.routeScope?.isCurrent == false) ||
          explicitTarget?.supportedCommands.isNotEmpty == true) {
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
              _overlapsClippedViewport(element, effectiveViewport)
          ? _buildTarget(
              element,
              routeName: targetRouteName,
              path: path,
              insideActionableTarget: insideActionableTarget,
              session: session,
            )
          : null;
      final hasMeaningfulViewportExposure =
          candidate == null ||
          _hasMeaningfulClippedViewportExposure(
            element,
            effectiveViewport,
            strictVisibility: candidate.supportedCommands.isEmpty,
          );
      final createsActionableScope =
          candidate != null &&
          hasMeaningfulViewportExposure &&
          candidate.supportedCommands.isNotEmpty;
      if (candidate != null && hasMeaningfulViewportExposure) {
        discoveredTargets.add(candidate);
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
          insideActionableTarget || createsActionableScope,
          childScope,
        );
        childIndex += 1;
      });
    }

    visit(rootElement, 'root', false, rootScope);
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
      bool insideActionableTarget,
      _InheritedDiscoveryScope scope,
    ) {
      final explicitTarget = explicitTargetsByElement[element];
      if (found ||
          !element.mounted ||
          policy.ignoresSubtree(element) ||
          scope.ancestorHidden ||
          (!allowInactiveRouteFallback &&
              scope.routeScope?.isCurrent == false) ||
          explicitTarget?.supportedCommands.isNotEmpty == true) {
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
              insideActionableTarget: insideActionableTarget,
              session: session,
            )
          : null;
      final hasMeaningfulViewportExposure =
          candidate == null ||
          _hasMeaningfulClippedViewportExposure(
            element,
            effectiveViewport,
            strictVisibility: candidate.supportedCommands.isEmpty,
          );
      final createsActionableScope =
          candidate != null &&
          hasMeaningfulViewportExposure &&
          candidate.supportedCommands.isNotEmpty;
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
          insideActionableTarget || createsActionableScope,
          childScope,
        );
        childIndex += 1;
      });
    }

    visit(rootElement, 'root', false, rootScope);
    return found;
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
        (existing) => _isDuplicatePassiveTarget(existing, target),
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

  bool _isDuplicatePassiveTarget(CockpitTarget left, CockpitTarget right) {
    if (left.supportedCommands.isNotEmpty ||
        right.supportedCommands.isNotEmpty) {
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
    if (target.supportedCommands.isNotEmpty) {
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
        if (explicitTargetsByElement[ancestor]?.supportedCommands.isNotEmpty ==
            true) {
          ancestorHidden = true;
        }
        routeScope ??= _cockpitRouteScopeForWidget(widget);
        if (_marksViewportBoundary(ancestor)) {
          effectiveViewport = _intersectViewports(effectiveViewport, ancestor);
        }
        return true;
      });
    }

    return _InheritedDiscoveryScope(
      ancestorHidden: ancestorHidden,
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
    required bool insideActionableTarget,
    required _DiscoverySession session,
  }) {
    final semantics = cockpitResolveSemanticsTargetInfo(element);
    final tapHandler = _tapHandlerForElement(element);
    final longPressHandler = _longPressHandlerForElement(element);
    final doubleTapHandler = _doubleTapHandlerForElement(element);
    final enterTextHandler = _enterTextHandlerForElement(element);
    final textInputHandler = _textInputHandlerForElement(element);
    final isTextInput = enterTextHandler != null || textInputHandler != null;
    final hasDirectHandlers =
        tapHandler != null ||
        longPressHandler != null ||
        doubleTapHandler != null ||
        enterTextHandler != null ||
        textInputHandler != null;
    final supportedCommands = <CockpitCommandType>{
      if (tapHandler != null) CockpitCommandType.tap,
      if (longPressHandler != null) CockpitCommandType.longPress,
      if (doubleTapHandler != null) CockpitCommandType.doubleTap,
      if (enterTextHandler != null || textInputHandler != null)
        CockpitCommandType.enterText,
      if (textInputHandler != null) ...<CockpitCommandType>{
        CockpitCommandType.focusTextInput,
        CockpitCommandType.setTextEditingValue,
        CockpitCommandType.sendTextInputAction,
      },
      if (semantics != null) ...semantics.supportedCommands,
    };
    final typeName = _publicTypeNameForWidget(element.widget);

    if (insideActionableTarget) {
      return null;
    }

    if (!hasDirectHandlers &&
        supportedCommands.isNotEmpty &&
        _shouldDeferSemanticsOnlyCandidate(element, semantics, session)) {
      return null;
    }

    if (supportedCommands.isNotEmpty) {
      final metadata = _extractInteractiveMetadata(
        element,
        semantics: semantics,
        isTextInput: isTextInput,
        session: session,
      );
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
        tooltip: metadata.tooltip,
        typeName: typeName,
        path: _locatorPathForElement(element, session),
        scrollablePath: scrollableMetadata.path,
        scrollableKeyValue: scrollableMetadata.keyValue,
        scrollableTypeName: scrollableMetadata.typeName,
        routeName: routeName ?? '',
        supportedCommands: supportedCommands,
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
        onSemanticTap: semantics?.actionHandler(SemanticsAction.tap),
        onSemanticLongPress: semantics?.actionHandler(
          SemanticsAction.longPress,
        ),
        onSemanticShowOnScreen: semantics?.actionHandler(
          SemanticsAction.showOnScreen,
        ),
        onSemanticIncrease: semantics?.actionHandler(SemanticsAction.increase),
        onSemanticDecrease: semantics?.actionHandler(SemanticsAction.decrease),
        onSemanticDismiss: semantics?.actionHandler(SemanticsAction.dismiss),
        onSemanticEnterText:
            semantics == null || !semantics.supports(SemanticsAction.setText)
            ? null
            : (text) => semantics.performAction(SemanticsAction.setText, text),
        onSemanticTextInput:
            semantics == null || !semantics.supports(SemanticsAction.setText)
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
      ancestors.add(
        CockpitSnapshotAncestor(
          typeName: ancestor.widget.runtimeType.toString(),
          cockpitId: _firstNonEmpty(<String?>[semanticId, keyValue]),
          semanticId: semanticId,
          keyValue: keyValue,
          textPreview: _firstNonEmpty(<String?>[
            _passiveTextForElement(ancestor),
            tooltip,
          ]),
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
        widget is Listener ||
        widget is MouseRegion ||
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

  bool _shouldDeferPassiveCandidate(
    Element element,
    CockpitSemanticsTargetInfo? semantics,
    _DiscoverySession session,
  ) {
    final widget = element.widget;
    final typeName = widget.runtimeType.toString();
    if (typeName.startsWith('_')) {
      return true;
    }
    if (widget is InheritedWidget ||
        widget is ParentDataWidget<ParentData> ||
        widget is Focus ||
        widget is Listener ||
        widget is IgnorePointer ||
        widget is MouseRegion ||
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

  CockpitTapHandler? _tapHandlerForElement(Element element) {
    final customHandler = policy.tapHandlerForElement?.call(element);
    if (customHandler != null) {
      return customHandler;
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
    if (widget is InkWell) {
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
    final editableState = _editableTextStateForElement(element);
    if (editableState != null) {
      final state = editableState;
      return () => state.widget.focusNode.requestFocus();
    }
    return null;
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
      final shouldUpdateValue =
          request.hasEditingMutation || request.requestFocus;
      if (shouldUpdateValue) {
        final value = currentValue.copyWith(
          text: resolvedText,
          selection: selection,
          composing: TextRange.empty,
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
    if (widget is InkWell) {
      return widget.onLongPress;
    }
    if (widget is GestureDetector) {
      return widget.onLongPress;
    }
    if (widget is ListTile) {
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
    if (widget is InkWell) {
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
    final text = isTextInput && inputLabel != null
        ? _joinTextSignals(<String?>[inputLabel, inputError])
        : _firstNonEmpty(<String?>[
            policy.extractText?.call(element),
            semantics?.label,
            semantics?.value,
            semantics?.hint,
            _interactiveTextForElement(element),
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
      return _normalizeText(widget.data ?? widget.textSpan?.toPlainText());
    }
    if (widget is RichText) {
      return _normalizeText(widget.text.toPlainText());
    }
    if (widget is EditableText) {
      return _normalizeText(widget.controller.text);
    }
    if (widget is TextField) {
      return _normalizeText(
        widget.controller?.text.isNotEmpty == true
            ? widget.controller?.text
            : widget.decoration?.labelText ?? widget.decoration?.hintText,
      );
    }
    if (widget is TextFormField) {
      final controllerText = widget.controller?.text;
      return _normalizeText(
        controllerText != null && controllerText.isNotEmpty
            ? controllerText
            : widget.initialValue,
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

  String? _tooltipFromWidget(Widget widget) {
    if (widget is Tooltip) {
      return _normalizeText(widget.message);
    }
    if (widget is Semantics) {
      return _normalizeText(widget.properties.tooltip);
    }
    return null;
  }

  String _publicTypeNameForWidget(Widget widget) {
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

  String? _collectDescendantText(Element element) {
    final values = <String>[];

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
    if (values.isEmpty) {
      return null;
    }
    return values.join(' ').trim();
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
    required this.effectiveViewport,
    this.routeScope,
  });

  /// Whether any ancestor is an active Offstage (subtree invisible).
  final bool ancestorHidden;

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
    final routeScope = _cockpitRouteScopeForWidget(widget) ?? this.routeScope;
    if (hidden == ancestorHidden &&
        identical(effectiveViewport, this.effectiveViewport) &&
        identical(routeScope, this.routeScope)) {
      return this;
    }
    return _InheritedDiscoveryScope(
      ancestorHidden: hidden,
      effectiveViewport: effectiveViewport,
      routeScope: routeScope,
    );
  }
}

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
