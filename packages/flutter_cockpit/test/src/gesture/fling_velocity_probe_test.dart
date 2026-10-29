import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cockpit/src/gesture/cockpit_gesture_action.dart';
import 'package:flutter_cockpit/src/gesture/cockpit_gesture_engine.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_target.dart';

CockpitTarget _targetFor(WidgetTester tester, String keyValue) {
  final element = tester.element(find.byKey(ValueKey<String>(keyValue)));
  return CockpitTarget(
    registrationId: keyValue,
    keyValue: keyValue,
    routeName: '/',
    diagnosticNodeProvider: () => element,
  );
}

void main() {
  group('fling release velocity', () {
    // A fling that carries no explicit velocity keeps the historical
    // behaviour: the up shares the final move's timestamp and the tracker
    // reports a near-zero release velocity.
    for (final entry in <double, bool>{
      900: true,
      2000: true,
      8000: true,
    }.entries) {
      testWidgets(
        'velocity ${entry.key.toInt()} reaches the app above the fling floor',
        (t) async {
          Offset? panEnd;
          await t.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: GestureDetector(
                  key: const ValueKey<String>('fling-target'),
                  behavior: HitTestBehavior.opaque,
                  onPanEnd: (d) => panEnd = d.velocity.pixelsPerSecond,
                  child: const SizedBox(width: 400, height: 800),
                ),
              ),
            ),
          );
          await t.pump();
          final engine = CockpitGestureEngine(delay: t.pump);
          await engine.perform(
            CockpitGestureAction.fling(
              target: _targetFor(t, 'fling-target'),
              delta: const Offset(0, -700),
              duration: const Duration(milliseconds: 350),
              moveEventCount: 10,
              velocity: entry.key,
            ),
          );
          await t.pumpAndSettle();
          expect(panEnd, isNotNull);
          expect(
            panEnd!.dy,
            lessThan(0),
            reason: 'upward fling reports negative dy',
          );
          expect(
            panEnd!.dy.abs(),
            greaterThan(800),
            reason:
                'requested velocity should clear the fling floor, not read zero',
          );
        },
      );
    }

    testWidgets('a velocity-less fling still completes cleanly', (t) async {
      var endCount = 0;
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GestureDetector(
              key: const ValueKey<String>('fling-target'),
              behavior: HitTestBehavior.opaque,
              onPanEnd: (_) => endCount += 1,
              child: const SizedBox(width: 400, height: 800),
            ),
          ),
        ),
      );
      await t.pump();
      final engine = CockpitGestureEngine(delay: t.pump);
      await engine.perform(
        CockpitGestureAction.fling(
          target: _targetFor(t, 'fling-target'),
          delta: const Offset(0, -220),
          duration: const Duration(milliseconds: 88),
        ),
      );
      await t.pumpAndSettle();
      expect(endCount, 1);
    });
  });
}
