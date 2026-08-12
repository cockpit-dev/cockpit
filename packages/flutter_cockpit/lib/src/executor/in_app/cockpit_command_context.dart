import '../../capture/cockpit_capture_result.dart';
import '../../control/cockpit_command_type.dart';
import '../../control/cockpit_locator.dart';
import '../../control/cockpit_screenshot_request.dart';
import '../../gesture/cockpit_gesture_action.dart';
import '../../gesture/cockpit_gesture_profile.dart';
import '../../runtime/cockpit_interaction_policy.dart';
import '../../runtime/cockpit_key_event_request.dart';
import '../../runtime/cockpit_reveal_alignment.dart';
import '../../runtime/cockpit_scroll_step_result.dart';
import '../../runtime/cockpit_snapshot.dart';
import '../../runtime/cockpit_snapshot_options.dart';
import '../../runtime/cockpit_target_registry.dart';

typedef CockpitCaptureHandler =
    Future<CockpitCaptureResult> Function(CockpitScreenshotRequest request);
typedef CockpitSnapshotProvider =
    CockpitSnapshot Function({CockpitSnapshotOptions options});
typedef CockpitLocatorProbe =
    CockpitTargetResolutionResult Function(
      CockpitLocator locator, {
      CockpitCommandType? requiredCommand,
    });
typedef CockpitPostActionSettler = Future<void> Function();
typedef CockpitScrollStepHandler =
    Future<CockpitScrollStepResult> Function({
      required bool reverse,
      required double viewportFraction,
      String? scrollableKey,
      CockpitLocator? targetLocator,
      CockpitLocator? scrollableLocator,
      required Duration duration,
      required CockpitGestureProfile gestureProfile,
      required bool continuous,
      required bool postScrollEnsureVisible,
    });
typedef CockpitEnsureVisibleHandler =
    Future<bool> Function({
      required CockpitLocator locator,
      required Duration duration,
      required CockpitRevealAlignment alignment,
      required double padding,
      required double offset,
    });
typedef CockpitGestureHandler =
    Future<void> Function(CockpitGestureAction action);
typedef CockpitNetworkActivityClearer = void Function();
typedef CockpitNetworkIdleWaiter =
    Future<bool> Function({
      required Duration quietWindow,
      required Duration timeout,
    });
typedef CockpitBackNavigationHandler = Future<bool> Function();
typedef CockpitWaitTickHandler = Future<void> Function(Duration duration);
typedef CockpitRecordingActivityProbe = bool Function();
typedef CockpitRouteNameSynchronizer = void Function(String? routeName);
typedef CockpitKeyEventHandler =
    Future<bool> Function(
      CockpitKeyEventRequest request,
      CockpitCommandType type,
    );

final class CockpitInAppCommandContext {
  CockpitInAppCommandContext({
    required this.registry,
    required this.captureHandler,
    required this.snapshotProvider,
    required this.locatorProbe,
    required this.postActionSettler,
    required this.scrollStepHandler,
    required this.scrollStepProbesTarget,
    required this.ensureVisibleHandler,
    required this.gestureHandler,
    required this.clearNetworkActivityHandler,
    required this.waitForNetworkIdleHandler,
    required this.backNavigationHandler,
    required this.hasCustomWaitTickHandler,
    required this.waitTickHandler,
    required this.keyEventHandler,
    required this.interactionPolicy,
    required this.isRecordingActive,
    required this.routeNameSynchronizer,
    required this.platform,
    required this.transportType,
  });

  final CockpitTargetRegistry registry;
  final CockpitCaptureHandler? captureHandler;
  final CockpitSnapshotProvider snapshotProvider;
  final CockpitLocatorProbe? locatorProbe;
  final CockpitPostActionSettler postActionSettler;
  final CockpitScrollStepHandler? scrollStepHandler;
  final bool scrollStepProbesTarget;
  final CockpitEnsureVisibleHandler? ensureVisibleHandler;
  final CockpitGestureHandler? gestureHandler;
  final CockpitNetworkActivityClearer? clearNetworkActivityHandler;
  final CockpitNetworkIdleWaiter? waitForNetworkIdleHandler;
  final CockpitBackNavigationHandler? backNavigationHandler;
  final bool hasCustomWaitTickHandler;
  final CockpitWaitTickHandler waitTickHandler;
  final CockpitKeyEventHandler keyEventHandler;
  final CockpitInteractionPolicy interactionPolicy;
  final CockpitRecordingActivityProbe isRecordingActive;
  final CockpitRouteNameSynchronizer? routeNameSynchronizer;
  final String platform;
  final String transportType;

  CockpitSnapshot liveSnapshot() {
    return snapshotProvider(options: const CockpitSnapshotOptions.live());
  }
}
