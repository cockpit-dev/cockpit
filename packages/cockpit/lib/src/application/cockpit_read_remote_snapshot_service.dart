import 'dart:async';

export 'cockpit_application_service_exception.dart';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_interactive_snapshot_store.dart';
import 'cockpit_session_reference_resolver.dart';

typedef CockpitRemoteSnapshotDetailedReader =
    Future<CockpitRemoteSnapshotResponse> Function(
      Uri baseUri,
      CockpitSnapshotOptions options,
    );

typedef CockpitRemoteSnapshotArtifactDownloader =
    Future<Map<String, String>> Function(
      Uri baseUri,
      Iterable<CockpitRemoteArtifactDownload> downloads,
    );
typedef CockpitRemoteSnapshotUiIdleWaiter =
    Future<bool> Function(
      Uri baseUri, {
      required Duration quietWindow,
      required Duration timeout,
      required bool includeNetworkIdle,
    });

final class CockpitReadRemoteSnapshotRequest {
  const CockpitReadRemoteSnapshotRequest({
    this.baseUri,
    this.sessionHandle,
    this.sessionHandlePath,
    this.androidDeviceId,
    this.iosDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.standard(),
    this.snapshotOptions,
    this.compareAgainstSnapshotRef,
  });

  final Uri? baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String? sessionHandlePath;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
}

final class CockpitReadRemoteSnapshotResult {
  const CockpitReadRemoteSnapshotResult({
    required this.routeName,
    required this.diagnosticLevel,
    required this.truncated,
    this.uiSummary,
    this.snapshot,
    this.diagnostics,
    this.delta,
    this.snapshotRef,
    this.artifactDownloads = const <CockpitRemoteArtifactDownload>[],
    this.artifactSourcePaths = const <String, String>{},
    this.sessionHandle,
    this.effectiveSnapshotOptions,
  });

  final String? routeName;
  final String diagnosticLevel;
  final bool truncated;
  final CockpitInteractiveSnapshotSummary? uiSummary;
  final CockpitSnapshot? snapshot;
  final Map<String, Object?>? diagnostics;
  final CockpitInteractiveSnapshotDelta? delta;
  final String? snapshotRef;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;
  final Map<String, String> artifactSourcePaths;
  final CockpitRemoteSessionHandle? sessionHandle;
  final CockpitSnapshotOptions? effectiveSnapshotOptions;

  Map<String, Object?> toJson() => <String, Object?>{
    if (routeName != null) 'routeName': routeName,
    'diagnosticLevel': diagnosticLevel,
    'truncated': truncated,
    if (uiSummary != null) 'uiSummary': uiSummary!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (diagnostics != null) 'diagnostics': diagnostics,
    if (delta != null) 'delta': delta!.toJson(),
    if (snapshotRef != null) 'snapshotRef': snapshotRef,
    if (artifactDownloads.isNotEmpty)
      'artifactDownloads': artifactDownloads
          .map((download) => download.toJson())
          .toList(growable: false),
    if (artifactSourcePaths.isNotEmpty)
      'artifactSourcePaths': artifactSourcePaths,
    if (sessionHandle != null) 'sessionHandle': sessionHandle!.toJson(),
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
  };
}

final class CockpitReadRemoteSnapshotService {
  CockpitReadRemoteSnapshotService({
    CockpitRemoteSnapshotDetailedReader? readSnapshot,
    CockpitRemoteSnapshotArtifactDownloader? downloadArtifacts,
    CockpitRemoteArtifactTempFileFactory? artifactTempFileFactory,
    CockpitSessionReferenceResolver? sessionReferenceResolver,
    CockpitInteractiveSnapshotStore? snapshotStore,
  }) : _readSnapshot =
           readSnapshot ??
           ((baseUri, options) => CockpitRemoteSessionClient(
             baseUri: baseUri,
           ).readSnapshotDetailed(options: options)),
       _downloadArtifacts =
           downloadArtifacts ??
           (artifactTempFileFactory == null
               ? null
               : (baseUri, downloads) => CockpitRemoteSessionClient(
                   baseUri: baseUri,
                   artifactTempFileFactory: artifactTempFileFactory,
                 ).downloadArtifactsToFiles(downloads)),
       _sessionReferenceResolver =
           sessionReferenceResolver ?? CockpitSessionReferenceResolver(),
       _snapshotStore = snapshotStore ?? CockpitInteractiveSnapshotStore();

  final CockpitRemoteSnapshotDetailedReader _readSnapshot;
  final CockpitRemoteSnapshotArtifactDownloader? _downloadArtifacts;
  final CockpitSessionReferenceResolver _sessionReferenceResolver;
  final CockpitInteractiveSnapshotStore _snapshotStore;

