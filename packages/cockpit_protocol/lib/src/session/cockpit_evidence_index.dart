import '../capture/cockpit_capture_kind.dart';
import '../capture/cockpit_capture_profile.dart';
import '../control/cockpit_command_status.dart';
import '../model/cockpit_artifact_ref.dart';
import '../model/cockpit_step_record.dart';
import '../recording/cockpit_recording_kind.dart';
import '../recording/cockpit_recording_purpose.dart';

final class CockpitEvidenceIndex {
  CockpitEvidenceIndex._({
    required this.artifactRefs,
    required this.screenshotRefs,
    required this.primaryScreenshotRef,
    required this.recordingRefs,
    required this.primaryRecordingRef,
    required this.screenshotCount,
    required this.nativeScreenshotCount,
    required this.flutterScreenshotCount,
    required this.deliveryArtifactsReady,
    required this.recordingCount,
    required this.nativeRecordingCount,
    required this.deliveryVideoReady,
    required this.failureCount,
  });

  final List<CockpitArtifactRef> artifactRefs;
  final List<String> screenshotRefs;
  final String primaryScreenshotRef;
  final List<String> recordingRefs;
  final String primaryRecordingRef;
  final int screenshotCount;
  final int nativeScreenshotCount;
  final int flutterScreenshotCount;
  final bool deliveryArtifactsReady;
  final int recordingCount;
  final int nativeRecordingCount;
  final bool deliveryVideoReady;
  final int failureCount;

  static const Set<String> _screenshotRoles = <String>{
    'screenshot',
    'step_screenshot',
  };
  static const Set<String> _recordingRoles = <String>{'recording'};

  /// Creates a CockpitEvidenceIndex using the named constructor `fromSteps`.
  factory CockpitEvidenceIndex.fromSteps(List<CockpitStepRecord> steps) {
    final artifactRefs = _dedupeArtifactRefs(steps);
    final screenshotRefs = _collectArtifactPaths(
      steps,
      roles: _screenshotRoles,
    );
    final primaryScreenshotRef = _selectPrimaryScreenshotRef(steps);
    final recordingRefs = _collectArtifactPaths(steps, roles: _recordingRoles);
    final primaryRecordingRef = recordingRefs.isEmpty
        ? ''
        : recordingRefs.first;
    final screenshotCount = steps.fold<int>(
      0,
      (count, step) => count + step.captureRefs.length,
    );
    final nativeScreenshotCount = steps.fold<int>(
      0,
      (count, step) =>
          count +
          (step.resolvedCaptureKind != null &&
                  step.resolvedCaptureKind != CockpitCaptureKind.flutterView
              ? step.captureRefs.length
              : 0),
    );
    final flutterScreenshotCount = steps.fold<int>(
      0,
      (count, step) =>
          count +
          (step.resolvedCaptureKind == CockpitCaptureKind.flutterView
              ? step.captureRefs.length
              : 0),
    );
    final deliveryArtifactsReady = steps.any(
      (step) =>
          step.captureRefs.isNotEmpty &&
          (step.requestedCaptureProfile == CockpitCaptureProfile.acceptance ||
              step.requestedCaptureProfile ==
                  CockpitCaptureProfile.nativePreferred),
    );
    final recordingCount = recordingRefs.length;
    final nativeRecordingCount = _countNativeRecordings(steps);
    final deliveryVideoReady = steps.any(
      (step) =>
          step.artifactRefs.any((artifact) => artifact.role == 'recording') &&
          step.actionArgs['recordingPurpose'] ==
              CockpitRecordingPurpose.acceptance.name,
    );
    final failureCount = steps
        .where((step) => step.status == CockpitCommandStatus.failed)
        .length;

    return CockpitEvidenceIndex._(
      artifactRefs: artifactRefs,
      screenshotRefs: screenshotRefs,
      primaryScreenshotRef: primaryScreenshotRef,
      recordingRefs: recordingRefs,
      primaryRecordingRef: primaryRecordingRef,
      screenshotCount: screenshotCount,
      nativeScreenshotCount: nativeScreenshotCount,
      flutterScreenshotCount: flutterScreenshotCount,
      deliveryArtifactsReady: deliveryArtifactsReady,
      recordingCount: recordingCount,
      nativeRecordingCount: nativeRecordingCount,
      deliveryVideoReady: deliveryVideoReady,
      failureCount: failureCount,
    );
  }

