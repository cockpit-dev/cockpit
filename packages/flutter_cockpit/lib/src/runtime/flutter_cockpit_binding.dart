import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../model/cockpit_environment.dart';
import '../capture/cockpit_native_capture.dart';
import '../network/cockpit_http_network_observer.dart';
import '../network/cockpit_http_network_observer_configuration.dart';
import '../network/cockpit_network_observer.dart';
import '../recording/cockpit_native_recording.dart';
import '../recording/cockpit_recording_capabilities.dart';
import '../recording/cockpit_recording_kind.dart';
import '../recording/cockpit_recording_layer.dart';
import '../recording/cockpit_recording_request.dart';
import '../recording/cockpit_recording_result.dart';
import '../recording/cockpit_recording_session.dart';
import '../recording/cockpit_recording_state.dart';
import 'cockpit_short_id.dart';
import '../session/cockpit_session_controller.dart';
import 'flutter_cockpit_configuration.dart';
import '../model/cockpit_observation.dart';
import 'cockpit_rebuild_tracker.dart';
import 'cockpit_diagnostics_config.dart';
import 'cockpit_runtime_event.dart';
import 'cockpit_runtime_environment.dart';
import 'cockpit_runtime_observer.dart';
import 'cockpit_runtime_observer_configuration.dart';
import 'cockpit_runtime_step_buffer.dart';
import 'cockpit_target_registry.dart';

final class FlutterCockpitBinding {
  FlutterCockpitBinding(FlutterCockpitConfiguration configuration)
    : _configuration = configuration,
      registry =
          configuration.registry ??
          CockpitTargetRegistry(routeName: configuration.initialRouteName),
      nativeCapture =
          configuration.nativeCapture ?? const CockpitNativeCapture(),
      nativeRecording =
          configuration.nativeRecording ?? const CockpitNativeRecording(),
      sessionController =
          configuration.sessionController ??
          CockpitSessionController(
            sessionId: cockpitShortId('s'),
            taskId: 'runtime-session',
            platform: defaultTargetPlatform.name,
          ),
      networkObserver =
          configuration.networkObserver ??
          _buildHttpNetworkObserver(configuration.httpNetworkObserver),
      runtimeStepBuffer = CockpitRuntimeStepBuffer(),
      currentRouteName = ValueNotifier<String>(
        _normalizeConfiguredRouteName(configuration.initialRouteName),
      ) {
    rebuildTracker = configuration.diagnostics.enableRebuildTracking
        ? CockpitRebuildTracker(
            routeNameProvider: () => currentRouteName.value,
            maxTrackedEntries:
                configuration.diagnostics.maxTrackedRebuildEntries,
          )
        : null;
    runtimeObserver =
        configuration.runtimeObserver ??
        (configuration.runtimeObserverConfiguration.enabled
            ? configuration.runtimeObserverConfiguration.buildObserver(
                routeNameProvider: () => currentRouteName.value,
                onCriticalEvent: _recordCriticalRuntimeEvent,
              )
            : null);
    _installNetworkOverridesIfEnabled();
    navigatorObserver = createNavigatorObserver();
    registry.routeName = _normalizeConfiguredRouteName(
      configuration.initialRouteName,
    );
  }

  FlutterCockpitConfiguration _configuration;
  CockpitTargetRegistry registry;
  CockpitNativeCapture nativeCapture;
  CockpitNativeRecording nativeRecording;
  CockpitSessionController sessionController;
  CockpitNetworkObserver? networkObserver;
  CockpitRebuildTracker? rebuildTracker;
  CockpitRuntimeObserver? runtimeObserver;
  final CockpitRuntimeStepBuffer runtimeStepBuffer;
  final ValueNotifier<String> currentRouteName;
  late final NavigatorObserver navigatorObserver;
  final Set<_FlutterCockpitNavigatorObserver> _navigatorObservers =
      <_FlutterCockpitNavigatorObserver>{};
  final Map<_FlutterCockpitNavigatorObserver, int> _navigatorActivity =
      <_FlutterCockpitNavigatorObserver, int>{};
  final Map<Route<dynamic>, AnimationStatusListener> _routeTransitionListeners =
      <Route<dynamic>, AnimationStatusListener>{};
  final Set<_FlutterCockpitRouteInformationBinding> _routeInformationBindings =
      <_FlutterCockpitRouteInformationBinding>{};
  CockpitRecordingSession? _activeRecordingSession;
  bool _isDisposed = false;
  HttpOverrides? _previousHttpOverrides;
  bool _installedGlobalNetworkOverride = false;
  int _routeNameUpdateGeneration = 0;
  bool _isRouteTransitioning = false;
  Route<dynamic>? _pendingNavigatorRoute;
  bool _hasPendingNavigatorRoute = false;
  bool _pendingNavigatorPublicationScheduled = false;
  String? _lastRouteInformationName;
  String? _discoveredRouteName;

