import 'cockpit_locale.dart';
import 'cockpit_scenario.dart';

final class CockpitTestCaseProgram {
  CockpitTestCaseProgram({
    required this.id,
    required this.scenario,
    Map<String, Object?> targetOverrides = const <String, Object?>{},
  }) : targetOverrides = Map.unmodifiable(targetOverrides) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
  }

  final String id;
  final CockpitTestScenario scenario;
  final Map<String, Object?> targetOverrides;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'scenario': scenario.toJson(),
    if (targetOverrides.isNotEmpty) 'targetOverrides': targetOverrides,
  };
}

final class CockpitTestSuiteProgram {
  CockpitTestSuiteProgram({
    required this.id,
    required Iterable<CockpitTestCaseProgram> cases,
    Iterable<CockpitLocaleProfile> locales = const <CockpitLocaleProfile>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : cases = List.unmodifiable(cases),
       locales = List.unmodifiable(locales),
       metadata = Map.unmodifiable(metadata) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    _unique(this.cases.map((item) => item.id), 'case');
    _unique(this.locales.map((item) => item.toLanguageTag()), 'locale');
  }

  final String id;
  final List<CockpitTestCaseProgram> cases;
  final List<CockpitLocaleProfile> locales;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'cases': cases.map((item) => item.toJson()).toList(growable: false),
    if (locales.isNotEmpty)
      'locales': locales.map((item) => item.toJson()).toList(growable: false),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

void _unique(Iterable<String> values, String kind) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw ArgumentError('Duplicate $kind id: $value.');
  }
}
