import 'package:flutter/widgets.dart';

import '../control/cockpit_command_type.dart';
import 'cockpit_discovery_policy.dart';
import 'cockpit_native_target_discovery.dart';
import 'cockpit_target.dart';

final class CockpitDiscoveryEngine {
  const CockpitDiscoveryEngine({this.policy = const CockpitDiscoveryPolicy()});

  final CockpitDiscoveryPolicy policy;

  List<CockpitTarget> discover({
    required BuildContext rootContext,
    required String? routeName,
    List<CockpitTarget> explicitTargets = const <CockpitTarget>[],
    bool allowInactiveRouteFallback = false,
  }) {
    return CockpitNativeTargetDiscovery(policy: policy).discover(
      rootContext: rootContext,
      routeName: routeName,
      explicitTargets: explicitTargets,
      allowInactiveRouteFallback: allowInactiveRouteFallback,
    );
  }

  bool hasDiscoverableTarget({
    required BuildContext rootContext,
    required String? routeName,
    List<CockpitTarget> explicitTargets = const <CockpitTarget>[],
    bool allowInactiveRouteFallback = false,
  }) {
    return CockpitNativeTargetDiscovery(policy: policy).hasTarget(
      rootContext: rootContext,
      routeName: routeName,
      explicitTargets: explicitTargets,
      allowInactiveRouteFallback: allowInactiveRouteFallback,
    );
  }

  /// Discovers actionable targets related to one matched Flutter element.
  List<CockpitTarget> discoverRelatedActionTargets({
    required BuildContext rootContext,
    required Element element,
    required String? routeName,
    required CockpitCommandType requiredCommand,
    List<CockpitTarget> explicitTargets = const <CockpitTarget>[],
  }) {
    return CockpitNativeTargetDiscovery(
      policy: policy,
    ).discoverRelatedActionTargets(
      rootContext: rootContext,
      element: element,
      routeName: routeName,
      requiredCommand: requiredCommand,
      explicitTargets: explicitTargets,
    );
  }
}