  Future<CockpitReadRemoteSnapshotResult> read(
    CockpitReadRemoteSnapshotRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      baseUri: request.baseUri,
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final effectiveSnapshotOptions = request.resultProfile
        .resolveSnapshotOptions(request.snapshotOptions);
    final snapshotResponse = await cockpitReadRemoteSnapshotConsistently(
      baseUri: resolved.baseUri,
      options: effectiveSnapshotOptions,
      readSnapshot: _readSnapshot,
    );
    final snapshot = snapshotResponse.snapshot;
    final downloader = _downloadArtifacts;
    final artifactSourcePaths =
        request.resultProfile.artifacts ==
                CockpitInteractiveArtifactLevel.metadata &&
            snapshotResponse.artifactDownloads.isNotEmpty &&
            downloader != null
        ? await downloader(resolved.baseUri, snapshotResponse.artifactDownloads)
        : const <String, String>{};
    final sessionKey = resolved.baseUri.toString();
    final baseline = request.compareAgainstSnapshotRef == null
        ? null
        : _snapshotStore.read(
            request.compareAgainstSnapshotRef!,
            sessionKey: sessionKey,
          );
    final snapshotRef = request.resultProfile.emitsSnapshotRef
        ? _snapshotStore.put(sessionKey: sessionKey, snapshot: snapshot)
        : null;

    return CockpitReadRemoteSnapshotResult(
      routeName: snapshot.routeName,
      diagnosticLevel: snapshot.diagnosticLevel.jsonValue,
      truncated: snapshot.truncated,
      uiSummary: request.resultProfile.emitsUiSummary
          ? cockpitInteractiveSummarizeSnapshot(snapshot)
          : null,
      snapshot: request.resultProfile.emitsInlineSnapshot ? snapshot : null,
      diagnostics: cockpitInteractiveDiagnosticsFromSnapshot(
        snapshot,
        request.resultProfile.diagnostics,
      ),
      delta: baseline == null
          ? null
          : cockpitInteractiveDiffSnapshots(baseline.snapshot, snapshot),
      snapshotRef: snapshotRef,
      artifactDownloads: snapshotResponse.artifactDownloads,
      artifactSourcePaths: artifactSourcePaths,
      sessionHandle: resolved.sessionHandle,
      effectiveSnapshotOptions: effectiveSnapshotOptions,
    );
  }
}

Future<CockpitRemoteSnapshotResponse> cockpitReadRemoteSnapshotConsistently({
  required Uri baseUri,
  required CockpitSnapshotOptions options,
  required CockpitRemoteSnapshotDetailedReader readSnapshot,
  CockpitRemoteSnapshotUiIdleWaiter? waitForUiIdle,
}) async {
  var response = await readSnapshot(baseUri, options);
  if (!_isLikelyTransitionEmptySnapshot(response.snapshot)) {
    return response;
  }

  for (final delay in _transitionSnapshotRetryDelays) {
    await Future<void>.delayed(delay);
    response = await readSnapshot(baseUri, options);
    if (!_isLikelyTransitionEmptySnapshot(response.snapshot)) {
      break;
    }
  }

  if (_isLikelyTransitionEmptySnapshot(response.snapshot)) {
    await (waitForUiIdle ?? _defaultWaitForRemoteUiIdle)(
      baseUri,
      quietWindow: _transitionSnapshotIdleQuietWindow,
      timeout: _transitionSnapshotIdleTimeout,
      includeNetworkIdle: true,
    );
    response = await readSnapshot(baseUri, options);
  }

  return response;
}

const List<Duration> _transitionSnapshotRetryDelays = <Duration>[
  Duration(milliseconds: 120),
  Duration(milliseconds: 240),
];
const Duration _transitionSnapshotIdleQuietWindow = Duration(milliseconds: 96);
const Duration _transitionSnapshotIdleTimeout = Duration(milliseconds: 1600);

Future<bool> _defaultWaitForRemoteUiIdle(
  Uri baseUri, {
  required Duration quietWindow,
  required Duration timeout,
  required bool includeNetworkIdle,
}) async {
  final client = CockpitRemoteSessionClient(baseUri: baseUri);
  final initial = await client.waitForUiIdle(
    quietWindow: quietWindow,
    timeout: timeout,
    includeNetworkIdle: includeNetworkIdle,
  );
  if (initial) {
    return true;
  }
  await Future<void>.delayed(const Duration(milliseconds: 120));
  final retryTimeout = timeout < const Duration(milliseconds: 400)
      ? timeout
      : const Duration(milliseconds: 400);
  return client.waitForUiIdle(
    quietWindow: quietWindow,
    timeout: retryTimeout,
    includeNetworkIdle: includeNetworkIdle,
  );
}

bool _isLikelyTransitionEmptySnapshot(CockpitSnapshot snapshot) {
  final routeName = snapshot.routeName;
  if (routeName == null || routeName.isEmpty) {
    return false;
  }
  if (snapshot.visibleTargets.isNotEmpty) {
    return false;
  }

  final summary = snapshot.summary;
  if (summary != null && summary.visibleTargetCount > 0) {
    return false;
  }

  final accessibility = snapshot.accessibility;
  if (accessibility != null && accessibility.totalAccessibleTargetCount > 0) {
    return false;
  }

  return true;
}
