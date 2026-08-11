import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../development/cockpit_development_probe.dart';
import '../development/cockpit_development_session_handle.dart';
import '../development/cockpit_development_session_reference_resolver.dart';
import '../foundation/cockpit_ids.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_collect_remote_snapshot_service.dart';

typedef CockpitDevelopmentProbeSnapshotCollector =
    Future<CockpitCollectRemoteSnapshotResult> Function(
      CockpitCollectRemoteSnapshotRequest request,
    );
typedef CockpitDevelopmentProbeScreenshotCollector =
    Future<CockpitDevelopmentProbeScreenshot?> Function(
      CockpitDevelopmentSessionHandle sessionHandle,
      CockpitDevelopmentProbeProfile profile,
    );

final class CockpitDevelopmentProbeScreenshot {
  const CockpitDevelopmentProbeScreenshot({
    required this.path,
    required this.byteCount,
    required this.digest,
    this.width,
    this.height,
  });

  final String path;
  final int byteCount;
  final String digest;
  final int? width;
  final int? height;
}

final class CockpitCollectDevelopmentProbeRequest {
  const CockpitCollectDevelopmentProbeRequest({
    this.sessionHandle,
    this.sessionHandlePath,
    required this.profile,
    this.reason = CockpitDevelopmentProbeReason.manual,
    this.checkpoint,
  });

  final CockpitDevelopmentSessionHandle? sessionHandle;
  final String? sessionHandlePath;
  final CockpitDevelopmentProbeProfile profile;
  final CockpitDevelopmentProbeReason reason;
  final String? checkpoint;
}

final class CockpitCollectDevelopmentProbeResult {
  const CockpitCollectDevelopmentProbeResult({
    required this.probe,
    required this.sessionHandle,
    required this.effectiveSnapshotOptions,
    this.warnings = const <String>[],
  });

  final CockpitDevelopmentProbe probe;
  final CockpitDevelopmentSessionHandle sessionHandle;
  final CockpitSnapshotOptions effectiveSnapshotOptions;
  final List<String> warnings;

  Map<String, Object?> toJson() => <String, Object?>{
    'probe': probe.toJson(),
    'sessionHandle': sessionHandle.toJson(),
    'effectiveSnapshotOptions': effectiveSnapshotOptions.toJson(),
    'warnings': warnings,
  };
}

final class CockpitCollectDevelopmentProbeService {
  CockpitCollectDevelopmentProbeService({
    CockpitDevelopmentProbeSnapshotCollector? collectRemoteSnapshot,
    CockpitDevelopmentSessionReferenceResolver? sessionReferenceResolver,
    CockpitDevelopmentProbeScreenshotCollector? collectScreenshot,
    CockpitTokenGenerator? tokenGenerator,
    DateTime Function()? now,
  }) : _collectRemoteSnapshot =
           collectRemoteSnapshot ??
           ((request) =>
               CockpitCollectRemoteSnapshotService().collect(request)),
       _sessionReferenceResolver =
           sessionReferenceResolver ??
           const CockpitDevelopmentSessionReferenceResolver(),
       _collectScreenshot = collectScreenshot,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _now = now ?? DateTime.now;

  final CockpitDevelopmentProbeSnapshotCollector _collectRemoteSnapshot;
  final CockpitDevelopmentSessionReferenceResolver _sessionReferenceResolver;
  final CockpitDevelopmentProbeScreenshotCollector? _collectScreenshot;
  final CockpitTokenGenerator _tokenGenerator;
  final DateTime Function() _now;

