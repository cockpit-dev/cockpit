import 'package:collection/collection.dart';

import '../control/cockpit_locator.dart';
import 'cockpit_test_value.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestLocatorStrategy {
  text,
  label,
  nativeId,
  testId,
  role,
  type,
  path,
  coordinate,
  visual,
}

final class CockpitTestLocatorTemplate {
  /// Creates a CockpitTestLocatorTemplate.
  CockpitTestLocatorTemplate({
    this.text,
    this.label,
    this.matchMode,
    this.nativeId,
    this.testId,
    this.role,
    this.type,
    this.path,
    this.visual,
    this.x,
    this.y,
    this.threshold,
    this.index,
    this.enabled,
    this.selected,
    this.checked,
    this.focused,
    this.clickable,
    this.ancestor,
    this.child,
    this.descendant,
    this.above,
    this.below,
    this.leftOf,
    this.rightOf,
    Iterable<CockpitTestLocatorTemplate> fallbacks =
        const <CockpitTestLocatorTemplate>[],
  }) : fallbacks = List<CockpitTestLocatorTemplate>.unmodifiable(fallbacks) {
    _validateTemplate();
  }

  final CockpitTestTemplateValue? text;
  final CockpitTestTemplateValue? label;
  final CockpitTestTemplateValue? matchMode;
  final CockpitTestTemplateValue? nativeId;
  final CockpitTestTemplateValue? testId;
  final CockpitTestTemplateValue? role;
  final CockpitTestTemplateValue? type;
  final CockpitTestTemplateValue? path;
  final CockpitTestTemplateValue? visual;
  final CockpitTestTemplateValue? x;
  final CockpitTestTemplateValue? y;
  final CockpitTestTemplateValue? threshold;
  final CockpitTestTemplateValue? index;
  final CockpitTestTemplateValue? enabled;
  final CockpitTestTemplateValue? selected;
  final CockpitTestTemplateValue? checked;
  final CockpitTestTemplateValue? focused;
  final CockpitTestTemplateValue? clickable;
  final CockpitTestLocatorTemplate? ancestor;
  final CockpitTestLocatorTemplate? child;
  final CockpitTestLocatorTemplate? descendant;
  final CockpitTestLocatorTemplate? above;
  final CockpitTestLocatorTemplate? below;
  final CockpitTestLocatorTemplate? leftOf;
  final CockpitTestLocatorTemplate? rightOf;
  final List<CockpitTestLocatorTemplate> fallbacks;

  Iterable<
    ({CockpitTestLocatorStrategy strategy, CockpitTestTemplateValue value})
  >
  get signals sync* {
    for (final entry
        in <(CockpitTestLocatorStrategy, CockpitTestTemplateValue?)>[
          (CockpitTestLocatorStrategy.text, text),
          (CockpitTestLocatorStrategy.label, label),
          (CockpitTestLocatorStrategy.nativeId, nativeId),
          (CockpitTestLocatorStrategy.testId, testId),
          (CockpitTestLocatorStrategy.role, role),
          (CockpitTestLocatorStrategy.type, type),
          (CockpitTestLocatorStrategy.path, path),
        ]) {
      if (entry.$2 != null) {
        yield (strategy: entry.$1, value: entry.$2!);
      }
    }
  }

  bool get degraded => visual != null || x != null || y != null;

  CockpitTestLocatorStrategy get strategy {
    final primary = signals.firstOrNull;
    if (primary != null) return primary.strategy;
    if (x != null || y != null) return CockpitTestLocatorStrategy.coordinate;
    if (visual != null) return CockpitTestLocatorStrategy.visual;
    throw StateError('Locator template has no primary strategy.');
  }

