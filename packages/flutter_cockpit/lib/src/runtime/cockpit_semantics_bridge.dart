import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../control/cockpit_command_type.dart';

final class CockpitSemanticsTargetInfo {
  const CockpitSemanticsTargetInfo({
    required this.nodeId,
    required this.owner,
    required this.inheritedFromAncestor,
    required this.label,
    required this.value,
    required this.hint,
    required this.tooltip,
    required this.identifier,
    required this.supportedActions,
    required this.control,
  });

  final int nodeId;
  final SemanticsOwner owner;
  final bool inheritedFromAncestor;
  final String? label;
  final String? value;
  final String? hint;
  final String? tooltip;
  final String? identifier;
  final Set<SemanticsAction> supportedActions;
  final CockpitControlState? control;

  bool supports(SemanticsAction action) => supportedActions.contains(action);

  Set<CockpitCommandType> get supportedCommands => <CockpitCommandType>{
    if (supports(SemanticsAction.tap)) CockpitCommandType.tap,
    if (supports(SemanticsAction.longPress)) CockpitCommandType.longPress,
    if (supports(SemanticsAction.setText)) CockpitCommandType.enterText,
    if (supports(SemanticsAction.showOnScreen)) CockpitCommandType.showOnScreen,
    if (supports(SemanticsAction.increase)) CockpitCommandType.increase,
    if (supports(SemanticsAction.decrease)) CockpitCommandType.decrease,
    if (supports(SemanticsAction.dismiss)) CockpitCommandType.dismiss,
  };

  VoidCallback? actionHandler(SemanticsAction action) {
    if (!supports(action)) {
      return null;
    }
    return () => owner.performAction(nodeId, action);
  }

  void performAction(SemanticsAction action, [Object? args]) {
    if (!supports(action)) {
      throw StateError('Semantics node $nodeId does not support $action.');
    }
    owner.performAction(nodeId, action, args);
  }
}

CockpitSemanticsTargetInfo? cockpitResolveSemanticsTargetInfo(Element element) {
  final resolved = _resolveSemanticsNode(element);
  if (resolved == null) {
    return null;
  }
  return _targetInfoFromResolvedNode(resolved);
}

CockpitSemanticsTargetInfo? _targetInfoFromResolvedNode(
  ({SemanticsNode node, bool inheritedFromAncestor}) resolved,
) {
  final node = resolved.node;
  final owner = node.owner;
  if (owner == null) {
    return null;
  }
  final data = node.getSemanticsData();
  final supportedActions = _supportedActionsFrom(data);
  return CockpitSemanticsTargetInfo(
    nodeId: node.id,
    owner: owner,
    inheritedFromAncestor: resolved.inheritedFromAncestor,
    label: _normalizeSemanticsValue(data.label),
    value: _normalizeSemanticsValue(data.value),
    hint: _normalizeSemanticsValue(data.hint),
    tooltip: _normalizeSemanticsValue(data.tooltip),
    identifier: _normalizeSemanticsValue(data.identifier),
    supportedActions: supportedActions,
    control: _controlStateFrom(data, supportedActions),
  );
}

SemanticsAction? cockpitResolveSemanticScrollAction({
  required AxisDirection axisDirection,
  required bool forward,
}) {
  return switch ((axisDirection, forward)) {
    (AxisDirection.down, true) => SemanticsAction.scrollUp,
    (AxisDirection.down, false) => SemanticsAction.scrollDown,
    (AxisDirection.up, true) => SemanticsAction.scrollDown,
    (AxisDirection.up, false) => SemanticsAction.scrollUp,
    (AxisDirection.right, true) => SemanticsAction.scrollLeft,
    (AxisDirection.right, false) => SemanticsAction.scrollRight,
    (AxisDirection.left, true) => SemanticsAction.scrollRight,
    (AxisDirection.left, false) => SemanticsAction.scrollLeft,
  };
}

({SemanticsNode node, bool inheritedFromAncestor})? _resolveSemanticsNode(
  Element element,
) {
  RenderObject? renderObject = element.findRenderObject();
  SemanticsNode? result = renderObject?.debugSemantics;
  var inheritedFromAncestor = false;
  while (renderObject != null &&
      (result == null || result.isMergedIntoParent)) {
    inheritedFromAncestor = true;
    renderObject = renderObject.parent;
    result = renderObject?.debugSemantics;
  }
  if (result != null) {
    return (node: result, inheritedFromAncestor: inheritedFromAncestor);
  }
  if (!kReleaseMode) {
    return null;
  }
  // RenderObject.debugSemantics is assert-gated and always null in release
  // builds, so resolve through the live SemanticsOwner tree instead of
  // silently disabling the semantic plane.
  final ownerTreeResult = _resolveSemanticsNodeFromOwnerTree(element);
  if (ownerTreeResult == null) {
    return null;
  }
  return (
    node: ownerTreeResult.node,
    inheritedFromAncestor:
        ownerTreeResult.affinity < _minimumDirectSemanticsRectAffinity,
  );
}

@visibleForTesting
SemanticsNode? cockpitResolveSemanticsNodeFromOwnerTree(Element element) {
  return _resolveSemanticsNodeFromOwnerTree(element)?.node;
}

@visibleForTesting
CockpitSemanticsTargetInfo? cockpitResolveSemanticsTargetInfoFromOwnerTree(
  Element element,
) {
  final resolved = _resolveSemanticsNodeFromOwnerTree(element);
  if (resolved == null) {
    return null;
  }
  return _targetInfoFromResolvedNode((
    node: resolved.node,
    inheritedFromAncestor:
        resolved.affinity < _minimumDirectSemanticsRectAffinity,
  ));
}

