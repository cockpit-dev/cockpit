import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'captures a screenshot from CockpitSurface and attaches it to session data',
    (tester) async {
      final controller = CockpitSessionController(
        sessionId: 'capture-session',
        taskId: 'capture-task',
        platform: 'android',
      );

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitSurface(
            routeName: '/home',
            child: Center(child: Text('Cockpit Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final capture = await tester.runAsync(() {
        return surfaceState.captureScreenshot(
          const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: 'home-screen',
            includeSnapshot: true,
            attachToStep: true,
          ),
        );
      });
      expect(capture, isNotNull);
      final screenshot = capture!;

      controller.recordStep(
        actionType: 'capture_home',
        actionArgs: const {'target': 'home'},
        observation: CockpitObservation(
          routeName: screenshot.snapshot?.routeName,
          interactiveElements:
              screenshot.snapshot?.visibleTargets
                  .map((target) => target.displayLabel)
                  .whereType<String>()
                  .toList(growable: false) ??
              const <String>[],
          phase: CockpitObservationPhase.afterAction,
        ),
        artifactRefs: [screenshot.artifact],
        captureRefs: [screenshot.artifact],
        commandType: CockpitCommandType.captureScreenshot,
        status: CockpitCommandStatus.succeeded,
      );

      final bundle = controller.finish(
        environment: const CockpitEnvironment(
          platform: 'android',
          flutterVersion: '3.38.9',
          dartVersion: '3.10.8',
        ),
        capabilitiesUsed: const ['flutterViewCapture'],
      );

      expect(screenshot.bytes.length, greaterThan(8));
      expect(screenshot.artifact.relativePath, endsWith('.png'));
      expect(bundle.manifest.screenshotCount, 1);
      expect(bundle.steps.single.captureRefs.single, screenshot.artifact);
    },
  );

  testWidgets('crops Flutter-view screenshots to a resolved locator', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CockpitSurface(
          routeName: '/home',
          child: Center(
            child: Semantics(
              key: ValueKey<String>('crop-target'),
              label: 'Crop target',
              child: SizedBox(
                width: 120,
                height: 60,
                child: ColoredBox(color: Color(0xff245f9e)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final screenshot = await tester.runAsync(
      () => surfaceState.captureScreenshot(
        const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.baseline,
          name: 'crop-target',
          cropLocator: CockpitLocator(key: 'crop-target'),
        ),
      ),
    );

    expect(_pngSize(screenshot!.bytes), (120, 60));
  });
}

(int, int) _pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
