import 'cockpit_errors.dart';

enum CockpitTextDirection { auto, ltr, rtl }

/// A validated BCP-47 locale profile carried with a test attempt.
final class CockpitLocaleProfile {
  const CockpitLocaleProfile(
    this.languageTag, {
    this.region,
    this.direction = CockpitTextDirection.auto,
    this.metadata = const <String, String>{},
  }) : assert(languageTag != '', 'languageTag must not be empty');

  final String languageTag;
  final String? region;
  final CockpitTextDirection direction;
  final Map<String, String> metadata;

  String toLanguageTag() => languageTag;

  CockpitLocaleProfile copyWith({
    String? languageTag,
    String? region,
    CockpitTextDirection? direction,
    Map<String, String>? metadata,
  }) => CockpitLocaleProfile(
    languageTag ?? this.languageTag,
    region: region ?? this.region,
    direction: direction ?? this.direction,
    metadata: metadata ?? this.metadata,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'languageTag': languageTag,
    if (region != null) 'region': region,
    'direction': direction.name,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  bool operator ==(Object other) =>
      other is CockpitLocaleProfile &&
      other.languageTag == languageTag &&
      other.region == region &&
      other.direction == direction &&
      _mapsEqual(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(languageTag, region, direction, metadata);
}

/// A lazily resolved translated value. It never snapshots a locale at
/// scenario construction time, so language switches are observed naturally.
final class CockpitLocalizedText {
  const CockpitLocalizedText(
    this.key, {
    this.values = const <String, String>{},
    this.resolver,
  }) : assert(key != '', 'key must not be empty');

  final String key;
  final Map<String, String> values;
  final CockpitTextResolver? resolver;

  String resolve(CockpitLocaleProfile locale) {
    final resolve = resolver;
    final resolved =
        resolve?.resolve(key, locale) ??
        values[locale.toLanguageTag()] ??
        values[locale.languageTag.split('-').first];
    if (resolved == null) {
      throw CockpitTestLocalizationException(
        key: key,
        message:
            'No translation for "$key" in locale ${locale.toLanguageTag()}.',
      );
    }
    return resolved;
  }
}

abstract interface class CockpitTextResolver {
  String? resolve(String key, CockpitLocaleProfile locale);
}

bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
