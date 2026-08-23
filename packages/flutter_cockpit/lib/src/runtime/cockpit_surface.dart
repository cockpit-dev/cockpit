import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import '../capture/cockpit_captured_screenshot.dart';
import '../capture/flutter_view_capture.dart';
import '../control/cockpit_command_type.dart';
import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../errors/cockpit_command_error.dart';
import '../gesture/cockpit_gesture_engine.dart';
import '../control/cockpit_screenshot_request.dart';
import '../gesture/cockpit_gesture_action.dart';
import '../gesture/cockpit_gesture_profile.dart';
import 'cockpit_discovery_engine.dart';
import 'cockpit_discovery_policy.dart';
import 'cockpit_focus_snapshot_builder.dart';
import 'cockpit_rebuild_tracker.dart';
import 'cockpit_reveal_alignment.dart';
import 'cockpit_tap_feedback_overlay.dart';
import 'cockpit_diagnostic_builder.dart';
import 'cockpit_runtime_tree_visibility.dart';
import 'cockpit_scroll_step_result.dart';
import 'cockpit_semantics_bridge.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_snapshot_options.dart';
import 'cockpit_target.dart';
import 'cockpit_target_geometry.dart';
import 'cockpit_target_geometry_resolver.dart';
import 'cockpit_target_hit_test_inspector.dart';
import 'cockpit_target_registry.dart';
import 'cockpit_visual_frame_driver.dart';
import 'cockpit_widget_tree_builder.dart';
import 'flutter_cockpit.dart';

final class CockpitSurface extends StatefulWidget {
  const CockpitSurface({
    required this.routeName,
    required this.child,
    super.key,
    this.registry,
    this.gestureDelay,
    this.discoveryPolicy = const CockpitDiscoveryPolicy(),
    this.rebuildTracker,
    this.tapFeedbackController,
  });

  final String routeName;
  final Widget child;
  final CockpitTargetRegistry? registry;
  final CockpitGestureDelay? gestureDelay;
  final CockpitDiscoveryPolicy discoveryPolicy;
  final CockpitRebuildTracker? rebuildTracker;
  final CockpitTapFeedbackController? tapFeedbackController;

  static CockpitSurfaceState of(BuildContext context) {
    final state = maybeOf(context);
    if (state == null) {
      throw StateError('No CockpitSurface found in the current BuildContext.');
    }
    return state;
  }

  static CockpitSurfaceState? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_CockpitSurfaceScope>()
        ?.state;
  }

  @override
  State<CockpitSurface> createState() => CockpitSurfaceState();
}

final class CockpitSurfaceState extends State<CockpitSurface> {
  final GlobalKey _boundaryKey = GlobalKey(
    debugLabel: 'CockpitSurfaceBoundary',
  );
  final FlutterViewCapture _capture = const FlutterViewCapture();
  final CockpitDiagnosticBuilder _diagnosticBuilder =
      const CockpitDiagnosticBuilder();
  final CockpitWidgetTreeBuilder _widgetTreeBuilder =
      const CockpitWidgetTreeBuilder();
  SemanticsHandle? _semanticsHandle;
  late CockpitDiscoveryEngine _discoveryEngine = CockpitDiscoveryEngine(
    policy: widget.discoveryPolicy,
  );
  late final CockpitGestureEngine _gestureEngine = CockpitGestureEngine(
    delay: widget.gestureDelay,
    viewportGeometryProvider: _viewportGeometry,
  );
  late final CockpitTargetRegistry _registry =
      widget.registry ?? CockpitTargetRegistry(routeName: widget.routeName);
  Element? _scrollDiscoveryRoot;
  CockpitLocator? _scrollDiscoveryLocator;
  List<_CockpitScrollableCandidate> _scrollDiscoveryCandidates =
      const <_CockpitScrollableCandidate>[];
  bool _scrollDiscoveryTargetWasMounted = false;

  CockpitTargetRegistry get registry => _registry;

  CockpitSemanticActionHandler? resolveDismissAction() {
    const intent = DismissIntent();

    CockpitSemanticActionHandler? resolveFrom(BuildContext? context) {
      if (context is! Element || !context.mounted) return null;
      return Actions.handler(context, intent);
    }

    final focused = resolveFrom(FocusManager.instance.primaryFocus?.context);
    if (focused != null) return focused;

    final rootContext = _boundaryKey.currentContext;
    if (rootContext is! Element) return null;
    CockpitSemanticActionHandler? resolved;

    void visit(Element element) {
      if (resolved != null || !element.mounted) return;
      final children = <Element>[];
      element.visitChildElements(children.add);
      for (final child in children.reversed) {
        visit(child);
        if (resolved != null) return;
      }
      resolved = resolveFrom(element);
    }

    visit(rootContext);
    return resolved;
  }

