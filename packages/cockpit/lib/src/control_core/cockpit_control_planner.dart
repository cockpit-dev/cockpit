import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_execution_plan.dart';
import 'cockpit_intent.dart';
import 'cockpit_intent_action.dart';
import 'cockpit_intent_subject.dart';

final class CockpitControlPlanner {
  CockpitExecutionPlan plan({
    required CockpitIntent intent,
    required CockpitCapabilityProfile capabilityProfile,
  }) {
    if (intent.subject == CockpitIntentSubject.host &&
        intent.action == CockpitIntentAction.runShell) {
      return CockpitExecutionPlan(
        intent: intent,
        selectedPlane: CockpitPlaneKind.hostPlane,
        candidatePlanes: const <CockpitPlaneKind>[CockpitPlaneKind.hostPlane],
        fallbackChain: const <CockpitPlaneKind>[],
      );
    }

    final candidatePlanes = <CockpitPlaneKind>[];
    if (_supportsFlutterSemantic(intent, capabilityProfile)) {
      candidatePlanes.add(CockpitPlaneKind.flutterSemanticPlane);
    }
    if (_supportsNativeUi(intent, capabilityProfile)) {
      candidatePlanes.add(CockpitPlaneKind.nativeUiPlane);
    }
    if (_supportsDeviceSystem(intent, capabilityProfile)) {
      candidatePlanes.add(CockpitPlaneKind.deviceSystemPlane);
    }

    if (candidatePlanes.isEmpty) {
      throw StateError(
        'No execution planes are available for ${intent.action.name}.',
      );
    }

    final orderedPlanes = _applyExecutionPolicy(
      intent.executionPolicy,
      candidatePlanes,
    );
    return CockpitExecutionPlan(
      intent: intent,
      selectedPlane: orderedPlanes.first,
      candidatePlanes: orderedPlanes,
      fallbackChain: orderedPlanes.skip(1).toList(growable: false),
      requiresEvidence: intent.action == CockpitIntentAction.captureScreenshot,
      requiresObservation: _requiresObservation(intent.action),
    );
  }

  bool _supportsFlutterSemantic(
    CockpitIntent intent,
    CockpitCapabilityProfile capabilityProfile,
  ) {
    return capabilityProfile.targetKind == CockpitTargetKind.flutterApp &&
        capabilityProfile.supportsSurface(CockpitSurfaceKind.flutterSemantic) &&
        capabilityProfile.supportsAction(_actionCapabilityFor(intent.action));
  }

  bool _supportsNativeUi(
    CockpitIntent intent,
    CockpitCapabilityProfile capabilityProfile,
  ) {
    if (!capabilityProfile.supportsAction(
      _actionCapabilityFor(intent.action),
    )) {
      return false;
    }
    return capabilityProfile.supportsSurface(CockpitSurfaceKind.nativeUi) ||
        capabilityProfile.supportsSurface(CockpitSurfaceKind.systemUi) ||
        capabilityProfile.supportsSurface(CockpitSurfaceKind.desktopWindow) ||
        capabilityProfile.supportsSurface(CockpitSurfaceKind.browserDom);
  }

  bool _supportsDeviceSystem(
    CockpitIntent intent,
    CockpitCapabilityProfile capabilityProfile,
  ) {
    if (intent.subject == CockpitIntentSubject.host) {
      return false;
    }
    return capabilityProfile.targetKind != CockpitTargetKind.hostWorkspace;
  }

  List<CockpitPlaneKind> _applyExecutionPolicy(
    CockpitExecutionPolicy executionPolicy,
    List<CockpitPlaneKind> candidatePlanes,
  ) {
    final ordered = List<CockpitPlaneKind>.from(candidatePlanes);
    void prefer(CockpitPlaneKind planeKind) {
      final index = ordered.indexOf(planeKind);
      if (index > 0) {
        ordered
          ..removeAt(index)
          ..insert(0, planeKind);
      }
    }

    switch (executionPolicy) {
      case CockpitExecutionPolicy.preferFlutter:
        prefer(CockpitPlaneKind.flutterSemanticPlane);
      case CockpitExecutionPolicy.preferNative:
        prefer(CockpitPlaneKind.nativeUiPlane);
      case CockpitExecutionPolicy.preferSystem:
        prefer(CockpitPlaneKind.deviceSystemPlane);
      case CockpitExecutionPolicy.forcePlane:
      case CockpitExecutionPolicy.noFallback:
      case CockpitExecutionPolicy.auto:
        break;
    }
    return ordered;
  }

