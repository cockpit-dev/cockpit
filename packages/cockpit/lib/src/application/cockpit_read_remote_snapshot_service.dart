import 'dart:async';
import 'dart:convert';
import 'dart:io';

export 'cockpit_application_service_exception.dart';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_read_budget.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_application_service_exception.dart';
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
    this.deadline,
    this.retainArtifacts = true,
  });

  final Uri? baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String? sessionHandlePath;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
  final DateTime? deadline;
  final bool retainArtifacts;
}

final class CockpitReadRemoteSnapshotResult {
  const CockpitReadRemoteSnapshotResult({
    required this.routeName,
    required this.diagnosticLevel,
    required this.truncated,
    this.uiSummary,
    this.snapshot,
    this.completeSnapshot,
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
  final CockpitSnapshot? completeSnapshot;
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
  }) : _readSnapshot = readSnapshot,
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

  final CockpitRemoteSnapshotDetailedReader? _readSnapshot;
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
      readSnapshot: (baseUri, options) {
        final override = _readSnapshot;
        if (override != null) return override(baseUri, options);
        return CockpitRemoteSessionClient(
          baseUri: baseUri,
          requestTimeout: CockpitRemoteReadBudget(request.deadline).remaining(),
        ).readSnapshotDetailed(options: options);
      },
      deadline: request.deadline,
    );
    final snapshot = snapshotResponse.snapshot;
    final downloader = _downloadArtifacts;
    final artifactSourcePaths =
        (request.resultProfile.artifacts ==
                    CockpitInteractiveArtifactLevel.metadata ||
                (request.resultProfile.emitsInlineSnapshot &&
                    snapshot.diagnosticsArtifactRef != null)) &&
            snapshotResponse.artifactDownloads.isNotEmpty &&
            downloader != null
        ? await downloader(resolved.baseUri, snapshotResponse.artifactDownloads)
        : const <String, String>{};
    final mustResolveSnapshot =
        request.resultProfile.emitsInlineSnapshot &&
        (!request.retainArtifacts || artifactSourcePaths.isNotEmpty);
    late final CockpitSnapshot resolvedSnapshot;
    try {
      resolvedSnapshot = mustResolveSnapshot
          ? await _resolveInlineSnapshot(snapshot, artifactSourcePaths)
          : snapshot;
    } finally {
      if (!request.retainArtifacts) {
        await _deleteSnapshotArtifacts(artifactSourcePaths.values);
      }
    }
    final sessionKey = resolved.baseUri.toString();
    final baseline = request.compareAgainstSnapshotRef == null
        ? null
        : _snapshotStore.read(
            request.compareAgainstSnapshotRef!,
            sessionKey: sessionKey,
          );
    final snapshotRef = request.resultProfile.emitsSnapshotRef
        ? _snapshotStore.put(sessionKey: sessionKey, snapshot: resolvedSnapshot)
        : null;

    return CockpitReadRemoteSnapshotResult(
      routeName: resolvedSnapshot.routeName,
      diagnosticLevel: resolvedSnapshot.diagnosticLevel.jsonValue,
      truncated: resolvedSnapshot.truncated,
      uiSummary: request.resultProfile.emitsUiSummary
          ? cockpitInteractiveSummarizeSnapshot(resolvedSnapshot)
          : null,
      snapshot: request.resultProfile.emitsInlineSnapshot ? snapshot : null,
      completeSnapshot: request.resultProfile.emitsInlineSnapshot
          ? resolvedSnapshot
          : null,
      diagnostics: cockpitInteractiveDiagnosticsFromSnapshot(
        resolvedSnapshot,
        request.resultProfile.diagnostics,
      ),
      delta: baseline == null
          ? null
          : cockpitInteractiveDiffSnapshots(
              baseline.snapshot,
              resolvedSnapshot,
            ),
      snapshotRef: snapshotRef,
      artifactDownloads: request.retainArtifacts
          ? snapshotResponse.artifactDownloads
          : const <CockpitRemoteArtifactDownload>[],
      artifactSourcePaths: request.retainArtifacts
          ? artifactSourcePaths
          : const <String, String>{},
      sessionHandle: resolved.sessionHandle,
      effectiveSnapshotOptions: effectiveSnapshotOptions,
    );
  }

  Future<CockpitSnapshot> _resolveInlineSnapshot(
    CockpitSnapshot snapshot,
    Map<String, String> artifactSourcePaths,
  ) async {
    final artifactRef = snapshot.diagnosticsArtifactRef;
    if (artifactRef == null) return snapshot;
    final sourcePath = artifactSourcePaths[artifactRef.relativePath];
    if (sourcePath == null || sourcePath.isEmpty) {
      throw const CockpitApplicationServiceException(
        code: 'snapshotArtifactUnavailable',
        message: 'The complete remote snapshot artifact is unavailable.',
      );
    }
    try {
      final decoded = jsonDecode(await File(sourcePath).readAsString());
      if (decoded is! Map<Object?, Object?>) {
        throw const FormatException('Snapshot artifact is not an object.');
      }
      return CockpitSnapshot.fromJson(
        Map<String, Object?>.from(decoded),
      ).copyWith(diagnosticsArtifactRef: artifactRef);
    } on Object catch (error) {
      throw CockpitApplicationServiceException(
        code: 'snapshotArtifactInvalid',
        message: 'The complete remote snapshot artifact is invalid.',
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _deleteSnapshotArtifacts(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Worker-owned temporary files are cleaned up best-effort after the
        // complete snapshot has been reduced to a bounded locator result.
      }
    }
  }
}

Future<CockpitRemoteSnapshotResponse> cockpitReadRemoteSnapshotConsistently({
  required Uri baseUri,
  required CockpitSnapshotOptions options,
  required CockpitRemoteSnapshotDetailedReader readSnapshot,
  CockpitRemoteSnapshotUiIdleWaiter? waitForUiIdle,
  DateTime? deadline,
}) async {
  final budget = CockpitRemoteReadBudget(deadline);
  Future<CockpitRemoteSnapshotResponse> readOnce() =>
      budget.run(() => readSnapshot(baseUri, options));

  var response = await readOnce();
  if (!_isLikelyTransitionEmptySnapshot(response.snapshot)) {
    return response;
  }

  for (final delay in _transitionSnapshotRetryDelays) {
    await budget.delay(delay);
    response = await readOnce();
    if (!_isLikelyTransitionEmptySnapshot(response.snapshot)) {
      break;
    }
  }

  if (_isLikelyTransitionEmptySnapshot(response.snapshot)) {
    final idleTimeout = budget.bound(_transitionSnapshotIdleTimeout);
    await budget.run(
      () => (waitForUiIdle ?? _defaultWaitForRemoteUiIdle)(
        baseUri,
        quietWindow: _transitionSnapshotIdleQuietWindow,
        timeout: idleTimeout,
        includeNetworkIdle: true,
      ),
    );
    response = await readOnce();
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
