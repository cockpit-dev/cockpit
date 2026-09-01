import '../capture/cockpit_native_capture.dart';
import '../gesture/cockpit_gesture_engine.dart';
import '../network/cockpit_http_network_observer_configuration.dart';
import '../network/cockpit_network_observer.dart';
import '../remote/cockpit_remote_session_configuration.dart';
import '../recording/cockpit_native_recording.dart';
import 'cockpit_runtime_observer.dart';
import 'cockpit_runtime_observer_configuration.dart';
import '../session/cockpit_session_controller.dart';
import 'cockpit_interaction_policy.dart';
import 'cockpit_target_registry.dart';
import 'cockpit_discovery_policy.dart';
import 'cockpit_diagnostics_config.dart';
import '../performance/cockpit_performance_collector.dart';
import '../performance/cockpit_performance_plugin.dart';

final class FlutterCockpitConfiguration {
  const FlutterCockpitConfiguration({
    this.initialRouteName = '/',
    this.flutterVersion,
    this.registry,
    this.nativeCapture,
    this.nativeRecording,
    this.remoteSession,
    this.gestureDelay,
    this.sessionController,
    this.networkObserver,
    this.httpNetworkObserver,
    this.performanceCollector,
    this.performancePlugins = const <CockpitPerformancePlugin>[],
    this.runtimeObserver,
    this.runtimeObserverConfiguration =
        const CockpitRuntimeObserverConfiguration(),
    this.interactionPolicy = const CockpitInteractionPolicy(),
    this.discoveryPolicy = const CockpitDiscoveryPolicy(),
    this.diagnostics = const CockpitDiagnosticsConfig(),
  });

  final String initialRouteName;
  final String? flutterVersion;
  final CockpitTargetRegistry? registry;
  final CockpitNativeCapture? nativeCapture;
  final CockpitNativeRecording? nativeRecording;
  final CockpitRemoteSessionConfiguration? remoteSession;
  final CockpitGestureDelay? gestureDelay;
  final CockpitSessionController? sessionController;
  final CockpitNetworkObserver? networkObserver;
  final CockpitHttpNetworkObserverConfiguration? httpNetworkObserver;
  final CockpitPerformanceCollector? performanceCollector;
  final List<CockpitPerformancePlugin> performancePlugins;
  final CockpitRuntimeObserver? runtimeObserver;
  final CockpitRuntimeObserverConfiguration runtimeObserverConfiguration;
  final CockpitInteractionPolicy interactionPolicy;
  final CockpitDiscoveryPolicy discoveryPolicy;
  final CockpitDiagnosticsConfig diagnostics;