  bool get isRouteTransitioning => _isRouteTransitioning;

  FlutterCockpitConfiguration get configuration => _configuration;

  CockpitRecordingSession? get activeRecordingSession =>
      _activeRecordingSession;

  Future<bool> queryNativeCaptureAvailability() async {
    try {
      return await nativeCapture.queryAvailability();
    } on Object {
      return false;
    }
  }

  Future<CockpitRecordingCapabilities> queryRecordingCapabilities() async {
    try {
      return await nativeRecording.queryCapabilities();
    } on Object catch (error) {
      return CockpitRecordingCapabilities(
        supportsNativeRecording: false,
        preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        supportedLayers: const <CockpitRecordingLayer>[],
        recordingLimitations: <String>[_recordingProbeFailureMessage(error)],
      );
    }
  }

  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    final session = await nativeRecording.startRecording(request: request);
    _activeRecordingSession = session.state == CockpitRecordingState.recording
        ? session
        : null;
    return session;
  }

  Future<CockpitRecordingResult> stopRecording() async {
    final session = _activeRecordingSession;
    if (session == null) {
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        failureReason: 'recordingNotActive',
      );
    }

    final result = await nativeRecording.stopRecording(session: session);
    _activeRecordingSession = null;
    return result;
  }

  CockpitEnvironment? resolveRuntimeEnvironment({required String platform}) {
    return resolveCockpitRuntimeEnvironment(
      platform: platform,
      configuredFlutterVersion: configuration.flutterVersion,
    );
  }

  void dispose() {
    _isDisposed = true;
    if (_installedGlobalNetworkOverride ||
        identical(HttpOverrides.current, networkObserver)) {
      HttpOverrides.global = _previousHttpOverrides;
      _installedGlobalNetworkOverride = false;
    }
    currentRouteName.dispose();
    _navigatorObservers.clear();
    _navigatorActivity.clear();
    for (final entry in _routeTransitionListeners.entries) {
      final animation = entry.key is ModalRoute<dynamic>
          ? (entry.key as ModalRoute<dynamic>).animation
          : null;
      animation?.removeStatusListener(entry.value);
    }
    _routeTransitionListeners.clear();
    _isRouteTransitioning = false;
    _pendingNavigatorRoute = null;
    _hasPendingNavigatorRoute = false;
    _pendingNavigatorPublicationScheduled = false;
    for (final binding in _routeInformationBindings.toList()) {
      binding.dispose();
    }
    _routeInformationBindings.clear();
    _activeRecordingSession = null;
    rebuildTracker?.dispose();
    runtimeObserver?.dispose();
  }

  void updateConfiguration(FlutterCockpitConfiguration nextConfiguration) {
    if (_isDisposed) {
      return;
    }

    final previousConfiguration = _configuration;
    final previousRuntimeObserverConfig =
        previousConfiguration.runtimeObserverConfiguration;
    final previousDiagnostics = previousConfiguration.diagnostics;

    final previousInitialRouteName = _normalizeConfiguredRouteName(
      previousConfiguration.initialRouteName,
    );
    final nextInitialRouteName = _normalizeConfiguredRouteName(
      nextConfiguration.initialRouteName,
    );
    if (currentRouteName.value == previousInitialRouteName &&
        nextInitialRouteName != currentRouteName.value) {
      _applyRouteName(nextInitialRouteName);
    }

    _reconfigureNetworkObserver(nextConfiguration);
    _reconfigureRuntimeObserver(
      previousConfig: previousRuntimeObserverConfig,
      nextConfiguration: nextConfiguration,
    );
    _reconfigureRebuildTracker(
      previousDiagnostics: previousDiagnostics,
      nextDiagnostics: nextConfiguration.diagnostics,
    );
    _reconfigureRuntimeReferences(nextConfiguration);

    _configuration = nextConfiguration.copyWith(
      registry: registry,
      nativeCapture: nativeCapture,
      nativeRecording: nativeRecording,
      sessionController: sessionController,
      networkObserver: networkObserver,
      runtimeObserver: runtimeObserver,
    );
  }

  void _reconfigureRuntimeReferences(
    FlutterCockpitConfiguration nextConfiguration,
  ) {
    final nextRegistry = nextConfiguration.registry;
    if (nextRegistry != null && !identical(nextRegistry, registry)) {
      nextRegistry.routeName = currentRouteName.value;
      registry = nextRegistry;
    } else {
      registry.routeName = currentRouteName.value;
    }

    final nextSessionController = nextConfiguration.sessionController;
    if (nextSessionController != null &&
        !identical(nextSessionController, sessionController)) {
      sessionController = nextSessionController;
    }

    final nextNativeCapture = nextConfiguration.nativeCapture;
    if (nextNativeCapture != null &&
        !identical(nextNativeCapture, nativeCapture)) {
      nativeCapture = nextNativeCapture;
    }

    final nextNativeRecording = nextConfiguration.nativeRecording;
    if (nextNativeRecording != null &&
        !identical(nextNativeRecording, nativeRecording)) {
      nativeRecording = nextNativeRecording;
      _activeRecordingSession = null;
    }
  }

  void _installNetworkOverridesIfEnabled() {
    final observer = networkObserver;
    if (observer is! CockpitHttpNetworkObserver) {
      return;
    }
    _previousHttpOverrides = HttpOverrides.current;
    if (!observer.hasAttachedParentOverrides) {
      observer.attachParentOverrides(_previousHttpOverrides);
    }
    HttpOverrides.global = observer;
    _installedGlobalNetworkOverride = true;
  }

  void _reconfigureNetworkObserver(
    FlutterCockpitConfiguration nextConfiguration,
  ) {
    final nextObserver =
        nextConfiguration.networkObserver ??
        _buildHttpNetworkObserver(nextConfiguration.httpNetworkObserver);
    if (identical(networkObserver, nextObserver)) {
      return;
    }

    if (_installedGlobalNetworkOverride ||
        identical(HttpOverrides.current, networkObserver)) {
      HttpOverrides.global = _previousHttpOverrides;
      _installedGlobalNetworkOverride = false;
    }

    networkObserver = nextObserver;
    _installNetworkOverridesIfEnabled();
  }

  void _reconfigureRuntimeObserver({
    required CockpitRuntimeObserverConfiguration previousConfig,
    required FlutterCockpitConfiguration nextConfiguration,
  }) {
    if (nextConfiguration.runtimeObserver != null) {
      if (!identical(runtimeObserver, nextConfiguration.runtimeObserver)) {
        runtimeObserver?.dispose();
      }
      runtimeObserver = nextConfiguration.runtimeObserver;
      return;
    }

    final nextConfig = nextConfiguration.runtimeObserverConfiguration;
    if (previousConfig == nextConfig) {
      return;
    }

    runtimeObserver?.dispose();
    runtimeObserver = nextConfig.enabled
        ? nextConfig.buildObserver(
            routeNameProvider: () => currentRouteName.value,
            onCriticalEvent: _recordCriticalRuntimeEvent,
          )
        : null;
  }

  void _reconfigureRebuildTracker({
    required CockpitDiagnosticsConfig previousDiagnostics,
    required CockpitDiagnosticsConfig nextDiagnostics,
  }) {
    final changed =
        previousDiagnostics.enableRebuildTracking !=
            nextDiagnostics.enableRebuildTracking ||
        previousDiagnostics.maxTrackedRebuildEntries !=
            nextDiagnostics.maxTrackedRebuildEntries;
    if (!changed) {
      return;
    }

    rebuildTracker?.dispose();
    rebuildTracker = nextDiagnostics.enableRebuildTracking
        ? CockpitRebuildTracker(
            routeNameProvider: () => currentRouteName.value,
            maxTrackedEntries: nextDiagnostics.maxTrackedRebuildEntries,
          )
        : null;
  }

  void _setRouteName(Route<dynamic>? route) {
    if (_isDisposed) {
      return;
    }
    final nextRouteName = _normalizeObservedRouteName(route?.settings.name);
    if (currentRouteName.value == nextRouteName &&
        registry.routeName == nextRouteName) {
      return;
    }

    _setRouteNameValue(nextRouteName);
  }

  /// Binds a Flutter [RouteInformationProvider] without depending on a
  /// particular router package. This also covers go_router's public provider.
  ///
  /// The returned callback releases this caller's binding. Calling it more
  /// than once is harmless.
  VoidCallback bindRouteInformationProvider(RouteInformationProvider provider) {
    if (_isDisposed) {
      return () {};
    }
    for (final binding in _routeInformationBindings) {
      if (identical(binding.provider, provider)) {
        binding.retain();
        return _routeInformationReleaseCallback(binding);
      }
    }

    final binding = _FlutterCockpitRouteInformationBinding(
      provider: provider,
      onChanged: _setRouteInformation,
    );
    _routeInformationBindings.add(binding);
    binding.retain();
    return _routeInformationReleaseCallback(binding);
  }

  VoidCallback _routeInformationReleaseCallback(
    _FlutterCockpitRouteInformationBinding binding,
  ) {
    var released = false;
    return () {
      if (released) {
        return;
      }
      released = true;
      if (binding.release()) {
        _routeInformationBindings.remove(binding);
      }
    };
  }

  void _setRouteInformation(RouteInformation information) {
    if (_isDisposed) {
      return;
    }
    _clearPendingNavigatorRoute();
    final trimmedRouteName = information.uri.toString().trim();
    final routeName = trimmedRouteName.isEmpty
        ? _normalizeConfiguredRouteName(configuration.initialRouteName)
        : trimmedRouteName;
    if (_lastRouteInformationName == routeName &&
        _discoveredRouteName != null &&
        _discoveredRouteName != routeName &&
        currentRouteName.value == _discoveredRouteName) {
      return;
    }
    _lastRouteInformationName = routeName;
    _discoveredRouteName = null;
    _setRouteNameValue(routeName);
  }

  void _setRouteNameValue(String routeName) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _routeNameUpdateGeneration++;
      _applyRouteName(routeName);
      return;
    }

    final generation = ++_routeNameUpdateGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed || generation != _routeNameUpdateGeneration) {
        return;
      }
      _applyRouteName(routeName);
    });
  }

  NavigatorObserver createNavigatorObserver() {
    final observer = _FlutterCockpitNavigatorObserver(
      _handleNavigatorRouteChanged,
    );
    _navigatorObservers.add(observer);
    _navigatorActivity[observer] = 0;
    return observer;
  }

  Route<dynamic>? _mostRecentObservedRoute() {
    Route<dynamic>? fallback;
    var fallbackActivity = -1;
    for (final candidate in _navigatorObservers) {
      final candidateRoute = candidate.currentRoute;
      final candidateActivity = _navigatorActivity[candidate] ?? 0;
      if (candidateRoute != null && candidateActivity > fallbackActivity) {
        fallback = candidateRoute;
        fallbackActivity = candidateActivity;
      }
    }
    return fallback;
  }

  void _handleNavigatorRouteChanged(
    _FlutterCockpitNavigatorObserver observer,
    Route<dynamic>? route,
    Route<dynamic>? transitionRoute,
  ) {
    if (_isDisposed) {
      return;
    }
    final nextActivity =
        _navigatorActivity.values.fold<int>(
          0,
          (maximum, value) => value > maximum ? value : maximum,
        ) +
        1;
    _navigatorActivity[observer] = nextActivity;
    _trackRouteTransition(transitionRoute);
    final nextRoute = route ?? _mostRecentObservedRoute();
    if (_isRouteTransitioning) {
      _pendingNavigatorRoute = nextRoute;
      _hasPendingNavigatorRoute = true;
      _schedulePendingNavigatorRoutePublication();
      return;
    }
    _setRouteName(nextRoute);
  }

  void _trackRouteTransition(Route<dynamic>? route) {
    final animation = route is ModalRoute<dynamic> ? route.animation : null;
    if (route == null || animation == null) {
      return;
    }
    final existingListener = _routeTransitionListeners.remove(route);
    if (existingListener != null) {
      animation.removeStatusListener(existingListener);
    }
    final status = animation.status;
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _isRouteTransitioning = _routeTransitionListeners.isNotEmpty;
      return;
    }

    late final AnimationStatusListener listener;
    listener = (nextStatus) {
      if (nextStatus != AnimationStatus.completed &&
          nextStatus != AnimationStatus.dismissed) {
        return;
      }
      animation.removeStatusListener(listener);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed ||
            !identical(_routeTransitionListeners[route], listener)) {
          return;
        }
        _routeTransitionListeners.remove(route);
        _isRouteTransitioning = _routeTransitionListeners.isNotEmpty;
        if (!_isRouteTransitioning && _hasPendingNavigatorRoute) {
          _publishPendingNavigatorRoute();
        }
      });
    };
    _routeTransitionListeners[route] = listener;
    animation.addStatusListener(listener);
    _isRouteTransitioning = true;
  }

  void _schedulePendingNavigatorRoutePublication() {
    if (_pendingNavigatorPublicationScheduled) {
      return;
    }
    _pendingNavigatorPublicationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingNavigatorPublicationScheduled = false;
      if (_isDisposed || !_hasPendingNavigatorRoute) {
        return;
      }
      if (!_isRouteTransitioning ||
          _hasVisibleTargetsForRoute(_pendingNavigatorRoute)) {
        _publishPendingNavigatorRoute();
        return;
      }
      _schedulePendingNavigatorRoutePublication();
    });
  }

  bool _hasVisibleTargetsForRoute(Route<dynamic>? route) {
    final routeName = _normalizeObservedRouteName(route?.settings.name);
    final explicitMatch = registry.registeredTargets.any(
      (target) => target.isVisible && target.routeName == routeName,
    );
    final readinessProbe = registry.discoveredTargetsReadinessProbe;
    return explicitMatch ||
        (readinessProbe != null
            ? readinessProbe(allowRouteFallback: false, routeName: routeName)
            : registry.visibleTargets.any(
                (target) => target.isVisible && target.routeName == routeName,
              ));
  }

  void _publishPendingNavigatorRoute() {
    if (_isDisposed || !_hasPendingNavigatorRoute) {
      return;
    }
    final pendingRoute = _pendingNavigatorRoute;
    _pendingNavigatorRoute = null;
    _hasPendingNavigatorRoute = false;
    _setRouteName(pendingRoute);
  }

  void _applyRouteName(String routeName) {
    if (_isDisposed) {
      return;
    }
    currentRouteName.value = routeName;
    registry.routeName = routeName;
  }

  void setCurrentRouteName(String routeName) {
    if (_isDisposed) {
      return;
    }
    _clearPendingNavigatorRoute();
    _setRouteNameValue(_normalizeExplicitRouteName(routeName));
  }

  void setObservedRouteName(String? routeName) {
    if (_isDisposed) {
      return;
    }
    _clearPendingNavigatorRoute();
    _setRouteNameValue(_normalizeObservedRouteName(routeName));
  }

  /// Synchronizes a route discovered from the current widget tree.
  void setDiscoveredRouteName(String? routeName) {
    if (_isDisposed) {
      return;
    }
    final normalizedRouteName = _normalizeObservedRouteName(routeName);
    if (normalizedRouteName == currentRouteName.value) {
      return;
    }
    _discoveredRouteName = normalizedRouteName;
    // Discovery runs as part of a live target read. Apply this observation
    // synchronously so an expected-route wait can consume it in the same loop.
    _applyRouteName(normalizedRouteName);
  }

  void _clearPendingNavigatorRoute() {
    _pendingNavigatorRoute = null;
    _hasPendingNavigatorRoute = false;
  }

  String _normalizeObservedRouteName(String? routeName) {
    final initialRouteName = _normalizeConfiguredRouteName(
      configuration.initialRouteName,
    );
    if (routeName == null) {
      return initialRouteName;
    }
    final trimmedRouteName = routeName.trim();
    if (trimmedRouteName.isEmpty) {
      return initialRouteName;
    }
    return trimmedRouteName == '/' && initialRouteName != '/'
        ? initialRouteName
        : trimmedRouteName;
  }

  String _normalizeExplicitRouteName(String routeName) {
    final trimmedRouteName = routeName.trim();
    return trimmedRouteName.isEmpty
        ? _normalizeConfiguredRouteName(configuration.initialRouteName)
        : trimmedRouteName;
  }

  void _recordCriticalRuntimeEvent(CockpitRuntimeEvent event) {
    final observation = CockpitObservation(
      routeName: event.routeName,
      phase: CockpitObservationPhase.failure,
      interactiveElements: const <String>[],
    );
    final actionArgs = <String, Object?>{
      'eventId': event.eventId,
      'kind': event.kind.jsonValue,
      'severity': event.severity.jsonValue,
      'message': event.message,
      'routeName': event.routeName,
      'source': event.source,
      'details': event.details,
      'stackTracePreview': event.stackTracePreview,
      'stackTraceTruncated': event.stackTraceTruncated,
      'recordedAt': event.recordedAt.toUtc().toIso8601String(),
    };
    runtimeStepBuffer.recordStep(
      actionType: 'runtime_event',
      actionArgs: actionArgs,
      observation: observation,
    );
    try {
      sessionController.recordStep(
        actionType: 'runtime_event',
        actionArgs: actionArgs,
        observation: observation,
      );
    } on StateError {
      // Runtime observation must never crash the app after a session has closed.
    }
  }
}

