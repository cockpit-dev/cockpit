/// VM-only catalog loaders that read translation files from disk.
///
/// Host-side scenario code runs in a Dart VM process (`dart test`, the
/// programmatic runner, `flutter test`), so plain `dart:io` file reads are the
/// natural way to point a catalog at the app's real translation sources. Web
/// hosts should decode assets themselves and use the pure constructors.
library;

import 'dart:convert';
import 'dart:io';

import 'src/cockpit_catalog.dart';

/// Loads ARB files (Flutter `gen_l10n` catalogs) from disk.
///
/// [files] maps locale tags to ARB paths — typically the app's own
/// `lib/l10n/app_<locale>.arb` files:
///
/// ```dart
/// final catalog = loadCockpitArbCatalog({
///   'en': '../app/lib/l10n/app_en.arb',
///   'zh': '../app/lib/l10n/app_zh.arb',
/// });
/// ```
CockpitArbCatalog loadCockpitArbCatalog(Map<String, String> files) {
  return CockpitArbCatalog.fromArb({
    for (final entry in files.entries) entry.key: _decodeFile(entry.value),
  });
}

/// Loads per-locale JSON catalogs (`slang` sources, `easy_localization`
/// assets) from disk. [files] maps locale tags to JSON paths.
CockpitJsonCatalog loadCockpitJsonCatalog(Map<String, String> files) {
  return CockpitJsonCatalog.fromJson({
    for (final entry in files.entries) entry.key: _decodeFile(entry.value),
  });
}

Map<String, Object?> _decodeFile(String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on FileSystemException catch (error) {
    throw ArgumentError.value(path, 'files', 'Cannot read the file: $error');
  } on FormatException catch (error) {
    throw ArgumentError.value(path, 'files', 'Invalid JSON: $error');
  }
  if (decoded is! Map) {
    throw ArgumentError.value(path, 'files', 'Expected a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}
