import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:xml/xml.dart';

final class CockpitNativeUiSnapshot {
  CockpitNativeUiSnapshot._({
    required this.raw,
    required this.nodes,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final String raw;
  final List<CockpitNativeUiNode> nodes;
  final int viewportWidth;
  final int viewportHeight;

  factory CockpitNativeUiSnapshot.parse(String raw) {
    if (raw.trimLeft().startsWith('{')) {
      return _parseJson(raw);
    }
    final document = XmlDocument.parse(raw);
    final nodes = <CockpitNativeUiNode>[];

    void visit(XmlElement element, List<String> ancestorPaths) {
      var elementIndex = 0;
      final parent = element.parentElement;
      if (parent != null) {
        for (final sibling in parent.childElements) {
          if (identical(sibling, element)) break;
          if (sibling.name.local == element.name.local) elementIndex += 1;
        }
      }
      final path = <String>[
        ...ancestorPaths,
        '${element.name.local}[$elementIndex]',
      ].join('/');
      final attributes = <String, String>{
        for (final attribute in element.attributes)
          attribute.name.local.toLowerCase(): attribute.value,
      };
      final secure = attributes['secure'];
      if (secure != null) attributes.putIfAbsent('password', () => secure);
      final hintText = attributes['hinttext'];
      if (hintText != null) attributes.putIfAbsent('hint', () => hintText);
      final bounds = _readBounds(attributes);
      final parentPath = ancestorPaths.isEmpty
          ? null
          : '/${ancestorPaths.join('/')}';
      nodes.add(
        CockpitNativeUiNode(
          path: '/$path',
          parentPath: parentPath,
          ancestorPaths: List<String>.unmodifiable(<String>[
            for (var index = 0; index < ancestorPaths.length; index += 1)
              '/${ancestorPaths.take(index + 1).join('/')}',
          ]),
          elementName: element.name.local,
          attributes: Map<String, String>.unmodifiable(attributes),
          bounds: bounds,
        ),
      );
      for (final child in element.childElements) {
        visit(child, <String>[
          ...ancestorPaths,
          '${element.name.local}[$elementIndex]',
        ]);
      }
    }

    visit(document.rootElement, const <String>[]);
    var width = 0;
    var height = 0;
    for (final node in nodes) {
      final bounds = node.bounds;
      if (bounds == null) continue;
      if (bounds.right > width) width = bounds.right;
      if (bounds.bottom > height) height = bounds.bottom;
    }
    if (width <= 0 || height <= 0) {
      throw const FormatException(
        'Native UI tree does not contain a usable viewport.',
      );
    }
    return CockpitNativeUiSnapshot._(
      raw: raw,
      nodes: List<CockpitNativeUiNode>.unmodifiable(nodes),
      viewportWidth: width,
      viewportHeight: height,
    );
  }

  static CockpitNativeUiSnapshot _parseJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Native UI JSON root must be an object.');
    }
    final roots = <Map<Object?, Object?>>[];
    final windows = decoded['windows'];
    if (windows is List<Object?>) {
      roots.addAll(windows.whereType<Map<Object?, Object?>>());
    }
    final tree = decoded['tree'];
    if (tree is Map<Object?, Object?>) roots.add(tree);
    if (roots.isEmpty) {
      throw const FormatException('Native UI JSON contains no root nodes.');
    }

    final nodes = <CockpitNativeUiNode>[];

    void visit(
      Map<Object?, Object?> value,
      List<String> ancestorPaths,
      Map<String, int> siblingCounts,
    ) {
      final controlType = _jsonText(value['controlType']);
      final role = _jsonText(value['role']);
      final subrole = _jsonText(value['subrole']);
      final elementName = _jsonElementName(
        controlType ?? role ?? subrole ?? 'node',
      );
      final elementIndex = siblingCounts.update(
        elementName,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      final component = '$elementName[$elementIndex]';
      final pathParts = <String>[...ancestorPaths, component];
      final path = '/${pathParts.join('/')}';
      final attributes = <String, String>{};
      for (final entry in value.entries) {
        final key = entry.key;
        final scalar = _jsonScalar(entry.value);
        if (key is String && scalar != null) {
          attributes[key.toLowerCase()] = scalar;
        }
      }

      final title = _jsonText(value['title']);
      final name = _jsonText(value['name']);
      final description = _jsonText(value['description']);
      final automationId = _jsonText(value['automationId']);
      final className = _jsonText(value['className']);
      if (title != null) {
        attributes.putIfAbsent('text', () => title);
        attributes.putIfAbsent('label', () => title);
      }
      if (name != null) attributes.putIfAbsent('name', () => name);
      if (description != null) {
        attributes.putIfAbsent('hint', () => description);
      }
      if (role != null) attributes.putIfAbsent('role', () => role);
      if (controlType != null) {
        attributes.putIfAbsent('role', () => controlType);
        attributes.putIfAbsent('type', () => controlType);
      }
      if (subrole != null) attributes.putIfAbsent('type', () => subrole);
      if (automationId != null) {
        attributes.putIfAbsent('identifier', () => automationId);
        attributes.putIfAbsent('testid', () => automationId);
      }
      if (className != null) attributes.putIfAbsent('class', () => className);

      final frame = value['frame'];
      if (frame is Map<Object?, Object?>) {
        for (final key in const <String>['x', 'y', 'width', 'height']) {
          final scalar = _jsonScalar(frame[key]);
          if (scalar != null) attributes[key] = scalar;
        }
      }
      final parentPath = ancestorPaths.isEmpty
          ? null
          : '/${ancestorPaths.join('/')}';
      nodes.add(
        CockpitNativeUiNode(
          path: path,
          parentPath: parentPath,
          ancestorPaths: List<String>.unmodifiable(<String>[
            for (var index = 0; index < ancestorPaths.length; index += 1)
              '/${ancestorPaths.take(index + 1).join('/')}',
          ]),
          elementName: elementName,
          attributes: Map<String, String>.unmodifiable(attributes),
          bounds: _readBounds(attributes),
        ),
      );

      final children = value['children'];
      if (children is List<Object?>) {
        final childCounts = <String, int>{};
        for (final child in children.whereType<Map<Object?, Object?>>()) {
          visit(child, pathParts, childCounts);
        }
      }
    }

    final rootCounts = <String, int>{};
    for (final root in roots) {
      visit(root, const <String>[], rootCounts);
    }
    var width = 0;
    var height = 0;
    for (final node in nodes) {
      final bounds = node.bounds;
      if (bounds == null) continue;
      if (bounds.right > width) width = bounds.right;
      if (bounds.bottom > height) height = bounds.bottom;
    }
    if (width <= 0 || height <= 0) {
      throw const FormatException(
        'Native UI tree does not contain a usable viewport.',
      );
    }
    return CockpitNativeUiSnapshot._(
      raw: raw,
      nodes: List<CockpitNativeUiNode>.unmodifiable(nodes),
      viewportWidth: width,
      viewportHeight: height,
    );
  }

  CockpitNativeUiResolution resolve(
    CockpitTestLocator locator, {
    bool flutterAware = false,
  }) {
    final adapter = flutterAware ? 'flutterAwareNative' : 'native';
    for (final candidate in locator.flattened) {
      if (candidate.strategy == CockpitTestLocatorStrategy.visual) continue;
      final resolution = resolveSingle(candidate, flutterAware: flutterAware);
      if (resolution.found || resolution.ambiguous) return resolution;
    }
    return CockpitNativeUiResolution.notFound(locator, adapter: adapter);
  }

  CockpitNativeUiResolution resolveSingle(
    CockpitTestLocator locator, {
    bool flutterAware = false,
  }) {
    final adapter = flutterAware ? 'flutterAwareNative' : 'native';
    if (locator.strategy == CockpitTestLocatorStrategy.coordinate) {
      return CockpitNativeUiResolution.coordinate(
        locator: locator,
        adapter: adapter,
        x: (locator.x! * viewportWidth).round().clamp(0, viewportWidth - 1),
        y: (locator.y! * viewportHeight).round().clamp(0, viewportHeight - 1),
      );
    }
    if (locator.strategy == CockpitTestLocatorStrategy.visual) {
      return CockpitNativeUiResolution.notFound(locator, adapter: adapter);
    }
    final matches = _matchingNodes(locator, flutterAware: flutterAware);
    final index = locator.index;
    if (index != null) {
      return index < matches.length
          ? CockpitNativeUiResolution.node(
              locator: locator,
              node: matches[index],
              adapter: adapter,
            )
          : CockpitNativeUiResolution.notFound(locator, adapter: adapter);
    }
    if (matches.length == 1) {
      return CockpitNativeUiResolution.node(
        locator: locator,
        node: matches.single,
        adapter: adapter,
      );
    }
    if (matches.length > 1) {
      final preferred = _selectPreferredMatch(
        matches,
        locator,
        flutterAware: flutterAware,
      );
      if (preferred != null) {
        return CockpitNativeUiResolution.node(
          locator: locator,
          node: preferred,
          adapter: adapter,
        );
      }
      return CockpitNativeUiResolution.ambiguous(
        locator: locator,
        matchCount: matches.length,
        adapter: adapter,
      );
    }
    return CockpitNativeUiResolution.notFound(locator, adapter: adapter);
  }

  List<CockpitNativeUiNode> _matchingNodes(
    CockpitTestLocator locator, {
    required bool flutterAware,
  }) {
    final matches = nodes
        .where(
          (node) =>
              node.visible &&
              _matchesLocator(node, locator, flutterAware: flutterAware),
        )
        .toList(growable: false);
    return flutterAware
        ? _collapseFlutterSemanticDuplicates(matches, locator)
        : matches;
  }

  List<CockpitNativeUiNode> _collapseFlutterSemanticDuplicates(
    List<CockpitNativeUiNode> matches,
    CockpitTestLocator locator,
  ) {
    if (matches.length < 2) return matches;
    final redundantPaths = <String>{};
    for (var leftIndex = 0; leftIndex < matches.length; leftIndex += 1) {
      final left = matches[leftIndex];
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < matches.length;
        rightIndex += 1
      ) {
        final right = matches[rightIndex];
        if (!_sharesFlutterSemanticBounds(left, right) ||
            !_isAncestorOrDescendant(left, right)) {
          continue;
        }
        final preferred = _preferredFlutterSemanticNode(left, right, locator);
        redundantPaths.add(identical(preferred, left) ? right.path : left.path);
      }
    }
    return matches
        .where((candidate) => !redundantPaths.contains(candidate.path))
        .toList(growable: false);
  }