({SemanticsNode node, double affinity})? _resolveSemanticsNodeFromOwnerTree(
  Element element,
) {
  final renderObject = element.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.attached ||
      !renderObject.hasSize) {
    return null;
  }
  final pipelineOwner = renderObject.owner;
  final rootNode = pipelineOwner?.semanticsOwner?.rootSemanticsNode;
  if (rootNode == null) {
    return null;
  }
  // The root semantics node lives in the view's physical coordinate space,
  // so the logical element center must be mapped through the view transform
  // before rect containment checks.
  final rootRenderObject = pipelineOwner!.rootNode;
  final viewTransform = rootRenderObject is RenderView
      ? rootRenderObject.configuration.toMatrix()
      : Matrix4.identity();
  final globalElementRect = MatrixUtils.transformRect(
    viewTransform.multiplied(renderObject.getTransformTo(null)),
    Offset.zero & renderObject.size,
  );
  final globalCenter = globalElementRect.center;

  // Containment alone would let a deeper overlay node (modal barrier,
  // snackbar) win over the element's own node, so require the candidate rect
  // to substantially coincide with the element bounds and prefer the best
  // geometric match.
  SemanticsNode? best;
  var bestScore = 0.0;
  var bestDepth = -1;
  void visit(SemanticsNode node, Matrix4 parentTransform, int depth) {
    final nodeTransform = node.transform;
    final globalTransform = nodeTransform == null
        ? parentTransform
        : parentTransform.multiplied(nodeTransform);
    if (!node.isMergedIntoParent && !node.rect.isEmpty) {
      final globalRect = MatrixUtils.transformRect(globalTransform, node.rect);
      if (globalRect.contains(globalCenter) &&
          !_semanticsDataIsHidden(node.getSemanticsData())) {
        final score = _semanticsRectAffinity(globalRect, globalElementRect);
        if (score >= _minimumSemanticsRectAffinity &&
            (score > bestScore || (score == bestScore && depth >= bestDepth))) {
          best = node;
          bestScore = score;
          bestDepth = depth;
        }
      }
    }
    node.visitChildren((child) {
      visit(child, globalTransform, depth + 1);
      return true;
    });
  }

  visit(rootNode, Matrix4.identity(), 0);
  return best == null ? null : (node: best!, affinity: bestScore);
}

bool _semanticsDataIsHidden(SemanticsData data) {
  // Flutter 3.32 is the supported SDK floor and does not expose
  // SemanticsData.flagsCollection yet.
  // ignore: deprecated_member_use
  return data.hasFlag(SemanticsFlag.isHidden);
}

const double _minimumSemanticsRectAffinity = 0.25;
const double _minimumDirectSemanticsRectAffinity = 0.8;

double _semanticsRectAffinity(Rect nodeRect, Rect elementRect) {
  final intersection = nodeRect.intersect(elementRect);
  if (intersection.width <= 0 || intersection.height <= 0) {
    return 0;
  }
  final intersectionArea = intersection.width * intersection.height;
  final largerArea = math.max(
    nodeRect.width * nodeRect.height,
    elementRect.width * elementRect.height,
  );
  if (largerArea <= 0) {
    return 0;
  }
  return intersectionArea / largerArea;
}

Set<SemanticsAction> _supportedActionsFrom(SemanticsData data) {
  return SemanticsAction.values.where(data.hasAction).toSet();
}

CockpitControlState? _controlStateFrom(
  SemanticsData data,
  Set<SemanticsAction> actions,
) {
  // Flutter 3.32 is the supported SDK floor and does not expose the typed
  // SemanticsFlagsCollection API used by newer SDKs.
  // ignore: deprecated_member_use
  final hasEnabled = data.hasFlag(SemanticsFlag.hasEnabledState);
  // ignore: deprecated_member_use
  final hasChecked = data.hasFlag(SemanticsFlag.hasCheckedState);
  // ignore: deprecated_member_use
  final hasSelected = data.hasFlag(SemanticsFlag.hasSelectedState);
  // ignore: deprecated_member_use
  final isTextField = data.hasFlag(SemanticsFlag.isTextField);
  // ignore: deprecated_member_use
  final enabled = !hasEnabled || data.hasFlag(SemanticsFlag.isEnabled);
  final identifiesControl =
      (hasEnabled && !enabled) ||
      hasChecked ||
      hasSelected ||
      isTextField ||
      actions.any(_isControlAction);
  if (!identifiesControl) {
    return null;
  }

  final checked = !hasChecked
      ? null
      // ignore: deprecated_member_use
      : data.hasFlag(SemanticsFlag.isCheckStateMixed)
      ? CockpitCheckState.mixed
      // ignore: deprecated_member_use
      : data.hasFlag(SemanticsFlag.isChecked)
      ? CockpitCheckState.on
      : CockpitCheckState.off;
  return CockpitControlState(
    enabled: enabled,
    selected: !hasSelected
        ? null
        // ignore: deprecated_member_use
        : data.hasFlag(SemanticsFlag.isSelected),
    checked: checked,
    // ignore: deprecated_member_use
    focused: data.hasFlag(SemanticsFlag.isFocused),
    // ignore: deprecated_member_use
    readOnly: data.hasFlag(SemanticsFlag.isReadOnly),
    // ignore: deprecated_member_use
    obscured: data.hasFlag(SemanticsFlag.isObscured),
    value: _normalizeSemanticsValue(data.value),
  );
}

bool _isControlAction(SemanticsAction action) => const <SemanticsAction>{
  SemanticsAction.tap,
  SemanticsAction.longPress,
  SemanticsAction.setText,
  SemanticsAction.increase,
  SemanticsAction.decrease,
  SemanticsAction.dismiss,
}.contains(action);

String? _normalizeSemanticsValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
