import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/executor/in_app/cockpit_capture_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'captureExplicit waits for observation readiness and applies default snapshot options',
    () async {
      var settleCount = 0;
      var idleWaitCount = 0;
      bool? includeNetworkIdle;
      CockpitScreenshotRequest? capturedRequest;
      final inspector = _RecordingScreenshotInspector();
      final orchestrator = CockpitCaptureOrchestrator(
        captureHandler: (request) async {
          capturedRequest = request;
          return CockpitCaptureResult(
            screenshot: CockpitCapturedScreenshot(
              artifact: const CockpitArtifactRef(
                role: 'screenshot',
                relativePath: 'screenshots/acceptance.png',
              ),
              bytes: Uint8List.fromList(const <int>[137, 80, 78, 71]),
            ),
            requestedProfile: CockpitCaptureProfile.acceptance,
            resolvedCaptureKind: CockpitCaptureKind.flutterView,
          );
        },
        postActionSettler: () async {},
        settleBeforeObservation: () async {
          settleCount += 1;
        },
        bestEffortWaitForUiIdle:
            ({required bool includeNetworkIdleValue}) async {
              idleWaitCount += 1;
              includeNetworkIdle = includeNetworkIdleValue;
            },
        defaultSnapshotOptionsForReason: (reason) {
          expect(reason, CockpitScreenshotReason.acceptance);
          return const CockpitSnapshotOptions.investigate();
        },
        screenshotInspector: inspector,
      );

      final outcome = await orchestrator.captureExplicit(
        CockpitCommand(
          commandId: 'cmd-capture',
          commandType: CockpitCommandType.captureScreenshot,
          screenshotRequest: const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: 'acceptance',
            includeSnapshot: true,
          ),
        ),
        waitForNetworkIdleDuringAcceptanceCapture: true,
      );

      expect(outcome, isNotNull);
      expect(settleCount, 0);
      expect(idleWaitCount, 1);
      expect(includeNetworkIdle, isTrue);
      expect(
        capturedRequest?.snapshotOptions,
        const CockpitSnapshotOptions.investigate(),
      );
      expect(
        outcome!.artifacts.single.relativePath,
        'screenshots/acceptance.png',
      );
      expect(
        outcome.artifactPayloads['screenshots/acceptance.png'],
        Uint8List.fromList(const <int>[137, 80, 78, 71]),
      );
      expect(inspector.inspectCount, 1);
      expect(inspector.requireVisiblePixels, isTrue);
    },
  );

  test(
    'captureAfterAction returns null when the command does not request capture',
    () async {
      final orchestrator = CockpitCaptureOrchestrator(
        captureHandler: (_) async => throw UnimplementedError(),
        postActionSettler: () async {},
        settleBeforeObservation: () async {},
        bestEffortWaitForUiIdle: ({required includeNetworkIdleValue}) async {},
        defaultSnapshotOptionsForReason: (_) =>
            const CockpitSnapshotOptions.live(),
      );

      final outcome = await orchestrator.captureAfterAction(
        CockpitCommand(
          commandId: 'cmd-tap',
          commandType: CockpitCommandType.tap,
          capturePolicy: CockpitCapturePolicy.none,
        ),
      );

      expect(outcome, isNull);
    },
  );

  test('captureExplicit rejects empty screenshot evidence', () async {
    final orchestrator = CockpitCaptureOrchestrator(
      captureHandler: (_) async => CockpitCaptureResult(
        screenshot: CockpitCapturedScreenshot(
          artifact: const CockpitArtifactRef(
            role: 'screenshot',
            relativePath: 'screenshots/empty.png',
          ),
          bytes: Uint8List(0),
        ),
        requestedProfile: CockpitCaptureProfile.acceptance,
        resolvedCaptureKind: CockpitCaptureKind.flutterView,
      ),
      postActionSettler: () async {},
      settleBeforeObservation: () async {},
      bestEffortWaitForUiIdle: ({required includeNetworkIdleValue}) async {},
      defaultSnapshotOptionsForReason: (_) =>
          const CockpitSnapshotOptions.live(),
    );

    await expectLater(
      orchestrator.captureExplicit(
        CockpitCommand(
          commandId: 'cmd-capture-empty',
          commandType: CockpitCommandType.captureScreenshot,
          screenshotRequest: const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: 'empty',
          ),
        ),
        waitForNetworkIdleDuringAcceptanceCapture: true,
      ),
      throwsA(
        isA<CockpitScreenshotValidationException>().having(
          (error) => error.code,
          'code',
          'screenshotEmpty',
        ),
      ),
    );
  });

  test('captureExplicit rejects malformed screenshot evidence', () async {
    final orchestrator = _orchestratorReturning(
      bytes: Uint8List.fromList(const <int>[0, 1, 2, 3]),
      reasonProfile: CockpitCaptureProfile.diagnostic,
    );

    await expectLater(
      orchestrator.captureExplicit(
        _captureCommand(
          reason: CockpitScreenshotReason.assertionFailure,
          name: 'malformed',
        ),
        waitForNetworkIdleDuringAcceptanceCapture: false,
      ),
      throwsA(
        isA<CockpitScreenshotValidationException>().having(
          (error) => error.code,
          'code',
          'screenshotDecodeFailed',
        ),
      ),
    );
  });

  test('transparent diagnostic screenshot evidence is accepted', () async {
    final orchestrator = _orchestratorReturning(
      bytes: _transparentPng,
      reasonProfile: CockpitCaptureProfile.diagnostic,
    );

    final outcome = await orchestrator.captureExplicit(
      _captureCommand(
        reason: CockpitScreenshotReason.assertionFailure,
        name: 'transparent-diagnostic',
      ),
      waitForNetworkIdleDuringAcceptanceCapture: false,
    );

    expect(
      outcome?.artifactPayloads['screenshots/transparent-diagnostic.png'],
      _transparentPng,
    );
  });

  test(
    'transparent acceptance screenshot fails before artifacts are returned',
    () async {
      final orchestrator = _orchestratorReturning(
        bytes: _transparentPng,
        reasonProfile: CockpitCaptureProfile.acceptance,
      );

      await expectLater(
        orchestrator.captureExplicit(
          _captureCommand(
            reason: CockpitScreenshotReason.acceptance,
            name: 'transparent-acceptance',
          ),
          waitForNetworkIdleDuringAcceptanceCapture: true,
        ),
        throwsA(
          isA<CockpitScreenshotValidationException>().having(
            (error) => error.code,
            'code',
            'screenshotFullyTransparent',
          ),
        ),
      );
    },
  );
}

