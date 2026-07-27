import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_capture_adapter.dart';
import '../adapters/cockpit_recording_adapter.dart';
import '../capture/cockpit_host_capture_adapter.dart';
import 'cockpit_system_control_action_service.dart';
import 'cockpit_system_test_target.dart';

final class CockpitSystemTestCaptureAdapter implements CockpitCaptureAdapter {
  CockpitSystemTestCaptureAdapter({
    required CockpitSystemTestTarget target,
    required CockpitSystemControlActionService actionService,
  }) : _target = target,
       _actionService = actionService;

  final CockpitSystemTestTarget _target;
  final CockpitSystemControlActionService _actionService;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    final request = command.screenshotRequest;
    if (request == null) {
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: 0,
        message: 'System screenshot capture requires a screenshot request.',
      );
    }
    final stopwatch = Stopwatch()..start();
    final result = await _actionService.run(
      CockpitSystemControlActionRequest(
        platform: _target.platform,
        deviceId: _target.deviceId,
        appId: _target.appId,
        processId: _target.processId,
        metadata: _target.metadata,
        action: CockpitSystemControlAction.captureScreenshot,
        parameters: <String, Object?>{'name': request.name},
        timeout: Duration(milliseconds: command.timeoutMs ?? 15000),
      ),
    );
    final sourcePath = result.sourceFilePath;
    final artifactJson = result.artifact;
    if (!result.success || sourcePath == null || artifactJson == null) {
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: result.errorMessage ?? 'System screenshot capture failed.',
        details: <String, Object?>{
          if (result.errorCode != null) 'systemErrorCode': result.errorCode,
          if (result.errorDetails.isNotEmpty)
            'systemErrorDetails': result.errorDetails,
        },
      );
    }
    return cockpitSuccessfulHostCaptureExecution(
      command: command,
      artifact: CockpitArtifactRef.fromJson(artifactJson),
      durationMs: stopwatch.elapsedMilliseconds,
      sourceFilePath: sourcePath,
    );
  }
}

final class CockpitSystemTestRecordingAdapter
    implements CockpitRecordingAdapter {
  CockpitSystemTestRecordingAdapter({
    required CockpitSystemTestTarget target,
    required CockpitSystemControlActionService actionService,
  }) : _target = target,
       _actionService = actionService;

  final CockpitSystemTestTarget _target;
  final CockpitSystemControlActionService _actionService;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    final result = await _actionService.run(
      CockpitSystemControlActionRequest(
        platform: _target.platform,
        deviceId: _target.deviceId,
        appId: _target.appId,
        processId: _target.processId,
        metadata: _target.metadata,
        action: CockpitSystemControlAction.startRecording,
        parameters: <String, Object?>{
          'name': request.name,
          'purpose': request.purpose.name,
          'mode': request.mode.jsonValue,
          if (request.layer != null) 'layer': request.layer!.jsonValue,
        },
      ),
    );
    final session = result.recordingSession;
    if (!result.success || session == null) {
      throw StateError(
        result.errorMessage ?? 'System recording failed to start.',
      );
    }
    return CockpitRecordingSession.fromJson(session);
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    final result = await _actionService.run(
      CockpitSystemControlActionRequest(
        platform: _target.platform,
        deviceId: _target.deviceId,
        appId: _target.appId,
        processId: _target.processId,
        metadata: _target.metadata,
        action: CockpitSystemControlAction.stopRecording,
      ),
    );
    final recording = result.recordingResult;
    if (recording != null) {
      return CockpitRecordingResult.fromJson(recording);
    }
    return CockpitRecordingResult(
      state: CockpitRecordingState.failed,
      failureReason: result.errorMessage ?? 'System recording failed to stop.',
    );
  }
}
