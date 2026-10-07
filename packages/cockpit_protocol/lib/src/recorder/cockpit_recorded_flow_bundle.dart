import 'package:collection/collection.dart';

import '../foundation/cockpit_foundation_value_reader.dart';
import 'cockpit_interaction_recording_session.dart';
import 'cockpit_interaction_step.dart';

final class CockpitRecordedFlowBundle {
  /// Creates a CockpitRecordedFlowBundle.
  CockpitRecordedFlowBundle({
    required this.session,
    Iterable<CockpitInteractionStep> steps = const <CockpitInteractionStep>[],
    required Map<String, Object?> caseDocument,
    required this.caseYaml,
  }) : steps = List<CockpitInteractionStep>.unmodifiable(steps),
       caseDocument = Map<String, Object?>.unmodifiable(caseDocument) {
    if (caseDocument.isEmpty) {
      throw ArgumentError.value(
        caseDocument,
        'caseDocument',
        'Case document is empty.',
      );
    }
    if (caseYaml.isEmpty) {
      throw ArgumentError.value(caseYaml, 'caseYaml', 'Case YAML is empty.');
    }
  }

  final CockpitInteractionRecordingSession session;
  final List<CockpitInteractionStep> steps;

  /// Case document (`CockpitTestCase.toJson` output) carried alongside its
  /// YAML rendering.
  final Map<String, Object?> caseDocument;
  final String caseYaml;

  static const ListEquality<CockpitInteractionStep> _stepEquality =
      ListEquality<CockpitInteractionStep>();
  static const MapEquality<String, Object?> _documentEquality =
      MapEquality<String, Object?>();

  /// Encodes this CockpitRecordedFlowBundle as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'session': session.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
    'caseDocument': caseDocument,
    'caseYaml': caseYaml,
  };

  /// Decodes a CockpitRecordedFlowBundle from a JSON object.
  factory CockpitRecordedFlowBundle.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected an object at $path.');
    }
    final json = Map<String, Object?>.from(value);
    Object? required(String field) {
      if (!json.containsKey(field)) {
        throw FormatException('Missing required field $path.$field.');
      }
      return json[field];
    }

    final session = CockpitInteractionRecordingSession.fromJson(
      required('session'),
      path: '$path.session',
    );
    final rawSteps = CockpitFoundationValueReader.list(
      required('steps'),
      '$path.steps',
    );
    final document = required('caseDocument');
    if (document is! Map<Object?, Object?>) {
      throw FormatException('Expected an object at $path.caseDocument.');
    }
    return CockpitRecordedFlowBundle(
      session: session,
      steps: <CockpitInteractionStep>[
        for (var index = 0; index < rawSteps.length; index += 1)
          CockpitInteractionStep.fromJson(
            rawSteps[index],
            path: '$path.steps[$index]',
          ),
      ],
      caseDocument: Map<String, Object?>.from(document),
      caseYaml: CockpitFoundationValueReader.string(
        required('caseYaml'),
        '$path.caseYaml',
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitRecordedFlowBundle &&
            other.session == session &&
            _stepEquality.equals(other.steps, steps) &&
            _documentEquality.equals(other.caseDocument, caseDocument) &&
            other.caseYaml == caseYaml;
  }

  @override
  int get hashCode => Object.hash(
    session,
    _stepEquality.hash(steps),
    _documentEquality.hash(caseDocument),
    caseYaml,
  );
}
