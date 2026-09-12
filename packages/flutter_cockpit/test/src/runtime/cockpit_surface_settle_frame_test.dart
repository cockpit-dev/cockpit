import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_visual_frame_driver.dart';
import 'package:flutter_test/flutter_test.dart';

// The settle path skips bindings whose runtimeType still reads as the
// framework test binding, so a locally named subclass keeps the automated
// test machinery while letting the production frame-wait code run.
class _SettleFrameBinding extends AutomatedTestWidgetsFlutterBinding {}

void main() {
  // Constructing the subclass registers it as the binding testWidgets uses.
  final binding = _SettleFrameBinding();

  testWidgets(
    'scrollByViewport settles without a delivered frame while a visual-frame flight is parked',
    (tester) async {
      // The dodged binding also lets the global runtime observer install its
      // debugPrint hook (normally suppressed under test bindings); both it and
      // the platform override are restored so framework invariants hold.
      final previousDebugPrint = debugPrint;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _runWedgedFrameScrollScenario(binding, tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        debugPrint = previousDebugPrint;
      }
    },
  );
}

Future<void> _runWedgedFrameScrollScenario(
  _SettleFrameBinding binding,
  WidgetTester tester,
) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: CockpitSurface(
        routeName: '/wedged-frame',
        child: Material(
          child: ListView.builder(
            key: const ValueKey<String>('wedged-scrollable'),
            controller: controller,
            itemCount: 40,
            itemBuilder: (context, index) => SizedBox(
              height: 96,
              child: ListTile(title: Text('Task $index')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Reproduces the wedged engine measured live: an occluded desktop surface
  // stops delivering vsync, so the shared visual-frame flight is parked on a
  // frame that will never be produced. Advancing the clock below fires
  // timers but never runs a frame, exactly like the stalled engine.
  final wedgedFlight = ensureCockpitVisualFrame(
    platform: 'macos',
    force: true,
    budget: const Duration(milliseconds: 250),
    stallTimeout: const Duration(seconds: 20),
  );

  final surfaceState = tester.state<CockpitSurfaceState>(
    find.byType(CockpitSurface),
  );
  var settled = false;
  final scroll = surfaceState
      .scrollByViewport(
        viewportFraction: 0.8,
        duration: Duration.zero,
        scrollableKey: 'wedged-scrollable',
        targetLocator: const CockpitLocator(text: 'Task 12'),
      )
      .then((result) {
        settled = true;
        return result;
      });

  // No frame is ever delivered; the op must still terminate promptly.
  await binding.delayed(const Duration(seconds: 3));
  expect(settled, isTrue);

  final result = await scroll;
  expect(result.didScroll, isTrue);
  expect(controller.offset, greaterThan(0));

  // Let the parked flight finish so no fake timer outlives the test.
  await binding.delayed(const Duration(seconds: 25));
  await wedgedFlight;
}
