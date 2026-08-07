import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_app_handle.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_execute_remote_command_batch_service.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_session_registry.dart';
import 'cockpit_start_recording_service.dart';
import 'cockpit_stop_recording_service.dart';
import '../session/cockpit_remote_session_handle.dart';

typedef CockpitRunBatchCommand = CockpitInteractiveBatchCommand;

final class CockpitRunBatchRequest {
  const CockpitRunBatchRequest({
    required this.commands,
    this.appId,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.iosDeviceId,
    this.defaultResultProfile =
        const CockpitInteractiveResultProfile.standard(),
    this.failFast = true,
    this.recording,
    this.finalSnapshotProfile,
    this.finalSnapshotOptions,
    this.defaultCommandTimeout = const Duration(seconds: 30),
    this.cancellation,
  });

  final List<CockpitRunBatchCommand> commands;
  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final CockpitInteractiveResultProfile defaultResultProfile;
  final bool failFast;
  final CockpitRecordingRequest? recording;
  final CockpitInteractiveResultProfile? finalSnapshotProfile;
  final CockpitSnapshotOptions? finalSnapshotOptions;
  final Duration defaultCommandTimeout;
  final Future<void>? cancellation;
}

typedef CockpitRunBatchResult = CockpitExecuteRemoteCommandBatchResult;
typedef CockpitRunBatchStartRecordingFunction =
    Future<CockpitStartRecordingResult> Function(
      CockpitStartRecordingRequest request,
    );
typedef CockpitRunBatchStopRecordingFunction =
    Future<CockpitStopRecordingResult> Function(
      CockpitStopRecordingRequest request,
    );

final class CockpitRunBatchService {
  CockpitRunBatchService({
    CockpitExecuteRemoteCommandBatchService? executeService,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitStartRecordingService? startRecordingService,
    CockpitStopRecordingService? stopRecordingService,
    CockpitRunBatchStartRecordingFunction? startRecording,
    CockpitRunBatchStopRecordingFunction? stopRecording,
    CockpitSessionRegistry? registry,
  }) : _executeService =
           executeService ?? CockpitExecuteRemoteCommandBatchService(),
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _startRecording =
           startRecording ??
           (startRecordingService ??
                   CockpitStartRecordingService(registry: registry))
               .start,
       _stopRecording =
           stopRecording ??
           (stopRecordingService ??
                   CockpitStopRecordingService(registry: registry))
               .stop;

  final CockpitExecuteRemoteCommandBatchService _executeService;
  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitRunBatchStartRecordingFunction _startRecording;
  final CockpitRunBatchStopRecordingFunction _stopRecording;

  Future<CockpitRunBatchResult> run(CockpitRunBatchRequest request) async {
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final recording = request.recording;
    final sessionHandle = resolved.app?.remoteSession;
    if (recording == null) {
      return _executeRemoteBatch(
        request,
        baseUri: resolved.baseUri,
        sessionHandle: sessionHandle,
      );
    }

    CockpitStartRecordingResult? recordingSession;
    CockpitStopRecordingResult? recordingResult;
    var recordingStarted = false;
    try {
      recordingSession = await _startRecording(
        CockpitStartRecordingRequest(
          recording: recording,
          app: resolved.app,
          baseUri: resolved.app == null ? resolved.baseUri : null,
          androidDeviceId: request.androidDeviceId,
          iosDeviceId:
              request.iosDeviceId ??
              (resolved.app?.platform == 'ios' ? resolved.app?.deviceId : null),
        ),
      );
      recordingStarted = true;

      final batchResult = await _executeRemoteBatch(
        request,
        baseUri: resolved.baseUri,
        sessionHandle: sessionHandle,
        recording: null,
      );
      recordingResult = await _stopRecording(
        CockpitStopRecordingRequest(
          app: resolved.app,
          baseUri: resolved.app == null ? resolved.baseUri : null,
          androidDeviceId: request.androidDeviceId,
          iosDeviceId:
              request.iosDeviceId ??
              (resolved.app?.platform == 'ios' ? resolved.app?.deviceId : null),
        ),
      );
      recordingStarted = false;
      return _withRecordingResult(
        batchResult,
        recordingSession: recordingSession,
        recordingResult: recordingResult,
      );
    } finally {
      if (recordingStarted) {
        try {
          await _stopRecording(
            CockpitStopRecordingRequest(
              app: resolved.app,
              baseUri: resolved.app == null ? resolved.baseUri : null,
              androidDeviceId: request.androidDeviceId,
              iosDeviceId:
                  request.iosDeviceId ??
                  (resolved.app?.platform == 'ios'
                      ? resolved.app?.deviceId
                      : null),
            ),
          );
        } on Object {
          // Preserve the command or snapshot failure that caused cleanup.
        }
      }
    }
  }

  Future<CockpitExecuteRemoteCommandBatchResult> _executeRemoteBatch(
    CockpitRunBatchRequest request, {
    required Uri baseUri,
    CockpitRemoteSessionHandle? sessionHandle,
    CockpitRecordingRequest? recording,
  }) {
    return _executeService.execute(
      CockpitExecuteRemoteCommandBatchRequest(
        commands: request.commands,
        baseUri: baseUri,
        sessionHandle: sessionHandle,
        defaultResultProfile: request.defaultResultProfile,
        failFast: request.failFast,
        recording: recording,
        finalSnapshotProfile: request.finalSnapshotProfile,
        finalSnapshotOptions: request.finalSnapshotOptions,
        defaultCommandTimeout: request.defaultCommandTimeout,
        iosDeviceId: request.iosDeviceId,
        cancellation: request.cancellation,
      ),
    );
  }

  CockpitExecuteRemoteCommandBatchResult _withRecordingResult(
    CockpitExecuteRemoteCommandBatchResult result, {
    required CockpitStartRecordingResult? recordingSession,
    required CockpitStopRecordingResult? recordingResult,
  }) {
    return CockpitExecuteRemoteCommandBatchResult(
      results: result.results,
      summary: result.summary,
      recordingSession: recordingSession,
      recordingResult: recordingResult,
      finalSnapshot: result.finalSnapshot,
      sessionHandle: result.sessionHandle,
    );
  }
}
