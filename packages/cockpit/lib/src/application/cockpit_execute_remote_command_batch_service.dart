export 'cockpit_application_service_exception.dart';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../session/cockpit_remote_session_handle.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_execute_remote_command_service.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_interactive_session_lock.dart';
import 'cockpit_interactive_snapshot_store.dart';
import 'cockpit_read_remote_snapshot_service.dart';
import 'cockpit_session_reference_resolver.dart';
import 'cockpit_start_remote_recording_service.dart';
import 'cockpit_stop_remote_recording_service.dart';

final class CockpitInteractiveBatchCommand {
  const CockpitInteractiveBatchCommand({
    required this.command,
    this.resultProfile,
    this.snapshotOptions,
    this.compareAgainstSnapshotRef,
  });

  final CockpitCommand command;
  final CockpitInteractiveResultProfile? resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
}

final class CockpitExecuteRemoteCommandBatchRequest {
  const CockpitExecuteRemoteCommandBatchRequest({
    required this.commands,
    this.baseUri,
    this.sessionHandle,
    this.sessionHandlePath,
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

  final List<CockpitInteractiveBatchCommand> commands;
  final Uri? baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String? sessionHandlePath;
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

final class CockpitExecuteRemoteCommandBatchSummary {
  const CockpitExecuteRemoteCommandBatchSummary({
    required this.totalCount,
    required this.successCount,
    required this.failureCount,
    required this.stoppedEarly,
  });

  final int totalCount;
  final int successCount;
  final int failureCount;
  final bool stoppedEarly;

  Map<String, Object?> toJson() => <String, Object?>{
    'totalCount': totalCount,
    'successCount': successCount,
    'failureCount': failureCount,
    'stoppedEarly': stoppedEarly,
  };
}

final class CockpitExecuteRemoteCommandBatchResult {
  const CockpitExecuteRemoteCommandBatchResult({
    required this.results,
    required this.summary,
    this.recordingSession,
    this.recordingResult,
    this.finalSnapshot,
    this.sessionHandle,
  });

  final List<CockpitExecuteRemoteCommandResult> results;
  final CockpitExecuteRemoteCommandBatchSummary summary;
  final CockpitStartRemoteRecordingResult? recordingSession;
  final CockpitStopRemoteRecordingResult? recordingResult;
  final CockpitReadRemoteSnapshotResult? finalSnapshot;
  final CockpitRemoteSessionHandle? sessionHandle;

  Map<String, Object?> toJson() => <String, Object?>{
    'results': results.map((result) => result.toJson()).toList(),
    'summary': summary.toJson(),
    if (recordingSession != null)
      'recordingSession': recordingSession!.toJson(),
    if (recordingResult != null) 'recordingResult': recordingResult!.toJson(),
    if (finalSnapshot != null) 'finalSnapshot': finalSnapshot!.toJson(),
    if (sessionHandle != null) 'sessionHandle': sessionHandle!.toJson(),
  };
}

final class CockpitExecuteRemoteCommandBatchService {
  CockpitExecuteRemoteCommandBatchService({
    CockpitRemoteCommandExecutor? executeCommand,
    CockpitRemoteSnapshotDetailedReader? readSnapshot,
    CockpitRemoteRecordingStarter? startRecording,
    CockpitRemoteRecordingStopper? stopRecording,
    CockpitSessionReferenceResolver? sessionReferenceResolver,
    CockpitInteractiveSnapshotStore? snapshotStore,
    CockpitInteractiveSessionLock? sessionLock,
    CockpitCommandArtifactTempFileFactory? artifactTempFileFactory,
  }) : _executeCommand = executeCommand,
       _readSnapshot = readSnapshot,
       _startRecording = startRecording,
       _stopRecording = stopRecording,
       _sessionReferenceResolver =
           sessionReferenceResolver ?? CockpitSessionReferenceResolver(),
       _snapshotStore = snapshotStore ?? CockpitInteractiveSnapshotStore(),
       _sessionLock = sessionLock ?? CockpitInteractiveSessionLock(),
       _artifactTempFileFactory = artifactTempFileFactory;

  final CockpitRemoteCommandExecutor? _executeCommand;
  final CockpitRemoteSnapshotDetailedReader? _readSnapshot;
  final CockpitRemoteRecordingStarter? _startRecording;
  final CockpitRemoteRecordingStopper? _stopRecording;
  final CockpitSessionReferenceResolver _sessionReferenceResolver;
  final CockpitInteractiveSnapshotStore _snapshotStore;
  final CockpitInteractiveSessionLock _sessionLock;
  final CockpitCommandArtifactTempFileFactory? _artifactTempFileFactory;

  Future<CockpitExecuteRemoteCommandBatchResult> execute(
    CockpitExecuteRemoteCommandBatchRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      baseUri: request.baseUri,
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final sessionKey = resolved.baseUri.toString();

    final execution = _sessionLock.run(sessionKey, () async {
      final executeService = CockpitExecuteRemoteCommandService(
        executeCommand: _executeCommand,
        readSnapshot: _readSnapshot,
        sessionReferenceResolver: _sessionReferenceResolver,
        snapshotStore: _snapshotStore,
        sessionLock: CockpitInteractiveSessionLock(),
        artifactTempFileFactory: _artifactTempFileFactory,
      );
      final readSnapshotService = CockpitReadRemoteSnapshotService(
        readSnapshot: _readSnapshot,
        sessionReferenceResolver: _sessionReferenceResolver,
        snapshotStore: _snapshotStore,
      );
      final startRecordingService = request.recording == null
          ? null
          : CockpitStartRemoteRecordingService(
              startRecording: _startRecording,
              sessionReferenceResolver: _sessionReferenceResolver,
              sessionLock: CockpitInteractiveSessionLock(),
            );
      final stopRecordingService = request.recording == null
          ? null
          : CockpitStopRemoteRecordingService(
              stopRecording: _stopRecording,
              sessionReferenceResolver: _sessionReferenceResolver,
              sessionLock: CockpitInteractiveSessionLock(),
              artifactTempFileFactory: _artifactTempFileFactory,
            );

      final results = <CockpitExecuteRemoteCommandResult>[];
      var stoppedEarly = false;
      CockpitStartRemoteRecordingResult? recordingSession;
      CockpitStopRemoteRecordingResult? recordingResult;
      var recordingStarted = false;

      try {
        recordingSession = startRecordingService == null
            ? null
            : await startRecordingService.start(
                CockpitStartRemoteRecordingRequest(
                  baseUri: resolved.baseUri,
                  sessionHandle: resolved.sessionHandle,
                  iosDeviceId: request.iosDeviceId,
                  recording: request.recording!,
                ),
              );
        recordingStarted = recordingSession != null;

        for (final batchCommand in request.commands) {
          final result = await executeService.execute(
            CockpitExecuteRemoteCommandRequest(
              baseUri: resolved.baseUri,
              sessionHandle: resolved.sessionHandle,
              command: batchCommand.command,
              resultProfile:
                  batchCommand.resultProfile ?? request.defaultResultProfile,
              snapshotOptions: batchCommand.snapshotOptions,
              compareAgainstSnapshotRef: batchCommand.compareAgainstSnapshotRef,
              defaultCommandTimeout: request.defaultCommandTimeout,
              iosDeviceId: request.iosDeviceId,
              cancellation: request.cancellation,
            ),
          );
          results.add(result);
          if (!result.command.success && request.failFast) {
            stoppedEarly = true;
            break;
          }
        }

        final finalSnapshot = request.finalSnapshotProfile == null
            ? null
            : await readSnapshotService.read(
                CockpitReadRemoteSnapshotRequest(
                  baseUri: resolved.baseUri,
                  sessionHandle: resolved.sessionHandle,
                  resultProfile: request.finalSnapshotProfile!,
                  snapshotOptions: request.finalSnapshotOptions,
                  iosDeviceId: request.iosDeviceId,
                ),
              );
        if (stopRecordingService != null) {
          recordingResult = await stopRecordingService.stop(
            CockpitStopRemoteRecordingRequest(
              baseUri: resolved.baseUri,
              sessionHandle: resolved.sessionHandle,
              iosDeviceId: request.iosDeviceId,
            ),
          );
          recordingStarted = false;
        }
        final successCount = results
            .where((result) => result.command.success)
            .length;
        return CockpitExecuteRemoteCommandBatchResult(
          results: results,
          summary: CockpitExecuteRemoteCommandBatchSummary(
            totalCount: results.length,
            successCount: successCount,
            failureCount: results.length - successCount,
            stoppedEarly: stoppedEarly,
          ),
          recordingSession: recordingSession,
          recordingResult: recordingResult,
          finalSnapshot: finalSnapshot,
          sessionHandle: resolved.sessionHandle,
        );
      } finally {
        if (recordingStarted && stopRecordingService != null) {
          try {
            await stopRecordingService.stop(
              CockpitStopRemoteRecordingRequest(
                baseUri: resolved.baseUri,
                sessionHandle: resolved.sessionHandle,
                iosDeviceId: request.iosDeviceId,
              ),
            );
          } on Object {
            // Preserve the original failure so AI agents see the real cause.
          }
        }
      }
    });
    final cancellation = request.cancellation;
    if (cancellation == null) return execution;
    return Future.any<CockpitExecuteRemoteCommandBatchResult>(
      <Future<CockpitExecuteRemoteCommandBatchResult>>[
        execution,
        cancellation.then<CockpitExecuteRemoteCommandBatchResult>((_) {
          throw const CockpitRemoteCommandCancelledException();
        }),
      ],
    );
  }
}