String _recordingProbeFailureMessage(Object error) {
  return switch (error) {
    MissingPluginException(:final message?) =>
      message.isEmpty ? 'Native recording plugin is unavailable.' : message,
    MissingPluginException() => 'Native recording plugin is unavailable.',
    PlatformException(:final message?, :final code) =>
      message.isNotEmpty ? message : code,
    StateError(:final message) => message,
    _ => '$error',
  };
}

CockpitHttpNetworkObserver? _buildHttpNetworkObserver(
  CockpitHttpNetworkObserverConfiguration? configuration,
) {
  if (configuration == null) {
    return null;
  }
  return CockpitHttpNetworkObserver(
    maxRetainedEntries: configuration.maxRetainedEntries,
    maxHeaderCount: configuration.maxHeaderCount,
    maxHeaderValueLength: configuration.maxHeaderValueLength,
    maxBodyBytes: configuration.maxBodyBytes,
    captureHeaders: configuration.captureHeaders,
    captureBodies: configuration.captureBodies,
    redact: configuration.redact,
    maxWebSocketFrames: configuration.maxWebSocketFrames,
    maxWebSocketPreviewBytes: configuration.maxWebSocketPreviewBytes,
  );
}

String _normalizeConfiguredRouteName(String routeName) {
  final trimmedRouteName = routeName.trim();
  return trimmedRouteName.isEmpty ? '/' : trimmedRouteName;
}