  bool _sharesFlutterSemanticBounds(
    CockpitNativeUiNode left,
    CockpitNativeUiNode right,
  ) {
    final leftBounds = left.bounds;
    final rightBounds = right.bounds;
    return leftBounds != null &&
        rightBounds != null &&
        leftBounds.left == rightBounds.left &&
        leftBounds.top == rightBounds.top &&
        leftBounds.right == rightBounds.right &&
        leftBounds.bottom == rightBounds.bottom;
  }

  bool _isAncestorOrDescendant(
    CockpitNativeUiNode left,
    CockpitNativeUiNode right,
  ) =>
      left.ancestorPaths.contains(right.path) ||
      right.ancestorPaths.contains(left.path);

  CockpitNativeUiNode _preferredFlutterSemanticNode(
    CockpitNativeUiNode left,
    CockpitNativeUiNode right,
    CockpitTestLocator locator,
  ) {
    final leftScore = _matchPriorityScore(left, locator, flutterAware: true);
    final rightScore = _matchPriorityScore(right, locator, flutterAware: true);
    if (leftScore != rightScore) return leftScore > rightScore ? left : right;
    if (left.ancestorPaths.length != right.ancestorPaths.length) {
      return left.ancestorPaths.length > right.ancestorPaths.length
          ? left
          : right;
    }
    return left.path.compareTo(right.path) <= 0 ? left : right;
  }

