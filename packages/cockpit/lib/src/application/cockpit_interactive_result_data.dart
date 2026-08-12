import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_interactive_result_profile.dart';

final class CockpitInteractiveCommandCore {
  const CockpitInteractiveCommandCore({
    required this.commandId,
    required this.commandType,
    required this.success,
    required this.durationMs,
    this.locatorResolution,
    this.requestedCaptureProfile,
    this.resolvedCaptureKind,
    required this.usedCaptureFallback,
    this.degradationReason,
    this.surface,
    this.changed,
    this.error,
  });

  final String commandId;
  final String commandType;
  final bool success;
  final int durationMs;
  final CockpitLocatorResolution? locatorResolution;
  final String? requestedCaptureProfile;
  final String? resolvedCaptureKind;
  final bool usedCaptureFallback;
  final String? degradationReason;
  final Map<String, Object?>? surface;
  final bool? changed;
  final CockpitCommandError? error;

  factory CockpitInteractiveCommandCore.fromResult(
    CockpitCommandResult result,
  ) {
    return CockpitInteractiveCommandCore(
      commandId: result.commandId,
      commandType: result.commandType.name,
      success: result.success,
      durationMs: result.durationMs,
      locatorResolution: result.locatorResolution,
      requestedCaptureProfile: result.requestedCaptureProfile?.name,
      resolvedCaptureKind: result.resolvedCaptureKind?.name,
      usedCaptureFallback: result.usedCaptureFallback,
      degradationReason: result.degradationReason,
      surface: result.surface,
      changed: result.changed,
      error: result.error,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'commandId': commandId,
    'commandType': commandType,
    'success': success,
    'durationMs': durationMs,
    if (locatorResolution != null)
      'locatorResolution': locatorResolution!.toJson(),
    if (requestedCaptureProfile != null)
      'requestedCaptureProfile': requestedCaptureProfile,
    if (resolvedCaptureKind != null) 'resolvedCaptureKind': resolvedCaptureKind,
    'usedCaptureFallback': usedCaptureFallback,
    if (degradationReason != null) 'degradationReason': degradationReason,
    if (surface != null) 'surface': surface,
    if (changed != null) 'changed': changed,
    if (error != null) 'error': error!.toJson(),
  };
}

final class CockpitInteractiveArtifactDescriptor {
  const CockpitInteractiveArtifactDescriptor({
    required this.role,
    required this.relativePath,
    this.byteLength,
    this.sourcePath,
  });

  final String role;
  final String relativePath;
  final int? byteLength;
  final String? sourcePath;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'role': role, 'relativePath': relativePath};
    if (byteLength != null) {
      json['byteLength'] = byteLength;
    }
    if (sourcePath != null) {
      json['sourcePath'] = sourcePath;
    }
    return json;
  }
}

final class CockpitInteractiveSnapshotSummary {
  const CockpitInteractiveSnapshotSummary({
    required this.routeName,
    required this.diagnosticLevel,
    required this.truncated,
    required this.visibleTargetCount,
    required this.targetsWithCockpitIdCount,
    required this.targetsWithTextCount,
    required this.networkEntryCount,
    required this.networkFailureCount,
    required this.runtimeEntryCount,
    required this.runtimeErrorCount,
    required this.rebuildEntryCount,
    required this.totalRebuildCount,
    required this.accessibilityTargetCount,
    required this.accessibilityTraversalCount,
    required this.textPreviews,
    this.focus,
  });

  final String? routeName;
  final String diagnosticLevel;
  final bool truncated;
  final int visibleTargetCount;
  final int targetsWithCockpitIdCount;
  final int targetsWithTextCount;
  final int networkEntryCount;
  final int networkFailureCount;
  final int runtimeEntryCount;
  final int runtimeErrorCount;
  final int rebuildEntryCount;
  final int totalRebuildCount;
  final int accessibilityTargetCount;
  final int accessibilityTraversalCount;
  final List<String> textPreviews;
  final CockpitFocusSnapshot? focus;

  Map<String, Object?> toJson() => <String, Object?>{
    if (routeName != null) 'routeName': routeName,
    'diagnosticLevel': diagnosticLevel,
    'truncated': truncated,
    'visibleTargetCount': visibleTargetCount,
    'targetsWithCockpitIdCount': targetsWithCockpitIdCount,
    'targetsWithTextCount': targetsWithTextCount,
    'networkEntryCount': networkEntryCount,
    'networkFailureCount': networkFailureCount,
    'runtimeEntryCount': runtimeEntryCount,
    'runtimeErrorCount': runtimeErrorCount,
    'rebuildEntryCount': rebuildEntryCount,
    'totalRebuildCount': totalRebuildCount,
    'accessibilityTargetCount': accessibilityTargetCount,
    'accessibilityTraversalCount': accessibilityTraversalCount,
    'textPreviews': textPreviews,
    if (focus != null) 'focus': focus!.toJson(),
  };
}

