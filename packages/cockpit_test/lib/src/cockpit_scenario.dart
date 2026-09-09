import 'cockpit_tester.dart';

typedef CockpitTestScenarioBody = Future<void> Function(CockpitTester tester);

final class CockpitTestScenario {
  CockpitTestScenario({
    required this.id,
    required this.body,
    Iterable<String> requiredCapabilities = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : requiredCapabilities = Set.unmodifiable(
         requiredCapabilities.map(_validateId),
       ),
       metadata = Map.unmodifiable(metadata) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
  }

  final String id;
  final CockpitTestScenarioBody body;
  final Set<String> requiredCapabilities;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'requiredCapabilities': requiredCapabilities.toList(growable: false),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

String _validateId(String value) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, 'capability');
  return value;
}
