import 'package:collection/collection.dart';

import '../model/cockpit_environment.dart';
import '../model/cockpit_observation.dart';
import '../model/cockpit_run_manifest.dart';
import '../model/cockpit_step_record.dart';

final class CockpitContextBundle {
  /// Creates a CockpitContextBundle.
  CockpitContextBundle({
    required this.manifest,
    required this.environment,
    List<CockpitStepRecord> steps = const [],
    List<CockpitObservation> observations = const [],
    required this.acceptanceMarkdown,
    required Map<String, Object?> handoff,
    Map<String, Object?> delivery = const <String, Object?>{},
  }) : steps = List.unmodifiable(steps),
       observations = List.unmodifiable(observations),
       handoff = Map.unmodifiable(handoff),
       delivery = Map.unmodifiable(delivery);

  final CockpitRunManifest manifest;
  final CockpitEnvironment environment;
  final List<CockpitStepRecord> steps;
  final List<CockpitObservation> observations;
  final String acceptanceMarkdown;
  final Map<String, Object?> handoff;
  final Map<String, Object?> delivery;

  static const ListEquality<CockpitStepRecord> _stepListEquality =
      ListEquality<CockpitStepRecord>();
  static const ListEquality<CockpitObservation> _observationListEquality =
      ListEquality<CockpitObservation>();
  static const DeepCollectionEquality _handoffEquality =
      DeepCollectionEquality();

  /// Encodes this CockpitContextBundle as a JSON object.
  Map<String, Object?> toJson() => {
    'manifest': manifest.toJson(),
    'environment': environment.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
    'observations': observations
        .map((observation) => observation.toJson())
        .toList(),
    'acceptanceMarkdown': acceptanceMarkdown,
    'handoff': handoff,
    'delivery': delivery,
  };

  /// Decodes a CockpitContextBundle from a JSON object.
  factory CockpitContextBundle.fromJson(Map<String, Object?> json) {
    final manifestJson = Map<String, Object?>.from(
      json['manifest']! as Map<Object?, Object?>,
    );
    final environmentJson = Map<String, Object?>.from(
      json['environment']! as Map<Object?, Object?>,
    );
    final stepJson = (json['steps'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<Object?, Object?>>();
    final observationJson =
        (json['observations'] as List<Object?>? ?? const <Object?>[])
            .cast<Map<Object?, Object?>>();

    return CockpitContextBundle(
      manifest: CockpitRunManifest.fromJson(manifestJson),
      environment: CockpitEnvironment.fromJson(environmentJson),
      steps: stepJson
          .map(
            (item) =>
                CockpitStepRecord.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(),
      observations: observationJson
          .map(
            (item) =>
                CockpitObservation.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(),
      acceptanceMarkdown: json['acceptanceMarkdown']! as String,
      handoff: Map<String, Object?>.from(
        (json['handoff'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
      delivery: Map<String, Object?>.from(
        (json['delivery'] as Map<Object?, Object?>?) ??
            const <Object?, Object?>{},
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitContextBundle &&
            other.manifest == manifest &&
            other.environment == environment &&
            _stepListEquality.equals(other.steps, steps) &&
            _observationListEquality.equals(other.observations, observations) &&
            other.acceptanceMarkdown == acceptanceMarkdown &&
            _handoffEquality.equals(other.handoff, handoff) &&
            _handoffEquality.equals(other.delivery, delivery);
  }

  @override
  int get hashCode => Object.hash(
    manifest,
    environment,
    _stepListEquality.hash(steps),
    _observationListEquality.hash(observations),
    acceptanceMarkdown,
    _handoffEquality.hash(handoff),
    _handoffEquality.hash(delivery),
  );
}