  bool _requiresObservation(CockpitIntentAction action) {
    return switch (action) {
      CockpitIntentAction.tap ||
      CockpitIntentAction.hover ||
      CockpitIntentAction.wheel ||
      CockpitIntentAction.enterText ||
      CockpitIntentAction.eraseText ||
      CockpitIntentAction.pasteText ||
      CockpitIntentAction.focusTextInput ||
      CockpitIntentAction.setTextEditingValue ||
      CockpitIntentAction.sendTextInputAction ||
      CockpitIntentAction.sendKeyEvent ||
      CockpitIntentAction.sendKeyDownEvent ||
      CockpitIntentAction.sendKeyUpEvent ||
      CockpitIntentAction.longPress ||
      CockpitIntentAction.doubleTap ||
      CockpitIntentAction.drag ||
      CockpitIntentAction.fling ||
      CockpitIntentAction.swipe ||
      CockpitIntentAction.pinchZoom ||
      CockpitIntentAction.rotate ||
      CockpitIntentAction.panZoom ||
      CockpitIntentAction.multiTouch ||
      CockpitIntentAction.scrollUntilVisible ||
      CockpitIntentAction.clearNetworkActivity ||
      CockpitIntentAction.waitForNetworkIdle ||
      CockpitIntentAction.waitForUiIdle ||
      CockpitIntentAction.back ||
      CockpitIntentAction.showOnScreen ||
      CockpitIntentAction.increase ||
      CockpitIntentAction.decrease ||
      CockpitIntentAction.dismiss ||
      CockpitIntentAction.dismissKeyboard ||
      CockpitIntentAction.waitFor ||
      CockpitIntentAction.assertVisible ||
      CockpitIntentAction.assertText => true,
      CockpitIntentAction.copyText ||
      CockpitIntentAction.captureScreenshot ||
      CockpitIntentAction.collectSnapshot ||
      CockpitIntentAction.runShell => false,
    };
  }

  CockpitActionCapability _actionCapabilityFor(CockpitIntentAction action) {
    return switch (action) {
      CockpitIntentAction.tap => CockpitActionCapability.tap,
      CockpitIntentAction.hover => CockpitActionCapability.hover,
      CockpitIntentAction.wheel => CockpitActionCapability.scroll,
      CockpitIntentAction.longPress ||
      CockpitIntentAction.doubleTap ||
      CockpitIntentAction.drag ||
      CockpitIntentAction.fling ||
      CockpitIntentAction.swipe ||
      CockpitIntentAction.pinchZoom ||
      CockpitIntentAction.rotate ||
      CockpitIntentAction.panZoom ||
      CockpitIntentAction.multiTouch ||
      CockpitIntentAction.scrollUntilVisible ||
      CockpitIntentAction.back ||
      CockpitIntentAction.showOnScreen ||
      CockpitIntentAction.increase ||
      CockpitIntentAction.decrease ||
      CockpitIntentAction.dismiss ||
      CockpitIntentAction.waitFor ||
      CockpitIntentAction.assertVisible ||
      CockpitIntentAction.assertText => CockpitActionCapability.tap,
      CockpitIntentAction.enterText ||
      CockpitIntentAction.eraseText ||
      CockpitIntentAction.copyText ||
      CockpitIntentAction.pasteText ||
      CockpitIntentAction.focusTextInput ||
      CockpitIntentAction.setTextEditingValue ||
      CockpitIntentAction.sendTextInputAction ||
      CockpitIntentAction.dismissKeyboard ||
      CockpitIntentAction.sendKeyEvent ||
      CockpitIntentAction.sendKeyDownEvent ||
      CockpitIntentAction.sendKeyUpEvent => CockpitActionCapability.typeText,
      CockpitIntentAction.captureScreenshot =>
        CockpitActionCapability.captureScreenshot,
      CockpitIntentAction.collectSnapshot ||
      CockpitIntentAction.clearNetworkActivity ||
      CockpitIntentAction.waitForNetworkIdle ||
      CockpitIntentAction.waitForUiIdle => CockpitActionCapability.readLogs,
      CockpitIntentAction.runShell => CockpitActionCapability.runShell,
    };
  }
}
