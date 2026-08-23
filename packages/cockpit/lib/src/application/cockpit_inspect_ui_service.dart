import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_app_handle.dart';
import 'cockpit_app_reference_resolver.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_read_remote_snapshot_service.dart';
import 'cockpit_session_registry.dart';
import 'cockpit_ui_locator_advisor.dart';

final class CockpitInspectUiRequest {
  const CockpitInspectUiRequest({
    this.appId,
    this.app,
    this.appHandlePath,
    this.baseUri,
    this.androidDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.inspect(),
    this.snapshotOptions,
    this.compareAgainstSnapshotRef,
  });

  final String? appId;
  final CockpitAppHandle? app;
  final String? appHandlePath;
  final Uri? baseUri;
  final String? androidDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
}

final class CockpitInspectUiResult {
  const CockpitInspectUiResult({
    this.app,
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
    this.effectiveSnapshotOptions,
    this.locator,
  });

  final CockpitAppHandle? app;
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
  final CockpitSnapshotOptions? effectiveSnapshotOptions;
  final Map<String, Object?>? locator;

  Map<String, Object?> toJson() => <String, Object?>{
    if (app != null) 'app': app!.toJson(),
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
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
    if (locator != null) 'locator': locator,
  };
}

final class CockpitInspectUiService {
  CockpitInspectUiService({
    CockpitReadRemoteSnapshotService? snapshotService,
    CockpitAppReferenceResolver? appReferenceResolver,
    CockpitSessionRegistry? registry,
  }) : _snapshotService = snapshotService ?? CockpitReadRemoteSnapshotService(),
       _appReferenceResolver =
           appReferenceResolver ??
           CockpitAppReferenceResolver(registry: registry);

  final CockpitReadRemoteSnapshotService _snapshotService;
  final CockpitAppReferenceResolver _appReferenceResolver;

  Future<CockpitInspectUiResult> inspect(
    CockpitInspectUiRequest request,
  ) async {
    final locate =
        request.resultProfile.name ==
        CockpitInteractiveResultProfileName.locate;
    final locatorQuery = locate ? request.snapshotOptions?.query?.trim() : null;
    final resolved = await _appReferenceResolver.resolve(
      appId: request.appId,
      app: request.app,
      appHandlePath: request.appHandlePath,
      baseUri: request.baseUri,
      androidDeviceId: request.androidDeviceId,
    );
    var result = await _snapshotService.read(
      CockpitReadRemoteSnapshotRequest(
        baseUri: resolved.baseUri,
        sessionHandle: resolved.app?.remoteSession,
        resultProfile: request.resultProfile,
        snapshotOptions: request.snapshotOptions,
        compareAgainstSnapshotRef: request.compareAgainstSnapshotRef,
        retainArtifacts: !locate,
      ),
    );
    if (locate &&
        locatorQuery != null &&
        locatorQuery.isNotEmpty &&
        result.completeSnapshot?.visibleTargets.isEmpty == true) {
      result = await _snapshotService.read(
        CockpitReadRemoteSnapshotRequest(
          baseUri: resolved.baseUri,
          sessionHandle: resolved.app?.remoteSession,
          resultProfile: request.resultProfile,
          snapshotOptions: request.snapshotOptions!.copyWith(
            clearQuery: true,
            maxTargets: 24,
            maxAncestorsPerTarget: 0,
          ),
          compareAgainstSnapshotRef: request.compareAgainstSnapshotRef,
          retainArtifacts: false,
        ),
      );
    }
    final locator = result.completeSnapshot == null || !locate
        ? null
        : locatorQuery == null || locatorQuery.isEmpty
        ? cockpitBuildUiTargetIndex(result.completeSnapshot!)
        : cockpitBuildUiLocatorMatches(result.completeSnapshot!, locatorQuery);
    return CockpitInspectUiResult(
      app: resolved.app,
      routeName: result.routeName,
      diagnosticLevel: result.diagnosticLevel,
      truncated: result.truncated,
      uiSummary: result.uiSummary,
      snapshot: result.snapshot,
      diagnostics: result.diagnostics,
      delta: result.delta,
      snapshotRef: result.snapshotRef,
      artifactDownloads: result.artifactDownloads,
      artifactSourcePaths: result.artifactSourcePaths,
      effectiveSnapshotOptions: result.effectiveSnapshotOptions,
      locator: locator,
    );
  }
}
