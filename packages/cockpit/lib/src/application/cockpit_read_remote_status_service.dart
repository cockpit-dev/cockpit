export 'cockpit_application_service_exception.dart';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_read_budget.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_interactive_snapshot_store.dart';
import 'cockpit_read_remote_snapshot_service.dart';
import 'cockpit_session_reference_resolver.dart';

typedef CockpitRemoteStatusReader =
    Future<CockpitRemoteSessionStatus> Function(Uri baseUri);

final class CockpitReadRemoteStatusRequest {
  const CockpitReadRemoteStatusRequest({
    this.baseUri,
    this.sessionHandle,
    this.sessionHandlePath,
    this.androidDeviceId,
    this.iosDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.minimal(),
    this.snapshotOptions,
    this.deadline,
  });

  final Uri? baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String? sessionHandlePath;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final DateTime? deadline;
}

final class CockpitReadRemoteStatusResult {
  const CockpitReadRemoteStatusResult({
    required this.sessionId,
    required this.platform,
    required this.transportType,
    required this.currentRouteName,
    required this.capabilities,
    required this.recordingCapabilities,
    this.activeRecording,
    this.environment,
    this.uiSummary,
    this.snapshot,
    this.snapshotRef,
    this.artifactDownloads = const <CockpitRemoteArtifactDownload>[],
    this.sessionHandle,
    this.effectiveSnapshotOptions,
  });

  final String sessionId;
  final String platform;
  final String transportType;
  final String? currentRouteName;
  final CockpitCapabilities capabilities;
  final CockpitRecordingCapabilities recordingCapabilities;
  final CockpitRecordingSession? activeRecording;
  final CockpitEnvironment? environment;
  final CockpitInteractiveSnapshotSummary? uiSummary;
  final CockpitSnapshot? snapshot;
  final String? snapshotRef;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;
  final CockpitRemoteSessionHandle? sessionHandle;
  final CockpitSnapshotOptions? effectiveSnapshotOptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'platform': platform,
    'transportType': transportType,
    if (currentRouteName != null) 'currentRouteName': currentRouteName,
    'capabilities': capabilities.toJson(),
    'recordingCapabilities': recordingCapabilities.toJson(),
    if (activeRecording != null) 'activeRecording': activeRecording!.toJson(),
    if (environment != null) 'environment': environment!.toJson(),
    if (uiSummary != null) 'uiSummary': uiSummary!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (snapshotRef != null) 'snapshotRef': snapshotRef,
    if (artifactDownloads.isNotEmpty)
      'artifactDownloads': artifactDownloads
          .map((download) => download.toJson())
          .toList(growable: false),
    if (sessionHandle != null) 'sessionHandle': sessionHandle!.toJson(),
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
  };
}

final class CockpitReadRemoteStatusService {
  CockpitReadRemoteStatusService({
    CockpitRemoteStatusReader? readStatus,
    CockpitRemoteSnapshotDetailedReader? readSnapshot,
    CockpitSessionReferenceResolver? sessionReferenceResolver,
    CockpitInteractiveSnapshotStore? snapshotStore,
  }) : _readStatus = readStatus,
       _readSnapshot = readSnapshot,
       _sessionReferenceResolver =
           sessionReferenceResolver ?? CockpitSessionReferenceResolver(),
       _snapshotStore = snapshotStore ?? CockpitInteractiveSnapshotStore();

  final CockpitRemoteStatusReader? _readStatus;
  final CockpitRemoteSnapshotDetailedReader? _readSnapshot;
  final CockpitSessionReferenceResolver _sessionReferenceResolver;
  final CockpitInteractiveSnapshotStore _snapshotStore;

  Future<CockpitReadRemoteStatusResult> read(
    CockpitReadRemoteStatusRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      baseUri: request.baseUri,
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final budget = CockpitRemoteReadBudget(request.deadline);
    final status = await budget.run(() {
      final override = _readStatus;
      if (override != null) return override(resolved.baseUri);
      return CockpitRemoteSessionClient(
        baseUri: resolved.baseUri,
        requestTimeout: budget.bound(
          const Duration(seconds: 30),
          reserve: const Duration(seconds: 3),
        ),
      ).readStatus();
    });
    final effectiveSnapshotOptions =
        request.resultProfile.requiresStatusSnapshotRead
        ? request.resultProfile.resolveSnapshotOptions(request.snapshotOptions)
        : null;
    final snapshotResponse = effectiveSnapshotOptions == null
        ? null
        : await cockpitReadRemoteSnapshotConsistently(
            baseUri: resolved.baseUri,
            options: effectiveSnapshotOptions,
            readSnapshot: (baseUri, options) {
              final override = _readSnapshot;
              if (override != null) return override(baseUri, options);
              return CockpitRemoteSessionClient(
                baseUri: baseUri,
                requestTimeout: budget.bound(
                  const Duration(seconds: 30),
                  reserve: const Duration(seconds: 3),
                ),
              ).readSnapshotDetailed(options: options);
            },
            deadline: request.deadline,
          );
    final snapshot = snapshotResponse?.snapshot ?? status.snapshot;
    final snapshotRef = request.resultProfile.emitsSnapshotRef
        ? _snapshotStore.put(
            sessionKey: resolved.baseUri.toString(),
            snapshot: snapshot,
          )
        : null;

    return CockpitReadRemoteStatusResult(
      sessionId: status.sessionId,
      platform: status.platform,
      transportType: status.transportType,
      currentRouteName: snapshot.routeName ?? status.currentRouteName,
      capabilities: status.capabilities,
      recordingCapabilities: status.recordingCapabilities,
      activeRecording: status.activeRecording,
      environment: status.environment,
      uiSummary: request.resultProfile.emitsUiSummary
          ? cockpitInteractiveSummarizeSnapshot(snapshot)
          : null,
      snapshot: request.resultProfile.emitsInlineSnapshot ? snapshot : null,
      snapshotRef: snapshotRef,
      artifactDownloads:
          snapshotResponse?.artifactDownloads ??
          const <CockpitRemoteArtifactDownload>[],
      sessionHandle: resolved.sessionHandle,
      effectiveSnapshotOptions: effectiveSnapshotOptions,
    );
  }
}
