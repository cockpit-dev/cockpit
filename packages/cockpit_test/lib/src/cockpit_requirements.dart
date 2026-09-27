import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_test_feature.dart';

final class CockpitTestRequirements {
  CockpitTestRequirements({
    Iterable<CockpitCommandType> commands = const <CockpitCommandType>[],
    Iterable<CockpitLocatorKind> locators = const <CockpitLocatorKind>[],
    Iterable<CockpitTestFeature> features = const <CockpitTestFeature>[],
  }) : commands = Set<CockpitCommandType>.unmodifiable(commands),
       locators = Set<CockpitLocatorKind>.unmodifiable(locators),
       features = Set<CockpitTestFeature>.unmodifiable(features);

  final Set<CockpitCommandType> commands;
  final Set<CockpitLocatorKind> locators;
  final Set<CockpitTestFeature> features;

  bool get isEmpty => commands.isEmpty && locators.isEmpty && features.isEmpty;

  Map<String, Object?> toManifestJson() => <String, Object?>{
    if (commands.isNotEmpty)
      'commands': _sortedNames(commands.map((value) => value.name)),
    if (locators.isNotEmpty)
      'locators': _sortedNames(locators.map((value) => value.name)),
    if (features.isNotEmpty)
      'features': _sortedNames(features.map((value) => value.name)),
  };
}

List<String> _sortedNames(Iterable<String> values) {
  final result = values.toList(growable: false)..sort();
  return result;
}
