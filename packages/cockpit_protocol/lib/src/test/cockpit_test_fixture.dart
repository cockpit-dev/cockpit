import 'cockpit_test_suite_source.dart';
import 'cockpit_test_value_reader.dart';

enum CockpitTestFixtureScope { suite, caseAttempt }

final class CockpitTestFixture {
  /// Creates a CockpitTestFixture.
  CockpitTestFixture({
    required this.id,
    required this.setup,
    this.teardown,
    this.scope = CockpitTestFixtureScope.caseAttempt,
    this.targetId,
    Map<String, Object?> inputs = const <String, Object?>{},
    Iterable<String> dependsOn = const <String>[],
  }) : inputs = Map<String, Object?>.unmodifiable(
         CockpitTestValueReader.object(
           CockpitTestValueReader.jsonValue(inputs, r'$.inputs'),
           r'$.inputs',
         ),
       ),
       dependsOn = List<String>.unmodifiable(dependsOn) {
    CockpitTestValueReader.string(id, r'$.id', id: true);
    if (targetId != null) {
      CockpitTestValueReader.string(targetId, r'$.targetId', id: true);
    }
    final dependencies = <String>{};
    for (var index = 0; index < this.dependsOn.length; index += 1) {
      final dependency = this.dependsOn[index];
      CockpitTestValueReader.string(
        dependency,
        '\$.dependsOn[$index]',
        id: true,
      );
      if (dependency == id || !dependencies.add(dependency)) {
        throw FormatException(
          'Invalid fixture dependency at \$.dependsOn[$index].',
        );
      }
    }
  }

  final String id;
  final CockpitTestSuiteCaseSource setup;
  final CockpitTestSuiteCaseSource? teardown;
  final CockpitTestFixtureScope scope;
  final String? targetId;
  final Map<String, Object?> inputs;
  final List<String> dependsOn;

  /// Encodes this CockpitTestFixture as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'setup': setup.toJson(),
    if (teardown != null) 'teardown': teardown!.toJson(),
    'scope': scope.name,
    if (targetId != null) 'targetId': targetId,
    if (inputs.isNotEmpty) 'inputs': inputs,
    if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
  };

  /// Decodes a CockpitTestFixture from a JSON object.
  factory CockpitTestFixture.fromJson(Object? value, {required String path}) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'id',
        'setup',
        'teardown',
        'scope',
        'targetId',
        'inputs',
        'dependsOn',
      },
      path,
      required: const <String>{'id', 'setup'},
    );
    return CockpitTestFixture(
      id: CockpitTestValueReader.string(json['id'], '$path.id', id: true),
      setup: CockpitTestSuiteCaseSource.fromJson(
        json['setup'],
        path: '$path.setup',
      ),
      teardown: json['teardown'] == null
          ? null
          : CockpitTestSuiteCaseSource.fromJson(
              json['teardown'],
              path: '$path.teardown',
            ),
      scope: json['scope'] == null
          ? CockpitTestFixtureScope.caseAttempt
          : CockpitTestValueReader.enumeration(
              json['scope'],
              CockpitTestFixtureScope.values,
              '$path.scope',
            ),
      targetId: CockpitTestValueReader.optionalString(
        json['targetId'],
        '$path.targetId',
        id: true,
      ),
      inputs: json['inputs'] == null
          ? const <String, Object?>{}
          : CockpitTestValueReader.object(
              CockpitTestValueReader.jsonValue(json['inputs'], '$path.inputs'),
              '$path.inputs',
            ),
      dependsOn: json['dependsOn'] == null
          ? const <String>[]
          : CockpitTestValueReader.strings(
              json['dependsOn'],
              '$path.dependsOn',
              id: true,
              unique: true,
            ),
    );
  }
}