final class _RecordingScreenshotInspector
    implements CockpitScreenshotInspector {
  int inspectCount = 0;
  bool? requireVisiblePixels;

  @override
  Future<CockpitScreenshotInspection> inspect(
    Uint8List bytes, {
    required bool requireVisiblePixels,
  }) async {
    inspectCount += 1;
    this.requireVisiblePixels = requireVisiblePixels;
    return const CockpitScreenshotInspection(width: 1, height: 1);
  }
}

CockpitCaptureOrchestrator _orchestratorReturning({
  required Uint8List bytes,
  required CockpitCaptureProfile reasonProfile,
}) {
  return CockpitCaptureOrchestrator(
    captureHandler: (request) async => CockpitCaptureResult(
      screenshot: CockpitCapturedScreenshot(
        artifact: CockpitArtifactRef(
          role: 'screenshot',
          relativePath: 'screenshots/${request.name}.png',
        ),
        bytes: bytes,
      ),
      requestedProfile: reasonProfile,
      resolvedCaptureKind: CockpitCaptureKind.flutterView,
    ),
    postActionSettler: () async {},
    settleBeforeObservation: () async {},
    bestEffortWaitForUiIdle: ({required includeNetworkIdleValue}) async {},
    defaultSnapshotOptionsForReason: (_) => const CockpitSnapshotOptions.live(),
  );
}

CockpitCommand _captureCommand({
  required CockpitScreenshotReason reason,
  required String name,
}) {
  return CockpitCommand(
    commandId: 'cmd-$name',
    commandType: CockpitCommandType.captureScreenshot,
    screenshotRequest: CockpitScreenshotRequest(reason: reason, name: name),
  );
}

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIAAAUAAeImBZsAAAAASUVORK5CYII=',
);
