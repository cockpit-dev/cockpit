import 'cockpit_errors.dart';

enum CockpitTextDirection { auto, ltr, rtl }

/// A canonical language tag and presentation profile carried with a test attempt.
final class CockpitLocaleProfile {
  factory CockpitLocaleProfile(
    String languageTag, {
    String? region,
    CockpitTextDirection direction = CockpitTextDirection.auto,
    Map<String, String> metadata = const <String, String>{},
  }) {
    final parsed = _ParsedLanguageTag.parse(languageTag);
    final normalizedRegion = region == null ? null : _normalizeRegion(region);
    if (normalizedRegion != null &&
        parsed.region != null &&
        normalizedRegion != parsed.region) {
      throw ArgumentError.value(
        region,
        'region',
        'Conflicts with region ${parsed.region} in $languageTag.',
      );
    }
    final resolved = normalizedRegion == null || parsed.region != null
        ? parsed
        : parsed.withRegion(normalizedRegion);
    return CockpitLocaleProfile._(
      parsed: resolved,
      direction: direction,
      metadata: Map<String, String>.unmodifiable(metadata),
    );
  }

  CockpitLocaleProfile._({
    required _ParsedLanguageTag parsed,
    required this.direction,
    required this.metadata,
  }) : _parsed = parsed,
       languageTag = parsed.canonical;

  final _ParsedLanguageTag _parsed;
  final String languageTag;
  final CockpitTextDirection direction;
  final Map<String, String> metadata;

  String get languageCode => _parsed.language;
  String? get scriptCode => _parsed.script;
  String? get regionCode => _parsed.region;
  String? get region => regionCode;

  String toLanguageTag() => languageTag;

