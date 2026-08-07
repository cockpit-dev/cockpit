import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../capture/cockpit_screenshot_inspector.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_cli_runtime.dart';
import 'cockpit_dev_image_compare.dart';
import 'cockpit_dev_runtime.dart';

final class CockpitDevScreenshotService {
  CockpitDevScreenshotService(this.runtime, this.dev);

  final CockpitCliRuntime runtime;
  final CockpitDevRuntime dev;

  Future<int> capture({
    required String? sessionReference,
    required String? savePath,
    required String? baselinePath,
    required String? diffPath,
    required int pixelTolerance,
    required int maximumChangedPixels,
  }) async {
    var session = await runtime.resolveDevelopmentSession(sessionReference);
    final resolution = await dev.reconcile(session, allowRelaunch: false);
    if (!resolution.ready) {
      return dev.writeUnavailable(action: 'screenshot', resolution: resolution);
    }
    session = resolution.session;
    final platform = session.platform?.trim().toLowerCase();
    final systemFirst = platform == 'android' || platform == 'ios';
    final capture = await dev
        .invoke(session, 'evidence.screenshot.capture', <String, Object?>{
          'sessionId': session.sessionId,
          'name': 'dev-${DateTime.now().toUtc().microsecondsSinceEpoch}',
          'reason': 'acceptance',
          if (!systemFirst) 'captureProfile': 'flutterPreferred',
          'includeSnapshot': false,
          'attachToStep': false,
          'profile': 'standard',
        });
    if (!dev.operationSucceeded(capture)) {
      return dev.writeOperation(
        action: 'screenshot',
        session: session,
        result: capture,
        state: capture.output,
        changed: 'none',
      );
    }
    final reference = _pngArtifact(capture.output);
    if (reference == null) {
      throw const CockpitSupervisorClientException(
        code: 'screenshotArtifactMissing',
        message: 'Screenshot capture returned no session-owned PNG artifact.',
      );
    }
    final destination = savePath == null
        ? await _defaultDestination(session.handleId)
        : _pngPath(savePath, '--save');
    final receipt = await (await runtime.client())
        .downloadDevelopmentArtifactToFile(
          workspaceId: session.workspaceId,
          sessionId: session.sessionId,
          artifactId: reference.artifactId,
          mediaType: reference.mediaType,
          destination: File(destination),
        );
    final bytes = await receipt.file.readAsBytes();
    final inspection = await const CockpitImageScreenshotInspector().inspect(
      bytes,
      requireVisiblePixels: true,
    );
    final actualPath = p.normalize(await receipt.file.resolveSymbolicLinks());
    final actualEvidence = CockpitDevImageEvidence(
      path: actualPath,
      sizeBytes: receipt.sizeBytes,
      sha256: receipt.sha256,
      width: inspection.width,
      height: inspection.height,
    );
    CockpitDevImageComparison? comparison;
    if (baselinePath != null) {
      final resolvedDiff = diffPath == null
          ? p.join(
              p.dirname(actualPath),
              '${p.basenameWithoutExtension(actualPath)}.diff-'
              '${DateTime.now().toUtc().microsecondsSinceEpoch}.png',
            )
          : _pngPath(diffPath, '--diff');
      comparison = await const CockpitDevImageComparator().compare(
        actualPath: actualPath,
        baselinePath: baselinePath,
        diffPath: resolvedDiff,
        pixelTolerance: pixelTolerance,
        maximumChangedPixels: maximumChangedPixels,
      );
    }
    final errors = await dev.invoke(session, 'errors.read', <String, Object?>{
      'sessionId': session.sessionId,
      'maxErrors': 8,
    });
    final ok = dev.operationSucceeded(errors) && (comparison?.matched ?? true);
    final failures = <Object?>[
      ...dev.operationErrors(<CockpitOperationResult>[errors]),
      if (comparison != null && !comparison.matched)
        <String, Object?>{
          'code': 'visualComparisonFailed',
          'dimensionMismatch': comparison.dimensionMismatch,
          'changedPixelCount': comparison.changedPixelCount,
        },
    ];
    return dev.writeEnvelope(
      action: 'screenshot',
      session: session,
      ok: ok,
      state: <String, Object?>{
        ..._captureState(capture.output),
        'width': inspection.width,
        'height': inspection.height,
        if (comparison != null) 'comparison': comparison.toJson(),
        'runtimeErrors': errors.output,
      },
      changed: 'captured',
      evidence: <String, Object?>{
        'actual': actualEvidence.toJson(),
        if (comparison != null) ...<String, Object?>{
          'baseline': comparison.baseline.toJson(),
          'diff': comparison.diff.toJson(),
        },
      },
      errors: failures,
      next: ok ? null : 'cockpit dev diagnose',
      failureExitCode: cockpitDataExitCode,
    );
  }

  Future<String> _defaultDestination(String handleId) async {
    final home = CockpitHome.system();
    final paths = await home.initialize();
    final checkout = await runtime.checkoutIdentity();
    final directory = Directory(
      p.join(
        paths.artifactsDirectory,
        'development',
        checkout.value.substring(0, 16),
        handleId,
      ),
    );
    await directory.create(recursive: true);
    await home.permissionHardener.hardenDirectory(directory);
    return p.join(
      p.normalize(await directory.resolveSymbolicLinks()),
      'screenshot-${CockpitSecureTokenGenerator().nextResourceIdToken()}.png',
    );
  }
}

Map<String, Object?> _captureState(Object? output) {
  if (output is! Map<Object?, Object?>) return const <String, Object?>{};
  final command = output['command'];
  if (command is! Map<Object?, Object?>) return const <String, Object?>{};
  final fallback = command['usedCaptureFallback'];
  return <String, Object?>{
    if (command['resolvedCaptureKind'] != null)
      'capture': command['resolvedCaptureKind'],
    if (fallback is bool) 'fallback': fallback,
    if (command['degradationReason'] != null)
      'degraded': command['degradationReason'],
    if (output['selectedPlane'] != null) 'plane': output['selectedPlane'],
  };
}

({String artifactId, String mediaType})? _pngArtifact(Object? value) {
  ({String artifactId, String mediaType})? found;
  void visit(Object? candidate) {
    if (found != null) return;
    if (candidate case final Map<Object?, Object?> map) {
      final artifactId = map['artifactId'];
      final mediaType = map['mediaType'];
      if (artifactId is String && mediaType == 'image/png') {
        found = (artifactId: artifactId, mediaType: mediaType! as String);
        return;
      }
      for (final child in map.values) {
        visit(child);
      }
    } else if (candidate case final Iterable<Object?> items) {
      for (final item in items) {
        visit(item);
      }
    }
  }

  visit(value);
  return found;
}

String _pngPath(String value, String option) {
  final path = p.normalize(p.absolute(value));
  if (p.extension(path).toLowerCase() != '.png') {
    throw FormatException('$option must name a .png file.');
  }
  return path;
}
