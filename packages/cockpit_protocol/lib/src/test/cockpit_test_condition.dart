import '../control/cockpit_locator.dart';
import 'cockpit_test_error.dart';
import 'cockpit_test_locator.dart';
import 'cockpit_test_value.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestConditionKind { visible, text, route, uiIdle, networkIdle }

enum CockpitTestConditionState { matched, notMatched, error }

final class CockpitTestConditionTemplate {
  /// Creates a CockpitTestConditionTemplate.
  CockpitTestConditionTemplate({
    required this.kind,
    this.locator,
    this.expected,
    this.text,
    this.matchMode,
    this.route,
    this.quietMs,
  }) {
    _validate();
  }

  final CockpitTestConditionKind kind;
  final CockpitTestLocatorTemplate? locator;
  final CockpitTestTemplateValue? expected;
  final CockpitTestTemplateValue? text;
  final CockpitTextMatchMode? matchMode;
  final CockpitTestTemplateValue? route;
  final CockpitTestTemplateValue? quietMs;

  /// Encodes this CockpitTestConditionTemplate as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': kind.name,
    if (locator != null) 'locator': locator!.toJson(),
    if (expected != null) 'expected': expected!.toJson(),
    if (text != null) 'text': text!.toJson(),
    if (matchMode != null) 'matchMode': matchMode!.name,
    if (route != null) 'route': route!.toJson(),
    if (quietMs != null) 'quietMs': quietMs!.toJson(),
  };

  /// Decodes a CockpitTestConditionTemplate from a JSON object.
  factory CockpitTestConditionTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'type',
        'locator',
        'expected',
        'text',
        'matchMode',
        'route',
        'quietMs',
      },
      path,
      required: const <String>{'type'},
    );
    return CockpitTestConditionTemplate(
      kind: CockpitTestValueReader.enumeration(
        json['type'],
        CockpitTestConditionKind.values,
        '$path.type',
      ),
      locator: json['locator'] == null
          ? null
          : CockpitTestLocatorTemplate.fromJson(
              json['locator'],
              path: '$path.locator',
            ),
      expected: json['expected'] == null
          ? null
          : CockpitTestTemplateValue.fromJson(
              json['expected'],
              expectedType: CockpitTestValueType.boolean,
              path: '$path.expected',
            ),
      text: json['text'] == null
          ? null
          : CockpitTestTemplateValue.fromJson(
              json['text'],
              expectedType: CockpitTestValueType.string,
              path: '$path.text',
            ),
      matchMode: json['matchMode'] == null
          ? null
          : CockpitTestValueReader.enumeration(
              json['matchMode'],
              CockpitTextMatchMode.values,
              '$path.matchMode',
            ),
      route: json['route'] == null
          ? null
          : CockpitTestTemplateValue.fromJson(
              json['route'],
              expectedType: CockpitTestValueType.string,
              path: '$path.route',
            ),
      quietMs: json['quietMs'] == null
          ? null
          : CockpitTestTemplateValue.fromJson(
              json['quietMs'],
              expectedType: CockpitTestValueType.integer,
              path: '$path.quietMs',
            ),
    );
  }

  void _validate() {
    switch (kind) {
      case CockpitTestConditionKind.visible:
        if (locator == null ||
            text != null ||
            matchMode != null ||
            route != null ||
            quietMs != null) {
          throw const FormatException(
            'visible condition requires locator and accepts only expected.',
          );
        }
      case CockpitTestConditionKind.text:
        if (locator == null ||
            text == null ||
            expected != null ||
            route != null ||
            quietMs != null) {
          throw const FormatException(
            'text condition requires locator and text and accepts only matchMode.',
          );
        }
      case CockpitTestConditionKind.route:
        if (route == null ||
            locator != null ||
            expected != null ||
            text != null ||
            matchMode != null ||
            quietMs != null) {
          throw const FormatException('route condition requires only route.');
        }
      case CockpitTestConditionKind.uiIdle ||
          CockpitTestConditionKind.networkIdle:
        if (locator != null ||
            expected != null ||
            text != null ||
            matchMode != null ||
            route != null) {
          throw FormatException('${kind.name} condition accepts only quietMs.');
        }
    }
    if (quietMs?.kind == CockpitTestTemplateValueKind.literal &&
        (quietMs!.value! as int) <= 0) {
      throw const FormatException('Condition quietMs must be positive.');
    }
    if (kind == CockpitTestConditionKind.text &&
        matchMode == CockpitTextMatchMode.regex &&
        text?.kind == CockpitTestTemplateValueKind.literal) {
      RegExp(text!.value! as String);
    }
  }
}

