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
    final threshold =
        (command.parameters['similarity'] as num?)?.toDouble() ?? 0.99;
    final stem = _artifactStem(
      command.parameters['name'] as String? ??
          command.parameters['artifactName'] as String? ??
          command.commandId,
    );
    final capture = await _client.executeDetailed(
      command.copyWith(
        commandType: CockpitCommandType.captureScreenshot,
        parameters: <String, Object?>{'name': '$stem-actual'},
        screenshotRequest: CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.baseline,
          name: '$stem-actual',
          profile: CockpitCaptureProfile.flutterPreferred,
          allowFallback: false,
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
        threshold: threshold,
      );
      final baselinePath =
          'visual/$stem-baseline${p.extension(comparison.baselineSourcePath)}';
      final diffPath = 'visual/$stem-diff.png';
      final snapshot = <String, Object?>{
        'adapter': 'flutterViewVisual',
        'similarity': comparison.similarity,
        'requiredSimilarity': threshold,
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
            ...capture.result.artifacts,
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
                      : 'Screenshot similarity is below the required threshold.',
                  details: snapshot,
                ),
        ),
        artifactPayloads: <String, List<int>>{
          ...capture.artifactPayloads,
          diffPath: comparison.diffPng,
        },
        artifactSourcePaths: <String, String>{
          ...capture.artifactSourcePaths,
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
