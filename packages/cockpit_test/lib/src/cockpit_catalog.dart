import 'cockpit_icu.dart';
import 'cockpit_locale.dart';

/// Translations authored in ARB, the format of Flutter's official `gen_l10n`
/// tooling — and the catalog format translation vendors already know.
///
/// The catalog reuses the app's own `app_<locale>.arb` files as the single
/// source of truth, so expected text cannot drift from what the app renders.
/// Every message is parsed and validated at construction: malformed ICU
/// messages and placeholders that the `@key` metadata does not declare fail
/// immediately with the full list of problems, not at some later assertion.
///
/// ```dart
/// final catalog = CockpitArbCatalog.fromArb({
///   'en': {'settings.saved': 'Saved'},
///   'zh': {'settings.saved': '已保存'},
/// });
/// await tester.expectText('#status', catalog.text('settings.saved'));
/// ```
final class CockpitArbCatalog {
  factory CockpitArbCatalog.fromArb(
    Map<String, Map<String, Object?>> arbByLocale,
  ) {
    final templates = <String, Map<String, String>>{};
    for (final entry in arbByLocale.entries) {
      final localeTag = _canonicalLocaleTag(entry.key);
      if (templates.containsKey(localeTag)) {
        throw ArgumentError.value(
          entry.key,
          'arbByLocale',
          'Locale $localeTag appears more than once.',
        );
      }
      final declaredTag = entry.value['@@locale'];
      if (declaredTag is String &&
          _canonicalLocaleTag(declaredTag) != localeTag) {
        throw ArgumentError.value(
          entry.key,
          'arbByLocale',
          'The file declares @@locale "$declaredTag" but was mapped to '
              '"$localeTag".',
        );
      }
      final messages = <String, String>{};
      final metadata = <String, Map<String, Object?>>{};
      for (final message in entry.value.entries) {
        if (message.key.startsWith('@')) {
          if (message.key != '@@locale' && message.value is Map) {
            metadata[message.key.substring(1)] = Map<String, Object?>.from(
              message.value as Map,
            );
          }
          continue;
        }
        if (message.value is! String) {
          throw ArgumentError.value(
            entry.key,
            'arbByLocale',
            'Message "${message.key}" in $localeTag must be a string.',
          );
        }
        if (messages.containsKey(message.key)) {
          throw ArgumentError.value(
            entry.key,
            'arbByLocale',
            'Duplicate message "${message.key}" in $localeTag.',
          );
        }
        messages[message.key] = message.value as String;
      }
      _validateArbMessages(
        localeTag: localeTag,
        messages: messages,
        metadata: metadata,
      );
      templates[localeTag] = Map<String, String>.unmodifiable(messages);
    }
    return CockpitArbCatalog._(templates);
  }

  CockpitArbCatalog._(this._templates);

  final Map<String, Map<String, String>> _templates;

  /// The canonical locale tags this catalog carries.
  List<String> get locales => List<String>.unmodifiable(_templates.keys);

  /// Every message key that appears in at least one locale.
  Set<String> get keys =>
      _templates.values.expand((locale) => locale.keys).toSet();

  /// The message [key] as a lazily resolved value.
  ///
  /// [params] resolves ICU placeholders, `plural`, and `select` constructs
  /// against the active locale; without params the raw message is returned.
  CockpitLocalizedText text(
    String key, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    final values = <String, String>{};
    for (final locale in _templates.entries) {
      final template = locale.value[key];
      if (template != null) values[locale.key] = template;
    }
    return CockpitLocalizedText(key, values: values, params: params);
  }

  /// Checks the catalog against a locale matrix before a suite runs.
  ///
  /// A key covers a locale when any tag in that locale's fallback chain
  /// carries the message, matching how [text] resolves at runtime. The report
  /// lists every gap; an empty report means the matrix is fully covered.
  CockpitCatalogCoverage validateMatrix(
    Iterable<CockpitLocaleProfile> locales,
  ) {
    final gaps = <CockpitCatalogGap>[];
    for (final locale in locales) {
      for (final key in keys) {
        final covered = locale.fallbackTags.any(
          (tag) => _templates[tag]?.containsKey(key) ?? false,
        );
        if (!covered) {
          gaps.add(
            CockpitCatalogGap(localeTag: locale.toLanguageTag(), key: key),
          );
        }
      }
    }
    return CockpitCatalogCoverage(gaps);
  }

  static void _validateArbMessages({
    required String localeTag,
    required Map<String, String> messages,
    required Map<String, Map<String, Object?>> metadata,
  }) {
    final problems = <String>[];
    for (final message in messages.entries) {
      final CockpitIcuMessage parsed;
      try {
        parsed = CockpitIcuMessage.parse(
          message.value,
          path: '$localeTag.${message.key}',
        );
      } on FormatException catch (error) {
        problems.add('$localeTag.${message.key}: ${error.message}');
        continue;
      }
      final declarations = metadata[message.key]?['placeholders'];
      if (declarations is! Map) continue;
      final declared = declarations.keys.toSet();
      for (final placeholder in parsed.placeholders) {
        if (!declared.contains(placeholder)) {
          problems.add(
            '$localeTag.${message.key}: placeholder "$placeholder" is used '
            'but not declared in the @-metadata.',
          );
        }
      }
    }
    if (problems.isNotEmpty) {
      throw ArgumentError.value(
        localeTag,
        'arbByLocale',
        'Invalid ARB messages:\n  - ${problems.join('\n  - ')}',
      );
    }
  }
}

