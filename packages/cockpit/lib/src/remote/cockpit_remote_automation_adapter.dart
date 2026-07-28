import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../adapters/cockpit_automation_adapter.dart';
import '../system_control/cockpit_visual_matcher.dart';
import 'cockpit_remote_session_client.dart';

final class CockpitRemoteAutomationAdapter implements CockpitAutomationAdapter {
  CockpitRemoteAutomationAdapter({
    required CockpitRemoteSessionClient client,
    required String workspaceRoot,
    CockpitVisualMatcher? visualMatcher,
  }) : _client = client,
       _visualMatcher =
           visualMatcher ?? CockpitVisualMatcher(workspaceRoot: workspaceRoot);

  final CockpitRemoteSessionClient _client;
  final CockpitVisualMatcher _visualMatcher;

  @override
  Future<CockpitCapabilities> describeCapabilities() async {
    final capabilities = (await _client.readStatus()).capabilities;
    if (!capabilities.supportsFlutterViewCapture ||
        !capabilities.supportedCommands.contains(
          CockpitCommandType.captureScreenshot,
        )) {
      return capabilities;
    }
    return CockpitCapabilities(
      platform: capabilities.platform,
      transportType: capabilities.transportType,
      supportsInAppControl: capabilities.supportsInAppControl,
      supportsFlutterViewCapture: capabilities.supportsFlutterViewCapture,
      supportsNativeScreenCapture: capabilities.supportsNativeScreenCapture,
      supportsHostAutomation: capabilities.supportsHostAutomation,
      supportedCommands: <CockpitCommandType>{
        ...capabilities.supportedCommands,
        CockpitCommandType.assertScreenshot,
      }.toList(growable: false),
      supportedLocatorStrategies: capabilities.supportedLocatorStrategies,
      capabilityProfile: capabilities.capabilityProfile,
    );
  }

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) {
    if (command.commandType == CockpitCommandType.assertScreenshot) {
      return _assertScreenshot(command);
    }
    return _client.executeDetailed(command);
  }

  Future<CockpitCommandExecution> _assertScreenshot(
    CockpitCommand command,
  ) async {
    final stopwatch = Stopwatch()..start();
    final baseline = command.parameters['baseline'];
    if (baseline is! String || baseline.trim().isEmpty) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError(
          code: 'invalidScreenshotBaseline',
          message: 'assertScreenshot requires a non-empty baseline path.',
        ),
      );
    }
    final pixelTolerance =
        (command.parameters['pixelTolerance'] as num?)?.toDouble() ?? 0.1;
    final maxDifferingPixelRatio =
        (command.parameters['maxDifferingPixelRatio'] as num?)?.toDouble() ??
        0.01;
    final stem = _artifactStem(
      command.parameters['name'] as String? ??
          command.parameters['artifactName'] as String? ??
          command.commandId,
    );
    final configuredCapture = command.screenshotRequest;
    final capture = await _client.executeDetailed(
      command.copyWith(
        commandType: CockpitCommandType.captureScreenshot,
        parameters: <String, Object?>{'name': '$stem-actual'},
        screenshotRequest: CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.baseline,
          name: '$stem-actual',
          includeSnapshot:
              configuredCapture?.includeSnapshot ?? command.locator != null,
          attachToStep: configuredCapture?.attachToStep ?? true,
          snapshotOptions: configuredCapture?.snapshotOptions,
          profile:
              configuredCapture?.profile ??
              CockpitCaptureProfile.flutterPreferred,
          allowFallback: configuredCapture?.allowFallback ?? false,
          cropLocator: configuredCapture?.cropLocator ?? command.locator,
        ),
      ),
    );
    if (!capture.result.success) {
      return CockpitCommandExecution(
        result: CockpitCommandResult(
          success: false,
          commandId: command.commandId,
          commandType: command.commandType,
          durationMs: stopwatch.elapsedMilliseconds,
          artifacts: capture.result.artifacts,
          snapshot: capture.result.snapshot,
          requestedCaptureProfile: capture.result.requestedCaptureProfile,
          resolvedCaptureKind: capture.result.resolvedCaptureKind,
          usedCaptureFallback: capture.result.usedCaptureFallback,
          degradationReason: capture.result.degradationReason,
          error: capture.result.error,
        ),
        artifactPayloads: capture.artifactPayloads,
        artifactSourcePaths: capture.artifactSourcePaths,
        runtimeSteps: capture.runtimeSteps,
      );
    }
    CockpitArtifactRef? actualArtifact;
    for (final artifact in capture.result.artifacts) {
      if (artifact.role == 'screenshot') {
        actualArtifact = artifact;
        break;
      }
    }
    if (actualArtifact == null) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError(
          code: 'screenshotArtifactMissing',
          message: 'Flutter screenshot capture returned no image artifact.',
        ),
      );
    }

    Directory? temporaryDirectory;
    var actualSourcePath =
        capture.artifactSourcePaths[actualArtifact.relativePath];
    if (actualSourcePath == null) {
      final payload = capture.artifactPayloads[actualArtifact.relativePath];
      if (payload == null) {
        return _failure(
          command,
          stopwatch,
          CockpitCommandError(
            code: 'screenshotArtifactUnreadable',
            message: 'Flutter screenshot artifact bytes are unavailable.',
          ),
        );
      }
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'cockpit-visual-',
      );
      final file = File(p.join(temporaryDirectory.path, 'actual.png'));
      await file.writeAsBytes(payload, flush: true);
      actualSourcePath = file.path;
    }

    try {
      final comparison = await _visualMatcher.compareScreenshot(
        screenshotPath: actualSourcePath,
        baselineReference: baseline,
        pixelTolerance: pixelTolerance,
        maxDifferingPixelRatio: maxDifferingPixelRatio,
      );
      final baselinePath =
          'visual/$stem-baseline${p.extension(comparison.baselineSourcePath)}';
      final actualPath = 'visual/$stem-actual.png';
      final diffPath = 'visual/$stem-diff.png';
      final snapshot = <String, Object?>{
        'adapter': 'flutterViewVisual',
        'matchingPixelRatio': comparison.matchingPixelRatio,
        'differingPixelRatio': comparison.differingPixelRatio,
        'differingPixelCount': comparison.differingPixelCount,
        'totalPixelCount': comparison.totalPixelCount,
        'pixelTolerance': comparison.pixelTolerance,
        'maxDifferingPixelRatio': comparison.maxDifferingPixelRatio,
        'captureScope': command.locator == null
            ? capture.result.resolvedCaptureKind?.name ?? 'unknown'
            : 'element',
        'actualSize': <String, Object?>{
          'width': comparison.width,
          'height': comparison.height,
        },
        'baselineSize': <String, Object?>{
          'width': comparison.baselineWidth,
          'height': comparison.baselineHeight,
        },
        'dimensionMismatch': comparison.dimensionMismatch,
      };
      return CockpitCommandExecution(
        result: CockpitCommandResult(
          success: comparison.matched,
          commandId: command.commandId,
          commandType: command.commandType,
          durationMs: stopwatch.elapsedMilliseconds,
          artifacts: <CockpitArtifactRef>[
            ...capture.result.artifacts.where(
              (artifact) =>
                  artifact.relativePath != actualArtifact!.relativePath,
            ),
            CockpitArtifactRef(
              role: 'screenshotActual',
              relativePath: actualPath,
            ),
            CockpitArtifactRef(
              role: 'screenshotBaseline',
              relativePath: baselinePath,
            ),
            CockpitArtifactRef(role: 'screenshotDiff', relativePath: diffPath),
          ],
          snapshot: snapshot,
          requestedCaptureProfile: capture.result.requestedCaptureProfile,
          resolvedCaptureKind: capture.result.resolvedCaptureKind,
          usedCaptureFallback: capture.result.usedCaptureFallback,
          degradationReason: capture.result.degradationReason,
          error: comparison.matched
              ? null
              : CockpitCommandError.assertionFailed(
                  message: comparison.dimensionMismatch
                      ? 'Screenshot dimensions do not match the baseline profile.'
                      : 'Too many screenshot pixels differ from the baseline.',
                  details: snapshot,
                ),
        ),
        artifactPayloads: <String, List<int>>{
          for (final entry in capture.artifactPayloads.entries)
            if (entry.key != actualArtifact.relativePath)
              entry.key: entry.value,
          actualPath: comparison.actualPng,
          diffPath: comparison.diffPng,
        },
        artifactSourcePaths: <String, String>{
          for (final entry in capture.artifactSourcePaths.entries)
            if (entry.key != actualArtifact.relativePath)
              entry.key: entry.value,
          baselinePath: comparison.baselineSourcePath,
        },
        runtimeSteps: capture.runtimeSteps,
      );
    } on Object catch (error) {
      return _failure(
        command,
        stopwatch,
        CockpitCommandError(
          code: 'visualComparisonFailed',
          message: 'Flutter screenshot comparison failed: $error',
        ),
      );
    } finally {
      await temporaryDirectory?.delete(recursive: true);
    }
  }

  CockpitCommandExecution _failure(
    CockpitCommand command,
    Stopwatch stopwatch,
    CockpitCommandError error,
  ) => CockpitCommandExecution(
    result: CockpitCommandResult(
      success: false,
      commandId: command.commandId,
      commandType: command.commandType,
      durationMs: stopwatch.elapsedMilliseconds,
      error: error,
    ),
  );
}

String _artifactStem(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
    RegExp('[^a-z0-9._-]+'),
    '-',
  );
  return normalized.isEmpty ? 'screenshot' : normalized;
}
