import 'package:flutter/material.dart';

import 'cockpit_runtime_tree_visibility.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_target.dart';

final class CockpitWidgetTreeBuilder {
  const CockpitWidgetTreeBuilder();

  CockpitWidgetTree build({
    required Element root,
    required String? route,
    required List<CockpitTarget> targets,
    required CockpitWidgetTreeOptions options,
  }) {
    final targetsByElement = _targetsByElement(targets);
    final rawNodes = <_RawWidgetNode>[];
    final viewport = _boundsFor(root)?.rect;
    var nextNode = 0;

    void visit(
      Element element, {
      required _RawWidgetNode? parent,
      required int depth,
      required int? scroll,
    }) {
      if (!element.mounted) return;
      final nodeId = nextNode++;
      final isScrollable =
          element is StatefulElement && element.state is ScrollableState;
      final node = _RawWidgetNode(
        node: nodeId,
        element: element,
        parent: parent,
        depth: depth,
        target: targetsByElement[element],
        scroll: isScrollable ? nodeId : scroll,
        route: route,
        viewport: viewport,
      );
      rawNodes.add(node);
      element.visitChildElements((child) {
        visit(child, parent: node, depth: depth + 1, scroll: node.scroll);
      });
    }

    visit(root, parent: null, depth: 0, scroll: null);

    final included = _includedNodes(rawNodes, options.profile);
    final emitted = <CockpitWidgetNode>[];
    for (final raw in rawNodes) {
      if (!included.contains(raw) || emitted.length >= options.maxNodes) {
        continue;
      }
      emitted.add(
        raw.toNode(
          profile: options.profile,
          maxProps: options.maxProps,
          included: included,
        ),
      );
    }

    return CockpitWidgetTree(
      profile: options.profile,
      total: rawNodes.length,
      visible: rawNodes.where((node) => node.visible).length,
      truncated: included.length > emitted.length,
      nodes: emitted,
    );
  }

  Map<Element, CockpitTarget> _targetsByElement(List<CockpitTarget> targets) {
    final result = Map<Element, CockpitTarget>.identity();
    for (final target in targets) {
      final node = target.diagnosticNodeProvider?.call();
      if (node is! Element) continue;
      final current = result[node];
      if (current == null ||
          target.supportedCommands.length > current.supportedCommands.length) {
        result[node] = target;
      }
    }
    return result;
  }

  Set<_RawWidgetNode> _includedNodes(
    List<_RawWidgetNode> nodes,
    CockpitWidgetTreeProfile profile,
  ) {
    if (profile == CockpitWidgetTreeProfile.full) {
      return Set<_RawWidgetNode>.identity()..addAll(nodes);
    }
    if (profile == CockpitWidgetTreeProfile.standard) {
      return Set<_RawWidgetNode>.identity()
        ..addAll(nodes.where((node) => node.isPublicStructure));
    }

    final included = Set<_RawWidgetNode>.identity();
    for (final node in nodes.where((candidate) => candidate.isMeaningful)) {
      _includePublicChain(node, included);
    }
    if (nodes.isNotEmpty && included.isEmpty) {
      _includePublicChain(nodes.first, included);
    }
    return included;
  }

  void _includePublicChain(_RawWidgetNode node, Set<_RawWidgetNode> included) {
    _RawWidgetNode? current = node;
    while (current != null) {
      if (current.isPublicStructure || identical(current, node)) {
        included.add(current);
      }
      current = current.parent;
    }
  }
}

final class _RawWidgetNode {
  _RawWidgetNode({
    required this.node,
    required this.element,
    required this.parent,
    required this.depth,
    required this.target,
    required this.scroll,
    required this.route,
    required Rect? viewport,
  }) : type = element.widget.runtimeType.toString(),
       key = _stableKeyValue(element.widget.key),
       directText = _directText(element.widget),
       directTip = _directTip(element.widget),
       offstage = _isOffstage(element),
       bounds = _boundsFor(element),
       visible = _isVisible(element, viewport);

  final int node;
  final Element element;
  final _RawWidgetNode? parent;
  final int depth;
  final CockpitTarget? target;
  final int? scroll;
  final String? route;
  final String type;
  final String? key;
  final String? directText;
  final String? directTip;
  final bool offstage;
  final _NodeBounds? bounds;
  final bool visible;

  bool get isPublicStructure {
    if (type.startsWith('_')) return false;
    final widget = element.widget;
    return widget is! InheritedWidget && widget is! ParentDataWidget;
  }

  bool get isMeaningful {
    return target?.supportedCommands.isNotEmpty == true ||
        target?.cockpitId != null ||
        target?.semanticId != null ||
        key != null ||
        directText != null ||
        directTip != null ||
        element is StatefulElement &&
            (element as StatefulElement).state is ScrollableState;
  }

