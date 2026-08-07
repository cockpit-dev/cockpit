import 'cockpit_test_value.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestVariableSource { constant, input, secret }

const Object _absentVariableValue = Object();

final class CockpitTestVariableDeclaration {
  /// Creates a CockpitTestVariableDeclaration.
  CockpitTestVariableDeclaration({
    required this.source,
    required this.valueType,
    Object? value = _absentVariableValue,
    Object? defaultValue = _absentVariableValue,
    this.required = true,
    this.secretReference,
  }) : hasValue = !identical(value, _absentVariableValue),
       value = identical(value, _absentVariableValue)
           ? null
           : _typedVariableValue(value, valueType, r'$.value'),
       hasDefaultValue = !identical(defaultValue, _absentVariableValue),
       defaultValue = identical(defaultValue, _absentVariableValue)
           ? null
           : _typedVariableValue(defaultValue, valueType, r'$.default') {
    switch (source) {
      case CockpitTestVariableSource.constant:
        if (!hasValue || hasDefaultValue || secretReference != null) {
          throw const FormatException(
            'A constant variable requires value and forbids default/reference.',
          );
        }
      case CockpitTestVariableSource.input:
        if (hasValue || secretReference != null) {
          throw const FormatException(
            'An input variable forbids value and secret reference.',
          );
        }
      case CockpitTestVariableSource.secret:
        if (valueType != CockpitTestValueType.string ||
            hasValue ||
            hasDefaultValue ||
            secretReference == null ||
            secretReference!.trim().isEmpty) {
          throw const FormatException(
            'A secret variable must be a string reference without a value.',
          );
        }
    }
  }

  final CockpitTestVariableSource source;
  final CockpitTestValueType valueType;
  final bool hasValue;
  final Object? value;
  final bool hasDefaultValue;
  final Object? defaultValue;
  final bool required;
  final String? secretReference;

  /// Encodes this CockpitTestVariableDeclaration as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.name,
    'type': valueType.name,
    if (hasValue) 'value': value,
    if (hasDefaultValue) 'default': defaultValue,
    if (source == CockpitTestVariableSource.input) 'required': required,
    if (secretReference != null) 'reference': secretReference,
  };

  /// Decodes a CockpitTestVariableDeclaration from a JSON object.
  factory CockpitTestVariableDeclaration.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'source',
        'type',
        'value',
        'default',
        'required',
        'reference',
      },
      path,
      required: const <String>{'source', 'type'},
    );
    final source = CockpitTestValueReader.enumeration(
      json['source'],
      CockpitTestVariableSource.values,
      '$path.source',
    );
    final type = CockpitTestValueReader.enumeration(
      json['type'],
      CockpitTestValueType.values,
      '$path.type',
    );
    final rawValue = json.containsKey('value')
        ? _typedVariableValue(json['value'], type, '$path.value')
        : null;
    final rawDefault = json.containsKey('default')
        ? _typedVariableValue(json['default'], type, '$path.default')
        : null;
    switch (source) {
      case CockpitTestVariableSource.constant:
        if (!json.containsKey('value') ||
            json.containsKey('default') ||
            json.containsKey('required') ||
            json.containsKey('reference')) {
          throw FormatException(
            'A constant variable has invalid fields at $path.',
          );
        }
      case CockpitTestVariableSource.input:
        if (json.containsKey('value') || json.containsKey('reference')) {
          throw FormatException(
            'An input variable has invalid fields at $path.',
          );
        }
      case CockpitTestVariableSource.secret:
        if (type != CockpitTestValueType.string ||
            json.containsKey('value') ||
            json.containsKey('default') ||
            json.containsKey('required') ||
            !json.containsKey('reference')) {
          throw FormatException(
            'A secret variable has invalid fields at $path.',
          );
        }
    }
    return CockpitTestVariableDeclaration(
      source: source,
      valueType: type,
      value: json.containsKey('value') ? rawValue : _absentVariableValue,
      defaultValue: json.containsKey('default')
          ? rawDefault
          : _absentVariableValue,
      required: json['required'] == null
          ? true
          : CockpitTestValueReader.boolean(json['required'], '$path.required'),
      secretReference: CockpitTestValueReader.optionalString(
        json['reference'],
        '$path.reference',
      ),
    );
  }
}

Object? _typedVariableValue(
  Object? value,
  CockpitTestValueType type,
  String path,
) {
  final parsed = CockpitTestTemplateValue.fromJson(
    value,
    expectedType: type,
    path: path,
  );
  if (parsed.kind != CockpitTestTemplateValueKind.literal) {
    throw FormatException(
      'Variable values cannot reference another variable at $path.',
    );
  }
  return parsed.value;
}

final class CockpitTestSecretToken {
  /// Creates a CockpitTestSecretToken.
  const CockpitTestSecretToken(this.value);

  final String value;

  @override
  String toString() => '<secret-token>';
}
