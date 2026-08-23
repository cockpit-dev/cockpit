import 'package:collection/collection.dart';

enum CockpitCheckState {
  off('off'),
  on('on'),
  mixed('mixed');

  const CockpitCheckState(this.jsonValue);

  final String jsonValue;

  static CockpitCheckState fromJson(Object? json) {
    return values.firstWhere(
      (value) => value.jsonValue == json,
      orElse: () => throw ArgumentError.value(
        json,
        'json',
        'Unsupported control check state.',
      ),
    );
  }
}

/// Runtime state exposed by a Flutter control without application wiring.
final class CockpitControlState {
  const CockpitControlState({
    this.enabled = true,
    this.selected,
    this.checked,
    this.focused = false,
    this.readOnly = false,
    this.obscured = false,
    this.value,
  });

  final bool enabled;
  final bool? selected;
  final CockpitCheckState? checked;
  final bool focused;
  final bool readOnly;
  final bool obscured;
  final Object? value;

  static const DeepCollectionEquality _valueEquality = DeepCollectionEquality();

  Map<String, Object?> toJson() => <String, Object?>{
    if (!enabled) 'enabled': false,
    if (selected != null) 'selected': selected,
    if (checked != null) 'checked': checked!.jsonValue,
    if (focused) 'focused': true,
    if (readOnly) 'readOnly': true,
    if (obscured) 'obscured': true,
    if (value != null && !obscured) 'value': value,
  };

  factory CockpitControlState.fromJson(Map<String, Object?> json) {
    return CockpitControlState(
      enabled: json['enabled'] != false,
      selected: json['selected'] as bool?,
      checked: json['checked'] == null
          ? null
          : CockpitCheckState.fromJson(json['checked']),
      focused: json['focused'] == true,
      readOnly: json['readOnly'] == true,
      obscured: json['obscured'] == true,
      value: json['value'],
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitControlState &&
            other.enabled == enabled &&
            other.selected == selected &&
            other.checked == checked &&
            other.focused == focused &&
            other.readOnly == readOnly &&
            other.obscured == obscured &&
            _valueEquality.equals(other.value, value);
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    selected,
    checked,
    focused,
    readOnly,
    obscured,
    _valueEquality.hash(value),
  );
}
