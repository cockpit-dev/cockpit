import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../infrastructure/cockpit_monotonic_clock.dart';
import '../test/cockpit_test_execution_plan.dart';

final class CockpitTestStepRecordingHandle {
  const CockpitTestStepRecordingHandle._({
    required this.index,
    required this.node,
    required this.occurrence,
    required this.startedAt,
    required this.startedElapsed,
  });

  final int index;
  final CockpitTestExecutionNode node;
  final CockpitTestStepOccurrence occurrence;
  final DateTime startedAt;
  final Duration startedElapsed;
}

final class CockpitTestRecordedArtifact {
  CockpitTestRecordedArtifact({
    required this.artifactId,
    required this.kind,
    required this.relativePath,
    required this.mediaType,
    required this.stepExecutionId,
    List<int>? bytes,
    this.sourcePath,
  }) : bytes = bytes == null ? null : List<int>.unmodifiable(bytes) {
    if ((this.bytes == null) == (sourcePath == null)) {
      throw ArgumentError('Exactly one artifact source is required.');
    }
  }

  final String artifactId;
  final String kind;
  final String relativePath;
  final String mediaType;
  final String stepExecutionId;
  final List<int>? bytes;
  final String? sourcePath;
}

final class CockpitTestAttemptRecorder {
  CockpitTestAttemptRecorder({required CockpitMonotonicClock clock})
    : _clock = clock;

  final CockpitMonotonicClock _clock;
  final List<CockpitTestStepResult?> _steps = <CockpitTestStepResult?>[];
  final List<CockpitTestRecordedArtifact> _artifacts =
      <CockpitTestRecordedArtifact>[];
  final Set<String> _artifactPaths = <String>{};

  CockpitTestStepRecordingHandle startStep(
    CockpitTestExecutionNode node, {
    int? retryAttempt,
    int? loopIteration,
  }) {
    final handle = CockpitTestStepRecordingHandle._(
      index: _steps.length,
      node: node,
      occurrence: CockpitTestStepOccurrence(
        retryAttempt: retryAttempt,
        loopIteration: loopIteration,
        callPath: node.callPath,
      ),
      startedAt: _clock.utcNow,
      startedElapsed: _clock.elapsed,
    );
    _steps.add(null);
    return handle;
  }

  void finishStep(
    CockpitTestStepRecordingHandle handle, {
    required CockpitTestStepStatus status,
    CockpitTestPlane? requestedPlane,
    CockpitTestPlane? actualPlane,
    String? driverId,
    CockpitLocatorResolution? locatorResolution,
    String? degradationReason,
    CockpitTestError? error,
    Iterable<String> evidence = const <String>[],
  }) {
    if (_steps[handle.index] != null) {
      throw StateError('Step recording is already complete.');
    }
    _steps[handle.index] = CockpitTestStepResult(
      stepId: handle.node.stepId,
      executionId: handle.node.executionId,
      section: handle.node.section,
      description: handle.node.description,
      operation: _operationName(handle.node.operation),
      timeoutMs: handle.node.timeoutMs,
      definitionPath: handle.node.sourcePath,
      status: status,
      startedAt: handle.startedAt,
      durationMs: (_clock.elapsed - handle.startedElapsed).inMilliseconds,
      occurrence: handle.occurrence,
      sourceLocation: handle.node.sourceLocation,
      requestedPlane: requestedPlane,
      actualPlane: actualPlane,
      driverId: driverId,
      locatorResolution: locatorResolution,
      degradationReason: degradationReason,
      error: error,
      evidence: evidence,
    );
  }

  List<String> addExecutionArtifacts({
    required CockpitCommandExecution execution,
    required String stepExecutionId,
  }) {
    final ids = <String>[];
    final paths = <String>{
      ...execution.result.artifacts.map((artifact) => artifact.relativePath),
      ...execution.artifactPayloads.keys,
      ...execution.artifactSourcePaths.keys,
    };
    for (final path in paths) {
      final bytes = execution.artifactPayloads[path];
      final sourcePath = execution.artifactSourcePaths[path];
      if (bytes == null && sourcePath == null) {
        continue;
      }
      final recordedPath = _claimArtifactPath(path);
      final artifactId =
          'artifact${(_artifacts.length + 1).toString().padLeft(6, '0')}';
      String? role;
      for (final artifact in execution.result.artifacts) {
        if (artifact.relativePath == path) {
          role = artifact.role;
          break;
        }
      }
      _artifacts.add(
        CockpitTestRecordedArtifact(
          artifactId: artifactId,
          kind: role ?? 'artifact',
          relativePath: recordedPath,
          mediaType: _mediaType(recordedPath),
          stepExecutionId: stepExecutionId,
          bytes: bytes,
          sourcePath: bytes == null ? sourcePath : null,
        ),
      );
      ids.add(artifactId);
    }
    return List<String>.unmodifiable(ids);
  }

  String? addArtifact({
    required String kind,
    required String relativePath,
    required String stepExecutionId,
    List<int>? bytes,
    String? sourcePath,
  }) {
    if (bytes == null && sourcePath == null) {
      return null;
    }
    final recordedPath = _claimArtifactPath(relativePath);
    final artifactId =
        'artifact${(_artifacts.length + 1).toString().padLeft(6, '0')}';
    _artifacts.add(
      CockpitTestRecordedArtifact(
        artifactId: artifactId,
        kind: kind,
        relativePath: recordedPath,
        mediaType: _mediaType(recordedPath),
        stepExecutionId: stepExecutionId,
        bytes: bytes,
        sourcePath: bytes == null ? sourcePath : null,
      ),
    );
    return artifactId;
  }

  List<CockpitTestStepResult> get steps {
    if (_steps.any((step) => step == null)) {
      throw StateError('Attempt contains unfinished step recordings.');
    }
    return List<CockpitTestStepResult>.unmodifiable(_steps.cast());
  }

  List<CockpitTestRecordedArtifact> get artifacts =>
      List<CockpitTestRecordedArtifact>.unmodifiable(_artifacts);

  String _claimArtifactPath(String requested) {
    if (_artifactPaths.add(requested)) {
      return requested;
    }
    final slash = requested.lastIndexOf('/');
    final dot = requested.lastIndexOf('.');
    final hasExtension = dot > slash;
    final base = hasExtension ? requested.substring(0, dot) : requested;
    final extension = hasExtension ? requested.substring(dot) : '';
    for (var suffix = 2; ; suffix += 1) {
      final candidate = '$base-$suffix$extension';
      if (_artifactPaths.add(candidate)) {
        return candidate;
      }
    }
  }
}

String _operationName(CockpitTestPlanOperation operation) =>
    switch (operation) {
      CockpitTestActionPlanOperation(:final action) =>
        'action.${action.kind.name}',
      CockpitTestStartRecordingPlanOperation() => 'recording.start',
      CockpitTestStopRecordingPlanOperation() => 'recording.stop',
      CockpitTestIfPlanOperation() => 'control.if',
      CockpitTestRetryPlanOperation() => 'control.retry',
      CockpitTestLoopPlanOperation() => 'control.loop',
    };

String _mediaType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.txt') || lower.endsWith('.log')) return 'text/plain';
  return 'application/octet-stream';
}
