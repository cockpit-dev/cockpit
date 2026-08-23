// ignore_for_file: deprecated_member_use

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';

import 'cockpit_accessibility_summary.dart';
import 'cockpit_semantics_bridge.dart';
import 'cockpit_snapshot.dart';
import 'cockpit_snapshot_options.dart';
import 'cockpit_target.dart';

final class CockpitDiagnosticBuildResult {
  const CockpitDiagnosticBuildResult({
    required this.snapshot,
    required this.truncated,
  });

  final CockpitSnapshot snapshot;
  final bool truncated;
}

final class CockpitDiagnosticBuilder {
  const CockpitDiagnosticBuilder();

  CockpitDiagnosticBuildResult build({
    required String? routeName,
    required List<CockpitTarget> visibleTargets,
    required CockpitSnapshotOptions options,
  }) {
    var truncated = false;
    final query = options.query?.trim().toLowerCase();
    final hasQuery = query != null && query.isNotEmpty;
    final matchingTargets = !hasQuery
        ? visibleTargets
        : visibleTargets
              .where((target) => _matchesQuery(target, query))
              .toList(growable: false);
    final prioritizedTargets = _prioritizeTargets(
      matchingTargets,
    ).toList(growable: false);
    final summaryTargets = hasQuery ? prioritizedTargets : visibleTargets;
    final boundedTargets = prioritizedTargets
        .take(options.maxTargets)
        .toList(growable: false);
    if (prioritizedTargets.length > boundedTargets.length) {
      truncated = true;
    }

    final snapshotTargets = boundedTargets
        .map((target) {
          final result = _buildTarget(target, options);
          truncated = truncated || result.truncated;
          return result.target;
        })
        .toList(growable: false);
    final accessibility = options.includeAccessibilitySummary
        ? _buildAccessibilitySummary(
            boundedTargets,
            maxEntries: options.maxAccessibilityEntries,
            onTruncated: () => truncated = true,
          )
        : null;

    return CockpitDiagnosticBuildResult(
      truncated: truncated,
      snapshot: CockpitSnapshot(
        routeName: routeName,
        diagnosticLevel: options.profile,
        truncated: truncated,
        summary: CockpitSnapshotSummary(
          visibleTargetCount: summaryTargets.length,
          targetsWithCockpitIdCount: summaryTargets
              .where((target) => target.cockpitId != null)
              .length,
          targetsWithTextCount: summaryTargets
              .where((target) => target.text != null && target.text!.isNotEmpty)
              .length,
          styleDetailsIncluded: options.includeStyleDetails,
          diagnosticPropertiesIncluded: options.includeDiagnosticProperties,
          ancestorSummariesIncluded: options.maxAncestorsPerTarget > 0,
          rebuildSummaryIncluded: options.includeRebuildActivity,
          accessibilitySummaryIncluded: options.includeAccessibilitySummary,
        ),
        visibleTargets: snapshotTargets,
        accessibility: accessibility,
      ),
    );
  }

  bool _matchesQuery(CockpitTarget target, String query) => <String?>[
    target.cockpitId,
    target.semanticId,
    target.keyValue,
    target.text,
    ...target.textParts,
    target.tooltip,
    target.typeName,
    target.routeName,
    target.path,
  ].any((value) => value?.toLowerCase().contains(query) ?? false);

  Iterable<CockpitTarget> _prioritizeTargets(
    List<CockpitTarget> visibleTargets,
  ) {
    final indexedTargets = _deduplicateTargets(
      visibleTargets,
    ).indexed.toList(growable: false);
    indexedTargets.sort((left, right) {
      final salienceCompare = _salienceFor(
        right.$2,
      ).compareTo(_salienceFor(left.$2));
      if (salienceCompare != 0) {
        return salienceCompare;
      }
      return left.$1.compareTo(right.$1);
    });
    return indexedTargets.map((entry) => entry.$2);
  }

  List<CockpitTarget> _deduplicateTargets(List<CockpitTarget> visibleTargets) {
    final seenSignatures = <String>{};
    final deduplicated = <CockpitTarget>[];
    for (final target in visibleTargets) {
      final signature = _dedupSignatureFor(target);
      if (signature != null && !seenSignatures.add(signature)) {
        continue;
      }
      deduplicated.add(target);
    }
    return deduplicated;
  }

