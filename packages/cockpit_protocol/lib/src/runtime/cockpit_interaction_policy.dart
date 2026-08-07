import 'cockpit_hit_test_miss_policy.dart';

final class CockpitInteractionPolicy {
  /// Creates a CockpitInteractionPolicy.
  const CockpitInteractionPolicy({
    this.targetResolveTimeout = const Duration(seconds: 2),
    this.targetResolvePollInterval = const Duration(milliseconds: 32),
    this.uiIdleQuietWindow = const Duration(milliseconds: 96),
    this.uiIdleTimeout = const Duration(milliseconds: 1600),
    this.preActionVisualDelay = const Duration(milliseconds: 40),
    this.recordingPreActionVisualDelay = const Duration(milliseconds: 120),
    this.actionCommitTimeout = const Duration(milliseconds: 1200),
    this.actionVisualDelay = const Duration(milliseconds: 48),
    this.routeTransitionVisualDelay = const Duration(milliseconds: 96),
    this.recordingActionVisualDelay = const Duration(milliseconds: 160),
    this.waitForNetworkIdleDuringAcceptanceCapture = true,
    // Fail fast by default: continuing after a hit-test miss dispatches the
    // gesture at a position the target does not own (off-viewport or
    // covered), which can silently tap an unrelated widget and then burn the
    // whole command timeout waiting for a commit that never matches. Agents
    // get a structured targetNotHittable error with a recovery hint instead.
    this.hitTestMissPolicy = CockpitHitTestMissPolicy.fail,
  });

  final Duration targetResolveTimeout;
  final Duration targetResolvePollInterval;
  final Duration uiIdleQuietWindow;
  final Duration uiIdleTimeout;
  final Duration preActionVisualDelay;
  final Duration recordingPreActionVisualDelay;
  final Duration actionCommitTimeout;
  final Duration actionVisualDelay;
  final Duration routeTransitionVisualDelay;
  final Duration recordingActionVisualDelay;
  final bool waitForNetworkIdleDuringAcceptanceCapture;
  final CockpitHitTestMissPolicy hitTestMissPolicy;

  /// Returns a copy of this CockpitInteractionPolicy with supplied fields replaced.
  CockpitInteractionPolicy copyWith({
    Duration? targetResolveTimeout,
    Duration? targetResolvePollInterval,
    Duration? uiIdleQuietWindow,
    Duration? uiIdleTimeout,
    Duration? preActionVisualDelay,
    Duration? recordingPreActionVisualDelay,
    Duration? actionCommitTimeout,
    Duration? actionVisualDelay,
    Duration? routeTransitionVisualDelay,
    Duration? recordingActionVisualDelay,
    bool? waitForNetworkIdleDuringAcceptanceCapture,
    CockpitHitTestMissPolicy? hitTestMissPolicy,
  }) {
    return CockpitInteractionPolicy(
      targetResolveTimeout: targetResolveTimeout ?? this.targetResolveTimeout,
      targetResolvePollInterval:
          targetResolvePollInterval ?? this.targetResolvePollInterval,
      uiIdleQuietWindow: uiIdleQuietWindow ?? this.uiIdleQuietWindow,
      uiIdleTimeout: uiIdleTimeout ?? this.uiIdleTimeout,
      preActionVisualDelay: preActionVisualDelay ?? this.preActionVisualDelay,
      recordingPreActionVisualDelay:
          recordingPreActionVisualDelay ?? this.recordingPreActionVisualDelay,
      actionCommitTimeout: actionCommitTimeout ?? this.actionCommitTimeout,
      actionVisualDelay: actionVisualDelay ?? this.actionVisualDelay,
      routeTransitionVisualDelay:
          routeTransitionVisualDelay ?? this.routeTransitionVisualDelay,
      recordingActionVisualDelay:
          recordingActionVisualDelay ?? this.recordingActionVisualDelay,
      waitForNetworkIdleDuringAcceptanceCapture:
          waitForNetworkIdleDuringAcceptanceCapture ??
          this.waitForNetworkIdleDuringAcceptanceCapture,
      hitTestMissPolicy: hitTestMissPolicy ?? this.hitTestMissPolicy,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitInteractionPolicy &&
            other.targetResolveTimeout == targetResolveTimeout &&
            other.targetResolvePollInterval == targetResolvePollInterval &&
            other.uiIdleQuietWindow == uiIdleQuietWindow &&
            other.uiIdleTimeout == uiIdleTimeout &&
            other.preActionVisualDelay == preActionVisualDelay &&
            other.recordingPreActionVisualDelay ==
                recordingPreActionVisualDelay &&
            other.actionCommitTimeout == actionCommitTimeout &&
            other.actionVisualDelay == actionVisualDelay &&
            other.routeTransitionVisualDelay == routeTransitionVisualDelay &&
            other.recordingActionVisualDelay == recordingActionVisualDelay &&
            other.waitForNetworkIdleDuringAcceptanceCapture ==
                waitForNetworkIdleDuringAcceptanceCapture &&
            other.hitTestMissPolicy == hitTestMissPolicy;
  }

  @override
  int get hashCode => Object.hash(
    targetResolveTimeout,
    targetResolvePollInterval,
    uiIdleQuietWindow,
    uiIdleTimeout,
    preActionVisualDelay,
    recordingPreActionVisualDelay,
    actionCommitTimeout,
    actionVisualDelay,
    routeTransitionVisualDelay,
    recordingActionVisualDelay,
    waitForNetworkIdleDuringAcceptanceCapture,
    hitTestMissPolicy,
  );
}
