import 'cockpit_json.dart';
import 'cockpit_requirements.dart';
import 'cockpit_tester.dart';

typedef CockpitTestScenarioBody = Future<void> Function(CockpitTester tester);

final class CockpitTestScenario {
  CockpitTestScenario({
    required String id,
    required this.body,
    CockpitTestRequirements? requirements,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : id = _validatedId(id),
       requirements = requirements ?? CockpitTestRequirements(),
       metadata = freezeCockpitJson(metadata, path: r'$.metadata');

  final String id;
  final CockpitTestScenarioBody body;
  final CockpitTestRequirements requirements;
  final Map<String, Object?> metadata;

  Map<String, Object?> toManifestJson() => <String, Object?>{
    'id': id,
    if (!requirements.isEmpty) 'requirements': requirements.toManifestJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

String _validatedId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'id');
  return normalized;
}
