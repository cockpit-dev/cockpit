import 'package:flutter/widgets.dart';

/// Returns public Router providers in tree order, with nested routers last.
///
/// The scan is intentionally explicit and one-shot. Route changes are then
/// delivered by each provider's public listenable contract.
Iterable<RouteInformationProvider>
cockpitRouteInformationProvidersInRuntimeTree(Element rootElement) {
  final candidates = <({RouteInformationProvider provider, int depth})>[];

  void visit(Element element, int depth) {
    if (!element.mounted) {
      return;
    }
    final widget = element.widget;
    if (widget is Router<dynamic>) {
      final provider = widget.routeInformationProvider;
      if (provider != null) {
        candidates.add((provider: provider, depth: depth));
      }
    }
    element.visitChildElements((child) => visit(child, depth + 1));
  }

  visit(rootElement, 0);
  candidates.sort((left, right) => left.depth.compareTo(right.depth));
  return candidates.map((candidate) => candidate.provider);
}

Future<bool> cockpitMaybePopCurrentNavigator(Element rootElement) async {
  final candidates = <({NavigatorState state, int depth})>[];

  void visit(Element element, int depth) {
    if (!element.mounted) {
      return;
    }
    if (element is StatefulElement &&
        element.widget is Navigator &&
        element.state is NavigatorState &&
        cockpitIsVisibleInRuntimeTree(element)) {
      candidates.add((state: element.state as NavigatorState, depth: depth));
    }
    element.visitChildElements((child) => visit(child, depth + 1));
  }

  visit(rootElement, 0);
  candidates.sort((left, right) => right.depth.compareTo(left.depth));
  for (final candidate in candidates) {
    final navigator = candidate.state;
    if (navigator.mounted && navigator.canPop()) {
      return navigator.maybePop();
    }
  }
  return false;
}

bool cockpitIsVisibleInRuntimeTree(Element element) {
  if (!element.mounted) {
    return false;
  }

  if (!_isVisibleInAncestorTree(element)) {
    return false;
  }

  return true;
}

bool _isVisibleInAncestorTree(Element element) {
  var isVisible = true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if ((widget is Offstage && widget.offstage) ||
        _belongsToInactiveModalRoute(widget)) {
      isVisible = false;
      return false;
    }
    return true;
  });
  return isVisible;
}

bool _belongsToInactiveModalRoute(Widget widget) {
  if (widget is! InheritedModel<dynamic>) {
    return false;
  }
  try {
    final dynamic modalScopeStatus = widget;
    final dynamic route = modalScopeStatus.route;
    final dynamic isCurrent = modalScopeStatus.isCurrent;
    return route is ModalRoute<dynamic> && isCurrent is bool && !isCurrent;
  } on Object {
    return false;
  }
}
