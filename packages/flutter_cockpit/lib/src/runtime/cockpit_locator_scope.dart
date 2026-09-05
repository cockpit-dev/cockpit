import 'package:flutter/widgets.dart';

/// Returns whether [widget] is a public branching layout boundary worth
/// retaining in a compact Cockpit locator path.
///
/// Ordinary visual wrappers are intentionally omitted from paths. These
/// widgets, however, change paint order, branch ownership, or overlay
/// placement, so keeping them lets key-free selectors describe complex UIs.
bool cockpitIsLocatorScopeWidget(Widget widget) {
  return widget is Stack ||
      widget is IndexedStack ||
      widget is Positioned ||
      widget is PositionedDirectional ||
      widget is Overlay ||
      widget is OverlayPortal ||
      widget is CompositedTransformTarget ||
      widget is CompositedTransformFollower ||
      widget is Flow ||
      widget is CustomMultiChildLayout;
}