  String? _dedupSignatureFor(CockpitTarget target) {
    if (target.supportedCommands.isNotEmpty ||
        target.cockpitId != null ||
        target.semanticId != null ||
        target.keyValue != null ||
        target.tooltip != null) {
      return null;
    }
    final text = target.text;
    if (text == null || text.isEmpty) {
      return null;
    }
    return 'passive-text:$text';
  }

  int _salienceFor(CockpitTarget target) {
    var score = 0;
    if (target.control != null || target.supportedCommands.isNotEmpty) {
      score += 1000;
    }
    if (target.semanticId != null) {
      score += 350;
    }
    if (target.keyValue != null) {
      score += 250;
    }
    if (target.cockpitId != null) {
      score += 200;
    }
    if (target.text != null && target.text!.isNotEmpty) {
      score += 180;
      if (target.text!.length <= 40) {
        score += 30;
      }
      if (RegExp(r'^\d+$').hasMatch(target.text!)) {
        score -= 100;
      }
      if (RegExp(r'^[^A-Za-z0-9]+$').hasMatch(target.text!)) {
        score -= 220;
      }
      if (target.text!.contains(' ')) {
        score += 30;
      }
    }
    if (target.tooltip != null && target.tooltip!.isNotEmpty) {
      score += 90;
    }
    switch (target.typeName) {
      case 'EditableText':
      case 'TextField':
      case 'Checkbox':
      case 'CheckboxListTile':
      case 'Switch':
      case 'SwitchListTile':
      case 'FilledButton':
      case 'FilledButtonIcon':
      case 'OutlinedButton':
      case 'TextButton':
      case 'IconButton':
      case 'InkWell':
      case 'ListTile':
        score += 120;
      case 'Text':
      case 'RichText':
        score += 40;
      default:
        break;
    }
    return score;
  }

  _TargetBuildResult _buildTarget(
    CockpitTarget target,
    CockpitSnapshotOptions options,
  ) {
    if (options.profile == CockpitSnapshotProfile.live) {
      return _TargetBuildResult(
        target: CockpitSnapshotTarget(
          registrationId: target.registrationId,
          cockpitId: target.cockpitId,
          semanticId: target.semanticId,
          keyValue: target.keyValue,
          text: target.text,
          textParts: target.textParts.toList(growable: false),
          tooltip: target.tooltip,
          typeName: target.typeName,
          path: target.path,
          scrollablePath: target.scrollablePath,
          scrollableKeyValue: target.scrollableKeyValue,
          scrollableTypeName: target.scrollableTypeName,
          routeName: target.routeName,
          supportedCommands: target.supportedCommands.toList(growable: false),
          control: target.control,
        ),
      );
    }

    final runtimeNode = _resolveRuntimeNode(target);
    final layout = runtimeNode == null ? null : _extractLayout(runtimeNode);
    final content = CockpitSnapshotContent(
      displayLabel: target.displayLabel,
      textPreview: target.text,
    );

    var truncated = false;
    final ancestors = _resolvedAncestors(
      target,
      runtimeNode: runtimeNode,
      maxAncestors: options.maxAncestorsPerTarget,
      onTruncated: () => truncated = true,
    );
    final style = runtimeNode == null || !options.includeStyleDetails
        ? null
        : _extractStyle(runtimeNode.element);
    final diagnosticProperties =
        runtimeNode == null || !options.includeDiagnosticProperties
        ? const <CockpitDiagnosticProperty>[]
        : _extractDiagnosticProperties(
            runtimeNode,
            maxProperties: options.maxPropertiesPerTarget,
            onTruncated: () => truncated = true,
          );

    return _TargetBuildResult(
      truncated: truncated,
      target: CockpitSnapshotTarget(
        registrationId: target.registrationId,
        cockpitId: target.cockpitId,
        semanticId: target.semanticId,
        keyValue: target.keyValue,
        text: target.text,
        textParts: target.textParts.toList(growable: false),
        tooltip: target.tooltip,
        typeName: target.typeName,
        path: target.path,
        scrollablePath: target.scrollablePath,
        scrollableKeyValue: target.scrollableKeyValue,
        scrollableTypeName: target.scrollableTypeName,
        routeName: target.routeName,
        supportedCommands: target.supportedCommands.toList(growable: false),
        control: target.control,
        layout: layout,
        content: content,
        style: style,
        ancestors: ancestors,
        diagnosticProperties: diagnosticProperties,
      ),
    );
  }