  List<CockpitNativeUiNode> _resolvedRelationNodes(
    CockpitTestLocator locator, {
    required bool flutterAware,
  }) {
    for (final candidate in locator.flattened) {
      if (candidate.degraded) continue;
      final matches = _matchingNodes(candidate, flutterAware: flutterAware);
      final index = candidate.index;
      if (index != null) {
        if (index < matches.length) {
          return <CockpitNativeUiNode>[matches[index]];
        }
        continue;
      }
      if (matches.isNotEmpty) return matches;
    }
    return const <CockpitNativeUiNode>[];
  }

  bool _matchesLocator(
    CockpitNativeUiNode node,
    CockpitTestLocator locator, {
    required bool flutterAware,
  }) {
    for (final signal in locator.signals) {
      if (!_matchesSignal(
        node,
        signal.strategy,
        signal.value,
        locator.matchMode,
      )) {
        return false;
      }
    }
    for (final state in locator.stateMap.entries) {
      if (node.state(state.key) != state.value) return false;
    }
    if (locator.ancestor case final ancestor?) {
      final paths = _resolvedRelationNodes(
        ancestor,
        flutterAware: flutterAware,
      ).map((candidate) => candidate.path).toSet();
      if (!node.ancestorPaths.any(paths.contains)) return false;
    }
    if (locator.child case final child?) {
      if (!_resolvedRelationNodes(
        child,
        flutterAware: flutterAware,
      ).any((candidate) => candidate.parentPath == node.path)) {
        return false;
      }
    }
    if (locator.descendant case final descendant?) {
      if (!_resolvedRelationNodes(
        descendant,
        flutterAware: flutterAware,
      ).any((candidate) => candidate.ancestorPaths.contains(node.path))) {
        return false;
      }
    }
    for (final relation
        in <
          ({
            CockpitTestLocator? locator,
            bool Function(CockpitNativeUiBounds, CockpitNativeUiBounds) matches,
          })
        >[
          (
            locator: locator.above,
            matches: (subject, reference) => subject.bottom <= reference.top,
          ),
          (
            locator: locator.below,
            matches: (subject, reference) => subject.top >= reference.bottom,
          ),
          (
            locator: locator.leftOf,
            matches: (subject, reference) => subject.right <= reference.left,
          ),
          (
            locator: locator.rightOf,
            matches: (subject, reference) => subject.left >= reference.right,
          ),
        ]) {
      final reference = relation.locator;
      if (reference == null) continue;
      final bounds = node.bounds;
      if (bounds == null ||
          !_resolvedRelationNodes(reference, flutterAware: flutterAware).any(
            (candidate) =>
                candidate.path != node.path &&
                candidate.bounds != null &&
                relation.matches(bounds, candidate.bounds!),
          )) {
        return false;
      }
    }
    return true;
  }