final class CockpitInteractiveSnapshotDelta {
  const CockpitInteractiveSnapshotDelta({
    required this.routeChanged,
    required this.fromRouteName,
    required this.toRouteName,
    required this.visibleTargetCountDelta,
    required this.targetsWithTextCountDelta,
    required this.networkFailureCountDelta,
    required this.runtimeErrorCountDelta,
    required this.accessibilityTargetCountDelta,
    required this.addedTextPreviews,
    required this.removedTextPreviews,
  });

  final bool routeChanged;
  final String? fromRouteName;
  final String? toRouteName;
  final int visibleTargetCountDelta;
  final int targetsWithTextCountDelta;
  final int networkFailureCountDelta;
  final int runtimeErrorCountDelta;
  final int accessibilityTargetCountDelta;
  final List<String> addedTextPreviews;
  final List<String> removedTextPreviews;

  Map<String, Object?> toJson() => <String, Object?>{
    'routeChanged': routeChanged,
    if (fromRouteName != null) 'fromRouteName': fromRouteName,
    if (toRouteName != null) 'toRouteName': toRouteName,
    'visibleTargetCountDelta': visibleTargetCountDelta,
    'targetsWithTextCountDelta': targetsWithTextCountDelta,
    'networkFailureCountDelta': networkFailureCountDelta,
    'runtimeErrorCountDelta': runtimeErrorCountDelta,
    'accessibilityTargetCountDelta': accessibilityTargetCountDelta,
    'addedTextPreviews': addedTextPreviews,
    'removedTextPreviews': removedTextPreviews,
  };
}

CockpitInteractiveSnapshotSummary? cockpitInteractiveStaticSummaryForProfile(
  CockpitInteractiveResultProfile profile, {
  String? routeName,
}) {
  if (!profile.emitsUiSummary && !profile.emitsInlineSnapshot) {
    return null;
  }
  return CockpitInteractiveSnapshotSummary(
    routeName: routeName,
    diagnosticLevel: profile.snapshotProfile.jsonValue,
    truncated: false,
    visibleTargetCount: 0,
    targetsWithCockpitIdCount: 0,
    targetsWithTextCount: 0,
    networkEntryCount: 0,
    networkFailureCount: 0,
    runtimeEntryCount: 0,
    runtimeErrorCount: 0,
    rebuildEntryCount: 0,
    totalRebuildCount: 0,
    accessibilityTargetCount: 0,
    accessibilityTraversalCount: 0,
    textPreviews: const <String>[],
    focus: null,
  );
}

CockpitInteractiveSnapshotSummary cockpitInteractiveSummarizeSnapshot(
  CockpitSnapshot snapshot,
) {
  final summary = snapshot.summary;
  final visibleTargets = snapshot.visibleTargets;
  final textPreviews = visibleTargets
      .map((target) => target.text ?? target.content?.displayLabel)
      .whereType<String>()
      .where((text) => text.trim().isNotEmpty)
      .take(5)
      .toList(growable: false);
  return CockpitInteractiveSnapshotSummary(
    routeName: snapshot.routeName,
    diagnosticLevel: snapshot.diagnosticLevel.jsonValue,
    truncated: snapshot.truncated,
    visibleTargetCount: summary?.visibleTargetCount ?? visibleTargets.length,
    targetsWithCockpitIdCount:
        summary?.targetsWithCockpitIdCount ??
        visibleTargets.where((target) => target.cockpitId != null).length,
    targetsWithTextCount:
        summary?.targetsWithTextCount ??
        visibleTargets.where((target) => (target.text ?? '').isNotEmpty).length,
    networkEntryCount:
        snapshot.network?.capturedEntryCount ??
        snapshot.network?.totalEntryCount ??
        0,
    networkFailureCount: snapshot.network?.failureCount ?? 0,
    runtimeEntryCount:
        snapshot.runtime?.capturedEntryCount ??
        snapshot.runtime?.totalEntryCount ??
        0,
    runtimeErrorCount: snapshot.runtime?.errorCount ?? 0,
    rebuildEntryCount: snapshot.rebuild?.capturedEntryCount ?? 0,
    totalRebuildCount: snapshot.rebuild?.totalRebuildCount ?? 0,
    accessibilityTargetCount:
        snapshot.accessibility?.totalAccessibleTargetCount ?? 0,
    accessibilityTraversalCount:
        snapshot.accessibility?.traversalEntries.length ?? 0,
    textPreviews: textPreviews,
    focus: snapshot.focus,
  );
}