  /// Encodes this CockpitTestLocatorTemplate as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (text != null) 'text': text!.toJson(),
    if (label != null) 'label': label!.toJson(),
    if (matchMode != null) 'matchMode': matchMode!.toJson(),
    if (nativeId != null) 'nativeId': nativeId!.toJson(),
    if (testId != null) 'testId': testId!.toJson(),
    if (role != null) 'role': role!.toJson(),
    if (type != null) 'type': type!.toJson(),
    if (path != null) 'path': path!.toJson(),
    if (visual != null) 'visual': visual!.toJson(),
    if (x != null) 'x': x!.toJson(),
    if (y != null) 'y': y!.toJson(),
    if (threshold != null) 'threshold': threshold!.toJson(),
    if (index != null) 'index': index!.toJson(),
    if (enabled != null) 'enabled': enabled!.toJson(),
    if (selected != null) 'selected': selected!.toJson(),
    if (checked != null) 'checked': checked!.toJson(),
    if (focused != null) 'focused': focused!.toJson(),
    if (clickable != null) 'clickable': clickable!.toJson(),
    if (ancestor != null) 'ancestor': ancestor!.toJson(),
    if (child != null) 'child': child!.toJson(),
    if (descendant != null) 'descendant': descendant!.toJson(),
    if (above != null) 'above': above!.toJson(),
    if (below != null) 'below': below!.toJson(),
    if (leftOf != null) 'leftOf': leftOf!.toJson(),
    if (rightOf != null) 'rightOf': rightOf!.toJson(),
    if (fallbacks.isNotEmpty)
      'fallbacks': fallbacks.map((locator) => locator.toJson()).toList(),
  };

  /// Decodes a CockpitTestLocatorTemplate from a JSON object.
  factory CockpitTestLocatorTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'text',
      'label',
      'matchMode',
      'nativeId',
      'testId',
      'role',
      'type',
      'path',
      'visual',
      'x',
      'y',
      'threshold',
      'index',
      'enabled',
      'selected',
      'checked',
      'focused',
      'clickable',
      'ancestor',
      'child',
      'descendant',
      'above',
      'below',
      'leftOf',
      'rightOf',
      'fallbacks',
    }, path);
    CockpitTestTemplateValue? template(
      String field,
      CockpitTestValueType type,
    ) => json[field] == null
        ? null
        : CockpitTestTemplateValue.fromJson(
            json[field],
            expectedType: type,
            path: '$path.$field',
          );
    CockpitTestLocatorTemplate? relation(String field) => json[field] == null
        ? null
        : CockpitTestLocatorTemplate.fromJson(
            json[field],
            path: '$path.$field',
          );
    final rawFallbacks = json['fallbacks'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['fallbacks'], '$path.fallbacks');
    return CockpitTestLocatorTemplate(
      text: template('text', CockpitTestValueType.string),
      label: template('label', CockpitTestValueType.string),
      matchMode: template('matchMode', CockpitTestValueType.string),
      nativeId: template('nativeId', CockpitTestValueType.string),
      testId: template('testId', CockpitTestValueType.string),
      role: template('role', CockpitTestValueType.string),
      type: template('type', CockpitTestValueType.string),
      path: template('path', CockpitTestValueType.string),
      visual: template('visual', CockpitTestValueType.string),
      x: template('x', CockpitTestValueType.number),
      y: template('y', CockpitTestValueType.number),
      threshold: template('threshold', CockpitTestValueType.number),
      index: template('index', CockpitTestValueType.integer),
      enabled: template('enabled', CockpitTestValueType.boolean),
      selected: template('selected', CockpitTestValueType.boolean),
      checked: template('checked', CockpitTestValueType.boolean),
      focused: template('focused', CockpitTestValueType.boolean),
      clickable: template('clickable', CockpitTestValueType.boolean),
      ancestor: relation('ancestor'),
      child: relation('child'),
      descendant: relation('descendant'),
      above: relation('above'),
      below: relation('below'),
      leftOf: relation('leftOf'),
      rightOf: relation('rightOf'),
      fallbacks: <CockpitTestLocatorTemplate>[
        for (var index = 0; index < rawFallbacks.length; index += 1)
          CockpitTestLocatorTemplate.fromJson(
            rawFallbacks[index],
            path: '$path.fallbacks[$index]',
          ),
      ],
    );
  }

  void _validateTemplate() {
    if (matchMode != null && text == null && label == null) {
      throw const FormatException(
        'Locator matchMode requires a text or label signal.',
      );
    }
    if (matchMode?.kind == CockpitTestTemplateValueKind.literal) {
      final rawMode = matchMode!.value! as String;
      final mode = CockpitTextMatchMode.values
          .where((candidate) => candidate.name == rawMode)
          .firstOrNull;
      if (mode == null) {
        throw const FormatException('Unsupported locator matchMode.');
      }
      if (mode == CockpitTextMatchMode.regex) {
        for (final pattern in <CockpitTestTemplateValue?>[text, label]) {
          if (pattern?.kind == CockpitTestTemplateValueKind.literal) {
            RegExp(pattern!.value! as String);
          }
        }
      }
    }
    final semantic = signals.isNotEmpty;
    final coordinate = x != null || y != null;
    final image = visual != null;
    if ((semantic ? 1 : 0) + (coordinate ? 1 : 0) + (image ? 1 : 0) != 1) {
      throw const FormatException(
        'A locator requires exactly one semantic, coordinate, or visual mode.',
      );
    }
    final constrained = <Object?>[
      enabled,
      selected,
      checked,
      focused,
      clickable,
      ancestor,
      child,
      descendant,
      above,
      below,
      leftOf,
      rightOf,
    ].any((value) => value != null);
    if (coordinate &&
        (x == null ||
            y == null ||
            threshold != null ||
            index != null ||
            constrained)) {
      throw const FormatException(
        'A coordinate locator requires x/y and forbids semantic constraints.',
      );
    }
    if (image && (index != null || constrained)) {
      throw const FormatException(
        'A visual locator forbids semantic constraints.',
      );
    }
    if (semantic && threshold != null) {
      throw const FormatException('A semantic locator forbids threshold.');
    }
    if (index?.kind == CockpitTestTemplateValueKind.literal &&
        (index!.value! as int) < 0) {
      throw const FormatException('Locator index must be non-negative.');
    }
    for (final coordinate in <CockpitTestTemplateValue?>[x, y]) {
      if (coordinate?.kind == CockpitTestTemplateValueKind.literal) {
        final value = coordinate!.value! as num;
        if (value < 0 || value > 1) {
          throw const FormatException(
            'Coordinate locator values must be normalized from 0 through 1.',
          );
        }
      }
    }
    if (threshold?.kind == CockpitTestTemplateValueKind.literal) {
      final value = threshold!.value! as num;
      if (value <= 0 || value > 1) {
        throw const FormatException('Visual threshold must be in (0, 1].');
      }
    }
  }
}