final class CockpitTestCondition {
  /// Creates a CockpitTestCondition.
  CockpitTestCondition({
    required this.kind,
    this.locator,
    this.expected,
    this.text,
    this.matchMode,
    this.route,
    this.quietMs,
  }) {
    CockpitTestConditionTemplate(
      kind: kind,
      locator: locator == null
          ? null
          : CockpitTestLocatorTemplate.fromJson(
              locator!.toJson(),
              path: r'$.locator',
            ),
      expected: expected == null
          ? null
          : CockpitTestTemplateValue.literal(
              expected,
              expectedType: CockpitTestValueType.boolean,
            ),
      text: text == null
          ? null
          : CockpitTestTemplateValue.literal(
              text,
              expectedType: CockpitTestValueType.string,
            ),
      matchMode: matchMode,
      route: route == null
          ? null
          : CockpitTestTemplateValue.literal(
              route,
              expectedType: CockpitTestValueType.string,
            ),
      quietMs: quietMs == null
          ? null
          : CockpitTestTemplateValue.literal(
              quietMs,
              expectedType: CockpitTestValueType.integer,
            ),
    );
    if (quietMs != null && quietMs! <= 0) {
      throw const FormatException('Condition quietMs must be positive.');
    }
    if (kind == CockpitTestConditionKind.text &&
        matchMode == CockpitTextMatchMode.regex) {
      RegExp(text!);
    }
  }

  final CockpitTestConditionKind kind;
  final CockpitTestLocator? locator;
  final bool? expected;
  final String? text;
  final CockpitTextMatchMode? matchMode;
  final String? route;
  final int? quietMs;

  /// Encodes this CockpitTestCondition as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': kind.name,
    if (locator != null) 'locator': locator!.toJson(),
    if (expected != null) 'expected': expected,
    if (text != null) 'text': text,
    if (matchMode != null) 'matchMode': matchMode!.name,
    if (route != null) 'route': route,
    if (quietMs != null) 'quietMs': quietMs,
  };

  /// Decodes a CockpitTestCondition from a JSON object.
  factory CockpitTestCondition.fromJson(Object? value, {required String path}) {
    final template = CockpitTestConditionTemplate.fromJson(value, path: path);
    Object? literal(CockpitTestTemplateValue? candidate, String field) {
      if (candidate == null) {
        return null;
      }
      if (candidate.kind != CockpitTestTemplateValueKind.literal) {
        throw FormatException('Unbound condition value at $path.$field.');
      }
      return candidate.value;
    }

    return CockpitTestCondition(
      kind: template.kind,
      locator: template.locator == null
          ? null
          : CockpitTestLocator.fromJson(
              template.locator!.toJson(),
              path: '$path.locator',
            ),
      expected: literal(template.expected, 'expected') as bool?,
      text: literal(template.text, 'text') as String?,
      matchMode: template.matchMode,
      route: literal(template.route, 'route') as String?,
      quietMs: literal(template.quietMs, 'quietMs') as int?,
    );
  }
}

final class CockpitTestConditionEvaluation {
  const CockpitTestConditionEvaluation._({required this.state, this.error});

  /// Creates a CockpitTestConditionEvaluation using the named constructor `matched`.
  const CockpitTestConditionEvaluation.matched()
    : this._(state: CockpitTestConditionState.matched);

  /// Creates a CockpitTestConditionEvaluation using the named constructor `notMatched`.
  const CockpitTestConditionEvaluation.notMatched()
    : this._(state: CockpitTestConditionState.notMatched);

  /// Creates a CockpitTestConditionEvaluation using the named constructor `error`.
  const CockpitTestConditionEvaluation.error(CockpitTestError error)
    : this._(state: CockpitTestConditionState.error, error: error);

  final CockpitTestConditionState state;
  final CockpitTestError? error;

  /// Encodes this CockpitTestConditionEvaluation as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    if (error != null) 'error': error!.toJson(),
  };

  /// Decodes a CockpitTestConditionEvaluation from a JSON object.
  factory CockpitTestConditionEvaluation.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'state', 'error'},
      path,
      required: const <String>{'state'},
    );
    final state = CockpitTestValueReader.enumeration(
      json['state'],
      CockpitTestConditionState.values,
      '$path.state',
    );
    final error = json['error'] == null
        ? null
        : CockpitTestError.fromJson(json['error'], path: '$path.error');
    return switch (state) {
      CockpitTestConditionState.matched when error == null =>
        const CockpitTestConditionEvaluation.matched(),
      CockpitTestConditionState.notMatched when error == null =>
        const CockpitTestConditionEvaluation.notMatched(),
      CockpitTestConditionState.error when error != null =>
        CockpitTestConditionEvaluation.error(error),
      _ => throw FormatException(
        'Condition state and error presence are inconsistent at $path.',
      ),
    };
  }
}
