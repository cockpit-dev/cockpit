import 'cockpit_test_document.dart';
import 'cockpit_test_policy.dart';
import 'cockpit_test_suite_policy.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestProjectTarget {
  /// Creates a CockpitTestProjectTarget.
  CockpitTestProjectTarget({
    required this.requirements,
    Iterable<String> deviceIds = const <String>[],
    Map<String, String> labels = const <String, String>{},
  }) : deviceIds = List<String>.unmodifiable(deviceIds),
       labels = Map<String, String>.unmodifiable(labels) {
    for (var index = 0; index < this.deviceIds.length; index += 1) {
      CockpitTestValueReader.string(
        this.deviceIds[index],
        '\$.deviceIds[$index]',
      );
    }
    for (final entry in this.labels.entries) {
      CockpitTestValueReader.string(entry.key, r'$.labels', id: true);
      CockpitTestValueReader.string(entry.value, '\$.labels.${entry.key}');
    }
  }

  final CockpitTestTargetRequirements requirements;
  final List<String> deviceIds;
  final Map<String, String> labels;

  /// Encodes this CockpitTestProjectTarget as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'requirements': requirements.toJson(),
    if (deviceIds.isNotEmpty) 'deviceIds': deviceIds,
    if (labels.isNotEmpty) 'labels': labels,
  };

  /// Decodes a CockpitTestProjectTarget from a JSON object.
  factory CockpitTestProjectTarget.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'requirements', 'deviceIds', 'labels'},
      path,
      required: const <String>{'requirements'},
    );
    final labels = json['labels'] == null
        ? const <String, Object?>{}
        : CockpitTestValueReader.object(json['labels'], '$path.labels');
    return CockpitTestProjectTarget(
      requirements: CockpitTestTargetRequirements.fromJson(
        json['requirements'],
        path: '$path.requirements',
      ),
      deviceIds: json['deviceIds'] == null
          ? const <String>[]
          : CockpitTestValueReader.strings(
              json['deviceIds'],
              '$path.deviceIds',
              unique: true,
            ),
      labels: <String, String>{
        for (final entry in labels.entries)
          entry.key: CockpitTestValueReader.string(
            entry.value,
            '$path.labels.${entry.key}',
          ),
      },
    );
  }
}

final class CockpitTestProject implements CockpitTestDocument {
  /// Creates a CockpitTestProject.
  CockpitTestProject({
    this.schemaVersion = 'cockpit.test/v2',
    this.kind = 'project',
    required this.id,
    this.name,
    this.description,
    required Iterable<String> suiteSources,
    Map<String, CockpitTestProjectTarget> targets =
        const <String, CockpitTestProjectTarget>{},
    Iterable<String> allowedSecretProviders = const <String>[],
    CockpitTestSuiteExecutionPolicy? executionDefaults,
    CockpitTestSuiteReportPolicy? reportDefaults,
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : suiteSources = List<String>.unmodifiable(suiteSources),
       targets = Map<String, CockpitTestProjectTarget>.unmodifiable(targets),
       allowedSecretProviders = Set<String>.unmodifiable(
         allowedSecretProviders,
       ),
       executionDefaults =
           executionDefaults ?? CockpitTestSuiteExecutionPolicy.standard,
       reportDefaults = reportDefaults ?? CockpitTestSuiteReportPolicy.standard,
       extensions = CockpitTestValueReader.extensions(
         extensions,
         r'$.extensions',
       ) {
    if (schemaVersion != 'cockpit.test/v2' || kind != 'project') {
      throw const FormatException(
        'Expected a cockpit.test/v2 project document.',
      );
    }
    CockpitTestValueReader.string(id, r'$.id', id: true);
    if (name != null) CockpitTestValueReader.string(name, r'$.name');
    if (description != null) {
      CockpitTestValueReader.string(description, r'$.description');
    }
    if (this.suiteSources.isEmpty || this.suiteSources.length > 10000) {
      throw const FormatException(
        'A project requires 1 to 10000 suite sources.',
      );
    }
    final sources = <String>{};
    for (var index = 0; index < this.suiteSources.length; index += 1) {
      final source = _relativePath(
        this.suiteSources[index],
        '\$.suiteSources[$index]',
      );
      if (!sources.add(source)) {
        throw FormatException(
          'Duplicate suite source at \$.suiteSources[$index].',
        );
      }
    }
    for (final targetId in this.targets.keys) {
      CockpitTestValueReader.string(targetId, r'$.targets', id: true);
    }
    for (final provider in this.allowedSecretProviders) {
      CockpitTestValueReader.string(
        provider,
        r'$.allowedSecretProviders',
        id: true,
      );
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
  final List<String> suiteSources;
  final Map<String, CockpitTestProjectTarget> targets;
  final Set<String> allowedSecretProviders;
  final CockpitTestSuiteExecutionPolicy executionDefaults;
  final CockpitTestSuiteReportPolicy reportDefaults;
  final Map<String, Object?> extensions;

  /// Encodes this CockpitTestProject as a JSON object.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind,
    'id': id,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    'suiteSources': suiteSources,
    if (targets.isNotEmpty)
      'targets': <String, Object?>{
        for (final entry in targets.entries) entry.key: entry.value.toJson(),
      },
    if (allowedSecretProviders.isNotEmpty)
      'allowedSecretProviders': allowedSecretProviders.toList(growable: false),
    'executionDefaults': executionDefaults.toJson(),
    'reportDefaults': reportDefaults.toJson(),
    ...extensions,
  };

  /// Decodes a CockpitTestProject from a JSON object.
  factory CockpitTestProject.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'schemaVersion',
        'kind',
        'id',
        'name',
        'description',
        'suiteSources',
        'targets',
        'allowedSecretProviders',
        'executionDefaults',
        'reportDefaults',
      },
      path,
      required: const <String>{'schemaVersion', 'kind', 'id', 'suiteSources'},
      allowExtensions: true,
    );
    final rawTargets = json['targets'] == null
        ? const <String, Object?>{}
        : CockpitTestValueReader.object(json['targets'], '$path.targets');
    return CockpitTestProject(
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
      suiteSources: CockpitTestValueReader.strings(
        json['suiteSources'],
        '$path.suiteSources',
        unique: true,
      ),
      targets: <String, CockpitTestProjectTarget>{
        for (final entry in rawTargets.entries)
          entry.key: CockpitTestProjectTarget.fromJson(
            entry.value,
            path: '$path.targets.${entry.key}',
          ),
      },
      allowedSecretProviders: json['allowedSecretProviders'] == null
          ? const <String>[]
          : CockpitTestValueReader.strings(
              json['allowedSecretProviders'],
              '$path.allowedSecretProviders',
              id: true,
              unique: true,
            ),
      executionDefaults: json['executionDefaults'] == null
          ? null
          : CockpitTestSuiteExecutionPolicy.fromJson(
              json['executionDefaults'],
              path: '$path.executionDefaults',
            ),
      reportDefaults: json['reportDefaults'] == null
          ? null
          : CockpitTestSuiteReportPolicy.fromJson(
              json['reportDefaults'],
              path: '$path.reportDefaults',
            ),
      extensions: <String, Object?>{
        for (final entry in json.entries)
          if (entry.key.startsWith('x-')) entry.key: entry.value,
      },
    );
  }
}

String _relativePath(Object? value, String path) {
  final source = CockpitTestValueReader.string(value, path, maximum: 4096);
  if (source.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source) ||
      source.split(RegExp(r'[\\/]')).any((segment) => segment == '..')) {
    throw FormatException('Expected a confined relative path at $path.');
  }
  return source;
}
