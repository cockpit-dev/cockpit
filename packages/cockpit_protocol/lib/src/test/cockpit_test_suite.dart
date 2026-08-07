import 'cockpit_test_document.dart';
import 'cockpit_test_fixture.dart';
import 'cockpit_test_matrix.dart';
import 'cockpit_test_suite_entry.dart';
import 'cockpit_test_suite_policy.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestSuite implements CockpitTestDocument {
  /// Creates a CockpitTestSuite.
  CockpitTestSuite({
    this.schemaVersion = 'cockpit.test/v2',
    this.kind = 'suite',
    required this.id,
    this.name,
    this.description,
    Iterable<String> tags = const <String>[],
    required Iterable<CockpitTestSuiteEntry> cases,
    Iterable<CockpitTestFixture> fixtures = const <CockpitTestFixture>[],
    CockpitTestMatrix? matrix,
    CockpitTestSuiteExecutionPolicy? execution,
    CockpitTestSuiteReportPolicy? report,
    Iterable<String> includeTags = const <String>[],
    Iterable<String> excludeTags = const <String>[],
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : tags = Set<String>.unmodifiable(tags),
       cases = List<CockpitTestSuiteEntry>.unmodifiable(cases),
       fixtures = List<CockpitTestFixture>.unmodifiable(fixtures),
       matrix = matrix ?? CockpitTestMatrix.empty,
       execution = execution ?? CockpitTestSuiteExecutionPolicy.standard,
       report = report ?? CockpitTestSuiteReportPolicy.standard,
       includeTags = Set<String>.unmodifiable(includeTags),
       excludeTags = Set<String>.unmodifiable(excludeTags),
       extensions = CockpitTestValueReader.extensions(
         extensions,
         r'$.extensions',
       ) {
    if (schemaVersion != 'cockpit.test/v2' || kind != 'suite') {
      throw const FormatException('Expected a cockpit.test/v2 suite document.');
    }
    CockpitTestValueReader.string(id, r'$.id', id: true);
    if (name != null) CockpitTestValueReader.string(name, r'$.name');
    if (description != null) {
      CockpitTestValueReader.string(description, r'$.description');
    }
    if (this.cases.isEmpty || this.cases.length > 10000) {
      throw const FormatException('A suite requires 1 to 10000 case entries.');
    }
    _validateTags(this.tags, r'$.tags');
    _validateTags(this.includeTags, r'$.includeTags');
    _validateTags(this.excludeTags, r'$.excludeTags');
    if (this.includeTags.intersection(this.excludeTags).isNotEmpty) {
      throw const FormatException('Suite tag filters conflict.');
    }
    _validateGraph();
  }

  @override
  final String schemaVersion;
  @override
  final String kind;
  @override
  final String id;
  @override
  final String? name;
  final String? description;
  final Set<String> tags;
  final List<CockpitTestSuiteEntry> cases;
  final List<CockpitTestFixture> fixtures;
  final CockpitTestMatrix matrix;
  final CockpitTestSuiteExecutionPolicy execution;
  final CockpitTestSuiteReportPolicy report;
  final Set<String> includeTags;
  final Set<String> excludeTags;
  final Map<String, Object?> extensions;

  /// Encodes this CockpitTestSuite as a JSON object.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind,
    'id': id,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (tags.isNotEmpty) 'tags': tags.toList(growable: false),
    'cases': cases.map((entry) => entry.toJson()).toList(),
    if (fixtures.isNotEmpty)
      'fixtures': fixtures.map((fixture) => fixture.toJson()).toList(),
    if (matrix.axes.isNotEmpty || matrix.include.isNotEmpty)
      'matrix': matrix.toJson(),
    'execution': execution.toJson(),
    'report': report.toJson(),
    if (includeTags.isNotEmpty)
      'includeTags': includeTags.toList(growable: false),
    if (excludeTags.isNotEmpty)
      'excludeTags': excludeTags.toList(growable: false),
    ...extensions,
  };

  /// Decodes a CockpitTestSuite from a JSON object.
  factory CockpitTestSuite.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'schemaVersion',
        'kind',
        'id',
        'name',
        'description',
        'tags',
        'cases',
        'fixtures',
        'matrix',
        'execution',
        'report',
        'includeTags',
        'excludeTags',
      },
      path,
      required: const <String>{'schemaVersion', 'kind', 'id', 'cases'},
      allowExtensions: true,
    );
    final rawCases = CockpitTestValueReader.list(json['cases'], '$path.cases');
    final rawFixtures = json['fixtures'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['fixtures'], '$path.fixtures');
    return CockpitTestSuite(
      schemaVersion: CockpitTestValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      kind: CockpitTestValueReader.string(json['kind'], '$path.kind'),
      id: CockpitTestValueReader.string(json['id'], '$path.id', id: true),
      name: CockpitTestValueReader.optionalString(json['name'], '$path.name'),
      description: CockpitTestValueReader.optionalString(
        json['description'],
        '$path.description',
      ),
      tags: _strings(json['tags'], '$path.tags'),
      cases: <CockpitTestSuiteEntry>[
        for (var index = 0; index < rawCases.length; index += 1)
          CockpitTestSuiteEntry.fromJson(
            rawCases[index],
            path: '$path.cases[$index]',
          ),
      ],
      fixtures: <CockpitTestFixture>[
        for (var index = 0; index < rawFixtures.length; index += 1)
          CockpitTestFixture.fromJson(
            rawFixtures[index],
            path: '$path.fixtures[$index]',
          ),
      ],
      matrix: json['matrix'] == null
          ? CockpitTestMatrix.empty
          : CockpitTestMatrix.fromJson(json['matrix'], path: '$path.matrix'),
      execution: json['execution'] == null
          ? CockpitTestSuiteExecutionPolicy.standard
          : CockpitTestSuiteExecutionPolicy.fromJson(
              json['execution'],
              path: '$path.execution',
            ),
      report: json['report'] == null
          ? CockpitTestSuiteReportPolicy.standard
          : CockpitTestSuiteReportPolicy.fromJson(
              json['report'],
              path: '$path.report',
            ),
      includeTags: _strings(json['includeTags'], '$path.includeTags'),
      excludeTags: _strings(json['excludeTags'], '$path.excludeTags'),
      extensions: <String, Object?>{
        for (final entry in json.entries)
          if (entry.key.startsWith('x-')) entry.key: entry.value,
      },
    );
  }

  void _validateGraph() {
    final entryIds = <String>{};
    for (final entry in cases) {
      if (!entryIds.add(entry.id)) {
        throw FormatException('Duplicate suite case entry ${entry.id}.');
      }
    }
    final fixtureIds = <String>{};
    for (final fixture in fixtures) {
      if (!fixtureIds.add(fixture.id)) {
        throw FormatException('Duplicate suite fixture ${fixture.id}.');
      }
    }
    for (final entry in cases) {
      if (entry.dependsOn.any((id) => !entryIds.contains(id)) ||
          entry.fixtures.any((id) => !fixtureIds.contains(id)) ||
          entry.matrixAxes.any((axis) => !matrix.axes.containsKey(axis))) {
        throw FormatException(
          'Suite case ${entry.id} has an unknown reference.',
        );
      }
    }
    for (final fixture in fixtures) {
      if (fixture.dependsOn.any((id) => !fixtureIds.contains(id))) {
        throw FormatException(
          'Suite fixture ${fixture.id} has an unknown dependency.',
        );
      }
    }
    _rejectCycles(<String, List<String>>{
      for (final entry in cases) entry.id: entry.dependsOn,
    }, 'case');
    _rejectCycles(<String, List<String>>{
      for (final fixture in fixtures) fixture.id: fixture.dependsOn,
    }, 'fixture');
  }
}

List<String> _strings(Object? value, String path) => value == null
    ? const <String>[]
    : CockpitTestValueReader.strings(value, path, unique: true);

void _validateTags(Iterable<String> values, String path) {
  for (final value in values) {
    CockpitTestValueReader.string(value, path);
  }
}

void _rejectCycles(Map<String, List<String>> graph, String kind) {
  final active = <String>{};
  final done = <String>{};
  bool visit(String id) {
    if (done.contains(id)) return false;
    if (!active.add(id)) return true;
    if (graph[id]!.any(visit)) return true;
    active.remove(id);
    done.add(id);
    return false;
  }

  if (graph.keys.any(visit)) {
    throw FormatException('Suite $kind dependency graph contains a cycle.');
  }
}