  bool _matchesSignal(
    CockpitNativeUiNode node,
    CockpitTestLocatorStrategy strategy,
    String expected,
    CockpitTextMatchMode matchMode,
  ) => switch (strategy) {
    CockpitTestLocatorStrategy.text => _matchesTextValues(
      node.textValues,
      expected,
      matchMode,
    ),
    CockpitTestLocatorStrategy.label => _matchesTextValues(
      node.labelValues,
      expected,
      matchMode,
    ),
    CockpitTestLocatorStrategy.nativeId => node.nativeIds.contains(expected),
    CockpitTestLocatorStrategy.testId => node.testIds.contains(expected),
    CockpitTestLocatorStrategy.role => node.roles.any(
      (role) => _typeMatches(role, expected),
    ),
    CockpitTestLocatorStrategy.type => node.types.any(
      (type) => _typeMatches(type, expected),
    ),
    CockpitTestLocatorStrategy.path => node.path == expected,
    CockpitTestLocatorStrategy.coordinate ||
    CockpitTestLocatorStrategy.visual => false,
  };

  CockpitNativeUiNode? _selectPreferredMatch(
    List<CockpitNativeUiNode> matches,
    CockpitTestLocator locator, {
    required bool flutterAware,
  }) {
    final ordered = matches.toList(growable: false)
      ..sort((left, right) {
        final scoreCompare =
            _matchPriorityScore(
              right,
              locator,
              flutterAware: flutterAware,
            ).compareTo(
              _matchPriorityScore(left, locator, flutterAware: flutterAware),
            );
        if (scoreCompare != 0) return scoreCompare;
        return left.path.compareTo(right.path);
      });
    final bestScore = _matchPriorityScore(
      ordered.first,
      locator,
      flutterAware: flutterAware,
    );
    if (ordered
        .skip(1)
        .any(
          (candidate) =>
              _matchPriorityScore(
                candidate,
                locator,
                flutterAware: flutterAware,
              ) ==
              bestScore,
        )) {
      return null;
    }
    return ordered.first;
  }

