import 'package:collection/collection.dart';

import '../foundation/cockpit_enum.dart';
import '../foundation/cockpit_foundation_value_reader.dart';
import 'cockpit_locator_candidate.dart';
import 'cockpit_recorder_phase.dart';

enum CockpitInteractionStepKind {
  tap,
  longPress,
  text,
  scroll,
  routeChange,
  back,
  marker,
  note;

  static CockpitInteractionStepKind fromJson(
    Object? json, {
    String path = r'$.kind',
  }) => cockpitEnumFromJson(json, values, path);
}

enum CockpitInteractionScrollDirection {
  up,
  down,
  left,
  right;

  static CockpitInteractionScrollDirection fromJson(
    Object? json, {
    String path = r'$.scrollDirection',
  }) => cockpitEnumFromJson(json, values, path);
}

double? _optionalDouble(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw FormatException('Expected a number at $path.');
  }
  return value.toDouble();
}

final class CockpitInteractionStep {
  /// Creates a CockpitInteractionStep.
  CockpitInteractionStep({
    required this.stepId,
    required this.kind,
    Iterable<CockpitLocatorCandidate> locatorCandidates =
        const <CockpitLocatorCandidate>[],
    this.resolvedValue,
    this.scrollDirection,
    this.routeName,
    this.fromRouteName,
    this.positionDx,
    this.positionDy,
    required this.phase,
    this.unresolved = false,
    Iterable<String> segments = const <String>[],
    this.annotation,
    this.settledAfterMs,
    required this.recordedAt,
  }) : locatorCandidates = List<CockpitLocatorCandidate>.unmodifiable(
         _dedupeBySelector(locatorCandidates),
       ),
       segments = List<String>.unmodifiable(segments) {
    if (stepId.isEmpty) {
      throw ArgumentError.value(stepId, 'stepId', 'Step id is empty.');
    }
  }

  /// Monotonic identifier: `s1`, `s2`, …
  final String stepId;

  final CockpitInteractionStepKind kind;

  /// Ordered, deduped by selector; empty for `unresolved` steps.
  final List<CockpitLocatorCandidate> locatorCandidates;

  /// Final committed text (kind `text`).
  final String? resolvedValue;

  /// Scroll axis direction (kind `scroll`).
  final CockpitInteractionScrollDirection? scrollDirection;

  /// Route active when the step settled.
  final String? routeName;

  /// Previous route (kind `routeChange`).
  final String? fromRouteName;

  /// Diagnostic only; never used for replay.
  final double? positionDx;
  final double? positionDy;

  /// Session phase at capture.
  final CockpitRecorderPhase phase;

  /// True when no target resolved (noise chrome).
  final bool unresolved;

  /// Segment marks active at capture.
  final List<String> segments;

  /// Free-text note (kind `note`, or attached).
  final String? annotation;

  /// Measured quiet window after the action.
  final int? settledAfterMs;

  /// Wall clock, diagnostic.
  final DateTime recordedAt;

  static const ListEquality<CockpitLocatorCandidate> _candidateEquality =
      ListEquality<CockpitLocatorCandidate>();
  static const ListEquality<String> _segmentEquality = ListEquality<String>();

