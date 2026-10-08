import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('CockpitRecorderEntryButton', () {
    testWidgets('invokes the onTap callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: CockpitRecorderEntryButton(onTap: () => taps += 1),
          ),
        ),
      );

      // The floating ball stays compact: 40x40 logical pixels.
      expect(
        tester.getSize(find.byType(CockpitRecorderEntryButton)),
        const Size(40, 40),
      );

      await tester.tap(find.byType(CockpitRecorderEntryButton));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('CockpitRecorderIndicator', () {
    testWidgets('reflects all four phases', (tester) async {
      final controller = newController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: CockpitRecorderIndicator(controller: controller)),
        ),
      );

      expect(find.text('IDLE'), findsOneWidget);

      controller.start();
      await tester.pump();
      expect(find.text('RECORDING'), findsOneWidget);

      controller.pause();
      await tester.pump();
      expect(find.text('PAUSED'), findsOneWidget);

      controller.stop();
      await tester.pump();
      expect(find.text('STOPPED'), findsOneWidget);
    });

    testWidgets('renders the dot only without a label', (tester) async {
      final controller = newController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: CockpitRecorderIndicator(
              controller: controller,
              showLabel: false,
            ),
          ),
        ),
      );

      expect(find.text('IDLE'), findsNothing);
    });

    testWidgets('ignores pointers so hits pass through', (tester) async {
      final controller = newController();
      var underlyingTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => underlyingTaps += 1,
                child: const SizedBox.expand(),
              ),
              Center(child: CockpitRecorderIndicator(controller: controller)),
            ],
          ),
        ),
      );

      // Tap right on the indicator: it must not absorb the hit.
      await tester.tap(
        find.byType(CockpitRecorderIndicator),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(underlyingTaps, 1);
    });
  });
}
