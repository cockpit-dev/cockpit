import 'cockpit_test_policy.dart';
import 'cockpit_test_step.dart';
import 'cockpit_test_document.dart';
import 'cockpit_test_value_reader.dart';
import 'cockpit_test_variable.dart';

final class CockpitTestCase implements CockpitTestDocument {
  /// Creates a CockpitTestCase.
  CockpitTestCase({
    this.schemaVersion = 'cockpit.test/v2',
    this.kind = 'case',
    required this.id,
    this.name,
    this.description,
    Iterable<String> tags = const <String>[],
    required this.target,
    this.defaults = CockpitTestCaseDefaults.standard,
    Map<String, CockpitTestVariableDeclaration> variables =
        const <String, CockpitTestVariableDeclaration>{},
    Map<String, List<CockpitTestStepTemplate>> fragments =
        const <String, List<CockpitTestStepTemplate>>{},
    Iterable<CockpitTestStepTemplate> setup = const <CockpitTestStepTemplate>[],
    required Iterable<CockpitTestStepTemplate> steps,
    Iterable<CockpitTestStepTemplate> finallySteps =
        const <CockpitTestStepTemplate>[],
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : tags = Set<String>.unmodifiable(tags),
       variables = Map<String, CockpitTestVariableDeclaration>.unmodifiable(
         variables,
       ),
       fragments = Map<String, List<CockpitTestStepTemplate>>.unmodifiable(
         <String, List<CockpitTestStepTemplate>>{
           for (final entry in fragments.entries)
             entry.key: List<CockpitTestStepTemplate>.unmodifiable(entry.value),
         },
       ),
       setup = List<CockpitTestStepTemplate>.unmodifiable(setup),
       steps = List<CockpitTestStepTemplate>.unmodifiable(steps),
       finallySteps = List<CockpitTestStepTemplate>.unmodifiable(finallySteps),
       extensions = CockpitTestValueReader.extensions(
         extensions,
         r'$.extensions',
       ) {
    if (schemaVersion != 'cockpit.test/v2') {
      throw const FormatException(
        'schemaVersion must be exactly cockpit.test/v2.',
      );
    }
    if (kind != 'case') {
      throw const FormatException(
        'Only kind case is supported by this runtime.',
      );
    }
    CockpitTestValueReader.string(id, r'$.id', id: true);
    if (name != null) {
      CockpitTestValueReader.string(name, r'$.name');
    }
    if (description != null) {
      CockpitTestValueReader.string(description, r'$.description');
    }
    for (final tag in this.tags) {
      CockpitTestValueReader.string(tag, r'$.tags');
    }
    for (final name in this.variables.keys) {
      CockpitTestValueReader.string(name, r'$.variables', id: true);
    }
    if (this.steps.isEmpty) {
      throw const FormatException('A case requires at least one main step.');
    }
    for (final fragment in this.fragments.entries) {
      CockpitTestValueReader.string(fragment.key, r'$.fragments', id: true);
      if (fragment.value.isEmpty) {
        throw FormatException('Fragment ${fragment.key} cannot be empty.');
      }
    }
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
  final CockpitTestTargetRequirements target;
  final CockpitTestCaseDefaults defaults;
  final Map<String, CockpitTestVariableDeclaration> variables;
  final Map<String, List<CockpitTestStepTemplate>> fragments;
  final List<CockpitTestStepTemplate> setup;
  final List<CockpitTestStepTemplate> steps;
  final List<CockpitTestStepTemplate> finallySteps;
  final Map<String, Object?> extensions;

  /// Encodes this CockpitTestCase as a JSON object.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind,
    'id': id,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (tags.isNotEmpty) 'tags': tags.toList(growable: false),
    'target': target.toJson(),
    'defaults': defaults.toJson(),
    if (variables.isNotEmpty)
      'variables': <String, Object?>{
        for (final entry in variables.entries) entry.key: entry.value.toJson(),
      },
    if (fragments.isNotEmpty)
      'fragments': <String, Object?>{
        for (final entry in fragments.entries)
          entry.key: entry.value.map((step) => step.toJson()).toList(),
      },
    if (setup.isNotEmpty) 'setup': setup.map((step) => step.toJson()).toList(),
    'steps': steps.map((step) => step.toJson()).toList(),
    if (finallySteps.isNotEmpty)
      'finally': finallySteps.map((step) => step.toJson()).toList(),
    ...extensions,
  };

  /// Decodes a CockpitTestCase from a JSON object.
  factory CockpitTestCase.fromJson(Object? value, {String path = r'$'}) {
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
        'target',
        'defaults',
        'variables',
        'fragments',
        'setup',
        'steps',
        'finally',
      },
      path,
      required: const <String>{
        'schemaVersion',
        'kind',
        'id',
        'target',
        'steps',
      },
      allowExtensions: true,
    );
    final rawTags = json['tags'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(json['tags'], '$path.tags');
    final tags = <String>{};
    for (var index = 0; index < rawTags.length; index += 1) {
      final tag = CockpitTestValueReader.string(
        rawTags[index],
        '$path.tags[$index]',
      );
      if (!tags.add(tag)) {
        throw FormatException('Duplicate tag at $path.tags[$index].');
      }
    }
    return CockpitTestCase(
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
      tags: tags,
      target: CockpitTestTargetRequirements.fromJson(
        json['target'],
        path: '$path.target',
      ),
      defaults: json['defaults'] == null
          ? CockpitTestCaseDefaults.standard
          : CockpitTestCaseDefaults.fromJson(
              json['defaults'],
              path: '$path.defaults',
            ),
      variables: _readVariables(json['variables'], '$path.variables'),
      fragments: _readFragments(json['fragments'], '$path.fragments'),
      setup: _readSteps(json['setup'], '$path.setup', allowAbsent: true),
      steps: _readSteps(json['steps'], '$path.steps'),
      finallySteps: _readSteps(
        json['finally'],
        '$path.finally',
        allowAbsent: true,
      ),
      extensions: <String, Object?>{
        for (final entry in json.entries)
          if (entry.key.startsWith('x-'))
            entry.key: CockpitTestValueReader.jsonValue(
              entry.value,
              '$path.${entry.key}',
            ),
      },
    );
  }
}

Map<String, CockpitTestVariableDeclaration> _readVariables(
  Object? value,
  String path,
) {
  if (value == null) {
    return const <String, CockpitTestVariableDeclaration>{};
  }
  final json = CockpitTestValueReader.object(value, path);
  return Map<String, CockpitTestVariableDeclaration>.unmodifiable(
    <String, CockpitTestVariableDeclaration>{
      for (final entry in json.entries)
        CockpitTestValueReader.string(
          entry.key,
          path,
          id: true,
        ): CockpitTestVariableDeclaration.fromJson(
          entry.value,
          path: '$path.${entry.key}',
        ),
    },
  );
}

Map<String, List<CockpitTestStepTemplate>> _readFragments(
  Object? value,
  String path,
) {
  if (value == null) {
    return const <String, List<CockpitTestStepTemplate>>{};
  }
  final json = CockpitTestValueReader.object(value, path);
  return Map<String, List<CockpitTestStepTemplate>>.unmodifiable(
    <String, List<CockpitTestStepTemplate>>{
      for (final entry in json.entries)
        CockpitTestValueReader.string(entry.key, path, id: true): _readSteps(
          entry.value,
          '$path.${entry.key}',
        ),
    },
  );
}

List<CockpitTestStepTemplate> _readSteps(
  Object? value,
  String path, {
  bool allowAbsent = false,
}) {
  if (value == null && allowAbsent) {
    return const <CockpitTestStepTemplate>[];
  }
  final raw = CockpitTestValueReader.list(value, path);
  return List<CockpitTestStepTemplate>.unmodifiable(<CockpitTestStepTemplate>[
    for (var index = 0; index < raw.length; index += 1)
      CockpitTestStepTemplate.fromJson(raw[index], path: '$path[$index]'),
  ]);
}