/// Translations authored as plain JSON maps, the catalog shape used by
/// `slang` sources and `easy_localization` assets.
///
/// Keys are dotted paths into nested maps — `'settings.saved'` reads
/// `{"settings": {"saved": ...}}` — and each locale carries its own map:
///
/// ```dart
/// final catalog = CockpitJsonCatalog.fromJson({
///   'en': {'settings': {'saved': 'Saved'}},
///   'zh': {'settings': {'saved': '已保存'}},
/// });
/// ```
///
/// JSON leaves are returned verbatim unless [text] is given params, which
/// then resolve `{placeholder}` substitution and ICU constructs exactly like
/// ARB messages.
final class CockpitJsonCatalog {
  factory CockpitJsonCatalog.fromJson(
    Map<String, Map<String, Object?>> jsonByLocale,
  ) {
    final trees = <String, Map<String, Object?>>{};
    for (final entry in jsonByLocale.entries) {
      final localeTag = _canonicalLocaleTag(entry.key);
      if (trees.containsKey(localeTag)) {
        throw ArgumentError.value(
          entry.key,
          'jsonByLocale',
          'Locale $localeTag appears more than once.',
        );
      }
      trees[localeTag] = Map<String, Object?>.unmodifiable(entry.value);
      _validateLeaves(localeTag, entry.value, '');
    }
    return CockpitJsonCatalog._(trees);
  }

  CockpitJsonCatalog._(this._trees);

  final Map<String, Map<String, Object?>> _trees;

  /// The canonical locale tags this catalog carries.
  List<String> get locales => List<String>.unmodifiable(_trees.keys);

  /// Every dotted leaf path that appears in at least one locale.
  Set<String> get keys => <String>{
    for (final tree in _trees.values) ..._leafPaths(tree),
  };

  CockpitLocalizedText text(
    String key, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    final values = <String, String>{};
    for (final locale in _trees.entries) {
      final leaf = _lookup(locale.value, key);
      if (leaf != null) values[locale.key] = leaf;
    }
    return CockpitLocalizedText(key, values: values, params: params);
  }

  /// Checks the catalog against a locale matrix before a suite runs, with the
  /// same fallback-chain semantics as [text].
  CockpitCatalogCoverage validateMatrix(
    Iterable<CockpitLocaleProfile> locales,
  ) {
    final gaps = <CockpitCatalogGap>[];
    for (final locale in locales) {
      for (final key in keys) {
        final covered = locale.fallbackTags.any(
          (tag) => _lookup(_trees[tag], key) != null,
        );
        if (!covered) {
          gaps.add(
            CockpitCatalogGap(localeTag: locale.toLanguageTag(), key: key),
          );
        }
      }
    }
    return CockpitCatalogCoverage(gaps);
  }

  static void _validateLeaves(
    String localeTag,
    Map<String, Object?> node,
    String prefix,
  ) {
    for (final entry in node.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map) {
        _validateLeaves(localeTag, Map<String, Object?>.from(value), path);
      } else if (value is! String) {
        throw ArgumentError.value(
          localeTag,
          'jsonByLocale',
          '"$path" must be a string, got ${value.runtimeType}.',
        );
      }
    }
  }

  static Iterable<String> _leafPaths(
    Map<String, Object?> node, [
    String prefix = '',
  ]) {
    return node.entries.expand((entry) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      if (entry.value is Map) {
        return _leafPaths(Map<String, Object?>.from(entry.value as Map), path);
      }
      return <String>[path];
    });
  }

  static String? _lookup(Map<String, Object?>? tree, String key) {
    if (tree == null) return null;
    Object? current = tree;
    for (final segment in key.split('.')) {
      if (current is! Map) return null;
      current = current[segment];
    }
    return current is String ? current : null;
  }
}

/// The result of checking a catalog against a locale matrix.
final class CockpitCatalogCoverage {
  CockpitCatalogCoverage(Iterable<CockpitCatalogGap> gaps)
    : gaps = List<CockpitCatalogGap>.unmodifiable(gaps);

  /// Every (locale, key) pair the catalog does not cover.
  final List<CockpitCatalogGap> gaps;

  bool get isComplete => gaps.isEmpty;

  @override
  String toString() {
    if (isComplete) return 'Catalog covers the full locale matrix.';
    return 'Catalog gaps:\n  - ${gaps.join('\n  - ')}';
  }
}

/// One uncovered translation: [key] is missing for [localeTag], or cannot be
/// used ([problem] explains why).
final class CockpitCatalogGap {
  const CockpitCatalogGap({
    required this.localeTag,
    required this.key,
    this.problem,
  });

  final String localeTag;
  final String key;
  final String? problem;

  @override
  String toString() => '$localeTag/$key: ${problem ?? 'missing'}';
}

String _canonicalLocaleTag(String tag) {
  return CockpitLocaleProfile(tag.replaceAll('_', '-')).toLanguageTag();
}