final class CockpitTestLocator {
  /// Creates a CockpitTestLocator.
  CockpitTestLocator({
    this.text,
    this.label,
    this.matchMode = CockpitTextMatchMode.exact,
    this.nativeId,
    this.testId,
    this.role,
    this.type,
    this.path,
    this.visual,
    this.x,
    this.y,
    this.threshold,
    this.index,
    this.enabled,
    this.selected,
    this.checked,
    this.focused,
    this.clickable,
    this.ancestor,
    this.child,
    this.descendant,
    this.above,
    this.below,
    this.leftOf,
    this.rightOf,
    Iterable<CockpitTestLocator> fallbacks = const <CockpitTestLocator>[],
  }) : fallbacks = List<CockpitTestLocator>.unmodifiable(fallbacks) {
    _validate();
  }

  final String? text;
  final String? label;
  final CockpitTextMatchMode matchMode;
  final String? nativeId;
  final String? testId;
  final String? role;
  final String? type;
  final String? path;
  final String? visual;
  final double? x;
  final double? y;
  final double? threshold;
  final int? index;
  final bool? enabled;
  final bool? selected;
  final bool? checked;
  final bool? focused;
  final bool? clickable;
  final CockpitTestLocator? ancestor;
  final CockpitTestLocator? child;
  final CockpitTestLocator? descendant;
  final CockpitTestLocator? above;
  final CockpitTestLocator? below;
  final CockpitTestLocator? leftOf;
  final CockpitTestLocator? rightOf;
  final List<CockpitTestLocator> fallbacks;

  Iterable<({CockpitTestLocatorStrategy strategy, String value})>
  get signals sync* {
    for (final entry in <(CockpitTestLocatorStrategy, String?)>[
      (CockpitTestLocatorStrategy.text, text),
      (CockpitTestLocatorStrategy.label, label),
      (CockpitTestLocatorStrategy.nativeId, nativeId),
      (CockpitTestLocatorStrategy.testId, testId),
      (CockpitTestLocatorStrategy.role, role),
      (CockpitTestLocatorStrategy.type, type),
      (CockpitTestLocatorStrategy.path, path),
    ]) {
      if (entry.$2 != null) {
        yield (strategy: entry.$1, value: entry.$2!);
      }
    }
  }

  CockpitTestLocatorStrategy get strategy {
    final primary = signals.firstOrNull;
    if (primary != null) return primary.strategy;
    if (x != null || y != null) return CockpitTestLocatorStrategy.coordinate;
    if (visual != null) return CockpitTestLocatorStrategy.visual;
    throw StateError('Locator has no primary strategy.');
  }