  /// Encodes this CockpitInteractionStep as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'stepId': stepId,
    'kind': kind.name,
    if (locatorCandidates.isNotEmpty)
      'locatorCandidates': locatorCandidates
          .map((candidate) => candidate.toJson())
          .toList(),
    if (resolvedValue != null) 'resolvedValue': resolvedValue,
    if (scrollDirection != null) 'scrollDirection': scrollDirection!.name,
    if (routeName != null) 'routeName': routeName,
    if (fromRouteName != null) 'fromRouteName': fromRouteName,
    if (positionDx != null) 'positionDx': positionDx,
    if (positionDy != null) 'positionDy': positionDy,
    'phase': phase.name,
    if (unresolved) 'unresolved': unresolved,
    if (segments.isNotEmpty) 'segments': segments.toList(),
    if (annotation != null) 'annotation': annotation,
    if (settledAfterMs != null) 'settledAfterMs': settledAfterMs,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };

  /// Decodes a CockpitInteractionStep from a JSON object.
  factory CockpitInteractionStep.fromJson(Object? value, {String path = r'$'}) {
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

    final rawCandidates = json['locatorCandidates'] == null
        ? const <Object?>[]
        : CockpitFoundationValueReader.list(
            json['locatorCandidates'],
            '$path.locatorCandidates',
          );
    final rawSegments = json['segments'] == null
        ? const <Object?>[]
        : CockpitFoundationValueReader.list(json['segments'], '$path.segments');

    return CockpitInteractionStep(
      stepId: CockpitFoundationValueReader.string(
        required('stepId'),
        '$path.stepId',
      ),
      kind: CockpitInteractionStepKind.fromJson(
        required('kind'),
        path: '$path.kind',
      ),
      locatorCandidates: <CockpitLocatorCandidate>[
        for (var index = 0; index < rawCandidates.length; index += 1)
          CockpitLocatorCandidate.fromJson(
            rawCandidates[index],
            path: '$path.locatorCandidates[$index]',
          ),
      ],
      resolvedValue: json['resolvedValue'] == null
          ? null
          : CockpitFoundationValueReader.boundedString(
              json['resolvedValue'],
              '$path.resolvedValue',
            ),
      scrollDirection: json['scrollDirection'] == null
          ? null
          : CockpitInteractionScrollDirection.fromJson(
              json['scrollDirection'],
              path: '$path.scrollDirection',
            ),
      routeName: json['routeName'] == null
          ? null
          : CockpitFoundationValueReader.boundedString(
              json['routeName'],
              '$path.routeName',
            ),
      fromRouteName: json['fromRouteName'] == null
          ? null
          : CockpitFoundationValueReader.boundedString(
              json['fromRouteName'],
              '$path.fromRouteName',
            ),
      positionDx: _optionalDouble(json['positionDx'], '$path.positionDx'),
      positionDy: _optionalDouble(json['positionDy'], '$path.positionDy'),
      phase: CockpitRecorderPhase.fromJson(
        required('phase'),
        path: '$path.phase',
      ),
      unresolved: json['unresolved'] == null
          ? false
          : CockpitFoundationValueReader.boolean(
              json['unresolved'],
              '$path.unresolved',
            ),
      segments: <String>[
        for (var index = 0; index < rawSegments.length; index += 1)
          CockpitFoundationValueReader.boundedString(
            rawSegments[index],
            '$path.segments[$index]',
          ),
      ],
      annotation: json['annotation'] == null
          ? null
          : CockpitFoundationValueReader.boundedString(
              json['annotation'],
              '$path.annotation',
            ),
      settledAfterMs: json['settledAfterMs'] == null
          ? null
          : CockpitFoundationValueReader.integer(
              json['settledAfterMs'],
              '$path.settledAfterMs',
              min: 0,
            ),
      recordedAt: CockpitFoundationValueReader.dateTime(
        required('recordedAt'),
        '$path.recordedAt',
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitInteractionStep &&
            other.stepId == stepId &&
            other.kind == kind &&
            _candidateEquality.equals(
              other.locatorCandidates,
              locatorCandidates,
            ) &&
            other.resolvedValue == resolvedValue &&
            other.scrollDirection == scrollDirection &&
            other.routeName == routeName &&
            other.fromRouteName == fromRouteName &&
            other.positionDx == positionDx &&
            other.positionDy == positionDy &&
            other.phase == phase &&
            other.unresolved == unresolved &&
            _segmentEquality.equals(other.segments, segments) &&
            other.annotation == annotation &&
            other.settledAfterMs == settledAfterMs &&
            other.recordedAt == recordedAt;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    stepId,
    kind,
    _candidateEquality.hash(locatorCandidates),
    resolvedValue,
    scrollDirection,
    routeName,
    fromRouteName,
    positionDx,
    positionDy,
    phase,
    unresolved,
    _segmentEquality.hash(segments),
    annotation,
    settledAfterMs,
    recordedAt,
  ]);
}

List<CockpitLocatorCandidate> _dedupeBySelector(
  Iterable<CockpitLocatorCandidate> candidates,
) {
  final seen = <String>{};
  return <CockpitLocatorCandidate>[
    for (final candidate in candidates)
      if (seen.add(candidate.selector)) candidate,
  ];
}