  CockpitWidgetNode toNode({
    required CockpitWidgetTreeProfile profile,
    required int maxProps,
    required Set<_RawWidgetNode> included,
  }) {
    _RawWidgetNode? emittedParent = parent;
    while (emittedParent != null && !included.contains(emittedParent)) {
      emittedParent = emittedParent.parent;
    }
    final renderObject = element.findRenderObject();
    final full = profile == CockpitWidgetTreeProfile.full;
    final standard = profile != CockpitWidgetTreeProfile.minimal;
    return CockpitWidgetNode(
      node: node,
      loc: target?.path,
      parent: emittedParent?.node,
      depth: depth,
      type: type,
      element: full ? element.runtimeType.toString() : null,
      state: full && element is StatefulElement
          ? (element as StatefulElement).state.runtimeType.toString()
          : null,
      render: standard ? renderObject?.runtimeType.toString() : null,
      cockpitId: target?.cockpitId,
      semanticId: target?.semanticId,
      key: target?.keyValue ?? key,
      text: directText ?? target?.text,
      tip: directTip ?? target?.tooltip,
      route: route,
      visible: visible,
      offstage: offstage,
      bounds: bounds?.toProtocol(includeConstraints: full),
      scroll: scroll,
      actions:
          target?.supportedCommands.toList(growable: false) ??
          const <CockpitCommandType>[],
      props: full ? _propertiesFor(element, maxProps: maxProps) : const [],
    );
  }
}

final class _NodeBounds {
  const _NodeBounds({required this.rect, required this.constraints});

  final Rect rect;
  final String? constraints;

  CockpitWidgetBounds toProtocol({required bool includeConstraints}) {
    return CockpitWidgetBounds(
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      constraints: includeConstraints ? constraints : null,
    );
  }
}

_NodeBounds? _boundsFor(Element element) {
  final renderObject = element.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return null;
  try {
    if (!renderObject.hasSize) return null;
    final size = renderObject.size;
    final offset = renderObject.localToGlobal(Offset.zero);
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        !offset.dx.isFinite ||
        !offset.dy.isFinite) {
      return null;
    }
    final constraints = renderObject.constraints;
    return _NodeBounds(
      rect: offset & size,
      constraints:
          'min:${constraints.minWidth.toStringAsFixed(1)}x${constraints.minHeight.toStringAsFixed(1)} '
          'max:${constraints.maxWidth.isFinite ? constraints.maxWidth.toStringAsFixed(1) : 'inf'}x'
          '${constraints.maxHeight.isFinite ? constraints.maxHeight.toStringAsFixed(1) : 'inf'}',
    );
  } on Object {
    return null;
  }
}

bool _isVisible(Element element, Rect? viewport) {
  if (!cockpitIsVisibleInRuntimeTree(element)) return false;
  final bounds = _boundsFor(element)?.rect;
  if (bounds == null || bounds.isEmpty) return false;
  return viewport == null || bounds.overlaps(viewport);
}

bool _isOffstage(Element element) {
  var offstage =
      element.widget is Offstage && (element.widget as Offstage).offstage;
  if (offstage) return true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Offstage && widget.offstage) {
      offstage = true;
      return false;
    }
    return true;
  });
  return offstage;
}

String? _stableKeyValue(Key? key) {
  final value = switch (key) {
    ValueKey<Object?>(value: final value) => value,
    ObjectKey(value: final value) => value,
    _ => null,
  };
  if (value == null || value.runtimeType.toString().startsWith('_')) {
    return null;
  }
  return _normalize(value.toString());
}

String? _directText(Widget widget) {
  return switch (widget) {
    Text(data: final data, textSpan: final span) => _normalize(
      data ?? span?.toPlainText(),
    ),
    RichText(text: final span) => _normalize(span.toPlainText()),
    SelectableText(data: final data, textSpan: final span) => _normalize(
      data ?? span?.toPlainText(),
    ),
    _ => null,
  };
}

String? _directTip(Widget widget) {
  if (widget is! Tooltip) return null;
  return _normalize(widget.message ?? widget.richMessage?.toPlainText());
}

List<CockpitWidgetProperty> _propertiesFor(
  Element element, {
  required int maxProps,
}) {
  if (maxProps <= 0) return const <CockpitWidgetProperty>[];
  final result = <CockpitWidgetProperty>[];
  final seen = <String>{};
  try {
    for (final property in element.toDiagnosticsNode().getProperties()) {
      final name = _normalize(property.name);
      final value = _normalize(property.toDescription(), maxLength: 240);
      if (name == null || value == null || !seen.add(name)) continue;
      result.add(CockpitWidgetProperty(name: name, value: value));
      if (result.length >= maxProps) break;
    }
  } on Object {
    return List<CockpitWidgetProperty>.unmodifiable(result);
  }
  return List<CockpitWidgetProperty>.unmodifiable(result);
}

String? _normalize(String? value, {int maxLength = 512}) {
  final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength - 1)}…';
}
