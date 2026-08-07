import 'cockpit_test_suite_policy.dart';
import 'cockpit_test_suite_source.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestSuiteEntry {
  /// Creates a CockpitTestSuiteEntry.
  CockpitTestSuiteEntry({
    required this.id,
    required this.source,
    Iterable<String> dependsOn = const <String>[],
    Iterable<String> fixtures = const <String>[],
    Iterable<String> matrixAxes = const <String>[],
    Iterable<String> targetIds = const <String>[],
    Map<String, Object?> inputs = const <String, Object?>{},
    this.retry,
    Iterable<String> tags = const <String>[],
  }) : dependsOn = _ids(dependsOn, r'$.dependsOn'),
       fixtures = _ids(fixtures, r'$.fixtures'),
       matrixAxes = _ids(matrixAxes, r'$.matrixAxes'),
       targetIds = _ids(targetIds, r'$.targetIds'),
       inputs = Map<String, Object?>.unmodifiable(
         CockpitTestValueReader.object(
           CockpitTestValueReader.jsonValue(inputs, r'$.inputs'),
           r'$.inputs',
         ),
       ),
       tags = Set<String>.unmodifiable(tags) {
    CockpitTestValueReader.string(id, r'$.id', id: true);
    for (final tag in this.tags) {
      CockpitTestValueReader.string(tag, r'$.tags');
    }
  }

  final String id;
  final CockpitTestSuiteCaseSource source;
  final List<String> dependsOn;
  final List<String> fixtures;
  final List<String> matrixAxes;
  final List<String> targetIds;
  final Map<String, Object?> inputs;
  final CockpitTestSuiteRetryPolicy? retry;
  final Set<String> tags;

  /// Encodes this CockpitTestSuiteEntry as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source': source.toJson(),
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
    if (fixtures.isNotEmpty) 'fixtures': fixtures,
    if (matrixAxes.isNotEmpty) 'matrixAxes': matrixAxes,
    if (targetIds.isNotEmpty) 'targetIds': targetIds,
    if (inputs.isNotEmpty) 'inputs': inputs,
    if (retry != null) 'retry': retry!.toJson(),
    if (tags.isNotEmpty) 'tags': tags.toList(growable: false),
  };

  /// Decodes a CockpitTestSuiteEntry from a JSON object.
  factory CockpitTestSuiteEntry.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'id',
        'source',
        'dependsOn',
        'fixtures',
        'matrixAxes',
        'targetIds',
        'inputs',
        'retry',
        'tags',
      },
      path,
      required: const <String>{'id', 'source'},
    );
    return CockpitTestSuiteEntry(
      id: CockpitTestValueReader.string(json['id'], '$path.id', id: true),
      source: CockpitTestSuiteCaseSource.fromJson(
        json['source'],
        path: '$path.source',
      ),
      dependsOn: _optionalIds(json['dependsOn'], '$path.dependsOn'),
      fixtures: _optionalIds(json['fixtures'], '$path.fixtures'),
      matrixAxes: _optionalIds(json['matrixAxes'], '$path.matrixAxes'),
      targetIds: _optionalIds(json['targetIds'], '$path.targetIds'),
      inputs: json['inputs'] == null
          ? const <String, Object?>{}
          : CockpitTestValueReader.object(
              CockpitTestValueReader.jsonValue(json['inputs'], '$path.inputs'),
              '$path.inputs',
            ),
      retry: json['retry'] == null
          ? null
          : CockpitTestSuiteRetryPolicy.fromJson(
              json['retry'],
              path: '$path.retry',
            ),
      tags: json['tags'] == null
          ? const <String>[]
          : CockpitTestValueReader.strings(
              json['tags'],
              '$path.tags',
              unique: true,
            ),
    );
  }
}

List<String> _optionalIds(Object? value, String path) => value == null
    ? const <String>[]
    : CockpitTestValueReader.strings(value, path, id: true, unique: true);

List<String> _ids(Iterable<String> source, String path) {
  final result = <String>[];
  final seen = <String>{};
  var index = 0;
  for (final value in source) {
    CockpitTestValueReader.string(value, '$path[$index]', id: true);
    if (!seen.add(value)) {
      throw FormatException('Duplicate identifier at $path[$index].');
    }
    result.add(value);
    index += 1;
  }
  return List<String>.unmodifiable(result);
}
