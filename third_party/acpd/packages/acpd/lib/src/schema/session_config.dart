/// Session configuration option selectors and their current state.
///
/// [SessionConfigOption] is a sealed union discriminated by `type`:
/// `select` (single-value dropdown) or `boolean` (on/off toggle). Select
/// options may be flat ([SessionConfigSelectOption]) or grouped
/// ([SessionConfigSelectGroup]).
library;

import '../json_codec.dart';
import 'enums.dart';

/// A possible value for a session configuration option.
class SessionConfigSelectOption {
  const SessionConfigSelectOption({
    required this.value,
    required this.name,
    this.description,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Unique identifier for this value.
  final String value;

  /// Human-readable label.
  final String name;

  /// Optional description.
  final String? description;

  final Map<String, Object?> meta;

  factory SessionConfigSelectOption.fromJson(Map<String, Object?> json) {
    return SessionConfigSelectOption(
      value: requireField<String>(json, 'value'),
      name: requireField<String>(json, 'name'),
      description: readField<String>(json, 'description'),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'value': value,
      'name': name,
    };
    if (description != null) json['description'] = description;
    writeMeta(json, meta);
    return json;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionConfigSelectOption &&
          value == other.value &&
          name == other.name &&
          description == other.description &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(value, name, description, meta);
}

/// A group of option values under a header.
class SessionConfigSelectGroup {
  const SessionConfigSelectGroup({
    required this.group,
    required this.name,
    this.options = const [],
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// Unique identifier for this group.
  final String group;

  /// Human-readable group label.
  final String name;

  /// Options in this group.
  final List<SessionConfigSelectOption> options;

  final Map<String, Object?> meta;

  factory SessionConfigSelectGroup.fromJson(Map<String, Object?> json) {
    return SessionConfigSelectGroup(
      group: requireField<String>(json, 'group'),
      name: requireField<String>(json, 'name'),
      options:
          readListField(json, 'options', SessionConfigSelectOption.fromJson),
      meta: readMeta(json),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'group': group,
      'name': name,
      'options': options.map((o) => o.toJson()).toList(),
    };
    writeMeta(json, meta);
    return json;
  }
}

/// A sealed union over flat vs grouped option lists.
sealed class SessionConfigSelectOptions {
  const SessionConfigSelectOptions();

  /// Parses an options list. Discriminates by the first element's shape:
  /// objects with a `group` field are groups, otherwise flat options.
  static SessionConfigSelectOptions? fromJson(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final first = raw.first;
    if (first is Map && first.containsKey('group')) {
      return SessionConfigGroupedOptions.fromJson(
          raw.cast<Map<String, Object?>>());
    }
    return SessionConfigUngroupedOptions.fromJson(
        raw.cast<Map<String, Object?>>());
  }

  List<Object?> toJson();
}

/// A flat list of options.
final class SessionConfigUngroupedOptions extends SessionConfigSelectOptions {
  const SessionConfigUngroupedOptions(this.options);

  final List<SessionConfigSelectOption> options;

  factory SessionConfigUngroupedOptions.fromJson(
      List<Map<String, Object?>> json) {
    return SessionConfigUngroupedOptions(
        json.map(SessionConfigSelectOption.fromJson).toList());
  }

  @override
  List<Object?> toJson() => options.map((o) => o.toJson()).toList();
}

/// A grouped list of options.
final class SessionConfigGroupedOptions extends SessionConfigSelectOptions {
  const SessionConfigGroupedOptions(this.groups);

  final List<SessionConfigSelectGroup> groups;

  factory SessionConfigGroupedOptions.fromJson(
      List<Map<String, Object?>> json) {
    return SessionConfigGroupedOptions(
        json.map(SessionConfigSelectGroup.fromJson).toList());
  }

  @override
  List<Object?> toJson() => groups.map((g) => g.toJson()).toList();
}

/// A session configuration option — select or boolean.
sealed class SessionConfigOption {
  const SessionConfigOption({required this.id, required this.name});

  /// Unique identifier.
  final String id;

  /// Human-readable label.
  final String name;

  /// The wire discriminator.
  String get type;

  /// Optional description.
  String? get description;

  /// Optional semantic category (UX hint).
  SessionConfigOptionCategory? get category;

  /// Free-form metadata.
  Map<String, Object?> get meta;

  /// Parses a config option by its `type` discriminator.
  static SessionConfigOption fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'boolean' => SessionConfigBooleanOption.fromJson(json),
      _ => SessionConfigSelectOptionValue.fromJson(json),
    };
  }

  Map<String, Object?> toJson();
}

/// A single-value (dropdown) config option.
final class SessionConfigSelectOptionValue extends SessionConfigOption {
  const SessionConfigSelectOptionValue({
    required super.id,
    required super.name,
    required this.currentValue,
    required this.options,
    this.description,
    this.category,
    this.meta = const {},
  });

  /// Currently selected value.
  final String currentValue;

  /// Selectable options.
  final SessionConfigSelectOptions options;

  @override
  String get type => 'select';

  @override
  final String? description;

  @override
  final SessionConfigOptionCategory? category;

  @override
  final Map<String, Object?> meta;

  factory SessionConfigSelectOptionValue.fromJson(Map<String, Object?> json) {
    return SessionConfigSelectOptionValue(
      id: requireField<String>(json, 'id'),
      name: requireField<String>(json, 'name'),
      currentValue: requireField<String>(json, 'currentValue'),
      options: SessionConfigSelectOptions.fromJson(json['options']) ??
          const SessionConfigUngroupedOptions([]),
      description: readField<String>(json, 'description'),
      category: _readCategory(json['category']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'id': id,
      'name': name,
      'currentValue': currentValue,
      'options': options.toJson(),
    };
    if (description != null) json['description'] = description;
    if (category != null) json['category'] = category!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

/// A boolean on/off config option.
final class SessionConfigBooleanOption extends SessionConfigOption {
  const SessionConfigBooleanOption({
    required super.id,
    required super.name,
    required this.currentValue,
    this.description,
    this.category,
    this.meta = const {},
  });

  final bool currentValue;

  @override
  String get type => 'boolean';

  @override
  final String? description;

  @override
  final SessionConfigOptionCategory? category;

  @override
  final Map<String, Object?> meta;

  factory SessionConfigBooleanOption.fromJson(Map<String, Object?> json) {
    return SessionConfigBooleanOption(
      id: requireField<String>(json, 'id'),
      name: requireField<String>(json, 'name'),
      currentValue: requireField<bool>(json, 'currentValue'),
      description: readField<String>(json, 'description'),
      category: _readCategory(json['category']),
      meta: readMeta(json),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'type': type,
      'id': id,
      'name': name,
      'currentValue': currentValue,
    };
    if (description != null) json['description'] = description;
    if (category != null) json['category'] = category!.toJson();
    writeMeta(json, meta);
    return json;
  }
}

SessionConfigOptionCategory? _readCategory(Object? raw) {
  if (raw is String) return SessionConfigOptionCategory.fromJson(raw);
  return null;
}