  int _matchPriorityScore(
    CockpitNativeUiNode node,
    CockpitTestLocator locator, {
    required bool flutterAware,
  }) {
    var score = 0;
    if (locator.text case final expected?) {
      score += _textValuesPriorityScore(
        node.textValues,
        expected,
        locator.matchMode,
      );
    }
    if (locator.label case final expected?) {
      score += _textValuesPriorityScore(
        node.labelValues,
        expected,
        locator.matchMode,
      );
    }
    if (flutterAware) score += _flutterSemanticActionabilityScore(node);
    return score;
  }

  int _flutterSemanticActionabilityScore(CockpitNativeUiNode node) {
    var score = 0;
    if (node.state('enabled') == true) score += 16;
    if (node.state('clickable') == true || node.state('hittable') == true) {
      score += 256;
    }
    if (node.state('long-clickable') == true) score += 64;
    if (node.state('focusable') == true || node.state('focused') == true) {
      score += 64;
    }
    if (node.state('checkable') == true || node.state('scrollable') == true) {
      score += 32;
    }
    if (node.types.followedBy(node.roles).any(_isInteractiveSemanticType)) {
      score += 128;
    }
    return score;
  }

  bool _isInteractiveSemanticType(String value) {
    final normalized = value.toLowerCase();
    return const <String>[
      'button',
      'checkbox',
      'textfield',
      'textinput',
      'switch',
      'radio',
      'slider',
      'link',
      'menuitem',
    ].any(normalized.contains);
  }

  bool _matchesTextValues(
    Iterable<String> values,
    String expected,
    CockpitTextMatchMode matchMode,
  ) => values.any((value) => _textMatches(value, expected, matchMode));

  bool _textMatches(
    String actual,
    String expected,
    CockpitTextMatchMode matchMode,
  ) => cockpitTextMatches(actual, expected, matchMode);

  int _textValuesPriorityScore(
    Iterable<String> values,
    String expected,
    CockpitTextMatchMode matchMode,
  ) {
    var bestScore = 0;
    for (final value in values) {
      final score = cockpitTextMatchScore(value, expected, matchMode);
      if (score > bestScore) bestScore = score;
    }
    return bestScore;
  }
}

final class CockpitNativeUiNode {
  const CockpitNativeUiNode({
    required this.path,
    required this.parentPath,
    required this.ancestorPaths,
    required this.elementName,
    required this.attributes,
    required this.bounds,
  });

  final String path;
  final String? parentPath;
  final List<String> ancestorPaths;
  final String elementName;
  final Map<String, String> attributes;
  final CockpitNativeUiBounds? bounds;

  bool get visible {
    final visible = attributes['visible'] ?? attributes['visible-to-user'];
    return visible?.toLowerCase() != 'false' && bounds?.hasArea == true;
  }

  Set<String> get textValues =>
      _values(<String>['text', 'value', 'label', 'name', 'hint']);

  Set<String> get labelValues =>
      _values(<String>['content-desc', 'label', 'name', 'hint']);

  Set<String> get nativeIds =>
      _values(<String>['resource-id', 'name', 'identifier', 'id']);