  String? get value => signals.firstOrNull?.value ?? visual;

  Map<String, String> get signalMap =>
      Map<String, String>.unmodifiable(<String, String>{
        for (final signal in signals) signal.strategy.name: signal.value,
      });

  Map<String, bool> get stateMap =>
      Map<String, bool>.unmodifiable(<String, bool>{
        'enabled': ?enabled,
        'selected': ?selected,
        'checked': ?checked,
        'focused': ?focused,
        'clickable': ?clickable,
      });

  bool get hasNativeOnlyConstraints =>
      stateMap.isNotEmpty ||
      child != null ||
      descendant != null ||
      above != null ||
      below != null ||
      leftOf != null ||
      rightOf != null;

  bool get degraded => visual != null || x != null || y != null;

  Iterable<CockpitTestLocator> get flattened sync* {
    yield this;
    for (final fallback in fallbacks) {
      yield* fallback.flattened;
    }
  }

  Iterable<CockpitTestLocator> get tree sync* {
    yield this;
    for (final relation in <CockpitTestLocator?>[
      ancestor,
      child,
      descendant,
      above,
      below,
      leftOf,
      rightOf,
    ]) {
      if (relation != null) yield* relation.tree;
    }
    for (final fallback in fallbacks) {
      yield* fallback.tree;
    }
  }