  CockpitTargetResolutionResult probeVisibleLocator(
    CockpitLocator locator, {
    CockpitCommandType? requiredCommand,
  }) {
    final rootContext = _boundaryKey.currentContext;
    if (rootContext is! Element) {
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: 'The Flutter surface is not mounted.',
        ),
      );
    }
    var needsNativeDiscoveryFallback = false;
    for (final candidate in _flatten(locator)) {
      if (candidate.index != null) {
        return _registry.resolve(candidate, requiredCommand: requiredCommand);
      }
      if (requiredCommand != null && _registry.registeredTargets.isNotEmpty) {
        final registryResolution = _registry.resolveRegistered(
          candidate,
          requiredCommand: requiredCommand,
        );
        final resolvedTargetSupportsCommand =
            registryResolution.target?.supportedCommands.contains(
              requiredCommand,
            ) ==
            true;
        final hasCommandMatches = registryResolution.matches.any(
          (target) => target.supportedCommands.contains(requiredCommand),
        );
        if (resolvedTargetSupportsCommand || hasCommandMatches) {
          return registryResolution;
        }
      }
      final probe = _probeForLocator(
        rootContext,
        candidate,
        visibleOnly: true,
        fallbackLocator: _stableTextKeyFallback(candidate),
      );
      if (probe.ambiguous) {
        if (requiredCommand != null &&
            !_allowsExplicitGestureFallback(candidate, requiredCommand)) {
          return _registry.resolve(locator, requiredCommand: requiredCommand);
        }
        return CockpitTargetResolutionResult.failure(
          error: CockpitCommandError.ambiguousTarget(
            message: 'Multiple visible Flutter elements matched the locator.',
            details: <String, Object?>{
              'matchedKind': candidate.kind.name,
              'matchedValue': candidate.value,
              'candidateCount': probe.matchCount,
            },
          ),
        );
      }
      final element = probe.element;
      if (element != null) {
        final targetResolution = _probeTargetForElement(
          element,
          rootContext: rootContext,
          requiredCommand: requiredCommand,
          allowGestureFallback: _allowsExplicitGestureFallback(
            candidate,
            requiredCommand,
          ),
        );
        if (!targetResolution.isSuccess) {
          return targetResolution;
        }
        return CockpitTargetResolutionResult.success(
          target: targetResolution.target!,
          locatorResolution: CockpitLocatorResolution(
            matchedKind: candidate.kind,
            matchedValue: candidate.value,
            matchedSignals: _matchedLocatorSignals(candidate),
          ),
          matches: targetResolution.matches,
        );
      }
      if (!_canFastFailDirectElementProbe(candidate, requiredCommand)) {
        needsNativeDiscoveryFallback = true;
      }
    }
    if (!needsNativeDiscoveryFallback) {
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.targetNotFound(
          message: 'No visible target matched the requested locator chain.',
          details: <String, Object?>{'requestedLocator': locator.toJson()},
        ),
      );
    }
    return _registry.resolve(locator, requiredCommand: requiredCommand);
  }

  bool _canFastFailDirectElementProbe(
    CockpitLocator locator,
    CockpitCommandType? requiredCommand,
  ) {
    if (requiredCommand != null ||
        locator.text == null ||
        locator.signalMap.length != 1 ||
        locator.matchMode != CockpitTextMatchMode.exact ||
        locator.ancestor != null ||
        locator.index != null) {
      return false;
    }
    final routeName = _registry.routeName;
    return !_registry.registeredTargets.any((target) {
      if (!target.isVisible ||
          (routeName != null &&
              routeName.isNotEmpty &&
              target.routeName != routeName)) {
        return false;
      }
      return <String?>[
        target.text,
        ...target.textParts,
        target.displayLabel,
        target.tooltip,
      ].any(
        (value) => _matchesTextSignal(
          value,
          locator.value,
          CockpitTextMatchMode.exact,
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
    _registry.discoveredTargetsProvider = _discoverNativeTargets;
    _registry.discoveredTargetsReadinessProbe = _hasDiscoveredNativeTarget;
  }

  @override
  void didUpdateWidget(covariant CockpitSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registry.routeName = widget.routeName;
    if (oldWidget.routeName != widget.routeName ||
        oldWidget.discoveryPolicy != widget.discoveryPolicy) {
      _clearScrollDiscoveryCache();
    }
    if (oldWidget.discoveryPolicy != widget.discoveryPolicy) {
      _discoveryEngine = CockpitDiscoveryEngine(policy: widget.discoveryPolicy);
    }
  }

  @override
  void dispose() {
    _registry.discoveredTargetsProvider = null;
    _registry.discoveredTargetsReadinessProbe = null;
    _semanticsHandle?.dispose();
    super.dispose();
  }

  CockpitSnapshot snapshot({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions(),
  }) {
    var visibleTargets = options.maxTargets == 0 && options.query == null
        ? const <CockpitTarget>[]
        : _registry.visibleTargets;
    var diagnosticOptions = options;
    final query = options.query?.trim();
    if (query != null && query.isNotEmpty) {
      visibleTargets = _mountedTargetsForQuery(query);
      diagnosticOptions = options.copyWith(clearQuery: true);
    }
    var snapshot = _diagnosticBuilder
        .build(
          routeName: _registry.routeName,
          visibleTargets: visibleTargets,
          options: diagnosticOptions,
        )
        .snapshot;
    final treeOptions = options.tree;
    final rootContext = _boundaryKey.currentContext;
    if (treeOptions != null && rootContext is Element) {
      snapshot = snapshot.copyWith(
        tree: _widgetTreeBuilder.build(
          root: rootContext,
          route: _registry.routeName,
          targets: visibleTargets,
          options: treeOptions,
        ),
      );
    }
    if (!options.includeRebuildActivity || widget.rebuildTracker == null) {
      return snapshot.copyWith(focus: cockpitBuildFocusSnapshot());
    }
    return snapshot.copyWith(
      focus: cockpitBuildFocusSnapshot(),
      rebuild: widget.rebuildTracker!.snapshot(
        maxEntries: options.maxRebuildEntries,
      ),
    );
  }

  Future<CockpitCapturedScreenshot> captureScreenshot(
    CockpitScreenshotRequest request, {
    double pixelRatio = 1.0,
  }) {
    Rect? cropRect;
    final cropLocator = request.cropLocator;
    if (cropLocator != null) {
      final resolution = _registry.resolve(cropLocator);
      final geometry = resolution.target == null
          ? null
          : CockpitTargetGeometryResolver.maybeFromTarget(resolution.target!);
      final viewport = _viewportGeometry();
      if (!resolution.isSuccess || geometry == null || viewport == null) {
        throw StateError('Screenshot crop locator has no visible geometry.');
      }
      final target = Rect.fromLTWH(
        geometry.left,
        geometry.top,
        geometry.width,
        geometry.height,
      );
      final viewportRect = Rect.fromLTWH(
        viewport.left,
        viewport.top,
        viewport.width,
        viewport.height,
      );
      final visible = target.intersect(viewportRect);
      if (visible.isEmpty) {
        throw StateError(
          'Screenshot crop locator is outside the Flutter view.',
        );
      }
      cropRect = visible.shift(Offset(-viewport.left, -viewport.top));
    }
    return _capture.capture(
      repaintBoundaryKey: _boundaryKey,
      request: request,
      snapshot: request.includeSnapshot
          ? snapshot(
              options:
                  request.snapshotOptions ??
                  const CockpitSnapshotOptions.live(),
            )
          : null,
      pixelRatio: pixelRatio,
      cropRect: cropRect,
    );
  }

  Future<void> performGesture(CockpitGestureAction action) {
    widget.tapFeedbackController?.record(action);
    return _gestureEngine.perform(action);
  }

  Future<bool> ensureLocatorVisible(
    CockpitLocator locator, {
    Duration duration = const Duration(milliseconds: 220),
    CockpitRevealAlignment alignment = CockpitRevealAlignment.nearest,
    double padding = 0,
    double offset = 0,
  }) async {
    final rootContext = _boundaryKey.currentContext;
    if (rootContext is! Element) {
      return false;
    }

    final resolution = _registry.resolve(locator);
    final resolvedNode = resolution.target?.diagnosticNodeProvider?.call();
    final match = switch (resolvedNode) {
      final Element element when resolution.isSuccess && element.mounted =>
        element,
      _ => _findMountedElementForLocator(rootContext, locator),
    };
    if (match == null) {
      return false;
    }

    // Search steps preserve their requested pacing. Final placement is an
    // atomic jump so nested scrollables cannot leave Cockpit waiting on
    // competing animation futures after the target is already located.
    const effectiveDuration = Duration.zero;
    final revealRequest = _resolveRevealRequest(
      match,
      alignment: alignment,
      padding: padding,
    );
    if (revealRequest != null) {
      unawaited(
        Scrollable.ensureVisible(
          match,
          alignment: revealRequest.alignment,
          duration: effectiveDuration,
          alignmentPolicy: revealRequest.alignmentPolicy,
        ).catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'flutter_cockpit',
              context: ErrorDescription('while revealing a Cockpit target'),
            ),
          );
        }),
      );
      await _settleAtomicRevealFrame();
    }
    await _applyRevealAdjustment(
      match,
      alignment: alignment,
      padding: padding,
      offset: offset,
      duration: effectiveDuration,
    );
    await _settleAtomicRevealFrame();
    return _locatorIsVisible(locator);
  }

  Future<void> _settleAtomicRevealFrame() async {
    await Future<void>.microtask(() {});
    final binding = WidgetsBinding.instance;
    if (_isTestBinding(binding)) {
      return;
    }
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    if (cockpitSupportsSyntheticVisualFrames(platform)) {
      await ensureCockpitVisualFrame(
        platform: platform,
        force: true,
        budget: const Duration(milliseconds: 250),
        stallTimeout: const Duration(milliseconds: 250),
      );
      return;
    }
    if (!binding.hasScheduledFrame &&
        binding.schedulerPhase == SchedulerPhase.idle) {
      binding.scheduleFrame();
    }
    if (!binding.hasScheduledFrame) return;
    try {
      await binding.endOfFrame.timeout(const Duration(milliseconds: 250));
    } on TimeoutException {
      // Geometry is revalidated below; a continuously animated application
      // must not turn one deterministic reveal into an unbounded wait.
    }
  }

  bool _scrollExtentExpanded(
    CockpitScrollStepResult result,
    ScrollPosition position, {
    required bool reverse,
  }) {
    const tolerance = 0.5;
    if (reverse) {
      final previousMin = result.minScrollExtent;
      return previousMin != null &&
          position.minScrollExtent < previousMin - tolerance;
    }
    final previousMax = result.maxScrollExtent;
    return previousMax != null &&
        position.maxScrollExtent > previousMax + tolerance;
  }

  CockpitScrollStepResult _mergeExpandedScrollStep(
    CockpitScrollStepResult initial,
    CockpitScrollStepResult expanded,
  ) {
    return CockpitScrollStepResult(
      didScroll: initial.didScroll || expanded.didScroll,
      strategy: expanded.didScroll
          ? '${expanded.strategy}_extentRefresh'
          : initial.strategy,
      scrollableKey: expanded.scrollableKey ?? initial.scrollableKey,
      scrollablePath: expanded.scrollablePath ?? initial.scrollablePath,
      scrollableTypeName:
          expanded.scrollableTypeName ?? initial.scrollableTypeName,
      pixelsBefore: initial.pixelsBefore ?? expanded.pixelsBefore,
      pixelsAfter: expanded.pixelsAfter ?? initial.pixelsAfter,
      nextPixels: expanded.nextPixels ?? initial.nextPixels,
      minScrollExtent: expanded.minScrollExtent ?? initial.minScrollExtent,
      maxScrollExtent: expanded.maxScrollExtent ?? initial.maxScrollExtent,
      viewportDimension:
          expanded.viewportDimension ?? initial.viewportDimension,
      acceptsUserOffset:
          expanded.acceptsUserOffset ?? initial.acceptsUserOffset,
      allowsProgrammaticScroll:
          expanded.allowsProgrammaticScroll ?? initial.allowsProgrammaticScroll,
      hadGestureTarget: initial.hadGestureTarget || expanded.hadGestureTarget,
      hadSemanticAction:
          initial.hadSemanticAction || expanded.hadSemanticAction,
      matchedRegistryTarget:
          initial.matchedRegistryTarget || expanded.matchedRegistryTarget,
    );
  }

  CockpitScrollStepResult _refreshScrollExtents(
    CockpitScrollStepResult result,
    ScrollPosition position,
  ) {
    return CockpitScrollStepResult(
      didScroll: result.didScroll,
      strategy: result.strategy,
      scrollableKey: result.scrollableKey,
      scrollablePath: result.scrollablePath,
      scrollableTypeName: result.scrollableTypeName,
      scrollableCandidateIndex: result.scrollableCandidateIndex,
      scrollableCandidateCount: result.scrollableCandidateCount,
      pixelsBefore: result.pixelsBefore,
      pixelsAfter: position.pixels,
      nextPixels: result.nextPixels,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
      acceptsUserOffset: result.acceptsUserOffset,
      allowsProgrammaticScroll: result.allowsProgrammaticScroll,
      hadGestureTarget: result.hadGestureTarget,
      hadSemanticAction: result.hadSemanticAction,
      matchedRegistryTarget: result.matchedRegistryTarget,
      targetVisibilityObserved: result.targetVisibilityObserved,
      targetMounted: result.targetMounted,
      targetVisible: result.targetVisible,
    );
  }

  List<CockpitTarget> _discoverNativeTargets({
    bool includeClippedTargets = false,
  }) {
    final rootContext = _boundaryKey.currentContext;
    if (rootContext == null) {
      return const <CockpitTarget>[];
    }

    final discovered = _discoveryEngine.discover(
      rootContext: rootContext,
      routeName: _registry.routeName,
      explicitTargets: _registry.registeredTargets,
      includeClippedTargets: includeClippedTargets,
    );
    _syncRouteFromDiscoveredTargets(discovered);
    if (discovered.isNotEmpty ||
        _registry.routeName == null ||
        _registry.registeredTargets.any(
          (target) =>
              target.isVisible && target.routeName == _registry.routeName,
        )) {
      return discovered;
    }

    final fallbackDiscovered = _discoveryEngine.discover(
      rootContext: rootContext,
      routeName: _registry.routeName,
      explicitTargets: _registry.registeredTargets,
      allowInactiveRouteFallback: true,
      includeClippedTargets: includeClippedTargets,
    );
    _syncRouteFromDiscoveredTargets(fallbackDiscovered);
    return fallbackDiscovered;
  }

  List<CockpitTarget> _mountedTargetsForQuery(String query) {
    final discovered = _discoverNativeTargets(includeClippedTargets: true);
    final mountedRegistry = CockpitTargetRegistry(
      routeName: _registry.routeName,
    )..discoveredTargetsProvider = () => discovered;
    for (final target in _registry.registeredTargets) {
      mountedRegistry.register(target);
    }
    final mountedTargets = mountedRegistry.allTargets;
    if (CockpitSelector.isExplicit(query)) {
      final matches = mountedRegistry.matchingTargets(
        CockpitSelector.parse(query),
        includeHidden: true,
      );
      return matches.isEmpty ? mountedRegistry.visibleTargets : matches;
    }
    final normalized = query.toLowerCase();
    final matches = mountedTargets
        .where((target) => _targetMatchesQuery(target, normalized))
        .toList(growable: false);
    return matches.isEmpty ? mountedRegistry.visibleTargets : matches;
  }

  bool _targetMatchesQuery(CockpitTarget target, String query) => <String?>[
    target.cockpitId,
    target.semanticId,
    target.keyValue,
    target.text,
    ...target.textParts,
    target.tooltip,
    target.typeName,
    target.routeName,
    target.path,
  ].any((value) => value?.toLowerCase().contains(query) ?? false);

  void _syncRouteFromDiscoveredTargets(List<CockpitTarget> targets) {
    if (targets.isEmpty) {
      return;
    }
    final routeCounts = <String, int>{};
    for (final target in targets) {
      final routeName = target.routeName.trim();
      if (routeName.isEmpty || routeName == '/') {
        continue;
      }
      routeCounts[routeName] = (routeCounts[routeName] ?? 0) + 1;
    }
    if (routeCounts.isEmpty) {
      return;
    }
    var routeName = routeCounts.keys.first;
    var routeCount = routeCounts[routeName]!;
    for (final entry in routeCounts.entries.skip(1)) {
      if (entry.value > routeCount) {
        routeName = entry.key;
        routeCount = entry.value;
      }
    }
    FlutterCockpit.binding.setDiscoveredRouteName(routeName);
  }

  bool _hasDiscoveredNativeTarget({
    bool allowRouteFallback = true,
    String? routeName,
  }) {
    final rootContext = _boundaryKey.currentContext;
    if (rootContext == null) {
      return false;
    }
    return _discoveryEngine.hasDiscoverableTarget(
      rootContext: rootContext,
      routeName: routeName ?? _registry.routeName,
      explicitTargets: _registry.registeredTargets,
      allowInactiveRouteFallback: allowRouteFallback,
    );
  }

  CockpitTargetGeometry? _viewportGeometry() {
    final rootContext = _boundaryKey.currentContext;
    if (rootContext is! Element) {
      return null;
    }
    return CockpitTargetGeometryResolver.maybeFromViewport(rootContext);
  }

  Future<CockpitScrollStepResult> scrollByViewport({
    bool reverse = false,
    double viewportFraction = 0.8,
    String? scrollableKey,
    CockpitLocator? targetLocator,
    CockpitLocator? scrollableLocator,
    Duration duration = const Duration(milliseconds: 220),
    CockpitGestureProfile gestureProfile = CockpitGestureProfile.userLike,
    bool continuous = false,
    bool postScrollEnsureVisible = true,
    bool probeDuringScroll = true,
  }) async {
    final rootContext = _boundaryKey.currentContext;
    if (rootContext == null) {
      return const CockpitScrollStepResult(didScroll: false);
    }

    final rootElement = rootContext as Element;
    final targetElement = targetLocator == null
        ? null
        : _findResolvedElementForLocator(rootElement, targetLocator);
    final scrollables =
        _scrollableCandidatesForSearch(
              rootElement,
              targetLocator: targetLocator,
              targetElement: targetElement,
            )
            .where((candidate) {
              final position = candidate.state.position;
              if (!position.haveDimensions || position.maxScrollExtent <= 0) {
                return false;
              }
              if (targetLocator != null &&
                  !position.physics.allowUserScrolling) {
                return false;
              }
              if (scrollableKey == null || scrollableKey.isEmpty) {
                return true;
              }
              return candidate.keyValue == scrollableKey;
            })
            .toList(growable: false);
    if (scrollables.isEmpty) {
      return const CockpitScrollStepResult(didScroll: false);
    }
    final selection = _selectScrollableCandidate(
      scrollables,
      targetLocator: targetLocator,
      targetElement: targetElement,
      scrollableLocator: scrollableLocator,
    );
    if (selection == null) {
      final targetMounted = targetElement != null;
      return CockpitScrollStepResult(
        didScroll: false,
        scrollableCandidateCount: scrollables.length,
        targetVisibilityObserved: targetLocator != null,
        targetMounted: targetMounted,
        targetVisible: targetMounted && _locatorIsVisible(targetLocator),
      );
    }
    final scrollable = selection.candidate;
    final position = scrollable.state.position;
    final targetAlreadyVisible = targetLocator?.kind == CockpitLocatorKind.route
        ? widget.routeName == targetLocator?.value
        : targetElement != null && _elementIsFullyVisible(targetElement);
    if (targetAlreadyVisible) {
      return _withScrollableSelection(
        CockpitScrollStepResult(
          didScroll: false,
          strategy: 'alreadyVisible',
          scrollableKey: scrollable.keyValue,
          scrollablePath: scrollable.path,
          scrollableTypeName: scrollable.typeName,
          pixelsBefore: position.pixels,
          pixelsAfter: position.pixels,
          nextPixels: position.pixels,
          minScrollExtent: position.minScrollExtent,
          maxScrollExtent: position.maxScrollExtent,
          viewportDimension: position.viewportDimension,
          acceptsUserOffset: position.physics.shouldAcceptUserOffset(position),
          allowsProgrammaticScroll: position.physics.allowUserScrolling,
          targetMounted: true,
          targetVisible: true,
        ),
        selection,
        targetLocator: targetLocator,
        targetMounted: targetElement != null,
      );
    }

    var scrollResult = await _scrollScrollableByViewport(
      scrollable,
      reverse: reverse,
      viewportFraction: viewportFraction,
      duration: duration,
      gestureProfile: gestureProfile,
      continuous: continuous,
      postScrollEnsureVisible: postScrollEnsureVisible,
      preferProgrammatic: probeDuringScroll && targetLocator != null,
    );
    if (probeDuringScroll && targetLocator != null) {
      await _settleAtomicRevealFrame();
    }
    if (!scrollResult.didScroll &&
        _scrollExtentExpanded(scrollResult, position, reverse: reverse)) {
      final expandedResult = await _scrollScrollableByViewport(
        scrollable,
        reverse: reverse,
        viewportFraction: viewportFraction,
        duration: duration,
        gestureProfile: gestureProfile,
        continuous: continuous,
        postScrollEnsureVisible: postScrollEnsureVisible,
        preferProgrammatic: probeDuringScroll && targetLocator != null,
      );
      scrollResult = _mergeExpandedScrollStep(scrollResult, expandedResult);
      if (probeDuringScroll && targetLocator != null) {
        await _settleAtomicRevealFrame();
      }
    }
    scrollResult = _refreshScrollExtents(scrollResult, position);
    final resolvedTarget = targetLocator == null
        ? targetElement
        : _findResolvedElementForLocator(rootElement, targetLocator);
    final targetVisible =
        resolvedTarget != null && _elementIsFullyVisible(resolvedTarget);
    return _withScrollableSelection(
      scrollResult,
      selection,
      targetLocator: targetLocator,
      targetMounted: resolvedTarget != null,
      targetVisible: targetVisible,
    );
  }

  Future<CockpitScrollStepResult> _scrollScrollableByViewport(
    _CockpitScrollableCandidate scrollable, {
    required bool reverse,
    required double viewportFraction,
    required Duration duration,
    required CockpitGestureProfile gestureProfile,
    required bool continuous,
    required bool postScrollEnsureVisible,
    bool preferProgrammatic = false,
  }) async {
    final position = scrollable.state.position;
    final pixelsBefore = position.pixels;
    final axisSign = switch (position.axisDirection) {
      AxisDirection.down || AxisDirection.right => 1.0,
      AxisDirection.up || AxisDirection.left => -1.0,
    };
    final delta =
        position.viewportDimension * viewportFraction.clamp(0.1, 0.95);
    final directionSign = reverse ? -axisSign : axisSign;
    final nextPixels = (position.pixels + (delta * directionSign)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final allowsProgrammaticScroll = position.physics.allowUserScrolling;
    final acceptsUserOffset = position.physics.shouldAcceptUserOffset(position);
    final baseResult = CockpitScrollStepResult(
      didScroll: false,
      strategy: 'none',
      scrollableKey: scrollable.keyValue,
      scrollablePath: scrollable.path,
      scrollableTypeName: scrollable.typeName,
      pixelsBefore: pixelsBefore,
      pixelsAfter: position.pixels,
      nextPixels: nextPixels,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
      acceptsUserOffset: acceptsUserOffset,
      allowsProgrammaticScroll: allowsProgrammaticScroll,
      hadGestureTarget: false,
      hadSemanticAction: false,
      matchedRegistryTarget: false,
    );
    if ((nextPixels - position.pixels).abs() < 0.5) {
      return baseResult;
    }

    final semanticScrollAction = cockpitResolveSemanticScrollAction(
      axisDirection: position.axisDirection,
      forward: nextPixels > position.pixels,
    );
    final hadSemanticAction =
        !preferProgrammatic && semanticScrollAction != null;
    final scrollableTarget = _registryTargetForScrollableCandidate(scrollable);
    final scrollGeometry = scrollableTarget == null
        ? CockpitTargetGeometryResolver.maybeFromElement(scrollable.element)
        : null;
    if (!preferProgrammatic && scrollGeometry != null) {
      final initialPixels = position.pixels;
      try {
        await _gestureEngine
            .perform(
              CockpitGestureAction.drag(
                target: scrollableTarget,
                geometry: scrollGeometry,
                delta: _scrollDragDelta(
                  axisDirection: position.axisDirection,
                  distance: delta,
                  forward: nextPixels > position.pixels,
                ),
                duration: duration,
                moveEventCount: continuous ? 24 : 0,
                profile: gestureProfile,
                touchSlopX: cockpitDefaultDragTouchSlop,
                touchSlopY: cockpitDefaultDragTouchSlop,
              ),
            )
            .timeout(_scrollStepAnimationTimeout(duration));
        if (postScrollEnsureVisible) {
          await Future<void>.microtask(() {});
        }
        if ((position.pixels - initialPixels).abs() >= 0.5) {
          return CockpitScrollStepResult(
            didScroll: true,
            strategy: 'gesture',
            scrollableKey: scrollable.keyValue,
            scrollablePath: scrollable.path,
            scrollableTypeName: scrollable.typeName,
            pixelsBefore: pixelsBefore,
            pixelsAfter: position.pixels,
            nextPixels: nextPixels,
            minScrollExtent: position.minScrollExtent,
            maxScrollExtent: position.maxScrollExtent,
            viewportDimension: position.viewportDimension,
            acceptsUserOffset: acceptsUserOffset,
            allowsProgrammaticScroll: allowsProgrammaticScroll,
            hadGestureTarget: true,
            hadSemanticAction: false,
            matchedRegistryTarget: scrollableTarget != null,
          );
        }
      } on StateError {
        // Fall through to semantics or direct position adjustment.
      } on ArgumentError {
        // Fall through to semantics or direct position adjustment.
      } on TimeoutException {
        // Fall through to the bounded programmatic adjustment below.
      }
    }
    if (!preferProgrammatic && semanticScrollAction != null) {
      final initialPixels = position.pixels;
      final semanticAction = scrollable.semanticScrollActionHandler(
        semanticScrollAction,
      );
      if (semanticAction != null) {
        semanticAction();
        await Future<void>.microtask(() {});
        if ((position.pixels - initialPixels).abs() >= 0.5) {
          return CockpitScrollStepResult(
            didScroll: true,
            strategy: 'semantics',
            scrollableKey: scrollable.keyValue,
            scrollablePath: scrollable.path,
            scrollableTypeName: scrollable.typeName,
            pixelsBefore: pixelsBefore,
            pixelsAfter: position.pixels,
            nextPixels: nextPixels,
            minScrollExtent: position.minScrollExtent,
            maxScrollExtent: position.maxScrollExtent,
            viewportDimension: position.viewportDimension,
            acceptsUserOffset: acceptsUserOffset,
            allowsProgrammaticScroll: allowsProgrammaticScroll,
            hadGestureTarget:
                scrollGeometry != null || scrollableTarget != null,
            hadSemanticAction: true,
            matchedRegistryTarget: scrollableTarget != null,
          );
        }
      }
    }

    if (allowsProgrammaticScroll) {
      final initialPixels = position.pixels;
      try {
        if (preferProgrammatic ||
            duration == Duration.zero ||
            _isTestBinding(WidgetsBinding.instance)) {
          position.jumpTo(nextPixels);
          await Future<void>.microtask(() {});
          return CockpitScrollStepResult(
            didScroll: (position.pixels - initialPixels).abs() >= 0.5,
            strategy: 'jumpTo',
            scrollableKey: scrollable.keyValue,
            scrollablePath: scrollable.path,
            scrollableTypeName: scrollable.typeName,
            pixelsBefore: pixelsBefore,
            pixelsAfter: position.pixels,
            nextPixels: nextPixels,
            minScrollExtent: position.minScrollExtent,
            maxScrollExtent: position.maxScrollExtent,
            viewportDimension: position.viewportDimension,
            acceptsUserOffset: acceptsUserOffset,
            allowsProgrammaticScroll: allowsProgrammaticScroll,
            hadGestureTarget:
                scrollGeometry != null || scrollableTarget != null,
            hadSemanticAction: hadSemanticAction,
            matchedRegistryTarget: scrollableTarget != null,
          );
        }
        var animationTimedOut = false;
        try {
          await position
              .animateTo(
                nextPixels,
                duration: duration,
                curve: Curves.easeOutCubic,
              )
              .timeout(_scrollStepAnimationTimeout(duration));
        } on TimeoutException {
          animationTimedOut = true;
          position.jumpTo(nextPixels);
        }
        await Future<void>.microtask(() {});
        if ((position.pixels - initialPixels).abs() >= 0.5) {
          return CockpitScrollStepResult(
            didScroll: true,
            strategy: animationTimedOut ? 'jumpTo_timeout' : 'animateTo',
            scrollableKey: scrollable.keyValue,
            scrollablePath: scrollable.path,
            scrollableTypeName: scrollable.typeName,
            pixelsBefore: pixelsBefore,
            pixelsAfter: position.pixels,
            nextPixels: nextPixels,
            minScrollExtent: position.minScrollExtent,
            maxScrollExtent: position.maxScrollExtent,
            viewportDimension: position.viewportDimension,
            acceptsUserOffset: acceptsUserOffset,
            allowsProgrammaticScroll: allowsProgrammaticScroll,
            hadGestureTarget:
                scrollGeometry != null || scrollableTarget != null,
            hadSemanticAction: hadSemanticAction,
            matchedRegistryTarget: scrollableTarget != null,
          );
        }
        position.jumpTo(nextPixels);
        await Future<void>.microtask(() {});
        if ((position.pixels - initialPixels).abs() >= 0.5) {
          return CockpitScrollStepResult(
            didScroll: true,
            strategy: 'jumpTo',
            scrollableKey: scrollable.keyValue,
            scrollablePath: scrollable.path,
            scrollableTypeName: scrollable.typeName,
            pixelsBefore: pixelsBefore,
            pixelsAfter: position.pixels,
            nextPixels: nextPixels,
            minScrollExtent: position.minScrollExtent,
            maxScrollExtent: position.maxScrollExtent,
            viewportDimension: position.viewportDimension,
            acceptsUserOffset: acceptsUserOffset,
            allowsProgrammaticScroll: allowsProgrammaticScroll,
            hadGestureTarget:
                scrollGeometry != null || scrollableTarget != null,
            hadSemanticAction: hadSemanticAction,
            matchedRegistryTarget: scrollableTarget != null,
          );
        }
      } on StateError {
        // Ignore and fall back to reporting the scroll failure.
      } on ArgumentError {
        // Ignore and fall back to reporting the scroll failure.
      }
    }

    return CockpitScrollStepResult(
      didScroll: false,
      strategy: 'none',
      scrollableKey: scrollable.keyValue,
      scrollablePath: scrollable.path,
      scrollableTypeName: scrollable.typeName,
      pixelsBefore: pixelsBefore,
      pixelsAfter: position.pixels,
      nextPixels: nextPixels,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
      viewportDimension: position.viewportDimension,
      acceptsUserOffset: acceptsUserOffset,
      allowsProgrammaticScroll: allowsProgrammaticScroll,
      hadGestureTarget: scrollGeometry != null || scrollableTarget != null,
      hadSemanticAction: hadSemanticAction,
      matchedRegistryTarget: scrollableTarget != null,
    );
  }

  Duration _scrollStepAnimationTimeout(Duration duration) {
    return Duration(milliseconds: math.max(500, duration.inMilliseconds * 3));
  }

  CockpitScrollStepResult _withScrollableSelection(
    CockpitScrollStepResult result,
    _CockpitScrollableSelection selection, {
    required CockpitLocator? targetLocator,
    required bool targetMounted,
    bool? targetVisible,
  }) {
    return CockpitScrollStepResult(
      didScroll: result.didScroll,
      strategy: result.strategy,
      scrollableKey: result.scrollableKey,
      scrollablePath: result.scrollablePath,
      scrollableTypeName: result.scrollableTypeName,
      scrollableCandidateIndex: selection.index,
      scrollableCandidateCount: selection.count,
      pixelsBefore: result.pixelsBefore,
      pixelsAfter: result.pixelsAfter,
      nextPixels: result.nextPixels,
      minScrollExtent: result.minScrollExtent,
      maxScrollExtent: result.maxScrollExtent,
      viewportDimension: result.viewportDimension,
      acceptsUserOffset: result.acceptsUserOffset,
      allowsProgrammaticScroll: result.allowsProgrammaticScroll,
      hadGestureTarget: result.hadGestureTarget,
      hadSemanticAction: result.hadSemanticAction,
      matchedRegistryTarget: result.matchedRegistryTarget,
      targetVisibilityObserved: targetLocator != null,
      targetMounted: targetMounted || result.targetMounted,
      targetVisible: targetVisible ?? result.targetVisible,
    );
  }

  bool _locatorIsVisible(CockpitLocator? locator) {
    if (locator == null) {
      return false;
    }
    if (locator.kind == CockpitLocatorKind.route) {
      return widget.routeName == locator.value;
    }
    final rootContext = _boundaryKey.currentContext;
    if (rootContext is! Element) {
      return false;
    }
    final element = _findResolvedElementForLocator(rootContext, locator);
    if (element == null || !cockpitIsVisibleInRuntimeTree(element)) {
      return false;
    }
    final targetGeometry = CockpitTargetGeometryResolver.maybeFromElement(
      element,
    );
    final viewportGeometry = _viewportGeometry();
    if (targetGeometry == null || viewportGeometry == null) {
      return false;
    }
    final targetRect = Rect.fromLTWH(
      targetGeometry.left,
      targetGeometry.top,
      targetGeometry.width,
      targetGeometry.height,
    );
    final viewportRect = Rect.fromLTWH(
      viewportGeometry.left,
      viewportGeometry.top,
      viewportGeometry.width,
      viewportGeometry.height,
    );
    if (!_rectContainsRect(viewportRect, targetRect)) {
      return false;
    }
    return _isFullyVisibleInScrollableAncestors(element, targetRect);
  }

  Element? _findResolvedElementForLocator(
    Element rootElement,
    CockpitLocator locator,
  ) {
    final localMatch = _findMountedElementForLocator(rootElement, locator);
    if (localMatch != null) {
      return localMatch;
    }
    if (!_requiresLogicalTargetResolution(locator)) {
      return null;
    }
    final resolution = _registry.resolve(locator);
    final resolvedNode = resolution.target?.diagnosticNodeProvider?.call();
    return switch (resolvedNode) {
      final Element element when resolution.isSuccess && element.mounted =>
        element,
      _ => null,
    };
  }

  bool _requiresLogicalTargetResolution(CockpitLocator locator) {
    if (locator.signalMap.length < 2) {
      return false;
    }
    return locator.cockpitId != null ||
        locator.semanticId != null ||
        locator.key != null;
  }

  bool _isFullyVisibleInScrollableAncestors(Element element, Rect targetRect) {
    RenderObject? renderObject = element.findRenderObject();
    final visited = <RenderObject>{};
    while (renderObject != null && visited.add(renderObject)) {
      if (renderObject is RenderAbstractViewport && renderObject is RenderBox) {
        final viewport = renderObject as RenderBox;
        if (!viewport.attached || !viewport.hasSize) {
          return false;
        }
        final viewportRect =
            viewport.localToGlobal(Offset.zero) & viewport.size;
        if (!_rectContainsRect(viewportRect, targetRect)) {
          return false;
        }
      }
      renderObject = renderObject.parent;
    }
    return true;
  }

  bool _rectContainsRect(Rect viewport, Rect target) {
    const tolerance = 0.5;
    return target.left >= viewport.left - tolerance &&
        target.top >= viewport.top - tolerance &&
        target.right <= viewport.right + tolerance &&
        target.bottom <= viewport.bottom + tolerance;
  }

  CockpitTarget? _registryTargetForScrollableCandidate(
    _CockpitScrollableCandidate candidate,
  ) {
    final matches = _registry.visibleTargets
        .where((target) {
          if (!_matchesTypeSignal(target.typeName, candidate.typeName)) {
            return false;
          }
          if (candidate.keyValue != null &&
              candidate.keyValue!.isNotEmpty &&
              target.keyValue != candidate.keyValue) {
            return false;
          }
          if (!_matchesPath(target.path, candidate.path)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }
    matches.sort((left, right) {
      final leftGeometry = left.geometryProvider?.call();
      final rightGeometry = right.geometryProvider?.call();
      final geometryCompare = (rightGeometry != null ? 1 : 0).compareTo(
        leftGeometry != null ? 1 : 0,
      );
      if (geometryCompare != 0) {
        return geometryCompare;
      }
      return (right.path ?? '').length.compareTo((left.path ?? '').length);
    });
    return matches.first;
  }

  Element? _findMountedElementForLocator(
    Element rootElement,
    CockpitLocator locator,
  ) {
    for (final candidate in _flatten(locator)) {
      final probe = _probeForLocator(
        rootElement,
        candidate,
        fallbackLocator: _stableTextKeyFallback(candidate),
      );
      if (probe.element case final element?) {
        return element;
      }
    }
    return null;
  }

  CockpitLocator? _stableTextKeyFallback(CockpitLocator locator) {
    final text = locator.text;
    if (text == null ||
        locator.signalMap.length != 1 ||
        locator.matchMode != CockpitTextMatchMode.exact) {
      return null;
    }
    return CockpitLocator(
      key: text,
      ancestor: locator.ancestor,
      index: locator.index,
    );
  }

  Iterable<CockpitLocator> _flatten(CockpitLocator locator) sync* {
    yield locator;
    for (final fallback in locator.fallbacks) {
      yield* _flatten(fallback);
    }
  }

  _CockpitMountedLocatorProbe _probeForLocator(
    Element rootElement,
    CockpitLocator locator, {
    bool visibleOnly = false,
    CockpitLocator? fallbackLocator,
  }) {
    final matchesByRenderObject = <Object, ({Element element, int score})>{};
    final fallbackMatchesByRenderObject =
        <Object, ({Element element, int score})>{};

    void recordMatch(
      Map<Object, ({Element element, int score})> matches,
      Element element,
      int score,
    ) {
      if (score < 0 || (visibleOnly && !_elementIsFullyVisible(element))) {
        return;
      }
      final identity = element.findRenderObject() ?? element;
      final current = matches[identity];
      if (current == null || score > current.score) {
        matches[identity] = (element: element, score: score);
      }
    }

    void visit(Element element) {
      if (!element.mounted ||
          cockpitHidesRuntimeSubtree(element) ||
          widget.discoveryPolicy.ignoresSubtree(element)) {
        return;
      }
      recordMatch(
        matchesByRenderObject,
        element,
        _locatorMatchScore(element, locator),
      );
      if (fallbackLocator != null) {
        recordMatch(
          fallbackMatchesByRenderObject,
          element,
          _locatorMatchScore(element, fallbackLocator),
        );
      }
      if (visibleOnly) {
        element.debugVisitOnstageChildren(visit);
      } else {
        element.visitChildElements(visit);
      }
    }

    visit(rootElement);
    final primary = _resolveMountedLocatorProbe(matchesByRenderObject, locator);
    if (primary.element != null ||
        primary.ambiguous ||
        fallbackLocator == null) {
      return primary;
    }
    return _resolveMountedLocatorProbe(
      fallbackMatchesByRenderObject,
      fallbackLocator,
    );
  }

  _CockpitMountedLocatorProbe _resolveMountedLocatorProbe(
    Map<Object, ({Element element, int score})> matchesByRenderObject,
    CockpitLocator locator,
  ) {
    final matches = matchesByRenderObject.values.toList(growable: false);
    if (matches.isEmpty) return const _CockpitMountedLocatorProbe();
    final index = locator.index;
    if (index != null) {
      return _CockpitMountedLocatorProbe(
        element: index < matches.length ? matches[index].element : null,
        matchCount: matches.length,
      );
    }
    final bestScore = matches
        .map((candidate) => candidate.score)
        .reduce((left, right) => left > right ? left : right);
    final bestMatches = matches
        .where((candidate) => candidate.score == bestScore)
        .toList(growable: false);
    if (bestMatches.length == 1) {
      return _CockpitMountedLocatorProbe(
        element: bestMatches.single.element,
        matchCount: bestMatches.length,
      );
    }

    // A single logical control commonly repeats its label through a Semantics
    // container and one or more descendant Text widgets. Collapse only when
    // one matching ancestor contains every equal match. Equal matches in
    // separate controls remain ambiguous.
    for (final candidate in bestMatches) {
      final isSharedMatchingAncestor = bestMatches.every(
        (other) =>
            identical(candidate.element, other.element) ||
            _isElementAncestor(candidate.element, other.element),
      );
      if (isSharedMatchingAncestor) {
        return _CockpitMountedLocatorProbe(
          element: candidate.element,
          matchCount: bestMatches.length,
        );
      }
    }
    return _CockpitMountedLocatorProbe(
      ambiguous: true,
      matchCount: bestMatches.length,
    );
  }

  CockpitTargetResolutionResult _probeTargetForElement(
    Element element, {
    required Element rootContext,
    CockpitCommandType? requiredCommand,
    bool allowGestureFallback = false,
  }) {
    final semanticId = _elementSemanticSignal(element);
    final keyValue = _stableKeyValue(element.widget.key);
    final probeTarget = CockpitTarget(
      registrationId: 'probe:${identityHashCode(element)}',
      cockpitId: semanticId ?? keyValue,
      semanticId: semanticId,
      keyValue: keyValue,
      text: _elementTextSignal(element),
      tooltip: _elementTooltipSignal(element),
      typeName: element.widget.runtimeType.toString(),
      path: _locatorPathForElement(element),
      routeName: widget.routeName,
      supportedCommands: allowGestureFallback && requiredCommand != null
          ? <CockpitCommandType>{requiredCommand}
          : const <CockpitCommandType>{},
      locatorAncestors: _extractLocatorAncestors(element),
      diagnosticNodeProvider: () => element,
      geometryProvider: () =>
          CockpitTargetGeometryResolver.maybeFromElement(element),
    );
    if (requiredCommand == null) {
      return CockpitTargetResolutionResult.success(target: probeTarget);
    }
    final relatedTargets = _relatedActionTargets(
      element,
      rootContext: rootContext,
      requiredCommand: requiredCommand,
    );
    if (relatedTargets.isEmpty) {
      return CockpitTargetResolutionResult.success(target: probeTarget);
    }

    final closestDistance = relatedTargets.first.distance;
    final closest = relatedTargets
        .takeWhile((candidate) => candidate.distance == closestDistance)
        .map((candidate) => candidate.target)
        .toList(growable: false);
    if (closest.length > 1) {
      return CockpitTargetResolutionResult.failure(
        error: CockpitCommandError.ambiguousTarget(
          message:
              'Multiple actionable Flutter controls are equally related to the matched element.',
          details: <String, Object?>{
            'candidateCount': closest.length,
            'candidates': closest
                .map((target) => target.registrationId)
                .toList(growable: false),
          },
        ),
        matches: closest,
      );
    }

    final actionTarget = closest.single;
    return CockpitTargetResolutionResult.success(
      target: _mergeProbeIdentity(probeTarget, actionTarget),
      matches: closest,
    );
  }

  bool _allowsExplicitGestureFallback(
    CockpitLocator locator,
    CockpitCommandType? requiredCommand,
  ) {
    if (requiredCommand != CockpitCommandType.tap &&
        requiredCommand != CockpitCommandType.longPress &&
        requiredCommand != CockpitCommandType.doubleTap) {
      return false;
    }
    return locator.type != null ||
        locator.path != null ||
        locator.ancestor != null ||
        locator.cockpitId != null ||
        locator.semanticId != null ||
        locator.key != null ||
        locator.tooltip != null;
  }

  List<({CockpitTarget target, int distance})> _relatedActionTargets(
    Element element, {
    required Element rootContext,
    required CockpitCommandType requiredCommand,
  }) {
    final candidates = <({CockpitTarget target, int distance})>[];
    final seenElements = <Element>{};
    final routeName = _registry.routeName;
    final targets = <CockpitTarget>[
      ..._registry.registeredTargets,
      ..._discoveryEngine.discoverRelatedActionTargets(
        rootContext: rootContext,
        element: element,
        routeName: routeName,
        requiredCommand: requiredCommand,
        explicitTargets: _registry.registeredTargets,
      ),
    ];
    for (final target in targets) {
      if (!target.isVisible ||
          (routeName != null &&
              routeName.isNotEmpty &&
              target.routeName != routeName)) {
        continue;
      }
      if (!target.supportedCommands.contains(requiredCommand)) {
        continue;
      }
      final targetElement = target.diagnosticNodeProvider?.call();
      if (targetElement is! Element ||
          !targetElement.mounted ||
          !seenElements.add(targetElement)) {
        continue;
      }
      final distance = _relatedElementDistance(element, targetElement);
      if (distance != null) {
        candidates.add((target: target, distance: distance));
      }
    }
    candidates.sort((left, right) {
      final distanceCompare = left.distance.compareTo(right.distance);
      if (distanceCompare != 0) return distanceCompare;
      return left.target.registrationId.compareTo(right.target.registrationId);
    });
    return candidates;
  }

  int? _relatedElementDistance(Element matched, Element candidate) {
    if (identical(matched, candidate)) return 0;

    var distance = 0;
    int? result;
    candidate.visitAncestorElements((ancestor) {
      distance += 1;
      if (identical(ancestor, matched)) {
        result = distance;
        return false;
      }
      return true;
    });
    if (result != null) return result;

    distance = 0;
    matched.visitAncestorElements((ancestor) {
      distance += 1;
      if (identical(ancestor, candidate)) {
        result = distance;
        return false;
      }
      return true;
    });
    return result;
  }

  CockpitTarget _mergeProbeIdentity(CockpitTarget probe, CockpitTarget action) {
    return CockpitTarget(
      registrationId: action.registrationId,
      cockpitId: probe.cockpitId ?? action.cockpitId,
      semanticId: probe.semanticId ?? action.semanticId,
      keyValue: probe.keyValue ?? action.keyValue,
      text: probe.text ?? action.text,
      textParts: <String>{...probe.textParts, ...action.textParts},
      tooltip: probe.tooltip ?? action.tooltip,
      typeName: probe.typeName ?? action.typeName,
      path: probe.path ?? action.path,
      scrollablePath: action.scrollablePath,
      scrollableKeyValue: action.scrollableKeyValue,
      scrollableTypeName: action.scrollableTypeName,
      routeName: action.routeName,
      supportedCommands: action.supportedCommands,
      control: action.control,
      locatorAncestors: probe.locatorAncestors,
      onTap: action.onTap,
      onLongPress: action.onLongPress,
      onDoubleTap: action.onDoubleTap,
      onEnterText: action.onEnterText,
      onTextInput: action.onTextInput,
      onSemanticTap: action.onSemanticTap,
      onSemanticLongPress: action.onSemanticLongPress,
      onSemanticEnterText: action.onSemanticEnterText,
      onSemanticTextInput: action.onSemanticTextInput,
      onSemanticShowOnScreen: action.onSemanticShowOnScreen,
      onSemanticIncrease: action.onSemanticIncrease,
      onSemanticDecrease: action.onSemanticDecrease,
      onSemanticDismiss: action.onSemanticDismiss,
      diagnosticNodeProvider: action.diagnosticNodeProvider,
      geometryProvider: action.geometryProvider,
    );
  }

  Map<String, String> _matchedLocatorSignals(CockpitLocator locator) {
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

  bool _elementIsFullyVisible(Element element) {
    if (!cockpitIsVisibleInRuntimeTree(element)) {
      return false;
    }
    final targetGeometry = CockpitTargetGeometryResolver.maybeFromElement(
      element,
    );
    final viewportGeometry = _viewportGeometry();
    if (targetGeometry == null || viewportGeometry == null) {
      return false;
    }
    final targetRect = Rect.fromLTWH(
      targetGeometry.left,
      targetGeometry.top,
      targetGeometry.width,
      targetGeometry.height,
    );
    final viewportRect = Rect.fromLTWH(
      viewportGeometry.left,
      viewportGeometry.top,
      viewportGeometry.width,
      viewportGeometry.height,
    );
    return _rectContainsRect(viewportRect, targetRect) &&
        _isFullyVisibleInScrollableAncestors(element, targetRect);
  }

  bool _isElementAncestor(Element ancestor, Element descendant) {
    var matched = false;
    descendant.visitAncestorElements((candidate) {
      if (identical(candidate, ancestor)) {
        matched = true;
        return false;
      }
      return true;
    });
    return matched;
  }

  int _locatorMatchScore(Element element, CockpitLocator locator) {
    if (!_matchesElementLocator(element, locator)) {
      return -1;
    }

    var score = locator.signalMap.length * 10;
    final pathSignal = locator.path;
    if (pathSignal != null) {
      score += _pathMatchPriorityScore(
        _locatorPathForElement(element),
        pathSignal,
      );
    }
    final keyValue = _stableKeyValue(element.widget.key);
    if (locator.key != null && keyValue != null) {
      score += 8;
    }
    if (locator.text case final expectedText?) {
      score += _textMatchPriorityScore(
        _elementTextSignal(element),
        expectedText,
        locator.matchMode,
      );
    }
    if (locator.tooltip case final expectedTooltip?) {
      score += _textMatchPriorityScore(
        _elementTooltipSignal(element),
        expectedTooltip,
        locator.matchMode,
      );
    }
    if (locator.semanticId case final expectedSemanticId?) {
      score += _textMatchPriorityScore(
        _elementSemanticSignal(element),
        expectedSemanticId,
        locator.matchMode,
      );
    }
    if (locator.ancestor != null) {
      score += 2;
    }
    return score;
  }

  bool _matchesElementLocator(Element element, CockpitLocator locator) {
    if (!locator.hasSignals) {
      return false;
    }
    for (final signal in locator.signals) {
      if (!_matchesElementSignal(
        element,
        signal.kind,
        signal.value,
        locator.matchMode,
      )) {
        return false;
      }
    }
    final ancestor = locator.ancestor;
    if (ancestor != null &&
        !_matchesAncestorChain(_extractLocatorAncestors(element), ancestor)) {
      return false;
    }
    return true;
  }

  bool _matchesElementSignal(
    Element element,
    CockpitLocatorKind kind,
    String value,
    CockpitTextMatchMode matchMode,
  ) {
    return switch (kind) {
      CockpitLocatorKind.ref => false,
      CockpitLocatorKind.cockpitId =>
        _stableKeyValue(element.widget.key) == value ||
            _matchesTextSignal(
              _elementSemanticSignal(element),
              value,
              CockpitTextMatchMode.exact,
            ),
      CockpitLocatorKind.semanticId => _matchesTextSignal(
        _elementSemanticSignal(element),
        value,
        matchMode,
      ),
      CockpitLocatorKind.key => _stableKeyValue(element.widget.key) == value,
      CockpitLocatorKind.text => _matchesTextSignal(
        _elementTextSignal(element),
        value,
        matchMode,
      ),
      CockpitLocatorKind.tooltip => _matchesTextSignal(
        _elementTooltipSignal(element),
        value,
        matchMode,
      ),
      CockpitLocatorKind.type => _matchesTypeSignal(
        element.widget.runtimeType.toString(),
        value,
      ),
      CockpitLocatorKind.route => widget.routeName == value,
      CockpitLocatorKind.registrationId => false,
      CockpitLocatorKind.path => _matchesPath(
        _locatorPathForElement(element),
        value,
      ),
      CockpitLocatorKind.nativeId ||
      CockpitLocatorKind.testId ||
      CockpitLocatorKind.role ||
      CockpitLocatorKind.coordinate ||
      CockpitLocatorKind.visual => false,
    };
  }

  String? _elementTextSignal(Element element) {
    return _textPreviewForAncestor(element);
  }

  String? _elementSemanticSignal(Element element) {
    final widget = element.widget;
    if (widget is! Semantics || _isExcludedFromSemantics(element)) {
      return null;
    }
    return _normalizeText(
      widget.properties.identifier ??
          widget.properties.label ??
          widget.properties.value ??
          widget.properties.hint,
    );
  }

  bool _isExcludedFromSemantics(Element element) {
    var excluded = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is ExcludeSemantics) {
        excluded = true;
        return false;
      }
      return true;
    });
    return excluded;
  }

  String? _elementTooltipSignal(Element element) {
    String? fromWidget(Widget widget) {
      if (widget is Tooltip) {
        return _normalizeText(widget.message);
      }
      if (widget is Semantics) {
        return _normalizeText(widget.properties.tooltip);
      }
      return null;
    }

    final ownTooltip = fromWidget(element.widget);
    if (ownTooltip != null) {
      return ownTooltip;
    }
    String? inheritedTooltip;
    element.visitAncestorElements((ancestor) {
      inheritedTooltip = fromWidget(ancestor.widget);
      return inheritedTooltip == null;
    });
    return inheritedTooltip;
  }

  _CockpitScrollableSelection? _selectScrollableCandidate(
    List<_CockpitScrollableCandidate> candidates, {
    CockpitLocator? targetLocator,
    Element? targetElement,
    CockpitLocator? scrollableLocator,
  }) {
    final indexOnlyLocator =
        scrollableLocator != null &&
        !scrollableLocator.hasSignals &&
        scrollableLocator.index != null;
    final matchingScrollableCandidates =
        scrollableLocator == null || indexOnlyLocator
        ? candidates
        : candidates
              .where(
                (candidate) =>
                    _scrollableLocatorMatchScore(candidate, scrollableLocator) >
                    0,
              )
              .toList(growable: false);
    if (matchingScrollableCandidates.isEmpty) {
      return null;
    }

    final targetScrollableCandidates = targetElement == null
        ? const <_CockpitScrollableCandidate>[]
        : matchingScrollableCandidates
              .where(
                (candidate) =>
                    _targetScrollableDistance(targetElement, candidate) != null,
              )
              .toList(growable: false);
    final ordered =
        (targetScrollableCandidates.isEmpty
                ? matchingScrollableCandidates
                : targetScrollableCandidates)
            .toList(growable: false)
          ..sort((left, right) {
            if (targetElement != null) {
              final distanceCompare =
                  (_targetScrollableDistance(targetElement, left) ?? 1 << 30)
                      .compareTo(
                        _targetScrollableDistance(targetElement, right) ??
                            1 << 30,
                      );
              if (distanceCompare != 0) {
                return distanceCompare;
              }
            }
            final rightScore = _scrollablePriorityScore(
              right,
              targetLocator: targetLocator,
              scrollableLocator: scrollableLocator,
            );
            final leftScore = _scrollablePriorityScore(
              left,
              targetLocator: targetLocator,
              scrollableLocator: scrollableLocator,
            );
            final scoreCompare = rightScore.compareTo(leftScore);
            if (scoreCompare != 0) {
              return scoreCompare;
            }

            final maxExtentCompare = right.state.position.maxScrollExtent
                .compareTo(left.state.position.maxScrollExtent);
            if (maxExtentCompare != 0) {
              return maxExtentCompare;
            }

            final viewportCompare = right.state.position.viewportDimension
                .compareTo(left.state.position.viewportDimension);
            if (viewportCompare != 0) {
              return viewportCompare;
            }
            return right.depth.compareTo(left.depth);
          });
    if (scrollableLocator?.index case final index?) {
      if (index < 0 || index >= ordered.length) {
        return null;
      }
      return _CockpitScrollableSelection(
        candidate: ordered[index],
        index: index,
        count: ordered.length,
      );
    }
    return _CockpitScrollableSelection(
      candidate: ordered.first,
      index: 0,
      count: ordered.length,
    );
  }

  int? _targetScrollableDistance(
    Element target,
    _CockpitScrollableCandidate candidate,
  ) {
    if (identical(target, candidate.element) ||
        identical(target, candidate.semanticsElement)) {
      return 0;
    }

    int? match;
    var distance = 1;
    target.visitAncestorElements((ancestor) {
      if (identical(ancestor, candidate.semanticsElement) ||
          identical(ancestor, candidate.element)) {
        match = distance;
        return false;
      }
      distance += 1;
      return true;
    });
    return match;
  }

  Offset _scrollDragDelta({
    required AxisDirection axisDirection,
    required double distance,
    required bool forward,
  }) {
    return switch ((axisDirection, forward)) {
      (AxisDirection.down, true) => Offset(0, -distance),
      (AxisDirection.down, false) => Offset(0, distance),
      (AxisDirection.up, true) => Offset(0, distance),
      (AxisDirection.up, false) => Offset(0, -distance),
      (AxisDirection.right, true) => Offset(-distance, 0),
      (AxisDirection.right, false) => Offset(distance, 0),
      (AxisDirection.left, true) => Offset(distance, 0),
      (AxisDirection.left, false) => Offset(-distance, 0),
    };
  }

  List<_CockpitScrollableCandidate> _discoverScrollables(Element rootElement) {
    final candidates = <_CockpitScrollableCandidate>[];
    final policy = widget.discoveryPolicy;

    void visit(Element element, int depth) {
      if (!element.mounted ||
          cockpitHidesRuntimeSubtree(element) ||
          policy.ignoresSubtree(element)) {
        return;
      }
      if (element is StatefulElement && element.state is ScrollableState) {
        final locatorBoundary = _scrollableLocatorBoundary(element);
        candidates.add(
          _CockpitScrollableCandidate(
            state: element.state as ScrollableState,
            depth: depth,
            keyValue: _scrollableKeyValue(locatorBoundary),
            typeName: _scrollableLocatorTypeName(
              locatorBoundary,
              fallbackElement: element,
            ),
            path: _locatorPathForElement(locatorBoundary),
            locatorAncestors: _extractLocatorAncestors(locatorBoundary),
            element: locatorBoundary,
            semanticsElement: element,
          ),
        );
        if (policy.marksScrollableBoundary(element)) {
          return;
        }
      }
      if (policy.stopsTraversal(element)) {
        return;
      }

      element.visitChildElements((child) => visit(child, depth + 1));
    }

    if (cockpitIsVisibleInRuntimeTree(rootElement)) {
      visit(rootElement, 0);
    }
    return candidates;
  }

  List<_CockpitScrollableCandidate> _scrollableCandidatesForSearch(
    Element rootElement, {
    required CockpitLocator? targetLocator,
    required Element? targetElement,
  }) {
    final canReuse =
        targetLocator != null &&
        identical(_scrollDiscoveryRoot, rootElement) &&
        identical(_scrollDiscoveryLocator, targetLocator) &&
        !(targetElement != null && !_scrollDiscoveryTargetWasMounted);
    if (canReuse) {
      final mountedCandidates = _scrollDiscoveryCandidates
          .where(
            (candidate) =>
                candidate.element.mounted &&
                cockpitIsVisibleInRuntimeTree(candidate.element),
          )
          .toList(growable: false);
      if (mountedCandidates.length == _scrollDiscoveryCandidates.length) {
        _scrollDiscoveryTargetWasMounted = targetElement != null;
        return mountedCandidates;
      }
    }

    final candidates = _discoverScrollables(rootElement);
    if (targetLocator == null) {
      _clearScrollDiscoveryCache();
      return candidates;
    }
    _scrollDiscoveryRoot = rootElement;
    _scrollDiscoveryLocator = targetLocator;
    _scrollDiscoveryCandidates = candidates;
    _scrollDiscoveryTargetWasMounted = targetElement != null;
    return candidates;
  }

  void _clearScrollDiscoveryCache() {
    _scrollDiscoveryRoot = null;
    _scrollDiscoveryLocator = null;
    _scrollDiscoveryCandidates = const <_CockpitScrollableCandidate>[];
    _scrollDiscoveryTargetWasMounted = false;
  }

  String? _stableKeyValue(Key? key) {
    return switch (key) {
      ValueKey<Object?>(value: final value) => _stableKeyPayload(value),
      ObjectKey(value: final value) => _stableKeyPayload(value),
      _ => null,
    };
  }

  String? _stableKeyPayload(Object? value) {
    if (value == null || value.runtimeType.toString().startsWith('_')) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _scrollableKeyValue(Element element) {
    return _stableKeyValue(element.widget.key);
  }

  Element _scrollableLocatorBoundary(Element element) {
    if (_isSemanticScrollableBoundary(element)) {
      return element;
    }

    Element? boundary;
    element.visitAncestorElements((ancestor) {
      if (_isSemanticScrollableBoundary(ancestor)) {
        boundary = ancestor;
        return false;
      }
      return true;
    });
    if (boundary != null) {
      return boundary!;
    }
    return _semanticScrollableBoundaryInSubtree(element) ?? element;
  }

  Element? _semanticScrollableBoundaryInSubtree(Element element) {
    if (_isSemanticScrollableBoundary(element)) {
      return element;
    }

    Element? match;

    void visit(Element candidate) {
      if (match != null || !candidate.mounted) {
        return;
      }
      if (_isSemanticScrollableBoundary(candidate)) {
        match = candidate;
        return;
      }
      candidate.visitChildElements(visit);
    }

    element.visitChildElements(visit);
    return match;
  }

  bool _isSemanticScrollableBoundary(Element element) {
    if (widget.discoveryPolicy.marksScrollableBoundary(element)) {
      return true;
    }
    final normalizedType = _normalizeTypeName(
      element.widget.runtimeType.toString(),
    );
    return normalizedType != null &&
        _semanticScrollableTypeNames.contains(normalizedType);
  }

  String _scrollableLocatorTypeName(
    Element element, {
    required Element fallbackElement,
  }) {
    final typeName = element.widget.runtimeType.toString();
    if (_isSemanticScrollableBoundary(element) && typeName != 'Scrollable') {
      return typeName;
    }
    return _scrollableTypeName(fallbackElement);
  }

  String _scrollableTypeName(Element element) {
    final ownType = element.widget.runtimeType.toString();
    if (ownType != 'Scrollable') {
      return ownType;
    }
    final pathHint = _scrollableTypeNameFromPath(
      _locatorPathForElement(element),
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

  String _locatorPathForElement(Element element) {
    final segments = <String>[];
    final chain = <Element>[element];
    element.visitAncestorElements((ancestor) {
      chain.add(ancestor);
      return true;
    });
    for (final candidate in chain.reversed) {
      if (_shouldSkipPathElement(candidate)) {
        continue;
      }
      final segment = _locatorPathSegment(
        candidate.widget.runtimeType.toString(),
      );
      if (segment == null) {
        continue;
      }
      segments.add(segment);
    }
    final trimmedSegments = _trimMeaningfulPathSegments(segments);
    if (trimmedSegments.isEmpty) {
      return '/scrollable';
    }
    return '/${trimmedSegments.join('/')}';
  }

  List<CockpitSnapshotAncestor> _extractLocatorAncestors(Element element) {
    final ancestors = <CockpitSnapshotAncestor>[];
    element.visitAncestorElements((ancestor) {
      if (_shouldSkipAncestorElement(ancestor)) {
        return true;
      }
      final keyValue = _stableKeyValue(ancestor.widget.key);
      final semanticId = _semanticIdForAncestor(ancestor);
      ancestors.add(
        CockpitSnapshotAncestor(
          typeName: ancestor.widget.runtimeType.toString(),
          cockpitId: semanticId ?? keyValue,
          semanticId: semanticId,
          keyValue: keyValue,
          textPreview: _textPreviewForAncestor(ancestor),
          tooltip: _tooltipForAncestor(ancestor),
          routeName: widget.routeName,
          path: _locatorPathForElement(ancestor),
        ),
      );
      return true;
    });
    return List<CockpitSnapshotAncestor>.unmodifiable(ancestors);
  }

  bool _shouldSkipAncestorElement(Element ancestor) {
    final widget = ancestor.widget;
    final typeName = widget.runtimeType.toString();
    if (typeName.startsWith('_')) {
      return true;
    }
    return widget is InheritedWidget ||
        widget is ParentDataWidget<ParentData> ||
        widget is Focus ||
        widget is Semantics ||
        widget is IgnorePointer ||
        widget is MouseRegion ||
        widget is ExcludeSemantics ||
        widget is MergeSemantics;
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

  String? _locatorPathSegment(String typeName) {
    if (typeName.startsWith('_')) {
      return null;
    }
    final slug = _slugify(typeName).replaceAll('-', '');
    return slug.isEmpty ? null : slug;
  }

  String _slugify(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.toLowerCase().codeUnits) {
      final isAlphaNumeric =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 97 && codeUnit <= 122);
      if (isAlphaNumeric) {
        buffer.writeCharCode(codeUnit);
      } else if (buffer.isEmpty || buffer.toString().endsWith('-')) {
        continue;
      } else {
        buffer.write('-');
      }
    }
    final slug = buffer.toString().replaceAll(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'value' : slug;
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

  String? _textPreviewForAncestor(Element element) {
    final widget = element.widget;
    if (widget is Text) {
      return _normalizeText(widget.data ?? widget.textSpan?.toPlainText());
    }
    if (widget is RichText) {
      return _normalizeText(widget.text.toPlainText());
    }
    if (widget is Semantics) {
      return _normalizeText(
        widget.properties.label ??
            widget.properties.value ??
            widget.properties.hint,
      );
    }
    return null;
  }

  String? _semanticIdForAncestor(Element element) {
    final widget = element.widget;
    if (widget is Semantics) {
      return _normalizeText(
        widget.properties.identifier ??
            widget.properties.label ??
            widget.properties.value ??
            widget.properties.hint,
      );
    }
    return null;
  }

  String? _tooltipForAncestor(Element element) {
    final widget = element.widget;
    if (widget.runtimeType.toString() == 'Tooltip') {
      final dynamic tooltip = widget;
      return _normalizeText(tooltip.message as String?);
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

  String? _normalizeTypeName(String? value) {
    final normalized = _normalizeText(value)?.toLowerCase();
    if (normalized == null) {
      return null;
    }
    final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return compact.isEmpty ? null : compact;
  }

  bool _scrollableMatchesLocator(
    _CockpitScrollableCandidate candidate,
    CockpitLocator locator,
  ) {
    if (!locator.hasSignals) {
      return false;
    }
    for (final signal in locator.signals) {
      final matched = switch (signal.kind) {
        CockpitLocatorKind.key => candidate.keyValue == signal.value,
        CockpitLocatorKind.type => _matchesTypeSignal(
          candidate.typeName,
          signal.value,
        ),
        CockpitLocatorKind.path => _matchesPath(candidate.path, signal.value),
        CockpitLocatorKind.route => widget.routeName == signal.value,
        CockpitLocatorKind.text => _matchesTextSignal(
          candidate.textPreview,
          signal.value,
          locator.matchMode,
        ),
        CockpitLocatorKind.cockpitId =>
          candidate.keyValue == signal.value ||
              _matchesTextSignal(
                candidate.textPreview,
                signal.value,
                CockpitTextMatchMode.exact,
              ),
        CockpitLocatorKind.ref ||
        CockpitLocatorKind.semanticId ||
        CockpitLocatorKind.tooltip ||
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
    final ancestor = locator.ancestor;
    if (ancestor != null &&
        !_matchesAncestorChain(candidate.locatorAncestors, ancestor)) {
      return false;
    }
    return true;
  }

  int _scrollablePriorityScore(
    _CockpitScrollableCandidate candidate, {
    CockpitLocator? targetLocator,
    CockpitLocator? scrollableLocator,
  }) {
    var score = 0;
    if (scrollableLocator != null) {
      score += _scrollableLocatorMatchScore(candidate, scrollableLocator);
    }

    if (targetLocator != null) {
      score += _scrollableTargetContextScore(candidate, targetLocator);
      final targetPath = targetLocator.path;
      if (targetPath != null) {
        if (_pathContainsScrollable(candidate.path, targetPath)) {
          score += 80;
        } else {
          score += _pathMatchPriorityScore(candidate.path, targetPath);
        }
      }
      final targetAncestor = targetLocator.ancestor;
      if (targetAncestor != null &&
          (_scrollableMatchesLocator(candidate, targetAncestor) ||
              _matchesAncestorChain(
                candidate.locatorAncestors,
                targetAncestor,
              ))) {
        score += 60;
      }
    }

    if (candidate.keyValue != null && candidate.keyValue!.isNotEmpty) {
      score += 10;
    }
    return score;
  }

  int _scrollableTargetContextScore(
    _CockpitScrollableCandidate candidate,
    CockpitLocator targetLocator,
  ) {
    const maxVisitedElements = 1200;
    var visitedElements = 0;
    var bestScore = 0;

    void visit(Element element) {
      if (!element.mounted || visitedElements >= maxVisitedElements) {
        return;
      }
      visitedElements += 1;
      for (final locator in _flatten(targetLocator)) {
        bestScore = math.max(
          bestScore,
          _elementTargetContextScore(element, locator),
        );
      }
      if (bestScore < 160) {
        element.visitChildElements(visit);
      }
    }

    visit(candidate.element);
    return bestScore;
  }

  int _elementTargetContextScore(Element element, CockpitLocator locator) {
    var score = 0;
    final keyValue = _stableKeyValue(element.widget.key);
    final semanticSignal = _elementSemanticSignal(element);
    final textSignal = _elementTextSignal(element);
    final tooltipSignal = _elementTooltipSignal(element);

    if (locator.cockpitId case final expected?) {
      if (keyValue == expected ||
          _normalizedContains(semanticSignal, expected) ||
          _normalizedContains(textSignal, expected)) {
        score = math.max(score, 160);
      }
    }
    if (locator.semanticId case final expected?) {
      if (_normalizedContains(semanticSignal, expected)) {
        score = math.max(score, 160);
      }
    }
    if (locator.key case final expected?) {
      if (keyValue == expected) {
        score = math.max(score, 160);
      }
    }
    if (locator.text case final expected?) {
      score = math.max(score, _targetTextContextScore(textSignal, expected));
      score = math.max(
        score,
        _targetTextContextScore(semanticSignal, expected),
      );
    }
    if (locator.tooltip case final expected?) {
      score = math.max(score, _targetTextContextScore(tooltipSignal, expected));
    }
    if (locator.type case final expected?) {
      if (_matchesTypeSignal(element.widget.runtimeType.toString(), expected)) {
        score = math.max(score, 32);
      }
    }
    return score;
  }

  int _targetTextContextScore(String? candidate, String expected) {
    final normalizedCandidate = _normalizeText(candidate)?.toLowerCase();
    final normalizedExpected = _normalizeText(expected)?.toLowerCase();
    if (normalizedCandidate == null || normalizedExpected == null) {
      return 0;
    }
    if (normalizedCandidate == normalizedExpected) {
      return 144;
    }
    if (normalizedCandidate.contains(normalizedExpected) ||
        normalizedExpected.contains(normalizedCandidate)) {
      return 96;
    }
    return 0;
  }

  bool _normalizedContains(String? candidate, String expected) {
    final normalizedCandidate = _normalizeText(candidate)?.toLowerCase();
    final normalizedExpected = _normalizeText(expected)?.toLowerCase();
    return normalizedCandidate != null &&
        normalizedExpected != null &&
        normalizedCandidate.contains(normalizedExpected);
  }

  int _scrollableLocatorMatchScore(
    _CockpitScrollableCandidate candidate,
    CockpitLocator locator,
  ) {
    if (!locator.hasSignals) {
      return 0;
    }

    var score = 0;
    var matchedSignals = 0;
    final pathOnly =
        locator.signalMap.length == 1 &&
        locator.path != null &&
        locator.ancestor == null;

    for (final signal in locator.signals) {
      switch (signal.kind) {
        case CockpitLocatorKind.key:
          if (candidate.keyValue != signal.value) {
            return 0;
          }
          score += 80;
          matchedSignals += 1;
        case CockpitLocatorKind.type:
          if (!_matchesTypeSignal(candidate.typeName, signal.value)) {
            return 0;
          }
          score += 64;
          matchedSignals += 1;
        case CockpitLocatorKind.path:
          final pathScore = _pathMatchPriorityScore(
            candidate.path,
            signal.value,
          );
          if (pathScore <= 0 && pathOnly) {
            return 0;
          }
          if (pathScore > 0) {
            score += pathScore;
            matchedSignals += 1;
          }
        case CockpitLocatorKind.route:
          if (widget.routeName != signal.value) {
            return 0;
          }
          score += 32;
          matchedSignals += 1;
        case CockpitLocatorKind.text:
          if (!_matchesTextSignal(
            candidate.textPreview,
            signal.value,
            locator.matchMode,
          )) {
            return 0;
          }
          score += 24;
          matchedSignals += 1;
        case CockpitLocatorKind.cockpitId:
          final matched =
              candidate.keyValue == signal.value ||
              _matchesTextSignal(
                candidate.textPreview,
                signal.value,
                CockpitTextMatchMode.exact,
              );
          if (!matched) {
            return 0;
          }
          score += 24;
          matchedSignals += 1;
        case CockpitLocatorKind.ref ||
            CockpitLocatorKind.semanticId ||
            CockpitLocatorKind.tooltip ||
            CockpitLocatorKind.registrationId ||
            CockpitLocatorKind.nativeId ||
            CockpitLocatorKind.testId ||
            CockpitLocatorKind.role ||
            CockpitLocatorKind.coordinate ||
            CockpitLocatorKind.visual:
          return 0;
      }
    }

    final ancestor = locator.ancestor;
    if (ancestor != null &&
        !_matchesAncestorChain(candidate.locatorAncestors, ancestor)) {
      return 0;
    }
    if (matchedSignals == 0) {
      return 0;
    }
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
        CockpitLocatorKind.ref ||
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

  bool _matchesTextSignal(
    String? candidate,
    String expected,
    CockpitTextMatchMode matchMode,
  ) => candidate != null && cockpitTextMatches(candidate, expected, matchMode);

  int _textMatchPriorityScore(
    String? candidate,
    String expected,
    CockpitTextMatchMode matchMode,
  ) => candidate == null
      ? 0
      : cockpitTextMatchScore(candidate, expected, matchMode);

  bool _matchesTypeSignal(String? candidate, String expected) {
    final normalizedCandidate = _normalizeTypeName(candidate);
    final normalizedExpected = _normalizeTypeName(expected);
    if (normalizedCandidate == null || normalizedExpected == null) {
      return false;
    }
    return normalizedCandidate == normalizedExpected;
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

  bool _pathContainsScrollable(String? candidate, String targetPath) {
    final candidateSegments = _pathSegments(candidate);
    final targetSegments = _pathSegments(targetPath);
    if (candidateSegments.isEmpty ||
        targetSegments.length < candidateSegments.length) {
      return false;
    }
    for (
      var candidateIndex = 0;
      candidateIndex < candidateSegments.length;
      candidateIndex += 1
    ) {
      if (candidateSegments[candidateIndex] != targetSegments[candidateIndex]) {
        return false;
      }
    }
    return true;
  }

  String? _normalizePath(String? value) {
    final segments = _pathSegments(value);
    if (segments.isEmpty) {
      return null;
    }
    return '/${segments.join('/')}';
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

  static const Set<String> _semanticScrollableTypeNames = <String>{
    'customscrollview',
    'gridview',
    'listview',
    'pageview',
    'reorderablelistview',
    'singlechildscrollview',
    'tabbarview',
  };

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

  bool _isTestBinding(WidgetsBinding binding) {
    return binding.runtimeType.toString().contains('TestWidgetsFlutterBinding');
  }

  Future<void> _applyRevealAdjustment(
    Element targetElement, {
    required CockpitRevealAlignment alignment,
    required double padding,
    required double offset,
    required Duration duration,
  }) async {
    final scrollableState = Scrollable.maybeOf(targetElement);
    final targetRenderObject = targetElement.findRenderObject();
    final viewportRenderObject = _resolveViewportRenderObject(
      targetRenderObject,
    );
    if (scrollableState == null ||
        targetRenderObject is! RenderBox ||
        !targetRenderObject.hasSize ||
        viewportRenderObject is! RenderBox ||
        !viewportRenderObject.hasSize) {
      return;
    }

    final axisDirection = scrollableState.position.axisDirection;
    final axis = switch (axisDirection) {
      AxisDirection.down || AxisDirection.up => Axis.vertical,
      AxisDirection.left || AxisDirection.right => Axis.horizontal,
    };
    final viewportExtent = axis == Axis.vertical
        ? viewportRenderObject.size.height
        : viewportRenderObject.size.width;
    final targetExtent = axis == Axis.vertical
        ? targetRenderObject.size.height
        : targetRenderObject.size.width;
    final availableExtent = viewportExtent - targetExtent;
    if (availableExtent <= 0) {
      return;
    }

    final origin = targetRenderObject.localToGlobal(
      Offset.zero,
      ancestor: viewportRenderObject,
    );
    final leadingEdge = axis == Axis.vertical ? origin.dy : origin.dx;
    final trailingEdge = leadingEdge + targetExtent;
    final clampedPadding = padding.clamp(0, availableExtent).toDouble();
    final alignedLeadingEdge = switch (alignment) {
      CockpitRevealAlignment.start => clampedPadding,
      CockpitRevealAlignment.center => availableExtent / 2,
      CockpitRevealAlignment.end =>
        viewportExtent - targetExtent - clampedPadding,
      CockpitRevealAlignment.nearest =>
        leadingEdge < clampedPadding
            ? clampedPadding
            : trailingEdge > viewportExtent - clampedPadding
            ? viewportExtent - targetExtent - clampedPadding
            : leadingEdge,
    };
    final desiredLeadingEdge = (alignedLeadingEdge + offset).clamp(
      0,
      availableExtent,
    );
    final viewportDelta = leadingEdge - desiredLeadingEdge;
    if (viewportDelta.abs() < 0.5) {
      return;
    }

    final scrollSign = switch (axisDirection) {
      AxisDirection.down || AxisDirection.right => 1.0,
      AxisDirection.up || AxisDirection.left => -1.0,
    };
    final nextPixels =
        (scrollableState.position.pixels + (viewportDelta * scrollSign)).clamp(
          scrollableState.position.minScrollExtent,
          scrollableState.position.maxScrollExtent,
        );
    if ((nextPixels - scrollableState.position.pixels).abs() < 0.5) {
      return;
    }

    if (duration == Duration.zero) {
      scrollableState.position.jumpTo(nextPixels);
      return;
    }

    await scrollableState.position.animateTo(
      nextPixels,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  _CockpitRevealRequest? _resolveRevealRequest(
    Element targetElement, {
    required CockpitRevealAlignment alignment,
    required double padding,
  }) {
    final scrollableState = Scrollable.maybeOf(targetElement);
    final targetRenderObject = targetElement.findRenderObject();
    final viewportRenderObject = _resolveViewportRenderObject(
      targetRenderObject,
    );
    if (targetRenderObject is! RenderBox ||
        !targetRenderObject.hasSize ||
        viewportRenderObject is! RenderBox ||
        !viewportRenderObject.hasSize) {
      return switch (alignment) {
        CockpitRevealAlignment.nearest => const _CockpitRevealRequest(
          alignment: 1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
        CockpitRevealAlignment.start => const _CockpitRevealRequest(
          alignment: 0,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        ),
        CockpitRevealAlignment.center => const _CockpitRevealRequest(
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        ),
        CockpitRevealAlignment.end => const _CockpitRevealRequest(
          alignment: 1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        ),
      };
    }

    final axis = switch (scrollableState!.position.axisDirection) {
      AxisDirection.down || AxisDirection.up => Axis.vertical,
      AxisDirection.left || AxisDirection.right => Axis.horizontal,
    };
    final viewportExtent = axis == Axis.vertical
        ? viewportRenderObject.size.height
        : viewportRenderObject.size.width;
    final targetExtent = axis == Axis.vertical
        ? targetRenderObject.size.height
        : targetRenderObject.size.width;
    final availableExtent = viewportExtent - targetExtent;
    if (availableExtent <= 0) {
      return const _CockpitRevealRequest(
        alignment: 0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    }

    final clampedPadding = padding.clamp(0, availableExtent).toDouble();
    final targetOrigin = targetRenderObject.localToGlobal(
      Offset.zero,
      ancestor: viewportRenderObject,
    );
    final leadingEdge = axis == Axis.vertical
        ? targetOrigin.dy
        : targetOrigin.dx;
    final trailingEdge = leadingEdge + targetExtent;
    final paddedLeadingEdge = clampedPadding;
    final paddedTrailingEdge = viewportExtent - clampedPadding;

    return switch (alignment) {
      CockpitRevealAlignment.start => _CockpitRevealRequest(
        alignment: clampedPadding / availableExtent,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      ),
      CockpitRevealAlignment.center => const _CockpitRevealRequest(
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      ),
      CockpitRevealAlignment.end => _CockpitRevealRequest(
        alignment: 1 - (clampedPadding / availableExtent),
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      ),
      CockpitRevealAlignment.nearest =>
        (leadingEdge >= paddedLeadingEdge &&
                trailingEdge <= paddedTrailingEdge &&
                _elementWinsHitTest(targetElement))
            ? null
            : leadingEdge >= paddedLeadingEdge &&
                  trailingEdge <= paddedTrailingEdge
            ? const _CockpitRevealRequest(
                alignment: 0.5,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              )
            : trailingEdge > paddedTrailingEdge
            ? _CockpitRevealRequest(
                alignment: 1 - (clampedPadding / availableExtent),
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              )
            : _CockpitRevealRequest(
                alignment: clampedPadding / availableExtent,
                alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              ),
    };
  }

  bool _elementWinsHitTest(Element element) {
    final result = CockpitTargetHitTestInspector.inspect(
      CockpitTarget(
        registrationId: 'reveal:${identityHashCode(element)}',
        routeName: widget.routeName,
        diagnosticNodeProvider: () => element,
      ),
    );
    return result == null || (result.withinTargetBounds && result.hit);
  }

  RenderObject? _resolveViewportRenderObject(RenderObject? targetRenderObject) {
    if (targetRenderObject == null) {
      return null;
    }
    try {
      return RenderAbstractViewport.of(targetRenderObject) as RenderObject?;
    } on FlutterError {
      return null;
    } on StateError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _registry.routeName = widget.routeName;

    return _CockpitSurfaceScope(
      state: this,
      routeName: widget.routeName,
      child: RepaintBoundary(key: _boundaryKey, child: widget.child),
    );
  }
}

final class _CockpitMountedLocatorProbe {
  const _CockpitMountedLocatorProbe({
    this.element,
    this.ambiguous = false,
    this.matchCount = 0,
  });

  final Element? element;
  final bool ambiguous;
  final int matchCount;
}

final class _CockpitRevealRequest {
  const _CockpitRevealRequest({
    required this.alignment,
    required this.alignmentPolicy,
  });

  final double alignment;
  final ScrollPositionAlignmentPolicy alignmentPolicy;
}

final class _CockpitScrollableCandidate {
  const _CockpitScrollableCandidate({
    required this.state,
    required this.depth,
    required this.keyValue,
    required this.typeName,
    required this.path,
    required this.locatorAncestors,
    required this.element,
    required this.semanticsElement,
  });

  final ScrollableState state;
  final int depth;
  final String? keyValue;
  final String typeName;
  final String path;
  final List<CockpitSnapshotAncestor> locatorAncestors;
  final Element element;
  final Element semanticsElement;

  String? get textPreview =>
      cockpitResolveSemanticsTargetInfo(element)?.label ??
      cockpitResolveSemanticsTargetInfo(element)?.hint ??
      cockpitResolveSemanticsTargetInfo(semanticsElement)?.label ??
      cockpitResolveSemanticsTargetInfo(semanticsElement)?.hint;

  VoidCallback? semanticScrollActionHandler(SemanticsAction action) {
    return cockpitResolveSemanticsTargetInfo(
          semanticsElement,
        )?.actionHandler(action) ??
        cockpitResolveSemanticsTargetInfo(element)?.actionHandler(action);
  }
}

final class _CockpitScrollableSelection {
  const _CockpitScrollableSelection({
    required this.candidate,
    required this.index,
    required this.count,
  });

  final _CockpitScrollableCandidate candidate;
  final int index;
  final int count;
}

final class _CockpitSurfaceScope extends InheritedWidget {
  const _CockpitSurfaceScope({
    required this.state,
    required this.routeName,
    required super.child,
  });

  final CockpitSurfaceState state;
  final String routeName;

  @override
  bool updateShouldNotify(_CockpitSurfaceScope oldWidget) {
    return oldWidget.state != state || oldWidget.routeName != routeName;
  }
}

final class CockpitTargetNode extends StatefulWidget {
  const CockpitTargetNode({
    required this.registrationId,
    required this.child,
    super.key,
    this.cockpitId,
    this.semanticId,
    this.keyValue,
    this.text,
    this.tooltip,
    this.typeName,
    this.supportedCommands = const <CockpitCommandType>{},
    this.onTap,
    this.onEnterText,
  });

  final String registrationId;
  final String? cockpitId;
  final String? semanticId;
  final String? keyValue;
  final String? text;
  final String? tooltip;
  final String? typeName;
  final Set<CockpitCommandType> supportedCommands;
  final CockpitTapHandler? onTap;
  final CockpitEnterTextHandler? onEnterText;
  final Widget child;

  @override
  State<CockpitTargetNode> createState() => _CockpitTargetNodeState();
}

final class _CockpitTargetNodeState extends State<CockpitTargetNode> {
  CockpitTargetRegistry? _registry;
  String? _modalRouteName;
  final GlobalKey _diagnosticKey = GlobalKey(debugLabel: 'CockpitTargetNode');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _modalRouteName = ModalRoute.of(context)?.settings.name?.trim();
    _registerTarget();
  }

  @override
  void didUpdateWidget(covariant CockpitTargetNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registerTarget();
  }

  @override
  void dispose() {
    _registry?.unregister(widget.registrationId);
    super.dispose();
  }

  void _registerTarget() {
    final surface = CockpitSurface.maybeOf(context);
    final registry = surface?.registry;
    if (registry == null) {
      return;
    }

    if (!identical(_registry, registry)) {
      _registry?.unregister(widget.registrationId);
      _registry = registry;
    }

    final routeName = _modalRouteName;
    final registeredRouteName =
        routeName == null ||
            routeName.isEmpty ||
            (routeName == '/' && registry.routeName != '/')
        ? registry.routeName ?? ''
        : routeName;

    registry.register(
      CockpitTarget(
        registrationId: widget.registrationId,
        cockpitId: widget.cockpitId,
        semanticId: widget.semanticId,
        keyValue: widget.keyValue,
        text: widget.text,
        tooltip: widget.tooltip,
        typeName: widget.typeName,
        routeName: registeredRouteName,
        supportedCommands: widget.supportedCommands,
        onTap: widget.onTap,
        onEnterText: widget.onEnterText,
        diagnosticNodeProvider: () => _diagnosticKey.currentContext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _diagnosticKey, child: widget.child);
  }
}
