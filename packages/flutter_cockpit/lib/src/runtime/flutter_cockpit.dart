import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/widgets.dart' as widgets;

import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../control/cockpit_command_status.dart';
import '../control/cockpit_command_type.dart';
import '../control/cockpit_locator.dart';
import '../control/cockpit_locator_resolution.dart';
import '../model/cockpit_artifact_ref.dart';
import '../model/cockpit_observation.dart';
import '../runtime/cockpit_snapshot.dart';
import '../model/cockpit_step_record.dart';
import 'cockpit_flutter_runtime_observer.dart';
import 'flutter_cockpit_binding.dart';
import 'flutter_cockpit_config.dart';
import 'flutter_cockpit_configuration.dart';
import 'flutter_cockpit_root.dart';
import '../performance/cockpit_performance_collector.dart';
import '../performance/cockpit_performance_plugin.dart';

abstract final class FlutterCockpit {
  static FlutterCockpitBinding? _binding;

  static FlutterCockpitBinding initialize([
    FlutterCockpitConfiguration configuration =
        const FlutterCockpitConfiguration(),
  ]) {
    final existing = _binding;
    if (existing != null) {
      existing.updateConfiguration(configuration);
      return existing;
    }
    _binding = FlutterCockpitBinding(configuration);
    return _binding!;
  }

  static FlutterCockpitBinding get binding {
    return _binding ?? initialize();
  }

  static bool get isInitialized => _binding != null;

  static FlutterCockpitBinding bootstrap([
    FlutterCockpitConfig config = const FlutterCockpitConfig.production(),
  ]) {
    return initialize(config.toRuntimeConfiguration());
  }

  static FlutterCockpitBinding ensureInitialized([
    FlutterCockpitConfig config = const FlutterCockpitConfig.production(),
  ]) {
    widgets.WidgetsFlutterBinding.ensureInitialized();
    return bootstrap(config);
  }

  static void runApp(
    widgets.Widget child, {
    FlutterCockpitConfig config = const FlutterCockpitConfig.production(),
  }) {
    final binding = ensureInitialized(config);
    final observer = binding.runtimeObserver;

    void mount() {
      widgets.runApp(FlutterCockpitRoot(child: child));
    }

    if (observer case final CockpitFlutterRuntimeObserver runtimeObserver) {
      runtimeObserver.runWithDiagnosticsZone(mount);
      return;
    }
    mount();
  }

  static void dispose() {
    _binding?.dispose();
    _binding = null;
  }

  static widgets.NavigatorObserver get navigatorObserver =>
      binding.navigatorObserver;

  /// The explicit performance collector owned by this runtime session.
  static CockpitPerformanceCollector get performanceCollector =>
      binding.performanceCollector;

  /// Plugins configured for the current development runtime.
  static CockpitPerformancePluginRegistry get performancePlugins =>
      binding.performancePlugins;

  /// Creates a navigator observer for a nested Navigator or router-managed
  /// navigator. Each Navigator must receive its own observer instance.
  static widgets.NavigatorObserver createNavigatorObserver() =>
      binding.createNavigatorObserver();

  /// Binds a public Flutter router provider, including providers exposed by
  /// go_router and other Router-based packages.
  static foundation.VoidCallback bindRouteInformationProvider(
    widgets.RouteInformationProvider provider,
  ) => binding.bindRouteInformationProvider(provider);

  static void setCurrentRouteName(String routeName) {
    binding.setCurrentRouteName(routeName);
  }

  static void recordStep({
    required String actionType,
    required Map<String, Object?> actionArgs,
    CockpitObservation? observation,
    CockpitSnapshot? snapshot,
    List<CockpitArtifactRef> artifactRefs = const [],
    CockpitCommandType? commandType,
    CockpitLocator? locator,
    CockpitLocatorResolution? locatorResolution,
    int? durationMs,
    CockpitCommandStatus? status,
    CockpitCaptureProfile? requestedCaptureProfile,
    CockpitCaptureKind? resolvedCaptureKind,
    bool usedCaptureFallback = false,
    String? degradationReason,
    List<CockpitArtifactRef> captureRefs = const [],
  }) {
    binding.runtimeStepBuffer.recordStep(
      actionType: actionType,
      actionArgs: actionArgs,
      observation: observation,
      snapshot: snapshot,
      artifactRefs: artifactRefs,
      commandType: commandType,
      locator: locator,
      locatorResolution: locatorResolution,
      durationMs: durationMs,
      status: status,
      requestedCaptureProfile: requestedCaptureProfile,
      resolvedCaptureKind: resolvedCaptureKind,
      usedCaptureFallback: usedCaptureFallback,
      degradationReason: degradationReason,
      captureRefs: captureRefs,
    );
    binding.sessionController.recordStep(
      actionType: actionType,
      actionArgs: actionArgs,
      observation: observation,
      snapshot: snapshot,
      artifactRefs: artifactRefs,
      commandType: commandType,
      locator: locator,
      locatorResolution: locatorResolution,
      durationMs: durationMs,
      status: status,
      requestedCaptureProfile: requestedCaptureProfile,
      resolvedCaptureKind: resolvedCaptureKind,
      usedCaptureFallback: usedCaptureFallback,
      degradationReason: degradationReason,
      captureRefs: captureRefs,
    );
  }

  static List<CockpitStepRecord> drainRecordedSteps({bool clear = true}) {
    return binding.runtimeStepBuffer.drain(clear: clear);
  }

  static void clearRecordedSteps() {
    binding.runtimeStepBuffer.clear();
  }
}
