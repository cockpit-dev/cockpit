import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_visual_frame_driver.dart';
import 'package:flutter_test/flutter_test.dart';

// The remote snapshot path skips bindings whose runtimeType still reads as
// the framework test binding, so a locally named subclass keeps the
// automated test machinery while letting the production frame-wait code run.
class _RemoteSnapshotFrameBinding extends AutomatedTestWidgetsFlutterBinding {}

void main() {
  // Constructing the subclass registers it as the binding testWidgets uses.
  final binding = _RemoteSnapshotFrameBinding();

  tearDown(FlutterCockpit.dispose);

  testWidgets(
    'remote snapshot terminates while a visual-frame flight is parked frameless',
    (tester) async {
      // The dodged binding also lets the global runtime observer install its
      // debugPrint hook (normally suppressed under test bindings); it is
      // restored so framework invariants hold.
      final previousDebugPrint = debugPrint;
      try {
        FlutterCockpit.initialize(const FlutterCockpitConfiguration());
        final rootKey = GlobalKey<FlutterCockpitRootState>();
        await tester.pumpWidget(
          FlutterCockpitRoot(key: rootKey, child: const MaterialApp()),
        );
        await tester.pumpAndSettle();

        // Reproduces the wedged engine measured live: an occluded desktop
        // surface stops delivering vsync, so the shared visual-frame flight
        // is parked on a frame that will never be produced. Advancing the
        // clock below fires timers but never runs a frame.
        final wedgedFlight = ensureCockpitVisualFrame(
          platform: 'macos',
          force: true,
          budget: const Duration(milliseconds: 250),
          stallTimeout: const Duration(seconds: 20),
        );

        var completed = false;
        final snapshot = rootKey.currentState!
            .remoteSnapshot(options: const CockpitSnapshotOptions.live())
            .then((result) {
              completed = true;
              return result;
            });

        // No frame is ever delivered; the snapshot must still terminate.
        await binding.delayed(const Duration(seconds: 3));
        expect(completed, isTrue);

        final result = await snapshot;
        expect(result.degradationReason, 'frameTimeout');

        // Let the parked flight finish so no fake timer outlives the test.
        await binding.delayed(const Duration(seconds: 25));
        await wedgedFlight;
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );
}
