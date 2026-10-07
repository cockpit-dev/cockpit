import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('cockpitRecorderSnapBallPosition', () {
    const Size bounds = Size(800, 600);
    const Size ball = Size(52, 52);

    test('docks to the nearer horizontal edge', () {
      expect(
        cockpitRecorderSnapBallPosition(const Offset(300, 100), bounds, ball),
        const Offset(0, 100),
      );
      expect(
        cockpitRecorderSnapBallPosition(const Offset(500, 100), bounds, ball),
        const Offset(748, 100),
      );
    });

    test('clamps vertically into bounds', () {
      expect(
        cockpitRecorderSnapBallPosition(const Offset(300, 700), bounds, ball),
        const Offset(0, 548),
      );
      expect(
        cockpitRecorderSnapBallPosition(const Offset(500, -20), bounds, ball),
        const Offset(748, 0),
      );
    });

    test('degrades to the origin when bounds are smaller than the ball', () {
      expect(
        cockpitRecorderSnapBallPosition(
          const Offset(10, 10),
          const Size(40, 40),
          ball,
        ),
        Offset.zero,
      );
    });
  });

  group('host', () {
    testWidgets('renders the collapsed ball and no sheet', (tester) async {
      final controller = newController();
      await tester.pumpWidget(
        CockpitRecorderScope(
          controller: controller,
          child: CockpitRecorderHost(controller: controller),
        ),
      );

      expect(find.byType(CockpitRecorderEntryButton), findsOneWidget);
      expect(find.byType(CockpitRecorderPanel), findsNothing);
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
      final controller = newController();
      await tester.pumpWidget(
        CockpitRecorderScope(
          controller: controller,
          child: CockpitRecorderHost(controller: controller),
        ),
      );
      final ball = find.byKey(const ValueKey<String>('cockpit_recorder_ball'));
      // Default test surface is 800x600: the ball starts docked right, 70% down.
      expect(tester.widget<AnimatedPositioned>(ball).left, 748.0);
      expect(tester.widget<AnimatedPositioned>(ball).top, 420.0);

      await tester.drag(ball, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedPositioned>(ball).left, 0.0);
      expect(tester.widget<AnimatedPositioned>(ball).top, 420.0);
    });

    testWidgets('drag keeps the ball within vertical bounds', (tester) async {
      final controller = newController();
      await tester.pumpWidget(
        CockpitRecorderScope(
          controller: controller,
          child: CockpitRecorderHost(controller: controller),
        ),
      );
      final ball = find.byKey(const ValueKey<String>('cockpit_recorder_ball'));

      await tester.drag(ball, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedPositioned>(ball).top, 548.0);
      expect(tester.widget<AnimatedPositioned>(ball).left, 748.0);
    });

    testWidgets('tap expands the panel sheet and close collapses it', (
      tester,
    ) async {
      final controller = newController();
      await tester.pumpWidget(
        CockpitRecorderScope(
          controller: controller,
          child: CockpitRecorderHost(controller: controller),
        ),
      );

      await tester.tap(find.byType(CockpitRecorderEntryButton));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cockpit_recorder_sheet')),
        findsOneWidget,
      );
      expect(find.byType(CockpitRecorderPanel), findsOneWidget);
      expect(find.text('no session'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cockpit_recorder_sheet')),
        findsNothing,
      );
      expect(find.byType(CockpitRecorderPanel), findsNothing);
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
      // Stack and renders its control area.
      expect(find.text('no session'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });
  });
}
