import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../capture/cockpit_capture_fallback_exception.dart';
import '../capture/cockpit_capture_result.dart';
import '../control/cockpit_screenshot_request.dart';
import '../executor/in_app_cockpit_command_executor.dart';
import '../gesture/cockpit_gesture_action.dart';
import '../gesture/cockpit_gesture_engine.dart';
import '../model/cockpit_environment.dart';
import '../network/cockpit_network_query.dart';
import '../remote/cockpit_remote_bridge_protocol.dart';
import '../remote/cockpit_remote_bridge_binary_file_reader.dart';
import '../remote/cockpit_remote_session_configuration.dart';
import '../remote/cockpit_remote_session_server.dart';
import '../remote/cockpit_remote_session_status.dart';
import '../remote/cockpit_remote_session_bridge_client.dart';
import '../remote/cockpit_remote_session_endpoint_handler.dart';
import '../recording/cockpit_recording_capabilities.dart';
import '../recording/cockpit_recording_kind.dart';
import '../recording/cockpit_recording_layer.dart';
import '../recording/cockpit_recording_request.dart';
import '../recording/cockpit_recording_result.dart';
import '../recording/cockpit_recording_session.dart';
import 'flutter_cockpit.dart';
import 'cockpit_tap_feedback_overlay.dart';
import 'cockpit_capabilities.dart';
import 'cockpit_native_semantics.dart';
import 'cockpit_process_id.dart';
import 'cockpit_pending_frame_waiter.dart';
import 'cockpit_native_viewport.dart';
import 'cockpit_runtime_query.dart';
import 'cockpit_remote_session_platform.dart';
import 'cockpit_runtime_tree_visibility.dart';
import 'cockpit_scroll_step_result.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_snapshot_options.dart';
import 'cockpit_surface.dart';
import 'cockpit_ui_idle_waiter.dart';
import 'cockpit_visual_frame_driver.dart';

final class FlutterCockpitRoot extends StatefulWidget {
  const FlutterCockpitRoot({required this.child, super.key});

  final Widget child;

  @override
  State<FlutterCockpitRoot> createState() => FlutterCockpitRootState();
}

final class FlutterCockpitRootState extends State<FlutterCockpitRoot> {
  // Keep this key untyped. Flutter web hot restart can keep this State object
  // while remounting CockpitSurface from a new code generation; a typed
  // GlobalKey<CockpitSurfaceState> can then reject the fresh State by stale
  // generic type identity and make the remote bridge look ready but unusable.
  final GlobalKey _surfaceKey = GlobalKey();
  CockpitRemoteSessionServer? _remoteSessionServer;
  CockpitRemoteSessionBridgeClient? _remoteSessionBridgeClient;
  Future<void>? _remoteSessionStartFuture;
  CockpitTapFeedbackController? _tapFeedbackController;
  final Map<RouteInformationProvider, VoidCallback> _routeInformationUnbinders =
      <RouteInformationProvider, VoidCallback>{};
  bool _routeInformationDiscoveryScheduled = false;
  Object? _remoteSessionStartError;
  StackTrace? _remoteSessionStartErrorStackTrace;
  bool _reportedRemoteSessionStartFailure = false;
  SemanticsHandle? _semanticsHandle;
  final CockpitNativeSemantics _nativeSemantics =
      const CockpitNativeSemantics();
  final CockpitNativeViewport _nativeViewport = const CockpitNativeViewport();

  @override
  void initState() {
    super.initState();
    _scheduleRouteInformationDiscovery();
    _syncTapFeedbackController();
    final configuration = FlutterCockpit.binding.configuration.remoteSession;
    if (configuration != null &&
        configuration.enabled &&
        configuration.autoStart) {
      _remoteSessionStartFuture = _beginRemoteSessionStart(ignoreFailure: true);
    }
  }

  @override
  void didUpdateWidget(covariant FlutterCockpitRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTapFeedbackController();
    _scheduleRouteInformationDiscovery();
  }

  @override
  void reassemble() {
    super.reassemble();
    FlutterCockpit.binding.runtimeObserver?.clear();
    FlutterCockpit.clearRecordedSteps();
  }

