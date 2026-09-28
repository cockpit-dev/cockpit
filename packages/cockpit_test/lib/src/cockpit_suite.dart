import 'cockpit_json.dart';
import 'cockpit_locale.dart';
import 'cockpit_scenario.dart';

final class CockpitTestCaseProgram {
  CockpitTestCaseProgram({
    required String id,
    required this.scenario,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : id = _validatedId(id),
       metadata = freezeCockpitJson(metadata, path: r'$.metadata');

  final String id;
  final CockpitTestScenario scenario;
  final Map<String, Object?> metadata;

  Map<String, Object?> toManifestJson() => <String, Object?>{
    'id': id,
    'scenario': scenario.toManifestJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

final class CockpitTestSuiteProgram {
  /// Composes a suite from [cases] and/or bare [scenarios].
  ///
  /// Each entry of [scenarios] becomes a case named after the scenario id,
  /// which keeps single-purpose suites to one id instead of three. Pass
  /// [cases] instead when a scenario needs a case-specific id or metadata.
  CockpitTestSuiteProgram({
    required String id,
    Iterable<CockpitTestCaseProgram> cases = const <CockpitTestCaseProgram>[],
    Iterable<CockpitTestScenario> scenarios = const <CockpitTestScenario>[],
    Iterable<CockpitLocaleProfile> locales = const <CockpitLocaleProfile>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : id = _validatedId(id),
       cases =
           List<CockpitTestCaseProgram>.unmodifiable(<CockpitTestCaseProgram>[
             ...cases,
             for (final scenario in scenarios)
               CockpitTestCaseProgram(id: scenario.id, scenario: scenario),
           ]),
       locales = List<CockpitLocaleProfile>.unmodifiable(locales),
       metadata = freezeCockpitJson(metadata, path: r'$.metadata') {
    if (this.cases.isEmpty) {
      throw ArgumentError.value(
        this.cases,
        'cases',
        'A suite needs at least one case or scenario.',
      );
    }
    _unique(this.cases.map((item) => item.id), 'case');
    _unique(this.locales.map((item) => item.toLanguageTag()), 'locale');
  }

  final String id;
  final List<CockpitTestCaseProgram> cases;
  final List<CockpitLocaleProfile> locales;
  final Map<String, Object?> metadata;

  Map<String, Object?> toManifestJson() => <String, Object?>{
    'id': id,
    'cases': cases.map((item) => item.toManifestJson()).toList(growable: false),
    if (locales.isNotEmpty)
      'locales': locales.map((item) => item.toJson()).toList(growable: false),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

String _validatedId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'id');
  return normalized;
}

void _unique(Iterable<String> values, String kind) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw ArgumentError('Duplicate $kind id: $value.');
  }
}