  Future<CockpitCollectDevelopmentProbeResult> collect(
    CockpitCollectDevelopmentProbeRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
    );
    final snapshotResult = await _collectRemoteSnapshot(
      CockpitCollectRemoteSnapshotRequest(
        baseUri: resolved.remoteBaseUri,
        options: _optionsForProfile(request.profile),
      ),
    );
    final screenshot = await (_collectScreenshot ?? _defaultCollectScreenshot)(
      resolved.sessionHandle!,
      request.profile,
    );
    final probe = _buildProbe(
      sessionHandle: resolved.sessionHandle!,
      profile: request.profile,
      reason: request.reason,
      checkpoint: request.checkpoint,
      snapshot: snapshotResult.snapshot,
      screenshot: screenshot,
    );
    return CockpitCollectDevelopmentProbeResult(
      probe: probe,
      sessionHandle: resolved.sessionHandle!,
      effectiveSnapshotOptions: snapshotResult.effectiveOptions,
      warnings: snapshotResult.warnings,
    );
  }

  CockpitDevelopmentProbe _buildProbe({
    required CockpitDevelopmentSessionHandle sessionHandle,
    required CockpitDevelopmentProbeProfile profile,
    required CockpitDevelopmentProbeReason reason,
    required String? checkpoint,
    required CockpitSnapshot snapshot,
    required CockpitDevelopmentProbeScreenshot? screenshot,
  }) {
    return CockpitDevelopmentProbe(
      probeId: _tokenGenerator.nextResourceId('q'),
      sessionId: sessionHandle.developmentSessionId,
      reloadGeneration: sessionHandle.reloadGeneration,
      capturedAt: _now().toUtc(),
      reason: reason,
      checkpoint: checkpoint,
      profile: profile,
      routeName: snapshot.routeName ?? '',
      ui: _buildUiSummary(snapshot),
      network: _buildNetworkSummary(snapshot.network),
      runtime: _buildRuntimeSummary(snapshot.runtime),
      rebuild: _buildRebuildSummary(snapshot.rebuild),
      artifacts: <String, Object?>{
        if (screenshot != null) ...<String, Object?>{
          'screenshotPath': screenshot.path,
          'screenshotByteCount': screenshot.byteCount,
          'screenshotDigest': screenshot.digest,
          if (screenshot.width != null) 'screenshotWidth': screenshot.width,
          if (screenshot.height != null) 'screenshotHeight': screenshot.height,
        },
        if (snapshot.diagnosticsArtifactRef != null)
          'diagnosticsArtifactPath':
              snapshot.diagnosticsArtifactRef!.relativePath,
      },
    );
  }

  Map<String, Object?> _buildUiSummary(CockpitSnapshot snapshot) {
    final accessibilityLabels = _uniqueNonEmpty(
      snapshot.accessibility?.traversalEntries.map(
            (entry) => entry.primarySignal,
          ) ??
          const Iterable<String?>.empty(),
    );
    return <String, Object?>{
      'visibleTextPreviews': _uniqueNonEmpty(
        snapshot.visibleTargets.expand(
          (target) => <String?>[
            target.text,
            target.content?.textPreview,
            target.content?.displayLabel,
          ],
        ),
      ),
      'visibleSemanticIds': _uniqueNonEmpty(
        snapshot.visibleTargets.map((target) => target.semanticId),
      ),
      'interactiveLabels': _uniqueNonEmpty(
        snapshot.visibleTargets
            .where((target) => target.supportedCommands.isNotEmpty)
            .map(_preferredInteractiveLabel),
      ),
      'focusedTargetLabel':
          snapshot.focus?.primaryFocusLabel ??
          _firstNonEmpty(
            snapshot.visibleTargets
                .where(_targetLooksFocused)
                .map((target) => target.displayLabel),
          ),
      'hasPrimaryFocus': snapshot.focus?.hasPrimaryFocus ?? false,
      'focusedWidgetType': snapshot.focus?.primaryFocusWidgetType,
      'hasTextInputFocus': snapshot.focus?.isTextInputFocus ?? false,
      'overlayLabels': _uniqueNonEmpty(
        snapshot.visibleTargets
            .where(_targetLooksLikeOverlay)
            .map((target) => target.displayLabel),
      ),
      'accessibilityLabels': accessibilityLabels,
      'visualSignals': _buildVisualSignals(snapshot),
      'visibleTargetCount': snapshot.visibleTargets.length,
      'accessibilityEntryCount':
          snapshot.accessibility?.traversalEntries.length ?? 0,
      'hasAccessibilitySummary': snapshot.accessibility != null,
      'truncated': snapshot.truncated,
    };
  }

  Map<String, Object?> _buildNetworkSummary(CockpitNetworkSnapshot? network) {
    if (network == null) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'totalEntryCount': network.totalEntryCount,
      'failureCount': network.failureCount,
      'inFlightCount': network.inFlightCount,
      'truncated': network.truncated,
      'failureSignals': network.entries
          .where((entry) => entry.isFailure)
          .map(_networkFailureSignal)
          .toList(growable: false),
    };
  }

  Map<String, Object?> _buildRuntimeSummary(CockpitRuntimeSnapshot? runtime) {
    if (runtime == null) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'totalEntryCount': runtime.totalEntryCount,
      'errorCount': runtime.errorCount,
      'warningCount': runtime.warningCount,
      'truncated': runtime.truncated,
      'errorSignals': runtime.entries
          .where((entry) => entry.isError)
          .map(_runtimeErrorSignal)
          .toList(growable: false),
    };
  }

  Map<String, Object?> _buildRebuildSummary(CockpitRebuildSnapshot? rebuild) {
    if (rebuild == null) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'totalRebuildCount': rebuild.totalRebuildCount,
      'uniqueElementCount': rebuild.uniqueElementCount,
      'truncated': rebuild.truncated,
      'hotspots': rebuild.entries
          .map((entry) => entry.signature)
          .toList(growable: false),
    };
  }

  CockpitSnapshotOptions _optionsForProfile(
    CockpitDevelopmentProbeProfile profile,
  ) {
    switch (profile) {
      case CockpitDevelopmentProbeProfile.quick:
        return const CockpitSnapshotOptions(
          profile: CockpitSnapshotProfile.live,
          maxTargets: 12,
          includeNetworkActivity: true,
          maxNetworkEntries: 4,
          includeRuntimeActivity: true,
          maxRuntimeEntries: 4,
          runtimeQuery: CockpitRuntimeQuery(onlyErrors: true),
        );
      case CockpitDevelopmentProbeProfile.interactive:
        return const CockpitSnapshotOptions(
          profile: CockpitSnapshotProfile.baseline,
          maxTargets: 24,
          maxAncestorsPerTarget: 1,
          maxPropertiesPerTarget: 4,
          includeNetworkActivity: true,
          maxNetworkEntries: 8,
          includeRuntimeActivity: true,
          maxRuntimeEntries: 8,
          runtimeQuery: CockpitRuntimeQuery(onlyErrors: true),
          includeRebuildActivity: true,
          maxRebuildEntries: 8,
          includeAccessibilitySummary: true,
        );
      case CockpitDevelopmentProbeProfile.diagnostic:
        return const CockpitSnapshotOptions.investigate();
      case CockpitDevelopmentProbeProfile.forensic:
        return const CockpitSnapshotOptions.forensic();
    }
  }

  Future<CockpitDevelopmentProbeScreenshot?> _defaultCollectScreenshot(
    CockpitDevelopmentSessionHandle sessionHandle,
    CockpitDevelopmentProbeProfile profile,
  ) async {
    if (profile == CockpitDevelopmentProbeProfile.quick) {
      return null;
    }
    final commandId = _tokenGenerator.nextResourceId('q');
    final response =
        await CockpitRemoteSessionClient(
          baseUri: sessionHandle.baseUri,
        ).executeDetailed(
          CockpitCommand(
            commandId: commandId,
            commandType: CockpitCommandType.captureScreenshot,
            screenshotRequest: CockpitScreenshotRequest(
              reason: CockpitScreenshotReason.afterAction,
              name:
                  'development_probe_${sessionHandle.developmentSessionId}_${profile.jsonValue}',
              includeSnapshot: false,
              attachToStep: false,
            ),
          ),
        );
    final artifact = response.result.artifacts.firstWhere(
      (candidate) =>
          candidate.role.contains('screenshot') ||
          candidate.relativePath.endsWith('.png'),
      orElse: () => const CockpitArtifactRef(role: '', relativePath: ''),
    );
    if (artifact.relativePath.isEmpty) {
      return null;
    }
    final bytes = response.artifactPayloads[artifact.relativePath];
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final outputDir = Directory(
      '${Directory.systemTemp.path}/flutter_cockpit_development_probes/${sessionHandle.developmentSessionId}',
    );
    await outputDir.create(recursive: true);
    final file = File('${outputDir.path}/$commandId.png');
    await file.writeAsBytes(bytes, flush: true);
    final dimensions = _readPngDimensions(bytes);
    return CockpitDevelopmentProbeScreenshot(
      path: file.path,
      byteCount: bytes.length,
      digest: 'fnv1a64:${_fnv1a64Hex(bytes)}',
      width: dimensions?.$1,
      height: dimensions?.$2,
    );
  }

  static List<String> _buildVisualSignals(CockpitSnapshot snapshot) {
    return snapshot.visibleTargets
        .map(_visualSignalForTarget)
        .whereType<String>()
        .toList(growable: false);
  }

  static String? _visualSignalForTarget(CockpitSnapshotTarget target) {
    final layout = target.layout;
    final style = target.style;
    final label = _firstNonEmpty(<String?>[
      target.displayLabel,
      target.semanticId,
      target.registrationId,
    ]);
    if (label == null && layout == null && style == null) {
      return null;
    }
    final parts = <String>[
      target.typeName ?? '',
      label ?? '',
      if (layout != null)
        '${layout.dx.toStringAsFixed(1)},${layout.dy.toStringAsFixed(1)},${layout.width.toStringAsFixed(1)}x${layout.height.toStringAsFixed(1)}',
      if (style?.textColor != null) style!.textColor!,
      if (style?.backgroundColor != null) style!.backgroundColor!,
      if (style?.fontSize != null) style!.fontSize!.toStringAsFixed(1),
      if (style?.fontWeight != null) style!.fontWeight!,
      if (style?.borderSummary != null) style!.borderSummary!,
      if (style?.shadowSummary != null) style!.shadowSummary!,
    ];
    return parts.join('|');
  }

  static (int, int)? _readPngDimensions(List<int> bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24) {
      return null;
    }
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) {
        return null;
      }
    }
    final width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return (width, height);
  }

  static String _fnv1a64Hex(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _networkFailureSignal(CockpitNetworkEntry entry) {
    final status = entry.statusCode == null ? 'error' : '${entry.statusCode}';
    final suffix = entry.error == null ? status : '$status ${entry.error}';
    return '${entry.method} ${entry.uri} -> $suffix';
  }

  static String _runtimeErrorSignal(CockpitRuntimeEvent entry) {
    final normalizedKind = switch (entry.kind) {
      CockpitRuntimeEventKind.flutterError => 'flutterError',
      CockpitRuntimeEventKind.uncaughtError => 'uncaughtError',
      CockpitRuntimeEventKind.debugLog => 'debugLog',
    };
    return '$normalizedKind:${entry.severity.jsonValue}:${entry.message}';
  }

  static bool _targetLooksFocused(CockpitSnapshotTarget target) {
    return target.diagnosticProperties.any((property) {
      final name = property.name.toLowerCase();
      final value = property.value.toLowerCase();
      return name.contains('focus') &&
          (value == 'true' || value == 'yes' || value.contains('focused'));
    });
  }

  static String? _preferredInteractiveLabel(CockpitSnapshotTarget target) {
    return _firstNonEmpty(<String?>[
      target.text,
      target.content?.textPreview,
      target.content?.displayLabel,
      target.tooltip,
      target.semanticId,
      target.cockpitId,
      target.keyValue,
      target.typeName,
    ]);
  }

  static bool _targetLooksLikeOverlay(CockpitSnapshotTarget target) {
    final names = <String?>[
      target.typeName,
      ...target.ancestors.map((ancestor) => ancestor.typeName),
    ].whereType<String>();
    return names.any((name) {
      final normalized = name.toLowerCase();
      return normalized.contains('dialog') ||
          normalized.contains('sheet') ||
          normalized.contains('drawer') ||
          normalized.contains('popup');
    });
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  static List<String> _uniqueNonEmpty(Iterable<String?> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      result.add(normalized);
    }
    return List<String>.unmodifiable(result);
  }
}
