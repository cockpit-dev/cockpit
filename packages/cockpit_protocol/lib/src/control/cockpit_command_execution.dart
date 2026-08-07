import 'package:collection/collection.dart';

import '../model/cockpit_step_record.dart';
import 'cockpit_command_result.dart';

final class CockpitCommandExecution {
  /// Creates a CockpitCommandExecution.
  CockpitCommandExecution({
    required this.result,
    Map<String, List<int>> artifactPayloads = const <String, List<int>>{},
    Map<String, String> artifactSourcePaths = const <String, String>{},
    List<CockpitStepRecord> runtimeSteps = const <CockpitStepRecord>[],
  }) : artifactPayloads = Map.unmodifiable(
         artifactPayloads.map(
           (path, bytes) => MapEntry(path, List<int>.unmodifiable(bytes)),
         ),
       ),
       artifactSourcePaths = Map.unmodifiable(artifactSourcePaths),
       runtimeSteps = List.unmodifiable(runtimeSteps);

  final CockpitCommandResult result;
  final Map<String, List<int>> artifactPayloads;
  final Map<String, String> artifactSourcePaths;
  final List<CockpitStepRecord> runtimeSteps;

  static const MapEquality<String, List<int>> _artifactPayloadEquality =
      MapEquality<String, List<int>>(values: ListEquality<int>());
  static const MapEquality<String, String> _artifactSourcePathEquality =
      MapEquality<String, String>();
  static const ListEquality<CockpitStepRecord> _runtimeStepEquality =
      ListEquality<CockpitStepRecord>();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CockpitCommandExecution &&
            other.result == result &&
            _artifactPayloadEquality.equals(
              other.artifactPayloads,
              artifactPayloads,
            ) &&
            _artifactSourcePathEquality.equals(
              other.artifactSourcePaths,
              artifactSourcePaths,
            ) &&
            _runtimeStepEquality.equals(other.runtimeSteps, runtimeSteps);
  }

  @override
  int get hashCode => Object.hash(
    result,
    _artifactPayloadEquality.hash(artifactPayloads),
    _artifactSourcePathEquality.hash(artifactSourcePaths),
    _runtimeStepEquality.hash(runtimeSteps),
  );
}