  void _scheduleRouteInformationDiscovery() {
    if (_routeInformationDiscoveryScheduled) {
      return;
    }
    _routeInformationDiscoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeInformationDiscoveryScheduled = false;
      if (!mounted) {
        return;
      }
      final providers = cockpitRouteInformationProvidersInRuntimeTree(
        context as Element,
      ).toSet();
      for (final entry in _routeInformationUnbinders.entries.toList()) {
        if (!providers.contains(entry.key)) {
          entry.value();
          _routeInformationUnbinders.remove(entry.key);
        }
      }
      for (final provider in providers) {
        _routeInformationUnbinders.putIfAbsent(
          provider,
          () => FlutterCockpit.bindRouteInformationProvider(provider),
        );
      }
    });
  }

  CockpitSnapshot snapshot({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions(),
  }) {
    final surfaceState = _requireSurfaceState();
    final snapshot = surfaceState.snapshot(options: options);
    final networkObserver = FlutterCockpit.binding.networkObserver;
    final runtimeObserver = FlutterCockpit.binding.runtimeObserver;
    return snapshot.copyWith(
      network: !options.includeNetworkActivity || networkObserver == null
          ? snapshot.network
          : networkObserver.snapshot(
              maxEntries: options.maxNetworkEntries,
              query: options.networkQuery,
            ),
      runtime: !options.includeRuntimeActivity || runtimeObserver == null
          ? snapshot.runtime
          : runtimeObserver.snapshot(
              maxEntries: options.maxRuntimeEntries,
              query: options.runtimeQuery,
            ),
    );
  }

  /// Creates the same in-app command executor used by the remote Cockpit
  /// bridge.
  ///
  /// This is intentionally exposed for development-only test adapters. It
  /// keeps Dart integration tests on the exact Element traversal, hit testing,
  /// reveal, gesture, wait, assertion, capture, and diagnostic paths used by
  /// `cockpit dev`, without requiring a loopback server or a second runner.
  InAppCockpitCommandExecutor createCommandExecutor({
    String? platform,
    String transportType = 'inAppTest',
    Future<void> Function()? postActionSettler,
    Future<void> Function(Duration duration)? waitTickHandler,
    CockpitGestureDelay? gestureDelay,
  }) {
    return _buildRemoteCommandExecutor(
      platform ??
          resolveCockpitRemoteSessionPlatform(
            isWeb: kIsWeb,
            targetPlatform: defaultTargetPlatform,
          ),
      transportType: transportType,
      postActionSettler: postActionSettler,
      waitTickHandler: waitTickHandler,
      gestureDelay: gestureDelay,
    );
  }

  Future<CockpitSnapshot> _remoteSnapshot({
    required CockpitSnapshotOptions options,
  }) async {
    final binding = WidgetsBinding.instance;
    if (_isTestBinding(binding)) {
      return snapshot(options: options);
    }
    await ensureCockpitVisualFrame(
      platform: resolveCockpitRemoteSessionPlatform(
        isWeb: kIsWeb,
        targetPlatform: defaultTargetPlatform,
      ),
    );
    await waitForPendingCockpitFrame(
      phase: binding.schedulerPhase,
      hasScheduledFrame: binding.hasScheduledFrame,
      waitForEndOfFrame: () => binding.endOfFrame,
    );
    return snapshot(options: options);
  }

  Future<bool> waitForUiIdle({
    Duration? quietWindow,
    Duration? timeout,
    bool? includeNetworkIdle,
  }) {
    final interactionPolicy =
        FlutterCockpit.binding.configuration.interactionPolicy;
    return waitForCockpitUiIdle(
      quietWindow: quietWindow ?? interactionPolicy.uiIdleQuietWindow,
      timeout: timeout ?? interactionPolicy.uiIdleTimeout,
      waitTick: (duration) => Future<void>.delayed(duration),
      waitForNetworkIdle: FlutterCockpit.binding.networkObserver?.waitForIdle,
      ensureVisualFrame: () => ensureCockpitVisualFrame(
        platform: resolveCockpitRemoteSessionPlatform(
          isWeb: kIsWeb,
          targetPlatform: defaultTargetPlatform,
        ),
      ),
      includeNetworkIdle:
          includeNetworkIdle ??
          interactionPolicy.waitForNetworkIdleDuringAcceptanceCapture,
    );
  }

  Future<CockpitCaptureResult> captureScreenshot(
    CockpitScreenshotRequest request, {
    CockpitCaptureProfile? profile,
    bool? allowFallback,
    bool waitForIdle = true,
  }) async {
    final effectiveProfile =
        profile ?? request.profile ?? _defaultProfileFor(request);
    final effectiveAllowFallback = allowFallback ?? request.allowsFallback;
    final effectiveRequest = request.snapshotOptions == null
        ? request.copyWith(
            snapshotOptions: _defaultSnapshotOptionsFor(request.reason),
          )
        : request;
    final surfaceState = _requireSurfaceState();

    if (waitForIdle &&
        effectiveRequest.reason == CockpitScreenshotReason.acceptance) {
      try {
        await waitForUiIdle();
      } on Object {
        // Idle observation improves capture stability but is not a prerequisite.
      }
    }

    final snapshotData = effectiveRequest.includeSnapshot
        ? surfaceState.snapshot(
            options:
                effectiveRequest.snapshotOptions ??
                _defaultSnapshotOptionsFor(effectiveRequest.reason),
          )
        : null;

    final prefersNativeCapture = cockpitCaptureProfilePrefersNative(
      effectiveProfile,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
    if (prefersNativeCapture) {
      if (effectiveRequest.cropLocator != null) {
        if (!effectiveAllowFallback) {
          throw PlatformException(
            code: 'nativeElementCropUnavailable',
            message:
                'Element-scoped capture requires the Flutter view capture profile.',
          );
        }
        final screenshot = await surfaceState.captureScreenshot(
          effectiveRequest,
        );
        return CockpitCaptureResult(
          screenshot: screenshot,
          requestedProfile: effectiveProfile,
          resolvedCaptureKind: CockpitCaptureKind.flutterView,
          usedFallback: true,
          degradationReason: 'nativeElementCropUnavailable',
        );
      }
      final nativeCaptureAvailable = await FlutterCockpit.binding
          .queryNativeCaptureAvailability();
      if (!nativeCaptureAvailable) {
        if (!effectiveAllowFallback) {
          throw PlatformException(
            code: 'nativeCaptureUnavailable',
            message: 'Native screenshot capture is unavailable.',
          );
        }
        final screenshot = await surfaceState.captureScreenshot(
          effectiveRequest,
        );
        return CockpitCaptureResult(
          screenshot: screenshot,
          requestedProfile: effectiveProfile,
          resolvedCaptureKind: CockpitCaptureKind.flutterView,
          usedFallback: true,
          degradationReason: 'nativeCaptureUnavailable',
        );
      }

      try {
        final screenshot = await FlutterCockpit.binding.nativeCapture.capture(
          request: effectiveRequest,
          profile: effectiveProfile,
          snapshot: snapshotData,
        );
        return CockpitCaptureResult(
          screenshot: screenshot,
          requestedProfile: effectiveProfile,
          resolvedCaptureKind: CockpitCaptureKind.appNative,
        );
      } on Object catch (error, stackTrace) {
        if (!effectiveAllowFallback) {
          rethrow;
        }

        final CockpitCapturedScreenshot screenshot;
        try {
          screenshot = await surfaceState.captureScreenshot(effectiveRequest);
        } on Object catch (fallbackError, fallbackStackTrace) {
          Error.throwWithStackTrace(
            CockpitCaptureFallbackException(
              primaryError: error,
              primaryStackTrace: stackTrace,
              fallbackError: fallbackError,
              fallbackStackTrace: fallbackStackTrace,
            ),
            stackTrace,
          );
        }
        return CockpitCaptureResult(
          screenshot: screenshot,
          requestedProfile: effectiveProfile,
          resolvedCaptureKind: CockpitCaptureKind.flutterView,
          usedFallback: true,
          degradationReason: _captureFailureReason(error),
        );
      }
    }

    final screenshot = await surfaceState.captureScreenshot(effectiveRequest);
    return CockpitCaptureResult(
      screenshot: screenshot,
      requestedProfile: effectiveProfile,
      resolvedCaptureKind: CockpitCaptureKind.flutterView,
    );
  }

  String _captureFailureReason(Object error) {
    return switch (error) {
      PlatformException(:final code, :final message) => message ?? code,
      MissingPluginException(:final message) =>
        message ?? 'nativePluginMissing',
      _ => error.toString(),
    };
  }

  Future<CockpitRecordingCapabilities> queryRecordingCapabilities() {
    return FlutterCockpit.binding.queryRecordingCapabilities();
  }

  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) {
    return FlutterCockpit.binding.startRecording(request);
  }

  Future<CockpitRecordingResult> stopRecording() {
    return FlutterCockpit.binding.stopRecording();
  }

  /// Resizes the native viewport when the current platform exposes that
  /// capability. The result reports an unavailable capability instead of
  /// pretending that the logical size changed.
  Future<CockpitViewportResizeResult> resizeViewport(
    CockpitViewportResizeRequest request,
  ) {
    return _resizeRemoteViewport(request);
  }

  Future<void> performGesture(CockpitGestureAction action) {
    final surfaceState = _requireSurfaceState();
    return surfaceState.performGesture(action);
  }

  Uri? get remoteSessionBaseUri =>
      _remoteSessionServer?.baseUri ??
      _remoteSessionBridgeClient?.publicBaseUri;

  Future<Uri?> waitForRemoteSession() async {
    await _ensureRemoteSessionStarted();
    return remoteSessionBaseUri;
  }

  Future<CockpitRemoteSessionStatus> remoteSessionStatus() {
    return _withRemoteSessionStarted(_buildRemoteSessionStatus);
  }

  dynamic get _surfaceStateOrNull => _surfaceKey.currentState;

  dynamic _requireSurfaceState() {
    final surfaceState = _surfaceStateOrNull;
    if (surfaceState == null) {
      throw StateError('FlutterCockpitRoot is not mounted.');
    }
    return surfaceState;
  }

  @override
  void dispose() {
    for (final unbind in _routeInformationUnbinders.values) {
      unbind();
    }
    _routeInformationUnbinders.clear();
    unawaited(_remoteSessionServer?.close());
    unawaited(_remoteSessionBridgeClient?.close());
    _semanticsHandle?.dispose();
    _tapFeedbackController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = FlutterCockpit.binding;
    return ValueListenableBuilder<String>(
      valueListenable: binding.currentRouteName,
      builder: (context, routeName, child) {
        final surface = CockpitSurface(
          key: _surfaceKey,
          routeName: routeName,
          registry: binding.registry,
          gestureDelay: binding.configuration.gestureDelay,
          discoveryPolicy: binding.configuration.discoveryPolicy,
          rebuildTracker: binding.rebuildTracker,
          tapFeedbackController: _tapFeedbackController,
          child: child ?? const SizedBox.shrink(),
        );
        final tapFeedbackController = _tapFeedbackController;
        if (tapFeedbackController == null) {
          return surface;
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            surface,
            Positioned.fill(
              child: CockpitTapFeedbackOverlay(
                controller: tapFeedbackController,
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }

  void _syncTapFeedbackController() {
    final shouldEnable =
        kDebugMode &&
        FlutterCockpit.binding.configuration.diagnostics.enableTapFeedback;
    if (shouldEnable) {
      _tapFeedbackController ??= CockpitTapFeedbackController();
      return;
    }
    _tapFeedbackController?.dispose();
    _tapFeedbackController = null;
  }

  CockpitCaptureProfile _defaultProfileFor(CockpitScreenshotRequest request) {
    return request.reason == CockpitScreenshotReason.acceptance
        ? CockpitCaptureProfile.acceptance
        : CockpitCaptureProfile.diagnostic;
  }

  CockpitSnapshotOptions _defaultSnapshotOptionsFor(
    CockpitScreenshotReason reason,
  ) {
    return switch (reason) {
      CockpitScreenshotReason.assertionFailure =>
        const CockpitSnapshotOptions.investigate(),
      CockpitScreenshotReason.baseline =>
        const CockpitSnapshotOptions.baseline(),
      CockpitScreenshotReason.acceptance =>
        const CockpitSnapshotOptions.investigate(),
      CockpitScreenshotReason.beforeAction ||
      CockpitScreenshotReason.afterAction =>
        const CockpitSnapshotOptions.live(),
    };
  }

  InAppCockpitCommandExecutor _buildRemoteCommandExecutor(
    String platform, {
    String transportType = 'remoteHttp',
    Future<void> Function()? postActionSettler,
    Future<void> Function(Duration duration)? waitTickHandler,
    CockpitGestureDelay? gestureDelay,
  }) {
    return InAppCockpitCommandExecutor(
      registry: FlutterCockpit.binding.registry,
      captureHandler: (request) =>
          captureScreenshot(request, waitForIdle: false),
      snapshotProvider: snapshot,
      locatorProbe: (locator, {requiredCommand}) {
        final surface = _surfaceStateOrNull;
        return surface == null
            ? FlutterCockpit.binding.registry.resolve(
                locator,
                requiredCommand: requiredCommand,
              )
            : surface.probeVisibleLocator(
                locator,
                requiredCommand: requiredCommand,
              );
      },
      routeNameSynchronizer: FlutterCockpit.binding.setDiscoveredRouteName,
      scrollStepProbesTarget: true,
      scrollStepHandler:
          ({
            required reverse,
            required viewportFraction,
            scrollableKey,
            targetLocator,
            scrollableLocator,
            required duration,
            required gestureProfile,
            required continuous,
            required postScrollEnsureVisible,
          }) async {
            final surfaceState = _surfaceStateOrNull;
            if (surfaceState == null) {
              return const CockpitScrollStepResult(didScroll: false);
            }
            final result = await surfaceState.scrollByViewport(
              reverse: reverse,
              viewportFraction: viewportFraction,
              scrollableKey: scrollableKey,
              targetLocator: targetLocator,
              scrollableLocator: scrollableLocator,
              duration: duration,
              gestureProfile: gestureProfile,
              continuous: continuous,
              postScrollEnsureVisible: postScrollEnsureVisible,
            );
            // Test bindings do not expose a live endOfFrame future. The
            // injected settler is the authoritative frame pump for lazy
            // children after jumpTo/gesture scrolling.
            if (postActionSettler != null && result.didScroll) {
              await postActionSettler();
            }
            return result;
          },
      ensureVisibleHandler:
          ({
            required locator,
            required duration,
            required alignment,
            required padding,
            required offset,
          }) {
            final surfaceState = _surfaceStateOrNull;
            if (surfaceState == null) {
              return Future<bool>.value(false);
            }
            return surfaceState.ensureLocatorVisible(
              locator,
              duration: duration,
              alignment: alignment,
              padding: padding,
              offset: offset,
            );
          },
      gestureHandler: (action) {
        final surfaceState = _surfaceStateOrNull;
        if (surfaceState == null) {
          return Future<void>.error(
            StateError('FlutterCockpitRoot surface is not mounted.'),
          );
        }
        return surfaceState.performGesture(action, delay: gestureDelay);
      },
      clearNetworkActivityHandler:
          FlutterCockpit.binding.networkObserver == null
          ? null
          : () {
              FlutterCockpit.binding.networkObserver?.clear();
            },
      waitForNetworkIdleHandler: FlutterCockpit.binding.networkObserver == null
          ? null
          : ({required quietWindow, required timeout}) {
              return FlutterCockpit.binding.networkObserver!.waitForIdle(
                quietWindow: quietWindow,
                timeout: timeout,
              );
            },
      postActionSettler: postActionSettler,
      waitTickHandler:
          waitTickHandler ?? FlutterCockpit.binding.configuration.gestureDelay,
      interactionPolicy: FlutterCockpit.binding.configuration.interactionPolicy,
      isRecordingActive: () =>
          FlutterCockpit.binding.activeRecordingSession != null,
      backNavigationHandler: () async {
        final navigator = FlutterCockpit.binding.navigatorObserver.navigator;
        if (navigator != null && await navigator.maybePop()) {
          return true;
        }
        return cockpitMaybePopCurrentNavigator(context as Element);
      },
      dismissActionResolver: () => _surfaceStateOrNull?.resolveDismissAction(),
      platform: platform,
      transportType: transportType,
    );
  }

  Future<void> _startRemoteSessionIfEnabled() async {
    final configuration = FlutterCockpit.binding.configuration.remoteSession;
    if (configuration == null || !configuration.enabled) {
      return;
    }
    if (_remoteSessionServer != null || _remoteSessionBridgeClient != null) {
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await _nativeSemantics.enable();
      _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    }

    final executor = _buildRemoteCommandExecutor(
      resolveCockpitRemoteSessionPlatform(
        isWeb: kIsWeb,
        targetPlatform: defaultTargetPlatform,
      ),
    );
    final endpointHandler = CockpitRemoteSessionEndpointHandler(
      configuration: configuration,
      statusProvider: _buildRemoteSessionStatus,
      readyProvider: _buildRemoteSessionReady,
      snapshotProvider: _remoteSnapshot,
      commandExecutor: executor.executeWithArtifacts,
      viewportResizer: _resizeRemoteViewport,
      runtimeStepDrainer: ({required clear}) {
        return FlutterCockpit.drainRecordedSteps(clear: clear);
      },
      startRecording: startRecording,
      stopRecording: stopRecording,
    );
    if (kIsWeb) {
      final bridgeClient = CockpitRemoteSessionBridgeClient(
        configuration: configuration,
        protocol: CockpitRemoteSessionBridgeProtocol(
          requestHandler: endpointHandler.handle,
          binaryFileReader: cockpitRemoteBridgeBinaryFileReader(),
        ),
      );
      await bridgeClient.start();
      _remoteSessionBridgeClient = bridgeClient;
      return;
    }
    final server = CockpitRemoteSessionServer(
      configuration: configuration,
      statusProvider: _buildRemoteSessionStatus,
      readyProvider: _buildRemoteSessionReady,
      snapshotProvider: _remoteSnapshot,
      commandExecutor: executor.executeWithArtifacts,
      viewportResizer: _resizeRemoteViewport,
      runtimeStepDrainer: ({required clear}) {
        return FlutterCockpit.drainRecordedSteps(clear: clear);
      },
      startRecording: startRecording,
      stopRecording: stopRecording,
    );
    await server.start();
    _remoteSessionServer = server;
  }

  Map<String, Object?> _buildRemoteSessionReady() {
    final surfaceMounted = _surfaceStateOrNull != null;
    return <String, Object?>{
      'ready': surfaceMounted,
      'currentRouteName': FlutterCockpit.binding.currentRouteName.value,
      'supportsInAppControl': surfaceMounted,
    };
  }

  Future<void> _beginRemoteSessionStart({bool ignoreFailure = false}) async {
    try {
      await _startRemoteSessionIfEnabled();
      _remoteSessionStartError = null;
      _remoteSessionStartErrorStackTrace = null;
    } on Object catch (error, stackTrace) {
      _remoteSessionStartError = error;
      _remoteSessionStartErrorStackTrace = stackTrace;
      _reportRemoteSessionStartFailure(error, stackTrace);
      if (!ignoreFailure) {
        rethrow;
      }
    }
  }

  Future<void> _ensureRemoteSessionStarted() {
    final configuration = FlutterCockpit.binding.configuration.remoteSession;
    if (configuration == null || !configuration.enabled) {
      return Future<void>.value();
    }
    if (_remoteSessionStartError != null) {
      return Future<void>.error(
        _remoteSessionStartError!,
        _remoteSessionStartErrorStackTrace,
      );
    }

    return _remoteSessionStartFuture ??= _beginRemoteSessionStart();
  }

  Future<T> _withRemoteSessionStarted<T>(Future<T> Function() action) async {
    await _ensureRemoteSessionStarted();
    return action();
  }

  void _reportRemoteSessionStartFailure(Object error, StackTrace stackTrace) {
    if (_reportedRemoteSessionStartFailure) {
      return;
    }
    _reportedRemoteSessionStartFailure = true;

    final configuration = FlutterCockpit.binding.configuration.remoteSession;
    final message = 'flutter_cockpit remote session startup failed: $error';
    debugPrint(message);
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        configuration != null &&
        configuration.host != '127.0.0.1' &&
        configuration.host != 'localhost') {
      debugPrint(
        'flutter_cockpit iOS hint: remote-session host ${configuration.host} '
        'may require local network access and a reachable device-side bind.',
      );
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'Failed to start the flutter_cockpit remote session: $error',
        ),
        stack: stackTrace,
        library: 'flutter_cockpit',
        context: ErrorDescription(
          'while starting the flutter_cockpit remote session',
        ),
        informationCollector: () sync* {
          if (configuration != null) {
            yield DiagnosticsProperty<CockpitRemoteSessionConfiguration>(
              'remoteSessionConfiguration',
              configuration,
            );
            final host = configuration.host;
            if (defaultTargetPlatform == TargetPlatform.iOS &&
                host != '127.0.0.1' &&
                host != 'localhost') {
              yield ErrorHint(
                'Physical iOS apps that expose flutter_cockpit over the '
                'device network must declare NSLocalNetworkUsageDescription '
                'in Info.plist and allow local network access.',
              );
            }
          }
        },
      ),
    );
  }

  Future<CockpitRemoteSessionStatus> _buildRemoteSessionStatus() async {
    final remoteSessionPlatform = resolveCockpitRemoteSessionPlatform(
      isWeb: kIsWeb,
      targetPlatform: defaultTargetPlatform,
    );
    final currentRouteName = FlutterCockpit.binding.currentRouteName.value;
    final executor = _buildRemoteCommandExecutor(remoteSessionPlatform);
    final baseCapabilities = await executor.describeCapabilities();
    final supportsNativeCapture = await FlutterCockpit.binding
        .queryNativeCaptureAvailability();
    final viewportAvailability = await _nativeViewport.queryAvailability(
      platform: remoteSessionPlatform,
    );
    final configuredLaunchId = FlutterCockpit
        .binding
        .configuration
        .remoteSession
        ?.launchId
        .trim();
    final sessionId = configuredLaunchId == null || configuredLaunchId.isEmpty
        ? 'cockpit-$remoteSessionPlatform-${remoteSessionBaseUri?.port ?? 0}'
        : configuredLaunchId;
    return CockpitRemoteSessionStatus(
      sessionId: sessionId,
      platform: remoteSessionPlatform,
      transportType: 'remoteHttp',
      currentRouteName: currentRouteName,
      processId: cockpitCurrentProcessId(),
      capabilities: CockpitCapabilities(
        platform: baseCapabilities.platform,
        transportType: baseCapabilities.transportType,
        supportsInAppControl: baseCapabilities.supportsInAppControl,
        supportsFlutterViewCapture: baseCapabilities.supportsFlutterViewCapture,
        supportsNativeScreenCapture: supportsNativeCapture,
        supportsHostAutomation: baseCapabilities.supportsHostAutomation,
        supportsViewportResize: viewportAvailability.available,
        viewportResizeAlternative:
            viewportAvailability.alternatives.firstOrNull,
        supportedCommands: baseCapabilities.supportedCommands,
        supportedLocatorStrategies: baseCapabilities.supportedLocatorStrategies,
      ),
      recordingCapabilities:
          await _recordingCapabilitiesForRemoteSessionHealth(),
      snapshot: _snapshotForRemoteSessionHealth(currentRouteName),
      environment: _runtimeEnvironmentForRemoteSessionHealth(),
      activeRecording: FlutterCockpit.binding.activeRecordingSession,
    );
  }

  Future<CockpitViewportResizeResult> _resizeRemoteViewport(
    CockpitViewportResizeRequest request,
  ) async {
    final platform = resolveCockpitRemoteSessionPlatform(
      isWeb: kIsWeb,
      targetPlatform: defaultTargetPlatform,
    );
    final before = _currentViewportMetrics();
    final availability = await _nativeViewport.queryAvailability(
      platform: platform,
    );
    if (!availability.available) {
      return CockpitViewportResizeResult(
        available: false,
        changed: false,
        requestedWidth: request.width,
        requestedHeight: request.height,
        platform: platform,
        logicalWidth: before.logicalWidth,
        logicalHeight: before.logicalHeight,
        physicalWidth: before.physicalWidth,
        physicalHeight: before.physicalHeight,
        devicePixelRatio: before.devicePixelRatio,
        reason: availability.reason ?? 'viewportUnavailable',
        alternatives: availability.alternatives,
      );
    }

    final resize = await _nativeViewport.resize(
      width: request.width,
      height: request.height,
    );
    if (!resize.accepted) {
      return CockpitViewportResizeResult(
        available: false,
        changed: false,
        requestedWidth: request.width,
        requestedHeight: request.height,
        platform: platform,
        logicalWidth: before.logicalWidth,
        logicalHeight: before.logicalHeight,
        physicalWidth: before.physicalWidth,
        physicalHeight: before.physicalHeight,
        devicePixelRatio: before.devicePixelRatio,
        reason: resize.reason ?? 'viewportResizeRejected',
        alternatives: resize.alternatives,
      );
    }
    final effective = await _waitForViewport(
      width: request.width,
      height: request.height,
    );
    return CockpitViewportResizeResult(
      available: true,
      changed:
          (before.logicalWidth - effective.logicalWidth).abs() > 0.5 ||
          (before.logicalHeight - effective.logicalHeight).abs() > 0.5,
      requestedWidth: request.width,
      requestedHeight: request.height,
      platform: platform,
      logicalWidth: effective.logicalWidth,
      logicalHeight: effective.logicalHeight,
      physicalWidth: effective.physicalWidth,
      physicalHeight: effective.physicalHeight,
      devicePixelRatio: effective.devicePixelRatio,
    );
  }

  Future<_CockpitViewportMetrics> _waitForViewport({
    required int width,
    required int height,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var settledFrames = 0;
    var metrics = _currentViewportMetrics();
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
      metrics = _currentViewportMetrics();
      final matches =
          (metrics.logicalWidth - width).abs() <= 1 &&
          (metrics.logicalHeight - height).abs() <= 1;
      if (!matches) {
        settledFrames = 0;
        continue;
      }
      settledFrames += 1;
      if (settledFrames >= 2) return metrics;
    }
    throw StateError(
      'Viewport resize did not settle at ${width}x$height logical pixels; '
      'effective size is ${metrics.logicalWidth}x${metrics.logicalHeight}.',
    );
  }

  _CockpitViewportMetrics _currentViewportMetrics() {
    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    return _CockpitViewportMetrics(
      logicalWidth: view.physicalSize.width / dpr,
      logicalHeight: view.physicalSize.height / dpr,
      physicalWidth: view.physicalSize.width.round(),
      physicalHeight: view.physicalSize.height.round(),
      devicePixelRatio: dpr,
    );
  }

  Future<CockpitRecordingCapabilities>
  _recordingCapabilitiesForRemoteSessionHealth() async {
    try {
      return await queryRecordingCapabilities();
    } on Object catch (error) {
      return CockpitRecordingCapabilities(
        supportsNativeRecording: false,
        preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
        supportedLayers: const <CockpitRecordingLayer>[],
        recordingLimitations: <String>[error.toString()],
      );
    }
  }

  CockpitSnapshot _snapshotForRemoteSessionHealth(String currentRouteName) {
    try {
      return snapshot(
        options: const CockpitSnapshotOptions(
          profile: CockpitSnapshotProfile.live,
          includeNetworkActivity: true,
          maxNetworkEntries: 4,
          networkQuery: CockpitNetworkQuery(onlyFailures: true),
          includeRuntimeActivity: true,
          maxRuntimeEntries: 4,
          runtimeQuery: CockpitRuntimeQuery(onlyErrors: true),
        ),
      );
    } on Object {
      return CockpitSnapshot(
        routeName: currentRouteName,
        diagnosticLevel: CockpitSnapshotProfile.live,
      );
    }
  }

  CockpitEnvironment? _runtimeEnvironmentForRemoteSessionHealth() {
    try {
      return FlutterCockpit.binding.resolveRuntimeEnvironment(
        platform: defaultTargetPlatform.name,
      );
    } on Object {
      return null;
    }
  }
}

bool _isTestBinding(WidgetsBinding binding) {
  return binding.runtimeType.toString().contains('TestWidgetsFlutterBinding');
}

final class _CockpitViewportMetrics {
  const _CockpitViewportMetrics({
    required this.logicalWidth,
    required this.logicalHeight,
    required this.physicalWidth,
    required this.physicalHeight,
    required this.devicePixelRatio,
  });

  final double logicalWidth;
  final double logicalHeight;
  final int physicalWidth;
  final int physicalHeight;
  final double devicePixelRatio;
}

bool cockpitCaptureProfilePrefersNative(
  CockpitCaptureProfile profile, {
  required bool isWeb,
  TargetPlatform? platform,
}) {
  if (profile == CockpitCaptureProfile.nativePreferred) return true;
  if (isWeb || profile != CockpitCaptureProfile.acceptance) return false;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => false,
  };
}