  CockpitLocaleProfile copyWith({
    String? languageTag,
    String? region,
    CockpitTextDirection? direction,
    Map<String, String>? metadata,
  }) {
    final sourceTag =
        languageTag ??
        (region == null
            ? this.languageTag
            : _parsed.withRegion(null).canonical);
    return CockpitLocaleProfile(
      sourceTag,
      region: region,
      direction: direction ?? this.direction,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'languageTag': languageTag,
    if (regionCode != null) 'region': regionCode,
    'direction': direction.name,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CockpitLocaleProfile &&
          other.languageTag == languageTag &&
          other.direction == direction &&
          _mapsEqual(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(languageTag, direction, _mapHash(metadata));
}

/// A lazily resolved translated value. It never snapshots a locale at
/// scenario construction time, so language switches are observed naturally.
final class CockpitLocalizedText {
  factory CockpitLocalizedText(
    String key, {
    Map<String, String> values = const <String, String>{},
    CockpitTextResolver? resolver,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) throw ArgumentError.value(key, 'key');
    return CockpitLocalizedText._(
      key: normalizedKey,
      values: _normalizedTranslations(values),
      resolver: resolver,
    );
  }

  CockpitLocalizedText._({
    required this.key,
    required this.values,
    required this.resolver,
  });

  final String key;
  final Map<String, String> values;
  final CockpitTextResolver? resolver;

  String resolve(CockpitLocaleProfile locale) {
    final resolvedByResolver = resolver?.resolve(key, locale);
    if (resolvedByResolver != null) return resolvedByResolver;

    for (final candidate in locale._parsed.fallbackTags) {
      final resolved = values[candidate];
      if (resolved != null) return resolved;
    }
    throw CockpitTestLocalizationException(
      key: key,
      message: 'No translation for "$key" in locale ${locale.toLanguageTag()}.',
    );
  }
}

abstract interface class CockpitTextResolver {
  String? resolve(String key, CockpitLocaleProfile locale);
}

Map<String, String> _normalizedTranslations(Map<String, String> values) {
  final result = <String, String>{};
  for (final entry in values.entries) {
    final tag = _ParsedLanguageTag.parse(entry.key).canonical;
    if (result.containsKey(tag)) {
      throw ArgumentError.value(
        values,
        'values',
        'Contains duplicate locale $tag after normalization.',
      );
    }
    result[tag] = entry.value;
  }
  return Map<String, String>.unmodifiable(result);
}

String _normalizeRegion(String value) {
  final normalized = value.trim();
  if (!_regionPattern.hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'region',
      'Expected a two-letter or three-digit region subtag.',
    );
  }
  return _lettersPattern.hasMatch(normalized)
      ? normalized.toUpperCase()
      : normalized;
}

bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash(Map<String, String> value) {
  final keys = value.keys.toList(growable: false)..sort();
  return Object.hashAll(keys.map((key) => Object.hash(key, value[key])));
}

final RegExp _languagePattern = RegExp(r'^[A-Za-z]{2,8}$');
final RegExp _extlangPattern = RegExp(r'^[A-Za-z]{3}$');
final RegExp _scriptPattern = RegExp(r'^[A-Za-z]{4}$');
final RegExp _regionPattern = RegExp(r'^(?:[A-Za-z]{2}|[0-9]{3})$');
final RegExp _variantPattern = RegExp(
  r'^(?:[A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3})$',
);
final RegExp _singletonPattern = RegExp(r'^[0-9A-WY-Za-wy-z]$');
final RegExp _extensionPattern = RegExp(r'^[A-Za-z0-9]{2,8}$');
final RegExp _privateUsePattern = RegExp(r'^[A-Za-z0-9]{1,8}$');
final RegExp _lettersPattern = RegExp(r'^[A-Za-z]+$');

final class _ParsedLanguageTag {
  _ParsedLanguageTag({
    required this.language,
    required this.extlangs,
    required this.script,
    required this.region,
    required this.variants,
    required this.extensions,
    required this.privateUse,
  }) : canonical = <String>[
         language,
         ...extlangs,
         ?script,
         ?region,
         ...variants,
         for (final extension in extensions) ...extension,
         if (privateUse.isNotEmpty) ...<String>['x', ...privateUse],
       ].join('-');

  factory _ParsedLanguageTag.parse(String value) {
    final source = value.trim();
    if (source.isEmpty) throw ArgumentError.value(value, 'languageTag');
    final parts = source.split('-');
    if (parts.any((part) => part.isEmpty)) {
      throw ArgumentError.value(
        value,
        'languageTag',
        'Language tags must use non-empty hyphen-separated subtags.',
      );
    }

    var index = 0;
    final languagePart = parts[index++];
    if (!_languagePattern.hasMatch(languagePart)) {
      throw ArgumentError.value(
        value,
        'languageTag',
        'Expected a 2-8 letter language subtag.',
      );
    }
    final language = languagePart.toLowerCase();

    final extlangs = <String>[];
    if (languagePart.length <= 3) {
      while (index < parts.length &&
          extlangs.length < 3 &&
          _extlangPattern.hasMatch(parts[index])) {
        extlangs.add(parts[index++].toLowerCase());
      }
    }

    String? script;
    if (index < parts.length && _scriptPattern.hasMatch(parts[index])) {
      final sourceScript = parts[index++].toLowerCase();
      script = '${sourceScript[0].toUpperCase()}${sourceScript.substring(1)}';
    }

    String? region;
    if (index < parts.length && _regionPattern.hasMatch(parts[index])) {
      region = _normalizeRegion(parts[index++]);
    }

    final variants = <String>[];
    final seenVariants = <String>{};
    while (index < parts.length && _variantPattern.hasMatch(parts[index])) {
      final variant = parts[index++].toLowerCase();
      if (!seenVariants.add(variant)) {
        throw ArgumentError.value(
          value,
          'languageTag',
          'Variant subtags must not be repeated.',
        );
      }
      variants.add(variant);
    }

    final extensions = <List<String>>[];
    final seenSingletons = <String>{};
    while (index < parts.length && _singletonPattern.hasMatch(parts[index])) {
      final singleton = parts[index++].toLowerCase();
      if (!seenSingletons.add(singleton)) {
        throw ArgumentError.value(
          value,
          'languageTag',
          'Extension singletons must not be repeated.',
        );
      }
      final extension = <String>[singleton];
      while (index < parts.length && _extensionPattern.hasMatch(parts[index])) {
        extension.add(parts[index++].toLowerCase());
      }
      if (extension.length == 1) {
        throw ArgumentError.value(
          value,
          'languageTag',
          'Extension $singleton requires at least one value subtag.',
        );
      }
      extensions.add(extension);
    }

    final privateUse = <String>[];
    if (index < parts.length && parts[index].toLowerCase() == 'x') {
      index++;
      while (index < parts.length &&
          _privateUsePattern.hasMatch(parts[index])) {
        privateUse.add(parts[index++].toLowerCase());
      }
      if (privateUse.isEmpty) {
        throw ArgumentError.value(
          value,
          'languageTag',
          'Private-use marker x requires at least one subtag.',
        );
      }
    }

    if (index != parts.length) {
      throw ArgumentError.value(
        value,
        'languageTag',
        'Contains an invalid or misplaced subtag: ${parts[index]}.',
      );
    }

    return _ParsedLanguageTag(
      language: language,
      extlangs: List<String>.unmodifiable(extlangs),
      script: script,
      region: region,
      variants: List<String>.unmodifiable(variants),
      extensions: List<List<String>>.unmodifiable(
        extensions.map(List<String>.unmodifiable),
      ),
      privateUse: List<String>.unmodifiable(privateUse),
    );
  }

  final String language;
  final List<String> extlangs;
  final String? script;
  final String? region;
  final List<String> variants;
  final List<List<String>> extensions;
  final List<String> privateUse;
  final String canonical;

  String get languageBase => <String>[language, ...extlangs].join('-');

  List<String> get fallbackTags => <String>[
    canonical,
    if (script != null) '$languageBase-$script',
    languageBase,
  ];

  _ParsedLanguageTag withRegion(String? value) => _ParsedLanguageTag(
    language: language,
    extlangs: extlangs,
    script: script,
    region: value,
    variants: variants,
    extensions: extensions,
    privateUse: privateUse,
  );
}