  Set<String> get testIds =>
      _values(<String>['resource-id', 'name', 'identifier', 'testid']);

  Set<String> get roles => _values(<String>['role', 'type', 'class']);

  Set<String> get types => <String>{
    elementName,
    ..._values(<String>['type', 'class']),
  };

  bool? state(String name) {
    final raw = attributes[name]?.trim().toLowerCase();
    return switch (raw) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => null,
    };
  }

  Set<String> _values(List<String> keys) => keys
      .map((key) => attributes[key]?.trim())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet();
}

final class CockpitNativeUiBounds {
  const CockpitNativeUiBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  bool get hasArea => right > left && bottom > top;
  int get centerX => left + ((right - left) / 2).round();
  int get centerY => top + ((bottom - top) / 2).round();
}

final class CockpitNativeUiResolution {
  const CockpitNativeUiResolution._({
    required this.locator,
    required this.adapter,
    this.node,
    this.x,
    this.y,
    this.matchCount = 0,
  });

  const CockpitNativeUiResolution.node({
    required CockpitTestLocator locator,
    required CockpitNativeUiNode node,
    required String adapter,
  }) : this._(locator: locator, adapter: adapter, node: node, matchCount: 1);

  const CockpitNativeUiResolution.coordinate({
    required CockpitTestLocator locator,
    required String adapter,
    required int x,
    required int y,
  }) : this._(locator: locator, adapter: adapter, x: x, y: y, matchCount: 1);

  const CockpitNativeUiResolution.ambiguous({
    required CockpitTestLocator locator,
    required int matchCount,
    required String adapter,
  }) : this._(locator: locator, adapter: adapter, matchCount: matchCount);

  const CockpitNativeUiResolution.notFound(
    CockpitTestLocator locator, {
    required String adapter,
  }) : this._(locator: locator, adapter: adapter);

  final CockpitTestLocator locator;
  final String adapter;
  final CockpitNativeUiNode? node;
  final int? x;
  final int? y;
  final int matchCount;

  bool get found => node != null || (x != null && y != null);
  bool get ambiguous => !found && matchCount > 1;
  int? get centerX => x ?? node?.bounds?.centerX;
  int? get centerY => y ?? node?.bounds?.centerY;
}

CockpitNativeUiBounds? _readBounds(Map<String, String> attributes) {
  final android = attributes['bounds'];
  if (android != null) {
    final match = RegExp(
      r'^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$',
    ).firstMatch(android.trim());
    if (match != null) {
      return CockpitNativeUiBounds(
        left: int.parse(match.group(1)!),
        top: int.parse(match.group(2)!),
        right: int.parse(match.group(3)!),
        bottom: int.parse(match.group(4)!),
      );
    }
  }
  final x = _number(attributes['x']);
  final y = _number(attributes['y']);
  final width = _number(attributes['width']);
  final height = _number(attributes['height']);
  if (x == null || y == null || width == null || height == null) return null;
  return CockpitNativeUiBounds(
    left: x.round(),
    top: y.round(),
    right: (x + width).round(),
    bottom: (y + height).round(),
  );
}

double? _number(String? value) => value == null ? null : double.tryParse(value);

String? _jsonText(Object? value) {
  final text = _jsonScalar(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _jsonScalar(Object? value) => switch (value) {
  String value => value,
  num value => '$value',
  bool value => '$value',
  _ => null,
};

String _jsonElementName(String value) {
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return normalized.isEmpty ? 'node' : normalized;
}

bool _typeMatches(String actual, String expected) {
  final normalizedActual = actual.toLowerCase();
  final normalizedExpected = expected.toLowerCase();
  final compactActual = normalizedActual.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  final compactExpected = normalizedExpected.replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '',
  );
  return normalizedActual == normalizedExpected ||
      normalizedActual.endsWith(normalizedExpected) ||
      normalizedActual.endsWith('type$normalizedExpected') ||
      compactActual == compactExpected ||
      compactActual.endsWith(compactExpected);
}
