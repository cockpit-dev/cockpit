import 'dart:async';
import 'dart:collection';

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
import '../../runtime/cockpit_target.dart';
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
typedef CockpitDismissActionResolver = CockpitSemanticActionHandler? Function();
typedef CockpitWaitTickHandler = Future<void> Function(Duration duration);
typedef CockpitRecordingActivityProbe = bool Function();
typedef CockpitRouteNameSynchronizer = void Function(String? routeName);
typedef CockpitKeyEventHandler =
    Future<bool> Function(
      CockpitKeyEventRequest request,
      CockpitCommandType type,
    );

final class CockpitInAppCommandContext {
  factory CockpitInAppCommandContext({
    required CockpitTargetRegistry registry,
    required CockpitCaptureHandler? captureHandler,
    required CockpitSnapshotProvider snapshotProvider,
    required CockpitLocatorProbe? locatorProbe,
    required CockpitPostActionSettler postActionSettler,
    required CockpitScrollStepHandler? scrollStepHandler,
    required bool scrollStepProbesTarget,
    required CockpitEnsureVisibleHandler? ensureVisibleHandler,
    required CockpitGestureHandler? gestureHandler,
    required CockpitNetworkActivityClearer? clearNetworkActivityHandler,
    required CockpitNetworkIdleWaiter? waitForNetworkIdleHandler,
    required CockpitBackNavigationHandler? backNavigationHandler,
    required CockpitDismissActionResolver? dismissActionResolver,
    required bool hasCustomWaitTickHandler,
    required CockpitWaitTickHandler waitTickHandler,
    required CockpitKeyEventHandler keyEventHandler,
    required CockpitInteractionPolicy interactionPolicy,
    required CockpitRecordingActivityProbe isRecordingActive,
    required CockpitRouteNameSynchronizer? routeNameSynchronizer,
    required String platform,
    required String transportType,
  }) {
    final callbacks = _CockpitSerializedCallbacks(
      postActionSettler: postActionSettler,
      waitTickHandler: waitTickHandler,
    );
    return CockpitInAppCommandContext._(
      registry: registry,
      captureHandler: captureHandler,
      snapshotProvider: snapshotProvider,
      locatorProbe: locatorProbe,
      postActionSettler: callbacks.postActionSettler,
      scrollStepHandler: scrollStepHandler,
      scrollStepProbesTarget: scrollStepProbesTarget,
      ensureVisibleHandler: ensureVisibleHandler,
      gestureHandler: gestureHandler,
      clearNetworkActivityHandler: clearNetworkActivityHandler,
      waitForNetworkIdleHandler: waitForNetworkIdleHandler,
      backNavigationHandler: backNavigationHandler,
      dismissActionResolver: dismissActionResolver,
      hasCustomWaitTickHandler: hasCustomWaitTickHandler,
      waitTickHandler: callbacks.waitTickHandler,
      keyEventHandler: keyEventHandler,
      interactionPolicy: interactionPolicy,
      isRecordingActive: isRecordingActive,
      routeNameSynchronizer: routeNameSynchronizer,
      platform: platform,
      transportType: transportType,
    );
  }

  CockpitInAppCommandContext._({
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
    required this.dismissActionResolver,
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
  final CockpitDismissActionResolver? dismissActionResolver;
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

final class _CockpitSerializedCallbacks {
  _CockpitSerializedCallbacks({
    required CockpitPostActionSettler postActionSettler,
    required CockpitWaitTickHandler waitTickHandler,
  }) : _postActionSettler = postActionSettler,
       _waitTickHandler = waitTickHandler;

  final CockpitPostActionSettler _postActionSettler;
  final CockpitWaitTickHandler _waitTickHandler;
  final _CockpitCallbackQueue _queue = _CockpitCallbackQueue();

  Future<void> postActionSettler() => _queue.run(_postActionSettler);

  Future<void> waitTickHandler(Duration duration) =>
      _queue.run(() => _waitTickHandler(duration));
}

final class _CockpitCallbackQueue {
  final Queue<_CockpitQueuedCallback> _pending =
      Queue<_CockpitQueuedCallback>();
  bool _active = false;

  Future<void> run(Future<void> Function() callback) {
    final completion = Completer<void>();
    _pending.add(
      _CockpitQueuedCallback(
        callback: callback,
        completion: completion,
        zone: Zone.current,
      ),
    );
    _startNext();
    return completion.future;
  }

  void _startNext() {
    if (_active || _pending.isEmpty) return;
    _active = true;
    final task = _pending.removeFirst();
    task.zone
        .run<Future<void>>(() => Future<void>.sync(task.callback))
        .then<void>(
          (_) => task.completion.complete(),
          onError: (Object error, StackTrace stackTrace) {
            task.completion.completeError(error, stackTrace);
          },
        )
        .whenComplete(() {
          _active = false;
          scheduleMicrotask(_startNext);
        });
  }
}

final class _CockpitQueuedCallback {
  const _CockpitQueuedCallback({
    required this.callback,
    required this.completion,
    required this.zone,
  });

  final Future<void> Function() callback;
  final Completer<void> completion;
  final Zone zone;
}