final class _FlutterCockpitNavigatorObserver extends NavigatorObserver {
  _FlutterCockpitNavigatorObserver(this._onRouteChanged);

  final void Function(
    _FlutterCockpitNavigatorObserver observer,
    Route<dynamic>? route,
    Route<dynamic>? transitionRoute,
  )
  _onRouteChanged;
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  Route<dynamic>? get currentRoute => _routes.isEmpty ? null : _routes.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _routes.add(route);
    _onRouteChanged(this, route, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _onRouteChanged(this, previousRoute ?? currentRoute, route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    if (previousRoute != null && !_routes.contains(previousRoute)) {
      _routes.add(previousRoute);
    }
    _onRouteChanged(this, previousRoute ?? currentRoute, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _routes.remove(oldRoute);
    }
    if (newRoute != null) {
      _routes.add(newRoute);
    }
    _onRouteChanged(this, newRoute ?? currentRoute, newRoute);
  }
}

final class _FlutterCockpitRouteInformationBinding {
  _FlutterCockpitRouteInformationBinding({
    required this.provider,
    required this.onChanged,
  });

  final RouteInformationProvider provider;
  final void Function(RouteInformation information) onChanged;
  bool _attached = false;
  int _retainCount = 0;

  void _listener() {
    onChanged(provider.value);
  }

  void retain() {
    _retainCount++;
    if (!_attached) {
      _attached = true;
      provider.addListener(_listener);
      onChanged(provider.value);
    }
  }

  bool release() {
    if (_retainCount == 0) {
      return false;
    }
    _retainCount--;
    if (_retainCount > 0) {
      return false;
    }
    dispose();
    return true;
  }

  void dispose() {
    _retainCount = 0;
    if (!_attached) {
      return;
    }
    _attached = false;
    provider.removeListener(_listener);
  }
}
