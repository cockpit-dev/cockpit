import 'package:collection/collection.dart';

import 'cockpit_test_value_reader.dart';

enum CockpitTestValueType { string, integer, number, boolean, json }

enum CockpitTestTemplateValueKind { literal, variable, stringTemplate }

Object? cockpitTestCopyJsonValue(Object? value, {String path = r'$'}) =>
    CockpitTestValueReader.jsonValue(value, path);

final class CockpitTestTemplateValue {
  /// Creates a CockpitTestTemplateValue using the named constructor `literal`.
  CockpitTestTemplateValue.literal(Object? value, {required this.expectedType})
    : kind = CockpitTestTemplateValueKind.literal,
      value = _copyLiteral(value, expectedType, r'$'),
      variable = null;

  /// Creates a CockpitTestTemplateValue using the named constructor `variable`.
  CockpitTestTemplateValue.variable(this.variable, {required this.expectedType})
    : kind = CockpitTestTemplateValueKind.variable,
      value = null {
    CockpitTestValueReader.string(variable, r'$.$var', id: true);
  }

  /// Creates a CockpitTestTemplateValue using the named constructor `stringTemplate`.
  CockpitTestTemplateValue.stringTemplate(String template)
    : kind = CockpitTestTemplateValueKind.stringTemplate,
      expectedType = CockpitTestValueType.string,
      value = template,
      variable = null {
    CockpitTestValueReader.string(template, r'$');
  }

  final CockpitTestTemplateValueKind kind;
  final CockpitTestValueType expectedType;
  final Object? value;
  final String? variable;

  /// Encodes this CockpitTestTemplateValue as a JSON object.
  Object? toJson() => switch (kind) {
    CockpitTestTemplateValueKind.literal => value,
    CockpitTestTemplateValueKind.variable => <String, Object?>{
      r'$var': variable,
    },
    CockpitTestTemplateValueKind.stringTemplate => value,
  };

  /// Decodes a CockpitTestTemplateValue from a JSON object.
  factory CockpitTestTemplateValue.fromJson(
    Object? value, {
    required CockpitTestValueType expectedType,
    required String path,
  }) {
    if (value is Map<Object?, Object?>) {
      final json = CockpitTestValueReader.object(value, path);
      if (json.length == 1 && json.containsKey(r'$var')) {
        return CockpitTestTemplateValue.variable(
          CockpitTestValueReader.string(json[r'$var'], '$path.\$var', id: true),
          expectedType: expectedType,
        );
      }
    }
    if (expectedType == CockpitTestValueType.string &&
        value is String &&
        value.contains(r'${')) {
      return CockpitTestTemplateValue.stringTemplate(value);
    }
    _validateLiteral(value, expectedType, path);
    return CockpitTestTemplateValue.literal(
      CockpitTestValueReader.jsonValue(value, path),
      expectedType: expectedType,
    );
  }

  static void _validateLiteral(
    Object? value,
    CockpitTestValueType expectedType,
    String path,
  ) {
    switch (expectedType) {
      case CockpitTestValueType.string:
        CockpitTestValueReader.string(value, path);
      case CockpitTestValueType.integer:
        CockpitTestValueReader.integer(value, path);
      case CockpitTestValueType.number:
        CockpitTestValueReader.number(value, path);
      case CockpitTestValueType.boolean:
        CockpitTestValueReader.boolean(value, path);
      case CockpitTestValueType.json:
        CockpitTestValueReader.jsonValue(value, path);
    }
  }

  static Object? _copyLiteral(
    Object? value,
    CockpitTestValueType expectedType,
    String path,
  ) {
    _validateLiteral(value, expectedType, path);
    return CockpitTestValueReader.jsonValue(value, path);
  }

  @override
  bool operator ==(Object other) =>
      other is CockpitTestTemplateValue &&
      other.kind == kind &&
      other.expectedType == expectedType &&
      const DeepCollectionEquality().equals(other.value, value) &&
      other.variable == variable;

  @override
  int get hashCode => Object.hash(
    kind,
    expectedType,
    const DeepCollectionEquality().hash(value),
    variable,
  );
}