  FlutterCockpitConfiguration copyWith({
    String? initialRouteName,
    String? flutterVersion,
    CockpitTargetRegistry? registry,
    CockpitNativeCapture? nativeCapture,
    CockpitNativeRecording? nativeRecording,
    CockpitRemoteSessionConfiguration? remoteSession,
    CockpitGestureDelay? gestureDelay,
    CockpitSessionController? sessionController,
    CockpitNetworkObserver? networkObserver,
    CockpitHttpNetworkObserverConfiguration? httpNetworkObserver,
    CockpitPerformanceCollector? performanceCollector,
    Iterable<CockpitPerformancePlugin>? performancePlugins,
    CockpitRuntimeObserver? runtimeObserver,
    CockpitRuntimeObserverConfiguration? runtimeObserverConfiguration,
    CockpitInteractionPolicy? interactionPolicy,
    CockpitDiscoveryPolicy? discoveryPolicy,
    CockpitDiagnosticsConfig? diagnostics,
    bool clearFlutterVersion = false,
    bool clearRegistry = false,
    bool clearNativeCapture = false,
    bool clearNativeRecording = false,
    bool clearRemoteSession = false,
    bool clearGestureDelay = false,
    bool clearSessionController = false,
    bool clearNetworkObserver = false,
    bool clearHttpNetworkObserver = false,
    bool clearPerformanceCollector = false,
    bool clearRuntimeObserver = false,
    bool clearRuntimeObserverConfiguration = false,
    bool clearInteractionPolicy = false,
    bool clearDiscoveryPolicy = false,
    bool clearDiagnostics = false,
  }) {
    return FlutterCockpitConfiguration(
      initialRouteName: initialRouteName ?? this.initialRouteName,
      flutterVersion: clearFlutterVersion
          ? null
          : (flutterVersion ?? this.flutterVersion),
      registry: clearRegistry ? null : (registry ?? this.registry),
      nativeCapture: clearNativeCapture
          ? null
          : (nativeCapture ?? this.nativeCapture),
      nativeRecording: clearNativeRecording
          ? null
          : (nativeRecording ?? this.nativeRecording),
      remoteSession: clearRemoteSession
          ? null
          : (remoteSession ?? this.remoteSession),
      gestureDelay: clearGestureDelay
          ? null
          : (gestureDelay ?? this.gestureDelay),
      sessionController: clearSessionController
          ? null
          : (sessionController ?? this.sessionController),
      networkObserver: clearNetworkObserver
          ? null
          : (networkObserver ?? this.networkObserver),
      httpNetworkObserver: clearHttpNetworkObserver
          ? null
          : (httpNetworkObserver ?? this.httpNetworkObserver),
      performanceCollector: clearPerformanceCollector
          ? null
          : (performanceCollector ?? this.performanceCollector),
      performancePlugins: performancePlugins == null
          ? this.performancePlugins
          : List<CockpitPerformancePlugin>.unmodifiable(performancePlugins),
      runtimeObserver: clearRuntimeObserver
          ? null
          : (runtimeObserver ?? this.runtimeObserver),
      runtimeObserverConfiguration: clearRuntimeObserverConfiguration
          ? const CockpitRuntimeObserverConfiguration()
          : (runtimeObserverConfiguration ?? this.runtimeObserverConfiguration),
      interactionPolicy: clearInteractionPolicy
          ? const CockpitInteractionPolicy()
          : (interactionPolicy ?? this.interactionPolicy),
      discoveryPolicy: clearDiscoveryPolicy
          ? const CockpitDiscoveryPolicy()
          : (discoveryPolicy ?? this.discoveryPolicy),
      diagnostics: clearDiagnostics
          ? const CockpitDiagnosticsConfig()
          : (diagnostics ?? this.diagnostics),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlutterCockpitConfiguration &&
            other.initialRouteName == initialRouteName &&
            other.flutterVersion == flutterVersion &&
            other.registry == registry &&
            other.nativeCapture == nativeCapture &&
            other.nativeRecording == nativeRecording &&
            other.remoteSession == remoteSession &&
            other.gestureDelay == gestureDelay &&
            other.sessionController == sessionController &&
            other.networkObserver == networkObserver &&
            other.httpNetworkObserver == httpNetworkObserver &&
            other.performanceCollector == performanceCollector &&
            _samePlugins(other.performancePlugins, performancePlugins) &&
            other.runtimeObserver == runtimeObserver &&
            other.runtimeObserverConfiguration ==
                runtimeObserverConfiguration &&
            other.interactionPolicy == interactionPolicy &&
            other.discoveryPolicy == discoveryPolicy &&
            other.diagnostics == diagnostics;
  }

  @override
  int get hashCode => Object.hash(
    initialRouteName,
    flutterVersion,
    registry,
    nativeCapture,
    nativeRecording,
    remoteSession,
    gestureDelay,
    sessionController,
    networkObserver,
    httpNetworkObserver,
    performanceCollector,
    Object.hashAll(performancePlugins),
    runtimeObserver,
    runtimeObserverConfiguration,
    interactionPolicy,
    discoveryPolicy,
    diagnostics,
  );
}

bool _samePlugins(
  List<CockpitPerformancePlugin> left,
  List<CockpitPerformancePlugin> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (!identical(left[index], right[index])) return false;
  }
  return true;
}
