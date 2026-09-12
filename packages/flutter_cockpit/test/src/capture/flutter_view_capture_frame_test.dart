import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'view capture finishes when the in-flight frame never completes',
    (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundaryKey,
            child: const SizedBox(width: 32, height: 32),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reproduces the wedged engine measured live: a frame begins but its
      // draw phase never runs, so `endOfFrame` completes on no future frame.
      // runAsync gives the bounded wait real time to elapse; the unbounded
      // await of the old capture parked here forever.
      final shot = await tester.runAsync(() async {
        final binding = tester.binding;
        binding.handleBeginFrame(binding.currentSystemFrameTimeStamp);
        final captured = await const FlutterViewCapture().capture(
          repaintBoundaryKey: boundaryKey,
          request: const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.afterAction,
            name: 'wedged-frame',
          ),
        );
        binding.handleDrawFrame();
        return captured;
      });

      expect(shot, isNotNull);
      expect(shot!.bytes, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
