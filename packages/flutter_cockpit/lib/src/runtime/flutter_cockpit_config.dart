import '../capture/cockpit_native_capture.dart';
import '../gesture/cockpit_gesture_engine.dart';
import '../network/cockpit_http_network_observer_configuration.dart';
import '../network/cockpit_network_observer.dart';
import '../recording/cockpit_native_recording.dart';
import '../remote/cockpit_remote_session_configuration.dart';
import '../session/cockpit_session_controller.dart';
import 'cockpit_discovery_policy.dart';
import 'cockpit_diagnostics_config.dart';
import 'flutter_cockpit_configuration.dart';
import 'cockpit_interaction_policy.dart';
import 'cockpit_runtime_observer.dart';
import 'cockpit_runtime_observer_configuration.dart';
import 'cockpit_target_registry.dart';
import '../performance/cockpit_performance_collector.dart';

final class FlutterCockpitConfig {
  const FlutterCockpitConfig({
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
    this.runtimeObserver,
    this.runtimeObserverConfiguration =
        const CockpitRuntimeObserverConfiguration(),
    this.interactionPolicy = const CockpitInteractionPolicy(),
    this.discoveryPolicy = const CockpitDiscoveryPolicy(),
    this.diagnostics = const CockpitDiagnosticsConfig(),
  });

  const FlutterCockpitConfig.production({
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
    this.runtimeObserver,
    this.runtimeObserverConfiguration =
        const CockpitRuntimeObserverConfiguration(),
    this.interactionPolicy = const CockpitInteractionPolicy(),
    this.discoveryPolicy = const CockpitDiscoveryPolicy(),
    this.diagnostics = const CockpitDiagnosticsConfig(),
  });

  factory FlutterCockpitConfig.fromRuntimeConfiguration(
    FlutterCockpitConfiguration configuration,
  ) {
    return FlutterCockpitConfig(
      initialRouteName: configuration.initialRouteName,
      flutterVersion: configuration.flutterVersion,
      registry: configuration.registry,
      nativeCapture: configuration.nativeCapture,
      nativeRecording: configuration.nativeRecording,
      remoteSession: configuration.remoteSession,
      gestureDelay: configuration.gestureDelay,
      sessionController: configuration.sessionController,
      networkObserver: configuration.networkObserver,
      httpNetworkObserver: configuration.httpNetworkObserver,
      performanceCollector: configuration.performanceCollector,
      runtimeObserver: configuration.runtimeObserver,
      runtimeObserverConfiguration: configuration.runtimeObserverConfiguration,
      interactionPolicy: configuration.interactionPolicy,
      discoveryPolicy: configuration.discoveryPolicy,
      diagnostics: configuration.diagnostics,
    );
  }

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
  final CockpitRuntimeObserver? runtimeObserver;
  final CockpitRuntimeObserverConfiguration runtimeObserverConfiguration;
  final CockpitInteractionPolicy interactionPolicy;
  final CockpitDiscoveryPolicy discoveryPolicy;
  final CockpitDiagnosticsConfig diagnostics;

  FlutterCockpitConfiguration toRuntimeConfiguration() {
    return FlutterCockpitConfiguration(
      initialRouteName: initialRouteName,
      flutterVersion: flutterVersion,
      registry: registry,
      nativeCapture: nativeCapture,
      nativeRecording: nativeRecording,
      remoteSession: remoteSession,
      gestureDelay: gestureDelay,
      sessionController: sessionController,
      networkObserver: networkObserver,
      httpNetworkObserver: httpNetworkObserver,
      performanceCollector: performanceCollector,
      runtimeObserver: runtimeObserver,
      runtimeObserverConfiguration: runtimeObserverConfiguration,
      interactionPolicy: interactionPolicy,
      discoveryPolicy: discoveryPolicy,
      diagnostics: diagnostics,
    );
  }

  FlutterCockpitConfig copyWith({
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
    CockpitRuntimeObserver? runtimeObserver,
    CockpitRuntimeObserverConfiguration? runtimeObserverConfiguration,
    CockpitInteractionPolicy? interactionPolicy,
    CockpitDiscoveryPolicy? discoveryPolicy,
    CockpitDiagnosticsConfig? diagnostics,
  }) {
    return FlutterCockpitConfig(
      initialRouteName: initialRouteName ?? this.initialRouteName,
      flutterVersion: flutterVersion ?? this.flutterVersion,
      registry: registry ?? this.registry,
      nativeCapture: nativeCapture ?? this.nativeCapture,
      nativeRecording: nativeRecording ?? this.nativeRecording,
      remoteSession: remoteSession ?? this.remoteSession,
      gestureDelay: gestureDelay ?? this.gestureDelay,
      sessionController: sessionController ?? this.sessionController,
      networkObserver: networkObserver ?? this.networkObserver,
      httpNetworkObserver: httpNetworkObserver ?? this.httpNetworkObserver,
      performanceCollector: performanceCollector ?? this.performanceCollector,
      runtimeObserver: runtimeObserver ?? this.runtimeObserver,
      runtimeObserverConfiguration:
          runtimeObserverConfiguration ?? this.runtimeObserverConfiguration,
      interactionPolicy: interactionPolicy ?? this.interactionPolicy,
      discoveryPolicy: discoveryPolicy ?? this.discoveryPolicy,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlutterCockpitConfig &&
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
    runtimeObserver,
    runtimeObserverConfiguration,
    interactionPolicy,
    discoveryPolicy,
    diagnostics,
  );
}