  static List<CockpitArtifactRef> _dedupeArtifactRefs(
    List<CockpitStepRecord> steps,
  ) {
    final refs = <CockpitArtifactRef>[];
    final seen = <String>{};
    for (final step in steps) {
      for (final artifact in <CockpitArtifactRef>[
        ...step.artifactRefs,
        ...step.captureRefs,
      ]) {
        final key = '${artifact.role}:${artifact.relativePath}';
        if (!seen.add(key)) {
          continue;
        }
        refs.add(artifact);
      }
    }
    return List<CockpitArtifactRef>.unmodifiable(refs);
  }

  static List<String> _collectArtifactPaths(
    List<CockpitStepRecord> steps, {
    required Set<String> roles,
  }) {
    final paths = <String>[];
    final seenPaths = <String>{};
    for (final step in steps) {
      for (final artifact in <CockpitArtifactRef>[
        ...step.captureRefs,
        ...step.artifactRefs,
      ]) {
        if (!roles.contains(artifact.role) ||
            !seenPaths.add(artifact.relativePath)) {
          continue;
        }
        paths.add(artifact.relativePath);
      }
    }
    return List<String>.unmodifiable(paths);
  }

  static int _countNativeRecordings(List<CockpitStepRecord> steps) {
    final seenPaths = <String>{};
    var count = 0;
    for (final step in steps) {
      final isNative = _recordsNativeRecording(step);
      for (final artifact in <CockpitArtifactRef>[
        ...step.captureRefs,
        ...step.artifactRefs,
      ]) {
        if (!_recordingRoles.contains(artifact.role) ||
            !seenPaths.add(artifact.relativePath)) {
          continue;
        }
        if (isNative) {
          count += 1;
        }
      }
    }
    return count;
  }

  static bool _recordsNativeRecording(CockpitStepRecord step) {
    // Only count recordings whose producer explicitly stamped the kind;
    // claiming "native" for unlabeled artifacts would fabricate evidence.
    return step.actionArgs['recordingKind'] ==
        CockpitRecordingKind.nativeScreen.name;
  }

  static String _selectPrimaryScreenshotRef(List<CockpitStepRecord> steps) {
    for (final step in steps.reversed) {
      if (step.requestedCaptureProfile != CockpitCaptureProfile.acceptance &&
          step.requestedCaptureProfile !=
              CockpitCaptureProfile.nativePreferred) {
        continue;
      }
      final screenshotRef = _primaryScreenshotPathForStep(step);
      if (screenshotRef != null) {
        return screenshotRef;
      }
    }
    for (final step in steps.reversed) {
      final screenshotRef = _primaryScreenshotPathForStep(step);
      if (screenshotRef != null) {
        return screenshotRef;
      }
    }
    return '';
  }

  /// Dedicated 'screenshot' artifacts outrank incidental per-step
  /// 'step_screenshot' captures when both exist on the same step.
  static String? _primaryScreenshotPathForStep(CockpitStepRecord step) {
    return _lastArtifactPathForStep(
          step,
          roles: const <String>{'screenshot'},
        ) ??
        _lastArtifactPathForStep(
          step,
          roles: const <String>{'step_screenshot'},
        );
  }

  static String? _lastArtifactPathForStep(
    CockpitStepRecord step, {
    required Set<String> roles,
  }) {
    for (final artifact in <CockpitArtifactRef>[
      ...step.captureRefs.reversed,
      ...step.artifactRefs.reversed,
    ]) {
      if (roles.contains(artifact.role)) {
        return artifact.relativePath;
      }
    }
    return null;
  }
}