CockpitInteractiveSnapshotDelta cockpitInteractiveDiffSnapshots(
  CockpitSnapshot previous,
  CockpitSnapshot current,
) {
  final previousSummary = cockpitInteractiveSummarizeSnapshot(previous);
  final currentSummary = cockpitInteractiveSummarizeSnapshot(current);
  final previousTexts = previousSummary.textPreviews.toSet();
  final currentTexts = currentSummary.textPreviews.toSet();
  return CockpitInteractiveSnapshotDelta(
    routeChanged: previous.routeName != current.routeName,
    fromRouteName: previous.routeName,
    toRouteName: current.routeName,
    visibleTargetCountDelta:
        currentSummary.visibleTargetCount - previousSummary.visibleTargetCount,
    targetsWithTextCountDelta:
        currentSummary.targetsWithTextCount -
        previousSummary.targetsWithTextCount,
    networkFailureCountDelta:
        currentSummary.networkFailureCount -
        previousSummary.networkFailureCount,
    runtimeErrorCountDelta:
        currentSummary.runtimeErrorCount - previousSummary.runtimeErrorCount,
    accessibilityTargetCountDelta:
        currentSummary.accessibilityTargetCount -
        previousSummary.accessibilityTargetCount,
    addedTextPreviews: currentTexts.difference(previousTexts).toList()..sort(),
    removedTextPreviews: previousTexts.difference(currentTexts).toList()
      ..sort(),
  );
}

Map<String, Object?>? cockpitInteractiveDiagnosticsFromSnapshot(
  CockpitSnapshot snapshot,
  CockpitInteractiveDiagnosticsLevel diagnosticsLevel,
) {
  if (diagnosticsLevel == CockpitInteractiveDiagnosticsLevel.none) {
    return null;
  }
  final diagnostics = <String, Object?>{'level': diagnosticsLevel.jsonValue};
  if (diagnosticsLevel == CockpitInteractiveDiagnosticsLevel.full) {
    diagnostics['network'] = (snapshot.network?.toJson());
    diagnostics['runtime'] = (snapshot.runtime?.toJson());
    diagnostics['rebuild'] = (snapshot.rebuild?.toJson());
    diagnostics['accessibility'] = (snapshot.accessibility?.toJson());
    return diagnostics;
  }

  final network = snapshot.network;
  if (network != null && network.failureCount > 0) {
    diagnostics['network'] = <String, Object?>{
      'totalEntryCount': network.totalEntryCount,
      'failureCount': network.failureCount,
      'entries': network.entries
          .where((entry) => entry.isFailure)
          .map((entry) => (entry.toJson()))
          .toList(growable: false),
      'endpointSummaries': network.endpointSummaries
          .where((summary) => summary.failureCount > 0)
          .map((summary) => (summary.toJson()))
          .toList(growable: false),
      'capturedEntryCount': network.capturedEntryCount,
      'inFlightCount': network.inFlightCount,
      'query': (network.query.toJson()),
      'truncated': network.truncated,
    };
  }

  final runtime = snapshot.runtime;
  if (runtime != null && runtime.errorCount > 0) {
    diagnostics['runtime'] = <String, Object?>{
      'totalEntryCount': runtime.totalEntryCount,
      'errorCount': runtime.errorCount,
      'warningCount': runtime.warningCount,
      'entries': runtime.entries
          .where((entry) => entry.isError)
          .map((entry) => (entry.toJson()))
          .toList(growable: false),
      'capturedEntryCount': runtime.capturedEntryCount,
      'query': (runtime.query.toJson()),
      'truncated': runtime.truncated,
    };
  }

  return diagnostics;
}

List<CockpitInteractiveArtifactDescriptor>
cockpitInteractiveArtifactsFromExecution(
  CockpitCommandExecution execution,
  CockpitInteractiveArtifactLevel artifactLevel,
) {
  if (artifactLevel == CockpitInteractiveArtifactLevel.none) {
    return const <CockpitInteractiveArtifactDescriptor>[];
  }
  return execution.result.artifacts
      .map(
        (artifact) => CockpitInteractiveArtifactDescriptor(
          role: artifact.role,
          relativePath: artifact.relativePath,
          byteLength: artifactLevel == CockpitInteractiveArtifactLevel.metadata
              ? _artifactByteLength(execution, artifact.relativePath)
              : null,
          sourcePath: artifactLevel == CockpitInteractiveArtifactLevel.metadata
              ? execution.artifactSourcePaths[artifact.relativePath]
              : null,
        ),
      )
      .toList(growable: false);
}

int? _artifactByteLength(
  CockpitCommandExecution execution,
  String relativePath,
) {
  final payload = execution.artifactPayloads[relativePath];
  if (payload != null) {
    return payload.length;
  }
  final sourcePath = execution.artifactSourcePaths[relativePath];
  if (sourcePath == null || sourcePath.isEmpty) {
    return null;
  }
  try {
    final file = File(sourcePath);
    return file.existsSync() ? file.lengthSync() : null;
  } on Object {
    return null;
  }
}
