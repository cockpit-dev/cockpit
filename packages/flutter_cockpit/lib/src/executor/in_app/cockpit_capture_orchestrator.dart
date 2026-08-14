import '../../capture/cockpit_capture_kind.dart';
import '../../capture/cockpit_capture_profile.dart';
import '../../capture/cockpit_screenshot_inspector.dart';
import '../../control/cockpit_capture_policy.dart';
import '../../control/cockpit_command.dart';
import '../../control/cockpit_screenshot_request.dart';
import '../../model/cockpit_artifact_ref.dart';
import '../../runtime/cockpit_snapshot_options.dart';
import 'cockpit_command_context.dart';

typedef CockpitBestEffortWaitForUiIdle =
    Future<void> Function({required bool includeNetworkIdleValue});
typedef CockpitSnapshotOptionsForReason =
    CockpitSnapshotOptions Function(CockpitScreenshotReason reason);

final class CockpitCaptureArtifacts {
  const CockpitCaptureArtifacts({
    required this.artifacts,
    required this.artifactPayloads,
    this.snapshot,
    this.requestedCaptureProfile,
    this.resolvedCaptureKind,
    this.usedCaptureFallback = false,
    this.degradationReason,
  });

  final List<CockpitArtifactRef> artifacts;
  final Map<String, List<int>> artifactPayloads;
  final Map<String, Object?>? snapshot;
  final CockpitCaptureProfile? requestedCaptureProfile;
  final CockpitCaptureKind? resolvedCaptureKind;
  final bool usedCaptureFallback;
  final String? degradationReason;
}

final class CockpitCaptureOrchestrator {
  const CockpitCaptureOrchestrator({
    required CockpitCaptureHandler? captureHandler,
    required CockpitPostActionSettler postActionSettler,
    required CockpitPostActionSettler settleBeforeObservation,
    required CockpitBestEffortWaitForUiIdle bestEffortWaitForUiIdle,
    required CockpitSnapshotOptionsForReason defaultSnapshotOptionsForReason,
    CockpitScreenshotInspector? screenshotInspector,
  }) : _captureHandler = captureHandler,
       _postActionSettler = postActionSettler,
       _settleBeforeObservation = settleBeforeObservation,
       _bestEffortWaitForUiIdle = bestEffortWaitForUiIdle,
       _defaultSnapshotOptionsForReason = defaultSnapshotOptionsForReason,
       _screenshotInspector =
           screenshotInspector ?? const CockpitDartUiScreenshotInspector();

  final CockpitCaptureHandler? _captureHandler;
  final CockpitPostActionSettler _postActionSettler;
  final CockpitPostActionSettler _settleBeforeObservation;
  final CockpitBestEffortWaitForUiIdle _bestEffortWaitForUiIdle;
  final CockpitSnapshotOptionsForReason _defaultSnapshotOptionsForReason;
  final CockpitScreenshotInspector _screenshotInspector;

  Future<CockpitCaptureArtifacts?> captureAfterAction(CockpitCommand command) {
    final shouldCapture = switch (command.capturePolicy) {
      CockpitCapturePolicy.afterAction ||
      CockpitCapturePolicy.afterActionAndFailure => true,
      CockpitCapturePolicy.none || CockpitCapturePolicy.onFailure => false,
    };
    if (!shouldCapture || _captureHandler == null) {
      return Future<CockpitCaptureArtifacts?>.value(null);
    }

    return _capture(
      command.screenshotRequest ??
          CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.afterAction,
            name: command.commandId,
            includeSnapshot: true,
            attachToStep: true,
            snapshotOptions: const CockpitSnapshotOptions.live(),
          ),
    );
  }

  Future<CockpitCaptureArtifacts?> captureExplicit(
    CockpitCommand command, {
    required bool waitForNetworkIdleDuringAcceptanceCapture,
  }) async {
    final request = command.screenshotRequest;
    if (request == null || _captureHandler == null) {
      return null;
    }

    await _postActionSettler();
    if (request.includeSnapshot) {
      await _bestEffortWaitForUiIdle(
        includeNetworkIdleValue: waitForNetworkIdleDuringAcceptanceCapture,
      );
    } else {
      await _settleBeforeObservation();
    }

    return _capture(request);
  }

  Future<CockpitCaptureArtifacts> _capture(
    CockpitScreenshotRequest request,
  ) async {
    final capture = await _captureHandler!(
      request.copyWith(
        snapshotOptions:
            request.snapshotOptions ??
            _defaultSnapshotOptionsForReason(request.reason),
      ),
    );
    final bytes = capture.screenshot.bytes;
    await _screenshotInspector.inspect(
      bytes,
      requireVisiblePixels:
          request.reason == CockpitScreenshotReason.acceptance,
    );

    return CockpitCaptureArtifacts(
      artifacts: <CockpitArtifactRef>[capture.screenshot.artifact],
      artifactPayloads: <String, List<int>>{
        capture.screenshot.artifact.relativePath: bytes,
      },
      snapshot: capture.screenshot.snapshot?.toJson(),
      requestedCaptureProfile: capture.requestedProfile,
      resolvedCaptureKind: capture.resolvedCaptureKind,
      usedCaptureFallback: capture.usedFallback,
      degradationReason: capture.degradationReason,
    );
  }
}
