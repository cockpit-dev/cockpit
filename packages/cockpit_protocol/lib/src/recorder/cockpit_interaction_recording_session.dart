import 'package:collection/collection.dart';

import '../foundation/cockpit_foundation_value_reader.dart';
import 'cockpit_interaction_step.dart';
import 'cockpit_recorder_phase.dart';

final class CockpitInteractionRecordingSession {
  /// Creates a CockpitInteractionRecordingSession.
  CockpitInteractionRecordingSession({
    required this.sessionId,
    required this.phase,
    required this.startedAt,
    this.pausedAt,
    this.endedAt,
    this.stepCount = 0,
    this.unresolvedCount = 0,
  }) {
    if (stepCount < 0) {
      throw ArgumentError.value(
        stepCount,
        'stepCount',
        'Must not be negative.',
      );
    }
    if (unresolvedCount < 0) {
      throw ArgumentError.value(
        unresolvedCount,
        'unresolvedCount',
        'Must not be negative.',
      );
    }
    if (unresolvedCount > stepCount) {
      throw ArgumentError.value(
        unresolvedCount,
        'unresolvedCount',
        'Must not exceed stepCount ($stepCount).',
      );
    }
  }

  final String sessionId;
  final CockpitRecorderPhase phase;
  final DateTime startedAt;
  final DateTime? pausedAt;
  final DateTime? endedAt;
  final int stepCount;
  final int unresolvedCount;

  /// Encodes this CockpitInteractionRecordingSession as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'phase': phase.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (pausedAt != null) 'pausedAt': pausedAt!.toUtc().toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    'stepCount': stepCount,
    'unresolvedCount': unresolvedCount,
  };

  /// Decodes a CockpitInteractionRecordingSession from a JSON object.
  factory CockpitInteractionRecordingSession.fromJson(
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

    return CockpitInteractionRecordingSession(
      sessionId: CockpitFoundationValueReader.string(
        required('sessionId'),
        '$path.sessionId',
      ),
      phase: CockpitRecorderPhase.fromJson(
        required('phase'),
        path: '$path.phase',
      ),
      startedAt: CockpitFoundationValueReader.dateTime(
        required('startedAt'),
        '$path.startedAt',
      ),
      pausedAt: json['pausedAt'] == null
          ? null
          : CockpitFoundationValueReader.dateTime(
              json['pausedAt'],
              '$path.pausedAt',
            ),
      endedAt: json['endedAt'] == null
          ? null
          : CockpitFoundationValueReader.dateTime(
              json['endedAt'],
              '$path.endedAt',
            ),
      stepCount: CockpitFoundationValueReader.integer(
        required('stepCount'),
        '$path.stepCount',
        min: 0,
      ),
      unresolvedCount: CockpitFoundationValueReader.integer(
        required('unresolvedCount'),
        '$path.unresolvedCount',
        min: 0,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitInteractionRecordingSession &&
            other.sessionId == sessionId &&
            other.phase == phase &&
            other.startedAt == startedAt &&
            other.pausedAt == pausedAt &&
            other.endedAt == endedAt &&
            other.stepCount == stepCount &&
            other.unresolvedCount == unresolvedCount;
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    phase,
    startedAt,
    pausedAt,
    endedAt,
    stepCount,
    unresolvedCount,
  );
}

final class CockpitInteractionRecordingRequest {
  /// Creates a CockpitInteractionRecordingRequest.
  const CockpitInteractionRecordingRequest({this.name, this.attachToStep});

  final String? name;

  /// Step id a recording session attaches to, mirroring
  /// `CockpitRecordingRequest.attachToStep`.
  final String? attachToStep;

  /// Encodes this CockpitInteractionRecordingRequest as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (name != null) 'name': name,
    if (attachToStep != null) 'attachToStep': attachToStep,
  };

  /// Decodes a CockpitInteractionRecordingRequest from a JSON object.
  factory CockpitInteractionRecordingRequest.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('Expected an object at $path.');
    }
    final json = Map<String, Object?>.from(value);
    return CockpitInteractionRecordingRequest(
      name: json['name'] == null
          ? null
          : CockpitFoundationValueReader.boundedString(
              json['name'],
              '$path.name',
            ),
      attachToStep: json['attachToStep'] == null
          ? null
          : CockpitFoundationValueReader.boundedString(
              json['attachToStep'],
              '$path.attachToStep',
            ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitInteractionRecordingRequest &&
            other.name == name &&
            other.attachToStep == attachToStep;
  }

  @override
  int get hashCode => Object.hash(name, attachToStep);
}

final class CockpitInteractionRecordingResult {
  /// Creates a CockpitInteractionRecordingResult.
  CockpitInteractionRecordingResult({
    required this.session,
    Iterable<CockpitInteractionStep> steps = const <CockpitInteractionStep>[],
  }) : steps = List<CockpitInteractionStep>.unmodifiable(steps);

  final CockpitInteractionRecordingSession session;
  final List<CockpitInteractionStep> steps;

  static const ListEquality<CockpitInteractionStep> _stepEquality =
      ListEquality<CockpitInteractionStep>();

  /// Encodes this CockpitInteractionRecordingResult as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'session': session.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  /// Decodes a CockpitInteractionRecordingResult from a JSON object.
  factory CockpitInteractionRecordingResult.fromJson(
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

    final rawSteps = CockpitFoundationValueReader.list(
      required('steps'),
      '$path.steps',
    );
    return CockpitInteractionRecordingResult(
      session: CockpitInteractionRecordingSession.fromJson(
        required('session'),
        path: '$path.session',
      ),
      steps: <CockpitInteractionStep>[
        for (var index = 0; index < rawSteps.length; index += 1)
          CockpitInteractionStep.fromJson(
            rawSteps[index],
            path: '$path.steps[$index]',
          ),
      ],
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitInteractionRecordingResult &&
            other.session == session &&
            _stepEquality.equals(other.steps, steps);
  }

  @override
  int get hashCode => Object.hash(session, _stepEquality.hash(steps));
}