  /// Encodes this CockpitTestLocator as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (text != null) 'text': text,
    if (label != null) 'label': label,
    if (matchMode != CockpitTextMatchMode.exact) 'matchMode': matchMode.name,
    if (nativeId != null) 'nativeId': nativeId,
    if (testId != null) 'testId': testId,
    if (role != null) 'role': role,
    if (type != null) 'type': type,
    if (path != null) 'path': path,
    if (visual != null) 'visual': visual,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (threshold != null) 'threshold': threshold,
    if (index != null) 'index': index,
    if (enabled != null) 'enabled': enabled,
    if (selected != null) 'selected': selected,
    if (checked != null) 'checked': checked,
    if (focused != null) 'focused': focused,
    if (clickable != null) 'clickable': clickable,
    if (ancestor != null) 'ancestor': ancestor!.toJson(),
    if (child != null) 'child': child!.toJson(),
    if (descendant != null) 'descendant': descendant!.toJson(),
    if (above != null) 'above': above!.toJson(),
    if (below != null) 'below': below!.toJson(),
    if (leftOf != null) 'leftOf': leftOf!.toJson(),
    if (rightOf != null) 'rightOf': rightOf!.toJson(),
    if (fallbacks.isNotEmpty)
      'fallbacks': fallbacks.map((locator) => locator.toJson()).toList(),
  };

  /// Decodes a CockpitTestLocator from a JSON object.
  factory CockpitTestLocator.fromJson(Object? value, {required String path}) {
    final template = CockpitTestLocatorTemplate.fromJson(value, path: path);
    Object? literal(CockpitTestTemplateValue? candidate, String field) {
      if (candidate == null) {
        return null;
      }
      if (candidate.kind != CockpitTestTemplateValueKind.literal) {
        throw FormatException('Unbound locator value at $path.$field.');
      }
      return candidate.value;
    }

    return CockpitTestLocator(
      text: literal(template.text, 'text') as String?,
      label: literal(template.label, 'label') as String?,
      matchMode: template.matchMode == null
          ? CockpitTextMatchMode.exact
          : CockpitTextMatchMode.fromJson(
              literal(template.matchMode, 'matchMode'),
            ),
      nativeId: literal(template.nativeId, 'nativeId') as String?,
      testId: literal(template.testId, 'testId') as String?,
      role: literal(template.role, 'role') as String?,
      type: literal(template.type, 'type') as String?,
      path: literal(template.path, 'path') as String?,
      visual: literal(template.visual, 'visual') as String?,
      x: (literal(template.x, 'x') as num?)?.toDouble(),
      y: (literal(template.y, 'y') as num?)?.toDouble(),
      threshold: (literal(template.threshold, 'threshold') as num?)?.toDouble(),
      index: literal(template.index, 'index') as int?,
      enabled: literal(template.enabled, 'enabled') as bool?,
      selected: literal(template.selected, 'selected') as bool?,
      checked: literal(template.checked, 'checked') as bool?,
      focused: literal(template.focused, 'focused') as bool?,
      clickable: literal(template.clickable, 'clickable') as bool?,
      ancestor: template.ancestor == null
          ? null
          : CockpitTestLocator.fromJson(
              template.ancestor!.toJson(),
              path: '$path.ancestor',
            ),
      child: template.child == null
          ? null
          : CockpitTestLocator.fromJson(
              template.child!.toJson(),
              path: '$path.child',
            ),
      descendant: template.descendant == null
          ? null
          : CockpitTestLocator.fromJson(
              template.descendant!.toJson(),
              path: '$path.descendant',
            ),
      above: template.above == null
          ? null
          : CockpitTestLocator.fromJson(
              template.above!.toJson(),
              path: '$path.above',
            ),
      below: template.below == null
          ? null
          : CockpitTestLocator.fromJson(
              template.below!.toJson(),
              path: '$path.below',
            ),
      leftOf: template.leftOf == null
          ? null
          : CockpitTestLocator.fromJson(
              template.leftOf!.toJson(),
              path: '$path.leftOf',
            ),
      rightOf: template.rightOf == null
          ? null
          : CockpitTestLocator.fromJson(
              template.rightOf!.toJson(),
              path: '$path.rightOf',
            ),
      fallbacks: <CockpitTestLocator>[
        for (var index = 0; index < template.fallbacks.length; index += 1)
          CockpitTestLocator.fromJson(
            template.fallbacks[index].toJson(),
            path: '$path.fallbacks[$index]',
          ),
      ],
    );
  }

  void _validate() {
    for (final signal in signals) {
      if (signal.value.trim().isEmpty) {
        throw FormatException('${signal.strategy.name} locator is empty.');
      }
    }
    final semantic = signals.isNotEmpty;
    final coordinate = x != null || y != null;
    final image = visual != null;
    if ((semantic ? 1 : 0) + (coordinate ? 1 : 0) + (image ? 1 : 0) != 1) {
      throw const FormatException(
        'A locator requires exactly one semantic, coordinate, or visual mode.',
      );
    }
    final constrained = hasNativeOnlyConstraints || ancestor != null;
    if (coordinate) {
      if (x == null ||
          y == null ||
          threshold != null ||
          index != null ||
          constrained) {
        throw const FormatException(
          'A coordinate locator requires x/y and forbids semantic constraints.',
        );
      }
      if (x! < 0 || x! > 1 || y! < 0 || y! > 1) {
        throw const FormatException(
          'Coordinate locator values must be normalized from 0 through 1.',
        );
      }
    }
    if (image) {
      if (visual!.trim().isEmpty || index != null || constrained) {
        throw const FormatException(
          'A visual locator requires a non-empty asset and forbids semantic constraints.',
        );
      }
      if (threshold != null && (threshold! <= 0 || threshold! > 1)) {
        throw const FormatException('Visual threshold must be in (0, 1].');
      }
    }
    if (semantic && threshold != null) {
      throw const FormatException('A semantic locator forbids threshold.');
    }
    if (matchMode != CockpitTextMatchMode.exact &&
        text == null &&
        label == null) {
      throw const FormatException(
        'Locator matchMode requires a text or label signal.',
      );
    }
    if (matchMode == CockpitTextMatchMode.regex) {
      for (final pattern in <String?>[text, label]) {
        if (pattern != null) RegExp(pattern);
      }
    }
    if (index != null && index! < 0) {
      throw const FormatException('Locator index must be non-negative.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CockpitTestLocator &&
      const MapEquality<String, String>().equals(other.signalMap, signalMap) &&
      other.matchMode == matchMode &&
      other.visual == visual &&
      other.x == x &&
      other.y == y &&
      other.threshold == threshold &&
      other.index == index &&
      const MapEquality<String, bool>().equals(other.stateMap, stateMap) &&
      other.ancestor == ancestor &&
      other.child == child &&
      other.descendant == descendant &&
      other.above == above &&
      other.below == below &&
      other.leftOf == leftOf &&
      other.rightOf == rightOf &&
      const ListEquality<CockpitTestLocator>().equals(
        other.fallbacks,
        fallbacks,
      );

  @override
  int get hashCode => Object.hash(
    const MapEquality<String, String>().hash(signalMap),
    matchMode,
    visual,
    x,
    y,
    threshold,
    index,
    const MapEquality<String, bool>().hash(stateMap),
    ancestor,
    child,
    descendant,
    above,
    below,
    leftOf,
    rightOf,
    const ListEquality<CockpitTestLocator>().hash(fallbacks),
  );
}
