import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('cockpitRecorderSnapBallPosition', () {
    const Size bounds = Size(800, 600);
    const Size ball = Size(40, 40);

    test('docks to the nearer horizontal edge', () {
      expect(
        cockpitRecorderSnapBallPosition(const Offset(300, 100), bounds, ball),
        const Offset(0, 100),
      );
      expect(
        cockpitRecorderSnapBallPosition(const Offset(500, 100), bounds, ball),
        const Offset(760, 100),
      );
    });

    test('an exact horizontal center docks right (strictly-less tie)', () {
      // The ball center sits exactly at the bounds middle: docksLeft is
      // strictly-less, so the tie resolves to the right edge.
      expect(
        cockpitRecorderSnapBallPosition(const Offset(380, 100), bounds, ball),
        const Offset(760, 100),
      );
      expect(
        cockpitRecorderSnapBallPosition(const Offset(379.9, 100), bounds, ball),
        const Offset(0, 100),
      );
    });

    test('clamps vertically into bounds', () {
      expect(
        cockpitRecorderSnapBallPosition(const Offset(300, 700), bounds, ball),
        const Offset(0, 560),
      );
      expect(
        cockpitRecorderSnapBallPosition(const Offset(500, -20), bounds, ball),
        const Offset(760, 0),
      );
    });

    test('degrades to the origin when bounds are smaller than the ball', () {
      expect(
        cockpitRecorderSnapBallPosition(
          const Offset(10, 10),
          const Size(30, 30),
          ball,
        ),
        Offset.zero,
      );
      // A zero-size bound docks at the origin whatever the input.
      expect(
        cockpitRecorderSnapBallPosition(
          const Offset(500, 500),
          Size.zero,
          ball,
        ),
        Offset.zero,
      );
    });
  });

  group('host', () {
    Future<void> pumpHost(WidgetTester tester) async {
      final controller = newController();
      await tester.pumpWidget(
        CockpitRecorderScope(
          controller: controller,
          child: CockpitRecorderHost(controller: controller),
        ),
      );
    }

    testWidgets('renders the collapsed 40x40 ball and no panel', (
      tester,
    ) async {
      await pumpHost(tester);

      expect(find.byType(CockpitRecorderEntryButton), findsOneWidget);
      expect(find.byType(CockpitRecorderPanel), findsNothing);
      expect(
        tester.getSize(
          find.byKey(const ValueKey<String>('cockpit_recorder_ball')),
        ),
        const Size(40, 40),
      );
      expect(
        tester.getSize(find.byType(CockpitRecorderEntryButton)),
        const Size(40, 40),
      );
      // The exclude marker wraps the host chrome (tier a, belt-and-braces:
      // the host also sits beside the capture subtree in the root stack).
      expect(
        find.byWidgetPredicate((widget) => widget is CockpitRecorderExclude),
        findsOneWidget,
      );
      expect(
        find.byElementPredicate(
          (element) => element.widget is CockpitRecorderExclude,
        ),
        findsOneWidget,
      );
    });

    testWidgets('drag repositions the ball and docks it to the edge', (
      tester,
    ) async {
      await pumpHost(tester);
      final ball = find.byKey(const ValueKey<String>('cockpit_recorder_ball'));
      // Default test surface is 800x600: the ball starts docked right, 70% down.
      expect(tester.widget<AnimatedPositioned>(ball).left, 760.0);
      expect(tester.widget<AnimatedPositioned>(ball).top, 420.0);

      await tester.drag(ball, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedPositioned>(ball).left, 0.0);
      expect(tester.widget<AnimatedPositioned>(ball).top, 420.0);
    });

    testWidgets('drag keeps the ball within vertical bounds', (tester) async {
      await pumpHost(tester);
      final ball = find.byKey(const ValueKey<String>('cockpit_recorder_ball'));

      await tester.drag(ball, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedPositioned>(ball).top, 560.0);
      expect(tester.widget<AnimatedPositioned>(ball).left, 760.0);
    });

    testWidgets('drag up docks at the top edge', (tester) async {
      await pumpHost(tester);
      final ball = find.byKey(const ValueKey<String>('cockpit_recorder_ball'));

      await tester.drag(ball, const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedPositioned>(ball).top, 0.0);
      expect(tester.widget<AnimatedPositioned>(ball).left, 760.0);
    });

    testWidgets('a small wiggle still taps; a real drag does not', (
      tester,
    ) async {
      await pumpHost(tester);
      final ball = find.byKey(const ValueKey<String>('cockpit_recorder_ball'));
      final fullscreen = find.byKey(
        const ValueKey<String>('cockpit_recorder_fullscreen'),
      );

      // Below the touch slop the tap recognizer wins the arena.
      final wiggle = await tester.startGesture(tester.getCenter(ball));
      await tester.pump();
      await wiggle.moveBy(const Offset(3, 0));
      await tester.pump();
      await wiggle.up();
      await tester.pumpAndSettle();

      expect(fullscreen, findsOneWidget);

      // Close, then drag well past the slop: the pan recognizer wins and
      // the panel stays closed.
      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();
      expect(fullscreen, findsNothing);

      final drag = await tester.startGesture(tester.getCenter(ball));
      await tester.pump();
      await drag.moveBy(const Offset(-60, 0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(fullscreen, findsNothing);
      // The pan happened (still right of center, so it re-docked right).
      expect(tester.widget<AnimatedPositioned>(ball).left, 760.0);
    });

    testWidgets('the host subtree installs the exclusion marker object', (
      tester,
    ) async {
      await pumpHost(tester);

      final marker = tester.renderObject<RenderObject>(
        find.byType(CockpitRecorderExclude),
      );
      expect(marker, isA<CockpitRecorderExcludeRenderObject>());
    });

    testWidgets('tap expands the full-screen panel and close collapses it', (
      tester,
    ) async {
      await pumpHost(tester);

      await tester.tap(find.byType(CockpitRecorderEntryButton));
      await tester.pumpAndSettle();

      final fullscreen = find.byKey(
        const ValueKey<String>('cockpit_recorder_fullscreen'),
      );
      expect(fullscreen, findsOneWidget);
      // The overlay occupies the whole window — no partial card.
      expect(tester.getRect(fullscreen), const Rect.fromLTWH(0, 0, 800, 600));
      expect(find.byType(CockpitRecorderPanel), findsOneWidget);
      expect(find.text('no session'), findsOneWidget);

      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();

      expect(fullscreen, findsNothing);
      expect(find.byType(CockpitRecorderPanel), findsNothing);
    });

    testWidgets('caps the panel width and centers it on ultra-wide windows', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpHost(tester);

      await tester.tap(find.byType(CockpitRecorderEntryButton));
      await tester.pumpAndSettle();

      // The content column centers at max 840 logical pixels wide.
      expect(
        tester.getRect(find.byType(CockpitRecorderPanel)),
        const Rect.fromLTWH(540, 0, 840, 1080),
      );
      // The backdrop behind it still fills the whole window.
      expect(
        tester.getRect(
          find.byKey(const ValueKey<String>('cockpit_recorder_fullscreen')),
        ),
        const Rect.fromLTWH(0, 0, 1920, 1080),
      );
    });
  });

  group('root wiring', () {
    tearDown(FlutterCockpit.dispose);

    Future<FlutterCockpitRootState> pumpRootApp(
      WidgetTester tester, {
      CockpitRecorderHostMode host = CockpitRecorderHostMode.floatingBall,
      Widget? child,
    }) async {
      FlutterCockpit.initialize(
        FlutterCockpitConfiguration(
          recorder: FlutterCockpitRecorderConfig(enabled: true, host: host),
        ),
      );
      final rootKey = GlobalKey<FlutterCockpitRootState>();
      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child:
              child ??
              const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();
      return rootKey.currentState!;
    }

    testWidgets('floatingBall mounts the host and the scope', (tester) async {
      final root = await pumpRootApp(tester);

      expect(find.byType(CockpitRecorderHost), findsOneWidget);
      expect(find.byType(CockpitRecorderEntryButton), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is CockpitRecorderScope),
        findsOneWidget,
      );
      expect(root.recorderController, isNotNull);
    });

    testWidgets('guest and headless mount no HUD', (tester) async {
      await pumpRootApp(tester, host: CockpitRecorderHostMode.guest);
      expect(find.byType(CockpitRecorderHost), findsNothing);
      expect(find.byType(CockpitRecorderEntryButton), findsNothing);

      await pumpRootApp(tester, host: CockpitRecorderHostMode.headless);
      expect(find.byType(CockpitRecorderHost), findsNothing);
      expect(find.byType(CockpitRecorderEntryButton), findsNothing);
    });

    testWidgets('guest mode serves an app-embedded panel via the scope', (
      tester,
    ) async {
      await pumpRootApp(
        tester,
        host: CockpitRecorderHostMode.guest,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 480,
                height: 640,
                child: CockpitRecorderPanel(),
              ),
            ),
          ),
        ),
      );

      // The panel resolves the controller from the scope above the root
      // Stack and renders its header and control row without a close
      // button (nothing to collapse in an embedded host).
      expect(find.text('no session'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('✕'), findsNothing);
    });
  });
}
