import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_app_handle.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_recording_evidence.dart';
import '../recording/cockpit_recording_strategy_resolver.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_session_registry.dart';
import 'cockpit_stop_remote_recording_service.dart';

final class CockpitStopRecordingRequest {
  const CockpitStopRecordingRequest({
    this.appId,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.iosDeviceId,
  });

  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final String? iosDeviceId;
}

typedef CockpitStopRecordingResult = CockpitStopRemoteRecordingResult;

final class CockpitStopRecordingService {
  CockpitStopRecordingService({
    CockpitStopRemoteRecordingService? stopService,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitRecordingStrategyResolver recordingStrategyResolver =
        const CockpitRecordingStrategyResolver(),
    CockpitSessionRegistry? registry,
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
  }) : _stopService =
           stopService ??
           CockpitStopRemoteRecordingService(
             artifactTempFileFactory: artifactTempFileFactory,
           ),
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry),
       _recordingStrategyResolver = recordingStrategyResolver,
       _artifactTempFileFactory = artifactTempFileFactory;

  final CockpitStopRemoteRecordingService _stopService;
  final CockpitAppReferenceResolver _appReferenceResolver;
  final CockpitRecordingStrategyResolver _recordingStrategyResolver;
  final CockpitRemoteArtifactTempFileFactory? _artifactTempFileFactory;

  Future<CockpitStopRecordingResult> stop(
    CockpitStopRecordingRequest request,
  ) async {
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final platform = _resolvedPlatform(
      app: resolved.app,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    if (platform != null) {
      final resolution = await _recordingStrategyResolver
          .resolveDetailedForStop(
            platform: platform,
            recording: const CockpitRecordingRequest(
              purpose: CockpitRecordingPurpose.acceptance,
              name: 'active-recording',
            ),
            client: CockpitRemoteSessionClient(
              baseUri: resolved.baseUri,
              artifactTempFileFactory: _artifactTempFileFactory,
            ),
            sessionHandle: resolved.app?.remoteSession,
            androidDeviceId:
                request.androidDeviceId ??
                (resolved.app?.platform == 'android'
                    ? resolved.app?.deviceId
                    : null),
            iosDeviceId:
                request.iosDeviceId ??
                (resolved.app?.platform == 'ios'
                    ? resolved.app?.deviceId
                    : null),
            platformAppId:
                resolved.app?.platformAppId ??
                resolved.app?.remoteSession?.effectivePlatformAppId,
            processId:
                resolved.app?.processId ??
                resolved.app?.remoteSession?.processId,
          );
      final adapter = resolution?.adapter;
      if (adapter != null) {
        return _toStopResult(
          await adapter.stopRecording(),
          sessionHandle: resolved.app?.remoteSession,
        );
      }
    }
    return _stopService.stop(
      CockpitStopRemoteRecordingRequest(
        baseUri: resolved.baseUri,
        sessionHandle: resolved.app?.remoteSession,
        iosDeviceId: request.iosDeviceId,
      ),
    );
  }

  CockpitStopRecordingResult _toStopResult(
    CockpitRecordingResult recordingResult, {
    required CockpitRemoteSessionHandle? sessionHandle,
  }) {
    final evidence = cockpitAssessRecordingEvidence(recordingResult);
    return CockpitStopRecordingResult(
      state: evidence.state,
      purpose: recordingResult.purpose,
      recordingKind: recordingResult.recordingKind,
      requestedMode: recordingResult.requestedMode,
      requestedLayer: recordingResult.requestedLayer,
      effectiveLayer: recordingResult.effectiveLayer,
      fallbackUsed: recordingResult.fallbackUsed,
      fallbackReason: recordingResult.fallbackReason,
      artifact: evidence.artifact,
      durationMs: recordingResult.durationMs,
      failureReason: evidence.failureReason,
      sessionHandle: sessionHandle,
    );
  }

  String? _resolvedPlatform({
    required CockpitAppHandle? app,
    required String? androidDeviceId,
    required String? iosDeviceId,
  }) {
    final appPlatform = app?.platform;
    if (appPlatform != null && appPlatform.isNotEmpty) {
      return appPlatform;
    }
    if (iosDeviceId != null && iosDeviceId.isNotEmpty) {
      return 'ios';
    }
    if (androidDeviceId != null && androidDeviceId.isNotEmpty) {
      return 'android';
    }
    return null;
  }
}