  List<CockpitSnapshotAncestor> _resolvedAncestors(
    CockpitTarget target, {
    required _RuntimeNode? runtimeNode,
    required int maxAncestors,
    required VoidCallback onTruncated,
  }) {
    if (maxAncestors <= 0) {
      return const <CockpitSnapshotAncestor>[];
    }

    if (runtimeNode != null) {
      return _extractAncestors(
        runtimeNode.element,
        maxAncestors: maxAncestors,
        onTruncated: onTruncated,
      );
    }

    final locatorAncestors = target.locatorAncestors;
    if (locatorAncestors.length > maxAncestors) {
      onTruncated();
    }
    return locatorAncestors.take(maxAncestors).toList(growable: false);
  }

  _RuntimeNode? _resolveRuntimeNode(CockpitTarget target) {
    final candidate = target.diagnosticNodeProvider?.call();
    if (candidate is! BuildContext) {
      return null;
    }

    final renderObject = candidate.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }

    final creator = renderObject.debugCreator;
    if (creator is! DebugCreator) {
      return null;
    }

    return _RuntimeNode(element: creator.element, renderBox: renderObject);
  }

  CockpitSnapshotLayout? _extractLayout(_RuntimeNode runtimeNode) {
    final size = runtimeNode.renderBox.size;
    final position = runtimeNode.renderBox.localToGlobal(Offset.zero);
    final constraints = runtimeNode.renderBox.constraints;
    final width = _finiteDoubleOrNull(size.width);
    final height = _finiteDoubleOrNull(size.height);
    final dx = _finiteDoubleOrNull(position.dx);
    final dy = _finiteDoubleOrNull(position.dy);
    if (width == null || height == null || dx == null || dy == null) {
      return null;
    }

    return CockpitSnapshotLayout(
      width: width,
      height: height,
      dx: dx,
      dy: dy,
      constraintsSummary:
          'min:${constraints.minWidth.toStringAsFixed(1)}x${constraints.minHeight.toStringAsFixed(1)} '
          'max:${constraints.maxWidth.isFinite ? constraints.maxWidth.toStringAsFixed(1) : 'inf'}x'
          '${constraints.maxHeight.isFinite ? constraints.maxHeight.toStringAsFixed(1) : 'inf'}',
    );
  }

  List<CockpitSnapshotAncestor> _extractAncestors(
    Element element, {
    required int maxAncestors,
    required VoidCallback onTruncated,
  }) {
    final ancestors = <CockpitSnapshotAncestor>[];
    var seen = 0;

    element.visitAncestorElements((ancestor) {
      if (_shouldSkipAncestorElement(ancestor)) {
        return true;
      }
      if (seen >= maxAncestors) {
        onTruncated();
        return false;
      }
      ancestors.add(
        CockpitSnapshotAncestor(
          typeName: ancestor.widget.runtimeType.toString(),
          textPreview: _textPreviewForWidget(ancestor.widget),
        ),
      );
      seen += 1;
      return true;
    });

    return ancestors;
  }

  CockpitSnapshotStyle? _extractStyle(Element element) {
    final widget = element.widget;
    if (widget is Text) {
      final style = widget.style;
      return CockpitSnapshotStyle(
        textColor: style?.color == null ? null : _colorHex(style!.color!),
        fontSize: _finiteDoubleOrNull(style?.fontSize),
        fontWeight: style?.fontWeight?.toString().split('.').last,
      );
    }
    if (widget is Container && widget.decoration is BoxDecoration) {
      final decoration = widget.decoration! as BoxDecoration;
      return CockpitSnapshotStyle(
        backgroundColor: decoration.color == null
            ? null
            : _colorHex(decoration.color!),
        borderSummary: decoration.border?.toString(),
        shadowSummary:
            decoration.boxShadow == null || decoration.boxShadow!.isEmpty
            ? null
            : decoration.boxShadow!.first.toString(),
      );
    }
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      final decoration = widget.decoration as BoxDecoration;
      return CockpitSnapshotStyle(
        backgroundColor: decoration.color == null
            ? null
            : _colorHex(decoration.color!),
        borderSummary: decoration.border?.toString(),
        shadowSummary:
            decoration.boxShadow == null || decoration.boxShadow!.isEmpty
            ? null
            : decoration.boxShadow!.first.toString(),
      );
    }
    return null;
  }

  List<CockpitDiagnosticProperty> _extractDiagnosticProperties(
    _RuntimeNode runtimeNode, {
    required int maxProperties,
    required VoidCallback onTruncated,
  }) {
    final limit = maxProperties <= 0 ? 12 : maxProperties;
    final mergedProperties = <CockpitDiagnosticProperty>[];
    final seenNames = <String>{};

    void addProperty(CockpitDiagnosticProperty property) {
      if (seenNames.add(property.name)) {
        mergedProperties.add(property);
      }
    }

    for (final property in _extractNormalizedProperties(
      runtimeNode.element.widget,
      runtimeNode.renderBox,
    )) {
      addProperty(property);
    }

    for (final property in _extractSemanticsProperties(runtimeNode.element)) {
      addProperty(property);
    }

    final diagnostics = runtimeNode.element.toDiagnosticsNode().getProperties();
    for (final property in diagnostics) {
      final name = property.name;
      final description = property.toDescription();
      if (name == null || name.isEmpty || description.isEmpty) {
        continue;
      }
      addProperty(
        CockpitDiagnosticProperty(
          name: name,
          value: description,
          category: _categorizeProperty(name),
        ),
      );
    }

    if (mergedProperties.length > limit) {
      onTruncated();
    }

    return mergedProperties.take(limit).toList(growable: false);
  }

  List<CockpitDiagnosticProperty> _extractSemanticsProperties(Element element) {
    final semantics = cockpitResolveSemanticsTargetInfo(element);
    if (semantics == null) {
      return const <CockpitDiagnosticProperty>[];
    }

    final actions = <String>[
      if (semantics.supports(SemanticsAction.tap)) 'tap',
      if (semantics.supports(SemanticsAction.longPress)) 'longPress',
      if (semantics.supports(SemanticsAction.setText)) 'setText',
      if (semantics.supports(SemanticsAction.scrollUp)) 'scrollUp',
      if (semantics.supports(SemanticsAction.scrollDown)) 'scrollDown',
      if (semantics.supports(SemanticsAction.scrollLeft)) 'scrollLeft',
      if (semantics.supports(SemanticsAction.scrollRight)) 'scrollRight',
      if (semantics.supports(SemanticsAction.showOnScreen)) 'showOnScreen',
    ];

    return <CockpitDiagnosticProperty>[
      if (semantics.identifier != null)
        CockpitDiagnosticProperty(
          name: 'Semantics Identifier',
          value: semantics.identifier!,
          category: CockpitDiagnosticCategory.basic,
        ),
      if (semantics.label != null)
        CockpitDiagnosticProperty(
          name: 'Semantics Label',
          value: semantics.label!,
          category: CockpitDiagnosticCategory.basic,
        ),
      if (semantics.value != null)
        CockpitDiagnosticProperty(
          name: 'Semantics Value',
          value: semantics.value!,
          category: CockpitDiagnosticCategory.basic,
        ),
      if (semantics.hint != null)
        CockpitDiagnosticProperty(
          name: 'Semantics Hint',
          value: semantics.hint!,
          category: CockpitDiagnosticCategory.basic,
        ),
      if (semantics.tooltip != null)
        CockpitDiagnosticProperty(
          name: 'Semantics Tooltip',
          value: semantics.tooltip!,
          category: CockpitDiagnosticCategory.basic,
        ),
      if (actions.isNotEmpty)
        CockpitDiagnosticProperty(
          name: 'Semantics Actions',
          value: actions.join(', '),
          category: CockpitDiagnosticCategory.other,
        ),
    ];
  }

  CockpitAccessibilitySummary? _buildAccessibilitySummary(
    List<CockpitTarget> visibleTargets, {
    required int maxEntries,
    required VoidCallback onTruncated,
  }) {
    final semanticsTargets = visibleTargets
        .map(
          (target) => (target: target, semantics: _semanticsForTarget(target)),
        )
        .where((entry) => entry.semantics != null)
        .toList(growable: false);
    if (semanticsTargets.isEmpty) {
      return null;
    }

    final byOwner = groupBy(
      semanticsTargets,
      (entry) => entry.semantics!.owner,
    );
    final traversalEntries = <CockpitAccessibilityEntry>[];
    final seenNodeIds = <int>{};

    for (final ownerEntries in byOwner.values) {
      final root = ownerEntries.first.semantics!.owner.rootSemanticsNode;
      if (root == null) {
        traversalEntries.addAll(
          _fallbackAccessibilityEntries(ownerEntries, seenNodeIds: seenNodeIds),
        );
        continue;
      }
      final relevantEntriesByNodeId = {
        for (final entry in ownerEntries) entry.semantics!.nodeId: entry,
      };
      _visitSemanticsTraversal(root, (node) {
        final relevantEntry = relevantEntriesByNodeId[node.id];
        if (relevantEntry == null || !seenNodeIds.add(node.id)) {
          return true;
        }
        final entry = _accessibilityEntryFromSemantics(
          nodeId: node.id,
          semantics: relevantEntry.semantics!,
        );
        if (!entry.hasMeaningfulSignal) {
          return true;
        }
        traversalEntries.add(entry);
        return true;
      });
      traversalEntries.addAll(
        _fallbackAccessibilityEntries(ownerEntries, seenNodeIds: seenNodeIds),
      );
    }

    final total = traversalEntries.length;
    final boundedEntries = traversalEntries
        .take(maxEntries)
        .toList(growable: false);
    if (total > boundedEntries.length) {
      onTruncated();
    }
    return CockpitAccessibilitySummary(
      totalAccessibleTargetCount: total,
      traversalEntries: boundedEntries,
      truncated: total > boundedEntries.length,
    );
  }

  List<CockpitAccessibilityEntry> _fallbackAccessibilityEntries(
    List<({CockpitTarget target, CockpitSemanticsTargetInfo? semantics})>
    semanticsTargets, {
    required Set<int> seenNodeIds,
  }) {
    return semanticsTargets
        .where((entry) => seenNodeIds.add(entry.semantics!.nodeId))
        .map(
          (entry) => _accessibilityEntryFromSemantics(
            nodeId: entry.semantics!.nodeId,
            semantics: entry.semantics!,
          ),
        )
        .where((entry) => entry.hasMeaningfulSignal)
        .toList(growable: false);
  }

  CockpitAccessibilityEntry _accessibilityEntryFromSemantics({
    required int nodeId,
    required CockpitSemanticsTargetInfo semantics,
  }) {
    return CockpitAccessibilityEntry(
      nodeId: nodeId,
      label: _normalizeSemanticsValue(semantics.label),
      identifier: _normalizeSemanticsValue(semantics.identifier),
      value: _normalizeSemanticsValue(semantics.value),
      hint: _normalizeSemanticsValue(semantics.hint),
      tooltip: _normalizeSemanticsValue(semantics.tooltip),
    );
  }

  CockpitSemanticsTargetInfo? _semanticsForTarget(CockpitTarget target) {
    final runtimeNode = _resolveRuntimeNode(target);
    if (runtimeNode == null) {
      return null;
    }
    return cockpitResolveSemanticsTargetInfo(runtimeNode.element);
  }

  bool _visitSemanticsTraversal(
    SemanticsNode node,
    bool Function(SemanticsNode node) visitor,
  ) {
    if (!visitor(node)) {
      return false;
    }
    final children = node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    );
    for (final child in children) {
      if (!visitor(child) || !_visitSemanticsTraversal(child, visitor)) {
        return false;
      }
    }
    return true;
  }

  List<CockpitDiagnosticProperty> _extractNormalizedProperties(
    Widget widget,
    RenderBox renderBox,
  ) {
    final properties = <CockpitDiagnosticProperty>[
      ..._extractConstraintProperties(renderBox),
      ..._extractPaddingProperties(widget),
      ..._extractAlignmentProperties(widget),
      ..._extractTextStyleProperties(widget),
      ..._extractDecorationProperties(widget),
      ..._extractOpacityProperties(widget),
      ..._extractIconProperties(widget),
      ..._extractImageProperties(widget),
    ];

    final child = _childForWidget(widget);
    if (child != null) {
      properties.addAll(_extractNormalizedProperties(child, renderBox));
    }

    return properties;
  }

  List<CockpitDiagnosticProperty> _extractConstraintProperties(RenderBox box) {
    final constraints = box.constraints;
    return <CockpitDiagnosticProperty>[
      CockpitDiagnosticProperty(
        name: 'Min Width',
        value: '${constraints.minWidth.toStringAsFixed(1)}px',
        category: CockpitDiagnosticCategory.layout,
      ),
      CockpitDiagnosticProperty(
        name: 'Max Width',
        value: constraints.maxWidth.isFinite
            ? '${constraints.maxWidth.toStringAsFixed(1)}px'
            : 'Infinity',
        category: CockpitDiagnosticCategory.layout,
      ),
      CockpitDiagnosticProperty(
        name: 'Min Height',
        value: '${constraints.minHeight.toStringAsFixed(1)}px',
        category: CockpitDiagnosticCategory.layout,
      ),
      CockpitDiagnosticProperty(
        name: 'Max Height',
        value: constraints.maxHeight.isFinite
            ? '${constraints.maxHeight.toStringAsFixed(1)}px'
            : 'Infinity',
        category: CockpitDiagnosticCategory.layout,
      ),
      CockpitDiagnosticProperty(
        name: 'Is Tight',
        value: constraints.isTight ? 'Yes' : 'No',
        category: CockpitDiagnosticCategory.layout,
      ),
    ];
  }

  List<CockpitDiagnosticProperty> _extractPaddingProperties(Widget widget) {
    EdgeInsetsGeometry? padding;
    if (widget is Container && widget.padding != null) {
      padding = widget.padding;
    } else if (widget is Padding) {
      padding = widget.padding;
    }

    if (padding == null) {
      return const <CockpitDiagnosticProperty>[];
    }

    final resolved = padding.resolve(TextDirection.ltr);
    return <CockpitDiagnosticProperty>[
      CockpitDiagnosticProperty(
        name: 'Padding Top',
        value: '${resolved.top.toStringAsFixed(1)}px',
        category: CockpitDiagnosticCategory.spacing,
      ),
      CockpitDiagnosticProperty(
        name: 'Padding Right',
        value: '${resolved.right.toStringAsFixed(1)}px',
        category: CockpitDiagnosticCategory.spacing,
      ),
      CockpitDiagnosticProperty(
        name: 'Padding Bottom',
        value: '${resolved.bottom.toStringAsFixed(1)}px',
        category: CockpitDiagnosticCategory.spacing,
      ),
      CockpitDiagnosticProperty(
        name: 'Padding Left',
        value: '${resolved.left.toStringAsFixed(1)}px',
        category: CockpitDiagnosticCategory.spacing,
      ),
    ];
  }

  List<CockpitDiagnosticProperty> _extractAlignmentProperties(Widget widget) {
    Alignment? alignment;
    if (widget is Align && widget.alignment is Alignment) {
      alignment = widget.alignment as Alignment;
    } else if (widget is Container && widget.alignment is Alignment) {
      alignment = widget.alignment as Alignment;
    }

    if (alignment == null) {
      return const <CockpitDiagnosticProperty>[];
    }

    return <CockpitDiagnosticProperty>[
      CockpitDiagnosticProperty(
        name: 'Alignment',
        value:
            'x:${alignment.x.toStringAsFixed(2)}, y:${alignment.y.toStringAsFixed(2)}',
        category: CockpitDiagnosticCategory.layout,
      ),
    ];
  }

  List<CockpitDiagnosticProperty> _extractTextStyleProperties(Widget widget) {
    TextStyle? style;
    if (widget is Text && widget.style != null) {
      style = widget.style;
    } else if (widget is RichText && widget.text is TextSpan) {
      style = (widget.text as TextSpan).style;
    }

    if (style == null) {
      return const <CockpitDiagnosticProperty>[];
    }

    return <CockpitDiagnosticProperty>[
      if (style.fontFamily != null)
        CockpitDiagnosticProperty(
          name: 'Font Family',
          value: style.fontFamily!,
          category: CockpitDiagnosticCategory.typography,
        ),
      if (style.fontSize != null)
        CockpitDiagnosticProperty(
          name: 'Font Size',
          value: '${style.fontSize!.toStringAsFixed(1)}px',
          category: CockpitDiagnosticCategory.typography,
        ),
      if (style.fontWeight != null)
        CockpitDiagnosticProperty(
          name: 'Font Weight',
          value: style.fontWeight.toString().split('.').last,
          category: CockpitDiagnosticCategory.typography,
        ),
      if (style.letterSpacing != null)
        CockpitDiagnosticProperty(
          name: 'Letter Spacing',
          value: '${style.letterSpacing!.toStringAsFixed(1)}px',
          category: CockpitDiagnosticCategory.typography,
        ),
      if (style.height != null)
        CockpitDiagnosticProperty(
          name: 'Line Height',
          value: style.height!.toStringAsFixed(2),
          category: CockpitDiagnosticCategory.typography,
        ),
      if (style.color != null)
        CockpitDiagnosticProperty(
          name: 'Text Color',
          value: _colorHex(style.color!),
          category: CockpitDiagnosticCategory.appearance,
        ),
    ];
  }

  List<CockpitDiagnosticProperty> _extractDecorationProperties(Widget widget) {
    BoxDecoration? decoration;
    if (widget is Container && widget.decoration is BoxDecoration) {
      decoration = widget.decoration as BoxDecoration;
    } else if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      decoration = widget.decoration as BoxDecoration;
    }

    if (decoration == null) {
      return const <CockpitDiagnosticProperty>[];
    }

    final properties = <CockpitDiagnosticProperty>[
      if (decoration.color != null)
        CockpitDiagnosticProperty(
          name: 'Background Color',
          value: _colorHex(decoration.color!),
          category: CockpitDiagnosticCategory.appearance,
        ),
    ];

    final border = decoration.border;
    if (border is Border) {
      if (border.top.width > 0) {
        properties.add(
          CockpitDiagnosticProperty(
            name: 'Border Top',
            value:
                '${border.top.width.toStringAsFixed(1)}px ${_colorHex(border.top.color)}',
            category: CockpitDiagnosticCategory.appearance,
          ),
        );
      }
      if (border.right.width > 0) {
        properties.add(
          CockpitDiagnosticProperty(
            name: 'Border Right',
            value:
                '${border.right.width.toStringAsFixed(1)}px ${_colorHex(border.right.color)}',
            category: CockpitDiagnosticCategory.appearance,
          ),
        );
      }
      if (border.bottom.width > 0) {
        properties.add(
          CockpitDiagnosticProperty(
            name: 'Border Bottom',
            value:
                '${border.bottom.width.toStringAsFixed(1)}px ${_colorHex(border.bottom.color)}',
            category: CockpitDiagnosticCategory.appearance,
          ),
        );
      }
      if (border.left.width > 0) {
        properties.add(
          CockpitDiagnosticProperty(
            name: 'Border Left',
            value:
                '${border.left.width.toStringAsFixed(1)}px ${_colorHex(border.left.color)}',
            category: CockpitDiagnosticCategory.appearance,
          ),
        );
      }
    }

    final borderRadius = decoration.borderRadius;
    if (borderRadius is BorderRadius) {
      properties.add(
        CockpitDiagnosticProperty(
          name: 'Border Radius',
          value:
              'TL:${borderRadius.topLeft.x.toInt()} TR:${borderRadius.topRight.x.toInt()} BR:${borderRadius.bottomRight.x.toInt()} BL:${borderRadius.bottomLeft.x.toInt()}',
          category: CockpitDiagnosticCategory.appearance,
        ),
      );
    }

    final shadow = decoration.boxShadow?.firstOrNull;
    if (shadow != null) {
      properties.add(
        CockpitDiagnosticProperty(
          name: 'Shadow',
          value:
              'blur:${shadow.blurRadius.toInt()} offset:(${shadow.offset.dx.toInt()},${shadow.offset.dy.toInt()})',
          category: CockpitDiagnosticCategory.appearance,
        ),
      );
    }

    return properties;
  }

  List<CockpitDiagnosticProperty> _extractOpacityProperties(Widget widget) {
    if (widget is! Opacity) {
      return const <CockpitDiagnosticProperty>[];
    }
    return <CockpitDiagnosticProperty>[
      CockpitDiagnosticProperty(
        name: 'Opacity',
        value: widget.opacity.toStringAsFixed(2),
        category: CockpitDiagnosticCategory.appearance,
      ),
    ];
  }

  List<CockpitDiagnosticProperty> _extractIconProperties(Widget widget) {
    if (widget is! Icon) {
      return const <CockpitDiagnosticProperty>[];
    }
    return <CockpitDiagnosticProperty>[
      if (widget.size != null)
        CockpitDiagnosticProperty(
          name: 'Icon Size',
          value: '${widget.size!.toInt()}px',
          category: CockpitDiagnosticCategory.layout,
        ),
      if (widget.color != null)
        CockpitDiagnosticProperty(
          name: 'Icon Color',
          value: _colorHex(widget.color!),
          category: CockpitDiagnosticCategory.appearance,
        ),
    ];
  }

  List<CockpitDiagnosticProperty> _extractImageProperties(Widget widget) {
    if (widget is! Image) {
      return const <CockpitDiagnosticProperty>[];
    }
    return <CockpitDiagnosticProperty>[
      if (widget.width != null)
        CockpitDiagnosticProperty(
          name: 'Image Width',
          value: '${widget.width!.toInt()}px',
          category: CockpitDiagnosticCategory.layout,
        ),
      if (widget.height != null)
        CockpitDiagnosticProperty(
          name: 'Image Height',
          value: '${widget.height!.toInt()}px',
          category: CockpitDiagnosticCategory.layout,
        ),
      CockpitDiagnosticProperty(
        name: 'Image Fit',
        value: widget.fit?.toString().split('.').last ?? 'none',
        category: CockpitDiagnosticCategory.appearance,
      ),
      CockpitDiagnosticProperty(
        name: 'Image Repeat',
        value: widget.repeat.toString().split('.').last,
        category: CockpitDiagnosticCategory.appearance,
      ),
    ];
  }

  Widget? _childForWidget(Widget widget) {
    return switch (widget) {
      Container(:final child) => child,
      Padding(:final child) => child,
      Align(:final child) => child,
      Opacity(:final child) => child,
      DecoratedBox(:final child) => child,
      _ => null,
    };
  }

  CockpitDiagnosticCategory _categorizeProperty(String key) {
    final lowerKey = key.toLowerCase();
    if (lowerKey.contains('widget') || lowerKey.contains('depth')) {
      return CockpitDiagnosticCategory.basic;
    }
    if (lowerKey.contains('size') ||
        lowerKey.contains('position') ||
        lowerKey.contains('constraint') ||
        lowerKey.contains('width') ||
        lowerKey.contains('height')) {
      return CockpitDiagnosticCategory.layout;
    }
    if (lowerKey.contains('padding') ||
        lowerKey.contains('margin') ||
        lowerKey.contains('inset')) {
      return CockpitDiagnosticCategory.spacing;
    }
    if (lowerKey.contains('color') ||
        lowerKey.contains('decoration') ||
        lowerKey.contains('border') ||
        lowerKey.contains('shadow') ||
        lowerKey.contains('background')) {
      return CockpitDiagnosticCategory.appearance;
    }
    if (lowerKey.contains('font') ||
        lowerKey.contains('text') ||
        lowerKey.contains('style') ||
        lowerKey.contains('letter') ||
        lowerKey.contains('line')) {
      return CockpitDiagnosticCategory.typography;
    }
    return CockpitDiagnosticCategory.other;
  }

  String? _textPreviewForWidget(Widget widget) {
    if (widget is Text) {
      return widget.data;
    }
    if (widget is RichText && widget.text is TextSpan) {
      return (widget.text as TextSpan).toPlainText();
    }
    return null;
  }

  String _colorHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  double? _finiteDoubleOrNull(double? value) {
    if (value == null || !value.isFinite) {
      return null;
    }
    return value;
  }

  String? _normalizeSemanticsValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final normalizedLines = trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .fold<List<String>>(<String>[], (lines, line) {
          if (!lines.contains(line)) {
            lines.add(line);
          }
          return lines;
        });
    if (normalizedLines.isEmpty) {
      return null;
    }
    return normalizedLines.join('\n');
  }

  bool _shouldSkipAncestorElement(Element element) {
    final typeName = element.widget.runtimeType.toString();
    return typeName.startsWith('_') ||
        typeName == 'KeyedSubtree' ||
        typeName.contains('Semantics') ||
        typeName.contains('Listener') ||
        typeName.contains('GestureDetector') ||
        typeName.contains('IgnorePointer') ||
        typeName.contains('MouseRegion');
  }
}

final class _RuntimeNode {
  const _RuntimeNode({required this.element, required this.renderBox});

  final Element element;
  final RenderBox renderBox;
}

final class _TargetBuildResult {
  const _TargetBuildResult({required this.target, this.truncated = false});

  final CockpitSnapshotTarget target;
  final bool truncated;
}
